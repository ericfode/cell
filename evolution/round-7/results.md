# Round 7 Results: eval-one (Metacircular Interpreter)

## Ratings
- T1 eval-one abstract + concrete: **9/10**
- T3 mixed crystal/soft eval-one: **8/10**

## Key Discoveries

### 1. eval-one is Kahn's algorithm, one step at a time
"Find cells whose given inputs are fully bound" = topological sort,
peeling off one source node per step. Well-understood since 1974.
An agent said: "I'm confident I could build it from these two programs
alone — one abstract, one concrete."

### 2. The document IS the state (isomorphism proven)
Agent showed h0→h1→h2→h3 as full program text at each step.
The ONLY change between states: one yield gains a ≡ binding.
- You can diff states to see what changed
- You can hash states for content addressing
- You can persist states mid-flight (resume later)
- Two agents looking at the same document see the same state

### 3. Termination is guaranteed by monotonicity
Yields only get bound, never unbound → state moves strictly upward
in a finite lattice → no cycles possible → termination guaranteed.
The max-100 bound is a safety belt, not a necessity.

### 4. Confluence (Church-Rosser) holds
When multiple cells are ready, execution order doesn't matter.
Ready cells are independent (otherwise one wouldn't be ready).
Same final result regardless of scheduling order.
Parallel execution is semantically valid.

### 5. eval-one CANNOT be crystallized (permanently soft)
It must execute arbitrary ∴ blocks → requires LLM → stays soft.
eval-one is the SOFT KERNEL of Cell. The irreducible LLM dependency.
Same as crystallize — these are the warm layers.

### 6. is-done and hash CAN be crystallized
is-done: "does every yield have ≡?" — pure syntax scan.
hash: content hash of program text — pure computation.
These are infrastructure cells — structure, not meaning.

### 7. Oracle promotion: oracles encode the answer
The oracle `⊨ n = len(tokens)` LITERALLY STATES the implementation.
The runtime can read the oracle and crystallize automatically.
"With the oracle as written: 0 examples needed."

### 8. Cost-aware scheduling
Execute crystallized (free) cells first → may unlock more cells
before any LLM call → reduces total LLM cost.
Cost tracking is natural but belongs in the trace, not syntax.

### 9. The core value proposition (stated by agent)
"Write everything as soft cells first. Crystallize incrementally.
The oracles bridge the gap. Start soft, harden gradually,
never lose correctness. Progressive crystallization with
oracle-guaranteed equivalence."
