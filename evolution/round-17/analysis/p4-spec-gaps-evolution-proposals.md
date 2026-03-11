# Phase 4: Spec Gaps & Evolution Proposals (R17 Corpus)

**Date**: 2026-03-11
**Corpus**: 30 R17 Cell programs + 10+ execution frame traces
**Baseline**: Cell v0.2 specification
**Purpose**: Identify spec gaps, ambiguities, and prioritized proposals for v0.3

---

## 1. Executive Summary

Five key findings from analysis of the complete R17 corpus:

1. **v0.2 solved the right problems.** Every new feature (file-scope `⊨?`, guard
   clauses, `given?`, `⊢=` expression language, `⊢∘` co-evolve) achieved universal
   or near-universal adoption across 30 programs. The false crystallization problem
   from R16 is fully resolved. Guard clauses eliminated the "N/A hack" pattern
   completely. The language *works*.

2. **The `⊢=` expression language is under-specified and drifting.** Programs use
   wildcard dependencies inside `⊢=` expressions (P22), complex filter/index chains
   (P23), object literals (P28), and set operations (P23) --- none of which are
   formally defined. This is the single largest spec gap.

3. **Spawner semantics need formalization.** The `accumulate` vs `replace` keyword
   syntax is inconsistent (`mode accumulate` in P11, bare `accumulate` in P04),
   `replace` placement varies (after cell list in P07/P16 vs inline), and spawned
   cell grouping relies on naming conventions rather than formal structure (P18's
   acts/scenes/beats hierarchy).

4. **Module/namespace system is emerging organically.** P26 uses `§cell-zero.read-graph`
   dot-notation, P05 outputs `§` quotations as programs, and multi-file Cell
   programs are implicit in several designs. The spec says nothing about this.

5. **Execution traces validate the model but expose ordering ambiguities.** Frame
   traces confirm eval-one/Kahn's algorithm works correctly, but non-deterministic
   ready-set selection creates divergent execution orders. The spec doesn't define
   whether this matters for deterministic programs (it shouldn't, per confluence,
   but programs with side-effects or `replace` spawners may disagree).

---

## 2. v0.2 Feature Scorecard

### Features That Proved Their Value

| Feature | Usage | Verdict | Evidence |
|---------|-------|---------|----------|
| File-scope `⊨?` | 30/30 | **Essential** | Every program declares recovery policy; eliminated per-oracle boilerplate |
| Guard clauses (`where`) | 28/30 | **Essential** | Replaced all "N/A hack" patterns; enables conditional dispatch cleanly |
| `given?` optional dep | 22/30 | **Essential** | Enables `⊥` tolerance, bootstrapping (iteration-0 problems solved), graceful degradation |
| Wildcard deps (`cell-*→field`) | 20+/30 | **Essential** | Aggregation pattern (test suites, fact-checkers, spawned specialists) depends on this |
| `⊢=` expression language | 18/30 | **Valuable but under-specified** | Crystallized aggregators, structural verifiers, observation cells all use it |
| `⊢∘` co-evolve | 3/30 | **Valuable, niche** | P09, P17, P07 — correct for circular dependencies, but most programs use single-target `⊢∘` |
| Aspirational oracles under `⊢∘` | 25+/30 | **Essential** | The v0.2 rule that oracles under `⊢∘` are aspirational (not fatal on failure) is universally relied upon |
| `⊢∘` parameter bindings | 12/30 | **Valuable** | P05 (5 bindings), P12, P18, P25 — clean parameterization of evolution loops |
| `⊥` as first-class value | 15/30 | **Essential** | Stop signals (P13), guard-induced bottom (P03, P29), spawner blocking (P13) |
| Conditional oracle semantics | 10/30 | **Valuable** | Vacuous satisfaction when antecedent is false — clean interaction with guards |
| `accumulate` / `replace` modes | 12/30 | **Valuable but syntax inconsistent** | Critical distinction (regression tests persist vs generations replace) |

### Features With Limited Adoption

