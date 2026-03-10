# Cell R11: eval-one-bottom — Cold Read Execution

**Bead**: ce-v43
**Mode**: COLD READ (no syntax reference consulted)
**Date**: 2026-03-10

## Program Under Test

A Cell program with 6 cells: `program`, `step-a`, `step-b`, `step-c`, `eval-one`, `is-done`.
The program demonstrates quotation (`§`), meta-evaluation, oracle checking, and ⊥ error propagation.

## Execution Trace

### Top-Level Execution Order (Kahn's on outer cells)

| Step | Cell | Input | Output |
|------|------|-------|--------|
| 1 | program | (none) | §cells ≡ [§step-a, §step-b, §step-c] |
| 2 | eval-one | program→§cells | §executed-program (runs inner Kahn's) |
| 3 | is-done | eval-one→§executed-program | done ≡ true, remaining-unbound ≡ 0 |

### Inner Execution (inside eval-one, Kahn's on §cells)

**Iteration 1** — step-a ready (`given x ≡ 10`, inline binding):
- `⊢= doubled ← x * 2` → `doubled ≡ 20` (crystallized)
- `⊨ doubled = 20` → **PASS**

**Iteration 2** — step-b ready (`given step-a→doubled ≡ 20`):
- `∴ Write a sentence that mentions the number «20»` → LLM call
- Example: `message ≡ "The number 20 is the result of doubling ten."`
- `⊨ message contains "20"` → **PASS**
- `⊨ message is exactly one sentence` → **PASS**

**Iteration 3** — step-c ready (`given step-b→message`, NOT ⊥ → handler inactive):
- `∴ Convert «message» to uppercase` → LLM call
- `upper-message ≡ "THE NUMBER 20 IS THE RESULT OF DOUBLING TEN."`
- `⊨ upper-message contains "20"` → **PASS**
- `⊨ upper-message contains no lowercase letters` → **PASS**

### ⊥ Path (step-b failure scenario)

1. step-b oracle fails → `⊨? on failure`: retry with `«oracle.failures»` appended, max 1
2. Retry also fails → `⊨? on exhaustion`: `error-value(⊥)` → `message ≡ ⊥`
3. step-c: `given step-b→message ⊥?` triggers → `skip with upper-message ≡ "STEP-B FAILED — NO MESSAGE TO CONVERT"`
4. step-c skips its ∴ body entirely, uses fallback value

## Oracle Results

| # | Oracle | Cell | Result | Notes |
|---|--------|------|--------|-------|
| 1 | `doubled = 20` | step-a | PASS | 10 × 2 = 20 |
| 2 | `message contains "20"` | step-b | PASS | LLM instructed to mention 20 |
| 3 | `message is exactly one sentence` | step-b | PASS | "a sentence" = singular |
| 4 | `upper-message contains "20"` | step-c | PASS | Digits survive uppercasing |
| 5 | `upper-message no lowercase` | step-c | PASS | Full uppercase conversion |
| 6 | `all yields bound (or ⊥)` | eval-one | PASS | All 3 inner cells produced values |
| 7 | `execution order respects deps` | eval-one | PASS | Topo order: a → b → c |
| 8 | `⊥ propagation correct` | eval-one | PASS | Vacuously true (happy path) |
| 9 | `done ⇒ remaining-unbound = 0` | is-done | PASS | done=true, remaining=0 |

## Evaluation Answers

### 1. Step-by-step execution

See Execution Trace above. Three-phase execution:
- Phase 1: Outer program cell binds §cells (quoted cell definitions as data)
- Phase 2: eval-one receives §cells and runs inner Kahn's (step-a → step-b → step-c)
- Phase 3: is-done checks all yields are bound

### 2. Crystallized vs Soft

**Crystallized (⊢=):** program, step-a, is-done — deterministic data assembly, arithmetic, structural checks.

**Soft (∴):** step-b (NL generation), step-c (uppercase conversion), eval-one (meta-evaluator).

**Why:** Crystallized cells have no ambiguity — their outputs are determined entirely by their inputs via a computable function. Soft cells require interpretation (step-b, step-c) or contain soft sub-steps (eval-one).

**Note:** step-c (uppercase) sits on the crystallization boundary. `toUpperCase()` is deterministic, but the program models it as soft — perhaps intentionally, to test the soft pipeline uniformly, or because natural language uppercase conversion has edge cases (accented characters, mixed scripts).

### 3. Oracle trace

All 9 oracles PASS in the happy path. See table above.

Key nuance: Oracle #8 (`if step-b produces ⊥, step-c uses ⊥? skip-with`) is vacuously true when step-b succeeds. The mechanism is correctly specified but untested in the happy path.

**Ambiguity:** Do oracles fire on skip-with values? If yes, step-c's oracle `upper-message contains "20"` would FAIL on the fallback "STEP-B FAILED — NO MESSAGE TO CONVERT". I argue oracles should NOT fire on skip-with values, since the ⊥? handler bypasses normal execution.

### 4. Minimum LLM calls

**3 LLM calls minimum:** step-b, step-c, eval-one.

**LLM-free:** program (data), step-a (arithmetic), is-done (structural check).

If eval-one is implemented as runtime machinery (Kahn's in code, not via LLM): **2 LLM calls minimum**.

### 5. Program clarity: 7/10

**Strengths:**
- Parseable from context alone — symbols are mnemonically chosen
- Explicit data flow via given/yield/→
- Elegant ⊥ propagation with ⊥? skip-with handlers
- Clean separation of oracle checking (⊨) from recovery (⊨?)
- §quotation enables meta-programming (eval-one as meta-evaluator)

**Could I maintain this?** Yes, with a syntax reference for edge cases. Core concepts learnable in minutes.

## Friction Points

1. **Oracle behavior on ⊥? skip-with**: Do oracles fire on substituted values? Unspecified.
2. **eval-one as ∴ vs runtime**: Is the meta-evaluator genuinely soft, or is ∴ documenting what crystallized runtime machinery does?
3. **§quotation scope**: When eval-one receives §cells, does it see structural data or opaque text?
4. **«oracle.failures» mechanism**: Referenced in step-b's retry policy but never formally defined.
5. **Two `given` semantics**: `given x ≡ 10` (inline constant) vs `given step-a→doubled` (dependency reference) — could benefit from clearer distinction.

## Confidence: 8/10

High confidence in execution trace and oracle results. Main uncertainty: edge-case semantics around ⊥? handlers, oracle firing rules, and §quotation structure.
