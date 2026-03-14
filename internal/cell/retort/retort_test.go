package retort

import (
	"fmt"
	"strings"
	"testing"
)

// dispatchDryRun is a test helper that dispatches a cell with dry-run
// behavior for soft cells (returns placeholder values instead of calling the API).
func dispatchDryRun(cell *CellRow, yields []YieldRow, bindings map[string]interface{}) DispatchResult {
	if cell.BodyType == "soft" {
		outputs := make(map[string]interface{})
		for _, y := range yields {
			outputs[y.FieldName] = fmt.Sprintf("<dry-run-%s-%s>", cell.Name, y.FieldName)
		}
		return DispatchResult{Outputs: outputs}
	}
	return Dispatch(nil, cell, yields, bindings)
}

// --- Expression evaluator tests ---

func TestEvalExprArithmetic(t *testing.T) {
	tests := []struct {
		expr     string
		bindings map[string]interface{}
		want     float64
	}{
		{"3 + 5", nil, 8},
		{"a + b", map[string]interface{}{"a": 3.0, "b": 5.0}, 8},
		{"a * 2", map[string]interface{}{"a": 10.0}, 20},
		{"10 - 3", nil, 7},
		{"15 / 3", nil, 5},
		{"10 % 3", nil, 1},
		{"0 - n", map[string]interface{}{"n": -7.0}, 7},
	}

	for _, tt := range tests {
		result, err := EvalExpr(tt.expr, tt.bindings)
		if err != nil {
			t.Errorf("EvalExpr(%q): %v", tt.expr, err)
			continue
		}
		got, ok := toFloat(result)
		if !ok {
			t.Errorf("EvalExpr(%q) = %v, want float", tt.expr, result)
			continue
		}
		if got != tt.want {
			t.Errorf("EvalExpr(%q) = %v, want %v", tt.expr, got, tt.want)
		}
	}
}

func TestEvalExprIfThenElse(t *testing.T) {
	tests := []struct {
		expr     string
		bindings map[string]interface{}
		want     interface{}
	}{
		{
			`if n < 0 then "negative" else "positive"`,
			map[string]interface{}{"n": -7.0},
			"negative",
		},
		{
			`if n < 0 then "negative" else "positive"`,
			map[string]interface{}{"n": 5.0},
			"positive",
		},
		{
			`if is-permutation and is-ordered then "certified" else "rejected"`,
			map[string]interface{}{"is-permutation": true, "is-ordered": true},
			"certified",
		},
	}

	for _, tt := range tests {
		result, err := EvalExpr(tt.expr, tt.bindings)
		if err != nil {
			t.Errorf("EvalExpr(%q): %v", tt.expr, err)
			continue
		}
		if result != tt.want {
			t.Errorf("EvalExpr(%q) = %v, want %v", tt.expr, result, tt.want)
		}
	}
}

func TestEvalExprFunctions(t *testing.T) {
	tests := []struct {
		expr     string
		bindings map[string]interface{}
		want     interface{}
	}{
		{
			`len(split(msg, " "))`,
			map[string]interface{}{"msg": "hello world foo"},
			3.0,
		},
		{
			`sorted(items)`,
			map[string]interface{}{"items": []interface{}{3.0, 1.0, 2.0}},
			nil, // checked separately
		},
		{
			`sum(items)`,
			map[string]interface{}{"items": []interface{}{1.0, 2.0, 3.0}},
			6.0,
		},
		{
			`upper("hello")`,
			nil,
			"HELLO",
		},
	}

	for _, tt := range tests {
		result, err := EvalExpr(tt.expr, tt.bindings)
		if err != nil {
			t.Errorf("EvalExpr(%q): %v", tt.expr, err)
			continue
		}
		if tt.want == nil {
			// Special case: check sorted
			if tt.expr == `sorted(items)` {
				lst, ok := result.([]interface{})
				if !ok || len(lst) != 3 {
					t.Errorf("sorted: expected list of 3, got %v", result)
				} else {
					a, _ := toFloat(lst[0])
					b, _ := toFloat(lst[1])
					c, _ := toFloat(lst[2])
					if a != 1 || b != 2 || c != 3 {
						t.Errorf("sorted: expected [1,2,3], got %v", result)
					}
				}
			}
			continue
		}
		if !valEqual(result, tt.want) {
			t.Errorf("EvalExpr(%q) = %v, want %v", tt.expr, result, tt.want)
		}
	}
}

