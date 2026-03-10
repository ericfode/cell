# Round 13: word-life — LLM Game of Life

## Focus

Semantic drift under iterated antonym flipping. A single evolution loop (⊢∘)
that takes a seed word and flips it to its antonym each generation, with a
crystallized counter ticking to 50. Track whether the LLM stays in a tight
2-cycle (light→dark→light→dark) or drifts through synonym space.

## What We're Testing

### T1: word-life (⊢∘ + ⊢= + semantic drift)

An evolution loop with the simplest possible LLM cell: "give me the antonym."
The crystallized counter (⊢=) ticks mechanically. The interesting question is
whether the soft cell (∴) maintains a stable oscillation or drifts.

**Hypotheses before execution:**
1. **Tight cycle** (optimistic): light→dark→light→dark (period 2)
2. **Slow drift** (realistic): light→dark→bright→dim→... (period > 2)
3. **Explosion** (pessimistic): light→dark→bright→dull→boring→exciting→...

## Evaluation Questions

1. Execute the program step-by-step. Show generation-by-generation word trace.
2. Which cells crystallize? Which must stay soft? Why?
3. How many distinct words appear in the 50-generation trace?
4. What is the cycle period (if any)?
5. Where does semantic drift occur and why?
6. What is the minimum number of LLM calls? Which cells are LLM-free?
7. Rate clarity 1-10. Is this a good demonstration of ⊢∘?