| Feature | Usage | Notes |
|---------|-------|-------|
| `⊢∘` co-evolve (multi-target) | 3/30 | Most `⊢∘` loops are single-target; co-evolve adds complexity |
| `§` quotation | 5/30 | P02, P05, P06, P26, P30 — powerful but specialized (meta-programs, bootstrapping) |
| `≡` binding | 8/30 | Mostly for `⊢∘` parameter bindings, rarely standalone |
| `▸` refinement stage | 0/30 | **Not used in any R17 program.** Was it needed? |

### Features NOT in Spec but Widely Used

| Pattern | Usage | Status |
|---------|-------|--------|
| Wildcard deps in `⊢=` expressions | 5/30 | Under-specified (P22, P23, P04) |
| Object literals in `⊢=` | 3/30 | Not in spec (P28, P23) |
| Dot-notation on `§` quotations | 1/30 | Not in spec (P26: `§cell-zero.read-graph`) |
| Guard-induced `⊥` | 6/30 | Implied by spec but not explicitly stated |
| `mode accumulate` keyword variant | 1/30 | P11 uses `mode accumulate` vs bare `accumulate` |

---

## 3. Spec Gaps With Evidence

### GAP-1: `⊢=` Expression Language is Undefined (CRITICAL)

**Category**: Under-specification
**Severity**: Critical --- programs depend on features with no formal definition

The v0.2 spec says `⊢=` bodies use "a defined set of primitives" and lists
`count`, `concat`, `all`, `any`, `filter`, `index` as examples. But:

- **P22** uses `count(fact-check-*→verdict, v => v = "confirmed")` --- wildcard
  deps *inside* expression arguments, with lambda syntax for predicates
- **P23** uses `filter(gauntlet-*→result, r => r.pass).length` --- dot-access on
  filter results, `.length` property
- **P23** also uses `index(gauntlet-*→result, r => not r.pass, 0)` --- default
  value parameter
- **P28** uses object literals: `{ target: input-data→target, ... }` inside `⊢=`
- **P04** uses `count(edge-test-*→verdict, v => v = "pass")` --- same lambda pattern

**What's missing from the spec:**
1. Complete primitive list with signatures
2. Lambda/predicate syntax for higher-order primitives
3. Whether wildcard deps can appear inside expressions (not just as top-level deps)
4. Object literal syntax
5. Dot-access on intermediate results
6. Type system (what types do expressions operate on?)
7. Error semantics (what happens when `index` is out of bounds?)

**Proposal**: Define a minimal expression calculus for `⊢=`. See PROPOSAL-1.

---

### GAP-2: Spawner Keyword Syntax is Inconsistent (HIGH)

**Category**: Ambiguity
**Severity**: High --- programs disagree on syntax

Three distinct syntactic patterns appear across the corpus:

1. **Bare keyword after `⊢⊢`**: `⊢⊢ spawn-tests accumulate` (P04, P08, P22)
2. **`mode` prefix**: `⊢⊢ spawn-task-decomposers mode accumulate` (P11)
3. **`replace` after cell list in `⊢∘`**: `⊢∘ (proposal-A, proposal-B) replace` (P07),
   `⊢∘ (population) replace` (P16)

The spec defines `accumulate` and `replace` as spawner modes but doesn't give
formal syntax. Is `mode` a keyword? Is `replace` a `⊢∘` modifier or a spawner
modifier?

**Evidence**:
- P04: `⊢⊢ spawn-edge-tests accumulate`
- P08: `⊢⊢ spawn-regression-test accumulate`
- P11: `⊢⊢ spawn-task-decomposers mode accumulate`
- P07: `⊢∘ (proposal-A, proposal-B) replace`
- P16: `⊢∘ (population) replace`
- P22: `⊢⊢ spawn-fact-checkers replace`

**Proposal**: Standardize on one syntax. See PROPOSAL-2.

---

### GAP-3: Spawned Cell Grouping / Parent Association (HIGH)

**Category**: Under-specification
**Severity**: High --- programs rely on naming conventions for structure

When a spawner creates cells, how do downstream cells know which spawned cells
belong together? The corpus uses naming conventions exclusively:

