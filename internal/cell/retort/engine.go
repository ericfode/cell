package retort

import (
	"context"
	"fmt"
	"time"
)

// Engine orchestrates Cell program evaluation.
type Engine struct {
	DB       *DB
	MaxSteps int
	Verbose  bool
	Log      func(string) // optional logger
}

// EvalResult summarizes an evaluation run.
type EvalResult struct {
	Steps    int
	Frozen   int
	Bottom   int
	Pending  int
	Status   string // "quiescent", "blocked", "halted"
	Error    error
}

// Eval runs the full evaluation loop for a program until quiescence.
func (e *Engine) Eval(ctx context.Context, programID string) EvalResult {
	maxSteps := e.MaxSteps
	if maxSteps <= 0 {
		maxSteps = 100
	}

	if err := e.DB.UpdateProgramStatus(ctx, programID, "running"); err != nil {
		return EvalResult{Error: err}
	}

	step := 0
	for step < maxSteps {
		result, done := e.evalOne(ctx, programID, step)
		if result.Error != nil {
			e.DB.UpdateProgramStatus(ctx, programID, "error")
			return result
		}
		if done {
			break
		}
		step = result.Steps
	}

	// Final status
	return e.summarize(ctx, programID, step, step >= maxSteps)
}

// EvalOne evaluates a single ready cell.
func (e *Engine) EvalOne(ctx context.Context, programID string) EvalResult {
	result, _ := e.evalOne(ctx, programID, 0)
	return result
}

func (e *Engine) evalOne(ctx context.Context, programID string, step int) (EvalResult, bool) {
	// 1. Find ready cells
	ready, err := e.DB.FindReadyCells(ctx, programID)
	if err != nil {
		return EvalResult{Error: err}, true
	}

	// 2. Handle guard-skipped cells before checking emptiness
	if len(ready) == 0 {
		skipped, err := e.skipGuardFailed(ctx, programID)
		if err != nil {
			return EvalResult{Error: err}, true
		}
		if skipped > 0 {
			// Re-check after skipping
			ready, err = e.DB.FindReadyCells(ctx, programID)
			if err != nil {
				return EvalResult{Error: err}, true
			}
		}
	}

	if len(ready) == 0 {
		return e.summarize(ctx, programID, step, false), true
	}

	// 3. Pick first ready cell
	target := ready[0]
	e.log("step %d: evaluating %s (%s)", step, target.Name, target.BodyType)

	// 4. Resolve givens
	bindings, _, err := e.DB.ResolveGivens(ctx, programID, target.ID)
	if err != nil {
		return EvalResult{Error: fmt.Errorf("resolve givens for %s: %w", target.Name, err)}, true
	}

	// 5. Check guards
	guardsPass, err := e.DB.CheckGuards(ctx, programID, target.ID, bindings)
	if err != nil {
		return EvalResult{Error: fmt.Errorf("check guards for %s: %w", target.Name, err)}, true
	}
	if !guardsPass {
		e.log("step %d: skip %s (guard false → ⊥)", step, target.Name)
		if err := e.bottomCell(ctx, &target, programID, step); err != nil {
			return EvalResult{Error: err}, true
		}
		return EvalResult{Steps: step + 1}, false
	}

	// 6. Set computing state
	if err := e.DB.SetCellState(ctx, target.ID, "computing"); err != nil {
		return EvalResult{Error: err}, true
	}

	// 7. Dispatch
	yields, err := e.DB.GetYields(ctx, target.ID)
	if err != nil {
		return EvalResult{Error: err}, true
	}

	start := time.Now()
	result := Dispatch(ctx, &target, yields, bindings)
	duration := time.Since(start)

	if result.Err != nil {
		e.log("step %d: dispatch error for %s: %v", step, target.Name, result.Err)
		// Treat dispatch error as oracle failure for recovery
		e.DB.InsertTrace(ctx, programID, step, target.ID, "dispatch_error",
			result.Err.Error(), int(duration.Milliseconds()))
		decision := DecideRecovery(&target, nil)
		if err := ApplyRecovery(ctx, e.DB, &target, decision); err != nil {
			return EvalResult{Error: err}, true
		}
		e.DB.DoltCommit(ctx, fmt.Sprintf("eval step %d: dispatch error %s", step, target.Name))
		return EvalResult{Steps: step + 1}, false
	}

	// 8. Set tentative values
	for _, y := range yields {
		if val, ok := result.Outputs[y.FieldName]; ok {
			valStr := fmt.Sprintf("%v", val)
			e.DB.SetTentativeValue(ctx, target.ID, y.FieldName, valStr)
		}
	}
	if err := e.DB.SetCellState(ctx, target.ID, "tentative"); err != nil {
		return EvalResult{Error: err}, true
	}

	// 9. Check oracles
	oracles, err := e.DB.GetOracles(ctx, target.ID)
	if err != nil {
		return EvalResult{Error: err}, true
	}

	allPass, oracleResults := CheckOracles(oracles, result.Outputs, bindings)

	// 10. Decide: freeze or retry
	if allPass {
		// Freeze yields
		for _, y := range yields {
			if val, ok := result.Outputs[y.FieldName]; ok {
				if err := e.DB.FreezeYield(ctx, target.ID, y.FieldName, val); err != nil {
					return EvalResult{Error: err}, true
				}
			}
		}
		if err := e.DB.SetCellState(ctx, target.ID, "frozen"); err != nil {
			return EvalResult{Error: err}, true
		}

		yieldsStr := formatOutputs(result.Outputs)
		e.log("step %d: freeze %s → %s", step, target.Name, yieldsStr)

		e.DB.InsertTrace(ctx, programID, step, target.ID, "freeze",
			yieldsStr, int(duration.Milliseconds()))
		e.DB.DoltCommit(ctx, fmt.Sprintf("eval step %d: freeze %s", step, target.Name))
	} else {
		// Oracle failed — recovery
		decision := DecideRecovery(&target, oracleResults)
		e.log("step %d: %s %s (%s)", step, decision.Action, target.Name, decision.Message)

		e.DB.InsertTrace(ctx, programID, step, target.ID, decision.Action,
			decision.Message, int(duration.Milliseconds()))

		if err := ApplyRecovery(ctx, e.DB, &target, decision); err != nil {
			return EvalResult{Error: err}, true
		}
		e.DB.DoltCommit(ctx, fmt.Sprintf("eval step %d: %s %s", step, decision.Action, target.Name))
	}

	return EvalResult{Steps: step + 1}, false
}

