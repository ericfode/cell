# Cell-Zero Bootstrap Roadmap: From Syntax Discovery to Working Runtime

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Bootstrap cell-zero — the self-improving Cell runtime — starting from an evolutionary syntax discovery process and ending with a runtime that applies distillation pressure to crystallize LLM cells into deterministic processes.

**Architecture:** Five phases, each producing a working artifact that feeds the next. Phase 1 discovers the syntax. Phase 2 builds a minimal "dumb" executor (beads-level). Phase 3 adds observation/recording. Phase 4 adds distillation. Phase 5 closes the loop (cell-zero rewrites itself).

**Tech Stack:** Go (runtime), beads formulas (bootstrap substrate), LLM API (Claude), blake3 (content addressing)

**Key constraint:** Cells can only rewrite unexecuted beads, create new beads, or add edges to executed cells. The past is frozen; only the frontier is mutable.

---

## Phase 1: Syntax Discovery (ce-s6y)

**Purpose:** Find Cell's LLM-native syntax through evolutionary experimentation.

**Input:** The current Cell examples + the pretend test requirement.
**Output:** A winning syntax that LLMs can execute (eval-one) and distill.

### Task 1.1: Build the syntax discovery formula as a beads formula

**Files:**
- Create: `formulas/syntax-discovery.toml` (beads formula format)

This is a 7-cell beads formula:
- seed: generate N syntax variants for the hello-world test case
- execute: map — pretend-test each variant (eval-one)
- oracle-execute: score execution accuracy (0-1)
- distill: map — attempt crystallization of each variant's first cell
- oracle-distill: score distillation quality (0-1)
- rank: combine scores, propose mutations for top 3
- report: summarize convergent patterns

**Wires:** seed → execute → oracle-execute → distill → oracle-distill → rank → report

**Test case:** Two-step program (greet + wrap). Greet takes name, produces { message: str }. Wrap depends on greet, produces { text: str, emoji: str }.

**Scoring:** 50% execute accuracy, 30% distill quality, 20% readability.

### Task 1.2: Run the formula (3-5 rounds)

Execute the formula iteratively:
1. Round 1: seed generates 5-10 variants
2. Score all variants
3. Top 3 get mutated (3 mutations each)
4. Round 2: test 12 candidates (9 mutants + 3 originals)
5. Continue until a variant scores >0.9 on all criteria

### Task 1.3: Formalize the winning syntax

- Document the winning syntax as a spec update
- Rewrite hello.cell and survey.cell in the new syntax
- Validate: hand rewritten files to a fresh LLM, confirm it can eval-one correctly

**Exit criteria:** A syntax that passes the pretend test with >90% accuracy.

---

## Phase 2: Dumb Executor (cell-pour)

**Purpose:** Build the simplest possible thing that can run Cell programs. No distillation, no staleness, no content addressing. Just: parse → topological sort → execute each cell → collect outputs.

**Input:** The winning syntax from Phase 1.
**Output:** A working `cell run` command that executes Cell programs.

**This is largely what exists today** in `internal/cell/subzero/`, but it needs to be realigned to the new syntax.

### Task 2.1: Update the parser for the new syntax

**Files:**
- Modify: `internal/cell/parser/lexer.go`
- Modify: `internal/cell/parser/parser.go`
- Modify: `internal/cell/parser/token.go`
- Modify: `internal/cell/parser/ast.go`
- Test: `internal/cell/parser/parser_test.go`

Rewrite the lexer and parser to handle whatever syntax won in Phase 1. The AST types may change. All existing parser tests need updating.

### Task 2.2: Update the runner for eval-one semantics

**Files:**
- Modify: `internal/cell/subzero/runner.go`
- Modify: `internal/cell/subzero/executor.go`
- Test: `internal/cell/subzero/subzero_test.go`

The runner currently does full topological execution. Add eval-one mode:
- `RunOne(program, state) → (next_cell, result, new_state)`
- State = map of cell_name → output (the "RAM")
- Returns which cell it executed, what it produced, and updated state
- Full execution = repeated eval-one until no ready cells remain

