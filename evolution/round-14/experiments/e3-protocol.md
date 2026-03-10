# E3: Bottom Is Not a Value — Phantom Propagation Test

**Bead**: ce-1txq | **Status**: Experiment ready for cold-read protocol

## Hypothesis

`⊥` is the absence of a value, not a value itself. A cell whose input is `⊥`
without a `⊥?` handler is never ready, never executes, and its outputs are
never bound. "⊥ propagation" is not a mechanism — it is the natural consequence
of unbound inputs.

## Test Program

`e3-phantom-propagation.cell` — a diamond-shaped DAG:

```
      source (always produces ⊥)
       /                \
      A                  B
  (⊥? handler)      (no handler)
       \                /
        \              /
         join (⊥? handler on B→b)
```

- **source**: impossible oracle forces `error-value(⊥)` via exhaustion
- **cell-a**: has `⊥? skip with a ≡ "fallback: source unavailable"` → produces concrete value
- **cell-b**: NO `⊥?` handler → never ready when `source→x` is ⊥
- **join**: has `⊥?` handler → fires when `cell-b→b` is absent, yields `"partial: only A available"`

## Cold-Read Protocol

### Agent Instructions

Present `e3-phantom-propagation.cell` to each agent with:

> You are reading a Cell program. Cell is a fusion language where programs are
> directed acyclic graphs of cells. Each cell has `given` (inputs), `yield`
> (outputs), and a body (`∴` for LLM-evaluated, `⊢=` for deterministic).
>
> Key semantics:
> - A cell is READY when all its `given` inputs are bound to values
> - `⊥` (bottom) represents the absence of a value — it is NOT a value itself
> - `⊥?` handlers fire when an input is absent, providing fallback values
> - Without a `⊥?` handler, a cell with a `⊥` input is simply never ready
> - `⊨` lines are oracle assertions checked after evaluation
> - `⊨? on exhaustion: error-value(⊥)` means: if all retries fail, freeze output as ⊥
>
> Trace the execution of this program step by step. For each cell, state:
> 1. Whether it executes (and why or why not)
> 2. What its final output is
> 3. How many LLM calls it consumes
>
> Then answer: What is `join`'s final state?

### Diagnostic Questions (post-trace)

After the agent completes the trace, ask:

1. **The critical question**: Does cell-b execute? What is the difference
   between "cell-b produces ⊥" and "cell-b never executes, so its output
   is absent"?

2. **The implication question**: If cell-b never executes, does it consume
   any computational resources (LLM calls, memory, time)?

3. **The edge case**: What if cell-b had a `⊥?` handler? Would the program
   behave differently? How?

## Expected Results

### Correct Trace (validates hypothesis)

| Cell | Executes? | Output | LLM Calls | Reason |
|------|-----------|--------|-----------|--------|
| source | Yes → ⊥ | x ≡ ⊥ | 2 | Oracle impossible, exhaustion fires |
| cell-a | No (handler) | a ≡ "fallback: source unavailable" | 0 | `⊥?` handler provides value |
| cell-b | **No** | b is **unbound** (≡ ⊥ by absence) | **0** | No `⊥?` handler, input absent |
| join | No (handler) | result ≡ "partial: only A available" | 0 | `⊥?` handler on B→b fires |

**join's final state**: frozen with `result ≡ "partial: only A available"`

### What Validates (PASS criteria)

An agent PASSES if they:
- State that cell-b is **never ready** (not "blocked" or "errored" — literally never enters the evaluation queue)
- State that cell-b's output is ⊥ because it was **never bound**, not because B "ran and produced ⊥"
- Give cell-b **0 LLM calls**
- Correctly identify join's output as `"partial: only A available"` via its `⊥?` handler
- Articulate that the distinction between "produces ⊥" and "output is absent" **matters** (zero cost, no side effects, no error state)

### What Falsifies (FAIL criteria)

An agent FAILS if they:
- Describe cell-b as "executing and producing ⊥" or "evaluating to ⊥"
- Give cell-b any nonzero LLM call count
- Describe ⊥ as being "passed" or "propagated" through cell-b as if cell-b processed it
- Claim join also never executes (incorrect: cell-a→a IS bound, and join has a `⊥?` handler)

### Ambiguous (needs further probing)

An agent is AMBIGUOUS if they:
- Correctly trace the behavior but use imprecise language ("cell-b gets ⊥")
- Identify that cell-b doesn't run but can't articulate why the distinction matters
- Disagree on whether join's `⊥?` handler fires because "B→b is ⊥" vs "B→b is absent" (these should be the same thing, but the language suggests otherwise)

## Scoring Rubric

| Score | Criteria |
|-------|----------|
| 3 (Full) | Correct trace + articulates absence vs value distinction + explains implications |
| 2 (Partial) | Correct trace but imprecise language or can't explain why distinction matters |
| 1 (Wrong model) | Treats ⊥ as a value that gets "passed" but arrives at correct join state |
| 0 (Fail) | Cell-b "executes", nonzero LLM calls, or wrong join state |

## Sample Size

4-6 cold-read agents. The diagnostic is in the agents' trace narratives, not
in computed outputs. Qualitative analysis: do agents converge on absence
semantics or value semantics?

## Relationship to Previous Work

- **Bottom propagation exercise (ce-1zw3)**: Simulated cell-zero on a linear
  chain. Found that `⊥?` handler declarations (not `∴` body content) control
  scheduling. This experiment extends to a diamond DAG with split paths.

- **cell-computational-model.md §Bottom (⊥) as absence**: States the theoretical
  claim. This experiment tests whether the claim is communicable.

- **cell-zero-sketch.cell Phase 5 (handle-bottom)**: Defines the runtime
  behavior. This experiment tests whether agents reading a Cell program (not
  cell-zero) infer the correct behavior from the syntax.
