# Round 9 Results: Oracle Cascade

## Mode: COLD READ (no syntax reference)

## Rating
- Oracle cascade (multi-step with failure handling): **7/10**

## Execution Flow

Three-step DAG with oracle-mediated data flow:
```
extract-sentiment → generate-response → quality-gate
```
Steps connected by `given step→field` syntax. The quality-gate uses `⊢=`
(pure computation), the other two are oracle-mediated.

### Failure Model

Two exhaustion strategies discovered:
- `error-value(⊥)` — abort with typed absence (bottom)
- `partial-accept(best)` — salvage best failed attempt

Retries append `oracle.failures` context to the prompt, giving the oracle
feedback on what went wrong. Bounded by `max N`.

**Maximum oracle calls**: 4 + 3 + 0 = 7 (quality-gate is deterministic via `⊢=`)

### Termination: YES
Bounded retries, DAG structure (no cycles), deterministic final step.
Always terminates in ≤7 oracle calls + 1 deterministic computation.

## Syntax Element Clarity (Cold Read)

| Element | Score | Notes |
|---------|-------|-------|
| `⊨?` | 6/10 | Readable as "contingent constraint" but relationship to `⊨` is gestural |
| `on failure:` | 9/10 | Crystal clear, natural language |
| `on exhaustion:` | 8/10 | Unambiguous in context — all retries spent |
| `error-value(⊥)` | 7/10 | PL-standard bottom, but ⊥ usually means non-termination — here it terminates |
| `partial-accept(best)` | 5/10 | Intent clear, "best" ranking undefined |
| `oracle.failures` | 7/10 | Implicitly scoped, schema unspecified |
| `⊢=` | 8/10 | Elegant — clearly marks pure computation vs oracle |
| `given step→field` | 9/10 | Data flow syntax reads naturally |

**Average**: 7.4/10

## Key Ambiguities

### Critical
1. **⊥ propagation**: When `extract-sentiment` returns `error-value(⊥)`,
   does `generate-response` receive ⊥ inputs? Does it short-circuit?
   Or does the runtime try to run it with missing data? This is the most
   important unresolved question — it determines whether the pipeline
   is fail-fast or fail-soft.

### Significant
2. **`partial-accept(best)` ranking**: No metric for "best." Last attempt?
   Most constraints satisfied? Highest confidence? The runtime needs a
   comparison function.

3. **Constraint timing**: Are `⊨` constraints checked post-hoc (after oracle
   responds) or injected into the prompt? Post-hoc → failed check = failure →
   retry. Pre-prompt → they're instructions, not checks. Round 8's execution
   trace (T2) shows post-hoc checking, but the program text doesn't specify.

4. **`max N` off-by-one**: "retry max 3" = 3 retries (4 total) or 3 total
   attempts? Classic ambiguity.

### Minor
5. **quality-gate has no feedback loop**: If `approved = false`, the program
   just ends. No mechanism to loop back to `generate-response`. Is this by
   design (caller handles rejection) or missing?

6. **`oracle.failures` schema**: What data per failure? Raw output, error
   message, or constraint violation details? Affects retry quality.

## Design Observations

### What works well
- **Cascade pattern is natural**: Each step's outputs feed the next.
  `given step→field` reads like a typed pipe.
- **`⊢=` vs `⊢` distinction**: Marking pure computation separately from
  oracle calls is elegant and critical for optimization — the runtime
  knows quality-gate never needs retries.
- **Failure context accumulation**: Appending `oracle.failures` to retries
  gives the oracle self-correcting feedback. This is a genuine pattern
  from LLM engineering (chain-of-repair).

### What needs work
- **Two exhaustion strategies, no unifying principle**: `error-value(⊥)` and
  `partial-accept(best)` are ad-hoc. What other strategies exist? Should
  there be a default? Should `partial-accept` require a ranking function?
- **No ⊥ propagation semantics**: This is the biggest gap. A multi-step
  pipeline MUST define what happens when an upstream step fails.
  Options: (a) fail-fast (⊥ propagates, pipeline aborts),
  (b) fail-soft (downstream gets ⊥, can handle it),
  (c) skip (downstream doesn't run, but no error).

## Cumulative Scores (all rounds)
- § quoting: 100% comprehension, universally natural
- ⊢= crystallization: 8/10
- ⊢∘ evolution loop: 8/10
- Proof-carrying computation: 9/10
- eval-one metacircular: 9/10
- Self-crystallization: 9/10
- Cell-as-agent: 8/10
- Oracle failure recovery ⊨?: 7/10
- Frontier growth: 6/10 (syntax gap)
- **Oracle cascade: 7/10** (solid pattern, ⊥ propagation gap)
