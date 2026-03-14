package main

import (
	"context"
	"encoding/json"
	"flag"
	"fmt"
	"os"
	"path/filepath"
	"strings"

	"github.com/ericfode/cell/internal/cell/retort"
)

func main() {
	if len(os.Args) < 2 {
		usage()
		os.Exit(1)
	}

	cmd := os.Args[1]
	args := os.Args[2:]

	ctx := context.Background()

	switch cmd {
	case "init":
		cmdInit(ctx, args)
	case "load":
		cmdLoad(ctx, args)
	case "eval":
		cmdEval(ctx, args)
	case "eval-one":
		cmdEvalOne(ctx, args)
	case "status":
		cmdStatus(ctx, args)
	case "ready":
		cmdReady(ctx, args)
	case "yields":
		cmdYields(ctx, args)
	case "trace":
		cmdTrace(ctx, args)
	case "sling":
		cmdSling(ctx, args)
	case "source":
		cmdSource(ctx, args)
	case "sql":
		cmdSQL(args)
	case "help", "--help", "-h":
		usage()
	default:
		fmt.Fprintf(os.Stderr, "unknown command: %s\n", cmd)
		usage()
		os.Exit(1)
	}
}

func usage() {
	fmt.Fprintf(os.Stderr, `rt — Retort Cell execution engine

Commands:
  init                          Create Retort Dolt DB
  load <file.cell>              Parse and load program into Retort
  load --sql <file.cell>        Emit SQL to stdout (no DB needed)
  eval [--program <name>]       Run eval loop until quiescence
  eval-one [--program <name>]   Evaluate one ready cell
  status [--program <name>]     Show program state
  ready [--program <name>]      Show ready cells
  yields [--program <name>]     Show frozen yields
  trace [--program <name>]      Show execution trace
  sling --formula <file.cell>   Generate Gas Town formula TOML from Cell program
  source <cell-name>            Decompile cell to turnstile syntax
  sql <file.cell>               Emit SQL INSERTs to stdout
`)
}

func openDB(ctx context.Context) *retort.DB {
	dsn := os.Getenv("RETORT_DSN")
	database := os.Getenv("RETORT_DB")
	db, err := retort.OpenDB(ctx, dsn, database)
	if err != nil {
		fmt.Fprintf(os.Stderr, "error: %v\n", err)
		os.Exit(1)
	}
	return db
}

func cmdInit(ctx context.Context, args []string) {
	db := openDB(ctx)
	defer db.Close()

	if err := db.InitSchema(ctx); err != nil {
		fmt.Fprintf(os.Stderr, "error: %v\n", err)
		os.Exit(1)
	}
	fmt.Println("Retort database initialized")
}

func cmdLoad(ctx context.Context, args []string) {
	fs := flag.NewFlagSet("load", flag.ExitOnError)
	sqlOnly := fs.Bool("sql", false, "Emit SQL to stdout instead of loading into DB")
	fs.Parse(args)

	if fs.NArg() < 1 {
		fmt.Fprintf(os.Stderr, "usage: rt load [--sql] <file.cell>\n")
		os.Exit(1)
	}
	path := fs.Arg(0)

	if *sqlOnly {
		cmdSQL([]string{path})
		return
	}

	db := openDB(ctx)
	defer db.Close()

	programID, err := retort.LoadFile(ctx, db, path)
	if err != nil {
		fmt.Fprintf(os.Stderr, "error: %v\n", err)
		os.Exit(1)
	}

	fmt.Printf("Loaded program: %s\n", programID)

	// Show cells
	cells, err := db.GetAllCells(ctx, programID)
	if err == nil {
		for _, c := range cells {
			yields, _ := db.GetYields(ctx, c.ID)
			yieldNames := make([]string, len(yields))
			for i, y := range yields {
				yieldNames[i] = y.FieldName
			}
			fmt.Printf("  %s %s: yields=[%s] state=%s\n",
				bodyIcon(c.BodyType), c.Name,
				strings.Join(yieldNames, ", "), c.State)
		}
	}
}

func cmdEval(ctx context.Context, args []string) {
	fs := flag.NewFlagSet("eval", flag.ExitOnError)
	program := fs.String("program", "", "Program name (uses most recent if empty)")
	maxSteps := fs.Int("max-steps", 100, "Maximum eval steps")
	verbose := fs.Bool("v", false, "Verbose output")
	fs.Parse(args)

	db := openDB(ctx)
	defer db.Close()

	programID, err := resolveProgram(ctx, db, *program)
	if err != nil {
		fmt.Fprintf(os.Stderr, "error: %v\n", err)
		os.Exit(1)
	}

	engine := &retort.Engine{
		DB:       db,
		MaxSteps: *maxSteps,
		Verbose:  *verbose,
		Log: func(msg string) {
			fmt.Printf("[retort] %s\n", msg)
		},
	}

	result := engine.Eval(ctx, programID)
	if result.Error != nil {
		fmt.Fprintf(os.Stderr, "error: %v\n", result.Error)
		os.Exit(1)
	}

	fmt.Printf("\n%s after %d steps: %d frozen, %d bottom, %d pending\n",
		strings.ToUpper(result.Status), result.Steps,
		result.Frozen, result.Bottom, result.Pending)

	// Show final yields
	printYields(ctx, db, programID)
}

