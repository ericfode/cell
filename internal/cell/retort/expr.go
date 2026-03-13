package retort

import (
	"fmt"
	"math"
	"regexp"
	"strconv"
	"strings"
	"unicode"
)

// EvalExpr evaluates a Cell ⊢= expression with the given bindings.
// This is a proper Pratt parser + tree-walk interpreter, replacing
// the fragile Python eval() approach.
func EvalExpr(expr string, bindings map[string]interface{}) (interface{}, error) {
	// Handle multi-line bodies with ← bindings
	lines := strings.Split(expr, "\n")
	if len(lines) > 1 {
		localBindings := make(map[string]interface{})
		for k, v := range bindings {
			localBindings[k] = v
		}
		var lastVal interface{}
		for _, line := range lines {
			line = strings.TrimSpace(line)
			if line == "" {
				continue
			}
			// Check for binding form: name ← expression
			if idx := strings.Index(line, "←"); idx > 0 {
				name := strings.TrimSpace(line[:idx])
				rest := strings.TrimSpace(line[idx+len("←"):])
				val, err := evalSingle(rest, localBindings)
				if err != nil {
					return nil, fmt.Errorf("binding %s: %w", name, err)
				}
				localBindings[name] = val
				lastVal = val
			} else {
				val, err := evalSingle(line, localBindings)
				if err != nil {
					return nil, err
				}
				lastVal = val
			}
		}
		return lastVal, nil
	}

	// Single expression - check for binding form
	trimmed := strings.TrimSpace(expr)
	if idx := strings.Index(trimmed, "←"); idx > 0 {
		rest := strings.TrimSpace(trimmed[idx+len("←"):])
		return evalSingle(rest, bindings)
	}
	return evalSingle(trimmed, bindings)
}

func evalSingle(expr string, bindings map[string]interface{}) (interface{}, error) {
	p := &exprParser{input: expr, pos: 0, bindings: bindings}
	val, err := p.parseExpr(0)
	if err != nil {
		return nil, err
	}
	return val, nil
}

// --- Tokenizer ---

type tokenKind int

const (
	tokEOF tokenKind = iota
	tokNum
	tokStr
	tokBool
	tokNull
	tokBottom
	tokIdent
	tokPlus
	tokMinus
	tokStar
	tokSlash
	tokPercent
	tokEq
	tokNeq
	tokLt
	tokLte
	tokGt
	tokGte
	tokAnd
	tokOr
	tokNot
	tokLParen
	tokRParen
	tokLBracket
	tokRBracket
	tokComma
	tokDot
	tokArrow // →
	tokIf
	tokThen
	tokElse
	tokConcat // ++
)

type token struct {
	kind tokenKind
	sval string
	nval float64
	bval bool
}

type exprParser struct {
	input    string
	pos      int
	bindings map[string]interface{}
	peeked   *token
}

func (p *exprParser) skipWhitespace() {
	for p.pos < len(p.input) && (p.input[p.pos] == ' ' || p.input[p.pos] == '\t') {
		p.pos++
	}
}

func (p *exprParser) peek() token {
	if p.peeked != nil {
		return *p.peeked
	}
	t := p.next()
	p.peeked = &t
	return t
}

func (p *exprParser) advance() token {
	if p.peeked != nil {
		t := *p.peeked
		p.peeked = nil
		return t
	}
	return p.next()
}

func (p *exprParser) next() token {
	p.skipWhitespace()
	if p.pos >= len(p.input) {
		return token{kind: tokEOF}
	}

	ch := p.input[p.pos]

	// Two-character operators
	if p.pos+1 < len(p.input) {
		two := p.input[p.pos : p.pos+2]
		switch two {
		case "!=":
			p.pos += 2
			return token{kind: tokNeq}
		case "<=":
			p.pos += 2
			return token{kind: tokLte}
		case ">=":
			p.pos += 2
			return token{kind: tokGte}
		case "++":
			p.pos += 2
			return token{kind: tokConcat}
		}
	}

	// Single-character operators
	switch ch {
	case '+':
		p.pos++
		return token{kind: tokPlus}
	case '-':
		// Check if this is a negative number (preceded by operator or start)
		p.pos++
		return token{kind: tokMinus}
	case '*':
		p.pos++
		return token{kind: tokStar}
	case '/':
		p.pos++
		return token{kind: tokSlash}
	case '%':
		p.pos++
		return token{kind: tokPercent}
	case '=':
		p.pos++
		return token{kind: tokEq}
	case '<':
		p.pos++
		return token{kind: tokLt}
	case '>':
		p.pos++
		return token{kind: tokGt}
	case '(':
		p.pos++
		return token{kind: tokLParen}
	case ')':
		p.pos++
		return token{kind: tokRParen}
	case '[':
		p.pos++
		return token{kind: tokLBracket}
	case ']':
		p.pos++
		return token{kind: tokRBracket}
	case ',':
		p.pos++
		return token{kind: tokComma}
	case '.':
		p.pos++
		return token{kind: tokDot}
	}

	// → arrow (UTF-8)
	if strings.HasPrefix(p.input[p.pos:], "→") {
		p.pos += len("→")
		return token{kind: tokArrow}
	}

	// ⊥ bottom
	if strings.HasPrefix(p.input[p.pos:], "⊥") {
		p.pos += len("⊥")
		return token{kind: tokBottom}
	}

	// String literal
	if ch == '"' {
		return p.readString()
	}

	// Number
	if ch >= '0' && ch <= '9' {
		return p.readNumber()
	}

	// Identifier or keyword
	if isIdentStart(ch) || ch > 127 {
		return p.readIdent()
	}

	// Unknown character - skip
	p.pos++
	return token{kind: tokEOF}
}