- **P18**: `⊢⊢ spawn-scenes` creates `scene-1-1`, `scene-1-2`, etc. Then
  `⊢⊢ spawn-beats` creates `beat-1-1-1`, `beat-1-1-2`. The hierarchical
  numbering encodes parent-child relationships, but this is pure convention.
- **P11**: `spawn-task-decomposers` creates cells per sub-goal; wildcard deps
  `task-*→subtasks` aggregate them. But if two different spawners both create
  `task-*` prefixed cells, they'd collide.
- **P14**: Two spawner levels (`spawn-analyzers` and `spawn-sub-analyzers`)
  create cells with module-name prefixes. Again, convention-only.

**What's missing**: Formal scoping or namespacing for spawned cells. The spec
says spawners "emit new cell declarations" but doesn't address name collision,
hierarchical grouping, or wildcard scope.

**Proposal**: See PROPOSAL-3 (spawner scoping).

---

### GAP-4: Module/Namespace System Absent (MEDIUM)

**Category**: Under-specification
**Severity**: Medium --- one program requires it, several would benefit

P26 (`cell-zero-exerciser`) uses `§cell-zero.read-graph`, implying a module
system with dot-notation for accessing cells within quoted programs. P05
(`meta-cell-designer`) outputs `§` quotations that are themselves complete Cell
programs. P29 (`bootstrapper`) creates specialists that could be separate modules.

The spec says nothing about:
1. How `§` quotations are scoped (can you reach into them?)
2. Whether `.` is an operator (field access? module path?)
3. Multi-file Cell programs
4. Import/include mechanisms

This is not urgent for v0.3 (most programs work fine without it), but the pattern
is emerging and will need formal treatment.

---

### GAP-5: `⊢∘` Semantics Edge Cases (MEDIUM)

**Category**: Ambiguity
**Severity**: Medium --- programs work but spec doesn't cover all cases

Several `⊢∘` patterns appear in the corpus that the spec doesn't fully address:

1. **Nested `⊢∘` loops**: P03 has `⊢∘ (harden-loop)` which evolves cells that
   themselves contain `⊢∘`-like iteration patterns. Can `⊢∘` loops nest?

2. **`⊢∘` with `through` binding to cells that have `given?` deps**: P08's
   `⊢∘` loop includes `harden` which has `given? regression-test-*→vulnerability`.
   On iteration 0, no regression tests exist. The `given?` handles this, but the
   interaction between `⊢∘` iteration state and `given?` defaults is implicit.

3. **`until` conditions referencing spawner output**: P04's `until` condition
   references `test-suite→coverage` which is itself computed from `edge-test-*`
   spawned cells. The `until` predicate must wait for spawner children to resolve.
   This creates a dependency chain the spec doesn't describe.

4. **`replace` vs `accumulate` within `⊢∘`**: P16 uses `replace` (generations
   replace), P08 uses `accumulate` (regression tests persist across iterations).
   The interaction between `⊢∘` iteration and spawner mode is well-exercised but
   not formally specified.

---

### GAP-6: Guard Clause Evaluation Order (MEDIUM)

**Category**: Ambiguity
**Severity**: Medium --- works in practice, underspecified in theory

Guards appear in two positions:

1. **On cell declarations**: `given x where condition` --- the cell is skipped
   (produces `⊥`) when condition is false.
2. **On `⊢∘` `through` bindings**: implicitly, via `given?` cells that may be `⊥`.

The spec says guards "determine whether a cell should be evaluated," but:
- When is the guard evaluated? Before all deps resolve, or after?
- Can a guard reference a cell that itself has a guard?
- If a guard references a wildcard dep, does `⊥` in one member fail the guard?

P13 demonstrates guard-induced `⊥` as a stop signal. P03 uses guard-gated
success/failure branching. P29 uses guard-skip on a spawner (the spawner produces
`⊥`, so its children are never spawned). These all work intuitively, but the spec
should be explicit.

---

### GAP-7: `▸` Refinement Stage Operator is Dead (LOW)

