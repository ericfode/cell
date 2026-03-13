package retort

import (
	"regexp"
	"strconv"
	"strings"
)

// ParseTurnstile parses a .cell file in turnstile syntax (⊢/∴/⊨) into Retort IR.
// This is the Go port of tools/cell-zero/parse.py.
func ParseTurnstile(source string) (*RetortProgram, error) {
	cells := parseTurnstileCells(source)
	prog := &RetortProgram{Cells: cells}
	return prog, nil
}

func parseTurnstileCells(text string) []RetortCell {
	var cells []RetortCell
	var current *RetortCell
	var bodyLines []string
	inBody := false

	cellDeclRe := regexp.MustCompile(`^(⊢⊢|⊢∘|⊢=|⊢)\s+(\S+)`)
	givenRe := regexp.MustCompile(`^\s+(given\??)\s+(.+)`)
	yieldRe := regexp.MustCompile(`^\s+yield\s+(.+)`)

	for _, rawLine := range strings.Split(text, "\n") {
		line := strings.TrimRight(rawLine, " \t\r")
		stripped := strings.TrimLeft(line, " \t")

		// Skip empty lines and comments
		if stripped == "" || strings.HasPrefix(stripped, "--") {
			if inBody && stripped == "" {
				bodyLines = append(bodyLines, "")
			}
			continue
		}

		// Cell declaration
		if m := cellDeclRe.FindStringSubmatch(stripped); m != nil {
			if current != nil && inBody && len(bodyLines) > 0 {
				current.Body = strings.TrimSpace(strings.Join(bodyLines, "\n"))
			}
			inBody = false
			bodyLines = nil

			ts := m[1]
			name := m[2]
			indent := len(line) - len(stripped)

			// ⊢= inside a cell body (indented, not a new cell)
			if indent > 0 && current != nil && ts == "⊢=" {
				exprPart := stripped[len("⊢= "):]
				if current.BodyType == BodyHard && current.Body != "" {
					current.Body = current.Body + "\n" + exprPart
				} else {
					current.Body = exprPart
				}
				current.BodyType = BodyHard
				continue
			}

			bt := bodyTypeFromTurnstile(ts)
			cell := RetortCell{
				Name:     name,
				BodyType: bt,
			}
			cells = append(cells, cell)
			current = &cells[len(cells)-1]
			continue
		}

		if current == nil {
			continue
		}

		// given clause
		if m := givenRe.FindStringSubmatch(line); m != nil {
			if inBody && len(bodyLines) > 0 {
				current.Body = strings.TrimSpace(strings.Join(bodyLines, "\n"))
				inBody = false
				bodyLines = nil
			}
			optional := m[1] == "given?"
			given := parseGivenClause(strings.TrimSpace(m[2]), optional)
			current.Givens = append(current.Givens, given)
			continue
		}

		// yield clause
		if m := yieldRe.FindStringSubmatch(line); m != nil {
			if inBody && len(bodyLines) > 0 {
				current.Body = strings.TrimSpace(strings.Join(bodyLines, "\n"))
				inBody = false
				bodyLines = nil
			}
			yieldText := strings.TrimSpace(m[1])
			yields := parseYieldClause(yieldText)
			current.Yields = append(current.Yields, yields...)
			continue
		}

		// ∴ body
		if strings.HasPrefix(stripped, "∴") {
			if inBody && len(bodyLines) > 0 {
				current.Body = strings.TrimSpace(strings.Join(bodyLines, "\n"))
			}
			bodyText := strings.TrimSpace(stripped[len("∴"):])
			bodyLines = nil
			if bodyText != "" {
				bodyLines = []string{bodyText}
			}
			inBody = true
			current.BodyType = BodySoft
			continue
		}

		// ⊨? recovery (may be multiline — append to existing recovery)
		if strings.HasPrefix(stripped, "⊨?") {
			if inBody && len(bodyLines) > 0 {
				current.Body = strings.TrimSpace(strings.Join(bodyLines, "\n"))
				inBody = false
				bodyLines = nil
			}
			recoveryText := strings.TrimSpace(stripped[len("⊨?"):])
			current.Recovery = parseRecovery(recoveryText)
			continue
		}

		// Continuation lines for recovery (indented, after ⊨? was seen)
		if current.Recovery != nil && len(line) > 0 && (line[0] == ' ' || line[0] == '\t') && !inBody {
			// Append to recovery directive and re-parse
			current.Recovery.RecoveryDirective += "\n" + stripped
			current.Recovery = parseRecovery(current.Recovery.RecoveryDirective)
			continue
		}

		// ⊨ oracle
		if strings.HasPrefix(stripped, "⊨") {
			if inBody && len(bodyLines) > 0 {
				current.Body = strings.TrimSpace(strings.Join(bodyLines, "\n"))
				inBody = false
				bodyLines = nil
			}
			oracleText := strings.TrimSpace(stripped[len("⊨"):])
			current.Oracles = append(current.Oracles, RetortOracle{
				Assertion: oracleText,
				Ordinal:   len(current.Oracles),
			})
			continue
		}

		// ⊢= expression body (indented)
		if strings.HasPrefix(stripped, "⊢=") {
			if inBody && len(bodyLines) > 0 {
				current.Body = strings.TrimSpace(strings.Join(bodyLines, "\n"))
				inBody = false
				bodyLines = nil
			}
			expr := strings.TrimSpace(stripped[len("⊢="):])
			if current.BodyType == BodyHard && current.Body != "" {
				current.Body = current.Body + "\n" + expr
			} else {
				current.Body = expr
			}
			current.BodyType = BodyHard
			continue
		}

		// Continuation of ∴ body
		if inBody {
			bodyLines = append(bodyLines, stripped)
			continue
		}
	}

	// Finalize last cell's body
	if current != nil && inBody && len(bodyLines) > 0 {
		current.Body = strings.TrimSpace(strings.Join(bodyLines, "\n"))
	}

	// Post-process: cells with no body are passthrough
	for i := range cells {
		if cells[i].Body == "" && cells[i].BodyType == "" {
			cells[i].BodyType = BodyPassthrough
		}
	}

	return cells
}