func (p *exprParser) readString() token {
	p.pos++ // skip opening quote
	var sb strings.Builder
	for p.pos < len(p.input) && p.input[p.pos] != '"' {
		if p.input[p.pos] == '\\' && p.pos+1 < len(p.input) {
			p.pos++
			switch p.input[p.pos] {
			case 'n':
				sb.WriteByte('\n')
			case 't':
				sb.WriteByte('\t')
			case '"':
				sb.WriteByte('"')
			case '\\':
				sb.WriteByte('\\')
			default:
				sb.WriteByte(p.input[p.pos])
			}
		} else {
			sb.WriteByte(p.input[p.pos])
		}
		p.pos++
	}
	if p.pos < len(p.input) {
		p.pos++ // skip closing quote
	}
	return token{kind: tokStr, sval: sb.String()}
}

func (p *exprParser) readNumber() token {
	start := p.pos
	for p.pos < len(p.input) && (p.input[p.pos] >= '0' && p.input[p.pos] <= '9') {
		p.pos++
	}
	if p.pos < len(p.input) && p.input[p.pos] == '.' {
		p.pos++
		for p.pos < len(p.input) && (p.input[p.pos] >= '0' && p.input[p.pos] <= '9') {
			p.pos++
		}
	}
	n, _ := strconv.ParseFloat(p.input[start:p.pos], 64)
	return token{kind: tokNum, nval: n}
}

func (p *exprParser) readIdent() token {
	start := p.pos
	for p.pos < len(p.input) {
		r := rune(p.input[p.pos])
		if p.pos > start && p.input[p.pos] > 127 {
			// Check for multi-byte UTF-8
			_, size := decodeRune(p.input[p.pos:])
			if size > 0 {
				r, _ = decodeRune(p.input[p.pos:])
				if !unicode.IsLetter(r) && !unicode.IsDigit(r) {
					break
				}
				p.pos += size
				continue
			}
		}
		if isIdentChar(p.input[p.pos]) {
			p.pos++
		} else {
			break
		}
	}
	word := p.input[start:p.pos]
	switch word {
	case "true":
		return token{kind: tokBool, bval: true}
	case "false":
		return token{kind: tokBool, bval: false}
	case "null", "nil":
		return token{kind: tokNull}
	case "and":
		return token{kind: tokAnd}
	case "or":
		return token{kind: tokOr}
	case "not":
		return token{kind: tokNot}
	case "if":
		return token{kind: tokIf}
	case "then":
		return token{kind: tokThen}
	case "else":
		return token{kind: tokElse}
	default:
		return token{kind: tokIdent, sval: word}
	}
}

func decodeRune(s string) (rune, int) {
	r, size := rune(s[0]), 1
	if s[0] >= 0x80 {
		for _, ru := range s {
			return ru, len(string(ru))
		}
	}
	return r, size
}

