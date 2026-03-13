# Cell Codebase Survey: Next-Mile Opportunities & Semantic Inconsistencies

**Date**: 2026-03-13
**Bead**: ce-emt
**Surveyor**: polecat rust

---

## Executive Summary

Cell has a rich specification (v0.2), formal verification (Lean4), and a working
Go implementation — but these three layers describe **different languages**. The
spec's logical-notation syntax (`⊢`, `∴`, `⊨`, `given/yield`) has never been
parsed or executed by any code. The Go implementation parses a pragmatic
`cell { type, prompt, refs }` syntax. The Lean4 formalization proves theorems
about a "BeadCalculus" that maps loosely to both. This divergence is the
central finding.

---

## Part 1: Semantic Inconsistencies

### 1.1 The Two-Language Problem (CRITICAL)

**The v0.2 spec describes a language that doesn't exist in code.**

| Aspect | v0.2 Spec Syntax | Implemented Syntax (Go) |
|--------|-----------------|------------------------|
| Declaration | `⊢ name` | `cell name { ... }` |
| Soft body | `∴ Natural language using «input»` | `prompt: """..."""` with `{{ref}}` |
| Hard body | `⊢= expression` | `type: script` + bash code fence |
| Dependencies | `given other-cell→field` | `refs: [other-cell]` |
| Outputs | `yield output1, output2` | `format>` section with typed fields |
| Oracles | `⊨ assertion` | `` ```oracle ... ``` `` block with DSL |
| Interpolation | `«guillemets»` | `{{mustache}}` |
| Binding | `given x ≡ "value"` | `param.x = value` |

**Impact**: Anyone reading the spec cannot use it to write programs the toolchain
accepts. Anyone reading `.cell` files won't find the spec concepts. The spec is
aspirational documentation, not a language reference.

**The `.cell` files in `testdata/`** (e.g., `spec-14-shiny.cell`) use the
implemented syntax, not the spec syntax. The spec syntax exists only in
`evolution/` round documents and the spec itself.

### 1.2 "Cell" vs "Bead" Identity Confusion

The word "Cell" and "Bead" are used interchangeably in overlapping contexts:

| Location | Uses "Cell" as | Uses "Bead" as |
|----------|---------------|----------------|
| v0.2 spec | Computation unit (`⊢ name`) | Not mentioned |
| grammar.md | "reactive **bead** computation graphs" | The computation graph itself |
| Lean4 | `CellType.lean` (type system) | `BeadCalculus` (package name) |
| Go parser | `CellDecl`, `Cell` struct | Not used |
| Gas Town | Not used | Issue/work-item tracker |

**The confusion**: In Gas Town, a "bead" is a tracked issue. In the formal model,
a "bead" is a computation node. In the spec, a "cell" is that computation node.
The Lean4 package is literally called `BeadCalculus` but proves properties about
what the spec calls "cells."

### 1.3 "Molecule" Triple Identity

The term "molecule" means three different things:

1. **In the Go parser** (`parser/ast.go:12`): A `## name { ... ##/` container that
   holds cells, wires, and presets. It's a compilation unit / namespace.

2. **In Gas Town / beads**: An instantiated formula with steps (wisps). A molecule
   is attached to a bead and defines a checklist workflow.

3. **In the v0.2 spec**: Not mentioned at all. The spec has no grouping construct
   above individual cells.

### 1.4 Two Separate AST Definitions

The codebase has two independent AST hierarchies:

- **`internal/cell/ast.go`** (basic): `File → CellDecl + RecipeDecl`. Cells have
  `Name, Type, Prompt, Refs, Oracle`. Simple flat structure.

- **`internal/cell/parser/ast.go`** (extended): `Program → Molecule + Recipe +
  PromptFragment + OracleDecl + InputDecl`. Cells have prompt sections, format
  specs, guards, annotations, vars blocks, script bodies.

The basic parser handles `cell { type, prompt, refs, oracle }`.
The extended parser handles `## molecule { # cell : type ... }`.

**The CLI tries both**: `cmd/cell/main.go` first tries the extended parser, falls
back to basic. This means `.cell` files can be in two different syntaxes with no
explicit version marker.

### 1.5 Grammar Document Describes a Third Language

`docs/specs/cell-language-grammar.md` defines a TOML/YAML formula grammar with
concepts like `FormulaType = "convoy" | "workflow" | "expansion" | "aspect"`,
`Leg`, `Step`, `Synthesis`, and `Sheet`.

