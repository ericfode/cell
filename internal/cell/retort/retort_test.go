package retort

import (
	"strings"
	"testing"
)

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

	result := Dispatch(nil, addCell, addYields, addBindings, ModeDryRun)
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

	result = Dispatch(nil, doubleCell, doubleYields, doubleBindings, ModeDryRun)
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

	result := Dispatch(nil, cell, yields, bindings, ModeDryRun)
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

	result = Dispatch(nil, negCell, negYields, negBindings, ModeDryRun)
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

	result := Dispatch(nil, cell, yields, bindings, ModeDryRun)
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
	addResult := Dispatch(nil, addCell, addYields, addBindings, ModeDryRun)
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
	dblResult := Dispatch(nil, dblCell, dblYields, dblBindings, ModeDryRun)
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
	csResult := Dispatch(nil, csCell, csYields, csBindings, ModeDryRun)
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
	negResult := Dispatch(nil, negCell, negYields, negBindings, ModeDryRun)
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

// --- Iterator predicate tests ---

func TestEvalExprAllPredicate(t *testing.T) {
	// all(i, sorted[i] <= sorted[i+1]) — the sort-proof pattern
	sorted := []interface{}{1.0, 2.0, 3.0, 4.0, 5.0}
	bindings := map[string]interface{}{"sorted": sorted}

	result, err := EvalExpr("all(i, sorted[i] <= sorted[i+1])", bindings)
	if err != nil {
		t.Fatalf("EvalExpr: %v", err)
	}
	if result != true {
		t.Errorf("expected true for sorted list, got %v", result)
	}

	// Unsorted list should fail
	unsorted := []interface{}{3.0, 1.0, 2.0}
	bindings["sorted"] = unsorted
	result, err = EvalExpr("all(i, sorted[i] <= sorted[i+1])", bindings)
	if err != nil {
		t.Fatalf("EvalExpr: %v", err)
	}
	if result != false {
		t.Errorf("expected false for unsorted list, got %v", result)
	}
}

func TestEvalExprAnyPredicate(t *testing.T) {
	items := []interface{}{1.0, 2.0, 5.0, 3.0}
	bindings := map[string]interface{}{"items": items}

	result, err := EvalExpr("any(i, items[i] > 4)", bindings)
	if err != nil {
		t.Fatalf("EvalExpr: %v", err)
	}
	if result != true {
		t.Errorf("expected true (5 > 4), got %v", result)
	}

	small := []interface{}{1.0, 2.0, 3.0}
	bindings["items"] = small
	result, err = EvalExpr("any(i, items[i] > 4)", bindings)
	if err != nil {
		t.Fatalf("EvalExpr: %v", err)
	}
	if result != false {
		t.Errorf("expected false (no element > 4), got %v", result)
	}
}

func TestEvalExprAllSimpleForm(t *testing.T) {
	// all([true, true, true]) — simple form
	result, err := EvalExpr("all([true, true, true])", nil)
	if err != nil {
		t.Fatalf("EvalExpr: %v", err)
	}
	if result != true {
		t.Errorf("expected true, got %v", result)
	}

	result, err = EvalExpr("all([true, false, true])", nil)
	if err != nil {
		t.Fatalf("EvalExpr: %v", err)
	}
	if result != false {
		t.Errorf("expected false, got %v", result)
	}
}

func TestEvalExprFilterMapCount(t *testing.T) {
	items := []interface{}{1.0, 2.0, 3.0, 4.0, 5.0}
	bindings := map[string]interface{}{"items": items}

	// filter(items, x, x > 3) → [4, 5]
	result, err := EvalExpr("filter(items, x, x > 3)", bindings)
	if err != nil {
		t.Fatalf("filter: %v", err)
	}
	lst, ok := result.([]interface{})
	if !ok {
		t.Fatalf("filter: expected list, got %T", result)
	}
	if len(lst) != 2 {
		t.Errorf("filter: expected 2 elements, got %d: %v", len(lst), lst)
	}

	// map(items, x, x * 2) → [2, 4, 6, 8, 10]
	result, err = EvalExpr("map(items, x, x * 2)", bindings)
	if err != nil {
		t.Fatalf("map: %v", err)
	}
	lst, ok = result.([]interface{})
	if !ok {
		t.Fatalf("map: expected list, got %T", result)
	}
	if len(lst) != 5 {
		t.Errorf("map: expected 5 elements, got %d", len(lst))
	} else {
		first, _ := toFloat(lst[0])
		last, _ := toFloat(lst[4])
		if first != 2 || last != 10 {
			t.Errorf("map: expected [2,...,10], got %v", lst)
		}
	}

	// count(items, x, x > 3) → 2
	result, err = EvalExpr("count(items, x, x > 3)", bindings)
	if err != nil {
		t.Fatalf("count: %v", err)
	}
	countVal, _ := toFloat(result)
	if countVal != 2 {
		t.Errorf("count: expected 2, got %v", result)
	}
}

