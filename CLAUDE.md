# Helix — Retort City Experiment

## What This Is

Retort is Cell's execution engine backed by Dolt (SQL with git semantics). Cell programs are DAGs of cells — soft cells dispatch to LLMs, hard cells evaluate deterministically. Dolt commits after each step = full execution trace.

**The mission**: Run the Millhaven City Experiment — 100 LLM citizens live a day in a simulated town, 10 analyst LLMs study the population through the interface of cells.

## Architecture

```
.cell file → Go parser → Retort IR → Dolt DB → Eval loop → Dolt commits
                                                    ↓
                                          soft cells → LLM API / polecats
                                          hard cells → expr evaluator
```

## Retort Dolt Server

Retort has its own Dolt server, separate from Beads (port 3307).

```bash
# Start (from repo root):
dolt sql-server --host 127.0.0.1 --port 3308 --data-dir .retort &>/tmp/retort-dolt.log &

# Verify:
ss -tlnp | grep 3308

# Connect:
export RETORT_DSN="retort@tcp(127.0.0.1:3308)/"
export RETORT_DB="retort"
```

Data lives in `.retort/` (gitignored). Port **3308**. Do NOT use port 3307 (that's Beads).

## CLI: `rt`

```bash
go run ./cmd/rt/ init                           # Create schema
go run ./cmd/rt/ load programs/millhaven-5.cell  # Parse + load
go run ./cmd/rt/ eval --mode live                # Run with API calls
go run ./cmd/rt/ eval --mode dryrun              # Placeholders
go run ./cmd/rt/ eval --mode simulate --simulate programs/millhaven-5-sim.json
go run ./cmd/rt/ status                          # Cell states
go run ./cmd/rt/ yields                          # Frozen outputs
go run ./cmd/rt/ trace                           # Execution log
```

## City Experiment Programs

```bash
# Hand-crafted (Gate 1):
programs/millhaven-5.cell       # 5 citizens + 1 analyst
programs/millhaven-5-sim.json   # Simulation data for testing

# Generated:
go run ./cmd/millhaven-gen/ -citizens N -analysts M > programs/millhaven-N.cell
programs/millhaven-20.cell      # Gate 2: 20 citizens + 2 analysts
programs/millhaven-50.cell      # Gate 3: 50 citizens + 5 analysts
programs/millhaven-100.cell     # Gate 4: 100 citizens + 10 analysts
```

## Gate Progression

1. **Gate 0** — Feature parity with Python cell-zero. ✅ DONE
2. **Gate 1** — 5 citizens + 1 analyst, live API. Use subagents or polecats for dispatch.
3. **Gate 2** — 20 citizens via polecat dispatch.
4. **Gate 3** — 50 citizens, 5 analysts, full oracle.
5. **Gate 4** — THE EXPERIMENT: 100 citizens, 10 analysts.

## Dispatch Strategy

Don't build parallelism into Retort. Use **polecats** (Gas Town transient workers) for parallel soft cell dispatch. Retort orchestrates, polecats execute.

For small runs, subagents (Claude Code Agent tool) work. For scale, create beads and sling to polecats.

## Tests

```bash
go test ./internal/cell/retort/ -count=1 -v     # 38 tests
```

Key test programs: add-double, abs-value, sort-proof, greet-shout, millhaven-5.

## Key Files

| What | Where |
|------|-------|
| Retort engine | `internal/cell/retort/` (15 Go files) |
| Expression evaluator | `internal/cell/retort/expr.go` |
| CLI | `cmd/rt/main.go` |
| City generator | `cmd/millhaven-gen/main.go` |
| City programs | `programs/` |
| Test programs | `tools/cell-zero/tests/` |
| Python reference | `tools/cell-zero/` |
| Dolt data | `.retort/` (gitignored) |