**Category**: Over-specification
**Severity**: Low --- included in spec but never used

The `▸` operator appears in the v0.2 spec but is used in **zero** R17 programs.
All refinement is handled by `⊢∘` with `through`/`until` bindings. The `▸`
operator appears to be superseded.

**Proposal**: Either remove from v0.3 or document why it's distinct from `⊢∘`.

---

### GAP-8: Oracle Assertion Scope Within `⊢∘` (LOW)

**Category**: Ambiguity
**Severity**: Low --- the v0.2 "aspirational" rule handles this, but edge cases exist

The v0.2 spec says oracles under `⊢∘` are aspirational (failure triggers retry,
not program failure). But what about oracles that reference cells *outside* the
`⊢∘` loop? P06's `⊢∘` loop has oracles that reference both loop-internal and
loop-external cells. Are external-referencing oracles still aspirational?

---

## 4. v0.3 Proposals (Prioritized)

### PROPOSAL-1: Formalize `⊢=` Expression Calculus (CRITICAL)

**Priority**: P0 --- blocking; programs already depend on undefined features

Define the complete `⊢=` expression language:

```
# Types
Value   := String | Number | Boolean | List[Value] | Record[String, Value] | ⊥
CellRef := cell-name → field-name | cell-* → field-name (wildcard)

# Primitives (with signatures)
count   : (CellRef, Predicate?) -> Number
concat  : (CellRef, separator?: String) -> String
all     : (CellRef, Predicate?) -> Boolean
any     : (CellRef, Predicate?) -> Boolean
filter  : (CellRef, Predicate) -> List[Value]
index   : (CellRef, Predicate | Number, default?: Value) -> Value
length  : List[Value] -> Number
sum     : (CellRef, accessor?: Accessor) -> Number
min/max : (CellRef, accessor?: Accessor) -> Value

# Predicate syntax
Predicate := identifier => expression
# e.g., v => v = "pass", r => r.score > 8

# Object literal syntax
{ key: expression, ... }

# Dot access
expression.field

# Comparison operators
=, !=, <, >, <=, >=, and, or, not

# Error semantics
- Out-of-bounds index with no default => ⊥
- Any primitive applied to ⊥ input => ⊥ (propagation)
- Type mismatch => ⊥
```

**Evidence**: P22 (`count` with predicate), P23 (`filter` with dot-access,
`index` with default), P28 (object literals), P04 (`count` with predicate).

**Risk if not addressed**: Every `⊢=` expression is technically unspecified,
making the distinction between `⊢=` (deterministic, crystallizable) and `∴`
(semantic, needs LLM) meaningless --- if `⊢=` can contain anything, it's just `∴`
with extra steps.

---

### PROPOSAL-2: Standardize Spawner Mode Syntax (HIGH)

**Priority**: P1 --- syntactic inconsistency causes confusion

Standardize on **bare keyword after spawner name**:

```cell
⊢⊢ spawn-tests accumulate     # YES --- spawner with accumulate mode
⊢⊢ spawn-checkers replace     # YES --- spawner with replace mode
⊢⊢ spawn-things               # YES --- default mode (accumulate)
```

Reject alternatives:
```cell
⊢⊢ spawn-tests mode accumulate    # NO --- `mode` keyword is redundant
⊢∘ (population) replace           # NO --- `replace` is a spawner concept, not ⊢∘
```

For `⊢∘` evolution loops, if the loop body contains spawners, the spawner's own
mode keyword controls its behavior. The `⊢∘` declaration itself does not take
a mode.

**Evidence**: P04, P08 use bare keyword (majority pattern). P11 uses `mode`
prefix (minority). P07, P16 put `replace` on `⊢∘` (conceptual mismatch).

---

### PROPOSAL-3: Spawner Scoping (HIGH)

**Priority**: P1 --- naming collisions are latent bugs

Introduce **spawner scope** via prefix binding:

```cell
⊢⊢ spawn-tests accumulate as test-*
  ∴ For each edge case in edge-cases→cases, create a test cell
```

