# Cell v0.1 Spec Review — Rule of Five

**Reviewer**: morpheus (language architect)
**Target**: `docs/design/cell-v0.1-spec.md` (8 rounds of evolutionary discovery)
**Method**: Rule of Five (draft analysis, correctness, clarity, edge cases, excellence)
**Lens**: Lean formal model (GraphOps, ProgramAlgebra, Confluence)

---

## Pass 1: Draft — Shape of the Spec

The spec covers:
- Core syntax (symbols, cell declarations)
- Execution model (eval-one = Kahn's algorithm)
- Quotation (`§`)
- Crystallization (soft `∴` → hard `⊢=`)
- Oracle system (`⊨`, `⊨?`)
- Proof-carrying computation
- Evolution loops (`⊢∘`)
- Self-crystallization
- Frontier growth (`⊢⊢`)
- Cell-as-agent pattern

**What maps to the formal model:**

| Spec concept | Lean formalization | Status |
|---|---|---|
| Cell declaration `⊢` | `CellDecl.cellDef` | Direct mapping |
| `given x→y` | `CellSpec.refs` | Direct mapping |
| `yield` | Part of `CellSpec` (output) | Implicit in model |
| eval-one | `TaskGraph.evalOne` | Proven correct |
| Confluence | `eval_diamond` theorem | **Proven** |
| Monotonicity | `execute_grows_frozen` | **Proven** |
| Crystallization `⊢=` | `Distillation` / `applyDistillation` | Modeled |
| Oracle `⊨` | Not formalized | **Gap** |
| Quotation `§` | Not formalized | **Gap** |
| Evolution `⊢∘` | Not formalized | **Gap** |
| Spawners `⊢⊢` | Not formalized | **Gap** |

**Shape assessment**: The spec has grown organically through 8 rounds. It's rich
with discoveries but reads as a lab notebook, not a language spec. The formal
model covers the execution core solidly. The outer features (oracles, quotation,
evolution) are ahead of the formalization.

---

## Pass 2: Correctness — Logic Alignment with Proofs

### 2.1 Confluence claim is correct but under-specified

The spec says: "Execution order of independent cells doesn't matter. Same final
result regardless of scheduling. Parallel execution valid."

The Lean proof (`eval_diamond`) proves this, but with a hypothesis: `g.uniqueNames`.
The spec doesn't mention unique names as a requirement. **This should be stated
explicitly** — duplicate cell names break confluence.

**Recommendation**: Add to spec: "Cell names within a program MUST be unique."

### 2.2 Termination: lean INTO non-termination

The spec says: "Termination: Guaranteed by monotonicity. No cycles possible."
But Section "Frontier Growth" says: "Termination NOT guaranteed (by design)."

The second statement is the right one. Cell should NOT guarantee termination.
Programs are living documents — they can grow, spawn, evolve indefinitely.
This is a feature, not a bug. Spreadsheets don't terminate. Smalltalk images
don't terminate. Servers don't terminate.

What Cell DOES guarantee:
- **Monotonicity**: values never change, yields only get bound
- **Confluence**: execution order doesn't matter for independent cells
- **Immutability**: the past is frozen, only the frontier is mutable

Termination is the CALLER'S problem (timeouts, budgets, `until` clauses).
The language is honest about this.

**Recommendation**: Remove the termination claim from Section "Properties."
Replace with: "Cell programs are not guaranteed to terminate. Halting is
controlled externally via budgets, `until` on spawners, or operator signal.
The invariant is monotonicity, not termination."

### 2.3 `⊨` oracle assertions vs the immutability invariant

The spec says oracles are checked at runtime. But the Lean model has no oracle
concept — execution just produces an output string. Oracles are a **layer above**
the execution model.

The formal model says: once a node is executed, its output is frozen. But what
happens when `⊨` fails? The spec says "retry with feedback." This means
**un-executing** the node and re-executing it — which violates immutability.

**Resolution options:**
1. Oracles are checked BEFORE freezing the output (execution = produce + validate)
2. Oracle failure creates a NEW node (the retry), not modifying the old one
3. The retry cell is a new cell with the failure context appended

Option 2 aligns with the formal model. The original cell's output is frozen (as
"failed"), and a new cell is spawned for the retry. This preserves immutability.

**Recommendation**: Clarify that oracle failure spawns a retry cell, not mutates.

### 2.4 `§` quotation needs formal semantics

