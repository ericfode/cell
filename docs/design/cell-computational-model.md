# Cell: Computational Model

*The theoretical foundation of Cell as a fusion language.*

## The Claim

Cell is a language that requires both a classical computer and a semantic
computer to execute. Neither alone is sufficient. Cell is not "a language
that uses LLMs" — it is a language for the joint computational model that
only exists when you fuse deterministic and semantic machines.

Cell is the language of the seam between classical and semantic computing.

## Why Neither Substrate Alone Works

**Classical computer alone**: can manage the task graph, evaluate `⊢=`
(deterministic) cells, check structural oracles, enforce immutability,
handle `⊥` propagation. Cannot evaluate `∴` (soft) cells. Cannot check
semantic oracles ("does this summary capture the main points?"). A
classical runtime can orchestrate but cannot think.

**Semantic computer alone**: can evaluate soft cells, check semantic
oracles, make judgments. Cannot reliably manage graph state. Cannot
guarantee deterministic computations are correct. Cannot enforce
immutability across a growing frontier. An LLM can think but cannot
reliably administrate.

**Cell requires both**: the graph operations are classical. The evaluation
of soft cells is semantic. Oracle checking spans both — some oracles are
deterministic (classical), some are semantic (LLM). `⊥` propagation
follows classical rules triggered by semantic failures. Spawner decisions
are semantic (what to spawn?) governed by classical structure (until
clauses, frontier management).

## Cell-Zero: The Kernel

Cell-zero is a `.cell` file. It is a Cell program, like any other. But it
provides the evaluation kernel — the fundamental operations that make
running Cell programs possible.

### What cell-zero provides

1. **Graph reading**: inspect the frontier, find ready cells, check
   execution state
2. **LLM invocation**: send a soft cell to the semantic substrate,
   receive tentative output
3. **Oracle spawning**: for each oracle on a cell, spawn a claim cell
   that checks the oracle against the tentative output
4. **Freeze/rewrite**: when oracles pass, freeze the output (commit to
   the graph). When oracles fail, rewrite (retry) or propagate `⊥`
5. **⊥ propagation**: when a cell's input is `⊥`, evaluate its `⊥?`
   handler (itself a cell) to decide: skip, error-value, or crash
6. **Spawner management**: when a `⊢⊢` cell fires, add its spawned
   cells to the frontier

### The Scheme analogy

Cell-zero is to Cell what the metacircular evaluator is to Scheme:

```
CPU → Scheme REPL → Scheme compiler → user programs
LLM + runtime → cell-zero.cell → evaluation kernel → user .cell files
```

You can write a Scheme compiler in Scheme. You can write cell-zero in
Cell. The evaluator is a program in its own language.

But Cell goes further. In Scheme, the metacircular evaluator is
a thought experiment — you still need a "real" implementation underneath.
In Cell, cell-zero is the real implementation. The LLM reads cell-zero.cell
and follows its instructions. Cell-zero IS the evaluator, running on the
semantic substrate.

### Substrate independence

The same cell-zero.cell can be executed by:

- **A classical runtime** that handles graph ops, deterministic cells,
  and structural oracles, but delegates soft cells to an LLM API
- **An LLM directly** that reads cell-zero as instructions and performs
  the evaluation loop in its context window
- **A hybrid** (the practical mode) where classical code manages the
  graph and the LLM evaluates soft cells

Confluence guarantees that all three produce the same frozen set,
regardless of evaluation order.

## Everything Is a Cell

### Oracles are cells

`⊨ message mentions «name»` is not a special assertion mechanism. It is
syntactic sugar for a cell:

```
⊢ greet·oracle·1
  given message ← tentative-output-of(greet)
  given name ← input-of(greet, "name")
  yield pass

  ∴ Does «message» mention «name»?

  ⊢= pass ← true  -- if the oracle determines yes
```

When cell-zero evaluates `greet`, it:
1. Sends the `∴` body to the LLM, receives tentative output
2. Spawns oracle cells (one per `⊨` on `greet`)
3. Evaluates the oracle cells
4. If all pass → freezes `greet` with the tentative output
5. If any fail → drops the oracle cells, rewrites `greet` (retry)

### ⊥ handlers are cells

`⊥? skip with records ≡ [], count ≡ 0` is a cell that cell-zero spawns
when it detects `⊥` in a cell's inputs:

```
⊢ parse·bottom·handler
  given payload ← ⊥
  yield records, count

  ⊢= records ← []
  ⊢= count ← 0
```

Cell-zero evaluates this handler cell, then freezes `parse` with the
handler's outputs.

### Deterministic cells are cells

`⊢= count ← |items|` is a cell with trivial evaluation. Cell-zero
spawns it, evaluates it (pure computation, no LLM needed), and freezes
it. The evaluation is deterministic but the mechanism is uniform.

Crystallization is the optimization: when a cell's evaluation is provably
deterministic, cell-zero can short-circuit the spawn-evaluate-freeze
cycle and compute the result directly. This is performance, not semantics.