func TestEvalExprBinding(t *testing.T) {
	// Multi-line with ← bindings
	expr := "sum ← a + b\nresult ← sum * 2"
	bindings := map[string]interface{}{"a": 3.0, "b": 5.0}
	result, err := EvalExpr(expr, bindings)
	if err != nil {
		t.Fatalf("EvalExpr: %v", err)
	}
	got, _ := toFloat(result)
	if got != 16 {
		t.Errorf("got %v, want 16", got)
	}
}

func TestEvalExprCellRef(t *testing.T) {
	// cell→field references
	bindings := map[string]interface{}{
		"add→sum": 8.0,
	}
	result, err := EvalExpr("add→sum * 2", bindings)
	if err != nil {
		t.Fatalf("EvalExpr: %v", err)
	}
	got, _ := toFloat(result)
	if got != 16 {
		t.Errorf("got %v, want 16", got)
	}
}

func TestEvalExprComparison(t *testing.T) {
	tests := []struct {
		expr     string
		bindings map[string]interface{}
		want     bool
	}{
		{"3 = 3", nil, true},
		{"3 != 4", nil, true},
		{"5 > 3", nil, true},
		{"3 < 5", nil, true},
		{"true and true", nil, true},
		{"true and false", nil, false},
		{"false or true", nil, true},
		{"not false", nil, true},
	}

	for _, tt := range tests {
		result, err := EvalExpr(tt.expr, tt.bindings)
		if err != nil {
			t.Errorf("EvalExpr(%q): %v", tt.expr, err)
			continue
		}
		got, ok := result.(bool)
		if !ok {
			t.Errorf("EvalExpr(%q) = %v (%T), want bool", tt.expr, result, result)
			continue
		}
		if got != tt.want {
			t.Errorf("EvalExpr(%q) = %v, want %v", tt.expr, got, tt.want)
		}
	}
}

func TestEvalExprList(t *testing.T) {
	result, err := EvalExpr("[1, 2, 3]", nil)
	if err != nil {
		t.Fatalf("EvalExpr: %v", err)
	}
	lst, ok := result.([]interface{})
	if !ok {
		t.Fatalf("expected list, got %T", result)
	}
	if len(lst) != 3 {
		t.Errorf("expected 3 elements, got %d", len(lst))
	}
}

// --- Turnstile parser tests ---

func TestParseTurnstileAddDouble(t *testing.T) {
	source := `-- add-double.cell
⊢ add
  given a ≡ 3
  given b ≡ 5
  yield sum

  ⊢= sum ← a + b

  ⊨ sum = 8

⊢ double
  given add→sum
  yield result

  ⊢= result ← add→sum * 2

  ⊨ result = 16`

	prog, err := ParseTurnstile(source)
	if err != nil {
		t.Fatalf("ParseTurnstile: %v", err)
	}

	if len(prog.Cells) != 2 {
		t.Fatalf("expected 2 cells, got %d", len(prog.Cells))
	}

	// Check 'add' cell
	add := prog.Cells[0]
	if add.Name != "add" {
		t.Errorf("cell 0 name = %q, want 'add'", add.Name)
	}
	if add.BodyType != BodyHard {
		t.Errorf("cell 0 body_type = %q, want 'hard'", add.BodyType)
	}
	if len(add.Givens) != 2 {
		t.Errorf("cell 0 givens = %d, want 2", len(add.Givens))
	}
	if add.Givens[0].Name != "a" || !add.Givens[0].HasDefault {
		t.Errorf("cell 0 given 0: name=%q hasDefault=%v", add.Givens[0].Name, add.Givens[0].HasDefault)
	}
	if len(add.Yields) != 1 || add.Yields[0].Name != "sum" {
		t.Errorf("cell 0 yields: %v", add.Yields)
	}
	if len(add.Oracles) != 1 || add.Oracles[0].Assertion != "sum = 8" {
		t.Errorf("cell 0 oracles: %v", add.Oracles)
	}

	// Check 'double' cell
	dbl := prog.Cells[1]
	if dbl.Name != "double" {
		t.Errorf("cell 1 name = %q, want 'double'", dbl.Name)
	}
	if len(dbl.Givens) != 1 {
		t.Errorf("cell 1 givens = %d, want 1", len(dbl.Givens))
	}
	if dbl.Givens[0].SourceCell != "add" || dbl.Givens[0].SourceField != "sum" {
		t.Errorf("cell 1 given 0: source=%q field=%q", dbl.Givens[0].SourceCell, dbl.Givens[0].SourceField)
	}
}

