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

### Bottom (⊥) as absence

⊥ is not a value. It is the ABSENCE of a value. A cell whose output
is never bound has output = ⊥ (bottom of the lattice).

In the graph model, ⊥ propagation is simply "the wavefront stops":

1. Cell A produces ⊥ (oracle exhaustion or upstream ⊥)
2. Cell B depends on A→output
3. Cell-zero checks: does B have a `⊥?` handler for A→output?
4. **With handler**: cell-zero spawns the handler cell, which provides
   fallback values. B is frozen with the fallback. Downstream proceeds.
5. **Without handler**: cell-zero can't evaluate B (input is absent).
   B's outputs remain unbound (⊥). Downstream sees ⊥.

No special ⊥ propagation machinery needed. It falls out naturally
from the graph evaluation rules:
- A cell is ready when all inputs are bound
- ⊥ inputs are not bound (they're absent)
- Without a handler, the cell is never ready
- Its outputs are therefore never bound
- Downstream cells that depend on those outputs are also never ready

The `⊥?` handler breaks the chain by providing values where none
exist — it LIFTS the cell from ⊥ to a concrete value.

This connects to domain theory: the frozen set forms a lattice under
the "more defined" ordering. ⊥ is bottom. Monotonicity means values
only increase. `⊥?` handlers are bottom-lifting functions.

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

## Crystallization as Optimization

In the fusion model, crystallization has a precise meaning:
**replacing semantic evaluation with classical evaluation**.

A soft cell (`∴`) requires an LLM to evaluate. A crystallized cell
(`⊢=`) requires only classical computation. The transformation is:

```
∴ Count the words in «text».     →     ⊢= split(«text», " ").length
```

Semantically, nothing changes. The cell has the same inputs, outputs,
and oracles. What changes is which substrate evaluates it. Before
crystallization: LLM. After: classical runtime.

This is why crystallization is an optimization, not a semantic change.
The oracles still hold. The frozen output is the same. Cell-zero
doesn't care which substrate produced the output — it just checks the
oracles either way.

### The crystallization spectrum

```
                    semantic ←———————————→ classical

∴ "summarize the document"                              (pure LLM)
∴ "extract the numbers"                                 (mostly LLM)
⊨ count = len(tokens)          oracle IS implementation (LLM → code)
⊢= split(text, " ").length                             (pure code)
```

Every cell exists somewhere on this spectrum. Crystallization moves
cells rightward. The `⊨` oracle that literally states the implementation
is the transition point — where the semantic description becomes
precise enough to be classical.

### What cannot crystallize

- `crystallize` itself (the cell that generates ⊢= from ∴)
- `eval-one` (the cell that interprets arbitrary ∴ blocks)
- Any cell that operates on `§` values (cell definitions as data)
- Cell-zero (the evaluation kernel)

These are permanently semantic. They are the "stem cells" — expensive,
pluripotent, rarely activated, essential for growth. They are what
makes Cell a fusion language rather than a classical language with
LLM calls.

## The Proof-Carrying Pattern

The paradigmatic example of fusion computing:

```
⊢ solve                           -- SEMANTIC: find a solution
  given equation
  yield x, proof[]
  ∴ Solve «equation». Show your work in «proof».

⊢ verify ▸ crystallized           -- CLASSICAL: check the solution
  given solve→x, equation
  yield holds
  ⊢= holds ← eval(lhs, x) == eval(rhs, x)
```

The LLM operates in NP-space (find a solution — hard, unreliable).
The classical verifier operates in P-space (check the solution — easy,
reliable). Neither alone is useful:

- LLM without verifier: might produce wrong answers
- Verifier without LLM: can check but cannot solve

Together they form a complete system. The LLM's unreliability is
bounded by the verifier's reliability. This pattern is only possible
in a fusion language — one that treats both substrates as equal
partners.

### Generalization

The proof-carrying pattern generalizes to ANY problem where:
- Finding is hard but checking is easy (NP problems)
- Generation is creative but validation is structural
- The LLM proposes, code disposes

This includes: code generation + testing, document writing + style
checking, data extraction + schema validation, plan generation +
constraint checking. Cell makes all of these first-class.

## Cell Is Not a Workflow Engine

Workflow engines (Airflow, Prefect, Temporal) are classical programs
that call LLMs as external services. The control flow is classical.
The LLM is a tool, like a database or an API.

Cell is different:

| Aspect | Workflow Engine | Cell |
|--------|----------------|------|
| Control flow | Classical (code) | Graph (cell-zero) |
| LLM role | External tool | Equal substrate |
| Verification | Testing (post-hoc) | Oracles (inline) |
| Self-modification | Not possible | Crystallization + §quotation |
| Error handling | Try/catch | ⊥ propagation + handler cells |
| Growth | Fixed DAG | Spawner-driven frontier growth |
| Termination | Expected | Not guaranteed (by design) |
| State | External (DB, files) | The document IS the state |

A workflow engine answers: "how do I orchestrate LLM calls?"
Cell answers: "what kind of programs exist in a world with both
classical and semantic computation?"

## Formal Connections

### Oracle Turing Machines

Cell has structural similarity to oracle TMs from complexity theory.
An OTM is a TM with access to an oracle that answers questions the
TM cannot compute. In Cell:

- The TM is the classical substrate (graph operations, deterministic
  cells, structural oracles)
- The oracle is the LLM (soft cells, semantic oracles)

But Cell goes beyond OTMs: in Cell, the oracle's answers are checked
by other oracle calls (because oracles are cells). This creates a
self-referential verification structure that OTMs don't have.

### Kahn Process Networks

Cell's dataflow model resembles Kahn Process Networks (KPN):
- Cells are processes
- `given`/`yield` edges are channels
- Execution is demand-driven (a cell evaluates when inputs are ready)
- Confluence (monotone functions on complete partial orders)

Cell extends KPN with: non-deterministic evaluation (LLM), oracle
verification (postconditions on channels), and frontier growth
(dynamic process creation via spawners).

### The Lambda Calculus Connection

Cell-zero as metacircular evaluator evokes the lambda calculus:
- A cell definition is a lambda (inputs → outputs)
- Cell-zero is eval/apply
- `§` quotation is quote/unquote
- Crystallization is partial evaluation

But Cell is not the lambda calculus. The lambda calculus is about
function application. Cell is about graph evaluation. The key
difference: in lambda calculus, evaluation reduces (terms get
smaller). In Cell, evaluation grows (the frontier expands).

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

## What Is Semantic Computation?

The user's original question: "What is the Turing machine of semantic
computers?"

The Turing machine captures the essence of classical computation: a
finite-state machine reading and writing symbols on a tape, following
deterministic rules. Everything a computer can do reduces to this.

What's the equivalent for semantic computation?

### A semantic computer is not a Turing machine

A Turing machine's power comes from its determinism: given the same
input and program, it always produces the same output. A semantic
computer's power comes from the opposite — given a natural language
instruction, it produces a "reasonable" output that varies with context,
phrasing, and internal state.

Key differences:

| Property | Turing Machine | Semantic Computer |
|----------|---------------|-------------------|
| Input | Formal symbols | Natural language |
| Output | Deterministic | Probabilistic, "reasonable" |
| Program | State transitions | Intent descriptions |
| Halting | Decidable for finite | Not meaningful |
| Composition | Function composition | Graph evaluation |
| Verification | Run it again | Oracle checking |

### The generate-and-check model

The closest formal analogue: a **nondeterministic Turing machine**
with a **verifier**.

- The LLM generates (like the nondeterministic branch)
- The oracles verify (like the deterministic check)
- The combination is sound: wrong outputs are caught

This is the NP analogy. The LLM explores the solution space. The
verifier confirms valid solutions. Neither alone is sufficient.

But Cell goes further: the verifier (oracle) can itself be semantic.
A semantic oracle like "does this summary capture the main points?"
requires LLM judgment to check. This creates a hierarchy:

```
Deterministic oracle: exact check, classical substrate
Structural oracle:    pattern check, classical substrate
Semantic oracle:      judgment call, semantic substrate
  └── checked by meta-oracle (itself potentially semantic)
```

The hierarchy bottoms out at human judgment: a human reads the output
and decides if it's good enough. Cell's oracle system is a formal
model of this informal process.

### You don't need to formalize "reasonable"

Cell's insight: you don't need a formal definition of what an LLM
computes. You just need to CHECK the output.

Classical computing needed Church-Turing to define computability.
Semantic computing doesn't need an equivalent because it operates
in human-interpretable space. The "specification" is natural language.
The "verification" is oracle checking. The formal structure is the
graph that connects them.

This is why Cell works without a theory of LLM computation. Cell
doesn't model what the LLM does — it models the STRUCTURE around
the LLM: inputs, outputs, dependencies, invariants, verification.
The LLM is a black box that produces outputs. Cell is the framework
that makes those outputs trustworthy.

### The essence of fusion computing

If classical computation is "follow these exact rules,"
and semantic computation is "achieve this intent,"
then fusion computation is "achieve this intent, and I'll check your work."

Cell is the language for expressing that bargain.

## Sketch: What Cell-Zero Looks Like

Cell-zero is a `.cell` file. Here's what its cells might look like:

```
-- cell-zero.cell: the evaluation kernel

⊢ scan-frontier
  given §graph
  yield ready-cells[], blocked-cells[]

  ∴ Read «§graph». Find all cells whose given inputs are
    fully bound. These are the ready cells.
    Cells with unbound inputs are blocked.

  ⊨ every cell in ready-cells has all givens bound
  ⊨ ready-cells ∪ blocked-cells = all cells in §graph

⊢ pick-next
  given scan-frontier→ready-cells
  yield §target

  ∴ Choose one cell from «ready-cells» to evaluate next.
    Prefer cells with fewer dependencies (leaf-first).

  ⊨ §target ∈ ready-cells

⊢ evaluate
  given pick-next→§target
  yield tentative-output, §claim-cells[]

  ∴ Evaluate «§target»:
    If it has ∴: send to LLM, receive output
    If it has ⊢=: compute deterministically
    Then for each ⊨ on the cell, create a claim cell
    that checks the oracle against the tentative output.

  ⊨ |§claim-cells| = number of oracles on §target

⊢ check-claims
  given evaluate→§claim-cells
  given evaluate→tentative-output
  yield all-pass, failed-oracles[]

  ∴ Evaluate each claim cell. Collect results.

  ⊢= all-pass ← |failed-oracles| = 0

⊢ commit-or-retry
  given check-claims→all-pass
  given evaluate→tentative-output
  given pick-next→§target
  yield §action

  ∴ If «all-pass»: freeze §target with tentative-output.
    If not: check retry policy (⊨?).
    If retries remain: rewrite §target with failure context.
    If exhausted: freeze §target with ⊥.

  ⊨ §action ∈ {freeze, rewrite, bottom}

⊢⊢ loop
  given commit-or-retry→§action
  given §graph
  yield §graph'
  until scan-frontier→ready-cells is empty

  ∴ Apply «§action» to «§graph».
    Then loop: scan frontier again, pick next, evaluate.
    This never terminates — the frontier keeps growing.
```

Note that cell-zero uses all of Cell's own features: `∴` for soft
evaluation, `⊢=` for deterministic checks, `⊨` for oracle assertions,
`§` for quotation (treating the graph and cells as data), `⊢⊢` for
the evaluation loop (itself a spawner).

This is the metacircular property: cell-zero IS a Cell program that
evaluates Cell programs. The substrate (LLM + runtime) reads cell-zero
and follows its instructions. Cell-zero could be crystallized — the
`scan-frontier` and `pick-next` cells could become `⊢=` (deterministic).
The `evaluate` cell stays soft forever.

## Open Questions

1. **Cell-zero specification**: The sketch above is illustrative. The
   real cell-zero.cell needs precise semantics for graph mutation,
   oracle spawning, and ⊥ propagation. Can we write it fully?

2. **Claim cell lifecycle**: When cell-zero spawns oracle claim cells,
   how are they named? How do they connect to the graph? Are they
   visible to the user or hidden by cell-zero?

3. **Substrate negotiation**: When cell-zero encounters a cell, how
   does it decide which substrate to use? Is this explicit (∴ vs ⊢=)
   or inferred?

4. **Formal verification scope**: The Lean model proves confluence
   for the simplified graph. How much of the full model (tentative
   outputs, claim cells, ⊥ handlers as cells) should be formalized?

5. **Cost model**: Semantic evaluation is expensive. Classical is
   cheap. Cell needs a cost model that accounts for both. This
   affects crystallization priorities — crystallize the most
   frequently-evaluated cells first.

6. **The halting question**: Cell programs don't terminate. But
   practical programs need to produce results. How does a caller
   observe a Cell program's state? Is there a "quiescent" notion
   (frontier is empty or all cells are blocked)?
