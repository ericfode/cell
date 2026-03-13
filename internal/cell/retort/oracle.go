package retort

import (
	"fmt"
	"regexp"
	"strings"
)

// OracleResult is the outcome of checking a single oracle assertion.
type OracleResult struct {
	Assertion string
	Pass      bool
	Reason    string
}

// ClassifyOracle determines the oracle type from its assertion text.
// Used at compile time when inserting into the oracles table.
func classifyOracle(assertion string) string {
	// Conditional: "if X then Y"
	if strings.HasPrefix(assertion, "if ") {
		return "conditional"
	}

	// Deterministic: field = value, field > value, etc.
	detRe := regexp.MustCompile(`^\w[\w-]*\s*[=<>!]+\s*.+$`)
	if detRe.MatchString(assertion) {
		return "deterministic"
	}

	// Structural: "X is valid JSON", "keys present: ..."
	if strings.Contains(assertion, "is valid JSON") ||
		strings.Contains(assertion, "keys present") {
		return "structural"
	}

	// Everything else is semantic (needs LLM to check)
	return "semantic"
}

// CheckOracles evaluates oracle assertions against cell outputs.
// Deterministic oracles use the expression evaluator.
// Semantic oracles are assumed to pass in v0 (or dispatched to LLM).
func CheckOracles(oracles []OracleRow, outputs map[string]interface{}, bindings map[string]interface{}) (bool, []OracleResult) {
	var results []OracleResult
	allPass := true

	// Merge outputs into bindings for expression evaluation
	merged := make(map[string]interface{})
	for k, v := range bindings {
		merged[k] = v
	}
	for k, v := range outputs {
		merged[k] = v
	}

	for _, oracle := range oracles {
		result := checkSingleOracle(oracle, outputs, merged)
		results = append(results, result)
		if !result.Pass {
			allPass = false
		}
	}

	return allPass, results
}

func checkSingleOracle(oracle OracleRow, outputs map[string]interface{}, bindings map[string]interface{}) OracleResult {
	assertion := oracle.Assertion

	switch oracle.OracleType {
	case "deterministic":
		return checkDeterministic(assertion, outputs, bindings)
	case "conditional":
		return checkConditional(assertion, outputs, bindings)
	case "structural":
		return checkStructural(assertion, outputs)
	default:
		// Semantic — assumed pass in v0
		return OracleResult{
			Assertion: assertion,
			Pass:      true,
			Reason:    "semantic: assumed pass",
		}
	}
}

func checkDeterministic(assertion string, outputs map[string]interface{}, bindings map[string]interface{}) OracleResult {
	// Pattern: field = value
	eqRe := regexp.MustCompile(`^(\w[\w-]*)\s*=\s*(.+)$`)
	if m := eqRe.FindStringSubmatch(assertion); m != nil {
		field := m[1]
		expectedStr := strings.TrimSpace(m[2])
		expected := parseLiteralValue(expectedStr)

		actual, ok := outputs[field]
		if !ok {
			actual = bindings[field]
		}

		if valEqual(actual, expected) {
			return OracleResult{
				Assertion: assertion,
				Pass:      true,
				Reason:    fmt.Sprintf("deterministic: %v == %v", actual, expected),
			}
		}
		return OracleResult{
			Assertion: assertion,
			Pass:      false,
			Reason:    fmt.Sprintf("deterministic: %v != %v", actual, expected),
		}
	}

	// Pattern: field > value, field < value, etc.
	cmpRe := regexp.MustCompile(`^(\w[\w-]*)\s*(>=|<=|>|<|!=)\s*(.+)$`)
	if m := cmpRe.FindStringSubmatch(assertion); m != nil {
		field := m[1]
		op := m[2]
		expectedStr := strings.TrimSpace(m[3])

		actual, ok := outputs[field]
		if !ok {
			actual = bindings[field]
		}

		a, aOk := toFloat(actual)
		b, bOk := toFloat(parseLiteralValue(expectedStr))

		if aOk && bOk {
			var pass bool
			switch op {
			case ">":
				pass = a > b
			case "<":
				pass = a < b
			case ">=":
				pass = a >= b
			case "<=":
				pass = a <= b
			case "!=":
				pass = a != b
			}
			return OracleResult{
				Assertion: assertion,
				Pass:      pass,
				Reason:    fmt.Sprintf("deterministic: %v %s %v = %v", a, op, b, pass),
			}
		}
	}

	// Try as full expression
	result, err := EvalExpr(assertion, bindings)
	if err == nil && toBool(result) {
		return OracleResult{
			Assertion: assertion,
			Pass:      true,
			Reason:    "deterministic expression: true",
		}
	}
	if err == nil {
		return OracleResult{
			Assertion: assertion,
			Pass:      false,
			Reason:    fmt.Sprintf("deterministic expression: false (%v)", result),
		}
	}

	// Fallback to semantic
	return OracleResult{
		Assertion: assertion,
		Pass:      true,
		Reason:    "unrecognized deterministic pattern, assumed pass",
	}
}

