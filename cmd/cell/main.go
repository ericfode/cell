package main

import (
	"encoding/json"
	"fmt"
	"os"
	"strings"

	"github.com/ericfode/cell/internal/cell"
	"github.com/ericfode/cell/internal/cell/parser"
	"github.com/ericfode/cell/internal/cell/subzero"
)

func main() {
	if len(os.Args) < 2 {
		printUsage()
		os.Exit(1)
	}

	cmd := os.Args[1]

	switch cmd {
	case "parse":
		requireFile()
		runParse(os.Args[2])
	case "validate":
		requireFile()
		runValidate(os.Args[2])
	case "fmt":
		requireFile()
		runFmt(os.Args[2])
	case "ast":
		requireFile()
		runAST(os.Args[2])
	case "run":
		requireFile()
		runExecute(os.Args[2])
	case "dag":
		requireFile()
		runDAG(os.Args[2])
	default:
		fmt.Fprintf(os.Stderr, "Unknown command: %s\n", cmd)
		printUsage()
		os.Exit(1)
	}
}

func printUsage() {
	fmt.Fprintf(os.Stderr, `Usage: cell <command> <file.cell> [options]

Commands:
  parse      Parse a .cell file and report syntax errors
  validate   Parse and run semantic validation
  fmt        Format a .cell file in-place
  ast        Dump the parsed AST as JSON
  run        Execute a .cell file (use --mode=mock|llm)
  dag        Show the dependency graph for a molecule

Run options:
  --mode=mock|llm    Execution mode (default: mock)
  --params=k=v,...   Parameters to pass to the molecule
  --max-cells=N      Maximum cells to execute (default: 100)
`)
}

func requireFile() {
	if len(os.Args) < 3 {
		fmt.Fprintf(os.Stderr, "Error: file argument required\n")
		printUsage()
		os.Exit(1)
	}
}

// runParse tries the extended parser first, falls back to basic parser.
func runParse(path string) {
	src, err := os.ReadFile(path)
	if err != nil {
		fatal("read error: %v", err)
	}

	// Try extended parser first (molecules)
	prog, extErr := parser.Parse(string(src))
	if extErr == nil {
		fmt.Fprintf(os.Stderr, "✓ %s — parsed successfully\n", path)
		printProgramSummary(prog)
		return
	}

	// Fall back to basic parser (simple cells/recipes)
	f, basicErr := cell.Parse(string(src), path)
	if basicErr == nil {
		fmt.Fprintf(os.Stderr, "✓ %s — parsed (basic syntax: %d cells, %d recipes)\n", path, len(f.Cells), len(f.Recipes))
		return
	}

	// Both failed — report extended parser error (more informative)
	fatal("parse error: %v", extErr)
}

func runValidate(path string) {
	src, err := os.ReadFile(path)
	if err != nil {
		fatal("read error: %v", err)
	}

	// Try extended parser
	prog, extErr := parser.Parse(string(src))
	if extErr == nil {
		errs := parser.Validate(prog)
		hasErrors := false
		for _, ve := range errs {
			if ve.Severity == "error" {
				fmt.Fprintf(os.Stderr, "✗ %s\n", ve.Error())
				hasErrors = true
			} else {
				fmt.Fprintf(os.Stderr, "⚠ %s\n", ve.Error())
			}
		}
		if hasErrors {
			os.Exit(1)
		}
		fmt.Fprintf(os.Stderr, "✓ %s — valid\n", path)
		printProgramSummary(prog)
		return
	}

	// Fall back to basic parser
	f, basicErr := cell.Parse(string(src), path)
	if basicErr != nil {
		fatal("parse error: %v", extErr)
	}
	errs := cell.Validate(f)
	if len(errs) == 0 {
		fmt.Fprintf(os.Stderr, "✓ %s: valid (%d cells, %d recipes)\n", path, len(f.Cells), len(f.Recipes))
		return
	}
	for _, e := range errs {
		fmt.Fprintf(os.Stderr, "✗ %s\n", e)
	}
	fmt.Fprintf(os.Stderr, "\n%d error(s) found\n", len(errs))
	os.Exit(1)
}

func runFmt(path string) {
	src, err := os.ReadFile(path)
	if err != nil {
		fatal("read error: %v", err)
	}

	// Try extended parser
	prog, extErr := parser.Parse(string(src))
	if extErr == nil {
		formatted := parser.PrettyPrint(prog)
		if err := os.WriteFile(path, []byte(formatted), 0o644); err != nil {
			fatal("write error: %v", err)
		}
		fmt.Fprintf(os.Stderr, "✓ formatted %s\n", path)
		return
	}

	// Fall back to basic parser
	f, basicErr := cell.ParseFile(path)
	if basicErr != nil {
		fatal("parse error: %v", extErr)
	}
	formatted := cell.PrettyPrint(f)
	if err := os.WriteFile(path, []byte(formatted), 0o644); err != nil {
		fatal("write error: %v", err)
	}
	fmt.Fprintf(os.Stderr, "✓ formatted %s\n", path)
}

