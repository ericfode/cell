# Round 12 Synthesis: The Big Ones — Real-World Scale Programs

## Overview

Round 12 tested Cell at production-relevant scale. Four programs, each 2-3x larger
than R9-R11 programs, exercising every major language feature simultaneously.

**4 test programs, 4 polecat cold-reads, ~2300 lines of analysis.**

| Test | Program | Cells | LLM Calls (min/max) | Clarity | Bugs |
|------|---------|-------|---------------------|---------|------|
| T1 | Code Review Pipeline | 10 defs / 18 instances | 17 / 33 | 7/10 | 4 |
| T2 | Research Agent | 10 + spawned | 17 / 77 | 7/10 | 5 |
| T3 | Multi-Agent Negotiation | 8 | 9 / 13 | 8/10 | 3 |
| T4 | Self-Improving Compiler | 8 | 7 / 14 | 8/10 | 1 |

**Total**: 36+ cell definitions, 16 bugs found, average clarity 7.5/10.

---

## Feature Maturity (Updated from R9-R11)

### Tier 1: Spec-Ready (confirmed at scale)

| Feature | R11 Score | R12 Score | Evidence |
|---------|-----------|-----------|----------|
| `§` quoting (cell-as-value) | 100% | 100% | T4 uses §source as data for metacircular compilation; T2 uses §experiments, §results throughout evolution loop. No confusion across any polecat. |
| `⊢=` crystallization | 9.5/10 | 9.5/10 | All 4 programs use ⊢= sub-computations correctly. T3 has 13 crystallized computations; T1 has 5; T4 uses ⊢= for source-program. |
| `∴` soft body | 9/10 | 9/10 | Well-understood. Every program correctly uses ∴ for LLM-requiring work. |
| `⊨` oracle constraint | 9/10 | 9/10 | T1 has 36 oracle checks, T2 has 45+, T3 has 27, T4 has 27. All programs use oracles fluently. |
| `⊥? skip with` | 8/10 | **9/10** | **Upgraded.** T3 demonstrates adversarial ⊥ propagation with 3 injection points, graduated recovery strategies, and graceful degradation. T1 shows complete ⊥ chain from merge-reviews→final-verdict yielding BLOCKED. T4 has comprehensive ⊥ handlers on every cell except meta-report. |
| Proof-carrying computation | 9/10 | 9/10 | Confirmed at scale. T4's verify-roundtrip and T1's re-analyze both demonstrate the verify-after-compute pattern. |

### Tier 2: Solid but with Documented Gaps

| Feature | R11 Score | R12 Score | Finding |
|---------|-----------|-----------|---------|
| `⊨? on failure/exhaustion` | 8/10 | **8.5/10** | Graduated retry budgets work well (T3: round-3 gets max 2, round-1 gets max 1). But `partial-accept(best)` remains under-specified — T2 and T1 both use it without defining "best". |
| Template instantiation | 8/10 | **8/10** | T1's §review-template and §fix-template work. But T1 exposes a gap: §re-reviewer template is referenced but never defined. Templates need better tooling for cross-reference checking. |
| `until` / `max` (halting) | 9/10 | 9/10 | T2's evolution loop uses both `until` (remaining-gaps empty ∨ confidence ≥ 0.8) and `max 3`. Clean semantics. |
| Hybrid ⊢=/∴ cells | — | **9/10** | **New finding.** Every program separates deterministic from creative work within cells. T3: every cell except buyer/seller-strategy has at least one ⊢= output. T4: source-program is fully ⊢=. This is the dominant authoring pattern at scale. |
| Tautological oracle detection | — | **Noted** | All 4 programs contain tautological oracles (⊢= outputs checked by ⊨). T3: 7/27 tautological. T2: 3/45. T1: 1/36. The `⊨` vs `⊨!` (assertion) distinction proposed in R11 is validated. |

### Tier 3: Needs Work

