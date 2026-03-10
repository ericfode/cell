# E4: Metacircular Evaluator Test — Results

**Date**: 2026-03-10
**Experimenter**: chrome (polecat)
**Bead**: ce-u20i

## Hypothesis Tested

**Metacircular** — Cell-zero, written in Cell, can evaluate Cell programs.
An LLM reading cell-zero.cell can use it as instructions to evaluate a target
program, producing the same structural outcome as direct evaluation.

## Protocol

Two independent agent evaluations of the same target program:

- **Agent A (cell-zero-guided)**: Given cell-zero-sketch.cell + target program.
  Instructed: "You are cell-zero. Follow the instructions in cell-zero-sketch.cell
  to evaluate the target program. Show each phase."

- **Agent B (direct evaluation)**: Given only the target program + standard Cell
  execution rules. No cell-zero.

### Target Program

```cell
⊢ greet
  given name ≡ "Alice"
  yield message
  ∴ Write a greeting for «name».
  ⊨ message mentions «name»

⊢ shout
  given greet→message
  yield loud
  ⊢= loud ← uppercase(greet→message)
  ⊨ loud = uppercase(greet→message)
```

Two-cell linear DAG: greet (semantic) → shout (deterministic).

## Results

### Structural Trace Comparison

| Property | Agent A (cell-zero) | Agent B (direct) | Match? |
|----------|-------------------|------------------|--------|
| Evaluation order | greet → shout | greet → shout | **YES** |
| greet.message | "Hello, Alice!" | "Hello, Alice!" | **YES** |
| shout.loud | "HELLO, ALICE!" | "HELLO, ALICE!" | **YES** |
| Oracle: greet | pass | pass | **YES** |
| Oracle: shout | pass | pass | **YES** |
| LLM calls | 1 | 1 | **YES** |
| Deterministic evals | 1 | 1 | **YES** |
| Frozen cells | {greet, shout} | {greet, shout} | **YES** |
| Quiescence reason | all cells frozen | all cells frozen | **YES** |

### Agent A: Phase-by-Phase Execution

Agent A followed all 8 cell-zero phases in order across 2 iterations + 1 quiescence check:

**Iteration 1 (cell: greet)**:
1. read-graph → extracted 2 cells, 1 edge. Oracles pass.
2. check-inputs → ready=[greet], blocked=[shout]. Oracles pass.
3. pick-cell → greet (only candidate, leaf-first). Oracle pass.
4. evaluate → semantic body, produced message="Hello, Alice!". Oracles pass.
5. spawn-claims → 1 claim cell (semantic: does message mention name?). Oracles pass.
6. check-claims → claim passes ("Hello, Alice!" contains "Alice"). all_pass=true.
7. decide → FREEZE. greet.message ≡ "Hello, Alice!". Oracles pass.
8. handle-bottom → no changes (no ⊥). Oracle pass.

**Iteration 2 (cell: shout)**:
1. check-inputs → ready=[shout], frozen=[greet]. Oracles pass.
2. pick-cell → shout (only candidate). Oracle pass.
3. evaluate → deterministic body, uppercase("Hello, Alice!") = "HELLO, ALICE!". Oracles pass.
4. spawn-claims → 1 claim cell (deterministic: exact equality). Oracles pass.
5. check-claims → claim passes. all_pass=true.
6. decide → FREEZE. shout.loud ≡ "HELLO, ALICE!". Oracles pass.
7. handle-bottom → no changes. Oracle pass.

**Iteration 3**: check-inputs → ready=[]. QUIESCE.

### Agent B: Direct Execution

Agent B evaluated cells in topological order without explicit phase separation:

**Step 1 (greet)**: semantic body → "Hello, Alice!" → oracle pass → freeze.
**Step 2 (shout)**: deterministic body → "HELLO, ALICE!" → oracle pass → freeze.
**Quiescence**: all cells frozen, no ready cells remain.

### Level Confusion Analysis

Agent A explicitly noted: "cell-zero's phases (read-graph, check-inputs, pick-cell,
evaluate, spawn-claims, check-claims, decide, handle-bottom) were used as
INSTRUCTIONS to evaluate the TARGET program's cells (greet, shout). At no point
were cell-zero's own cells treated as evaluation targets."

**No level confusion occurred.** Failure mode C (treating cell-zero's cells as
evaluation targets) was NOT triggered.

## Verdict

### VALIDATED

The metacircular evaluator test **validates** the hypothesis:

1. **Functional metacircular evaluator**: Agent A correctly identified and followed
   all cell-zero phases in order. Cell-zero provides sufficient instructions for
   an LLM to evaluate Cell programs.

2. **Structural identity**: The frozen graphs from both agents are identical —
   same cells frozen, same values bound, same oracle results, same evaluation
   order, same quiescence condition.

3. **No level confusion**: Agent A maintained clear separation between cell-zero's
   phases (instructions) and the target program's cells (evaluation targets).

4. **No distortion**: The metacircular layer did not introduce any structural
   differences. Both agents produced bit-identical frozen values.

## Caveats and Limitations

1. **Trivial target program**: The greet-shout program is deliberately simple
   (2 cells, 1 edge, no ⊥, no retries). More complex programs with ⊥ handling,
   spawners, or retry loops would stress the metacircular evaluator more.

2. **Same model**: Both agents were the same LLM model in the same session context.
   Cross-model testing would be more rigorous.

3. **Semantic output convergence**: Both agents produced the identical greeting
   "Hello, Alice!" — this is expected for a trivial case but may not hold for
   more creative/open-ended semantic bodies.

4. **No adversarial cases**: The experiment did not test edge cases where cell-zero's
   phase instructions might conflict with the target program's semantics.

## Recommended Follow-Up

- Run with a more complex target program (diamond DAG, ⊥ handlers, retries)
- Test with a target program that has a spawner (⊢⊢) to stress the eval-loop
- Cross-model testing (Agent A on one model, Agent B on another)
- Test with a target program where semantic evaluation is ambiguous (to see if
  cell-zero's structured phases produce better consistency)
