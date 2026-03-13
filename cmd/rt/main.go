package main

import (
	"context"
	"encoding/json"
	"flag"
	"fmt"
	"os"
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
	case "source":
		cmdSource(ctx, args)
	case "sql":
		cmdSQL(args)
	case "sling":
		cmdSling(ctx, args)
	case "collect":
		cmdCollect(ctx, args)
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
  source <cell-name>            Decompile cell to turnstile syntax
  sql <file.cell>               Emit SQL INSERTs to stdout
  sling [--program <name>]      Eval hard cells, output soft cells as prompts to sling
  collect [--program <name>]    Read results JSON from stdin, freeze yields
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
	mode := fs.String("mode", "dryrun", "Dispatch mode: live, dryrun, simulate, interactive")
	simFile := fs.String("simulate", "", "Simulation data file (JSON)")
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

	dispatchMode := parseDispatchMode(*mode, *simFile)

	engine := &retort.Engine{
		DB:       db,
		Mode:     dispatchMode,
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
	mode := fs.String("mode", "dryrun", "Dispatch mode: live, dryrun, simulate, interactive")
	simFile := fs.String("simulate", "", "Simulation data file (JSON)")
	fs.Parse(args)

	db := openDB(ctx)
	defer db.Close()

	programID, err := resolveProgram(ctx, db, *program)
	if err != nil {
		fmt.Fprintf(os.Stderr, "error: %v\n", err)
		os.Exit(1)
	}

	dispatchMode := parseDispatchMode(*mode, *simFile)

	engine := &retort.Engine{
		DB:   db,
		Mode: dispatchMode,
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

func cmdSling(ctx context.Context, args []string) {
	fs := flag.NewFlagSet("sling", flag.ExitOnError)
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
		DB:  db,
		Log: func(msg string) { fmt.Fprintf(os.Stderr, "[retort] %s\n", msg) },
	}

	work, result := engine.Sling(ctx, programID)
	if result.Error != nil {
		fmt.Fprintf(os.Stderr, "error: %v\n", result.Error)
		os.Exit(1)
	}

	if len(work) == 0 {
		fmt.Fprintf(os.Stderr, "No soft cells to sling (%d frozen, %d pending)\n",
			result.Frozen, result.Pending)
		return
	}

	// Output each cell's prompt as a JSON object for the operator to sling
	fmt.Fprintf(os.Stderr, "%d soft cells ready for dispatch:\n\n", len(work))

	for _, w := range work {
		fmt.Fprintf(os.Stderr, "=== %s ===\n", w.CellName)
		fmt.Fprintf(os.Stderr, "Yields: %s\n\n", joinCLIStrings(w.YieldNames))

		// Output the sling-ready JSON to stdout
		slingData := map[string]interface{}{
			"cell":   w.CellName,
			"prompt": w.Prompt,
			"yields": w.YieldNames,
		}
		enc := json.NewEncoder(os.Stdout)
		enc.Encode(slingData)
	}

	fmt.Fprintf(os.Stderr, "\nSling these, then run: rt collect < results.json\n")
}

func cmdCollect(ctx context.Context, args []string) {
	fs := flag.NewFlagSet("collect", flag.ExitOnError)
	program := fs.String("program", "", "Program name")
	resultsFile := fs.String("results", "", "Results JSON file (or stdin)")
	fs.Parse(args)

	db := openDB(ctx)
	defer db.Close()

	programID, err := resolveProgram(ctx, db, *program)
	if err != nil {
		fmt.Fprintf(os.Stderr, "error: %v\n", err)
		os.Exit(1)
	}

	// Read results from file or stdin
	var resultsData []byte
	if *resultsFile != "" {
		resultsData, err = os.ReadFile(*resultsFile)
	} else if fs.NArg() > 0 {
		resultsData, err = os.ReadFile(fs.Arg(0))
	} else {
		fmt.Fprintf(os.Stderr, "usage: rt collect --results <file.json>\n")
		os.Exit(1)
	}
	if err != nil {
		fmt.Fprintf(os.Stderr, "error reading results: %v\n", err)
		os.Exit(1)
	}

	var results map[string]map[string]interface{}
	if err := json.Unmarshal(resultsData, &results); err != nil {
		fmt.Fprintf(os.Stderr, "error parsing results JSON: %v\n", err)
		os.Exit(1)
	}

	engine := &retort.Engine{
		DB:  db,
		Log: func(msg string) { fmt.Printf("[retort] %s\n", msg) },
	}

	result := engine.Collect(ctx, programID, results)
	if result.Error != nil {
		fmt.Fprintf(os.Stderr, "error: %v\n", result.Error)
		os.Exit(1)
	}

	fmt.Printf("\n%s: %d frozen, %d bottom, %d pending\n",
		strings.ToUpper(result.Status), result.Frozen, result.Bottom, result.Pending)

	if result.Pending > 0 {
		fmt.Println("\nRun 'rt sling' again to dispatch newly-ready cells.")
	}
}

func joinCLIStrings(ss []string) string {
	return strings.Join(ss, ", ")
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

func parseDispatchMode(mode, simFile string) retort.DispatchMode {
	switch mode {
	case "live":
		return retort.ModeLive
	case "simulate":
		if simFile != "" {
			data, err := os.ReadFile(simFile)
			if err != nil {
				fmt.Fprintf(os.Stderr, "error reading simulation file: %v\n", err)
				os.Exit(1)
			}
			var sim map[string]map[string]interface{}
			if err := json.Unmarshal(data, &sim); err != nil {
				fmt.Fprintf(os.Stderr, "error parsing simulation file: %v\n", err)
				os.Exit(1)
			}
			retort.SimulationData = sim
		}
		return retort.ModeSimulate
	case "interactive":
		return retort.ModeInteractive
	default:
		return retort.ModeDryRun
	}
}

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