The `as test-*` clause formally binds the spawner's output namespace. Wildcard
deps `test-*→verdict` then resolve only to cells spawned by this specific
spawner, not any cell matching the pattern.

If `as` is not specified, the current behavior (convention-based naming) applies
for backward compatibility.

**Evidence**: P18 (hierarchical spawning with implicit naming), P11 (multi-level
spawning), P14 (two spawner levels).

---

### PROPOSAL-4: Guard-Induced `⊥` Semantics (HIGH)

**Priority**: P1 --- widely used but implicitly defined

Add to spec:

> When a cell's guard clause evaluates to false, the cell produces `⊥` as its
> output. This `⊥` propagates normally: cells with `given?` deps tolerate it,
> cells with `given` deps on a `⊥` cell are blocked (and produce `⊥` themselves
> unless they also have `given?`).
>
> A spawner cell that produces `⊥` (due to guard failure) does not spawn any
> children.
>
> An oracle assertion referencing a `⊥` cell is vacuously satisfied.

**Evidence**: P13 (guard `⊥` as stop signal), P03 (guard-gated branching), P29
(guard-skipped spawner).

---

### PROPOSAL-5: `⊢∘` / Spawner Interaction Semantics (MEDIUM)

**Priority**: P2 --- works but should be documented

Formalize how `⊢∘` iteration interacts with spawner modes:

> **`accumulate` under `⊢∘`**: Spawned cells from all iterations coexist.
> Wildcard deps in iteration N+1 resolve to spawned cells from iterations 0..N.
> (Use case: regression test accumulation in P08.)
>
> **`replace` under `⊢∘`**: Each iteration's spawned cells replace the previous
> iteration's. Wildcard deps resolve only to the current iteration's cells.
> (Use case: population generations in P16.)
>
> **`until` conditions referencing spawner output**: The `until` predicate is
> evaluated after all cells in the current iteration (including spawned children)
> have resolved. This means the `until` check is a synchronization barrier.

**Evidence**: P08 (`accumulate` regression tests persist), P16 (`replace`
generations), P04 (`until` referencing spawner-dependent aggregation).

---

### PROPOSAL-6: Deprecate or Redefine `▸` (LOW)

**Priority**: P3 --- cleanup

Either:
- **Remove** `▸` from v0.3 (zero usage in 30 R17 programs), or
- **Redefine** it as syntactic sugar for single-step refinement without the full
  `⊢∘` loop machinery (e.g., `▸ refine : draft` means "refine once, no iteration").

If removed, note in migration guide that `⊢∘ (target) through [...]` replaces
all `▸` use cases.

---

### PROPOSAL-7: Module/Namespace Foundation (LOW)

**Priority**: P3 --- forward-looking, not blocking

Define minimal module semantics for v0.3:

1. **Dot-notation on `§` quotations**: `§program.cell-name` accesses a cell
   within a quoted program. This is read-only (you can reference the cell's
   output but not mutate it).

2. **File as module**: A `.cell` file is implicitly a module. Its cells are
   accessible via `§filename.cell-name` from other files.

3. **No import mechanism yet** --- defer to v0.4. For now, `§` quotation is the
   only way to reference external programs.

**Evidence**: P26 (`§cell-zero.read-graph`), P05 (programs as output).

---

### PROPOSAL-8: Formalize Wildcard Dep Syntax (MEDIUM)

**Priority**: P2 --- widely used, partially specified

The v0.2 spec mentions wildcard deps but doesn't fully specify:

1. **Pattern syntax**: Only `*` glob? What about `cell-{a,b}-*`? Regex?
2. **Resolution timing**: When are wildcards resolved? At cell evaluation time
   (seeing only currently-frozen cells) or at program-end (seeing all cells)?
3. **Empty resolution**: What if `cell-*` matches nothing? Is the result `[]`
   (empty list) or `⊥`?
4. **Nested wildcards**: Can you write `section-*-task-*→status`?

Recommendation: wildcards resolve at evaluation time (only frozen cells),
empty match produces `[]`, only single `*` glob is supported.

