package retort

import (
	"fmt"
	"strings"
)

// FormulaStep represents a single step in a Gas Town formula.
type FormulaStep struct {
	ID          string
	Title       string
	Description string
	Acceptance  string
	Needs       []string
	YieldFields []string
}

// SlingFormula converts a RetortProgram into a Gas Town formula TOML string.
// Only soft cells become formula steps; hard cells are evaluated inline
// (already frozen by sling time).
func SlingFormula(prog *RetortProgram, programName string) string {
	// Build set of soft cell names
	softCells := make(map[string]bool)
	for _, cell := range prog.Cells {
		if cell.BodyType == BodySoft {
			softCells[cell.Name] = true
		}
	}

	var steps []FormulaStep
	for _, cell := range prog.Cells {
		if cell.BodyType != BodySoft {
			continue
		}

		step := FormulaStep{
			ID:    sanitizeTOMLKey(cell.Name),
			Title: cell.Name,
		}

		// Description = prompt body
		step.Description = cell.Body

		// Yield field names
		for _, y := range cell.Yields {
			step.YieldFields = append(step.YieldFields, y.Name)
		}

		// Acceptance from oracles or yield names
		if len(cell.Oracles) > 0 {
			var assertions []string
			for _, o := range cell.Oracles {
				assertions = append(assertions, o.Assertion)
			}
			step.Acceptance = strings.Join(assertions, "; ")
		} else {
			step.Acceptance = "Yield fields populated: " + strings.Join(step.YieldFields, ", ")
		}

		// Needs = upstream soft cell names from givens
		seen := make(map[string]bool)
		for _, g := range cell.Givens {
			upstream := g.SourceCell
			if upstream == "" {
				upstream = g.Name
			}
			if softCells[upstream] && !seen[upstream] {
				step.Needs = append(step.Needs, sanitizeTOMLKey(upstream))
				seen[upstream] = true
			}
		}

		steps = append(steps, step)
	}

	return renderFormulaTOML(programName, steps)
}

// sanitizeTOMLKey replaces characters not valid in TOML bare keys.
func sanitizeTOMLKey(name string) string {
	return strings.Map(func(r rune) rune {
		if (r >= 'a' && r <= 'z') || (r >= 'A' && r <= 'Z') ||
			(r >= '0' && r <= '9') || r == '-' || r == '_' {
			return r
		}
		return '-'
	}, name)
}

func renderFormulaTOML(programName string, steps []FormulaStep) string {
	var b strings.Builder

	b.WriteString(fmt.Sprintf("description = %s\n", tomlQuoteString("Cell program dispatch: "+programName)))
	b.WriteString(fmt.Sprintf("formula = %s\n", tomlQuoteString("cell-dispatch-"+programName)))
	b.WriteString("type = \"workflow\"\n")
	b.WriteString("version = 1\n")

	for _, step := range steps {
		b.WriteString("\n[[steps]]\n")
		b.WriteString(fmt.Sprintf("id = %s\n", tomlQuoteString(step.ID)))
		b.WriteString(fmt.Sprintf("title = %s\n", tomlQuoteString(step.Title)))
		if strings.Contains(step.Description, "\n") {
			b.WriteString(fmt.Sprintf("description = %s\n", tomlMultilineString(step.Description)))
		} else {
			b.WriteString(fmt.Sprintf("description = %s\n", tomlQuoteString(step.Description)))
		}
		b.WriteString(fmt.Sprintf("acceptance = %s\n", tomlQuoteString(step.Acceptance)))
		if len(step.Needs) > 0 {
			b.WriteString(fmt.Sprintf("needs = [%s]\n", tomlArray(step.Needs)))
		}
		if len(step.YieldFields) > 0 {
			b.WriteString(fmt.Sprintf("yield_fields = [%s]\n", tomlArray(step.YieldFields)))
		}
	}

	b.WriteString("\n[vars]\n")
	b.WriteString("[vars.program]\n")
	b.WriteString("description = \"The Cell program being dispatched\"\n")
	b.WriteString("required = true\n")

	return b.String()
}

// tomlQuoteString produces a TOML basic string with proper escaping.
func tomlQuoteString(s string) string {
	s = strings.ReplaceAll(s, `\`, `\\`)
	s = strings.ReplaceAll(s, `"`, `\"`)
	s = strings.ReplaceAll(s, "\n", `\n`)
	s = strings.ReplaceAll(s, "\r", `\r`)
	s = strings.ReplaceAll(s, "\t", `\t`)
	return `"` + s + `"`
}

// tomlMultilineString produces a TOML multi-line basic string.
func tomlMultilineString(s string) string {
	s = strings.ReplaceAll(s, `\`, `\\`)
	s = strings.ReplaceAll(s, `"""`, `\"\"\"`)
	return "\"\"\"\n" + s + "\n\"\"\""
}

// tomlArray renders a TOML array of strings.
func tomlArray(items []string) string {
	quoted := make([]string, len(items))
	for i, item := range items {
		quoted[i] = tomlQuoteString(item)
	}
	return strings.Join(quoted, ", ")
}