func TestParseTurnstileAbsValue(t *testing.T) {
	source := `⊢ check-sign
  given n ≡ -7
  yield sign
  ⊢= sign ← if n < 0 then "negative" else "positive"
  ⊨ sign = "negative"

⊢ negate
  given check-sign→sign where sign = "negative"
  given n ≡ -7
  yield result
  ⊢= result ← 0 - n
  ⊨ result = 7

⊢ pass-through
  given check-sign→sign where sign = "positive"
  given n ≡ -7
  yield result
  ⊢= result ← n`

	prog, err := ParseTurnstile(source)
	if err != nil {
		t.Fatalf("ParseTurnstile: %v", err)
	}

	if len(prog.Cells) != 3 {
		t.Fatalf("expected 3 cells, got %d", len(prog.Cells))
	}

	// Check guard on negate
	negate := prog.Cells[1]
	if negate.Name != "negate" {
		t.Errorf("cell 1 name = %q, want 'negate'", negate.Name)
	}
	if negate.Givens[0].GuardExpr != `sign = "negative"` {
		t.Errorf("negate guard = %q", negate.Givens[0].GuardExpr)
	}
}

func TestParseTurnstileRecovery(t *testing.T) {
	source := `⊢ sort
  given data→items
  yield sorted
  ∴ Sort «items» in ascending order.
  ⊨ sorted is a permutation of «data→items»
  ⊨? on failure:
    retry with «oracle.failures» appended to prompt
    max 2`

	prog, err := ParseTurnstile(source)
	if err != nil {
		t.Fatalf("ParseTurnstile: %v", err)
	}

	cell := prog.Cells[0]
	if cell.Recovery == nil {
		t.Fatal("expected recovery policy")
	}
	if cell.Recovery.MaxRetries != 2 {
		t.Errorf("max retries = %d, want 2", cell.Recovery.MaxRetries)
	}
}

func TestParseTurnstileSoftCell(t *testing.T) {
	source := `⊢ greet
  given name ≡ "Alice"
  yield message
  ∴ Generate a short, friendly greeting for «name».
    Just one sentence.
  ⊨ message is a string`

	prog, err := ParseTurnstile(source)
	if err != nil {
		t.Fatalf("ParseTurnstile: %v", err)
	}

	cell := prog.Cells[0]
	if cell.BodyType != BodySoft {
		t.Errorf("body type = %q, want soft", cell.BodyType)
	}
	if !strings.Contains(cell.Body, "greeting") {
		t.Errorf("body = %q, expected greeting prompt", cell.Body)
	}
}

// --- Syntax detection ---

func TestDetectSyntax(t *testing.T) {
	tests := []struct {
		input string
		want  string
	}{
		{"⊢ add\n  given a ≡ 3", "turnstile"},
		{"## mol\n# cell : llm", "molecule"},
		{"-- comment\n⊢ foo", "turnstile"},
		{"-- comment\n## bar", "molecule"},
	}

	for _, tt := range tests {
		got := DetectSyntax(tt.input)
		if got != tt.want {
			t.Errorf("DetectSyntax(%q...) = %q, want %q", tt.input[:20], got, tt.want)
		}
	}
}

