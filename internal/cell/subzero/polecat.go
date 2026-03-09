package subzero

import (
	"context"
	"fmt"
)

// PolecatExecutor delegates mol() cells to external agents.
// In standalone Cell, this is not supported — it requires Gas Town infrastructure.
type PolecatExecutor struct {
	Rig        string
	TimeoutMin int
	Depth      int
}

func (p *PolecatExecutor) Execute(ctx context.Context, cell *CellExec) (*CellResult, error) {
	return nil, fmt.Errorf("not supported in standalone mode: mol() cells require Gas Town agent infrastructure")
}
