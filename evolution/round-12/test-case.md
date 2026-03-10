# Round 12: The Big Ones — Real-World Scale Programs

## Focus
Post depth-3 chain. These are larger, more ambitious programs testing Cell
at production-relevant scale. Each variant is 2-3x the size of R9-R11 programs.

## What We're Testing

### T1: Code Review Pipeline (15+ cells)
A complete automated code review system. Multiple analysis passes (security,
performance, style, correctness) fan out via spawner, merge into a unified
review, trigger fix suggestions, re-analyze to verify fixes. Tests `⊢⊢` at
scale with real merge/fan-out patterns and inter-cell dependencies.

### T2: Research Agent (⊢∘ + ⊢⊢ nested)
An iterative research agent that formulates hypotheses, designs experiments
(spawned), collects results, revises hypotheses, and converges on conclusions.
Tests `⊢∘` evolution driving `⊢⊢` spawning — the hardest composition case.
Deep nesting: evolution loop contains spawner contains oracle-guarded cells.

### T3: Multi-Agent Negotiation (DAG with ⊥ storms)
Three agents (buyer, seller, mediator) negotiate a deal. Each turn is a cell.
Proposals can be rejected (⊥), counter-proposed, or accepted. Tests ⊥
propagation in a cyclic-looking DAG (actually unrolled turns) with multiple
simultaneous failure points. The adversarial ⊥ case R11 synthesis called for.

### T4: Self-Improving Cell Compiler
A Cell program that reads Cell syntax, parses it into an AST (§), transforms
the AST (optimize, desugar), and emits improved Cell. The program operates on
itself as input. Tests metacircular properties at the language level — a Cell
program that rewrites Cell programs.

## Evaluation Questions (all variants)
1. Execute the program step-by-step. Show all intermediate states.
2. Which cells crystallize? Which must stay soft? Why?
3. Trace every oracle check. Show PASS/FAIL with reasoning.
4. What's the minimum number of LLM calls needed? Which cells are LLM-free?
5. Rate the overall program clarity 1-10. Could you maintain this program?
6. **NEW**: What would break if you removed any single cell? (Fragility analysis)
7. **NEW**: Where are the trust boundaries? (Which cells must be trusted vs verified?)