This grammar doesn't match either the spec syntax OR the implemented syntax.
It describes the **beads formula format** (the `.formula.toml` files used by
Gas Town), not the Cell language proper. But it's filed under Cell's `docs/specs/`.

### 1.6 Naming Mismatches in Code

| Spec concept | Go name | Lean4 name | Notes |
|-------------|---------|-----------|-------|
| Cell declaration | `CellDecl` / `Cell` | `Cell` | OK, consistent |
| Soft body (`∴`) | `prompt` | — | Spec says "therefore"; code says "prompt" |
| Hard body (`⊢=`) | `type: script` | — | Spec implies expression language; code uses bash |
| Dependencies (`given`) | `refs` / `RefDecl` | `Wire` | Three different names |
| Outputs (`yield`) | `format>` section | `Port` | Three different names |
| Oracle (`⊨`) | `oracle` block | — | Similar enough |
| Interpolation (`«»`) | `{{}}` | — | Different delimiters |
| Binding (`≡`) | `=` | — | Different operator |
| Bottom (`⊥`) | Not implemented | — | Spec-only concept |
| Spawner (`⊢⊢`) | Not implemented | — | Spec-only concept |
| Evolution (`⊢∘`) | Not implemented | — | Spec-only concept |
| Quotation (`§`) | Not implemented | — | Spec-only concept |
| Wildcard deps | Not implemented | — | Spec-only concept |
| Guard clauses | `Guard` struct exists | — | Parsed but not in eval |

### 1.7 "Sub-Zero" vs "Cell-Zero"

The execution engine is in `internal/cell/subzero/`. The roadmap and spec
reference "cell-zero" as the self-bootstrapping evaluator. "Sub-zero" appears
to be a playful name for the prototype, but it creates confusion: is sub-zero
a precursor to cell-zero, or is it cell-zero?

### 1.8 Gas City vs Gas Town

Design documents reference "Gas City" as a future reactive spreadsheet layer.
Gas Town is the current multi-agent workspace. The relationship is unclear:
is Gas City an evolution of Gas Town? A component? A separate project?
Files like `gas-city-formula-engine-vision.md` blur the boundary.

---

## Part 2: Next-Mile Opportunities

### 2.1 Converge Spec and Implementation (HIGH PRIORITY)

**The single highest-impact action**: decide which syntax is canonical and align
the other artifacts to it.

**Option A — Adopt the implemented syntax as canonical:**
- Rewrite the spec to describe `cell { type, prompt, refs }` + molecules
- Retire the `⊢/∴/⊨` logical notation (or relegate to theoretical docs)
- Pro: Zero implementation work needed; spec matches reality
- Con: Loses the elegant logical notation that makes the spec beautiful

**Option B — Implement the spec syntax:**
- Build a parser for `⊢ name`, `given/yield`, `∴`, `⊨`, `«»`
- Rewrite all `.cell` test files
- Pro: The spec syntax is more expressive and theoretically grounded
- Con: Massive implementation effort; current working code gets thrown away

**Option C — Bridge (recommended):**
- Document both syntaxes explicitly: "pragmatic syntax" (current `.cell`) and
  "formal syntax" (spec notation)
- Define a mechanical translation between them
- Keep the formal syntax for specs/proofs, pragmatic syntax for execution
- Add a `cell fmt --formal` command that renders pragmatic → formal

### 2.2 Implement Missing v0.2 Features

Features specified but not implemented, ordered by impact:

1. **`⊥` (bottom) propagation**: First-class absence value. Currently, if a cell
   fails, execution errors out. With `⊥`, downstream cells would gracefully
   receive "no value" and could handle it via `given?`.

2. **`⊢=` expression language**: The spec defines deterministic expressions but
   the code only has bash scripts. A proper expression evaluator would enable
   crystallization — converting LLM results into deterministic code.

3. **Spawners (`⊢⊢`)**: Dynamic frontier growth. Currently the cell graph is
   static. Spawners would let cells create new cells at runtime.

4. **Wildcard dependencies (`given cell-*→field`)**: Aggregate outputs from
   dynamically-spawned cells. Requires spawners first.

5. **Guard clauses (`given x where condition`)**: Conditional cell readiness.
   The `Guard` struct exists in the parser AST but isn't used in execution.

