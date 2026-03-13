# Cell: Minimum Viable Language Specification

*The smallest kernel that is still recognizably Cell.*

## Design Rationale

Cell v0.2 has 15+ features. Many are powerful but not identity-defining.
This document strips Cell to its **irreducible core** — the features without
which the language stops being Cell and becomes something else.

The test for inclusion: "If we remove this, is Cell still Cell?"

## What Cell Is (Unchanged)

Cell is a self-bootstrapping metacircular language for LLMs. Programs are
documents. Execution fills in values. The document IS the program IS the state.

Cell requires both a classical computer and a semantic computer to execute.
Neither alone is sufficient.

## The Kernel: 7 Features

### Feature 1: Cell Declarations (`⊢`, `given`, `yield`)

A cell is a named unit of computation with typed inputs and outputs.

```
⊢ name
  given input1
  given input2 ≡ "default value"
  given other-cell→output
  yield output1, output2
```

**Why essential**: Without cells, there is no language. The `given`/`yield`
interface is how data flows. The `→` notation for output access and `≡` for
binding are inseparable from declaration — they're how the DAG is wired.

### Feature 2: Soft Bodies (`∴`)

Natural language computation. The semantic substrate.

```
⊢ summarize
  given text
  yield summary

  ∴ Summarize «text» in 2-3 sentences, preserving key facts.
```

**Why essential**: This is what makes Cell a language *for LLMs*, not a
language that *calls* LLMs. The `∴` block is an instruction to the semantic
substrate. Remove it and Cell is just another dataflow language.

The `«»` guillemets for interpolation are part of `∴` — they splice frozen
values into the natural language instruction.

### Feature 3: Hard Bodies (`⊢=`)

Deterministic computation. The classical substrate.

```
⊢ word-count
  given text
  yield count
  ⊢= count ← len(split(«text», " "))
```

**Why essential**: The soft/hard spectrum IS Cell's thesis. A language with
only `∴` is a prompt template. A language with only `⊢=` is a spreadsheet.
Cell is the *fusion* — the same declaration syntax spans both substrates.

#### Minimum `⊢=` Expression Language

To make the soft/hard boundary meaningful, `⊢=` needs a defined set of
valid operations. The minimum viable set:

| Category | Operations |
|----------|-----------|
| Arithmetic | `+`, `-`, `*`, `/`, `%` |
| Comparison | `=`, `!=`, `<`, `>`, `<=`, `>=` |
| Boolean | `and`, `or`, `not`, `true`, `false` |
| String | `split(s, d)`, `join(list, d)`, `contains(s, sub)`, `length(s)`, `trim(s)` |
| List | `len(list)`, `sort(list)`, `take(list, n)`, `drop(list, n)`, `filter(list, pred)`, `map(list, fn)`, `concat(a, b)` |
| Access | `x→field`, `list[i]` |
| Binding | `name ← expression` |
| Conditional | `if cond then a else b` |

The rule: if an expression requires subjective judgment or world knowledge,
it belongs in `∴`, not `⊢=`.

### Feature 4: Oracles (`⊨`)

First-class verification. Postconditions that are checked, not hoped for.

```
⊢ classify
  given text
  yield label
  ∴ Classify «text» as "positive", "negative", or "mixed".
  ⊨ label ∈ {"positive", "negative", "mixed"}
```

**Why essential**: Oracles are what make Cell programs *verifiable* despite
containing LLM computation. They enable:
- Proof-carrying computation (NP-solve + P-verify)
- The retry-with-feedback loop (oracle failure → rewrite → re-evaluate)
- Trust boundaries between soft and hard

Without oracles, Cell has no quality control. Any prompt template can
produce output. Only Cell *checks* it.

Oracles are cells themselves — claim cells spawned by the runtime after
evaluation. This means oracle checking participates in the same graph
mechanics. No special machinery.

#### Oracle Types

```
⊨ result = 55                    -- deterministic (exact value check)
⊨ sorted is a permutation        -- structural (checkable by code)
⊨ summary is 2-3 sentences       -- semantic (requires LLM judgment)
```

Oracle checking spans both substrates: deterministic oracles run classically,
semantic oracles run on the LLM.

### Feature 5: Bottom (`⊥`)

Absence of value as a first-class signal.

```
⊢ compress
  given text
  yield summary
  ∴ Compress «text» to half its length.
     If compression would lose critical meaning, yield ⊥ for summary.
```

**Why essential**: Without `⊥`, Cell has no principled way to handle:
- Oracle exhaustion (all retries failed)
- Guard-induced skipping (conditional dispatch)
- Explicit "no answer" signals from soft cells

`⊥` turns error handling from an afterthought into a dataflow primitive.
It propagates: a cell with `given x→field` where `field ≡ ⊥` is blocked
permanently. This is Railway Oriented Programming built into the DAG.

