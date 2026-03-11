# Cell Language Specification v0.2

*Evolved from v0.1 through empirical testing of 30 programs across 6 categories
(self-evolving, adversarial, recursive decomposition, generative, validation-heavy,
meta/self-referential). Every addition is grounded in specific program evidence.*

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
| `⊥` | bottom | absence of value; blocks downstream [v0.2] |
| `given?` | optional given | dependency that tolerates `⊥` [v0.2] |

## Execution Model: eval-one

Cell uses **Kahn's algorithm**, one step at a time:

1. Find all cells whose `given` inputs are fully bound (`≡` present)
   and whose guard clauses (if any) evaluate to true [v0.2]
2. Pick ONE such cell
3. Evaluate it (interpret `∴` via LLM or evaluate `⊢=` deterministically)
4. Spawn oracle claim cells to verify the tentative output
5. If all claims pass: freeze the output (fill in `yield ≡` values)
6. If any claim fails: retry (rewrite) or produce `⊥` (exhausted)
7. Repeat (the frontier grows monotonically -- programs don't terminate)

### Properties (proven in Lean)

- **Document-is-state**: The program text IS the execution state.
  Each step changes exactly one `yield` line to include `≡ value`.
- **Monotonicity**: Yields only get bound, never unbound.
  The frozen set only grows. Past is immutable.
- **Non-termination**: Cell programs do not terminate by design.
  Spawners grow the frontier. Termination is the caller's problem.
  See `cell-computational-model.md` for the full justification.
- **Confluence**: Execution order of independent cells doesn't matter.
  Same final result regardless of scheduling. Parallel execution valid.
  (Proven: `eval_diamond` theorem in `Confluence.lean`.)
- **Content addressing**: Hash the document = hash the state.
  Each eval-one step = hash transition (h0 -> h1 -> h2 -> ...).
- **Fusion**: Cell requires both classical and semantic substrates.
  Deterministic cells (`⊢=`) run classically. Soft cells (`∴`) need LLM.
  Oracle checking spans both. See `cell-computational-model.md`.

### Example Trace

```
State h0:                         State h1 (after eval-one):
⊢ add                            ⊢ add
  given a ≡ 3                      given a ≡ 3
  given b ≡ 5                      given b ≡ 5
  yield sum          <-changed->   yield sum ≡ 8
  ...                              ...

⊢ double                         ⊢ double
  given add→sum                    given add→sum     <- now resolvable
  yield result                     yield result
  ...                              ...
```

## Wildcard Dependencies [v0.2]

Collect outputs from dynamically spawned cells using glob patterns.

**Motivated by**: Programs 1, 4, 8, 11, 12, 14, 15, 18, 22, 29 all
independently converged on `cell-*→field` notation. This is the most
common dependency pattern after direct `cell→field` (23% of all programs).

### Syntax

```
given <pattern>→<field>
```

where `<pattern>` uses `*` as a wildcard matching any suffix.

### Semantics

- The wildcard resolves against all cells in the current graph whose
  names match the pattern.
- The cell becomes ready when ALL matching cells have frozen the
  referenced field.
- Collected values form an ordered array (by spawn order).
- If no cells match, the result is an empty array `[]`.

### Examples

```
⊢ collect-results
  given experiment-*→result         -- array of all experiment outputs
  given experiment-*→verdict        -- array of all verdicts
  yield summary

  ∴ Summarize the «experiment-*→result» across all experiments.
```

```
⊢ security-report
  given regression-test-*→passes    -- accumulates as spawner fires
  given regression-test-*→explanation
  yield report
```

### Interaction with `⊢⊢` spawners

When a `⊢⊢` spawner creates cells named `task-0`, `task-1`, ...,
the pattern `task-*→output` resolves to all of them. Under `⊢∘`
evolution loops, the match set may change between iterations as new
cells are spawned. The wildcard re-resolves at each ready-set computation.

**Accumulation vs replacement**: By default, spawned cells accumulate
across `⊢∘` iterations (programs 4, 8, 10). A spawner may specify
`replace` to discard previous spawned cells on re-fire (program 1).
If unspecified, the default is `accumulate`.

## Guard Clauses: Conditional Dispatch [v0.2]

Cells can declare guards that must evaluate to true (on frozen values)
before the cell enters the ready set.

**Motivated by**: Program 30 demonstrated the "N/A hack" anti-pattern:
without guards, all branches of a classification must execute, with
irrelevant branches producing useless output. Zero of 30 programs
found a clean workaround.

### Syntax

```
given <cell>→<field> where <condition>
```

The `where` clause is a deterministic expression (same language as `⊢=`)
evaluated against frozen concrete values. No LLM needed.

### Semantics

- When all `given` inputs are frozen, the guard expressions are evaluated.
- If ALL guards are true: the cell enters the ready set normally.
- If ANY guard is false: the cell is **skipped**. Its yields are never
  bound. Downstream cells that depend on a skipped cell's outputs receive
  `⊥` (see "Bottom Propagation" below).

### Example

```
⊢ classify
  given text
  yield label
  ∴ Classify «text» as "toxic", "borderline", or "clean".

⊢ handle-toxic
  given classify→label where label = "toxic"
  given text
  yield response
  ∴ Generate a firm but polite refusal for «text».

⊢ handle-borderline
  given classify→label where label = "borderline"
  given text
  yield response
  ∴ Flag «text» for human review, provide context.

⊢ handle-clean
  given classify→label where label = "clean"
  given text
  yield response
  ∴ Respond helpfully to «text».
```

Only ONE handler executes. The others are skipped. No wasted LLM calls.

### Guard expression constraints

Guards must be deterministic -- they compare frozen values using the
`⊢=` expression language. No LLM evaluation. No side effects. This
preserves confluence: the guard outcome is determined by the frozen
input values, which are immutable.

## Bottom Propagation: `⊥` as First-Class Value [v0.2]

**Motivated by**: Program 13 (progressive-summarization) is the only
program that used `⊥` as a genuine stop signal. Only 3% of programs
used `⊥` at all, suggesting severe underspecification.

### Definition

`⊥` (bottom) is a first-class value that any cell may yield for any field.
It represents the absence of a meaningful value -- not an error, but a
deliberate signal that "this question has no answer."

### Propagation rules

1. **Blocking**: A cell with `given cell→field` where `field ≡ ⊥` is
   **blocked permanently**. The dependency exists but will never be
   satisfied. The downstream cell never enters the ready set.

2. **Optional given**: A cell with `given? cell→field` accepts `⊥` as
   a concrete value. The `∴` body can inspect it and decide how to proceed.

3. **Guard-induced bottom**: When a guard clause evaluates to false,
   the skipped cell's yields are all `⊥`. This connects guard clauses
   to downstream dataflow cleanly.

4. **Oracle exhaustion**: When `⊨?` retries are exhausted and the policy
   is `error-value(⊥)`, all yields of the failed cell become `⊥`.

### Examples

```
-- ⊥ as stop signal (program 13 pattern)
⊢ compress
  given text
  yield next-summary, halted

  ∴ Compress «text» to half its length.
     If compression would lose critical meaning, yield ⊥ for next-summary.

⊢⊢ recurse-compression
  given compress→next-summary              -- blocks if ⊥
  given compress→halted
  ...

-- ⊥-aware cell using given?
⊢ report
  given? compress→next-summary             -- accepts ⊥
  given compress→halted
  yield final-summary

  ∴ If «compress→next-summary» is ⊥, use the previous level's summary.
     Otherwise, use «compress→next-summary».
```

## Quotation: `§`

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
| sort (computation) | Hard -- many valid algorithms | LLM chooses approach |
| verify-sort (verification) | Easy -- one correct behavior | Just check properties |
| crystallize (code generation) | Never -- permanently soft | Generates code from NL |
| eval-one (interpreter) | Never -- permanently soft | Executes arbitrary ∴ |
| is-done (structural check) | Trivially | Pure syntax scan |
| hash (content hash) | Trivially | Pure computation |

### Oracles on crystallized vs soft cells

On soft cells: `⊨` is a **guardrail** (checked at runtime, may fail).
On crystallized cells: `⊨` is a **contract** (verified at compile/test time).
Same syntax, different trust level.

## The `⊢=` Expression Language [v0.2]

**Motivated by**: Programs 27 and 28 exhibited false crystallization --
`⊢=` bodies containing semantic judgments masquerading as deterministic
expressions. Programs 19, 23, 24, 25 used undefined functions like
`proof-covers()`, `collect()`, `missing-from()`. Without a defined
expression language, the soft/hard boundary -- Cell's fundamental
invariant -- is meaningless.

### Valid `⊢=` primitives

A `⊢=` body must be composed entirely from these categories:

**Arithmetic**: `+`, `-`, `*`, `/`, `%` (modulo)

**Comparison**: `=`, `!=`, `<`, `>`, `<=`, `>=`

**Boolean**: `and`, `or`, `not`, `true`, `false`

**String operations**: `split(s, delim)`, `join(list, delim)`,
`contains(s, substr)`, `starts-with(s, prefix)`, `ends-with(s, suffix)`,
`length(s)` (string length), `trim(s)`, `upper(s)`, `lower(s)`,
`matches(s, pattern)` (regex match)

**List operations**: `len(list)`, `sort(list)`, `sort(list, key)`,
`take(list, n)`, `drop(list, n)`, `filter(list, predicate)`,
`map(list, fn)`, `concat(list-a, list-b)`, `flatten(list-of-lists)`,
`zip(list-a, list-b)`, `any(list, predicate)`, `all(list, predicate)`,
`count(list, predicate)`, `min(list)`, `max(list)`, `sum(list)`

**Access**: `x→field` (field access), `list[i]` (index access)

**Binding**: `name <- expression` (assign result)

**Conditional**: `if cond then expr-a else expr-b`

### The crystallization boundary rule

If an expression requires subjective judgment, interpretation, or
world knowledge to evaluate, it is NOT a valid `⊢=` expression. It
belongs in a `∴` body. Specifically:

- `⊢= len(items) > 3` -- VALID (deterministic)
- `⊢= sort(scores, descending).take(3)` -- VALID (deterministic)
- `⊢= summary addresses the same question` -- INVALID (semantic judgment)
- `⊢= proof-covers(sketch, properties)` -- INVALID (undefined function requiring interpretation)

Programs 27 and 28 would need to either (a) rewrite their pseudo-code
helpers as separate `⊢=` cells using only the primitives above, or
(b) honestly mark those cells as soft (`∴`).

## Oracle System

### Oracles are cells

Every `⊨` assertion is syntactic sugar for a **claim cell** that
cell-zero spawns after evaluation. The claim cell checks the oracle
against the tentative output. This means oracles participate in the
same graph mechanics as everything else -- no special oracle machinery.

### Oracle types

```
⊨ result = 55                    -- deterministic (exact value check)
⊨ sorted is a permutation        -- structural (checkable by code)
⊨ summary is 2-3 sentences       -- semantic (requires LLM judgment)
⊨ reversed read backwards = text -- ambiguous (needs interpretation commitment)
```

### Conditional oracles [v0.2]

**Motivated by**: Programs 21 and 30 use `if...then` oracle predicates.
Program 21's `diff` cell has four conditional oracles with overlapping
cases. The spec was silent on how conditional oracles interact.

```
⊨ if drift-score <= 1 then acceptable = true
⊨ if text has positive ∧ negative → sentiment = "mixed"
```

When the precondition of a conditional oracle evaluates to **false**,
the oracle is **vacuously satisfied** (skipped, not failed). This is
standard logical convention: `false → P` is true for any P.

### Oracle failure recovery (`⊨?`)

```
⊨? on failure:
  retry with «oracle.failures» appended to prompt
  max 3 attempts
```

`⊨?` is a meta-oracle -- policy about what to do when `⊨` fails.
Key insight: retry WITH FEEDBACK, not blind retry.

Retry is a graph rewrite: cell-zero drops the failed claim cells,
rewrites the original cell (with failure context), and re-evaluates.
The tentative output lives in the claim cells, NOT in the original
cell's state. The original remains unfrozen until oracles pass.
This is why retry doesn't violate immutability.

### `⊨?` scope [v0.2]

**Motivated by**: Programs 2, 19, 24, 28 placed `⊨?` at file scope
(not inside any cell). The spec only showed `⊨?` inside cell bodies.

- `⊨?` **inside a cell**: applies to that cell's oracles only.
- `⊨?` **at file scope**: applies as the default recovery policy for
  ALL cells in the file that do not declare their own `⊨?`.

### Exhaustion handler

```
⊨? on failure:
  retry with «oracle.failures» max 3
⊨? on exhaustion:
  escalate | error-value(⊥) | partial-accept(best)
```

### Oracle promotion

When an oracle like `⊨ n = len(tokens)` literally states the
implementation, the runtime can crystallize automatically.
The oracle IS the implementation.

## Oracle Classification (Round 8)

Oracles fall into two categories:

```
⊨ sentiment ∈ {"positive", "negative", "mixed"}   -- ASSERTION (post-hoc check)
⊨ if text has positive ∧ negative → sentiment = "mixed"  -- RULE (prescription)
```

Assertions catch formatting errors (easy to fix by reformatting).
Rules catch reasoning errors (need failure context to fix).
Different retry strategies appropriate for each.

### Exhaustion handler

```
⊨? on failure:
  retry with «oracle.failures» max 3
⊨? on exhaustion:
  escalate | error-value(⊥) | partial-accept(best)
```

**`partial-accept` with predicates** [v0.2]: The exhaustion handler
may include a predicate to select which partial result to accept:

```
⊨? on exhaustion:
  partial-accept(best where semantics-preserved = true)
```

**Motivated by**: Program 27 used `partial-accept(best where
semantics-preserved = true)` to filter acceptable partial results.

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
  ⊢= holds <- eval(lhs, x) == eval(rhs, x)  -- plug and check
```

The LLM operates in "NP space" (find a solution).
The crystallized verifier operates in "P space" (check the solution).
The verifier ALWAYS catches wrong answers.

## Frontier Growth: Semantic Automata (Round 8)

Cell programs can grow. Cells spawn new cells that join the frontier.
This is the semantic automata -- never-terminating exploration.

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

## Evolution Loops: `⊢∘`

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

### `⊢∘` naming convention [v0.2]

**Motivated by**: Programs used inconsistent naming -- `evolve` (1, 4, 8),
`harden` (6), `debate` (7), `teach` (10), `refine` (20, 21, 23),
`fact-check-loop` (22), `optimize` (27), `evolve-spec` (30). The spec
showed only `evolve`.

The identifier after `⊢∘` is an **arbitrary label** used for
documentation and debugging. It has no semantic effect. Parsing rule:

```
⊢∘ <label>(<target-cell>, <arg-bindings>...)
  through <cell>, <cell>, ...
  until <condition>
  max <N>
```

The label is NOT a function name. Examples:

```
⊢∘ harden(oracle-spec)             -- valid: label is "harden"
⊢∘ teach(ask)                      -- valid: label is "teach"
⊢∘ refine(draft-dsl)               -- valid: label is "refine"
⊢∘ evolve(summarize, input ≡ data) -- valid: with extra binding
```

### Multi-target `⊢∘` semantics [v0.2]

**Motivated by**: Program 7 used `debate(argue-for, argue-against)` with
two target cells. Program 9 used four parallel `⊢∘` loops sharing one
mediator. The spec only showed single-target evolution.

**Rule**: Each `⊢∘` declaration targets a **single cell**. Multiple
evolution targets require multiple `⊢∘` declarations.

**Shared cells**: Multiple `⊢∘` loops MAY share `through` and `until`
cells. Shared cells are re-evaluated on each iteration of ANY loop that
references them. This enables the mediator pattern (program 9) where
N perspectives evolve independently through a shared judge.

**Example** (program 9 pattern):

```
⊢∘ evolve(perspective-cto, question→text)
  through mediate, revise-cto
  until mediate→consensus-score ≥ 8
  max 5

⊢∘ evolve(perspective-senior, question→text)
  through mediate, revise-senior
  until mediate→consensus-score ≥ 8
  max 5
```

Both loops share `mediate`. When either loop iterates, `mediate` is
re-evaluated with all current perspective outputs.

### `⊢∘` with parameter bindings [v0.2]

**Motivated by**: Programs 12, 15, 17, 18, 29 pass extra arguments
to the evolution combinator beyond the target cell.

Extra arguments after the target cell are **fixed bindings** that
persist across all iterations. They provide stable context that the
target cell's `given` clauses reference:

```
⊢∘ evolve(extract-implicit, request→text, extract-explicit→requirements)
  through collect-requirements, refine-vague
  until completeness ≥ 9
  max 3
```

Here `request→text` and `extract-explicit→requirements` are frozen
values forwarded to `extract-implicit` on every iteration.

### Interface freeze constraint

```
⊨ §cell' has same given/yield signature as «§cell»
```

Liskov substitution for cells. Implementation can change,
interface cannot. Prevents self-modification cascades.

### Oracles on `⊢∘`-managed cells [v0.2]

**Motivated by**: Program 2's `summarize` cell has oracles that fail
in iteration 0 but the cell is frozen anyway because `⊢∘` drives
the improvement cycle.

When a cell is managed by `⊢∘`, its own `⊨` assertions are
**aspirational** -- they describe the target quality, not a hard gate.
The `⊢∘` loop's `until` condition is the actual convergence criterion.
The cell's oracles serve as feedback signals (their failure messages
feed into the `through` chain) but do not independently block freezing.

## Co-evolution: `⊢∘ co-evolve` [v0.2]

**Motivated by**: Program 17 (collaborative-world-builder) has circular
dependencies -- geography, history, and culture each reference the
others' outputs. This is a cycle that Kahn's algorithm cannot resolve.
The co-evolution pattern is legitimate but was unsupported by v0.1.

### Syntax

```
⊢∘ co-evolve(cell-a, cell-b, cell-c)
  through <validator-cells>
  until <condition>
  max <N>
```

### Semantics

1. **Iteration 0**: All cells in the co-evolve set are evaluated with
   `⊥` substituted for unavailable peer inputs. Each cell produces a
   tentative output based on whatever information it has.

2. **Iteration 1+**: All cells are re-evaluated with peer outputs from
   the previous iteration now available. Cross-references resolve to
   the latest frozen values.

3. **Convergence**: The `through` chain (typically a consistency checker)
   evaluates after each round. The `until` condition gates termination.

4. **Monotonicity preserved**: Each iteration adds information (replaces
   `⊥` with values, then refines values). No iteration removes information.

### Example (program 17 pattern)

```
⊢ geography
  given seed→premise
  given? history→backstory          -- given? tolerates ⊥ on iteration 0
  given? culture→customs
  yield layout, distances, sectors
  ∴ Design the station geography. If «history→backstory» available, respect it.

⊢ history
  given seed→premise
  given? geography→layout
  given? culture→customs
  yield backstory, timeline, factions
  ∴ Write station history. If «geography→layout» available, be consistent.

⊢ culture
  given seed→premise
  given? geography→sectors
  given? history→factions
  yield customs, languages, traditions
  ∴ Design cultures. If «geography→sectors» and «history→factions» known, align.

⊢∘ co-evolve(geography, history, culture)
  through check-consistency, resolve-contradictions
  until check-consistency→consistent = true
  max 3
```

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

`crystallize` cannot crystallize itself -- it is the layer that must
stay warm so others can go cold. The LLM becomes the stem cell of
the system: pluripotent, expensive, rarely activated, essential for growth.

## Bootstrap Sequence

1. Cell syntax defined externally (this document)
2. LLM executes first cells by interpreting ∴ blocks
3. `describe` cell parses Cell syntax (first crystallization candidate)
4. `crystallize` cell writes ⊢= for simple cells
5. `verify-crystal` checks crystallized cells against oracles
6. More cells crystallize -> LLM cost drops -> system hardens
7. Eventually: mostly hard cells, LLM invoked only at edges

The trajectory: soft everywhere -> hard core, soft frontier.

## Cell-as-Agent Pattern (Round 8)

```
inbox -> §handlers[] (cell definitions)
dispatch -> results[] (execute handlers)
act -> actions[] (filter needs-action)
```

This is Cell's eval/apply. Code-as-data emerges from § references.
Cell adds over Python: visible contracts, first-class constraints,
explicit dataflow, safe eval/apply, crystallization spectrum.

## Open Questions

1. **Type strictness at LLM boundaries**: yield annotations help but aren't enough
2. **Resource management**: Memory, timeouts, cost budgets
3. **Certificate format schemas**: Proof-carrying needs structured certificates
4. **Versioning beyond prime marks**: §greet''' doesn't scale
5. **Observation/tracing**: Need syntax for "emit intermediate results"
6. **Spawner syntax refinements**: ⊢⊢ template instantiation, auto-naming conventions
7. **Streaming**: ~ annotation for incremental input, long-lived cells
8. **Spawner output grouping**: When ⊢⊢ spawns hierarchically (scenes -> beats),
   how do beats associate with their parent scene? (program 18)
9. **Nested § quotation depth**: When §program contains cells that themselves
   use §, how deep does quotation nest? (program 5)
10. **Module/namespace system**: `§cell-zero.read-graph` implies dot-notation
    for qualified cell references (program 26)

---

## Migration from v0.1

### Summary of changes

All v0.1 syntax remains valid. v0.2 is a strict superset.

| Feature | Status | Motivation |
|---------|--------|------------|
| Wildcard dependencies (`given cell-*→field`) | **NEW** | Programs 1, 4, 8, 11, 12, 14, 15, 18, 22, 29 |
| Guard clauses (`given x where condition`) | **NEW** | Program 30 (N/A hack anti-pattern) |
| `⊢=` expression language (defined primitives) | **NEW** | Programs 27, 28 (false crystallization) |
| `⊥` as first-class value | **CLARIFIED** | Program 13 (only user of ⊥) |
| `given?` optional dependency | **NEW** | Programs 13, 17 (⊥-aware cells) |
| `⊢∘` naming convention | **CLARIFIED** | Programs 6, 7, 10, 20, 21, 22, 27, 30 |
| `⊢∘` multi-target semantics | **CLARIFIED** | Programs 7, 9 |
| `⊢∘` parameter bindings | **CLARIFIED** | Programs 12, 15, 17, 18, 29 |
| `⊢∘ co-evolve` | **NEW** | Program 17 (circular dependencies) |
| Conditional oracle semantics | **CLARIFIED** | Programs 21, 30 |
| `⊨?` file-scope rules | **CLARIFIED** | Programs 2, 19, 24, 28 |
| `partial-accept` with predicates | **CLARIFIED** | Program 27 |
| Oracles on `⊢∘`-managed cells | **CLARIFIED** | Program 2 |
| Spawner accumulate vs replace | **CLARIFIED** | Programs 1, 4, 8, 10 |

### What existing programs need to change

**Nothing breaks.** All 30 R16 programs remain valid (or become more
precisely valid) under v0.2. Specific improvements:

- Programs using `cell-*→field` (7 programs): now spec-compliant
- Programs using custom `⊢∘` verbs (13 programs): now explicitly blessed
- Program 17: can use `⊢∘ co-evolve` instead of illegal circular deps
- Programs 27, 28: should audit `⊢=` bodies against the expression
  language and re-mark semantic pseudo-code as `∴` (soft)
- Program 30: can rewrite the awkward-program fragment using guard clauses

### Feature frequency across R16 corpus

```
⊢  (soft cell)         100%  -- universal
«» (interpolation)     100%  -- universal
≡  (binding)           100%  -- universal
→  (output access)     100%  -- universal
⊨  (oracle)            100%  -- universal
⊢∘ (evolution loop)     77%  -- dominant control flow
⊢= (hard cell)          73%  -- heavily used in validation programs
§  (quotation)           70%  -- essential for self-modification patterns
⊢⊢ (spawner)             50%  -- half the corpus uses dynamic frontier growth
⊨? (recovery)            47%  -- underused relative to its importance
cell-*→field (wildcard)  23%  -- NEW IN v0.2, previously unspecified
▸  (refinement stage)    20%  -- niche, used with ⊢= crystallized cells
⊥  (bottom)               3%  -- should increase with v0.2 propagation rules
```
