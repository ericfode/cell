package retort

import (
	"context"
	"fmt"
	"time"
)

// Engine orchestrates Cell program evaluation.
type Engine struct {
	DB       *DB
	Mode     DispatchMode
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

	// 2. Propagate bottom: cells with required bottom deps become bottom
	bottomPropagated, err := e.propagateBottom(ctx, programID)
	if err != nil {
		return EvalResult{Error: err}, true
	}
	if bottomPropagated > 0 {
		ready, err = e.DB.FindReadyCells(ctx, programID)
		if err != nil {
			return EvalResult{Error: err}, true
		}
	}

	// 3. Handle guard-skipped cells before checking emptiness
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

	// Include yield defaults (data yields like `yield name ≡ "value"`) in bindings
	for _, y := range yields {
		if y.DefaultValue != "" {
			bindings[y.FieldName] = parseStoredValue(y.DefaultValue)
		}
	}

	start := time.Now()
	result := Dispatch(ctx, &target, yields, bindings, e.Mode)
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

// propagateBottom marks declared cells as bottom when any required (non-optional)
// dependency is bottom. Returns the number of cells bottomed.
func (e *Engine) propagateBottom(ctx context.Context, programID string) (int, error) {
	cells, err := e.DB.GetAllCells(ctx, programID)
	if err != nil {
		return 0, err
	}

	bottomed := 0
	for _, cell := range cells {
		if cell.State != "declared" {
			continue
		}

		givens, err := e.DB.GetGivens(ctx, cell.ID)
		if err != nil {
			return bottomed, err
		}

		hasBottomDep := false
		for _, g := range givens {
			if g.SourceCell == "" || g.IsOptional {
				continue
			}
			srcCell, err := e.DB.GetCellByName(ctx, programID, g.SourceCell)
			if err != nil {
				continue
			}
			if srcCell.State == "bottom" {
				hasBottomDep = true
				break
			}
		}

		if hasBottomDep {
			e.log("bottom %s (required dependency is ⊥)", cell.Name)
			if err := e.bottomCell(ctx, &cell, programID, -1); err != nil {
				return bottomed, err
			}
			bottomed++
		}
	}

	return bottomed, nil
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

// BeadWork represents a soft cell that needs to be slung to a polecat.
type BeadWork struct {
	CellName   string
	CellID     string
	BeadID     string // bead ID from bd create
	Prompt     string // the fully interpolated prompt
	YieldNames []string
}

// Sling finds all ready soft cells, creates beads for them, and returns
// the list of work that needs to be dispatched via polecats.
// Hard cells are evaluated inline. Only soft cells become beads.
func (e *Engine) Sling(ctx context.Context, programID string) ([]BeadWork, EvalResult) {
	// First evaluate any ready hard cells
	for {
		// Propagate bottom from upstream
		e.propagateBottom(ctx, programID)

		ready, err := e.DB.FindReadyCells(ctx, programID)
		if err != nil {
			return nil, EvalResult{Error: err}
		}

		// Handle guard-skipped cells
		if len(ready) == 0 {
			skipped, err := e.skipGuardFailed(ctx, programID)
			if err != nil {
				return nil, EvalResult{Error: err}
			}
			if skipped > 0 {
				ready, _ = e.DB.FindReadyCells(ctx, programID)
			}
		}

		if len(ready) == 0 {
			break
		}

		// Find first hard cell to eval inline
		hardIdx := -1
		for i, c := range ready {
			if c.BodyType == "hard" || c.BodyType == "passthrough" {
				hardIdx = i
				break
			}
		}
		if hardIdx < 0 {
			break // only soft cells left
		}

		// Eval the hard cell inline
		target := ready[hardIdx]
		e.log("sling: eval hard cell %s inline", target.Name)

		bindings, _, err := e.DB.ResolveGivens(ctx, programID, target.ID)
		if err != nil {
			return nil, EvalResult{Error: fmt.Errorf("resolve givens for %s: %w", target.Name, err)}
		}
		guardsPass, _ := e.DB.CheckGuards(ctx, programID, target.ID, bindings)
		if !guardsPass {
			e.bottomCell(ctx, &target, programID, -1)
			continue
		}

		e.DB.SetCellState(ctx, target.ID, "computing")
		yields, _ := e.DB.GetYields(ctx, target.ID)
		// Include yield defaults in bindings for hard cell eval
		for _, y := range yields {
			if y.DefaultValue != "" {
				bindings[y.FieldName] = parseStoredValue(y.DefaultValue)
			}
		}
		result := Dispatch(ctx, &target, yields, bindings, ModeLive) // hard cells eval inline regardless
		if result.Err != nil {
			e.log("sling: dispatch error for %s: %v", target.Name, result.Err)
			decision := DecideRecovery(&target, nil)
			if err := ApplyRecovery(ctx, e.DB, &target, decision); err != nil {
				return nil, EvalResult{Error: err}
			}
			e.DB.DoltCommit(ctx, fmt.Sprintf("sling: dispatch error %s", target.Name))
			continue
		}

		// Freeze
		for _, y := range yields {
			if val, ok := result.Outputs[y.FieldName]; ok {
				e.DB.FreezeYield(ctx, target.ID, y.FieldName, val)
			}
		}
		e.DB.SetCellState(ctx, target.ID, "frozen")
		e.DB.DoltCommit(ctx, fmt.Sprintf("sling: freeze hard cell %s", target.Name))
	}

	// Now find ready soft cells and create beads
	ready, err := e.DB.FindReadyCells(ctx, programID)
	if err != nil {
		return nil, EvalResult{Error: err}
	}

	var work []BeadWork
	for _, cell := range ready {
		if cell.BodyType != "soft" {
			continue
		}

		bindings, _, err := e.DB.ResolveGivens(ctx, programID, cell.ID)
		if err != nil {
			e.log("sling: skip %s (resolve error: %v)", cell.Name, err)
			continue
		}

		yields, _ := e.DB.GetYields(ctx, cell.ID)

		// Include yield defaults (data yields like `yield name ≡ "Rosa"`) in bindings
		// so that «name», «age», «occupation» etc. resolve during interpolation
		for _, y := range yields {
			if y.DefaultValue != "" {
				bindings[y.FieldName] = parseStoredValue(y.DefaultValue)
			}
		}

		// Build the fully interpolated prompt
		prompt := Interpolate(cell.Body, bindings)
		yieldNames := make([]string, 0, len(yields))
		for _, y := range yields {
			// Skip yields that already have defaults (data yields)
			if y.IsFrozen {
				continue
			}
			yieldNames = append(yieldNames, y.FieldName)
		}

		if len(yieldNames) == 0 {
			continue
		}

		// Set cell to computing
		e.DB.SetCellState(ctx, cell.ID, "computing")

		work = append(work, BeadWork{
			CellName:   cell.Name,
			CellID:     cell.ID,
			Prompt:     prompt,
			YieldNames: yieldNames,
		})
	}

	if len(work) > 0 {
		e.DB.DoltCommit(ctx, fmt.Sprintf("sling: %d soft cells awaiting dispatch", len(work)))
	}

	return work, e.summarize(ctx, programID, 0, false)
}

// Collect reads results for cells in "computing" state whose beads are done.
// resultsJSON maps cell names to their yield outputs.
func (e *Engine) Collect(ctx context.Context, programID string, results map[string]map[string]interface{}) EvalResult {
	cells, err := e.DB.GetAllCells(ctx, programID)
	if err != nil {
		return EvalResult{Error: err}
	}

	step := 0
	for _, cell := range cells {
		if cell.State != "computing" {
			continue
		}

		outputs, ok := results[cell.Name]
		if !ok {
			continue
		}

		yields, _ := e.DB.GetYields(ctx, cell.ID)

		// Set tentative
		for _, y := range yields {
			if val, ok := outputs[y.FieldName]; ok {
				e.DB.SetTentativeValue(ctx, cell.ID, y.FieldName, fmt.Sprintf("%v", val))
			}
		}
		e.DB.SetCellState(ctx, cell.ID, "tentative")

		// Check oracles
		oracles, _ := e.DB.GetOracles(ctx, cell.ID)
		bindings, _, _ := e.DB.ResolveGivens(ctx, programID, cell.ID)
		allPass, oracleResults := CheckOracles(oracles, outputs, bindings)

		if allPass {
			for _, y := range yields {
				if val, ok := outputs[y.FieldName]; ok {
					e.DB.FreezeYield(ctx, cell.ID, y.FieldName, val)
				}
			}
			e.DB.SetCellState(ctx, cell.ID, "frozen")
			e.log("collect: freeze %s", cell.Name)
			e.DB.InsertTrace(ctx, programID, step, cell.ID, "freeze",
				formatOutputs(outputs), 0)
		} else {
			decision := DecideRecovery(&cell, oracleResults)
			e.log("collect: %s %s (%s)", decision.Action, cell.Name, decision.Message)
			ApplyRecovery(ctx, e.DB, &cell, decision)
		}

		e.DB.DoltCommit(ctx, fmt.Sprintf("collect step %d: %s", step, cell.Name))
		step++
	}

	// After collecting, try to sling any newly-ready soft cells or eval hard cells
	// This handles the analyst becoming ready after citizens are frozen
	return e.summarize(ctx, programID, step, false)
}
