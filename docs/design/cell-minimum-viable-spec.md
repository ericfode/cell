# Cell: Minimum Viable Language Spec

*The smallest kernel that is still recognizably Cell.*

## Methodology

This spec was derived by reviewing the v0.2 spec, the computational model,
the Lean4 formalization, the Go implementation, 17 rounds of evolution notes,
and the codebase survey. Each feature was evaluated against the question:
"If you remove this, is the remaining language still *recognizably* Cell —
or is it just another reactive dataflow engine?"

## What Makes Cell Cell

Cell's thesis: programs exist in a world with **both** deterministic and
semantic computation. Neither alone is sufficient. Cell is the language
of the seam between them.

Five properties distinguish Cell from everything else:

1. **Dual-substrate fusion**: `∴` (soft, LLM) and `⊢=` (hard, code) are
   co-equal evaluation modes with the same graph mechanics.
2. **Document-is-state**: The program text IS the execution state. No
   separate runtime, no hidden state. Hash the document = hash the state.
3. **Oracle verification**: `⊨` assertions are cells themselves. The LLM
   proposes, oracles check. This is proof-carrying computation.
4. **Crystallization pressure**: Soft cells progressively harden into
   deterministic code under oracle pressure. The trajectory is
   soft-everywhere → hard-core, soft-frontier.
5. **Metacircularity via quotation**: `§` makes cell definitions into data.
   Cell can reason about and rewrite itself. Cell-zero (the evaluator) is
   a Cell program.

Remove any one of these five and Cell degenerates into a conventional
workflow engine, a prompt chaining library, or a generic reactive system.

## The Minimum Kernel

### What's IN

| Feature | Why it's essential |
|---------|-------------------|
| `⊢` cell declaration | The computation unit |
| `given` / `yield` | Dataflow wiring — the graph |
| `∴` soft body | Semantic evaluation — THE distinguishing feature |
| `⊢=` hard body | Deterministic evaluation — the dual substrate |
| `⊨` oracle assertions | Verification — what makes LLM output trustworthy |
| `«»` interpolation | How frozen values flow into natural language |
| `≡` binding | How values are assigned and frozen |
| `→` output access | How cells reference each other's outputs |
| `§` quotation | Cell definitions as data — enables metacircularity |
| `⊥` bottom | First-class absence — dataflow error semantics |
| `given?` optional deps | Tolerates `⊥` — needed for practical error handling |
| eval-one model | Kahn's algorithm, one step at a time |

### What's OUT (deferrable to later versions)

| Feature | Why it can wait |
|---------|----------------|
| `⊢⊢` spawners | Dynamic frontier growth is powerful but compound. Static graphs cover most use cases. Can be added as sugar over `§` + manual cell creation. |
| `⊢∘` evolution loops | Fixed-point iteration over cell definitions. Expressible manually with `§` + a loop cell. Important for self-improvement but not for the kernel. |
| `⊢∘ co-evolve` | Circular dependency resolution. Complex semantics (iteration 0 with `⊥` substitution). Deferrable. |
| Wildcard deps (`cell-*→field`) | Convenience pattern for spawner output collection. Requires spawners. |
| Guard clauses (`where`) | Conditional cell readiness. Can be simulated: a cell that always runs and yields `⊥` when the condition is false. |
| `⊨?` recovery policies | Meta-oracle policies. The kernel needs oracle pass/fail. Recovery (retry with feedback, exhaustion handlers) is important but can start as a fixed default: retry 1x then `⊥`. |
| `▸` refinement stage | Metadata annotation. Doesn't affect semantics. |
| Conditional oracles | `if P then Q` oracles. Can be expressed as two cells (one checks P, one checks Q with guard on P). |
| `partial-accept` | Exhaustion handler refinement. Beyond the kernel. |
| `⊢=` expression language | The spec defines ~40 primitives. The kernel needs `⊢=` to EXIST but the expression language can start minimal (arithmetic, comparison, string ops, field access). |

---

## Kernel Specification

### 1. Cell Declaration

