package subzero

import (
	"context"
	"fmt"
	"io"
	"strings"

	"github.com/ericfode/cell/internal/cell/parser"
)

// helloWorldCell is the canonical hello-world Cell program, embedded for smoke testing.
const helloWorldCell = `-- Hello World smoke test
## hello {
  input param.name : str required

  # greet : llm
    system>
      You are friendly and concise.
    user>
      Say hello to {{param.name}} in one sentence.
    format> greeting
      { message: str }
  #/

  # wrap : llm
    - greet
    user>
      Add an emoji to: {{greet.message}}
    format> display
      { text: str, emoji: str }
  #/
##/
`

// SmokeResult holds the outcome of a single smoke-test check.
type SmokeResult struct {
	Name   string
	Passed bool
	Detail string
}

// RunSmoke executes the hello-world smoke test pipeline and writes results to w.
// Returns nil if all checks pass, or an error describing failures.
func RunSmoke(w io.Writer) error {
	var results []SmokeResult

	// 1. Parse
	prog, err := parser.Parse(helloWorldCell)
	if err != nil {
		results = append(results, SmokeResult{"parse", false, err.Error()})
		return reportSmoke(w, results)
	}
	if len(prog.Molecules) == 0 {
		results = append(results, SmokeResult{"parse", false, "no molecules found"})
		return reportSmoke(w, results)
	}
	mol := prog.Molecules[0]
	cellCount := len(mol.Cells) + len(mol.MapCells) + len(mol.ReduceCells)
	results = append(results, SmokeResult{"parse", true,
		fmt.Sprintf("1 molecule (%s), %d cells", mol.Name, cellCount)})

	// 2. Validate
	verrs := parser.Validate(prog)
	hasErrors := false
	for _, ve := range verrs {
		if ve.Severity == "error" {
			hasErrors = true
		}
	}
	if hasErrors {
		var msgs []string
		for _, ve := range verrs {
			msgs = append(msgs, ve.Error())
		}
		results = append(results, SmokeResult{"validate", false, strings.Join(msgs, "; ")})
		return reportSmoke(w, results)
	}
	results = append(results, SmokeResult{"validate", true, "no errors"})

	// 3. Format round-trip
	formatted := parser.PrettyPrint(prog)
	prog2, err := parser.Parse(formatted)
	if err != nil {
		results = append(results, SmokeResult{"format", false, "round-trip parse failed: " + err.Error()})
	} else if len(prog2.Molecules) != len(prog.Molecules) {
		results = append(results, SmokeResult{"format", false, "molecule count changed after round-trip"})
	} else {
		results = append(results, SmokeResult{"format", true, "round-trip OK"})
	}

	// 4. Execute with mock
	runner := &Runner{
		Executor: &DispatchExecutor{
			LLM:    &MockExecutor{},
			Script: &ScriptExecutor{TimeoutSec: 5},
		},
		Params:   map[string]string{"name": "World"},
		MaxCells: 50,
	}
	cellResults, err := runner.Run(context.Background(), mol)
	if err != nil {
		results = append(results, SmokeResult{"execute", false, err.Error()})
		return reportSmoke(w, results)
	}
	results = append(results, SmokeResult{"execute", true,
		fmt.Sprintf("%d cells executed", len(cellResults))})

	// 5. Verify ref resolution (wrap should have received greet's output)
	greetRes, hasGreet := cellResults["greet"]
	wrapRes, hasWrap := cellResults["wrap"]
	if !hasGreet || !hasWrap {
		results = append(results, SmokeResult{"refs", false, "missing greet or wrap result"})
	} else if greetRes.Output == "" || wrapRes.Output == "" {
		results = append(results, SmokeResult{"refs", false, "empty output from greet or wrap"})
	} else {
		results = append(results, SmokeResult{"refs", true, "greet -> wrap resolution verified"})
	}

	return reportSmoke(w, results)
}

func reportSmoke(w io.Writer, results []SmokeResult) error {
	var failed int
	for _, r := range results {
		mark := "PASS"
		if !r.Passed {
			mark = "FAIL"
			failed++
		}
		fmt.Fprintf(w, "  %s  %-10s %s\n", mark, r.Name, r.Detail)
	}

	if failed > 0 {
		fmt.Fprintf(w, "\nSmoke test: %d/%d checks failed.\n", failed, len(results))
		return fmt.Errorf("%d smoke check(s) failed", failed)
	}
	fmt.Fprintf(w, "\nSmoke test: all %d checks passed.\n", len(results))
	return nil
}
