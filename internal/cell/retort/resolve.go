package retort

import (
	"fmt"
	"regexp"
	"strings"
)

var (
	// «name» template references (used in ∴ soft cell prompts)
	guilRef = regexp.MustCompile(`«([^»]+)»`)
	// {{name}} template references (used in markdown-recipe syntax)
	braceRef = regexp.MustCompile(`\{\{([^}]+)\}\}`)
)

// Interpolate replaces template references in text with binding values.
// Supports both «name» (turnstile) and {{name}} (molecule) syntax.
func Interpolate(text string, bindings map[string]interface{}) string {
	result := guilRef.ReplaceAllStringFunc(text, func(match string) string {
		ref := match[len("«") : len(match)-len("»")]
		return resolveRef(ref, bindings)
	})
	result = braceRef.ReplaceAllStringFunc(result, func(match string) string {
		ref := match[2 : len(match)-2]
		return resolveRef(ref, bindings)
	})
	return result
}

func resolveRef(ref string, bindings map[string]interface{}) string {
	// Direct lookup
	if val, ok := bindings[ref]; ok {
		return formatValue(val)
	}

	// cell→field lookup
	if strings.Contains(ref, "→") {
		if val, ok := bindings[ref]; ok {
			return formatValue(val)
		}
	}

	// Try matching on just the field part of cell→field bindings
	for k, v := range bindings {
		if strings.HasSuffix(k, "→"+ref) || k == ref {
			return formatValue(v)
		}
	}

	// Unresolved — return original
	return "«" + ref + "»"
}

func formatValue(v interface{}) string {
	if v == nil {
		return "⊥"
	}
	return fmt.Sprintf("%v", v)
}