```
⊢ name
  given input1
  given input2 ≡ "default value"
  given other-cell→field
  given? optional-cell→field
  yield output1, output2

  ∴ Natural language body using «input1».

  ⊨ output1 satisfies some property
```

A cell is the unit of computation. It declares:
- **Inputs** (`given`): dependencies on other cells' outputs
- **Optional inputs** (`given?`): dependencies that tolerate `⊥`
- **Outputs** (`yield`): named values this cell produces
- **Body**: either `∴` (soft) or `⊢=` (hard)
- **Oracles** (`⊨`): postconditions on outputs

### 2. Dual Evaluation: `∴` and `⊢=`

**Soft body** (`∴`): Natural language interpreted by an LLM.

```
⊢ summarize
  given text
  yield summary

  ∴ Summarize «text» in 2-3 sentences.

  ⊨ summary is 2-3 sentences
```

**Hard body** (`⊢=`): Deterministic expression evaluated classically.

```
⊢ word-count
  given text
  yield count

  ⊢= count ← len(split(«text», " "))
```

The `⊢=` body must be composed entirely of deterministic primitives.
If an expression requires judgment, interpretation, or world knowledge,
it belongs in `∴`, not `⊢=`. This boundary is Cell's fundamental invariant.

**Minimal `⊢=` primitives** (kernel set):
- Arithmetic: `+`, `-`, `*`, `/`, `%`
- Comparison: `=`, `!=`, `<`, `>`, `<=`, `>=`
- Boolean: `and`, `or`, `not`, `true`, `false`
- String: `split(s, d)`, `join(list, d)`, `len(s)`, `contains(s, sub)`
- List: `len(list)`, `sort(list)`, `concat(a, b)`
- Access: `x→field`, `list[i]`
- Binding: `name ← expression`
- Conditional: `if cond then a else b`

### 3. Dataflow Wiring

Cells form a directed acyclic graph via `given`/`yield`:

```
⊢ a
  yield x ≡ 3

⊢ b
  given a→x
  yield doubled

  ⊢= doubled ← a→x * 2
```

- `given other→field`: this cell depends on `other`'s `field` output
- `yield name`: this cell produces `name` as output
- `≡`: binds a concrete value (input default or frozen output)
- `→`: accesses a specific output of another cell

### 4. Interpolation: `«»`

Guillemets splice frozen values into natural language:

```
∴ Write a greeting for «name» that mentions «topic».
```

`«name»` resolves to the frozen value of the `name` input.
`«cell→field»` resolves to the frozen output of another cell.

### 5. Oracle System: `⊨`

Every `⊨` assertion becomes a **claim cell** — an ordinary cell that
checks the oracle against the tentative output.

```
⊢ extract
  given document
  yield entities

  ∴ Extract all named entities from «document».

  ⊨ every item in entities is a proper noun
  ⊨ len(entities) > 0
```

**Oracle types** (all coexist in the kernel):

| Type | Example | Checked by |
|------|---------|-----------|
| Deterministic | `⊨ count = 42` | Classical code |
| Structural | `⊨ sorted is a permutation of input` | Classical code |
| Semantic | `⊨ summary captures the main points` | LLM |

**Oracle lifecycle**:
1. Cell evaluates → tentative output (not yet frozen)
2. Cell-zero spawns claim cells (one per `⊨`)
3. Claim cells evaluate (checking oracle conditions)
4. All pass → **freeze** output (immutable)
5. Any fail → **retry** once with failure context, or **`⊥`**

In the kernel, retry policy is fixed: retry once with `«oracle.failures»`
appended, then `⊥` on second failure. (Full `⊨?` recovery policies are
a later addition.)

### 6. Bottom: `⊥`

`⊥` is first-class absence. Not an error — a signal that "this cell
has no meaningful value."

**Sources of `⊥`**:
- Oracle exhaustion (retry failed)
- Upstream `⊥` propagation (no handler)

**Propagation rules**:
- `given cell→field` where `field ≡ ⊥`: cell is **permanently blocked**.
  It never enters the ready set. Its outputs are `⊥`.
