# Round 9: Spawner Mechanics & Oracle Recovery Under Stress

## Focus
Two weakest areas from R8:
1. **Frontier growth / spawner syntax (⊢⊢)**: 6/10 — concept maps to Cell but syntax insufficient
2. **Oracle failure recovery (⊨?)**: 7/10 — core mechanism sound but needs fuller story

## What We're Testing

### T1: Spawner with Halting Condition
A spawner cell (⊢⊢) that generates follow-up cells from an exploration,
with explicit halting via `until`. Tests whether agents can trace
dynamic cell creation and termination.

### T2: Oracle Cascade Failure
A pipeline where oracle failures propagate — cell A fails ⊨, retries with
⊨? feedback, and cell B depends on A's output. Tests whether agents
understand retry-with-feedback AND downstream dependency blocking.

### T3: Spawner + Oracle Combined
A spawner that generates cells WITH oracles, then a verifier checks all
spawned cells' oracle results. The hard case: dynamic oracle count.

### T4: Exhaustion Semantics
What happens when ⊨? retries are spent? Tests the `on exhaustion:` clause
with escalate, error-value(⊥), and partial-accept strategies.

## Evaluation Questions (all variants)
1. Can you trace the spawner's output? How many cells get created?
2. What happens when an oracle fails? Show the retry flow.
3. Does the program terminate? Why or why not?
4. Rate the clarity of each new syntax element (⊢⊢, ⊨?, on exhaustion) 1-10.
5. What's ambiguous or underspecified?
