# Cell Hypothesis Validation — Synthesis

**Author**: morpheus | **Date**: 2026-03-10

## Source Analysis

Three parallel research agents analyzed Cell's core claims:

1. **Gap Analysis** — Classified 9 hypotheses as PROVEN / EMPIRICALLY TESTED / UNVALIDATED
2. **Experiment Design** — Designed 7 falsifiable experiments (see `experiment-design.md`)
3. **Lean Formalization Audit** — Mapped 11 computational model claims to Lean theorems

## Hypothesis Status

| # | Hypothesis | Status | Lean? | Empirical? | Action |
|---|-----------|--------|-------|-----------|--------|
| 1 | Fusion (both substrates required) | PROVEN | Yes (immutability + confluence) | Yes (R12, R13) | Validate via E6 |
| 2 | Everything-is-a-cell | PROVEN + TESTED | Partial (CellDecl uniform) | Yes (R11, R13) | — |
| 3 | Metacircular (cell-zero) | **UNVALIDATED** | No | No | **CRITICAL**: E4 |
| 4 | Confluence | PROVEN | Yes (eval_diamond) | Yes (R13) | Stress-test via E1 |
| 5 | Oracle-as-cell | PROVEN | Partial (no claim cells in Lean) | Yes (R11, R13) | Formalize in Lean |
| 6 | Bottom-as-absence | PROVEN + TESTED | No (no ⊥ in Lean) | Yes (R13 bottom-storm) | Validate via E3 |
| 7 | Crystallization-as-optimization | PROVEN + TESTED | Partial (distillation, not crystallization) | Yes (R12, R13) | E2 |
| 8 | Non-termination | PROVEN + TESTED | Partial (spawn_preserves_frozen) | Yes (R13 word-life) | E7 |
| 9 | Immutability | PROVEN | Yes (execute_irreversible) | Yes (all rounds) | — |

## Critical Gap

**Metacircular evaluation is the only UNVALIDATED hypothesis.** Cell-zero exists as a sketch
but has never been executed — not by an LLM, not by a runtime, not in Lean. This is the
difference between "Cell is a language specification" (validated) and "Cell is a
self-bootstrapping system" (unvalidated).

## Lean Formalization Gaps (Tier 1)

5 computational model claims are absent from the Lean formalization:

| Claim | Impact | What's Missing |
|-------|--------|---------------|
| Oracle cells as nodes | 9/10 | OracleCell structure, spawnOracles op, oracle confluence |
| Tentative state | 8/10 | ExecState.tentative variant, claim cell model |
| ⊥ and absence | 8/10 | Value type (⊥ \| Concrete), lattice ops, ⊥ propagation theorems |
| Cell-zero as a cell | 7/10 | Cell definition, self-evaluation well-foundedness |
| Evaluate→claim→freeze cycle | 7/10 | Full cycle op, extended diamond property |

## Two-Track Validation Plan

**Track A: Empirical (Experiments)** — Run with polecats via cold-read protocol.
Priority order: E6 (fusion) → E1 (confluence) → E3 (bottom) → E4 (metacircular).

**Track B: Formal (Lean)** — Extend Lean formalization to cover the 5 absent claims.
Priority order: Oracle cells → Tentative state → ⊥/absence.

Tracks are independent and can run in parallel.