- `given? cell→field` where `field ≡ ⊥`: cell receives `⊥` as a value.
  The `∴` body can inspect it and decide what to do.

No special propagation machinery. It falls out from the graph rules:
a cell is ready when all `given` inputs are bound; `⊥` inputs are not
bound (they are absent); without `given?`, the cell is never ready.

### 7. Quotation: `§`

`§` makes a cell's **definition** into data (not its output).

```
§greet              -- the definition of greet (as a value)
«greet→message»     -- the output of greet (a frozen value)
given §target       -- input: expects a cell definition
«§target»           -- interpolate the definition into a prompt
```

This is what makes Cell metacircular. With `§`:
- Programs can read and reason about other programs
- `crystallize` can read a `∴` body and write a `⊢=` replacement
- Cell-zero can be written in Cell itself

Without `§`, Cell is just a dataflow engine with LLM calls.

### 8. Execution Model: eval-one

Cell uses Kahn's algorithm, one step at a time:

1. Find all cells whose `given` inputs are fully bound
2. Pick ONE such cell (any — confluence guarantees order doesn't matter)
3. Evaluate it:
   - `∴` body → send to LLM, receive tentative output
   - `⊢=` body → evaluate deterministically
4. Spawn oracle claim cells
5. Evaluate claim cells
6. All pass → **freeze** (bind `yield ≡ value`, immutable)
7. Any fail → **retry** or **`⊥`**
8. Repeat

**This loop does not terminate.** The frontier grows monotonically (frozen
cells accumulate). Termination is the caller's problem — observe the
document, check if you have the values you need, stop when satisfied.

### 9. Proven Properties

These properties are proven in Lean4 and are mandatory for any
implementation of the kernel:

| Property | Statement | Why it matters |
|----------|-----------|---------------|
| **Monotonicity** | Yields only get bound, never unbound. The frozen set only grows. | Past is immutable. Cached results are valid forever. |
| **Confluence** | Independent cells can be evaluated in any order. Same final result. | Enables parallelism. Eliminates scheduling bugs. |
| **Immutability** | Graph operations cannot modify frozen nodes. | Trust: once an oracle passes, the value is permanent. |
| **Content addressing** | Hash(document) = Hash(state). Each eval-one = hash transition. | Caching, reproducibility, state addressability. |
| **Document-is-state** | Each step changes exactly one `yield` line to include `≡ value`. | No hidden state. The program IS its own execution log. |

### 10. Crystallization

The signature Cell pattern: soft cells progressively harden.

```
-- SOFT (LLM evaluates):
⊢ word-count
  given text
  yield count
  ∴ Count the words in «text».
  ⊨ count = len(split(«text», " "))

-- HARD (code evaluates, same cell, same oracles):
⊢ word-count
  given text
  yield count
  ⊢= count ← len(split(«text», " "))
  ⊨ count = len(split(«text», " "))
```

Crystallization is **optimization, not semantic change**. The cell has the
same inputs, outputs, and oracles. What changes is which substrate evaluates
it. The oracles still hold.

**What cannot crystallize** (permanently soft):
- `crystallize` itself (the cell that generates `⊢=` from `∴`)
- `eval-one` / cell-zero (interprets arbitrary `∴` blocks)
- Any cell that operates on `§` values (interpreter)

These are the "stem cells" — expensive, pluripotent, rarely activated,
essential for growth.

### 11. The Proof-Carrying Pattern

Cell's paradigmatic use case:

```
⊢ solve
  given equation
  yield x, proof

  ∴ Solve «equation». Show your work in «proof».

⊢ verify
  given solve→x
  given equation
  yield holds

  ⊢= holds ← eval(lhs, x) = eval(rhs, x)
```

The LLM operates in NP-space (find a solution — hard, unreliable).
The verifier operates in P-space (check the solution — easy, reliable).
The verifier ALWAYS catches wrong answers.

Generalizes to: code generation + testing, document writing + style
checking, data extraction + schema validation, plan generation +
constraint checking.

---

## What This Kernel Enables

With just these 11 features, you can write:

- **Proof-carrying computation**: LLM solves, code verifies
- **Self-crystallization**: `§` lets a crystallize cell read soft cells
  and write hard replacements
- **Multi-step reasoning**: Dataflow chains with oracle checkpoints
- **Graceful failure**: `⊥` propagation with `given?` fallbacks
- **Mixed-substrate pipelines**: Some cells are LLM, some are code,
  oracles span both

You CANNOT yet write (these require deferred features):

- **Self-growing programs**: Need `⊢⊢` spawners for dynamic frontier
- **Iterative self-improvement**: Need `⊢∘` evolution loops
- **Conditional branching**: Need guard clauses (workaround: use `⊥`)
- **Fan-out/collect patterns**: Need wildcard dependencies

The kernel is the foundation. The deferred features are the superstructure.

---

## The Crystallization Spectrum (Summary)

```
           semantic ←─────────────────────→ classical

∴ "summarize the document"                            (pure LLM)
∴ "extract the numbers" + ⊨ oracle                   (LLM + verification)
⊨ count = len(tokens)                                (oracle IS implementation)
⊢= split(text, " ").length                           (pure code)
```

Every cell exists somewhere on this spectrum. Crystallization moves cells
rightward. The oracle that literally states the implementation is the
transition point.

---

## Kernel vs v0.2: Feature Map

| v0.2 Feature | In Kernel? | Rationale |
|-------------|-----------|-----------|
| `⊢` cell declaration | **YES** | Core |
| `given` / `yield` | **YES** | Core |
| `∴` soft body | **YES** | Core — THE differentiator |
| `⊢=` hard body | **YES** | Core — dual substrate |
| `⊨` oracle | **YES** | Core — trust model |
| `«»` interpolation | **YES** | Core — value → language bridge |
| `≡` binding | **YES** | Core — how values freeze |
| `→` output access | **YES** | Core — cell wiring |
| `§` quotation | **YES** | Core — metacircularity |
| `⊥` bottom | **YES** | Core — dataflow error model |
| `given?` optional | **YES** | Core — `⊥` handling |
| eval-one | **YES** | Core — execution model |
| `⊨?` recovery | Simplified | Fixed: retry 1x then `⊥` |
| `⊢=` expression lang | Minimal | ~15 primitives (vs ~40 in v0.2) |
| `⊢⊢` spawners | **NO** | Deferred: compound feature |
| `⊢∘` evolution | **NO** | Deferred: compound feature |
| `⊢∘ co-evolve` | **NO** | Deferred: complex semantics |
| Wildcard deps | **NO** | Deferred: requires spawners |
| Guard clauses | **NO** | Deferred: workaround via `⊥` |
| Conditional oracles | **NO** | Deferred: express as two cells |
| `partial-accept` | **NO** | Deferred: refinement |
| `▸` refinement | **NO** | Deferred: metadata only |
| Multi-target `⊢∘` | **NO** | Deferred: requires `⊢∘` |

**Kernel size**: 12 features (11 syntactic + eval-one model)
**v0.2 size**: ~25 features
**Reduction**: ~50% smaller surface area

---

## Implementation Note

The kernel spec uses the **formal notation** (`⊢`, `∴`, `⊨`, `«»`) rather
than the implemented pragmatic syntax (`cell {}`, `prompt:`, `{{}}`, `refs:`).
This is deliberate — the formal notation IS Cell's identity. An implementation
may accept either syntax, but the formal notation is canonical.

The codebase survey (2026-03-13) found that the Go implementation and the
spec describe different languages. Aligning them is a separate task (see
ce-emt survey recommendations). This kernel spec defines WHAT Cell is.
HOW to parse it is an implementation concern.

---

## One-Sentence Summary

Cell is a dataflow language where soft cells (`∴`, evaluated by LLMs) and
hard cells (`⊢=`, evaluated by code) coexist in a confluent graph with
oracle verification (`⊨`), content-addressed state, and metacircular
self-reference (`§`) — enabling programs that progressively crystallize
from semantic intent into deterministic code.