func TestEvalExprMultiset(t *testing.T) {
	// multiset([3,1,2]) = multiset([1,2,3]) — permutation check
	bindings := map[string]interface{}{
		"a": []interface{}{3.0, 1.0, 2.0},
		"b": []interface{}{1.0, 2.0, 3.0},
	}
	result, err := EvalExpr("multiset(a) = multiset(b)", bindings)
	if err != nil {
		t.Fatalf("EvalExpr: %v", err)
	}
	if result != true {
		t.Errorf("expected true for same multiset, got %v", result)
	}
}

func TestEvalExprRange(t *testing.T) {
	result, err := EvalExpr("range(5)", nil)
	if err != nil {
		t.Fatalf("range: %v", err)
	}
	lst, ok := result.([]interface{})
	if !ok {
		t.Fatalf("range: expected list, got %T", result)
	}
	if len(lst) != 5 {
		t.Errorf("range: expected 5 elements, got %d", len(lst))
	}
}

func TestEvalExprFlatten(t *testing.T) {
	bindings := map[string]interface{}{
		"nested": []interface{}{
			[]interface{}{1.0, 2.0},
			[]interface{}{3.0, 4.0},
		},
	}
	result, err := EvalExpr("flatten(nested)", bindings)
	if err != nil {
		t.Fatalf("flatten: %v", err)
	}
	lst, ok := result.([]interface{})
	if !ok {
		t.Fatalf("flatten: expected list, got %T", result)
	}
	if len(lst) != 4 {
		t.Errorf("flatten: expected 4 elements, got %d: %v", len(lst), lst)
	}
}

func TestEvalExprTakeDrop(t *testing.T) {
	bindings := map[string]interface{}{
		"items": []interface{}{1.0, 2.0, 3.0, 4.0, 5.0},
	}

	// take(items, 3) → [1, 2, 3]
	result, err := EvalExpr("take(items, 3)", bindings)
	if err != nil {
		t.Fatalf("take: %v", err)
	}
	lst, ok := result.([]interface{})
	if !ok || len(lst) != 3 {
		t.Errorf("take: expected 3 elements, got %v", result)
	}

	// drop(items, 2) → [3, 4, 5]
	result, err = EvalExpr("drop(items, 2)", bindings)
	if err != nil {
		t.Fatalf("drop: %v", err)
	}
	lst, ok = result.([]interface{})
	if !ok || len(lst) != 3 {
		t.Errorf("drop: expected 3 elements, got %v", result)
	}
}

func TestEvalExprMatches(t *testing.T) {
	bindings := map[string]interface{}{"s": "hello world 42"}

	result, err := EvalExpr(`matches(s, "\\d+")`, bindings)
	if err != nil {
		t.Fatalf("matches: %v", err)
	}
	if result != true {
		t.Errorf("expected true for digit match, got %v", result)
	}

	result, err = EvalExpr(`matches(s, "^[A-Z]")`, bindings)
	if err != nil {
		t.Fatalf("matches: %v", err)
	}
	if result != false {
		t.Errorf("expected false (no uppercase start), got %v", result)
	}
}

// --- Full pipeline: sort-proof (hard cells only, simulates sorted output) ---