func cmdEvalOne(ctx context.Context, args []string) {
	fs := flag.NewFlagSet("eval-one", flag.ExitOnError)
	program := fs.String("program", "", "Program name")
	fs.Parse(args)

	db := openDB(ctx)
	defer db.Close()

	programID, err := resolveProgram(ctx, db, *program)
	if err != nil {
		fmt.Fprintf(os.Stderr, "error: %v\n", err)
		os.Exit(1)
	}

	engine := &retort.Engine{
		DB: db,
		Log: func(msg string) {
			fmt.Printf("[retort] %s\n", msg)
		},
	}

	result := engine.EvalOne(ctx, programID)
	if result.Error != nil {
		fmt.Fprintf(os.Stderr, "error: %v\n", result.Error)
		os.Exit(1)
	}
	fmt.Printf("Status: %s (%d frozen, %d bottom, %d pending)\n",
		result.Status, result.Frozen, result.Bottom, result.Pending)
}

func cmdStatus(ctx context.Context, args []string) {
	fs := flag.NewFlagSet("status", flag.ExitOnError)
	program := fs.String("program", "", "Program name")
	asJSON := fs.Bool("json", false, "Output as JSON")
	fs.Parse(args)

	db := openDB(ctx)
	defer db.Close()

	programID, err := resolveProgram(ctx, db, *program)
	if err != nil {
		fmt.Fprintf(os.Stderr, "error: %v\n", err)
		os.Exit(1)
	}

	cells, err := db.GetAllCells(ctx, programID)
	if err != nil {
		fmt.Fprintf(os.Stderr, "error: %v\n", err)
		os.Exit(1)
	}

	if *asJSON {
		enc := json.NewEncoder(os.Stdout)
		enc.SetIndent("", "  ")
		enc.Encode(cells)
		return
	}

	for _, c := range cells {
		icon := stateIcon(c.State)
		yields, _ := db.GetYields(ctx, c.ID)
		yieldStr := ""
		for _, y := range yields {
			if y.IsFrozen && !y.IsBottom {
				yieldStr += fmt.Sprintf(" %s=%s", y.FieldName, y.ValueText)
			} else if y.IsBottom {
				yieldStr += fmt.Sprintf(" %s=⊥", y.FieldName)
			}
		}
		fmt.Printf("  %s %s %s [%s]%s\n", icon, bodyIcon(c.BodyType), c.Name, c.State, yieldStr)
	}
}

func cmdReady(ctx context.Context, args []string) {
	fs := flag.NewFlagSet("ready", flag.ExitOnError)
	program := fs.String("program", "", "Program name")
	fs.Parse(args)

	db := openDB(ctx)
	defer db.Close()

	programID, err := resolveProgram(ctx, db, *program)
	if err != nil {
		fmt.Fprintf(os.Stderr, "error: %v\n", err)
		os.Exit(1)
	}

	ready, err := db.FindReadyCells(ctx, programID)
	if err != nil {
		fmt.Fprintf(os.Stderr, "error: %v\n", err)
		os.Exit(1)
	}

	if len(ready) == 0 {
		fmt.Println("No ready cells")
		return
	}

	for _, c := range ready {
		fmt.Printf("  %s %s (%s)\n", bodyIcon(c.BodyType), c.Name, c.BodyType)
	}
}

func cmdYields(ctx context.Context, args []string) {
	fs := flag.NewFlagSet("yields", flag.ExitOnError)
	program := fs.String("program", "", "Program name")
	fs.Parse(args)

	db := openDB(ctx)
	defer db.Close()

	programID, err := resolveProgram(ctx, db, *program)
	if err != nil {
		fmt.Fprintf(os.Stderr, "error: %v\n", err)
		os.Exit(1)
	}

	printYields(ctx, db, programID)
}

func cmdTrace(ctx context.Context, args []string) {
	fs := flag.NewFlagSet("trace", flag.ExitOnError)
	program := fs.String("program", "", "Program name")
	fs.Parse(args)

	db := openDB(ctx)
	defer db.Close()

	programID, err := resolveProgram(ctx, db, *program)
	if err != nil {
		fmt.Fprintf(os.Stderr, "error: %v\n", err)
		os.Exit(1)
	}

	traces, err := db.GetTrace(ctx, programID)
	if err != nil {
		fmt.Fprintf(os.Stderr, "error: %v\n", err)
		os.Exit(1)
	}

	if len(traces) == 0 {
		fmt.Println("No trace entries")
		return
	}

	for _, t := range traces {
		fmt.Printf("  [step %d] %s %s (%dms) %s\n",
			t.Step, t.Action, t.CellID, t.DurationMs, t.Detail)
	}
}

