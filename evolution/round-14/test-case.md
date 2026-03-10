# Round 14: Evolution Loop Stress Tests

## Focus

R13 tested fan-out DAGs (bottom storm, quotation roundtrip, word-life). R14
shifts to **evolution loops** (⊢∘) — the most complex Cell construct. Three
variants test fundamentally different loop patterns.

## What We're Testing

### V1: Distillation Loop (crystallization via ⊢∘)

A loop that generates a response, distills it to a template, tests the template,
and decides whether to crystallize. Tests the **substrate transfer** claim:
can a soft cell (LLM-generated response) evolve into a crystallized template
(deterministic) through iterative refinement?

Key questions:
- Does frame-by-frame execution produce coherent state evolution?
- Can polecats correctly track `§` references inside loop bodies?
- Does the `partial-accept(best)` exhaustion policy make sense?

### V2: Syntax Darwinism (tournament elimination via ⊢∘)

Six syntax candidates compete: each round, all express the same program,
eval-one judges confidence, bottom half is culled. Tests **eval-one as a
selection mechanism** and whether syntax clarity correlates with execution
confidence.

Key questions:
- Do polecats consistently rate the same syntaxes high/low?
- Does the tournament converge? (Do winners change between frames?)
- Which syntax properties predict cold-read executability?

### V3: Oracle Adversary (red-team via ⊢∘)

An attacker finds loopholes in a challenge, a judge rules, and the challenge
evolves to close loopholes. Tests **oracle trust boundaries** — whether
semantic oracles (LLM-judged) can be hardened through adversarial iteration.

Key questions:
- Does the challenge converge to robustness? (Attacker eventually loses?)
- Are the loopholes found by different polecats similar or divergent?
- Does hardening over-specify the challenge?

## Execution Protocol

Each bead contains ONE FRAME (seed + first iteration). Polecats execute
step-by-step, output structured JSON, and complete via `gt done`.

## Evaluation Questions (all variants)

1. Execute each cell in order. Show inputs and outputs.
2. Check all oracle assertions. Which pass? Which fail?
3. What is the loop state after this frame?
4. Could this frame's output feed the next frame correctly?
5. Rate execution clarity 1-10.
6. What spec changes would make the loop construct clearer?