func TestFullPipelineSortProof(t *testing.T) {
	source := `⊢ data
  yield items ≡ [4, 1, 7, 3, 9, 2]

⊢ verify-permutation
  given sort→sorted
  given data→items
  yield is-permutation
  ⊢= is-permutation ← multiset(sorted) = multiset(items)
  ⊨ is-permutation = true

⊢ verify-order
  given sort→sorted
  yield is-ordered
  ⊢= is-ordered ← all(i, sorted[i] <= sorted[i+1])
  ⊨ is-ordered = true

⊢ certificate
  given sort→sorted
  given verify-permutation→is-permutation
  given verify-order→is-ordered
  yield proof-status
  ⊢= proof-status ← if is-permutation and is-ordered then "certified" else "rejected"
  ⊨ proof-status = "certified"`

	prog, err := ParseTurnstile(source)
	if err != nil {
		t.Fatalf("parse: %v", err)
	}

	// data cell yields items = [4,1,7,3,9,2] (frozen on load via ≡)
	dataItems := []interface{}{4.0, 1.0, 7.0, 3.0, 9.0, 2.0}

	// Simulate the soft 'sort' cell having produced correct sorted output
	sortedItems := []interface{}{1.0, 2.0, 3.0, 4.0, 7.0, 9.0}

	// verify-permutation: multiset(sorted) = multiset(items)
	vpCell := prog.Cells[1]
	vpBindings := map[string]interface{}{
		"sorted":     sortedItems,
		"items":      dataItems,
		"sort→sorted": sortedItems,
		"data→items":  dataItems,
	}
	vpCellRow := &CellRow{Name: vpCell.Name, BodyType: string(vpCell.BodyType), Body: vpCell.Body}
	vpYields := []YieldRow{{FieldName: "is-permutation"}}
	vpResult := Dispatch(nil, vpCellRow, vpYields, vpBindings, ModeDryRun)
	if vpResult.Err != nil {
		t.Fatalf("dispatch verify-permutation: %v", vpResult.Err)
	}
	isPerm := vpResult.Outputs["is-permutation"]
	if isPerm != true {
		t.Errorf("verify-permutation: expected true, got %v (%T)", isPerm, isPerm)
	}

	// verify-order: all(i, sorted[i] <= sorted[i+1])
	voCell := prog.Cells[2]
	voBindings := map[string]interface{}{
		"sorted":     sortedItems,
		"sort→sorted": sortedItems,
	}
	voCellRow := &CellRow{Name: voCell.Name, BodyType: string(voCell.BodyType), Body: voCell.Body}
	voYields := []YieldRow{{FieldName: "is-ordered"}}
	voResult := Dispatch(nil, voCellRow, voYields, voBindings, ModeDryRun)
	if voResult.Err != nil {
		t.Fatalf("dispatch verify-order: %v", voResult.Err)
	}
	isOrdered := voResult.Outputs["is-ordered"]
	if isOrdered != true {
		t.Errorf("verify-order: expected true, got %v (%T)", isOrdered, isOrdered)
	}

	// certificate: if is-permutation and is-ordered then "certified" else "rejected"
	certCell := prog.Cells[3]
	certBindings := map[string]interface{}{
		"is-permutation":               isPerm,
		"is-ordered":                    isOrdered,
		"sort→sorted":                   sortedItems,
		"verify-permutation→is-permutation": isPerm,
		"verify-order→is-ordered":       isOrdered,
	}
	certCellRow := &CellRow{Name: certCell.Name, BodyType: string(certCell.BodyType), Body: certCell.Body}
	certYields := []YieldRow{{FieldName: "proof-status"}}
	certResult := Dispatch(nil, certCellRow, certYields, certBindings, ModeDryRun)
	if certResult.Err != nil {
		t.Fatalf("dispatch certificate: %v", certResult.Err)
	}
	status := certResult.Outputs["proof-status"]
	if status != "certified" {
		t.Errorf("certificate: expected 'certified', got %v", status)
	}

	// Now test with a WRONG sort (not a permutation) — should get "rejected"
	wrongSorted := []interface{}{1.0, 2.0, 3.0, 4.0, 5.0, 6.0}
	vpBindings["sorted"] = wrongSorted
	vpBindings["sort→sorted"] = wrongSorted
	vpResult = Dispatch(nil, vpCellRow, vpYields, vpBindings, ModeDryRun)
	if vpResult.Err != nil {
		t.Fatalf("dispatch verify-permutation (wrong): %v", vpResult.Err)
	}
	if vpResult.Outputs["is-permutation"] != false {
		t.Errorf("verify-permutation with wrong sort: expected false, got %v", vpResult.Outputs["is-permutation"])
	}
}

// --- Full sort-proof with simulate mode (the real deal) ---

