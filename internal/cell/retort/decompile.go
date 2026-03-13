package retort

import (
	"context"
	"fmt"
	"strings"
)

// Decompile reads a cell from the Retort database and renders it as turnstile syntax.
// Turnstile is the canonical decompiled form.
func Decompile(ctx context.Context, db *DB, cellID string) (string, error) {
	cell, err := db.GetCell(ctx, cellID)
	if err != nil {
		return "", err
	}

	givens, err := db.GetGivens(ctx, cellID)
	if err != nil {
		return "", err
	}

	yields, err := db.GetYields(ctx, cellID)
	if err != nil {
		return "", err
	}

	oracles, err := db.GetOracles(ctx, cellID)
	if err != nil {
		return "", err
	}

	return renderTurnstile(cell, givens, yields, oracles), nil
}

// DecompileProgram decompiles all cells in a program.
func DecompileProgram(ctx context.Context, db *DB, programID string) (string, error) {
	cells, err := db.GetAllCells(ctx, programID)
	if err != nil {
		return "", err
	}

	var parts []string
	for _, cell := range cells {
		source, err := Decompile(ctx, db, cell.ID)
		if err != nil {
			return "", err
		}
		parts = append(parts, source)
	}

	return strings.Join(parts, "\n\n"), nil
}

func renderTurnstile(cell *CellRow, givens []GivenRow, yields []YieldRow, oracles []OracleRow) string {
	var sb strings.Builder

	// Cell declaration
	turnstile := bodyTypeToTurnstile(cell.BodyType)
	sb.WriteString(fmt.Sprintf("%s %s\n", turnstile, cell.Name))

	// Givens
	for _, g := range givens {
		sb.WriteString("  ")
		if g.IsOptional {
			sb.WriteString("given? ")
		} else {
			sb.WriteString("given ")
		}

		if g.SourceCell != "" {
			sb.WriteString(g.SourceCell)
			sb.WriteString("→")
			sb.WriteString(g.SourceField)
			if g.ParamName != g.SourceField && g.ParamName != "" {
				sb.WriteString(" as ")
				sb.WriteString(g.ParamName)
			}
		} else if g.IsQuotation {
			sb.WriteString(g.ParamName)
		} else {
			sb.WriteString(g.ParamName)
		}

		if g.HasDefault && g.DefaultValue != "" && !g.IsQuotation {
			sb.WriteString(" ≡ ")
			sb.WriteString(g.DefaultValue)
		}

		if g.GuardExpr != "" {
			sb.WriteString(" where ")
			sb.WriteString(g.GuardExpr)
		}

		sb.WriteString("\n")
	}

	// Yields
	if len(yields) > 0 {
		yieldNames := make([]string, len(yields))
		for i, y := range yields {
			yieldNames[i] = y.FieldName
			if y.DefaultValue != "" {
				yieldNames[i] += " ≡ " + y.DefaultValue
			}
		}
		sb.WriteString(fmt.Sprintf("  yield %s\n", strings.Join(yieldNames, ", ")))
	}

	// Body
	switch cell.BodyType {
	case "hard":
		if cell.Body != "" {
			for _, line := range strings.Split(cell.Body, "\n") {
				sb.WriteString(fmt.Sprintf("  ⊢= %s\n", strings.TrimSpace(line)))
			}
		}
	case "soft":
		if cell.Body != "" {
			lines := strings.Split(cell.Body, "\n")
			sb.WriteString(fmt.Sprintf("  ∴ %s\n", lines[0]))
			for _, line := range lines[1:] {
				sb.WriteString(fmt.Sprintf("    %s\n", line))
			}
		}
	}

	// Oracles
	for _, o := range oracles {
		sb.WriteString(fmt.Sprintf("  ⊨ %s\n", o.Assertion))
	}

	return sb.String()
}

func bodyTypeToTurnstile(bt string) string {
	switch bt {
	case "hard":
		return "⊢"
	case "spawner":
		return "⊢⊢"
	case "evolution":
		return "⊢∘"
	default:
		return "⊢"
	}
}
