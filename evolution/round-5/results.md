# Round 5 Results: Crystallization + Oracle Failure

## Ratings
- T1 crystallization syntax (▸, ⊢=, ✓): **8/10**
- T3 oracle retry (⊨?): syllable oracles crystallizable, retry(3) too naive
- T4 self-evolution (§greet'): **8/10**, but loop structure is implicit
- T5 mixed pipeline: **7/10**, LLM→crystallized boundary is the weak point

## Key Discoveries

### 1. Crystallization syntax works
- `∴` = natural language intent (soft)
- `⊢=` = deterministic expression (hard)
- `▸ crystallized` = purity annotation
- `✓` = oracle verified against concrete execution
- Progression: specify → implement → verify is natural

### 2. ⊢= catches unfaithful crystallization
Agent caught that `split(text, " ")` != "whitespace-separated tokens".
The oracles detect this gap on edge cases. Crystallization can be WRONG
and the oracle system catches it. This is the whole point.

### 3. ⊨? is a meta-oracle (recovery policy)
- `⊨` = assertion about the output
- `⊨?` = policy about what to do when ⊨ fails
- Clean separation: ⊨ validates the WHAT, ⊨? controls the WHAT-IF

### 4. Blind retry is useless
"retry(3) is the LLM equivalent of while(!works) try_again()"
Better alternatives:
- retry with oracle feedback (which oracle failed, why)
- decompose (break into smaller cells)
- verify-then-patch (fix failing lines, keep passing ones)
- escalate to different cell

### 5. Frozen interfaces enable safe self-modification
`⊨ §greet' has same given/yield signature as §greet`
= Liskov substitution for cells
Without this, self-modification cascades into incoherence.

### 6. Verification crystallizes before computation
Syllable counting (oracle) is crystallizable.
Haiku writing (generation) is not.
Sort verification (oracle) is crystallizable.
Sorting (generation) has many valid algorithms.
Pattern: CHECKING is always easier to crystallize than DOING.

### 7. LLM→crystallized boundary needs work
LLMs are tolerant parsers (crystallized→LLM is smooth).
Code is strict parser (LLM→crystallized has serialization gap).
The `yield key-words[]` type annotation helps but isn't enough.

### 8. Same ⊨ symbol means different things
On crystallized cells: ⊨ is a contract (verified at compile time)
On soft cells: ⊨ is a guardrail (checked at runtime, may fail)
"Elegant but misleading" — might need differentiation.

## Open Design Questions
1. Evolution loop needs first-class syntax (not implicit)
2. ▸▸ doesn't scale — need better version chain syntax
3. Oracle feedback mechanism for retry
4. Type strictness at LLM output boundaries
