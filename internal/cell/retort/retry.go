package retort

import (
	"context"
	"fmt"
)

// RecoveryDecision represents what to do after an oracle failure.
type RecoveryDecision struct {
	Action  string // "retry", "bottom", "escalate"
	Message string
}

// DecideRecovery determines what to do after oracle failure for a cell.
func DecideRecovery(cell *CellRow, oracleResults []OracleResult) RecoveryDecision {
	if cell.RetryCount < cell.MaxRetries {
		failures := ""
		for _, r := range oracleResults {
			if !r.Pass {
				if failures != "" {
					failures += "; "
				}
				failures += fmt.Sprintf("%s (%s)", r.Assertion, r.Reason)
			}
		}
		return RecoveryDecision{
			Action:  "retry",
			Message: fmt.Sprintf("attempt %d/%d, failures: %s", cell.RetryCount+1, cell.MaxRetries, failures),
		}
	}

	return RecoveryDecision{
		Action:  "bottom",
		Message: fmt.Sprintf("exhausted after %d retries", cell.MaxRetries),
	}
}

// ApplyRecovery applies the recovery decision to the database.
func ApplyRecovery(ctx context.Context, db *DB, cell *CellRow, decision RecoveryDecision) error {
	switch decision.Action {
	case "retry":
		// Increment retry count, reset to declared so it can be picked up again
		if err := db.IncrementRetry(ctx, cell.ID); err != nil {
			return err
		}
		return db.SetCellState(ctx, cell.ID, "declared")

	case "bottom":
		// Mark cell as bottom, bottom all its yields
		if err := db.SetCellState(ctx, cell.ID, "bottom"); err != nil {
			return err
		}
		yields, err := db.GetYields(ctx, cell.ID)
		if err != nil {
			return err
		}
		for _, y := range yields {
			if err := db.SetYieldBottom(ctx, cell.ID, y.FieldName); err != nil {
				return err
			}
		}
		return nil

	case "escalate":
		// For v0, escalate falls back to bottom
		return ApplyRecovery(ctx, db, cell, RecoveryDecision{Action: "bottom", Message: decision.Message})

	default:
		return fmt.Errorf("unknown recovery action: %s", decision.Action)
	}
}