func TestFullPipelineSortProofSimulated(t *testing.T) {
	// This test proves the complete sort-proof Cell program works end-to-end
	// with a simulated LLM providing the sort output.
	source := `⊢ data
  yield items ≡ [4, 1, 7, 3, 9, 2]

⊢ sort
  given data→items
  yield sorted
  ∴ Sort «items» in ascending order.
  ⊨ sorted is a permutation of «data→items»
  ⊨ sorted is in ascending order
  ⊨? on failure:
    retry with «oracle.failures» appended to prompt
    max 2

⊢ verify-permutation
  given sort→sorted
  given data→items
  yield is-permutation
  ⊢= is-permutation ← multiset(sorted) = multiset(items)
  ⊨ is-permutation = true

⊢ verify-order
  given sort→sorted
  yield is-ordered
  ⊢= is-ordered ← all(i, sorted[i] <= sorted[i+1])
  ⊨ is-ordered = true

⊢ certificate
  given sort→sorted
  given verify-permutation→is-permutation
  given verify-order→is-ordered
  yield proof-status
  ⊢= proof-status ← if is-permutation and is-ordered then "certified" else "rejected"
  ⊨ proof-status = "certified"`

	prog, err := ParseTurnstile(source)
	if err != nil {
		t.Fatalf("parse: %v", err)
	}

	if len(prog.Cells) != 5 {
		t.Fatalf("expected 5 cells, got %d", len(prog.Cells))
	}

	// Set up simulation data for the soft 'sort' cell
	SimulationData = map[string]map[string]interface{}{
		"sort": {"sorted": []interface{}{1.0, 2.0, 3.0, 4.0, 7.0, 9.0}},
	}
	defer func() { SimulationData = nil }()

	// Step through the program manually:
	// 1. data cell → frozen on load (yield items ≡ [4,1,7,3,9,2])
	dataItems := []interface{}{4.0, 1.0, 7.0, 3.0, 9.0, 2.0}

	// 2. sort cell → simulated soft dispatch
	sortCell := &CellRow{Name: "sort", BodyType: "soft", Body: prog.Cells[1].Body}
	sortYields := []YieldRow{{FieldName: "sorted"}}
	sortBindings := map[string]interface{}{"items": dataItems, "data→items": dataItems}
	sortResult := Dispatch(nil, sortCell, sortYields, sortBindings, ModeSimulate)
	if sortResult.Err != nil {
		t.Fatalf("sort dispatch: %v", sortResult.Err)
	}
	sortedItems := sortResult.Outputs["sorted"].([]interface{})

	// 3. verify-permutation → hard dispatch
	vpBindings := map[string]interface{}{
		"sorted": sortedItems, "items": dataItems,
		"sort→sorted": sortedItems, "data→items": dataItems,
	}
	vpCell := &CellRow{Name: "verify-permutation", BodyType: "hard", Body: prog.Cells[2].Body}
	vpResult := Dispatch(nil, vpCell, []YieldRow{{FieldName: "is-permutation"}}, vpBindings, ModeSimulate)
	if vpResult.Err != nil {
		t.Fatalf("verify-perm: %v", vpResult.Err)
	}
	if vpResult.Outputs["is-permutation"] != true {
		t.Fatalf("expected is-permutation=true, got %v", vpResult.Outputs["is-permutation"])
	}

	// 4. verify-order → hard dispatch (uses all(i, sorted[i] <= sorted[i+1]))
	voBindings := map[string]interface{}{"sorted": sortedItems, "sort→sorted": sortedItems}
	voCell := &CellRow{Name: "verify-order", BodyType: "hard", Body: prog.Cells[3].Body}
	voResult := Dispatch(nil, voCell, []YieldRow{{FieldName: "is-ordered"}}, voBindings, ModeSimulate)
	if voResult.Err != nil {
		t.Fatalf("verify-order: %v", voResult.Err)
	}
	if voResult.Outputs["is-ordered"] != true {
		t.Fatalf("expected is-ordered=true, got %v", voResult.Outputs["is-ordered"])
	}

	// 5. certificate → hard dispatch
	certBindings := map[string]interface{}{
		"is-permutation": true, "is-ordered": true,
		"sort→sorted": sortedItems,
		"verify-permutation→is-permutation": true,
		"verify-order→is-ordered":           true,
	}
	certCell := &CellRow{Name: "certificate", BodyType: "hard", Body: prog.Cells[4].Body}
	certResult := Dispatch(nil, certCell, []YieldRow{{FieldName: "proof-status"}}, certBindings, ModeSimulate)
	if certResult.Err != nil {
		t.Fatalf("certificate: %v", certResult.Err)
	}
	if certResult.Outputs["proof-status"] != "certified" {
		t.Fatalf("expected 'certified', got %v", certResult.Outputs["proof-status"])
	}

	// 6. Check oracles
	certOracles := []OracleRow{{OracleType: "deterministic", Assertion: `proof-status = "certified"`}}
	pass, _ := CheckOracles(certOracles, certResult.Outputs, certBindings)
	if !pass {
		t.Error("certificate oracle failed")
	}
}

// --- Simulate mode ---

func TestDispatchSoftSimulate(t *testing.T) {
	SimulationData = map[string]map[string]interface{}{
		"sort": {"sorted": []interface{}{1.0, 2.0, 3.0}},
	}
	defer func() { SimulationData = nil }()

	cell := &CellRow{
		Name:     "sort",
		BodyType: "soft",
		Body:     "Sort «items» ascending",
	}
	yields := []YieldRow{{FieldName: "sorted"}}
	bindings := map[string]interface{}{"items": []interface{}{3.0, 1.0, 2.0}}

	result := Dispatch(nil, cell, yields, bindings, ModeSimulate)
	if result.Err != nil {
		t.Fatalf("simulate dispatch: %v", result.Err)
	}
	sorted, ok := result.Outputs["sorted"].([]interface{})
	if !ok || len(sorted) != 3 {
		t.Errorf("expected [1,2,3], got %v", result.Outputs["sorted"])
	}
}

// --- Helper ---
func strPtr(s string) *string {
	return &s
}