// --- Oracle classification ---

func TestClassifyOracle(t *testing.T) {
	tests := []struct {
		assertion string
		want      string
	}{
		{"sum = 8", "deterministic"},
		{"result = 16", "deterministic"},
		{"count > 0", "deterministic"},
		{"if x then y = 5", "conditional"},
		{"message is a string", "semantic"},
		{"sorted is in ascending order", "semantic"},
	}

	for _, tt := range tests {
		got := classifyOracle(tt.assertion)
		if got != tt.want {
			t.Errorf("classifyOracle(%q) = %q, want %q", tt.assertion, got, tt.want)
		}
	}
}

// --- Oracle checking ---

func TestCheckOraclesDeterministic(t *testing.T) {
	oracles := []OracleRow{
		{OracleType: "deterministic", Assertion: "sum = 8"},
		{OracleType: "deterministic", Assertion: "result = 16"},
	}
	outputs := map[string]interface{}{"sum": 8.0, "result": 16.0}
	bindings := map[string]interface{}{}

	allPass, results := CheckOracles(oracles, outputs, bindings)
	if !allPass {
		t.Errorf("expected all pass, got failures: %v", results)
	}

	// Test failure
	outputs["sum"] = 7.0
	allPass, results = CheckOracles(oracles, outputs, bindings)
	if allPass {
		t.Error("expected failure when sum=7")
	}
}

// --- SQL emission ---

func TestEmitSQL(t *testing.T) {
	prog := &RetortProgram{
		Name:       "test",
		SourceFile: "test.cell",
		Cells: []RetortCell{
			{
				Name:     "add",
				BodyType: BodyHard,
				Body:     "sum ← a + b",
				Givens: []RetortGiven{
					{Name: "a", HasDefault: true, Default: strPtr("3")},
					{Name: "b", HasDefault: true, Default: strPtr("5")},
				},
				Yields: []RetortYield{
					{Name: "sum"},
				},
				Oracles: []RetortOracle{
					{Assertion: "sum = 8", Ordinal: 0},
				},
			},
		},
	}

	sql := EmitSQL(prog)
	if !strings.Contains(sql, "INSERT INTO programs") {
		t.Error("expected INSERT INTO programs")
	}
	if !strings.Contains(sql, "INSERT INTO cells") {
		t.Error("expected INSERT INTO cells")
	}
	if !strings.Contains(sql, "INSERT INTO givens") {
		t.Error("expected INSERT INTO givens")
	}
	if !strings.Contains(sql, "INSERT INTO yields") {
		t.Error("expected INSERT INTO yields")
	}
	if !strings.Contains(sql, "INSERT INTO oracles") {
		t.Error("expected INSERT INTO oracles")
	}
}

// --- Dispatch (hard cells only, no DB needed) ---

func TestDispatchHardAddDouble(t *testing.T) {
	// Simulate add cell
	addCell := &CellRow{
		Name:     "add",
		BodyType: "hard",
		Body:     "sum ← a + b",
	}
	addYields := []YieldRow{{FieldName: "sum"}}
	addBindings := map[string]interface{}{"a": 3.0, "b": 5.0}

	result := Dispatch(nil, addCell, addYields, addBindings)
	if result.Err != nil {
		t.Fatalf("dispatch add: %v", result.Err)
	}
	sum, _ := toFloat(result.Outputs["sum"])
	if sum != 8 {
		t.Errorf("add: sum = %v, want 8", result.Outputs["sum"])
	}

	// Simulate double cell
	doubleCell := &CellRow{
		Name:     "double",
		BodyType: "hard",
		Body:     "result ← add→sum * 2",
	}
	doubleYields := []YieldRow{{FieldName: "result"}}
	doubleBindings := map[string]interface{}{"add→sum": 8.0}

	result = Dispatch(nil, doubleCell, doubleYields, doubleBindings)
	if result.Err != nil {
		t.Fatalf("dispatch double: %v", result.Err)
	}
	dblResult, _ := toFloat(result.Outputs["result"])
	if dblResult != 16 {
		t.Errorf("double: result = %v, want 16", result.Outputs["result"])
	}
}