### Cell-zero is a cell

Cell-zero is a cell that manages the frontier. Its "evaluation" is the
act of evaluating other cells. It never finishes because the frontier
keeps growing (non-termination is a feature). Cell-zero's inputs are the
graph. Its outputs are graph operations.

## The Evaluation Loop

```
          ┌─────────────────────────────────────┐
          │            cell-zero                 │
          │                                      │
          │  1. Read frontier: find ready cells   │
          │  2. Pick a cell to evaluate           │
          │  3. Send ∴ body to LLM (or compute)  │
          │  4. Receive tentative output          │
          │  5. Spawn oracle claim cells          │
          │  6. Evaluate claim cells              │
          │  7. All pass? → freeze                │
          │     Any fail? → rewrite (retry)       │
          │     Exhausted? → freeze with ⊥       │
          │  8. Check downstream ⊥ handlers      │
          │  9. If ⊢⊢ spawner: add new cells     │
          │  10. Go to 1                          │
          │                                      │
          │  (never terminates — the frontier     │
          │   grows monotonically)                │
          └─────────────────────────────────────┘
```

The loop is classical (steps 1, 2, 5, 7, 8, 9 are graph operations).
The evaluation is semantic (step 3 requires an LLM for soft cells).
The oracle checking is both (step 6 — deterministic oracles are classical,
semantic oracles are LLM).

## Key Properties

### Confluence

Independent evaluation steps commute. If cells A and B are both ready
and independent (no data dependency), evaluating A then B produces the
same graph as evaluating B then A. Proven in Lean (`eval_diamond` theorem).

This is what makes the fusion work. The LLM's evaluation order is
non-deterministic, but confluence guarantees the graph converges
regardless.

### Monotonicity

The frozen set only grows. Once a cell's output is committed (oracles
passed, cell-zero freezes it), it never changes. The past is immutable.
The future (frontier) can be rewritten freely.

Tentative outputs are NOT frozen. They live in claim cells on the
frontier. Oracle failure means claim cells are dropped and the original
cell is rewritten — no frozen state is ever touched.

### Non-termination

Cell programs do not terminate. The frontier grows monotonically:
- Spawners (`⊢⊢`) add cells
- Oracle checking adds claim cells
- ⊥ handling adds handler cells
- Even evaluation of a single cell can grow the graph

Termination is the caller's problem. A Cell program is a living document.
Cell-zero keeps evaluating as long as there are ready cells on the
frontier. When nothing is ready, the program quiesces but doesn't
terminate — new inputs or external events can wake it.

### Immutability invariant

The core theorem: graph operations cannot modify frozen nodes.

- `execute_irreversible`: once frozen, always frozen
- `dropNode_preserves_frozen`: dropping frontier nodes doesn't touch
  frozen ones
- `execute_grows_frozen`: each freeze strictly grows the frozen set

Proven in Lean (`GraphOps.lean`). This is the invariant that makes
everything else possible.

## The Tentative State

When cell-zero evaluates a cell:

```
unexecuted ──evaluate──→ tentative(output)
                              │
                    spawn oracle claim cells
                              │
                         ┌────┴────┐
                    all pass    any fail
                         │         │
                    freeze    retry (rewrite)
                         │         │
              executed(output)   unexecuted
                                 (with failure context)
```

The tentative output lives in the claim cells, not in the node's
execution state. The node remains "unexecuted" in the graph until
cell-zero freezes it. This is why retry doesn't violate immutability —
there's nothing to revert.

## What This Means for the Lean Model

The current Lean formalization models `ExecState` as:
```
unexecuted | executing | executed(output)
```

This needs refinement:
- `executing` should carry tentative output context (or this lives in
  claim cells, which are separate graph nodes)
- The `evaluate` operation should be split from `freeze`
- Oracle claim cells should be modeled as graph nodes with special
  structure
- The confluence proof should extend to cover the evaluate-claim-freeze
  cycle

The core theorems (immutability, confluence, monotonicity) still hold.
The tentative state doesn't weaken them — it strengthens the model by
explaining HOW oracle checking works without violating immutability.

## What This Means for the Spec

The v0.1 spec says `⊨? on failure: retry with ... max N`. This is
correct syntax but incomplete semantics. The spec should explain:

1. Retry is a graph rewrite, not a state mutation
2. Oracle checking spawns claim cells
3. The tentative output lives in claim cells, not in the node
4. `⊥? skip with ...` is a cell that cell-zero spawns and evaluates
5. Cell-zero is a `.cell` file, not a built-in

## The Bridge

Cell doesn't solve classical computing. Cell doesn't solve semantic
computing. Cell solves the problem of making them work together.

The classical substrate provides: reliability, determinism, state
management, immutability enforcement.

The semantic substrate provides: soft evaluation, judgment, natural
language understanding, creative generation.

Cell provides: the graph structure that lets them collaborate without
stepping on each other. Confluence is the guarantee. Cell-zero is the
bridge. The fusion is the language.
