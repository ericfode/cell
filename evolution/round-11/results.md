# Round 11 Results: Integration Test — Full Cell Execution Model

## Summary

Round 11 was the capstone of the depth-3 chain (R9→R10→R11). Each variant
combined ALL major Cell features into a single program. 4/4 polecats returned
comprehensive analyses.

| Variant | Polecat | Rating | Key Finding |
|---------|---------|--------|-------------|
| T1: Self-Crystallizing Harness | rust | 8/10 | 0/0 bug: empty test-runs → all-passed = true |
| T2: Proof-Carrying Oracle | chrome | 8/10 | Tautological oracles on crystallized cells (4/9 can't fail) |
| T3: Evolution-Spawner | nitro | 7/10 | Non-determinism bug: judges evaluate different greeting instances |
| T4: eval-one-bottom | guzzle | 8/10 | Cleanest ⊥ propagation demo; level confusion is the cost |

**Overall R11 average: 7.75/10** — significant jump from R9 (7.0) and R10 (7.25).

## Key Findings

### 1. The 0/0 Bug (T1)

When implementation is ⊥, run-tests skips to `§test-runs ≡ []`. Score then
computes `all-passed = (0 = 0) = true`. This falsely certifies a ⊥
implementation. Fix: `⊢= all-passed ← (pass-count = total) ∧ (total > 0)`.

**Implication**: ⊥ propagation via `skip with` can create semantically
incorrect default values. The language needs either:
- Convention: skip-with values must satisfy downstream oracles
- Enforcement: runtime checks skip-with values against oracles

### 2. Tautological Oracles on Crystals (T2)

Of 9 oracle checks in the proof-carrying pipeline, 4 are on crystallized cells
and can never fail (they validate properties guaranteed by the ⊢= formula). These
serve as assertions/invariants, not constraints. Cell should distinguish:
- `⊨` (oracle constraint — can fail, triggers recovery)
- `⊨!` or similar (assertion — should never fail, compile-time checkable)

### 3. Non-Determinism in Spawned Evaluation (T3)

Each judge independently instantiates greeting-v0, potentially getting different
LLM outputs. Judges then score different texts, making scores incomparable.
Fix requires shared intermediate values — suggests a `let` binding construct:
```
let sample ← instantiate(§greeting-v0, name ≡ test-name)
```
This is a gap in Cell's current syntax.

### 4. ⊥? skip MUST bypass oracles (T4)

T4's fallback message `"STEP-B FAILED — NO MESSAGE TO CONVERT"` deliberately
violates the happy-path oracle `⊨ contains "20"`. This confirms that `⊥? skip
with` must bypass oracle checking entirely — the skip-with value is correct for
the failure context, not the happy-path constraints.

### 5. Metacircular Level Confusion (T4)

When eval-one executes inner cells, who checks inner oracles? If eval-one is
an LLM executing a ∴ instruction, it's asking the LLM to verify predicates
that should be verified by the runtime. The metacircular structure creates
an oracle-checking level problem.

### 6. Exhaustion is Cheaper Than Late Success (T2)

If solve exhausts all retries → ⊥, total LLM calls = 4 (all in solve).
If solve succeeds on last retry, total = 5 (4 in solve + 1 in certificate).
The ⊥ path is cheaper because certificate's skip-with avoids its LLM call.
This is a general property: ⊥ propagation converts downstream LLM calls into
free deterministic operations.

### 7. Liskov Substitution for Cells (T3)

The improve cell's contract — preserve given/yield/⊨ signature — is behavioral
subtyping. The evolved cell must be a drop-in replacement. This is the right
constraint for cell evolution and should be formalized.

### 8. crystallize-or-report is Over-Soft (T1)

The certifier that validates crystallization is itself not crystallized. Its
logic is a pure if/then that could be ⊢=. A crystallize cell that requires
an LLM is structurally ironic. The `▸ crystallized` annotation may need
special runtime support, but this should be explicit.

## Syntax Clarity (R11 Scores)

| Element | Avg Score | Notes |
|---------|-----------|-------|
| `⊢= x ← expr` | 9.5/10 | Universally clear |
| `∴` instruction | 9/10 | Natural and obvious |
| `⊨ constraint` | 9/10 | Direct, verifiable |
| `until` / `max` | 9/10 | Plain English, unambiguous |
| `⊨? on failure/exhaustion` | 8/10 | Clear recovery, "max N" still ambiguous (retry vs attempt) |
| `⊥? skip with` | 7.5/10 | Intent clear, oracle-skipping semantics implicit |
| `§ cell-as-value` | 7.5/10 | Powerful but requires inference from context |
| `⊢⊢ spawner` | 5.5/10 | Most under-specified construct |
| `⊢∘ evolution` | 6/10 | Plausible but fragile |
| `▸ crystallized` | 7/10 | Clear as annotation, unclear when mandatory vs optional |

## Cumulative Scores (R9-R11)

| Feature | R9 | R10 | R11 | Trend |
|---------|-----|-----|-----|-------|
| § quoting | 100% | 100% | 100% | Stable — universal |
| eval-one | 9/10 | — | 9/10 | Stable |
| Proof-carrying | 9/10 | — | 9/10 | Stable |
| Self-crystallization | 9/10 | — | 9/10 | Stable |
| ⊢= crystallization | 8/10 | 8/10 | 9.5/10 | Rising |
| Cell-as-agent | 8/10 | — | 8/10 | Stable |
| Template instantiation | — | 8/10 | 8/10 | Stable |
| ⊥ propagation | — | 7/10 | 8/10 | Rising |
| Oracle cascade | 7/10 | 7/10 | 8/10 | Rising |
| Spawner (⊢⊢) | 7/10 | 7/10 | 5.5/10 | Falling — more scrutiny reveals gaps |
| ⊢∘ evolution | 8/10 | — | 6/10 | Falling — integration exposed ambiguity |
| Escalation chain | — | 7/10 | — | Not tested |
| Frontier growth | 6/10 | — | — | Not retested |

## Design Actions for v0.1 Spec

1. **Formalize `⊥? skip with` oracle bypass** — skip means skip EVERYTHING
2. **Add `let` bindings** for shared intermediate values in spawned cells
3. **Distinguish `⊨` (constraint) from assertions** on crystallized cells
4. **Define "max N" semantics** — N retries or N total attempts?
5. **Resolve ⊢⊢ spawner semantics** — scope, oracle inheritance, recursion
6. **Formalize Liskov substitution** for cell evolution (preserve given/yield/⊨)
7. **Address 0/0 class of bugs** — skip-with values vs downstream invariants
8. **Clarify ∴ on ⊢= cells** — is it documentation or active instruction?
