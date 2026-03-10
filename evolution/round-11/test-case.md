# Round 11: Integration Test — Full Cell Execution Model

## Focus
This is the capstone round. Instead of testing individual features, we test
the FULL Cell execution model: eval-one, crystallization, spawning, ⊥
propagation, oracle recovery, proof-carrying, and §-quoting all in one
program. Can an agent execute a program that uses everything?

## What We're Testing

### T1: Self-Crystallizing Test Harness
A program that writes code, tests it, crystallizes successes, and retries
failures. Uses: ⊢, ⊢=, ⊢⊢, §, ⊨, ⊨?, ⊥? skip with, ≡, →, ▸.
Every major Cell feature in one program.

### T2: Proof-Carrying Pipeline with Oracle Cascade
An NP-solver with P-verifier, where the verifier crystallizes and oracle
failures trigger retry-with-feedback. The classic Cell pattern pushed to
its limit.

### T3: Evolution Loop with Spawner
⊢∘ evolving a cell through judge/improve rounds, where the judge is a
spawner that runs multiple evaluation criteria in parallel. Tests ⊢∘ + ⊢⊢
interaction.

### T4: Metacircular eval-one with ⊥ Propagation
The eval-one interpreter from R7, extended with ⊥ propagation. When a cell
in the interpreted program fails, eval-one must propagate ⊥ to downstream
cells. Tests the hardest composition: metacircular + ⊥.

## Evaluation Questions (all variants)
1. Execute the program step-by-step. Show all intermediate states.
2. Which cells crystallize? Which must stay soft? Why?
3. Trace every oracle check. Show PASS/FAIL with reasoning.
4. What's the minimum number of LLM calls needed? Which cells are LLM-free?
5. Rate the overall program clarity 1-10. Could you maintain this program?
