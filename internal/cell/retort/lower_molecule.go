package retort

import (
	"strings"

	"github.com/ericfode/cell/internal/cell/parser"
)

// LowerMolecule converts a parsed Syntax A (markdown-recipe) AST into Retort IR.
// This handles the existing Go parser's output.
func LowerMolecule(prog *parser.Program) (*RetortProgram, error) {
	rp := &RetortProgram{}

	for _, mol := range prog.Molecules {
		for _, cell := range mol.Cells {
			rc := lowerCell(cell, mol.Name)
			rp.Cells = append(rp.Cells, rc)
		}
	}

	return rp, nil
}

func lowerCell(cell *parser.Cell, molName string) RetortCell {
	rc := RetortCell{
		Name:     cell.Name,
		BodyType: lowerCellType(cell),
	}

	// Refs → Givens
	for _, ref := range cell.Refs {
		g := RetortGiven{
			Name: ref.Name,
		}
		if ref.Field != "" {
			g.SourceCell = ref.Name
			g.SourceField = ref.Field
			g.Name = ref.Field
		}
		rc.Givens = append(rc.Givens, g)
	}

	// Prompts → Body (for soft cells)
	if rc.BodyType == BodySoft {
		var lines []string
		for _, ps := range cell.Prompts {
			lines = append(lines, ps.Lines...)
		}
		rc.Body = strings.Join(lines, "\n")
	}

	// Script body
	if cell.ScriptBody != "" {
		rc.BodyType = BodyScript
		rc.Body = cell.ScriptBody
	}

	// Yields from format spec
	if len(cell.Prompts) > 0 {
		for _, ps := range cell.Prompts {
			if ps.Format != nil {
				for _, f := range ps.Format.Fields {
					rc.Yields = append(rc.Yields, RetortYield{Name: f.Name})
				}
			}
		}
	}

	// If no yields were found from format, create a default "output" yield
	if len(rc.Yields) == 0 {
		rc.Yields = append(rc.Yields, RetortYield{Name: "output"})
	}

	// Oracle block → Oracles
	if cell.Oracle != nil {
		for i, stmt := range cell.Oracle.Statements {
			rc.Oracles = append(rc.Oracles, RetortOracle{
				Assertion: lowerOracleStmt(stmt),
				Ordinal:   i,
			})
		}
	}

	return rc
}

func lowerCellType(cell *parser.Cell) BodyType {
	switch cell.Type.Name {
	case "llm":
		return BodySoft
	case "script":
		return BodyScript
	case "oracle":
		return BodyHard // oracle cells evaluate deterministically
	case "decision":
		return BodySoft
	case "meta":
		return BodyPassthrough
	default:
		return BodySoft
	}
}

func lowerOracleStmt(stmt *parser.OracleStmt) string {
	switch stmt.Kind {
	case "assert":
		return stmt.Expr
	case "json_parse":
		return "output is valid JSON"
	case "keys_present":
		return "keys present: " + strings.Join(stmt.Args, ", ")
	case "reject":
		return "reject if " + stmt.Expr
	case "accept":
		return "accept if " + stmt.Expr
	default:
		if stmt.Expr != "" {
			return stmt.Expr
		}
		return stmt.Kind
	}
}
