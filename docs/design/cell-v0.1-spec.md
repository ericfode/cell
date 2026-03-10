# Cell Language Specification v0.1

*Discovered through 7 rounds of evolutionary syntax testing with blind LLM agents.*

## What Cell Is

Cell is a self-bootstrapping metacircular language for LLMs. Programs
are documents. Execution fills in values. The document IS the program
IS the state. Cells start as natural language (soft) and progressively
crystallize into deterministic code (hard) under oracle pressure.

Cell is the Scheme of LLMs.

## Core Syntax

### Cell Declaration

```
⊢ name
  given input1
  given input2 ≡ "default value"
  given other-cell→output
  yield output1, output2

  ∴ Natural language instruction using «input1» and «input2».

  ⊨ output1 satisfies some property
  ⊨ output2 = some deterministic expression
```

### Symbols

| Symbol | Name | Meaning |
|--------|------|---------|
| `⊢` | turnstile | declare a cell |
| `∴` | therefore | natural language intent (soft body) |
| `⊢=` | hard turnstile | deterministic expression (hard body) |
| `⊨` | models | oracle assertion (postcondition) |
| `⊨?` | meta-oracle | recovery policy (what to do on failure) |
| `§` | section | quotation (cell definition as data) |
| `«»` | guillemets | interpolation (splice value into text) |
| `≡` | identical | binding (concrete value assignment) |
| `→` | arrow | output access (cell→field) |
| `▸` | refinement | stage annotation (crystallized, verified) |
| `✓` / `✗` | check marks | oracle pass/fail (in executed form) |
| `⊢∘` | evolution | fixed-point combinator over cells |

## Execution Model: eval-one

Cell uses **Kahn's algorithm**, one step at a time:

1. Find all cells whose `given` inputs are fully bound (`≡` present)
2. Pick ONE such cell
3. Execute it (interpret `∴` or evaluate `⊢=`)
4. Fill in its `yield ≡` values
5. Repeat until `is-done` (all yields bound)

### Properties (proven through testing)

- **Document-is-state**: The program text IS the execution state.
  Each step changes exactly one `yield` line to include `≡ value`.
- **Monotonicity**: Yields only get bound, never unbound.
  State moves strictly upward in a finite lattice.
- **Termination**: Guaranteed by monotonicity. No cycles possible.
- **Confluence**: Execution order of independent cells doesn't matter.
  Same final result regardless of scheduling. Parallel execution valid.
- **Content addressing**: Hash the document = hash the state.
  Each eval-one step = hash transition (h0 → h1 → h2 → ...).

### Example Trace

```
State h0:                         State h1 (after eval-one):
⊢ add                            ⊢ add
  given a ≡ 3                      given a ≡ 3
  given b ≡ 5                      given b ≡ 5
  yield sum          ←changed→     yield sum ≡ 8
  ...                              ...

⊢ double                         ⊢ double
  given add→sum                    given add→sum     ← now resolvable
  yield result                     yield result
  ...                              ...
```

## Quotation: §

`§` passes a cell's definition as data (not its output).

```
§greet              -- the full definition of greet, as a value
«greet→message»     -- the output of executing greet (existing)
given §target       -- input expects a cell definition
«§target»           -- interpolate definition into prompt
```

Tested across 20+ agents. Zero confusion. 100% comprehension.

## Crystallization

The progression from soft to hard:

```
⊢ word-count                     -- SOFT: ∴ natural language
  given text
  yield count
  ∴ Count the words in «text».
  ⊨ count = number of whitespace-separated tokens in «text»

⊢ word-count ▸ crystallized      -- HARD: ⊢= deterministic code
  given text
  yield count
  ⊢= split(«text», " ").length
  ⊨ count = number of whitespace-separated tokens in «text»
```

### Key insight: verification crystallizes before computation

| Cell type | Crystallizable? | Why |
|-----------|----------------|-----|
| sort (computation) | Hard — many valid algorithms | LLM chooses approach |
| verify-sort (verification) | Easy — one correct behavior | Just check properties |
| crystallize (code generation) | Never — permanently soft | Generates code from NL |
| eval-one (interpreter) | Never — permanently soft | Executes arbitrary ∴ |
| is-done (structural check) | Trivially | Pure syntax scan |
| hash (content hash) | Trivially | Pure computation |

### Oracles on crystallized vs soft cells

On soft cells: `⊨` is a **guardrail** (checked at runtime, may fail).
On crystallized cells: `⊨` is a **contract** (verified at compile/test time).
Same syntax, different trust level.

## Oracle System

### Oracle types

```
⊨ result = 55                    -- deterministic (exact value check)
⊨ sorted is a permutation        -- structural (checkable by code)
⊨ summary is 2-3 sentences       -- semantic (requires LLM judgment)
⊨ reversed read backwards = text -- ambiguous (needs interpretation commitment)
```

### Oracle failure recovery (⊨?)

```
⊨? on failure:
  retry with «oracle.failures» appended to prompt
  max 3 attempts
```

`⊨?` is a meta-oracle — policy about what to do when `⊨` fails.
Key insight: retry WITH FEEDBACK, not blind retry.

### Oracle promotion

When an oracle like `⊨ n = len(tokens)` literally states the
implementation, the runtime can crystallize automatically.
The oracle IS the implementation.