6. **Evolution loops (`⊢∘`)**: Fixed-point iteration. Important for
   self-improving programs but complex to implement correctly.

### 2.3 Complete the Cell-Zero Bootstrap (Phase 3-5)

Per the roadmap (`2026-03-10-cell-zero-bootstrap-roadmap.md`):

- **Phase 1** (syntax discovery): Done via evolution rounds 1-17
- **Phase 2** (dumb executor): Partially done in `subzero/`
- **Phase 3** (observer/recorder): Not started — needs execution tracing and
  content-addressed state transitions
- **Phase 4** (distillation): Not started — needs `∴` → `⊢=` crystallization
- **Phase 5** (self-rewriting): Not started — cell-zero rewrites itself

**Next mile**: Phase 3 is the natural next step. It requires:
- Content addressing (hash each program state)
- Execution trace recording
- State transition logging

### 2.4 Unify AST Representations

Having two separate AST definitions creates maintenance burden and confusion.
The extended parser AST (`parser/ast.go`) is strictly more capable than the
basic AST (`ast.go`). Consider:

- Deprecating the basic parser/AST
- Or defining a shared interface/adapter layer
- The dual-parse fallback in `main.go` should at minimum emit a warning

### 2.5 Formal Verification Gaps

The Lean4 `BeadCalculus` proves confluence and monotonicity but lacks:

- Oracle checking semantics (what happens when oracles disagree?)
- `⊥` propagation rules
- Spawner correctness
- Content addressing scheme proofs

These are the properties most likely to have subtle bugs in implementation.

### 2.6 Module/Namespace System

Evolution round 17 found programs using `§cell-zero.read-graph` (dot notation)
for qualified references, but no module system is specified or implemented.
As programs grow, this becomes essential.

### 2.7 Error Recovery and Diagnostics

The current parser stops at first error. For a language designed to be written
by LLMs, robust error recovery is critical — LLMs will make syntax mistakes
and need actionable error messages to self-correct.

### 2.8 Clean Up Gas City / Gas Town Naming

Either:
- Formally define Gas City as "Cell + Gas Town integration" and document the
  relationship
- Or merge the Gas City concept into Gas Town's roadmap and retire the name

---

## Part 3: Architectural Assessment

### What's Working Well

1. **The computational model is sound**: Kahn's algorithm, eval-one, confluence —
   the theoretical foundation is strong and proven.

2. **The extended parser is capable**: `parser/parser.go` handles molecules,
   map/reduce cells, guards, format specs, oracle blocks — a lot of surface area.

3. **The executor is clean**: `subzero/runner.go` does topological sort and
   sequential execution correctly. Mock and LLM execution modes work.

4. **The evolution methodology**: 17 rounds of empirical syntax testing produced
   genuine insights. The v0.2 spec is evidence-grounded.

5. **The Lean4 formalization**: Real proofs of real properties. Not toy examples.

### What Needs Attention

1. **Spec-implementation alignment**: The #1 issue. Everything else is secondary.

2. **No integration tests between layers**: The parser tests don't run through
   the executor. The executor tests use hand-built ASTs. End-to-end coverage
   is missing.

3. **The `cell-zero` vision is far from realized**: Phases 3-5 of the roadmap
   are untouched. Self-bootstrapping is the stated goal but the current system
   is a conventional topological-sort executor.

4. **The project name "cell" collides with the concept "cell"**: Every search
   for "cell" in the codebase returns everything. Consider whether the language
   name or the computation-unit name should change.

---

## Recommendations (Prioritized)

1. **Write a "Cell Language Reference"** that documents what the toolchain
   actually accepts today. This is the fastest path to usefulness.

2. **Deprecate or explicitly version the spec syntax**. Label v0.2 as "formal
   notation for theoretical work" and the `.cell` syntax as "executable syntax."

3. **Implement `⊥` propagation** — it's the smallest v0.2 feature with the
   largest semantic impact. Makes the executor robust against partial failures.

4. **Unify ASTs** — remove the basic parser or make it a thin wrapper over the
   extended parser.

5. **Add end-to-end tests** — parse → validate → execute → check output for
   every testdata `.cell` file.

6. **Rename `BeadCalculus`** to `CellCalculus` in Lean4, or document why the
   name differs.

7. **Start Phase 3** (observer) of the cell-zero roadmap — this is the most
   exciting next-mile work and aligns with the project's stated goals.