### Task 2.3: Verify the pretend test

Write a test that:
1. Takes a Cell program in the new syntax
2. Sends it to Claude with "execute the next ready cell" prompt
3. Compares LLM output against `RunOne` output
4. They should produce equivalent results

**Exit criteria:** `cell run` works on hello.cell and survey.cell in the new syntax, and the pretend test passes.

---

## Phase 3: Observer (cell-one)

**Purpose:** Add observation — every cell execution is recorded as a bead with content-addressed inputs and outputs. No distillation yet, just watching.

**Input:** Working executor from Phase 2.
**Output:** An executor that produces a bead trail — every execution is recorded and content-addressed.

### Task 3.1: Content addressing

**Files:**
- Create: `internal/cell/addressing/hash.go`
- Test: `internal/cell/addressing/hash_test.go`

Implement: `ContentHash(prompt, sorted_ref_hashes, oracle_hash) → blake3_hash`

This is the identity of a cell execution. Same inputs = same hash = same result (if deterministic).

### Task 3.2: Bead recording

**Files:**
- Create: `internal/cell/observer/observer.go`
- Test: `internal/cell/observer/observer_test.go`

Wrap the executor: before and after each cell execution, record:
- Cell name, type, content hash
- Inputs (resolved refs with their content hashes)
- Output (raw + content hash)
- Duration, token count (if LLM)
- Whether output matched a cached hash (cache hit)

Store as beads via `bd` or a local bead store.

### Task 3.3: Cache layer

**Files:**
- Create: `internal/cell/cache/cache.go`
- Test: `internal/cell/cache/cache_test.go`

Simple content-addressed cache:
- Before executing a cell, compute its content hash
- If hash exists in cache, return cached result (skip execution)
- If not, execute, store result keyed by hash
- This is the first form of "distillation" — pure memoization

### Task 3.4: Staleness tracking

**Files:**
- Create: `internal/cell/staleness/tracker.go`
- Test: `internal/cell/staleness/tracker_test.go`

Track fresh/stale state per cell:
- When a cell's inputs change (different content hash), mark it stale
- Mark all downstream dependents stale (per Lean proof: staleness_propagation_sound)
- Only execute stale cells on re-run
- Non-dependents are never affected (staleness_preservation)

**Exit criteria:** Re-running a Cell program skips cells whose inputs haven't changed. Every execution produces a bead trail.

---

## Phase 4: Distiller (cell-zero-alpha)

**Purpose:** Add distillation pressure. The runtime observes patterns across executions and proposes deterministic replacements for LLM cells.

**Input:** Observer from Phase 3 with execution history.
**Output:** A runtime that can propose and validate cell crystallization.

### Task 4.1: Pattern detection

**Files:**
- Create: `internal/cell/distill/patterns.go`
- Test: `internal/cell/distill/patterns_test.go`

Given N execution records for a cell:
- Are the outputs consistent? (same structure, similar values)
- Is the input→output mapping learnable? (regex, template, lookup table)
- Classify: "always same" → constant, "pattern" → template/regex, "varies" → keep as LLM

### Task 4.2: Distillation proposal

**Files:**
- Create: `internal/cell/distill/propose.go`
- Test: `internal/cell/distill/propose_test.go`

For cells classified as "pattern":
- Generate a deterministic replacement (script cell with the learned pattern)
- The replacement has the same interface contract (inputs/outputs frozen)
- Only the implementation changes: LLM → script

### Task 4.3: Shadow execution

**Files:**
- Create: `internal/cell/distill/shadow.go`
- Test: `internal/cell/distill/shadow_test.go`

Run distilled cells alongside LLM cells:
- Both execute on same inputs
- Compare outputs
- Track match rate over time
- When match rate > threshold (e.g., 0.95 over 20 executions), promote shadow to primary

This is the graph operation: shadow = `!add` a new cell, then `!wire` it in parallel, then `!drop` the original once validated.

### Task 4.4: Freeze and promote

**Files:**
- Modify: `internal/cell/subzero/runner.go`
- Modify: `internal/cell/subzero/dispatch.go`