func isIdentStart(c byte) bool {
	return (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || c == '_'
}

func isIdentChar(c byte) bool {
	return isIdentStart(c) || (c >= '0' && c <= '9') || c == '-'
}

// --- Pratt Parser ---

// Precedence levels
func prefixBP(kind tokenKind) int {
	switch kind {
	case tokNot:
		return 13
	case tokMinus:
		return 13
	default:
		return 0
	}
}

func infixBP(kind tokenKind) (int, int) {
	switch kind {
	case tokOr:
		return 1, 2
	case tokAnd:
		return 3, 4
	case tokEq, tokNeq:
		return 5, 6
	case tokLt, tokLte, tokGt, tokGte:
		return 7, 8
	case tokConcat:
		return 9, 10
	case tokPlus, tokMinus:
		return 9, 10
	case tokStar, tokSlash, tokPercent:
		return 11, 12
	default:
		return 0, 0
	}
}

func (p *exprParser) parseExpr(minBP int) (interface{}, error) {
	// Check for if/then/else at the top level
	t := p.peek()
	if t.kind == tokIf {
		return p.parseIfThenElse()
	}

	lhs, err := p.parsePrefix()
	if err != nil {
		return nil, err
	}

	for {
		t = p.peek()
		if t.kind == tokEOF || t.kind == tokRParen || t.kind == tokRBracket ||
			t.kind == tokComma || t.kind == tokThen || t.kind == tokElse {
			break
		}

		lbp, rbp := infixBP(t.kind)
		if lbp == 0 || lbp < minBP {
			break
		}

		op := p.advance()
		rhs, err := p.parseExpr(rbp)
		if err != nil {
			return nil, err
		}

		lhs, err = evalBinOp(op.kind, lhs, rhs)
		if err != nil {
			return nil, err
		}
	}

	return lhs, nil
}

func (p *exprParser) parsePrefix() (interface{}, error) {
	t := p.peek()

	switch t.kind {
	case tokNum:
		p.advance()
		return t.nval, nil

	case tokStr:
		p.advance()
		return t.sval, nil

	case tokBool:
		p.advance()
		return t.bval, nil

	case tokNull, tokBottom:
		p.advance()
		return nil, nil

	case tokMinus:
		p.advance()
		val, err := p.parseExpr(prefixBP(tokMinus))
		if err != nil {
			return nil, err
		}
		n, ok := toFloat(val)
		if !ok {
			return nil, fmt.Errorf("cannot negate non-number: %v", val)
		}
		return -n, nil

	case tokNot:
		p.advance()
		val, err := p.parseExpr(prefixBP(tokNot))
		if err != nil {
			return nil, err
		}
		return !toBool(val), nil

	case tokLParen:
		p.advance()
		val, err := p.parseExpr(0)
		if err != nil {
			return nil, err
		}
		if p.peek().kind == tokRParen {
			p.advance()
		}
		return val, nil

	case tokLBracket:
		return p.parseList()

	case tokIdent:
		return p.parseIdentOrCall()

	default:
		p.advance()
		return nil, fmt.Errorf("unexpected token: %v", t)
	}
}

func (p *exprParser) parseIfThenElse() (interface{}, error) {
	p.advance() // consume 'if'
	cond, err := p.parseExpr(0)
	if err != nil {
		return nil, fmt.Errorf("if condition: %w", err)
	}
	if p.peek().kind != tokThen {
		return nil, fmt.Errorf("expected 'then', got %v", p.peek())
	}
	p.advance() // consume 'then'

	// Lazy evaluation: only evaluate the taken branch, skip the other
	thenVal, thenErr := p.parseExpr(0)

	if p.peek().kind != tokElse {
		return nil, fmt.Errorf("expected 'else', got %v", p.peek())
	}
	p.advance() // consume 'else'

	elseVal, elseErr := p.parseExpr(0)

	if toBool(cond) {
		if thenErr != nil {
			return nil, fmt.Errorf("then branch: %w", thenErr)
		}
		return thenVal, nil
	}
	if elseErr != nil {
		return nil, fmt.Errorf("else branch: %w", elseErr)
	}
	return elseVal, nil
}

func (p *exprParser) parseList() (interface{}, error) {
	p.advance() // consume '['
	var elems []interface{}
	for p.peek().kind != tokRBracket && p.peek().kind != tokEOF {
		val, err := p.parseExpr(0)
		if err != nil {
			return nil, err
		}
		elems = append(elems, val)
		if p.peek().kind == tokComma {
			p.advance()
		}
	}
	if p.peek().kind == tokRBracket {
		p.advance()
	}
	if elems == nil {
		elems = []interface{}{}
	}
	return elems, nil
}

func (p *exprParser) parseIdentOrCall() (interface{}, error) {
	t := p.advance() // consume identifier
	name := t.sval

	// Check for → (cell→field reference)
	if p.peek().kind == tokArrow {
		p.advance() // consume →
		fieldTok := p.advance()
		ref := name + "→" + fieldTok.sval
		if val, ok := p.bindings[ref]; ok {
			return val, nil
		}
		// Try just the field name
		if val, ok := p.bindings[fieldTok.sval]; ok {
			return val, nil
		}
		return nil, fmt.Errorf("unresolved reference: %s", ref)
	}

	// Check for function call
	if p.peek().kind == tokLParen {
		return p.parseCall(name)
	}

	// Check for field access via dot
	if p.peek().kind == tokDot {
		val, ok := p.bindings[name]
		if !ok {
			return nil, fmt.Errorf("undefined: %s", name)
		}
		for p.peek().kind == tokDot {
			p.advance() // consume '.'
			fieldTok := p.advance()
			val = fieldAccess(val, fieldTok.sval)
		}
		return val, nil
	}

	// Check for list index access (supports chaining: matrix[1][0])
	if p.peek().kind == tokLBracket {
		val, ok := p.bindings[name]
		if !ok {
			return nil, fmt.Errorf("undefined: %s", name)
		}
		for p.peek().kind == tokLBracket {
			p.advance() // consume '['
			idx, err := p.parseExpr(0)
			if err != nil {
				return nil, err
			}
			if p.peek().kind == tokRBracket {
				p.advance()
			}
			val, err = indexAccess(val, idx)
			if err != nil {
				return nil, err
			}
		}
		return val, nil
	}

	// Variable lookup
	if val, ok := p.bindings[name]; ok {
		return val, nil
	}

	return nil, fmt.Errorf("undefined: %s", name)
}

func (p *exprParser) parseCall(name string) (interface{}, error) {
	p.advance() // consume '('

	// Special forms: all(var, expr), any(var, expr), filter(list, var, expr),
	// map(list, var, expr), count(list, var, expr)
	// These need lazy evaluation of the expression with a bound variable.
	switch name {
	case "all", "any":
		return p.parseIteratorPredicate(name)
	case "filter":
		return p.parseIteratorTransform(name)
	case "map":
		return p.parseIteratorTransform(name)
	case "count":
		return p.parseIteratorTransform(name)
	}

	var args []interface{}
	for p.peek().kind != tokRParen && p.peek().kind != tokEOF {
		val, err := p.parseExpr(0)
		if err != nil {
			return nil, err
		}
		args = append(args, val)
		if p.peek().kind == tokComma {
			p.advance()
		}
	}
	if p.peek().kind == tokRParen {
		p.advance()
	}
	return callBuiltin(name, args)
}

// parseIteratorPredicate handles all(var, expr) and any(var, expr).
// Two forms:
//   all(list)         — check all elements truthy
//   all(var, expr)    — bind var to each index, check expr
func (p *exprParser) parseIteratorPredicate(name string) (interface{}, error) {
	// Try to detect if first arg is a variable name followed by comma
	// Save parser state to backtrack if needed
	savedPos := p.pos
	savedPeeked := p.peeked

	// Check if first token is an identifier followed by comma (iterator form)
	firstTok := p.peek()
	if firstTok.kind == tokIdent {
		// Check if this identifier is NOT in bindings (meaning it's a loop variable)
		if _, exists := p.bindings[firstTok.sval]; !exists {
			p.advance() // consume the variable name
			if p.peek().kind == tokComma {
				p.advance() // consume comma
				return p.evalIteratorPredicate(name, firstTok.sval)
			}
		}
	}

	// Backtrack — it's the simple form: all(list) or all(expr)
	p.pos = savedPos
	p.peeked = savedPeeked

	val, err := p.parseExpr(0)
	if err != nil {
		return nil, err
	}
	if p.peek().kind == tokRParen {
		p.advance()
	}

	// Simple form: all(list) / any(list)
	lst, ok := val.([]interface{})
	if !ok {
		return toBool(val), nil
	}
	if name == "all" {
		for _, v := range lst {
			if !toBool(v) {
				return false, nil
			}
		}
		return true, nil
	}
	// any
	for _, v := range lst {
		if toBool(v) {
			return true, nil
		}
	}
	return false, nil
}

// evalIteratorPredicate evaluates all(var, expr) or any(var, expr).
// The expression is captured as raw text and re-parsed for each iteration.
func (p *exprParser) evalIteratorPredicate(name, varName string) (interface{}, error) {
	// Capture the expression text from current position to closing paren
	exprText := p.captureUntilCloseParen()

	// We need to figure out the iteration range.
	// Heuristic: look at the expression for patterns like var[something] or list[var]
	// The iteration variable typically ranges over indices of some list in bindings.
	// Find the list by looking for `listname[varName]` patterns in the expression.
	iterList := findIterableList(exprText, varName, p.bindings)
	if iterList == nil {
		return nil, fmt.Errorf("%s: cannot determine iteration range for variable %s", name, varName)
	}

	// For all(i, sorted[i] <= sorted[i+1]), iterate i from 0 to len-2
	// (because sorted[i+1] needs i+1 to be valid)
	maxIdx := len(iterList)
	// Check if expression references varName+1 (like i+1)
	if strings.Contains(exprText, varName+"+1") || strings.Contains(exprText, varName+" + 1") {
		maxIdx = len(iterList) - 1
	}

	for idx := 0; idx < maxIdx; idx++ {
		// Create bindings with the loop variable
		localBindings := make(map[string]interface{})
		for k, v := range p.bindings {
			localBindings[k] = v
		}
		localBindings[varName] = float64(idx)

		result, err := evalSingle(exprText, localBindings)
		if err != nil {
			return nil, fmt.Errorf("%s iteration %d: %w", name, idx, err)
		}

		if name == "all" && !toBool(result) {
			return false, nil
		}
		if name == "any" && toBool(result) {
			return true, nil
		}
	}

	if name == "all" {
		return true, nil
	}
	return false, nil // any: no element matched
}

// parseIteratorTransform handles filter(list, var, expr), map(list, var, expr), count(list, var, expr).
func (p *exprParser) parseIteratorTransform(name string) (interface{}, error) {
	// First arg: the list (evaluated)
	listVal, err := p.parseExpr(0)
	if err != nil {
		return nil, err
	}
	if p.peek().kind == tokComma {
		p.advance()
	}

	lst, ok := listVal.([]interface{})
	if !ok {
		if p.peek().kind == tokRParen {
			p.advance()
		}
		return nil, fmt.Errorf("%s: first argument must be a list", name)
	}

	// Check if next token is a variable name (iterator form) or end
	if p.peek().kind == tokRParen {
		p.advance()
		// No predicate — just return list operations on the list
		switch name {
		case "count":
			return float64(len(lst)), nil
		default:
			return lst, nil
		}
	}

	// Second arg: variable name
	varTok := p.advance()
	if varTok.kind != tokIdent {
		return nil, fmt.Errorf("%s: expected variable name, got %v", name, varTok)
	}
	varName := varTok.sval

	if p.peek().kind == tokComma {
		p.advance()
	}

	// Third arg: expression (captured as text)
	exprText := p.captureUntilCloseParen()

	var result []interface{}
	countN := 0.0

	for _, elem := range lst {
		localBindings := make(map[string]interface{})
		for k, v := range p.bindings {
			localBindings[k] = v
		}
		localBindings[varName] = elem

		val, err := evalSingle(exprText, localBindings)
		if err != nil {
			return nil, fmt.Errorf("%s: %w", name, err)
		}

		switch name {
		case "filter":
			if toBool(val) {
				result = append(result, elem)
			}
		case "map":
			result = append(result, val)
		case "count":
			if toBool(val) {
				countN++
			}
		}
	}

	switch name {
	case "count":
		return countN, nil
	default:
		if result == nil {
			result = []interface{}{}
		}
		return result, nil
	}
}

// captureUntilCloseParen captures raw expression text until the matching ')'.
func (p *exprParser) captureUntilCloseParen() string {
	start := p.pos
	depth := 1
	for p.pos < len(p.input) && depth > 0 {
		ch := p.input[p.pos]
		if ch == '(' {
			depth++
		} else if ch == ')' {
			depth--
			if depth == 0 {
				text := strings.TrimSpace(p.input[start:p.pos])
				p.pos++ // consume ')'
				p.peeked = nil
				return text
			}
		}
		p.pos++
	}
	text := strings.TrimSpace(p.input[start:p.pos])
	p.peeked = nil
	return text
}

// findIterableList looks for a list in bindings that the expression indexes with the given variable.
func findIterableList(expr, varName string, bindings map[string]interface{}) []interface{} {
	// Look for patterns like "listname[varName" in the expression
	// e.g., "sorted[i]" → look for "sorted" in bindings
	pattern := regexp.MustCompile(`(\w[\w-]*)(?:→(\w[\w-]*))?\[` + regexp.QuoteMeta(varName))
	matches := pattern.FindAllStringSubmatch(expr, -1)
	for _, m := range matches {
		name := m[1]
		if m[2] != "" {
			name = m[1] + "→" + m[2]
		}
		if val, ok := bindings[name]; ok {
			if lst, ok := val.([]interface{}); ok {
				return lst
			}
		}
	}
	// Try all list-valued bindings as fallback
	for _, v := range bindings {
		if lst, ok := v.([]interface{}); ok {
			return lst
		}
	}
	return nil
}

// --- Built-in functions ---

func callBuiltin(name string, args []interface{}) (interface{}, error) {
	switch name {
	case "len", "length":
		if len(args) != 1 {
			return nil, fmt.Errorf("len: expected 1 arg, got %d", len(args))
		}
		switch v := args[0].(type) {
		case string:
			return float64(len(v)), nil
		case []interface{}:
			return float64(len(v)), nil
		default:
			return float64(0), nil
		}

	case "split":
		if len(args) != 2 {
			return nil, fmt.Errorf("split: expected 2 args, got %d", len(args))
		}
		s, _ := args[0].(string)
		d, _ := args[1].(string)
		parts := strings.Split(s, d)
		result := make([]interface{}, len(parts))
		for i, p := range parts {
			result[i] = p
		}
		return result, nil

	case "join":
		if len(args) != 2 {
			return nil, fmt.Errorf("join: expected 2 args, got %d", len(args))
		}
		lst, _ := args[0].([]interface{})
		d, _ := args[1].(string)
		strs := make([]string, len(lst))
		for i, v := range lst {
			strs[i] = fmt.Sprintf("%v", v)
		}
		return strings.Join(strs, d), nil

	case "abs":
		if len(args) != 1 {
			return nil, fmt.Errorf("abs: expected 1 arg, got %d", len(args))
		}
		n, ok := toFloat(args[0])
		if !ok {
			return nil, fmt.Errorf("abs: not a number: %v", args[0])
		}
		return math.Abs(n), nil

	case "min":
		if len(args) < 1 {
			return nil, fmt.Errorf("min: expected at least 1 arg")
		}
		// If first arg is a list, find min in the list
		if lst, ok := args[0].([]interface{}); ok && len(args) == 1 {
			if len(lst) == 0 {
				return nil, nil
			}
			minVal, _ := toFloat(lst[0])
			for _, v := range lst[1:] {
				n, _ := toFloat(v)
				if n < minVal {
					minVal = n
				}
			}
			return minVal, nil
		}
		minVal, _ := toFloat(args[0])
		for _, a := range args[1:] {
			n, _ := toFloat(a)
			if n < minVal {
				minVal = n
			}
		}
		return minVal, nil

	case "max":
		if len(args) < 1 {
			return nil, fmt.Errorf("max: expected at least 1 arg")
		}
		if lst, ok := args[0].([]interface{}); ok && len(args) == 1 {
			if len(lst) == 0 {
				return nil, nil
			}
			maxVal, _ := toFloat(lst[0])
			for _, v := range lst[1:] {
				n, _ := toFloat(v)
				if n > maxVal {
					maxVal = n
				}
			}
			return maxVal, nil
		}
		maxVal, _ := toFloat(args[0])
		for _, a := range args[1:] {
			n, _ := toFloat(a)
			if n > maxVal {
				maxVal = n
			}
		}
		return maxVal, nil

	case "sum":
		if len(args) != 1 {
			return nil, fmt.Errorf("sum: expected 1 arg, got %d", len(args))
		}
		lst, ok := args[0].([]interface{})
		if !ok {
			return float64(0), nil
		}
		total := 0.0
		for _, v := range lst {
			n, _ := toFloat(v)
			total += n
		}
		return total, nil

	case "sorted":
		if len(args) != 1 {
			return nil, fmt.Errorf("sorted: expected 1 arg, got %d", len(args))
		}
		lst, ok := args[0].([]interface{})
		if !ok {
			return args[0], nil
		}
		result := make([]interface{}, len(lst))
		copy(result, lst)
		// Simple insertion sort for numbers
		for i := 1; i < len(result); i++ {
			for j := i; j > 0; j-- {
				a, _ := toFloat(result[j-1])
				b, _ := toFloat(result[j])
				if a > b {
					result[j-1], result[j] = result[j], result[j-1]
				}
			}
		}
		return result, nil

	case "reversed":
		if len(args) != 1 {
			return nil, fmt.Errorf("reversed: expected 1 arg, got %d", len(args))
		}
		lst, ok := args[0].([]interface{})
		if !ok {
			return args[0], nil
		}
		result := make([]interface{}, len(lst))
		for i, v := range lst {
			result[len(lst)-1-i] = v
		}
		return result, nil

	case "contains":
		if len(args) != 2 {
			return nil, fmt.Errorf("contains: expected 2 args, got %d", len(args))
		}
		s, _ := args[0].(string)
		sub, _ := args[1].(string)
		return strings.Contains(s, sub), nil

	case "starts_with":
		if len(args) != 2 {
			return nil, fmt.Errorf("starts_with: expected 2 args")
		}
		s, _ := args[0].(string)
		prefix, _ := args[1].(string)
		return strings.HasPrefix(s, prefix), nil

	case "ends_with":
		if len(args) != 2 {
			return nil, fmt.Errorf("ends_with: expected 2 args")
		}
		s, _ := args[0].(string)
		suffix, _ := args[1].(string)
		return strings.HasSuffix(s, suffix), nil

	case "upper":
		if len(args) != 1 {
			return nil, fmt.Errorf("upper: expected 1 arg")
		}
		s, _ := args[0].(string)
		return strings.ToUpper(s), nil

	case "lower":
		if len(args) != 1 {
			return nil, fmt.Errorf("lower: expected 1 arg")
		}
		s, _ := args[0].(string)
		return strings.ToLower(s), nil

	case "trim":
		if len(args) != 1 {
			return nil, fmt.Errorf("trim: expected 1 arg")
		}
		s, _ := args[0].(string)
		return strings.TrimSpace(s), nil

	case "concat":
		if len(args) != 2 {
			return nil, fmt.Errorf("concat: expected 2 args")
		}
		return fmt.Sprintf("%v%v", args[0], args[1]), nil

	case "str":
		if len(args) != 1 {
			return nil, fmt.Errorf("str: expected 1 arg")
		}
		return fmt.Sprintf("%v", args[0]), nil

	case "int":
		if len(args) != 1 {
			return nil, fmt.Errorf("int: expected 1 arg")
		}
		n, _ := toFloat(args[0])
		return math.Trunc(n), nil

	case "float":
		if len(args) != 1 {
			return nil, fmt.Errorf("float: expected 1 arg")
		}
		n, _ := toFloat(args[0])
		return n, nil

	case "all":
		// all(fn, list) or all(list) - check if all elements are truthy
		if len(args) == 1 {
			lst, ok := args[0].([]interface{})
			if !ok {
				return toBool(args[0]), nil
			}
			for _, v := range lst {
				if !toBool(v) {
					return false, nil
				}
			}
			return true, nil
		}
		return nil, fmt.Errorf("all: unsupported arity %d", len(args))

	case "any":
		if len(args) == 1 {
			lst, ok := args[0].([]interface{})
			if !ok {
				return toBool(args[0]), nil
			}
			for _, v := range lst {
				if toBool(v) {
					return true, nil
				}
			}
			return false, nil
		}
		return nil, fmt.Errorf("any: unsupported arity %d", len(args))

	case "range":
		if len(args) < 1 || len(args) > 3 {
			return nil, fmt.Errorf("range: expected 1-3 args")
		}
		start, end, step := 0.0, 0.0, 1.0
		switch len(args) {
		case 1:
			end, _ = toFloat(args[0])
		case 2:
			start, _ = toFloat(args[0])
			end, _ = toFloat(args[1])
		case 3:
			start, _ = toFloat(args[0])
			end, _ = toFloat(args[1])
			step, _ = toFloat(args[2])
		}
		var result []interface{}
		for i := start; i < end; i += step {
			result = append(result, i)
		}
		if result == nil {
			result = []interface{}{}
		}
		return result, nil

	case "multiset":
		// multiset equality helper: returns a sorted copy for comparison
		if len(args) != 1 {
			return nil, fmt.Errorf("multiset: expected 1 arg")
		}
		lst, ok := args[0].([]interface{})
		if !ok {
			return args[0], nil
		}
		result := make([]interface{}, len(lst))
		copy(result, lst)
		// Sort for comparison
		for i := 1; i < len(result); i++ {
			for j := i; j > 0; j-- {
				a, _ := toFloat(result[j-1])
				b, _ := toFloat(result[j])
				if a > b {
					result[j-1], result[j] = result[j], result[j-1]
				}
			}
		}
		return result, nil

	case "flatten":
		if len(args) != 1 {
			return nil, fmt.Errorf("flatten: expected 1 arg")
		}
		lst, ok := args[0].([]interface{})
		if !ok {
			return args[0], nil
		}
		var result []interface{}
		for _, v := range lst {
			if sub, ok := v.([]interface{}); ok {
				result = append(result, sub...)
			} else {
				result = append(result, v)
			}
		}
		if result == nil {
			result = []interface{}{}
		}
		return result, nil

	case "zip":
		if len(args) != 2 {
			return nil, fmt.Errorf("zip: expected 2 args")
		}
		a, _ := args[0].([]interface{})
		b, _ := args[1].([]interface{})
		n := len(a)
		if len(b) < n {
			n = len(b)
		}
		result := make([]interface{}, n)
		for i := 0; i < n; i++ {
			result[i] = []interface{}{a[i], b[i]}
		}
		return result, nil

	case "take":
		if len(args) != 2 {
			return nil, fmt.Errorf("take: expected 2 args (list, count)")
		}
		lst, _ := args[0].([]interface{})
		n, _ := toFloat(args[1])
		count := int(n)
		if count > len(lst) {
			count = len(lst)
		}
		if count < 0 {
			count = 0
		}
		return append([]interface{}{}, lst[:count]...), nil

	case "drop":
		if len(args) != 2 {
			return nil, fmt.Errorf("drop: expected 2 args (list, count)")
		}
		lst, _ := args[0].([]interface{})
		n, _ := toFloat(args[1])
		count := int(n)
		if count > len(lst) {
			count = len(lst)
		}
		if count < 0 {
			count = 0
		}
		return append([]interface{}{}, lst[count:]...), nil

	case "matches":
		if len(args) != 2 {
			return nil, fmt.Errorf("matches: expected 2 args (string, pattern)")
		}
		s, _ := args[0].(string)
		pat, _ := args[1].(string)
		re, err := regexp.Compile(pat)
		if err != nil {
			return nil, fmt.Errorf("matches: invalid regex %q: %w", pat, err)
		}
		return re.MatchString(s), nil

	default:
		return nil, fmt.Errorf("unknown function: %s", name)
	}
}

// --- Binary operators ---

func evalBinOp(op tokenKind, lhs, rhs interface{}) (interface{}, error) {
	switch op {
	case tokPlus:
		// String concatenation if either side is string
		if ls, ok := lhs.(string); ok {
			return ls + fmt.Sprintf("%v", rhs), nil
		}
		if _, ok := rhs.(string); ok {
			return fmt.Sprintf("%v", lhs) + rhs.(string), nil
		}
		// List concatenation
		if la, ok := lhs.([]interface{}); ok {
			if ra, ok := rhs.([]interface{}); ok {
				result := make([]interface{}, len(la)+len(ra))
				copy(result, la)
				copy(result[len(la):], ra)
				return result, nil
			}
		}
		a, _ := toFloat(lhs)
		b, _ := toFloat(rhs)
		return a + b, nil

	case tokMinus:
		a, _ := toFloat(lhs)
		b, _ := toFloat(rhs)
		return a - b, nil

	case tokStar:
		a, _ := toFloat(lhs)
		b, _ := toFloat(rhs)
		return a * b, nil

	case tokSlash:
		a, _ := toFloat(lhs)
		b, _ := toFloat(rhs)
		if b == 0 {
			return nil, fmt.Errorf("division by zero")
		}
		return a / b, nil

	case tokPercent:
		a, _ := toFloat(lhs)
		b, _ := toFloat(rhs)
		if b == 0 {
			return nil, fmt.Errorf("modulo by zero")
		}
		return math.Mod(a, b), nil

	case tokEq:
		return valEqual(lhs, rhs), nil

	case tokNeq:
		return !valEqual(lhs, rhs), nil

	case tokLt:
		a, _ := toFloat(lhs)
		b, _ := toFloat(rhs)
		return a < b, nil

	case tokLte:
		a, _ := toFloat(lhs)
		b, _ := toFloat(rhs)
		return a <= b, nil

	case tokGt:
		a, _ := toFloat(lhs)
		b, _ := toFloat(rhs)
		return a > b, nil

	case tokGte:
		a, _ := toFloat(lhs)
		b, _ := toFloat(rhs)
		return a >= b, nil

	case tokAnd:
		return toBool(lhs) && toBool(rhs), nil

	case tokOr:
		return toBool(lhs) || toBool(rhs), nil

	case tokConcat:
		return fmt.Sprintf("%v%v", lhs, rhs), nil

	default:
		return nil, fmt.Errorf("unknown operator: %v", op)
	}
}

// --- Type coercion helpers ---

func toFloat(v interface{}) (float64, bool) {
	switch n := v.(type) {
	case float64:
		return n, true
	case int:
		return float64(n), true
	case int64:
		return float64(n), true
	case string:
		if f, err := strconv.ParseFloat(n, 64); err == nil {
			return f, true
		}
		return 0, false
	case bool:
		if n {
			return 1, true
		}
		return 0, true
	default:
		return 0, false
	}
}

func toBool(v interface{}) bool {
	switch b := v.(type) {
	case bool:
		return b
	case float64:
		return b != 0
	case int:
		return b != 0
	case string:
		return b != ""
	case []interface{}:
		return len(b) > 0
	case nil:
		return false
	default:
		return true
	}
}

func valEqual(a, b interface{}) bool {
	// Nil equality
	if a == nil && b == nil {
		return true
	}
	if a == nil || b == nil {
		return false
	}
	// List comparison — element-by-element
	aList, aIsList := a.([]interface{})
	bList, bIsList := b.([]interface{})
	if aIsList && bIsList {
		if len(aList) != len(bList) {
			return false
		}
		for i := range aList {
			if !valEqual(aList[i], bList[i]) {
				return false
			}
		}
		return true
	}
	// Bool comparison (before numeric, so true != 1 unless both are numbers)
	aBool, aIsBool := a.(bool)
	bBool, bIsBool := b.(bool)
	if aIsBool && bIsBool {
		return aBool == bBool
	}
	// Try numeric comparison
	an, aOk := toFloat(a)
	bn, bOk := toFloat(b)
	if aOk && bOk {
		return an == bn
	}
	// String comparison
	as := fmt.Sprintf("%v", a)
	bs := fmt.Sprintf("%v", b)
	return as == bs
}

func fieldAccess(v interface{}, field string) interface{} {
	switch m := v.(type) {
	case map[string]interface{}:
		return m[field]
	default:
		return nil
	}
}

func indexAccess(v interface{}, idx interface{}) (interface{}, error) {
	lst, ok := v.([]interface{})
	if !ok {
		return nil, fmt.Errorf("cannot index non-list: %v", v)
	}
	n, ok := toFloat(idx)
	if !ok {
		return nil, fmt.Errorf("non-numeric index: %v", idx)
	}
	i := int(n)
	if i < 0 || i >= len(lst) {
		return nil, fmt.Errorf("index out of range: %d (len=%d)", i, len(lst))
	}
	return lst[i], nil
}