`§greet` passes the cell's definition as data. In the formal model, this is
accessing a `CellSpec` value. But `CellSpec` includes the prompt text, which
might be large.

The formal model has `CellDecl.cellDef spec` — so `§` is essentially a reference
to the `CellDecl` for that cell. This is well-defined.

**What's missing**: Can `§` reference executed cells? Can you `§` a crystallized
cell and see its `⊢=` body? The formal model distinguishes `CellSpec` (static)
from `ExecState` (dynamic). `§` should reference the static part only.

### 2.5 `⊢∘` evolution loop and the bootstrap sequence

The Lean model has `BootstrapSeq` (a list of programs, each a distillation of
the previous). The `⊢∘` syntax is the runtime mechanism for this.

Correctness check: `⊢∘` requires `§cell'` to have the same `given/yield`
signature as `§cell`. The Lean model's `applyDistillation` preserves program
length but doesn't enforce interface preservation. **The Lean model should gain
an interface-preservation theorem for distillation.**

### 2.6 The crystallization boundary (`§` marks it)

Claim: "Any cell that executes §-referenced cells is an interpreter. The § sigil
marks the crystallization boundary."

This is a deep insight that the Lean model doesn't capture yet. In the formal
model, all cells are the same type (`CellSpec`). The distinction between
"crystallizable" and "permanently soft" is semantic, not structural.

**Recommendation**: Consider adding a `CellKind` enum to the formal model:
`soft | hard | interpreter` with a theorem that `interpreter` cells cannot
be distilled.

---

## Pass 3: Clarity — Can Someone Else Build From This?

### 3.1 Symbol overload

The spec introduces 12+ symbols (`⊢ ∴ ⊢= ⊨ ⊨? § «» ≡ → ▸ ✓ ✗ ⊢∘ ⊢⊢`).
For a language designed to be "LLM-native," this is a lot of novel Unicode.

The round-1 testing showed agents handle these well in isolation. But the spec
doesn't show a **complete real program** using all features together. The
`hello` example uses only `⊢`, `given`, `yield`, `∴`, `⊨`.

**Recommendation**: Add a complete "medium complexity" example that uses
crystallization, oracles, quotation, and at least one `⊢∘` or `⊢⊢`.

### 3.2 CellDecl mapping is unclear

The formal model has exactly 4 declaration types: `cellDef`, `wireDef`,
`graphOp`, `paramDecl`. The spec should explicitly state how each syntax
construct maps to these:

| Syntax | CellDecl |
|---|---|
| `⊢ name` block | `cellDef` |
| `given other→field` | Implicit `wireDef` (ref in cellDef) |
| `!add`, `!drop`, etc. | `graphOp` (not shown in spec) |
| Top-level parameters | `paramDecl` |

The spec doesn't mention graph operations (`!add`, `!drop`, `!wire`) at all.
These were in the syntax candidates but seem to have been dropped. Are they
replaced by `⊢⊢` spawners? This needs clarification.

### 3.3 The "document IS the state" metaphor

This is a powerful idea (state = program text with bindings filled in).
But it creates ambiguity: is the Cell file the PROGRAM or the STATE?

In the Lean model, the program is `CellProgram` (static) and the state is
`TaskGraph` (dynamic). They're different types. The spec conflates them.

**Recommendation**: Distinguish:
- `.cell` file = the PROGRAM (source of truth, committed to git)
- Execution state = the program with `yield ≡` bindings (ephemeral, in memory)
- Frozen state = fully executed (all yields bound, content-addressable)

### 3.4 Where are the types?

The spec mentions `yield output1, output2` but doesn't show type annotations.
Round 1 variants had `-> { message : string }` but the v0.1 spec dropped
explicit output types.

The formal model has `CellType` (text, decision, synthesis, etc.) and
`CellSpec.type`. If types are inferred, say so. If they're optional, say so.

---

## Pass 4: Edge Cases — What Could Go Wrong?

### 4.1 Circular dependencies