When a shadow is promoted:
- The cell type changes from "llm" to "distilled"
- The distilled executor (already exists in `distilled.go`) handles it
- The original LLM cell becomes a fallback (used only if distilled cell fails)
- Interface contract is preserved — downstream cells see no difference

**Exit criteria:** After running a Cell program N times, at least one cell gets distilled. The distilled version produces same outputs as the LLM version.

---

## Phase 5: The Loop (cell-zero)

**Purpose:** Close the metacircular loop. cell-zero can distill parts of itself. cell-forge can read Cell programs in the discovered syntax. The system rewrites itself toward determinism.

**Input:** Distiller from Phase 4.
**Output:** A self-improving runtime.

### Task 5.1: cell-forge reads the new syntax

Cell-forge (which reads Cell programs) should itself be a Cell program. Use the Phase 4 runtime to execute cell-forge, which reads Cell programs and produces ASTs.

Over time, cell-zero distills cell-forge's LLM cells into the deterministic parser we need. The parser emerges from the distillation process.

### Task 5.2: cell-zero observes itself

Run cell-zero on cell-zero's own execution:
- cell-zero executes a Cell program
- The execution is recorded as beads
- cell-zero can read those beads and look for distillation opportunities in its own pipeline

### Task 5.3: environment-cell

Create an "environment cell" that describes the available operations (LLM call, script execution, bead creation, graph mutation). Together with cell-forge and cell-zero, this is the foundation for Cell programs that build new Cell programs.

### Task 5.4: Self-rewriting validation

The Lean proofs define invariants that must hold:
- Effect algebra composition (associativity, commutativity, par_le_seq)
- Staleness soundness and preservation
- DAG readiness monotonicity
- Compression retention monotonicity (DPI)
- Molecule lifecycle phase irreversibility
- DAG-rewrite-completeness (8 operations sufficient)

Build validation checks (or property tests) for each invariant. These are the oracles that ensure self-rewriting doesn't break the system.

**Exit criteria:** cell-forge can read Cell programs. cell-zero can distill cells in cell-forge. The system has distilled at least one component of itself.

---

## Dependency Graph

```
Phase 1 (syntax)
    ↓
Phase 2 (dumb executor)
    ↓
Phase 3 (observer + cache + staleness)
    ↓
Phase 4 (distillation + shadows)
    ↓
Phase 5 (metacircular loop)
```

Each phase produces a working artifact. Each phase can be validated independently. No phase requires the next to be useful.

## What Already Exists (and What's Scrap)

**SCRAP — delete after Phase 1:**
- `internal/cell/subzero/` — Built as a batch pipeline executor against the wrong mental model. Not salvageable. Clean rewrite in Phase 2.
- `internal/cell/parser/` — Parser for the old syntax. Will be replaced by whatever syntax Phase 1 discovers. The new parser bootstraps from cell-forge (Phase 5), not hand-written code.
- `cmd/cell/main.go` — CLI built around old parser/runtime. Rewrite in Phase 2.
- `docs/examples/*.cell` — All 52 files use old syntax. Rewrite after Phase 1.

**KEEP:**
- **Lean proofs** (`lean4/`): 52 theorems defining invariants. These become Phase 5 oracles. The math doesn't change.
- **Design docs** (`docs/plans/`, `docs/design/`): Vision documents, spec, this roadmap.
- **Go module** (`go.mod`): Clean, no dependencies. Good foundation.

## Risk: The Bootstrap Chicken-and-Egg

Phase 1 uses beads formulas (not Cell) because Cell's syntax doesn't exist yet. But the whole point of Cell is to replace beads formulas. The resolution:

1. Phase 1 runs as beads formulas (dumb substrate)
2. Phase 1 discovers Cell syntax
3. Phase 2 builds an executor for that syntax
4. Phase 3+ retroactively makes Cell capable of running its own Phase 1
5. Eventually, the syntax discovery formula IS a Cell program discovering better Cell syntax

The bootstrap converges when Cell can express and execute its own discovery process.
