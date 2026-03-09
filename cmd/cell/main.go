package main

import (
	"fmt"
	"os"

	"github.com/ericfode/cell/internal/cell"
)

func main() {
	if len(os.Args) < 3 {
		fmt.Fprintf(os.Stderr, "Usage: cell <parse|validate|fmt> <file.cell>\n")
		os.Exit(1)
	}

	cmd := os.Args[1]
	path := os.Args[2]

	switch cmd {
	case "parse":
		f, err := cell.ParseFile(path)
		if err != nil {
			fmt.Fprintf(os.Stderr, "parse error: %v\n", err)
			os.Exit(1)
		}
		fmt.Print(cell.PrettyPrint(f))

	case "validate":
		f, err := cell.ParseFile(path)
		if err != nil {
			fmt.Fprintf(os.Stderr, "✗ %s\n", err)
			os.Exit(1)
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

	case "fmt":
		f, err := cell.ParseFile(path)
		if err != nil {
			fmt.Fprintf(os.Stderr, "parse error: %v\n", err)
			os.Exit(1)
		}
		formatted := cell.PrettyPrint(f)
		if err := os.WriteFile(path, []byte(formatted), 0o644); err != nil {
			fmt.Fprintf(os.Stderr, "writing formatted output: %v\n", err)
			os.Exit(1)
		}
		fmt.Fprintf(os.Stderr, "✓ formatted %s\n", path)

	default:
		fmt.Fprintf(os.Stderr, "Unknown command: %s\nUsage: cell <parse|validate|fmt> <file.cell>\n", cmd)
		os.Exit(1)
	}
}
