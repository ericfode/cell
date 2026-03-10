# Round 13: Fractal Dispatch — Targeted Stress Tests

## Focus

R12 found 16 bugs and recommended spec writing. Before that, we need to
nail the 4 weakest areas with targeted stress tests. Each variant isolates
ONE concern and pushes it to its limit.

## What We're Testing

### T1: Spawner Cascade (⊢⊢ depth stress)

A spawner that spawns spawners. Three levels deep: `explore` spawns
`sub-explore` cells, each of which spawns `leaf` cells. Tests whether
agents correctly track which cells exist at each depth, how `until`
clauses compose across levels, and what happens when a leaf fails.

This is the pattern that would emerge in a recursive research agent
or a recursive code analysis tool.

### T2: Oracle Trust Boundaries (⊨ hierarchy)

A pipeline where early cells have semantic oracles (LLM-judged), middle
cells have structural oracles (checkable by code), and late cells have
deterministic oracles (exact value checks). The question: when an early
semantic oracle passes but a late deterministic oracle fails, where is
the trust break? Does the agent correctly identify that the semantic
oracle was too permissive?

This tests the assert-vs-rule distinction from R8 and the oracle
promotion pattern from R7.

### T3: Bottom Storm (⊥ cascade + recovery)

A DAG where ONE early cell can produce ⊥, and 6 downstream cells must
handle it. Some have `⊥? skip with`, some have `⊥? error-value(⊥)`,
and some have NO handler (the #1 bug class from R12). The question:
does the agent correctly trace which cells receive ⊥, which handle it,
and which propagate it? Does it identify the missing handlers?

### T4: Quotation Mechanics (§ round-trip)

A cell that receives `§target` (a cell definition as data), modifies it
(adds an oracle), and yields `§target'`. A downstream cell receives BOTH
`§target` and `§target'` and must diff them. Tests whether the agent
treats § values as data (not executing them) and whether modification
preserves structure.

## Evaluation Questions (all variants)

1. Execute the program step-by-step. Show all intermediate states.
2. Identify every point where the program could fail or produce ⊥.
3. Trace every oracle check. Show PASS/FAIL with reasoning.
4. Which cells could be crystallized? Which must stay soft? Why?
5. Rate program clarity 1-10. What would you change?
6. **KEY**: What does this test program reveal about Cell's design?
   What spec changes would make this program simpler/clearer?