**Evidence**: P04, P08, P11, P14, P18, P22, P23, P29 all use wildcard deps.

---

## 5. R16 to R17 Comparison

### What Changed

| Dimension | R16 | R17 | Improvement |
|-----------|-----|-----|-------------|
| False crystallization | 2 programs (P27, P28) had `⊢=` bodies with semantic judgments | 0 programs --- all verify-proof cells split into structural `⊢=` + semantic `∴` | **Fully resolved** |
| Guard clauses | Not available; "N/A hack" in `∴` bodies | Universal adoption (28/30 programs) | **Transformative** |
| `given?` optional deps | Not available; iteration-0 bootstrapping was awkward | Universal adoption (22/30 programs) | **Solved bootstrapping** |
| File-scope `⊨?` | Not available; per-oracle `⊨?` or missing | Universal adoption (30/30) | **Boilerplate eliminated** |
| `⊢=` expression language | Informal; some programs had pseudo-code in `⊢=` | Richer usage but still under-specified | **Partially improved** |
| `⊢∘` co-evolve | Not available | 3 programs (P09, P17, P07) | **New capability** |
| Wildcard deps | Used informally | Used in 20+ programs, integrated with `⊢=` | **Proven essential** |
| `⊥` as value | Informal | First-class with propagation rules | **Formalized** |
| Spawner modes | Implicit | `accumulate`/`replace` keywords (inconsistent syntax) | **Improved but needs standardization** |

### What Didn't Change (Persistent Issues)

1. **`⊢=` expression language** still lacks formal definition (was informal in R16,
   still informal in R17 despite richer usage)
2. **Spawner grouping** still relies on naming conventions
3. **Module system** still absent
4. **`▸` operator** still unused (was unused in R16 too)

### Net Assessment