## Proof-Carrying Computation

Cell's killer pattern. Rated 9/10.

```
⊢ solve                          -- LLM does the hard work
  given equation
  yield x, proof[]                -- produces answer + certificate

⊢ substitute ▸ crystallized      -- code does the easy work
  given solve→x
  given equation
  yield holds
  ⊢= holds ← eval(lhs, x) == eval(rhs, x)  -- plug and check
```

The LLM operates in "NP space" (find a solution).
The crystallized verifier operates in "P space" (check the solution).
The verifier ALWAYS catches wrong answers.

## Evolution Loops: ⊢∘

First-class syntax for iterative self-improvement.

```
⊢∘ evolve(greet, name ≡ "Alice")
  through judge, improve
  until judge→quality ≥ 7
  max 5
```

`⊢∘` is a parameterized fixed-point combinator over cell definitions.
Generalizes to: tournament selection, beam search, adversarial
co-evolution, curriculum learning, prompt tuning.

### Interface freeze constraint

```
⊨ §cell' has same given/yield signature as «§cell»
```

Liskov substitution for cells. Implementation can change,
interface cannot. Prevents self-modification cascades.

## Self-Crystallization

The metacircular money shot:

```
⊢ crystallize
  given §target, test-cases[]
  yield §target', is-faithful

  ∴ Read «§target». Write ⊢= that replaces ∴.
    Test against «test-cases».

⊢ verify-crystal
  given §target', is-faithful
  yield approved

  ∴ Run §target' on test cases. Check oracles.

  ⊨ if approved and is-faithful then §target' may replace §target
```

**"May replace"** is PERMISSION, not equality. Deontic logic.
The soft cell is the specification. The hard cell is a proven optimization.
Both coexist. The ∴ block is never discarded.

`crystallize` cannot crystallize itself — it is the layer that must
stay warm so others can go cold. The LLM becomes the stem cell of
the system: pluripotent, expensive, rarely activated, essential for growth.

## Bootstrap Sequence

1. Cell syntax defined externally (this document)
2. LLM executes first cells by interpreting ∴ blocks
3. `describe` cell parses Cell syntax (first crystallization candidate)
4. `crystallize` cell writes ⊢= for simple cells
5. `verify-crystal` checks crystallized cells against oracles
6. More cells crystallize → LLM cost drops → system hardens
7. Eventually: mostly hard cells, LLM invoked only at edges

The trajectory: soft everywhere → hard core, soft frontier.

## Oracle Classification (Round 8)

Oracles fall into two categories:

```
⊨ sentiment ∈ {"positive", "negative", "mixed"}   -- ASSERTION (post-hoc check)
⊨ if text has positive ∧ negative → sentiment = "mixed"  -- RULE (prescription)
```

Assertions catch formatting errors (easy to fix by reformatting).
Rules catch reasoning errors (need failure context to fix).
Different retry strategies appropriate for each.

### Conditional oracles with soft preconditions

`if text contains positive and negative language` requires LLM judgment
to evaluate the precondition. The rule LOOKS deterministic but ISN'T.

### Exhaustion handler

```
⊨? on failure:
  retry with «oracle.failures» max 3
⊨? on exhaustion:
  escalate | error-value(⊥) | partial-accept(best)
```

## Frontier Growth: Semantic Automata (Round 8)

Cell programs can grow. Cells spawn new cells that join the frontier.
This is the semantic automata — never-terminating exploration.

```
⊢⊢ spawn                          -- ⊢⊢ marks a spawner (meta-level)
  given explore→follow-ups
  given §explore                   -- template cell
  yield §new-cells[]
  until depth > 5 ∨ follow-ups all empty
```

### Properties under growth

- Monotonicity preserved (values never change, cells only added)
- Confluence preserved relative to a fixed oracle
- Termination NOT guaranteed (by design)
- Halting via `until` on spawners, budget bounds, or external signal

### Crystallization boundary

Any cell that executes §-referenced cells is an interpreter.
The § sigil marks the crystallization boundary.
`dispatch` (executes arbitrary cells) can NEVER crystallize.

## Cell-as-Agent Pattern (Round 8)

```
inbox → §handlers[] (cell definitions)
dispatch → results[] (execute handlers)
act → actions[] (filter needs-action)
```

This is Cell's eval/apply. Code-as-data emerges from § references.
Cell adds over Python: visible contracts, first-class constraints,
explicit dataflow, safe eval/apply, crystallization spectrum.

Missing: streaming (need `~` stream binding), error propagation.

## Open Questions

1. **Error handling**: What happens when ⊢= throws? When ∴ produces wrong type?
2. **Type strictness at LLM boundaries**: yield annotations help but aren't enough
3. **Resource management**: Memory, timeouts, cost budgets
4. **Certificate format schemas**: Proof-carrying needs structured certificates
5. **Versioning beyond prime marks**: §greet''' doesn't scale
6. **Observation/tracing**: Need syntax for "emit intermediate results"
7. **Spawner syntax**: ⊢⊢ for meta-level cells, template instantiation, auto-naming
8. **Streaming**: ~ annotation for incremental input, long-lived cells
9. **Oracle distinction**: assert vs rule, soft vs hard preconditions
10. **Exhaustion semantics**: What happens when ⊨? retries are spent