The spec relies on eval-one (Kahn's algorithm) for scheduling. Kahn's detects
cycles by failing to find ready nodes. But the spec doesn't say what happens
when a cycle exists. The program just hangs?

The Lean model has `TaskGraph.readySet` — if it's empty and the frontier isn't,
there's a cycle. **This should be an explicit error condition.**

### 4.2 Name collisions in spawners

`⊢⊢ spawn` creates new cells at runtime. What prevents name collisions?
If `explore-1` already exists, spawning another `explore-1` violates
`uniqueNames`. The spec mentions "auto-naming" but doesn't specify the scheme.

The Lean model's `GraphOp.isValid (.addNode spec)` checks
`!(g.nodeNames.contains spec.name)`. So name collision is a runtime error.
**Content-addressed naming** (hash of template + inputs) would prevent this.

### 4.3 Oracle on crystallized cells: contract vs guardrail

The spec says: on soft cells, `⊨` is a guardrail; on crystallized cells, `⊨`
is a contract. But what enforces this distinction? If a crystallized cell's `⊢=`
expression violates `⊨`, is that a compile error or a runtime error?

In the Lean model, distillation preserves the frozen set but doesn't check
oracles. **Oracle checking is completely outside the formal model.**

### 4.4 What if `∴` produces unparseable output?

The `yield` line expects a structured value. The `∴` block is natural language.
What if the LLM produces garbage? The spec doesn't define output parsing/validation.

### 4.5 Interaction between `⊢∘` and `⊢⊢`

Can an evolution loop evolve a spawner? Can a spawner spawn an evolution loop?
These meta-level interactions could cause unbounded growth of the frontier.
The spec's `until` and `max` clauses help, but they're per-spawner, not global.

### 4.6 Multiple yields with partial binding

The spec shows `yield output1, output2`. What if the LLM produces `output1`
but not `output2`? Is the cell partially executed? The monotonicity claim
assumes all-or-nothing execution.

---

## Pass 5: Excellence — Making It Shine

### 5.1 Strengths to preserve

- **`§` quotation** at 100% comprehension is the killer feature. Keep it central.
- **Proof-carrying computation** (9/10) — LLM finds, code checks. This is Cell's
  unique value proposition over every other agent framework.
- **"Document IS state" isomorphism** — content addressing for free, diffable
  execution, resumable computation. This is profound.
- **Crystallization spectrum** — not binary (soft/hard) but graduated. The
  permanently-soft kernel insight is deep.

### 5.2 What would make it excellent

1. **A complete worked example** — not hello-world but something with 5+ cells,
   at least one crystallized, one oracle, one `§` reference. Show the full
   eval-one trace from h0 to h_final.

2. **Formal-model alignment section** — a table mapping every spec concept to
   its Lean formalization (or marking "not yet formalized"). This grounds the
   spec in proven properties.

3. **Error model** — what happens on: cycle detection, oracle failure with no
   `⊨?`, type mismatch, name collision, `⊢=` runtime error. Currently the
   spec only covers the happy path.

4. **Graph operations** — the spec is silent on `!add`/`!drop`/`!wire` from
   the formal model. Are these replaced by `⊢⊢`? If so, say so. If not, they
   need syntax.

5. **The "why" for each symbol** — why `⊢` and not `#`? Why `∴` and not prose?
   The evolution rounds discovered these, but the spec should capture the
   reasoning, not just the result.

### 5.3 Proposed spec structure (for v0.2)

```
1. What Cell Is (keep)
2. Core Syntax (expand with complete example)
3. Execution Model (separate fixed vs growing programs)
4. Oracle System (add error model, assert vs rule)
5. Crystallization (add formal alignment)
6. Quotation and Meta-Programming (§, ⊢⊢)
7. Evolution Loops (⊢∘)
8. Formal Properties (proven: confluence, monotonicity, immutability)
9. Error Conditions (cycles, oracle failure, name collision)
10. Open Questions (keep, prioritized)
```

---

## Summary

| Pass | Findings |
|---|---|
| Draft | Rich discovery, reads as lab notebook. 4 formal gaps (oracles, §, ⊢∘, ⊢⊢). |
| Correctness | Termination claim contradicts frontier growth. Oracle retry violates immutability without spawn interpretation. uniqueNames requirement missing. |
| Clarity | 12+ symbols need a complete example. CellDecl mapping unclear. Program vs state conflated. Types unspecified. |
| Edge Cases | Cycles undefined. Spawner naming collisions. Partial yield binding. Meta-level interactions unbounded. |
| Excellence | § and proof-carrying are the winners. Needs worked example, error model, formal alignment table. |

**Overall**: The spec captures genuine discoveries. The execution model core
(eval-one, confluence, monotonicity) is sound and backed by Lean proofs. The
outer features (oracles, evolution, spawners) need tightening. A v0.2 with
the recommendations above would be a solid language spec.