func runAST(path string) {
	src, err := os.ReadFile(path)
	if err != nil {
		fatal("read error: %v", err)
	}

	prog, err := parser.Parse(string(src))
	if err != nil {
		fatal("parse error: %v", err)
	}

	enc := json.NewEncoder(os.Stdout)
	enc.SetIndent("", "  ")
	if err := enc.Encode(prog); err != nil {
		fatal("json encode: %v", err)
	}
}

func runExecute(path string) {
	mode := "mock"
	params := ""
	maxCells := 100

	// Parse flags from remaining args
	for _, arg := range os.Args[3:] {
		switch {
		case strings.HasPrefix(arg, "--mode="):
			mode = strings.TrimPrefix(arg, "--mode=")
		case strings.HasPrefix(arg, "--params="):
			params = strings.TrimPrefix(arg, "--params=")
		case strings.HasPrefix(arg, "--max-cells="):
			fmt.Sscanf(strings.TrimPrefix(arg, "--max-cells="), "%d", &maxCells)
		default:
			fatal("unknown flag: %s", arg)
		}
	}

	p := subzero.ParseParams(params)
	if err := subzero.RunFile(path, p, mode, maxCells); err != nil {
		os.Exit(1)
	}
}

func runDAG(path string) {
	src, err := os.ReadFile(path)
	if err != nil {
		fatal("read error: %v", err)
	}

	prog, err := parser.Parse(string(src))
	if err != nil {
		fatal("parse error: %v", err)
	}

	if len(prog.Molecules) == 0 {
		fatal("no molecules in %s", path)
	}

	mol := prog.Molecules[0]
	fmt.Printf("Molecule: %s\n\n", mol.Name)

	// Print cells
	fmt.Println("Cells:")
	for _, c := range mol.Cells {
		refs := ""
		if len(c.Refs) > 0 {
			var refNames []string
			for _, r := range c.Refs {
				refNames = append(refNames, r.Name)
			}
			refs = " <- " + strings.Join(refNames, ", ")
		}
		fmt.Printf("  # %s : %s%s\n", c.Name, c.Type, refs)
	}
	for _, c := range mol.MapCells {
		fmt.Printf("  map # %s : %s over %s\n", c.Name, c.Type, c.OverRef)
	}
	for _, c := range mol.ReduceCells {
		fmt.Printf("  reduce # %s : %s\n", c.Name, c.Type)
	}

	// Print wires
	if len(mol.Wires) > 0 {
		fmt.Println("\nWires:")
		for _, w := range mol.Wires {
			var fromStr, toStr string
			if w.From != "" {
				fromStr = w.From
			} else if len(w.FromList) > 0 {
				fromStr = "[" + strings.Join(w.FromList, ", ") + "]"
			}
			if w.To != "" {
				toStr = w.To
			} else if len(w.ToList) > 0 {
				toStr = "[" + strings.Join(w.ToList, ", ") + "]"
			}
			if w.OracleGate != "" {
				fmt.Printf("  %s -> ? %s -> %s\n", fromStr, w.OracleGate, toStr)
			} else {
				fmt.Printf("  %s -> %s\n", fromStr, toStr)
			}
		}
	}
}

func printProgramSummary(prog *parser.Program) {
	var parts []string
	if len(prog.Molecules) > 0 {
		parts = append(parts, fmt.Sprintf("%d molecule(s)", len(prog.Molecules)))
	}
	for _, mol := range prog.Molecules {
		cellCount := len(mol.Cells) + len(mol.MapCells) + len(mol.ReduceCells)
		if cellCount > 0 {
			parts = append(parts, fmt.Sprintf("  %s: %d cell(s), %d wire(s)", mol.Name, cellCount, len(mol.Wires)))
		}
	}
	if len(prog.Recipes) > 0 {
		parts = append(parts, fmt.Sprintf("%d recipe(s)", len(prog.Recipes)))
	}
	if len(prog.Fragments) > 0 {
		parts = append(parts, fmt.Sprintf("%d fragment(s)", len(prog.Fragments)))
	}
	if len(parts) > 0 {
		fmt.Fprintln(os.Stderr, strings.Join(parts, "\n"))
	}
}

func fatal(format string, args ...any) {
	fmt.Fprintf(os.Stderr, format+"\n", args...)
	os.Exit(1)
}
