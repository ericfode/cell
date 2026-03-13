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

Build once: `go build -o rt ./cmd/rt/`

```bash
export RETORT_DSN="root@tcp(127.0.0.1:3308)/"

./rt init [--force]                              # Create/reset schema
./rt load <file.cell>                            # Parse + load into Dolt
./rt eval [--program <name>]                     # Full eval loop (hard+soft inline)
./rt eval-one [--program <name>]                 # Eval one ready cell
./rt sling [--program <name>]                    # Eval hard cells, output soft cell prompts
./rt collect --results <file.json>               # Feed LLM results back, freeze yields
./rt status [--program <name>]                   # Cell states
./rt yields [--program <name>]                   # Frozen outputs
./rt ready [--program <name>]                    # Show ready cells
./rt trace [--program <name>]                    # Execution log
./rt source <cell-name>                          # Decompile to turnstile
./rt sql <file.cell>                             # Emit SQL INSERTs to stdout
```

## Experiment Workflow

### Local experiments (hard cells only — deterministic)

These run entirely via `rt eval`, no LLM dispatch needed:

```bash
./rt init --force
./rt load experiments/hard-eval.cell && ./rt eval
./rt load experiments/sort-proof.cell && ./rt eval
./rt load experiments/edge-cases.cell && ./rt eval
```

Verify: `rt status` should show all cells frozen, no bottom (except intentional guard failures).

### Sling/collect experiments (soft cells — LLM dispatch)

**YOU are in the middle of the loop.** Retort handles deterministic bits, you dispatch soft cells.

```bash
# 1. Load and sling
./rt init --force
./rt load experiments/coherence.cell
./rt sling --program coherence > /tmp/sling.jsonl

# 2. For each line in sling output, dispatch via subagent:
#    Each line is JSON: {"cell":"name", "prompt":"...", "yields":["field1","field2"]}
#    Send prompt to a subagent, get back JSON with the yield fields.

# 3. Collect results
#    Merge subagent outputs into: {"cell-name": {"field1": "value", "field2": "value"}, ...}
./rt collect --program coherence --results /tmp/results.json

# 4. Repeat sling/collect until quiescent
./rt sling --program coherence  # New cells may be ready (e.g., analyst)
# ... dispatch ... collect ...
# Until: QUIESCENT: N frozen, 0 bottom, 0 pending
```

### Dispatch strategies

- **Subagents** (small runs, <=10 cells): Launch parallel Agent tool calls
- **Polecats** (scale, 20+ cells): Create beads, sling to Gas Town polecats
- **Manual** (debugging): `rt eval --mode interactive` prompts you on stdin

## Experiments

| File | Type | What it tests |
|------|------|---------------|
| `experiments/hard-eval.cell` | local | Arithmetic, lists, strings, conditionals, guards, iterators |
| `experiments/sort-proof.cell` | local | Multi-step hard pipeline, chained oracles |
| `experiments/edge-cases.cell` | local | Empty lists, division guards, bottom propagation, deep chains, wide fanout |
| `experiments/coherence.cell` | sling | 3 witnesses of same event, analyst checks cross-references |
| `experiments/analyst-debate.cell` | sling | 2 analysts (different frameworks), synthesizer reconciles |
| `experiments/day-two.cell` | sling | Multi-day continuity, Day 2 informed by Day 1 |
| `programs/millhaven-5.cell` | sling | Gate 1: 5 citizens + 1 analyst (PROVEN) |
| `programs/millhaven-20.cell` | sling | Gate 2: 20 citizens + 2 analysts |
| `programs/millhaven-50.cell` | sling | Gate 3: 50 citizens + 5 analysts |
| `programs/millhaven-100.cell` | sling | Gate 4: THE EXPERIMENT — 100 citizens + 10 analysts |

## Gate Progression

1. **Gate 0** — Feature parity with Python cell-zero. ✅ DONE
2. **Gate 1** — 5 citizens + 1 analyst, live dispatch. ✅ DONE (sling/collect proven)
3. **Gate 2** — 20 citizens via polecat dispatch.
4. **Gate 3** — 50 citizens, 5 analysts, full oracle.
5. **Gate 4** — THE EXPERIMENT: 100 citizens, 10 analysts.

## Dispatch Strategy

**Retort manages the deterministic bits. You are in the middle of the dispatch loop.**

Don't build parallelism into Retort. Use **subagents** for small runs (Agent tool, <=10 cells) or **polecats** (Gas Town transient workers) for scale. Retort tells you what to dispatch (`rt sling`), you dispatch it, then feed results back (`rt collect`).

## Tests

```bash
go test ./internal/cell/retort/ -count=1 -v     # 38+ tests
```

Key test programs: add-double, abs-value, sort-proof, greet-shout, millhaven-5.

## Key Files

| What | Where |
|------|-------|
| Retort engine | `internal/cell/retort/` (15 Go files) |
| Expression evaluator | `internal/cell/retort/expr.go` |
| Sling/Collect | `internal/cell/retort/engine.go` (Sling, Collect methods) |
| CLI | `cmd/rt/main.go` |
| City generator | `cmd/millhaven-gen/main.go` |
| Experiments | `experiments/` (6 experiment .cell files) |
| City programs | `programs/` (millhaven 5/20/50/100) |
| Test programs | `tools/cell-zero/tests/` (38 .cell files) |
| Python reference | `tools/cell-zero/` |
| Dolt data | `.retort/` (not versioned in git) |
| Skill | `.claude/skills/cell-to-dolt/` |