func cmdSource(ctx context.Context, args []string) {
	fs := flag.NewFlagSet("source", flag.ExitOnError)
	program := fs.String("program", "", "Program name")
	fs.Parse(args)

	db := openDB(ctx)
	defer db.Close()

	if fs.NArg() > 0 {
		// Decompile specific cell by name
		programID, err := resolveProgram(ctx, db, *program)
		if err != nil {
			fmt.Fprintf(os.Stderr, "error: %v\n", err)
			os.Exit(1)
		}
		cell, err := db.GetCellByName(ctx, programID, fs.Arg(0))
		if err != nil {
			fmt.Fprintf(os.Stderr, "error: %v\n", err)
			os.Exit(1)
		}
		source, err := retort.Decompile(ctx, db, cell.ID)
		if err != nil {
			fmt.Fprintf(os.Stderr, "error: %v\n", err)
			os.Exit(1)
		}
		fmt.Print(source)
	} else {
		// Decompile entire program
		programID, err := resolveProgram(ctx, db, *program)
		if err != nil {
			fmt.Fprintf(os.Stderr, "error: %v\n", err)
			os.Exit(1)
		}
		source, err := retort.DecompileProgram(ctx, db, programID)
		if err != nil {
			fmt.Fprintf(os.Stderr, "error: %v\n", err)
			os.Exit(1)
		}
		fmt.Print(source)
	}
}

func cmdSling(_ context.Context, args []string) {
	fs := flag.NewFlagSet("sling", flag.ExitOnError)
	formula := fs.Bool("formula", false, "Output Gas Town formula TOML")
	program := fs.String("program", "", "Program name (defaults to filename)")
	fs.Parse(args)

	if fs.NArg() < 1 {
		fmt.Fprintf(os.Stderr, "usage: rt sling --formula <file.cell>\n")
		os.Exit(1)
	}
	path := fs.Arg(0)

	if !*formula {
		fmt.Fprintf(os.Stderr, "error: --formula flag is required (JSONL output not yet implemented)\n")
		os.Exit(1)
	}

	data, err := os.ReadFile(path)
	if err != nil {
		fmt.Fprintf(os.Stderr, "error: %v\n", err)
		os.Exit(1)
	}

	prog, err := retort.Parse(string(data))
	if err != nil {
		fmt.Fprintf(os.Stderr, "error: %v\n", err)
		os.Exit(1)
	}

	name := *program
	if name == "" {
		name = strings.TrimSuffix(filepath.Base(path), filepath.Ext(path))
	}
	prog.Name = name

	fmt.Print(retort.SlingFormula(prog, name))
}

func cmdSQL(args []string) {
	if len(args) < 1 {
		fmt.Fprintf(os.Stderr, "usage: rt sql <file.cell>\n")
		os.Exit(1)
	}

	data, err := os.ReadFile(args[0])
	if err != nil {
		fmt.Fprintf(os.Stderr, "error: %v\n", err)
		os.Exit(1)
	}

	prog, err := retort.Parse(string(data))
	if err != nil {
		fmt.Fprintf(os.Stderr, "error: %v\n", err)
		os.Exit(1)
	}

	name := strings.TrimSuffix(args[0], ".cell")
	prog.Name = name
	prog.SourceFile = args[0]

	fmt.Print(retort.EmitSQL(prog))
}

// --- Helpers ---

func resolveProgram(ctx context.Context, db *retort.DB, name string) (string, error) {
	if name != "" {
		return db.GetProgramByName(ctx, name)
	}
	// Find most recent program
	var id string
	row := db.QueryRow(ctx, `SELECT id FROM programs ORDER BY created_at DESC LIMIT 1`)
	if err := row.Scan(&id); err != nil {
		return "", fmt.Errorf("no programs found — run 'rt load' first")
	}
	return id, nil
}

func printYields(ctx context.Context, db *retort.DB, programID string) {
	yields, err := db.GetAllYields(ctx, programID)
	if err != nil {
		fmt.Fprintf(os.Stderr, "error: %v\n", err)
		return
	}

	cells, _ := db.GetAllCells(ctx, programID)
	cellNames := make(map[string]string)
	for _, c := range cells {
		cellNames[c.ID] = c.Name
	}

	for _, y := range yields {
		cellName := cellNames[y.CellID]
		if y.IsFrozen && !y.IsBottom {
			fmt.Printf("  %s→%s = %s\n", cellName, y.FieldName, y.ValueText)
		} else if y.IsBottom {
			fmt.Printf("  %s→%s = ⊥\n", cellName, y.FieldName)
		} else {
			fmt.Printf("  %s→%s = (pending)\n", cellName, y.FieldName)
		}
	}
}

func bodyIcon(bt string) string {
	switch bt {
	case "hard":
		return "⊢="
	case "soft":
		return "∴"
	case "passthrough":
		return "→"
	case "spawner":
		return "⊢⊢"
	case "evolution":
		return "⊢∘"
	default:
		return "⊢"
	}
}

func stateIcon(state string) string {
	switch state {
	case "frozen":
		return "✓"
	case "bottom":
		return "⊥"
	case "computing":
		return "…"
	case "tentative":
		return "?"
	default:
		return "◌"
	}
}