R17 represents a **major quality improvement** over R16. The v0.2 spec changes
(guards, `given?`, file-scope `⊨?`, aspirational oracles) solved the right
problems. The programs are cleaner, more consistent, and demonstrate genuine
mastery of the Cell computational model. The remaining issues are mostly
**formalization gaps** (things that work but aren't specified) rather than
**design gaps** (things that don't work).

---

## 6. Recommendations for R18

### R18 Design Goals

1. **Test the `⊢=` expression calculus.** Once PROPOSAL-1 is accepted, write 5-10
   programs that stress-test the formal expression language. Include edge cases:
   nested wildcards, empty matches, type mismatches, `⊥` propagation through
   expressions.

2. **Test spawner scoping.** Once PROPOSAL-3 is accepted, write programs with
   intentional name collisions that would break without scoping. Verify the `as`
   clause resolves ambiguity.

3. **Push co-evolve harder.** Only 3/30 programs used `⊢∘` co-evolve. Write
   programs where co-evolution is essential (mutual recursion, negotiation with
   3+ parties, emergent consensus). Determine if co-evolve needs richer
   synchronization primitives.

4. **Module system exploration.** Write 2-3 programs that compose multiple `.cell`
   files. Test `§` quotation as module mechanism. Identify where it breaks.

5. **Adversarial programs.** Write programs designed to break the spec:
   - `⊢=` expressions that look deterministic but aren't
   - Guard clauses that create circular `⊥` cascades
   - `⊢∘` loops where `until` conditions are contradictory
   - Spawners that spawn spawners that spawn spawners
   - Programs where execution order matters despite confluence

### R18 Corpus Composition (Suggested)

| Category | Count | Purpose |
|----------|-------|---------|
| `⊢=` expression stress tests | 5 | Validate PROPOSAL-1 |
| Spawner scoping tests | 3 | Validate PROPOSAL-3 |
| Co-evolve deep dives | 4 | Push `⊢∘` co-evolve limits |
| Multi-module programs | 3 | Explore PROPOSAL-7 |
| Adversarial/edge-case | 5 | Break the spec intentionally |
| Application programs | 10 | Natural usage, diverse domains |
| **Total** | **30** | |

### Spec Work Before R18

Before generating R18 programs, the following spec changes should be finalized:

1. **P0**: Formalize `⊢=` expression calculus (PROPOSAL-1)
2. **P1**: Standardize spawner mode syntax (PROPOSAL-2)
3. **P1**: Define guard-induced `⊥` semantics (PROPOSAL-4)
4. **P2**: Formalize wildcard dep syntax (PROPOSAL-8)
5. **P2**: Document `⊢∘`/spawner interaction (PROPOSAL-5)

These five changes would produce a v0.3 spec that is tight enough to serve as
a real language specification rather than a design sketch.

### What NOT to Do in R18

- **Don't add new operators.** v0.2 has enough surface area. Formalize what exists.
- **Don't build a type system yet.** The expression calculus (PROPOSAL-1) should
  come first; types follow from usage patterns.
- **Don't try to make Cell Turing-complete.** The fusion model (classical + semantic)
  is the point. Classical completeness would undermine it.
- **Don't remove `§` quotation.** Even at 5/30 usage, it's the foundation for
  metacircular evaluation and module composition.

---

## Appendix A: Feature Frequency Table (R17)

| Feature | Count | Programs |
|---------|-------|----------|
| `⊨?` file-scope | 30 | All |
| `⊢` cell declaration | 30 | All |
| `∴` soft body | 30 | All |
| `⊨` oracle assertion | 30 | All |
| `where` guard clause | 28 | All except P01, P02 |
| `given?` optional dep | 22 | P01,03,04,08,10,11,12,13,14,15,16,17,18,20,21,22,24,25,26,27,29,30 |
| Wildcard deps | 20+ | P01,04,06,08,10,11,12,14,15,18,20,22,23,25,26,29,30 + others |
| `⊢∘` evolution loop | 27 | All except P13, P23, P24 |
| `⊢⊢` spawner | 18 | P01,04,05,08,10,11,12,14,15,18,20,22,23,25,26,29 + others |
| `⊢=` hard body | 18 | P03,04,08,11,13,14,16,19,22,23,24,26,27,28 + others |
| `accumulate` mode | 10 | P04,08,10,11,12,14,15,18,25,29 |
| `replace` mode | 5 | P01,07,16,22,25 |
| `given?` + `⊥` tolerance | 12 | P03,08,13,14,16,17,24,27,29 + others |
| `§` quotation | 5 | P02,05,06,26,30 |
| `⊢∘` co-evolve | 3 | P07,09,17 |
| `≡` binding | 8 | P05,12,18,25 + others |
| `→` output access | 30 | All |
| `⊥` explicit use | 15 | P03,08,13,14,16,17,24,27,29 + others |
| `▸` refinement stage | 0 | None |

## Appendix B: False Crystallization Audit

R16 had two programs (P27, P28) where `⊢=` bodies contained semantic judgments
(e.g., "compare semantics" in a supposedly deterministic cell). R17 status:

| Program | R16 Issue | R17 Fix | Status |
|---------|-----------|---------|--------|
| P19 (code-generator-proof) | N/A (new) | verify-proof split: structural `⊢=` + semantic `∴` | **Clean** |
| P24 (proof-carrying-code) | N/A (new) | verify-proof split: structural `⊢=` + semantic `∴` | **Clean** |
| P27 (self-optimizing-cell) | compare-semantics was `⊢=` | Moved to `∴` (semantic judgment) | **Fixed** |
| P28 (program-algebra-prover) | verify-proof was `⊢=` with semantic content | Split into structural `⊢=` + semantic `∴` | **Fixed** |

**Result**: Zero false crystallization instances in R17. The v0.2 guidance
("`⊢=` bodies must use only defined primitives") combined with the split pattern
(structural verification in `⊢=`, semantic judgment in `∴`) has fully resolved
this class of error.

---

*Analysis conducted on R17 corpus of 30 Cell programs + 10+ execution frame traces.*
*Baseline: Cell v0.2 specification (820 lines).*
*Context: Phase 1 analyses (p1-01-through-10.md, p1-11-through-20.md, p1-21-through-30.md).*