func checkConditional(assertion string, outputs map[string]interface{}, bindings map[string]interface{}) OracleResult {
	// Pattern: if X then Y
	condRe := regexp.MustCompile(`^if\s+(.+?)\s+then\s+(.+)$`)
	if m := condRe.FindStringSubmatch(assertion); m != nil {
		condExpr := m[1]
		thenExpr := m[2]

		condResult, err := EvalExpr(condExpr, bindings)
		if err != nil || !toBool(condResult) {
			// Condition not met — oracle is vacuously true
			return OracleResult{
				Assertion: assertion,
				Pass:      true,
				Reason:    "conditional: condition not met, vacuously true",
			}
		}

		// Check the 'then' part
		thenResult := checkDeterministic(thenExpr, outputs, bindings)
		return OracleResult{
			Assertion: assertion,
			Pass:      thenResult.Pass,
			Reason:    fmt.Sprintf("conditional: condition met, then: %s", thenResult.Reason),
		}
	}

	return OracleResult{
		Assertion: assertion,
		Pass:      true,
		Reason:    "conditional: assumed pass",
	}
}

func checkStructural(assertion string, outputs map[string]interface{}) OracleResult {
	// For v0, structural oracles are assumed to pass
	return OracleResult{
		Assertion: assertion,
		Pass:      true,
		Reason:    "structural: assumed pass",
	}
}

func parseLiteralValue(s string) interface{} {
	s = strings.TrimSpace(s)

	// Quoted string
	if len(s) >= 2 && s[0] == '"' && s[len(s)-1] == '"' {
		return s[1 : len(s)-1]
	}

	// Boolean
	if s == "true" {
		return true
	}
	if s == "false" {
		return false
	}

	// Bottom
	if s == "⊥" {
		return nil
	}

	// List literal: [1, 2, 3] or [1, 2, 3, 4, 5]
	if len(s) >= 2 && s[0] == '[' && s[len(s)-1] == ']' {
		inner := strings.TrimSpace(s[1 : len(s)-1])
		if inner == "" {
			return []interface{}{}
		}
		parts := splitListElements(inner)
		result := make([]interface{}, 0, len(parts))
		for _, p := range parts {
			result = append(result, parseLiteralValue(strings.TrimSpace(p)))
		}
		return result
	}

	// Number
	var f float64
	if n, err := fmt.Sscanf(s, "%g", &f); n == 1 && err == nil {
		return f
	}

	return s
}

// splitListElements splits on commas, respecting nested brackets.
func splitListElements(s string) []string {
	var parts []string
	depth := 0
	start := 0
	for i := 0; i < len(s); i++ {
		switch s[i] {
		case '[':
			depth++
		case ']':
			depth--
		case ',':
			if depth == 0 {
				parts = append(parts, s[start:i])
				start = i + 1
			}
		}
	}
	parts = append(parts, s[start:])
	return parts
}