### Feature 6: Quotation (`§`)

Cell definitions as data. Code as data.

```
§greet              -- the definition of greet (not its output)
given §target       -- input expects a cell definition
«§target»           -- interpolate the definition into a prompt
```

**Why essential**: This is what makes Cell metacircular — "the Scheme of
LLMs." Without `§`, Cell cannot:
- Define its own evaluator (cell-zero)
- Crystallize itself (write `⊢=` bodies for `∴` bodies)
- Pass cell definitions to evolution loops

Remove `§` and Cell loses its self-bootstrapping property. It becomes a
static dataflow language that happens to call LLMs.

### Feature 7: eval-one Execution Model

Kahn's algorithm, one step at a time.

1. Find all cells whose `given` inputs are fully bound (`≡` present)
2. Pick ONE such cell
3. Evaluate it (`∴` via LLM, or `⊢=` deterministically)
4. Spawn oracle claim cells to verify tentative output
5. If all claims pass: freeze output (`yield ≡` values)
6. If any claim fails: retry (rewrite with failure context) or produce `⊥`
7. Repeat

#### Properties (non-negotiable)

| Property | Statement | Why essential |
|----------|-----------|---------------|
| **Document-is-state** | The program text IS the execution state. Each step changes exactly one `yield` line to include `≡ value`. | Without this, Cell is not a document language. |
| **Monotonicity** | Yields only get bound, never unbound. The frozen set only grows. | Without this, content addressing breaks. |
| **Confluence** | Execution order of independent cells doesn't matter. Same final result regardless of scheduling. | Without this, parallel execution is unsafe and Cell is order-dependent. |
| **Content addressing** | Hash the document = hash the state. Each eval-one step = hash transition (h₀ → h₁ → h₂ → ...). | Without this, there is no audit trail. |
| **Dual substrate** | `⊢=` cells execute classically. `∴` cells execute semantically. Oracle checking spans both. | This IS Cell's computational model. |

## Symbol Table (Kernel Only)

| Symbol | Name | Meaning |
|--------|------|---------|
| `⊢` | turnstile | declare a cell |
| `∴` | therefore | natural language body (soft) |
| `⊢=` | hard turnstile | deterministic body (hard) |
| `⊨` | models | oracle assertion |
| `§` | section | quotation (definition as data) |
| `«»` | guillemets | interpolation |
| `≡` | identical | binding |
| `→` | arrow | output access |
| `⊥` | bottom | absence of value |

9 symbols. Everything else is syntax on top of these.

## What Is NOT in the Kernel (and Why)

Each feature below is valuable but removable without losing Cell's identity.
They can be added as extensions without changing the kernel semantics.

### Evolution Loops (`⊢∘`) — Deferred

Self-improvement via fixed-point iteration.

```
⊢∘ evolve(greet, name ≡ "Alice")
  through judge, improve
  until judge→quality ≥ 7
  max 5
```

**Why deferrable**: Evolution loops are *sugar* over the kernel. You can
manually wire a judge cell, an improve cell, and a loop counter using
`given`/`yield` and `§`. The `⊢∘` syntax compresses this pattern but
doesn't introduce new computational power. Cell programs that don't
self-improve are still Cell programs.

**When to add**: When the kernel is stable and self-improvement patterns
are well-understood.

### Spawners (`⊢⊢`) — Deferred

Dynamic frontier growth. Programs that grow.

```
⊢⊢ spawn
  given explore→follow-ups
  given §explore
  yield §new-cells[]
  until depth > 5
```

**Why deferrable**: Spawners add *dynamic* growth to the DAG. But a Cell
program with a fixed set of cells is still a valid Cell program. Most
useful programs have a known structure at write time. Dynamic growth is
an optimization for open-ended exploration, not a core requirement.

**When to add**: After the kernel supports static programs well. Spawners
also require wildcards (`cell-*→field`) to be useful, making them a
natural second-layer feature.

### Guard Clauses (`where`) — Deferred

Conditional cell activation.

```
given classify→label where label = "toxic"
```

**Why deferrable**: Guards are syntactic sugar for a pattern achievable
with `⊥` and conditional cells. Without guards, you need an explicit
routing cell. Less elegant, but the same computational power.

### Optional Dependencies (`given?`) — Deferred

Dependencies that tolerate `⊥`.

```
given? compress→next-summary    -- accepts ⊥ as a value
```

**Why deferrable**: In the minimum kernel, all dependencies block on `⊥`.
Optional dependencies are needed for co-evolution and `⊥`-aware patterns
but are not required for the majority of programs.

### Recovery Policies (`⊨?`) — Deferred

Meta-oracles for failure handling.

```
⊨? on failure: retry with «oracle.failures» max 3
⊨? on exhaustion: error-value(⊥)
```

