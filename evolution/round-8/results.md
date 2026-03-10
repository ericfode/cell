# Round 8 Results: Frontier Growth, Oracle Recovery, Agent Pattern

## Ratings
- T1 frontier growth (semantic automata): **6/10** (concept good, syntax insufficient)
- T2 oracle failure recovery: **7/10** (core mechanism sound, needs fuller story)
- T3 cell-as-agent: **8/10** (eval/apply emerges naturally from §)

## Key Discoveries

### 1. Frontier growth needs new syntax
The concept maps naturally to Cell's evaluation model (just add cells to
the ready-set). But Cell's syntax has no construct for spawning.
Proposal: `⊢⊢` for spawner cells (meta-level), distinct from `⊢`.
Also needs: template instantiation syntax, auto-naming, halting conditions.

### 2. Oracle-assertions vs oracle-rules are fundamentally different
- `⊨ sentiment ∈ {"positive", "negative", "mixed"}` = assertion (post-hoc check)
- `⊨ if text has positive ∧ negative → sentiment = "mixed"` = rule (prescription)
Assertions catch formatting errors. Rules catch reasoning errors.
Different retry strategies. Should be syntactically distinct.

### 3. Conditional oracles have soft preconditions
`if text contains positive and negative language` requires LLM judgment
to evaluate the precondition. The rule LOOKS deterministic but ISN'T.
Cell should mark these explicitly.

### 4. dispatch cannot crystallize (permanently dynamic)
Any cell that executes §-referenced cells is an interpreter.
The § sigil literally marks the crystallization boundary.
"In any system with eval/apply, the apply step resists compilation."
Lisp has the same property.

### 5. Streaming is absent
Current syntax handles batch-agent cleanly.
Real agents are long-running. Need stream type annotation (`~`?)
or external orchestration loop. Open design question.

### 6. The audit trail belongs in metadata
Document should show final accepted state (clean).
Attempt history preserved as collapsible metadata.
"Git stores the final state of each file, but preserves full history."

### 7. Exhaustion handler needed for ⊨?
`⊨? on exhaustion: escalate | error-value | partial-accept`
Currently undefined behavior when max retries hit.
Must be explicit — silent failure is worst kind.

## New Syntax Proposals
- `⊢⊢` = spawner cell (emits new cells into the program)
- `~` = stream binding (incremental input)
- `⊨ assert:` vs `⊨ rule:` for oracle classification
- `⊨? on exhaustion:` clause
- Auto-naming for spawned cells (content-addressed or sequential)

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