func TestDispatchHardAbsValue(t *testing.T) {
	// check-sign: if n < 0 then "negative" else "positive"
	cell := &CellRow{
		Name:     "check-sign",
		BodyType: "hard",
		Body:     `sign ← if n < 0 then "negative" else "positive"`,
	}
	yields := []YieldRow{{FieldName: "sign"}}
	bindings := map[string]interface{}{"n": -7.0}

	result := Dispatch(nil, cell, yields, bindings)
	if result.Err != nil {
		t.Fatalf("dispatch check-sign: %v", result.Err)
	}
	if result.Outputs["sign"] != "negative" {
		t.Errorf("check-sign: sign = %v, want 'negative'", result.Outputs["sign"])
	}

	// negate: 0 - n
	negCell := &CellRow{
		Name:     "negate",
		BodyType: "hard",
		Body:     "result ← 0 - n",
	}
	negYields := []YieldRow{{FieldName: "result"}}
	negBindings := map[string]interface{}{"n": -7.0}

	result = Dispatch(nil, negCell, negYields, negBindings)
	if result.Err != nil {
		t.Fatalf("dispatch negate: %v", result.Err)
	}
	negResult, _ := toFloat(result.Outputs["result"])
	if negResult != 7 {
		t.Errorf("negate: result = %v, want 7", result.Outputs["result"])
	}
}

func TestDispatchSoftDryRun(t *testing.T) {
	cell := &CellRow{
		Name:     "greet",
		BodyType: "soft",
		Body:     "Generate a greeting for «name»",
	}
	yields := []YieldRow{{FieldName: "message"}}
	bindings := map[string]interface{}{"name": "Alice"}

	result := dispatchDryRun(cell, yields, bindings)
	if result.Err != nil {
		t.Fatalf("dispatch greet: %v", result.Err)
	}
	msg := result.Outputs["message"].(string)
	if !strings.Contains(msg, "dry-run") {
		t.Errorf("expected dry-run placeholder, got %q", msg)
	}
}

// --- Template interpolation ---

func TestInterpolate(t *testing.T) {
	bindings := map[string]interface{}{
		"name":          "Alice",
		"data→items":    []interface{}{1.0, 2.0, 3.0},
		"check→sign":    "negative",
	}

	tests := []struct {
		input string
		want  string
	}{
		{"Hello «name»!", "Hello Alice!"},
		{"Items: «items»", "Items: [1 2 3]"},
		{"Sign is «sign»", "Sign is negative"},
		{"Hello {{name}}!", "Hello Alice!"},
	}

	for _, tt := range tests {
		got := Interpolate(tt.input, bindings)
		if got != tt.want {
			t.Errorf("Interpolate(%q) = %q, want %q", tt.input, got, tt.want)
		}
	}
}

// --- Decompile ---

func TestDecompileCell(t *testing.T) {
	cell := &CellRow{
		Name:     "add",
		BodyType: "hard",
		Body:     "sum ← a + b",
	}
	givens := []GivenRow{
		{ParamName: "a", HasDefault: true, DefaultValue: "3"},
		{ParamName: "b", HasDefault: true, DefaultValue: "5"},
	}
	yields := []YieldRow{
		{FieldName: "sum"},
	}
	oracles := []OracleRow{
		{OracleType: "deterministic", Assertion: "sum = 8"},
	}

	source := renderTurnstile(cell, givens, yields, oracles)

	if !strings.Contains(source, "⊢ add") {
		t.Error("expected ⊢ add in output")
	}
	if !strings.Contains(source, "given a ≡ 3") {
		t.Errorf("expected 'given a ≡ 3', got: %s", source)
	}
	if !strings.Contains(source, "yield sum") {
		t.Error("expected yield sum")
	}
	if !strings.Contains(source, "⊢= sum ← a + b") {
		t.Errorf("expected hard body, got: %s", source)
	}
	if !strings.Contains(source, "⊨ sum = 8") {
		t.Error("expected oracle")
	}
}

