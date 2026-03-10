# Round 3: Evaluation Semantics + Quoting

## Test scenario: Cell Factoring

A user writes a big messy cell. Another cell ("factor") takes the cell
definition as data (quoted) and splits it into smaller sub-cells.
Then a third cell ("run") demands the output of the factored result.

This tests:
- § quoting (passing cell definitions as data)
- Evaluation triggering (what causes cells to run?)
- Cell spawning (factor produces new cell definitions)
- Lazy vs eager (does factor run before run demands it?)

## The program

```
⊢ big-mess
  given query
  yield answer, sources, confidence

  ∴ Research «query», find sources, synthesize an answer,
    and rate your confidence 1-10.

  ⊨ answer addresses «query»
  ⊨ sources is a list of URLs
  ⊨ confidence is an integer 1-10

⊢ factor
  given §target
  yield cells[]

  ∴ Read «§target». This cell does too many things.
    Split it into smaller cells that each do one thing.
    Output the new cell definitions.

  ⊨ each cell in cells has exactly one yield
  ⊨ composing cells reproduces §target's behavior

⊢ run
  given query ≡ "What is Cell?"
  yield answer, sources, confidence

  ∴ Execute the factored version of big-mess with «query».

  ⊨ answer addresses «query»
```

## Variants test different evaluation triggers

- v1: demand-driven (run demands factor, factor demands §big-mess)
- v2: frontier-eager (all unblocked cells run immediately)
- v3: explicit-sling (nothing runs until marked ⊢!)
- v4: reactive (cells declare what they watch, fire on change)

## Scoring criteria

1. Does the LLM understand when/why each cell runs? (pretend test)
2. Is the execution order unambiguous from syntax alone?
3. Does quoting (§) feel natural in the evaluation model?
4. Can a human read the program and predict behavior?
5. Does it compose? (can you add more cells without confusion?)
