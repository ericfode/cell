# Round 14: Syntax Darwinism — Tournament Elimination

## Focus

6 syntax candidates compete head-to-head expressing the same non-trivial program.
Each frame culls the bottom half. Tests which syntax survives LLM cold-read pressure.

## The Tournament

**Candidates** (selected from R1's 12 original variants):

| ID | Style | Philosophy | Source |
|----|-------|------------|--------|
| S1 | turnstile | Formal logic operators (`⊢`, `∴`, `⊨`) | v9-turnstile |
| S2 | proof-style | Theorem prover (`theorem`, `proof:`, `check:`) | v11-proof-style |
| S3 | natural-minimal | Plain English (`cell`, `in:`, `out:`, `do:`, `ok:`) | v6-natural-minimal |
| S4 | lambda-math | Mathematical (`λ`, `∴`, `⊨`) | v10-lambda-math |
| S5 | conversation | Chat-like (`@name(inputs)`, `?` checks) | v2-conversation |
| S6 | arrow-chain | Arrow notation (`⟶`, `「」`, `◈`) | v4-arrow-chain |

## Benchmark Program: Translate & Verify

A 4-cell pipeline exercising the key Cell features:

1. **seed** (crystallized): Set phrase and target language
2. **translate** (soft/LLM): Translate phrase, with oracle recovery
3. **back-translate** (soft/LLM): Round-trip translation, with ⊥ handling
4. **verify** (mixed): Compare original to round-trip, rate fidelity

Features exercised: crystallized cells, soft cells, data flow references,
oracle checks, oracle retry, ⊥ propagation, skip-with recovery.

## Evaluation Criteria

Each candidate is scored 1-10 on:

1. **Cold-read clarity**: Can an LLM parse the structure on first read?
2. **Feature expression**: Does the syntax naturally accommodate all Cell features?
3. **Ambiguity resistance**: Are there parsing ambiguities or confusable constructs?
4. **Density**: Information per line (conciseness without sacrificing clarity)
5. **Extensibility**: Could the syntax accommodate future features (spawners, loops)?

## Tournament Rules

- Frame 0: All 6 candidates evaluated. Bottom 3 culled.
- Frame 1: Surviving 3 re-evaluated on a harder program. Bottom 1-2 culled.
- Frame 2: Final 1-2 compared in depth. Winner declared.