| Feature | R11 Score | R12 Score | Issue |
|---------|-----------|-----------|-------|
| `⊢⊢` spawner | 5.5/10 | **6.5/10** | Improved but still problematic. T1 uses 3 spawners at scale (analyze, generate-fixes, re-analyze) — works for template-driven fan-out. T2 nests spawners inside evolution loops. BUT: T1's re-analyze spawner references undefined template; T1's analyze has `max 6` vs `exactly 4` ambiguity. Spawner semantics clearer for simple fan-out, still fuzzy for error/retry handling. |
| `⊢∘` evolution loop | 6/10 | **6.5/10** | T2 is the definitive test: ⊢∘ containing ⊢⊢ spawners. Works structurally. BUT: variable binding across iterations is implicit (§current-hypothesis → §revised-hypothesis); evidence doesn't accumulate (Bug #1); remaining-gaps don't update (Bug #2). Evolution loops need explicit loop-variable declaration. |
| Metacircular evaluation | — | **8/10** | **New.** T4 demonstrates Cell-on-Cell compilation. §-quoting allows Cell programs as data. parse/emit are effectively quote/eval. The "who watches the watchmen" problem persists (verify-roundtrip uses same LLM class). |

---

## Cross-Test Findings

### 1. The Hybrid Cell Pattern Is Universal

Every R12 program separates ⊢= and ∴ within cells. This is not explicit in the spec
but is the natural authoring pattern. At scale:

- T3: 13 crystallized sub-computations across 8 cells
- T1: 5 crystallized sub-computations across 10 cells
- T4: source-program is fully ⊢=; verify-roundtrip and meta-report have ⊢= sub-yields
- T2: 4 crystallized formulas (confidence, conclusion-strength, filled-gaps, remaining-gaps)

**Spec action**: Hybrid cells should be first-class. A cell with both ⊢= and ∴ elements
should be the documented default, not a special case.

### 2. ⊥ Propagation Works at Scale

The biggest question from R11 was whether ⊥ would scale to larger programs. Answer: **yes**.

- T3: 3 ⊥ injection points, 3 propagation chains, graduated recovery (error-value vs partial-accept). Removing any round cell → clean cascade to "FAILED" via ⊥? skip.
- T1: Complete ⊥ chain from merge-reviews through 5 cells to final-verdict="BLOCKED".
- T4: Every cell except meta-report has ⊥? handlers. Removing any middle cell → graceful degradation.
- T2: run-experiments → ⊥ → update-evidence skip → confidence=0.0 → loop continues.

**Confirmed**: ⊥ propagation converts downstream LLM calls into free deterministic operations (R11 finding validated at scale).

### 3. Missing ⊥ Handlers Are the #1 Bug Class

Across all 4 programs, the most common bug is a cell with inputs but no ⊥? handler:

| Program | Cell | Missing Handler |
|---------|------|----------------|
| T1 | final-verdict | `apply-fixes→applied-count`, `apply-fixes→failed-count` |
| T2 | seed | No retry handler at all (root cell, 4 oracles) |
| T3 | buyer-strategy, seller-strategy | No ⊨? handlers |
| T4 | meta-report | No ⊥? handlers for any of 5 inputs |

**Pattern**: Root cells and terminal cells are most likely to lack handlers. Authors
protect the middle of the pipeline but forget the edges.

**Spec action**: Consider requiring ⊨? handlers on every cell with oracles, or at least
flagging their absence as a warning. Cell should make handler omission an explicit choice
(e.g., `⊨? none` to indicate intentional omission).

### 4. Tautological Oracles Are Pervasive

Every program has oracles that can never fail because they check ⊢= outputs:

| Program | Tautological / Total | Examples |
|---------|---------------------|----------|
| T3 | 7/27 (26%) | Status ∈ set, deadzone = 150000, satisfaction ∈ [0,100] |
| T2 | 3/45 (7%) | filled ∪ remaining = original, confidence ∈ [0,1] |
| T1 | 1/36 (3%) | applied + failed = total |
| T4 | 0/27 (0%) | (T4 avoids this — its ⊢= computations are sub-yields, not oracle-checked) |

**Insight**: T4's approach is best — use ⊢= for deterministic properties and don't
redundantly oracle-check them. The `⊨` vs `⊨!` distinction from R11 is confirmed:
oracles on ⊢= values should be assertions (documentation), not runtime checks.

### 5. Templates Collapse Spawning to Map (Confirmed at Scale)

T1 demonstrates the template-driven spawner pattern definitively:

```
⊢⊢ analyze → spawn §review-template[security, performance, correctness, style]
⊢⊢ generate-fixes → spawn §fix-template[action-item-1, ..., action-item-N]
```

This is `map(template, list)` — deterministic fan-out. The spawner's only job is
instantiation. All complexity lives in the template.

**Gap**: T1's re-analyze spawner references a template that was never defined. Templates
need cross-reference validation (either static analysis or runtime check).

### 6. Evidence Accumulation in Evolution Loops Is Broken

T2 exposes a fundamental issue with ⊢∘: loop body cells reference ORIGINAL inputs
(from before the loop), not accumulated state from prior iterations.

- `update-evidence` takes `extract-evidence→supporting` (the pre-loop value) in every iteration
- `remaining-gaps` never updates across iterations

**Root cause**: ⊢∘ has no explicit loop-variable mechanism except for the `through` clause.
§current-hypothesis is the only looped value. Evidence and gap state should also be loop
variables, but the syntax doesn't make this clear.

**Spec action**: ⊢∘ needs explicit loop-variable declaration:
```
⊢∘ refine-hypothesis
  loop-vars: §current-hypothesis, §accumulated-evidence, §remaining-gaps
  through: revise → design-experiments → run-experiments → update-evidence
  until: remaining-gaps is empty ∨ confidence ≥ 0.8
  max: 3
```

### 7. Scale Reveals LLM Call Variance

The range between minimum and maximum LLM calls widens dramatically at scale:

| Program | Min Calls | Max Calls | Ratio |
|---------|-----------|-----------|-------|
| T4 | 7 | 14 | 2.0x |
| T3 | 9 | 13 | 1.4x |
| T1 | 17 | 33 | 1.9x |
| T2 | 17 | 77 | 4.5x |

T2's 4.5x ratio comes from the interaction of spawners × evolution iterations × retries.
A 3-iteration loop with 3 spawned cells per iteration, each with 1 retry, creates
multiplicative cost. Cell programs need cost annotations or budgets to prevent runaway
LLM spend.

### 8. The Watchmen Problem Persists

Multiple programs have the "who watches the watchmen" pattern:

- **T4**: verify-roundtrip uses the same LLM class to verify output that produced it
- **T2**: `⊨ revised more specific than current` — LLM self-grades specificity
- **T1**: re-analyze uses LLM reviewers to check LLM-generated fixes
- **T3**: Oracles provide behavioral constraints but not strategic integrity

**Resolution**: Cell should acknowledge two oracle tiers:
1. **Structural oracles**: Mechanically verifiable (count, type, range, format). These are trustworthy.
2. **Semantic oracles**: Require judgment (quality, correctness, specificity). These are pragmatic, not provably sound.

The spec should document which tier each oracle belongs to and recommend structural
oracles where possible.

---

## Bugs Found (All Programs)

| # | Program | Bug | Severity | Fix |
|---|---------|-----|----------|-----|
| 1 | T1 | Missing §re-reviewer template | Critical | Define §re-review-template with resolved/new/regression schema |
| 2 | T1 | final-verdict missing ⊥? for apply-fixes counts | Medium | Add `⊥? skip with applied-count ≡ 0, failed-count ≡ 0` |
| 3 | T1 | analyze `max 6` vs `exactly 4` ambiguity | Low | Clarify max semantics for spawners |
| 4 | T1 | re-analyze has no recovery clauses | Low | Add ⊨? handlers |
| 5 | T2 | Evidence accumulation failure across iterations | High | Make evidence a loop variable |
| 6 | T2 | Stale remaining-gaps in loop termination | High | Add re-assess step or make gaps a loop variable |
| 7 | T2 | seed has no recovery handlers | High | Add ⊨? retry to root cell |
| 8 | T2 | Empty experiments edge case (avg of empty list) | Medium | Guard against §experiments = [] |
| 9 | T2 | Oracle self-grading ("more specific") | Low | Define specificity structurally |
| 10 | T3 | max-rounds declared but unused (5 vs 3 implemented) | Low | Remove or implement |
| 11 | T3 | Redundant ⊥ guard (round-2 lines 101-102) | Low | Remove unless partial ⊥ exists |
| 12 | T3 | buyer/seller-strategy missing ⊨? handlers | Medium | Add recovery handlers |
| 13 | T3 | partial-accept(best) undefined metric | Medium | Define "best" |
| 14 | T3 | Fragile oracle: buyer-offer-1 = opening-offer (exact echo) | Medium | Allow tolerance or rephrase |
| 15 | T4 | meta-report has no ⊥? handlers for 5 inputs | Medium | Add ⊥? skip with handlers |
| 16 | T4 | source-program typed ⊢ but is effectively ⊢= | Low | Change type to ⊢= |

**Bug class breakdown:**
- Missing ⊥ handlers: 5 bugs (#2, #7, #12, #15, #4)
- Under-specified semantics: 4 bugs (#3, #6, #13, #14)
- Logic errors: 3 bugs (#5, #8, #10)
- Template gaps: 2 bugs (#1, #9)
- Cosmetic: 2 bugs (#11, #16)

---

## Design Principles (New in R12)

### 1. Fan-Out/Fan-In Is the Natural Scale Pattern

Both T1 and T2 use the same pattern: spawner fans out N parallel cells, then a
merge cell fans them back in. T1 does this twice (analyze→merge, re-analyze→verdict).
This is the MapReduce of Cell.

### 2. Graduated Retry Budgets Work

T3 demonstrates intentional retry allocation: round-3 (critical, max 2) > round-1/2
(less critical, max 1). T4 gives parse and emit (critical for pipeline integrity) max 2,
while transform-add-handlers gets max 1. Authors correctly identify where retries matter
most.

### 3. Root Cells Are Single Points of Failure

Every program's root cell (setup, seed, parse-diff, source-program) has zero redundancy.
If the root fails, everything fails. T2's seed has 4 oracles and zero retry handlers —
the most fragile point in the most complex program.

### 4. Terminal Cells Are Safely Removable

Every program's terminal cell (post-mortem, synthesize, final-verdict, meta-report) can be
removed with minimal impact. The program produces its core output even without the summary.
This is a healthy architecture — reports are observers, not participants.

### 5. The Crystallization Paradox Extends to Compilers

T4 confirms R11's crystallization paradox: the compiler that fixes ⊥ handler gaps in
other programs has its own ⊥ handler gap (meta-report). The tool that improves programs
cannot improve itself without recursive self-application. This is inherent to bootstrapping.

### 6. Structural vs Value-Level ⊥ (Confirmed)

T3 demonstrates both:
- **Structural ⊥**: Cell-level failure → ⊥? skip → cascading collapse
- **Value-level ⊥**: `final-price = ⊥` within a successful cell → NO-DEAL

Both produce the same terminal state (all zeros) through different mechanisms. The spec
should document this distinction explicitly.

---

## Spec Actions (Updated)

### Must Do (blocking v0.1)

1. **Define hybrid cells as first-class** — ⊢= + ∴ within a single cell is the default pattern
2. **Define `partial-accept(best)` semantics** — requires a "best" metric or remove it
3. **Define ⊢∘ loop-variable declaration** — explicit list of values that carry across iterations
4. **Resolve `⊢⊢` spawner max semantics** — is `max` total attempts or successful spawns?
5. **Distinguish `⊨` (constraint) from `⊨!` (assertion/invariant)** — tautological oracles are pervasive

### Should Do (v0.1 quality)

6. **Require ⊥? handler declaration on every cell** — omission must be explicit (`⊥? none`)
7. **Define template cross-reference validation** — catch T1's missing re-reviewer template
8. **Structural vs semantic oracle documentation** — two tiers of verification
9. **Define structural vs value-level ⊥** — both exist, spec should distinguish them
10. **Add `let` binding for shared intermediate values** — carried from R11

### Nice to Have (v0.2)

11. **Cost annotations** — expected LLM calls per cell, total budget for program
12. **Static analysis for tautological oracles** — compiler warning when ⊨ checks ⊢= output
13. **Metacircular compilation support** — formalize § as quote/eval for Cell-on-Cell

---

## Statistics

| Metric | Value |
|--------|-------|
| Programs written | 4 |
| Total cell definitions | 36+ |
| Runtime instances (happy path) | 50+ |
| Polecat cold-reads | 4 (all returned results) |
| Total analysis | ~2300 lines |
| Oracle checks traced | 135+ across all programs |
| Tautological oracles found | 11 |
| Bugs discovered | 16 |
| Design principles extracted | 6 |
| Spec actions identified | 13 |
| Average clarity | 7.5/10 (range: 7-8) |
| Average LLM calls (min) | 12.5 |
| Average LLM calls (max) | 34.25 |
| Largest program | T1 (18 runtime instances) |
| Most complex program | T2 (⊢∘ + nested ⊢⊢, 77 max LLM calls) |
| Best ⊥ propagation | T3 (3 injection points, 3 chains, graduated recovery) |
| Most architecturally sophisticated | T4 (metacircular compilation) |

---

## Comparison: R9-R11 → R12

| Dimension | R9-R11 (12 programs) | R12 (4 programs) | Change |
|-----------|---------------------|-------------------|--------|
| Average program size | ~50 lines | ~190 lines | 3.8x |
| Cells per program | 3-5 | 8-10 | 2x |
| Oracle checks per program | 5-10 | 27-45 | 4x |
| Bugs per program | 1-2 | 4 | 2x |
| Clarity | 7.0 → 7.75 | 7.5 | Maintained |
| Feature coverage | Individual features | All features combined | Full integration |

**Key insight**: Clarity held at 7.5/10 despite 3.8x increase in program size. Cell scales
readably. The bug rate doubled (from ~1.5 to 4 per program), concentrated in ⊥ handler
gaps and under-specified semantics — both addressable with better tooling and spec clarity.

---

## Next Steps

Round 12 completes the exploration phase. The language has been tested at:
- Individual feature level (R1-R8)
- Feature integration level (R9-R11)
- Production-scale level (R12)

**Remaining gaps for v0.1 spec:**
1. `⊢⊢` spawner semantics (6.5/10) — improved but still the weakest feature
2. `⊢∘` loop-variable binding (6.5/10) — implicit binding doesn't scale
3. `partial-accept(best)` — used 4 times across R12, never defined

**Recommendation**: The next round should focus on **spec writing**, not more test programs.
The 12 rounds have produced sufficient evidence to write a v0.1 spec. The outstanding
issues (spawner semantics, loop variables, recovery strategies) are better resolved through
spec design than more cold-read experiments.
