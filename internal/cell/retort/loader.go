package retort

import (
	"context"
	"crypto/sha256"
	"fmt"
	"os"
	"path/filepath"
	"strings"

	"github.com/ericfode/cell/internal/cell/parser"
)

// LoadFile parses a .cell file and inserts it into the Retort database.
// Auto-detects syntax (turnstile vs molecule).
func LoadFile(ctx context.Context, db *DB, path string) (string, error) {
	data, err := os.ReadFile(path)
	if err != nil {
		return "", fmt.Errorf("retort: read file: %w", err)
	}

	source := string(data)
	hash := fmt.Sprintf("%x", sha256.Sum256(data))
	name := strings.TrimSuffix(filepath.Base(path), filepath.Ext(path))

	prog, err := Parse(source)
	if err != nil {
		return "", fmt.Errorf("retort: parse %s: %w", path, err)
	}

	prog.Name = name
	prog.SourceFile = path
	prog.SourceHash = hash

	return InsertProgram(ctx, db, prog)
}

// Parse parses a .cell source string into a RetortProgram.
// Auto-detects syntax.
func Parse(source string) (*RetortProgram, error) {
	syntax := DetectSyntax(source)

	switch syntax {
	case "turnstile":
		return ParseTurnstile(source)
	case "molecule":
		return parseMolecule(source)
	default:
		return ParseTurnstile(source)
	}
}

func parseMolecule(source string) (*RetortProgram, error) {
	ast, err := parser.Parse(source)
	if err != nil {
		return nil, fmt.Errorf("molecule parse: %w", err)
	}
	return LowerMolecule(ast)
}

// InsertProgram inserts a parsed program into the Retort database.
func InsertProgram(ctx context.Context, db *DB, prog *RetortProgram) (string, error) {
	programID, err := db.InsertProgram(ctx, prog)
	if err != nil {
		return "", err
	}

	for _, cell := range prog.Cells {
		cellID, err := db.InsertCell(ctx, programID, &cell)
		if err != nil {
			return "", err
		}

		for _, g := range cell.Givens {
			if err := db.InsertGiven(ctx, cellID, &g); err != nil {
				return "", fmt.Errorf("insert given %s for %s: %w", g.Name, cell.Name, err)
			}
		}

		for _, y := range cell.Yields {
			if err := db.InsertYield(ctx, cellID, &y); err != nil {
				return "", fmt.Errorf("insert yield %s for %s: %w", y.Name, cell.Name, err)
			}
		}

		for _, o := range cell.Oracles {
			oType := classifyOracle(o.Assertion)
			if err := db.InsertOracle(ctx, cellID, &o, oType); err != nil {
				return "", fmt.Errorf("insert oracle for %s: %w", cell.Name, err)
			}
		}

		if cell.Recovery != nil {
			if err := db.InsertRecoveryPolicy(ctx, cellID, cell.Recovery); err != nil {
				return "", fmt.Errorf("insert recovery for %s: %w", cell.Name, err)
			}
		}
	}

	// Resolve givens that have defaults or are self-referencing
	cells, err := db.GetAllCells(ctx, programID)
	if err != nil {
		return programID, nil // non-fatal
	}
	for _, cell := range cells {
		givens, err := db.GetGivens(ctx, cell.ID)
		if err != nil {
			continue
		}
		for _, g := range givens {
			if g.HasDefault || g.IsQuotation {
				db.MarkGivenResolved(ctx, g.ID)
			}
			// Handle yield defaults (data cells: yield X ≡ value)
			if g.SourceCell == "" && g.HasDefault {
				db.MarkGivenResolved(ctx, g.ID)
			}
		}
	}

	// Handle yield defaults (data cells with yield X ≡ value)
	for _, cell := range prog.Cells {
		for _, y := range cell.Yields {
			if y.DefaultValue != nil {
				// This is a data cell — freeze the yield with its default value
				cellRow, err := db.GetCellByName(ctx, programID, cell.Name)
				if err != nil {
					continue
				}
				val := parseStoredValue(*y.DefaultValue)
				db.FreezeYield(ctx, cellRow.ID, y.Name, val)

				// If all yields have defaults, freeze the cell
				allDefaults := true
				for _, y2 := range cell.Yields {
					if y2.DefaultValue == nil {
						allDefaults = false
						break
					}
				}
				if allDefaults {
					db.SetCellState(ctx, cellRow.ID, "frozen")
				}
			}
		}
	}

	db.DoltCommit(ctx, fmt.Sprintf("retort: load program %s", prog.Name))
	return programID, nil
}