// --- Full pipeline test (parse → dispatch, no DB) ---

func TestFullPipelineAddDouble(t *testing.T) {
	source := `⊢ add
  given a ≡ 3
  given b ≡ 5
  yield sum
  ⊢= sum ← a + b
  ⊨ sum = 8

⊢ double
  given add→sum
  yield result
  ⊢= result ← add→sum * 2
  ⊨ result = 16`

	prog, err := ParseTurnstile(source)
	if err != nil {
		t.Fatalf("parse: %v", err)
	}

	// Evaluate 'add'
	add := prog.Cells[0]
	addBindings := map[string]interface{}{
		"a": parseStoredValue(*add.Givens[0].Default),
		"b": parseStoredValue(*add.Givens[1].Default),
	}
	addCell := &CellRow{Name: add.Name, BodyType: string(add.BodyType), Body: add.Body}
	addYields := []YieldRow{{FieldName: "sum"}}
	addResult := Dispatch(nil, addCell, addYields, addBindings)
	if addResult.Err != nil {
		t.Fatalf("dispatch add: %v", addResult.Err)
	}
	sumVal, _ := toFloat(addResult.Outputs["sum"])
	if sumVal != 8 {
		t.Fatalf("add sum = %v, want 8", sumVal)
	}

	// Check oracle
	addOracles := []OracleRow{{OracleType: "deterministic", Assertion: "sum = 8"}}
	pass, _ := CheckOracles(addOracles, addResult.Outputs, addBindings)
	if !pass {
		t.Error("add oracle failed")
	}

	// Evaluate 'double'
	dbl := prog.Cells[1]
	dblBindings := map[string]interface{}{"add→sum": sumVal}
	dblCell := &CellRow{Name: dbl.Name, BodyType: string(dbl.BodyType), Body: dbl.Body}
	dblYields := []YieldRow{{FieldName: "result"}}
	dblResult := Dispatch(nil, dblCell, dblYields, dblBindings)
	if dblResult.Err != nil {
		t.Fatalf("dispatch double: %v", dblResult.Err)
	}
	resultVal, _ := toFloat(dblResult.Outputs["result"])
	if resultVal != 16 {
		t.Fatalf("double result = %v, want 16", resultVal)
	}

	// Check oracle
	dblOracles := []OracleRow{{OracleType: "deterministic", Assertion: "result = 16"}}
	pass, _ = CheckOracles(dblOracles, dblResult.Outputs, dblBindings)
	if !pass {
		t.Error("double oracle failed")
	}
}