**Why deferrable**: The kernel already has oracle failure → `⊥`. A default
policy of "retry once, then `⊥`" is sufficient for the minimum viable
language. Sophisticated retry strategies are important for production use
but not for establishing the language's identity.

### Wildcard Dependencies (`cell-*→field`) — Deferred

Depends on spawners. Deferred with them.

### Refinement Annotations (`▸`) — Deferred

```
⊢ word-count ▸ crystallized
```

Documentation/metadata. No semantic effect on execution.

### Co-evolution (`⊢∘ co-evolve`) — Deferred

Advanced pattern for circular dependencies. Requires evolution loops.

### Conditional Oracles — Deferred

```
⊨ if drift-score <= 1 then acceptable = true
```

Sugar over a guard + oracle combination. Not needed in the kernel.

## The Crystallization Story (Kernel-Compatible)

Crystallization — the progression from soft to hard — is *emergent* from
the kernel, not an additional feature:

1. Write a cell with `∴` (soft)
2. Write oracles (`⊨`) that define correct behavior
3. Use `§` to pass the cell to a crystallizer
4. The crystallizer writes a `⊢=` body that satisfies the oracles
5. The `⊢=` version replaces `∴` calls — same interface, deterministic

The kernel provides `∴`, `⊢=`, `⊨`, and `§`. Crystallization falls out
of combining them. No additional syntax required.

## The Bootstrap Story (Kernel-Compatible)

Cell-zero — the metacircular evaluator — is expressible with the kernel:

1. `⊢ read-graph` — inspect the frontier (soft cell)
2. `⊢ find-ready` — identify cells with all inputs bound (soft cell)
3. `⊢ evaluate` — execute a soft cell via LLM (uses `§`)
4. `⊢ check-oracles` — spawn and evaluate claim cells (uses `§`)
5. `⊢ freeze-or-rewrite` — commit output or retry (soft cell)

No evolution loops, spawners, or guards needed. The kernel supports
metacircular evaluation directly.

## Example: Complete MV-Cell Program

```
-- A complete Cell program using only kernel features.
-- Proof-carrying computation: solve an equation, verify the answer.

⊢ problem
  given equation ≡ "2x + 3 = 11"
  yield equation

⊢ solve
  given problem→equation
  yield x, method

  ∴ Solve «problem→equation» for x. Show your work in «method».

  ⊨ x is a number

⊢ verify
  given solve→x
  given problem→equation
  yield holds

  ⊢= holds ← 2 * solve→x + 3 = 11

  ⊨ holds = true

⊢ report
  given solve→x
  given solve→method
  given verify→holds
  yield summary

  ∴ Write a one-paragraph summary of the solution.
     Equation: «problem→equation»
     Answer: x = «solve→x»
     Method: «solve→method»
     Verified: «verify→holds»

  ⊨ summary mentions «solve→x»
```

**Execution trace**:
- h₀: All yields unbound
- h₁: `problem` freezes (literal input)
- h₂: `solve` evaluates via LLM, oracle checks `x`, freezes
- h₃: `verify` evaluates deterministically via `⊢=`, freezes
- h₄: `report` evaluates via LLM, oracle checks mention, freezes

4 cells. 2 soft, 1 hard, 1 literal. Both substrates exercised.
Oracle failure on `solve` → retry with feedback → or `⊥` → `verify` blocked.

## Layering Plan

The full Cell language is built in layers on the kernel:

| Layer | Features | Enables |
|-------|----------|---------|
| **0 (Kernel)** | `⊢`, `∴`, `⊢=`, `⊨`, `⊥`, `§`, eval-one | Static dataflow, proof-carrying, crystallization, bootstrap |
| **1 (Control)** | `given?`, `where` guards, `⊨?` recovery | Conditional dispatch, ⊥-tolerant patterns, retry policies |
| **2 (Growth)** | `⊢⊢` spawners, `cell-*→field` wildcards | Dynamic programs, semantic automata |
| **3 (Evolution)** | `⊢∘` loops, `▸` annotations, co-evolution | Self-improvement, iterative refinement |

Each layer depends only on layers below it. The kernel is complete without
any higher layer.

## What "Minimum Viable" Means

A minimum viable Cell program:
- Declares cells with `⊢`, `given`, `yield`
- Has at least one soft body (`∴`) — otherwise it's just a spreadsheet
- Has at least one oracle (`⊨`) — otherwise there's no verification
- Executes via eval-one on the fused classical+semantic substrate

A program meeting these criteria is *recognizably Cell*. It participates in
the document-as-state paradigm, exercises both substrates, and produces a
verified, content-addressable execution trace.

Everything beyond this makes Cell *better*. Nothing beyond this makes Cell
*Cell*.