// skipGuardFailed checks all declared cells with all deps satisfied
// and skips those whose guards fail.
func (e *Engine) skipGuardFailed(ctx context.Context, programID string) (int, error) {
	cells, err := e.DB.GetAllCells(ctx, programID)
	if err != nil {
		return 0, err
	}

	skipped := 0
	for _, cell := range cells {
		if cell.State != "declared" {
			continue
		}

		// Check if all source deps are resolved (frozen or bottom)
		givens, err := e.DB.GetGivens(ctx, cell.ID)
		if err != nil {
			return 0, err
		}

		allDepsResolved := true
		for _, g := range givens {
			if g.SourceCell == "" {
				continue
			}
			srcCell, err := e.DB.GetCellByName(ctx, programID, g.SourceCell)
			if err != nil {
				allDepsResolved = false
				break
			}
			if srcCell.State != "frozen" && srcCell.State != "bottom" {
				allDepsResolved = false
				break
			}
		}

		if !allDepsResolved {
			continue
		}

		// Resolve bindings and check guards
		bindings, _, err := e.DB.ResolveGivens(ctx, programID, cell.ID)
		if err != nil {
			continue
		}

		guardsPass, _ := e.DB.CheckGuards(ctx, programID, cell.ID, bindings)
		if !guardsPass {
			e.log("skip %s (guard false → ⊥)", cell.Name)
			e.bottomCell(ctx, &cell, programID, -1)
			skipped++
		}
	}

	return skipped, nil
}

func (e *Engine) bottomCell(ctx context.Context, cell *CellRow, programID string, step int) error {
	if err := e.DB.SetCellState(ctx, cell.ID, "bottom"); err != nil {
		return err
	}
	yields, err := e.DB.GetYields(ctx, cell.ID)
	if err != nil {
		return err
	}
	for _, y := range yields {
		if err := e.DB.SetYieldBottom(ctx, cell.ID, y.FieldName); err != nil {
			return err
		}
	}
	e.DB.InsertTrace(ctx, programID, step, cell.ID, "bottom", "guard false → ⊥", 0)
	e.DB.DoltCommit(ctx, fmt.Sprintf("eval: bottom %s (guard)", cell.Name))
	return nil
}

func (e *Engine) summarize(ctx context.Context, programID string, step int, halted bool) EvalResult {
	cells, err := e.DB.GetAllCells(ctx, programID)
	if err != nil {
		return EvalResult{Error: err}
	}

	frozen, bottom, pending := 0, 0, 0
	for _, c := range cells {
		switch c.State {
		case "frozen":
			frozen++
		case "bottom":
			bottom++
		default:
			pending++
		}
	}

	status := "quiescent"
	if halted {
		status = "halted"
	} else if pending > 0 {
		status = "blocked"
	}

	if status == "quiescent" {
		e.DB.UpdateProgramStatus(ctx, programID, "quiescent")
	}

	return EvalResult{
		Steps:   step,
		Frozen:  frozen,
		Bottom:  bottom,
		Pending: pending,
		Status:  status,
	}
}

func (e *Engine) log(format string, args ...interface{}) {
	if e.Log != nil {
		e.Log(fmt.Sprintf(format, args...))
	}
}

func formatOutputs(outputs map[string]interface{}) string {
	parts := make([]string, 0, len(outputs))
	for k, v := range outputs {
		parts = append(parts, fmt.Sprintf("%s=%v", k, v))
	}
	return fmt.Sprintf("{%s}", joinStrings(parts, ", "))
}

func joinStrings(ss []string, sep string) string {
	if len(ss) == 0 {
		return ""
	}
	result := ss[0]
	for _, s := range ss[1:] {
		result += sep + s
	}
	return result
}