func TestFullPipelineAbsValue(t *testing.T) {
	source := `⊢ check-sign
  given n ≡ -7
  yield sign
  ⊢= sign ← if n < 0 then "negative" else "positive"
  ⊨ sign = "negative"

⊢ negate
  given check-sign→sign where sign = "negative"
  given n ≡ -7
  yield result
  ⊢= result ← 0 - n
  ⊨ result = 7

⊢ pass-through
  given check-sign→sign where sign = "positive"
  given n ≡ -7
  yield result
  ⊢= result ← n`

	prog, err := ParseTurnstile(source)
	if err != nil {
		t.Fatalf("parse: %v", err)
	}

	// Evaluate check-sign
	cs := prog.Cells[0]
	csBindings := map[string]interface{}{
		"n": parseStoredValue(*cs.Givens[0].Default),
	}
	csCell := &CellRow{Name: cs.Name, BodyType: string(cs.BodyType), Body: cs.Body}
	csYields := []YieldRow{{FieldName: "sign"}}
	csResult := Dispatch(nil, csCell, csYields, csBindings)
	if csResult.Err != nil {
		t.Fatalf("dispatch check-sign: %v", csResult.Err)
	}
	if csResult.Outputs["sign"] != "negative" {
		t.Fatalf("check-sign: sign = %v, want 'negative'", csResult.Outputs["sign"])
	}

	// Check guard on negate: sign = "negative" should pass
	negGuard := prog.Cells[1].Givens[0].GuardExpr // sign = "negative"
	negBindings := map[string]interface{}{
		"sign":              csResult.Outputs["sign"],
		"check-sign→sign":   csResult.Outputs["sign"],
		"n":                 -7.0,
	}
	guardResult, err := EvalExpr(negGuard, negBindings)
	if err != nil {
		t.Fatalf("guard eval: %v", err)
	}
	if !toBool(guardResult) {
		t.Error("negate guard should pass for negative")
	}

	// Evaluate negate
	neg := prog.Cells[1]
	negCell := &CellRow{Name: neg.Name, BodyType: string(neg.BodyType), Body: neg.Body}
	negYields := []YieldRow{{FieldName: "result"}}
	negResult := Dispatch(nil, negCell, negYields, negBindings)
	if negResult.Err != nil {
		t.Fatalf("dispatch negate: %v", negResult.Err)
	}
	negVal, _ := toFloat(negResult.Outputs["result"])
	if negVal != 7 {
		t.Fatalf("negate result = %v, want 7", negVal)
	}

	// Check guard on pass-through: sign = "positive" should FAIL (sign is "negative")
	ptGuard := prog.Cells[2].Givens[0].GuardExpr // sign = "positive"
	ptBindings := map[string]interface{}{
		"sign":              csResult.Outputs["sign"],
		"check-sign→sign":   csResult.Outputs["sign"],
	}
	ptGuardResult, err := EvalExpr(ptGuard, ptBindings)
	if err != nil {
		t.Fatalf("pt guard eval: %v", err)
	}
	if toBool(ptGuardResult) {
		t.Error("pass-through guard should fail for negative")
	}
}

// --- SQL round-trip ---

func TestSQLRoundTrip(t *testing.T) {
	source := `⊢ add
  given a ≡ 3
  given b ≡ 5
  yield sum
  ⊢= sum ← a + b
  ⊨ sum = 8`

	prog, err := ParseTurnstile(source)
	if err != nil {
		t.Fatalf("parse: %v", err)
	}
	prog.Name = "test-add"
	prog.SourceFile = "test.cell"

	sql := EmitSQL(prog)

	// Verify SQL structure
	if strings.Count(sql, "INSERT INTO programs") != 1 {
		t.Error("expected 1 program INSERT")
	}
	if strings.Count(sql, "INSERT INTO cells") != 1 {
		t.Error("expected 1 cell INSERT")
	}
	if strings.Count(sql, "INSERT INTO givens") != 2 {
		t.Errorf("expected 2 given INSERTs, got %d", strings.Count(sql, "INSERT INTO givens"))
	}
	if strings.Count(sql, "INSERT INTO yields") != 1 {
		t.Error("expected 1 yield INSERT")
	}
	if strings.Count(sql, "INSERT INTO oracles") != 1 {
		t.Error("expected 1 oracle INSERT")
	}
}

// --- Recovery ---

func TestDecideRecovery(t *testing.T) {
	cell := &CellRow{RetryCount: 0, MaxRetries: 3}
	results := []OracleResult{{Pass: false, Assertion: "x = 5", Reason: "got 3"}}

	decision := DecideRecovery(cell, results)
	if decision.Action != "retry" {
		t.Errorf("expected retry, got %s", decision.Action)
	}

	cell.RetryCount = 3
	decision = DecideRecovery(cell, results)
	if decision.Action != "bottom" {
		t.Errorf("expected bottom, got %s", decision.Action)
	}
}

// --- Helper ---
func strPtr(s string) *string {
	return &s
}