func bodyTypeFromTurnstile(ts string) BodyType {
	switch ts {
	case "⊢=":
		return BodyHard
	case "⊢⊢":
		return BodySpawner
	case "⊢∘":
		return BodyEvolution
	default:
		return "" // will be set by body content or default to passthrough
	}
}

func parseGivenClause(text string, optional bool) RetortGiven {
	g := RetortGiven{IsOptional: optional}

	// Extract guard: "where <expr>"
	guardRe := regexp.MustCompile(`\s+where\s+(.+)$`)
	if m := guardRe.FindStringSubmatch(text); m != nil {
		g.GuardExpr = strings.TrimSpace(m[1])
		text = text[:guardRe.FindStringSubmatchIndex(text)[0]]
	}

	// Check for default: name ≡ value
	defaultRe := regexp.MustCompile(`^(\S+)\s*≡\s*(.+)$`)
	if m := defaultRe.FindStringSubmatch(text); m != nil {
		name := m[1]
		valStr := strings.TrimSpace(m[2])
		defVal := valStr
		g.Default = &defVal
		g.HasDefault = true

		if strings.Contains(name, "→") {
			parts := strings.SplitN(name, "→", 2)
			g.SourceCell = parts[0]
			g.SourceField = parts[1]
			g.Name = parts[1]
		} else {
			g.Name = name
		}
		return g
	}

	// Check for source reference: cell→field
	if strings.Contains(text, "→") {
		parts := strings.SplitN(text, "→", 2)
		g.SourceCell = strings.TrimSpace(parts[0])
		fieldPart := strings.TrimSpace(parts[1])

		// Handle "as alias" syntax
		asRe := regexp.MustCompile(`^(\S+)\s+as\s+(\S+)$`)
		if m := asRe.FindStringSubmatch(fieldPart); m != nil {
			g.SourceField = m[1]
			g.Name = m[2]
		} else {
			g.SourceField = fieldPart
			g.Name = fieldPart
		}
		return g
	}

	// Simple name (possibly §quotation)
	name := strings.TrimSpace(text)
	g.Name = name
	if strings.HasPrefix(name, "§") {
		g.IsQuotation = true
		g.HasDefault = true
		defVal := name
		g.Default = &defVal
	}
	return g
}

func parseYieldClause(text string) []RetortYield {
	var yields []RetortYield

	// Check for default: yield name ≡ value (handle entire text as one yield if ≡ present)
	if idx := strings.Index(text, "≡"); idx > 0 {
		name := strings.TrimSpace(text[:idx])
		name = strings.TrimRight(name, "[]")
		val := strings.TrimSpace(text[idx+len("≡"):])
		yields = append(yields, RetortYield{Name: name, DefaultValue: &val})
		return yields
	}

	// Split on commas only outside brackets
	parts := splitYieldNames(text)
	for _, p := range parts {
		p = strings.TrimSpace(p)
		if p == "" {
			continue
		}
		name := strings.TrimRight(strings.TrimSpace(p), "[]")
		yields = append(yields, RetortYield{Name: name})
	}
	return yields
}

// splitYieldNames splits yield names on commas, but not inside brackets.
func splitYieldNames(text string) []string {
	var parts []string
	depth := 0
	start := 0
	for i, ch := range text {
		switch ch {
		case '[':
			depth++
		case ']':
			depth--
		case ',':
			if depth == 0 {
				parts = append(parts, text[start:i])
				start = i + 1
			}
		}
	}
	parts = append(parts, text[start:])
	return parts
}

func parseRecovery(text string) *RetortRecovery {
	r := &RetortRecovery{
		MaxRetries:        3,
		ExhaustionAction:  "bottom",
		RecoveryDirective: text,
	}

	// Parse "max N" from recovery text
	maxRe := regexp.MustCompile(`max\s+(\d+)`)
	if m := maxRe.FindStringSubmatch(text); m != nil {
		n, err := strconv.Atoi(m[1])
		if err == nil {
			r.MaxRetries = n
		}
	}

	// Parse exhaustion action
	if strings.Contains(text, "escalate") {
		r.ExhaustionAction = "escalate"
	} else if strings.Contains(text, "partial") {
		r.ExhaustionAction = "partial_accept"
	}

	return r
}

// DetectSyntax auto-detects whether a .cell file uses turnstile or molecule syntax.
// Returns "turnstile" or "molecule".
func DetectSyntax(source string) string {
	for _, line := range strings.Split(source, "\n") {
		trimmed := strings.TrimSpace(line)
		if trimmed == "" || strings.HasPrefix(trimmed, "--") {
			continue
		}
		if strings.HasPrefix(trimmed, "⊢") || strings.HasPrefix(trimmed, "∴") ||
			strings.HasPrefix(trimmed, "⊨") {
			return "turnstile"
		}
		if strings.HasPrefix(trimmed, "##") || strings.HasPrefix(trimmed, "#") {
			return "molecule"
		}
		break
	}
	return "turnstile" // default
}
