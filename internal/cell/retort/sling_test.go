package retort

import (
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func TestSlingFormulaBasic(t *testing.T) {
	// A simple program with two soft cells and a dependency
	prog := &RetortProgram{
		Name: "test-program",
		Cells: []RetortCell{
			{
				Name:     "greet",
				BodyType: BodySoft,
				Body:     "Say hello to the user.",
				Yields:   []RetortYield{{Name: "message"}},
				Oracles: []RetortOracle{
					{Assertion: "output is valid JSON", Ordinal: 0},
					{Assertion: "keys present: message", Ordinal: 1},
				},
			},
			{
				Name:     "wrap",
				BodyType: BodySoft,
				Body:     "Take this greeting and add an emoji:\n«greet→message»",
				Givens: []RetortGiven{
					{Name: "message", SourceCell: "greet", SourceField: "message"},
				},
				Yields: []RetortYield{{Name: "text"}, {Name: "emoji"}},
			},
		},
	}

	toml := SlingFormula(prog, "test-program")

	// Verify TOML structure
	if !strings.Contains(toml, `formula = "cell-dispatch-test-program"`) {
		t.Errorf("missing formula name in output:\n%s", toml)
	}
	if !strings.Contains(toml, `type = "workflow"`) {
		t.Errorf("missing type in output:\n%s", toml)
	}
	if !strings.Contains(toml, "version = 1") {
		t.Errorf("missing version in output:\n%s", toml)
	}

	// Verify steps
	if !strings.Contains(toml, `id = "greet"`) {
		t.Errorf("missing greet step:\n%s", toml)
	}
	if !strings.Contains(toml, `id = "wrap"`) {
		t.Errorf("missing wrap step:\n%s", toml)
	}

	// Verify greet has oracle-based acceptance
	if !strings.Contains(toml, "output is valid JSON; keys present: message") {
		t.Errorf("missing oracle acceptance for greet:\n%s", toml)
	}

	// Verify wrap has yield-based acceptance (no oracles)
	if !strings.Contains(toml, "Yield fields populated: text, emoji") {
		t.Errorf("missing yield acceptance for wrap:\n%s", toml)
	}

	// Verify wrap needs greet
	if !strings.Contains(toml, `needs = ["greet"]`) {
		t.Errorf("missing dependency from wrap to greet:\n%s", toml)
	}

	// Verify yield_fields metadata
	if !strings.Contains(toml, `yield_fields = ["text", "emoji"]`) {
		t.Errorf("missing yield_fields for wrap:\n%s", toml)
	}

	// Verify vars section
	if !strings.Contains(toml, "[vars.program]") {
		t.Errorf("missing vars.program:\n%s", toml)
	}
	if !strings.Contains(toml, "required = true") {
		t.Errorf("missing required = true in vars:\n%s", toml)
	}
}

func TestSlingFormulaHardCellsExcluded(t *testing.T) {
	prog := &RetortProgram{
		Name: "mixed",
		Cells: []RetortCell{
			{
				Name:     "config",
				BodyType: BodyHard,
				Body:     "5 + 3",
				Yields:   []RetortYield{{Name: "value"}},
			},
			{
				Name:     "analyze",
				BodyType: BodySoft,
				Body:     "Analyze the data with limit «config→value»",
				Givens: []RetortGiven{
					{Name: "value", SourceCell: "config", SourceField: "value"},
				},
				Yields: []RetortYield{{Name: "result"}},
			},
			{
				Name:     "summarize",
				BodyType: BodySoft,
				Body:     "Summarize: «analyze→result»",
				Givens: []RetortGiven{
					{Name: "result", SourceCell: "analyze", SourceField: "result"},
				},
				Yields: []RetortYield{{Name: "summary"}},
			},
		},
	}

	toml := SlingFormula(prog, "mixed")

	// Hard cell should NOT appear as a step
	if strings.Contains(toml, `id = "config"`) {
		t.Errorf("hard cell 'config' should not be a formula step:\n%s", toml)
	}

	// Soft cells should appear
	if !strings.Contains(toml, `id = "analyze"`) {
		t.Errorf("missing analyze step:\n%s", toml)
	}
	if !strings.Contains(toml, `id = "summarize"`) {
		t.Errorf("missing summarize step:\n%s", toml)
	}

	// analyze should NOT need config (config is hard)
	// Check that analyze has no needs line
	lines := strings.Split(toml, "\n")
	inAnalyze := false
	for _, line := range lines {
		if strings.Contains(line, `id = "analyze"`) {
			inAnalyze = true
		}
		if inAnalyze && strings.Contains(line, `id = "summarize"`) {
			break
		}
		if inAnalyze && strings.HasPrefix(line, "needs") {
			t.Errorf("analyze should not have needs (config is hard):\n%s", toml)
		}
	}

	// summarize should need analyze
	if !strings.Contains(toml, `needs = ["analyze"]`) {
		t.Errorf("summarize should need analyze:\n%s", toml)
	}
}

func TestSlingFormulaFromFile(t *testing.T) {
	examplesDir := filepath.Join("..", "..", "..", "docs", "examples")
	path := filepath.Join(examplesDir, "hello.cell")

	data, err := os.ReadFile(path)
	if err != nil {
		t.Skipf("cannot read hello.cell: %v", err)
	}

	prog, err := Parse(string(data))
	if err != nil {
		t.Fatalf("parse error: %v", err)
	}
	prog.Name = "hello"

	toml := SlingFormula(prog, "hello")

	// Should have at least one step
	if !strings.Contains(toml, "[[steps]]") {
		t.Errorf("no steps in formula output:\n%s", toml)
	}

	// Should be valid-looking TOML with required fields
	if !strings.Contains(toml, `formula = "cell-dispatch-hello"`) {
		t.Errorf("missing formula name:\n%s", toml)
	}
	if !strings.Contains(toml, "version = 1") {
		t.Errorf("missing version:\n%s", toml)
	}

	// Verify dependency graph: wrap should need greet (both are soft/llm)
	if !strings.Contains(toml, `needs = ["greet"]`) {
		t.Errorf("wrap should depend on greet:\n%s", toml)
	}
}

func TestSanitizeTOMLKey(t *testing.T) {
	tests := []struct {
		input string
		want  string
	}{
		{"simple", "simple"},
		{"with-hyphens", "with-hyphens"},
		{"with_underscores", "with_underscores"},
		{"with spaces", "with-spaces"},
		{"special.chars!", "special-chars-"},
		{"citizen-maya", "citizen-maya"},
	}
	for _, tc := range tests {
		got := sanitizeTOMLKey(tc.input)
		if got != tc.want {
			t.Errorf("sanitizeTOMLKey(%q) = %q, want %q", tc.input, got, tc.want)
		}
	}
}
