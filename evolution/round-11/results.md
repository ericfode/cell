# Round 11 Results: Evolution-Spawner

## Mode: COLD READ (no syntax reference)

## The Program

An evolution loop that spawns judge cells, aggregates their scores, and
iteratively rewrites a greeting cell until quality meets threshold. Six cells
in total: **greeting-v0** → **evaluate** (spawner) → **aggregate** →
**evolve** (loop controller) → **improve** → **final-output**.

```
greeting-v0 ──→ evaluate (⊢⊢ spawns 3 judges)
                    │
                    ▼
               aggregate ──→ evolve (⊢∘ loop)
                    ▲              │
                    │              ▼
                    └─────── improve
                                  │
                                  ▼
                            final-output
```

---

## Evaluation Questions

### 1. Execute the program step-by-step. Show all intermediate states.

**Step 1: greeting-v0 (⊢ — soft cell)**

```
Input:  name = (not yet bound — this is a template)
Output: message

∴ body: "Write a warm, professional greeting for «name»."
```

This cell is NOT executed directly at the top level. It's a cell *definition* —
a template. The `⊢` marker with no upstream `given step→field` data flow means
it's a standalone cell that can be instantiated later. The `⊢⊢ evaluate` cell
and `⊢∘ evolve` cell both reference it as `§greeting-v0` — the `§` sigil
indicates a cell reference (the cell itself, not its output).

**Key cold-read inference**: `§` means "the cell as a value." This is
metaprogramming — cells can receive other cells as inputs and instantiate them.

**Step 2: evaluate (⊢⊢ — spawner cell)**

```
Input:  §greeting-v0 (the cell definition)
        test-name ≡ "Alice" (literal binding)
Output: §judges[] (array of spawned judge cells)
Termination: until all criteria processed, max 5
```

The `⊢⊢` sigil is new. On cold read, the double-turnstile suggests "meta-level
assertion" or "spawning" — creating cells rather than computing values. The `∴`
body instructs:

1. Create 3 judge cells, each evaluating greeting-v0 on a different criterion:
   - Judge 1: Warmth
   - Judge 2: Professionalism
   - Judge 3: Personalization
2. Each judge instantiates `§greeting-v0` with `name ≡ "Alice"` (the test-name)
3. Each judge executes the greeting cell
4. Each judge yields: `score` (1-10), `feedback` (text)

**Execution trace:**

```
evaluate:
  Receives §greeting-v0 (cell template), test-name = "Alice"

  Spawns Judge 1 (Warmth):
    Instantiates greeting-v0 with name ≡ "Alice"
    Executes greeting-v0 → message = "Hello Alice, it's wonderful to connect
      with you today. I hope this message finds you well."
    Evaluates warmth of message → score = 6, feedback = "Polite but generic.
      'Wonderful to connect' feels formulaic rather than genuinely warm."

  Spawns Judge 2 (Professionalism):
    Instantiates greeting-v0 with name ≡ "Alice" (same cell, fresh execution)
    Executes greeting-v0 → message = (same or different LLM output)
    Evaluates professionalism → score = 8, feedback = "Appropriate tone and
      length for a business context. No informalities."

  Spawns Judge 3 (Personalization):
    Instantiates greeting-v0 with name ≡ "Alice"
    Executes greeting-v0 → message = (same or different LLM output)
    Evaluates personalization → score = 5, feedback = "Name appears but feels
      inserted mechanically. 'Hello Alice' is a slot-fill, not natural usage."

  Oracles checked:
    ⊨ §judges[] has exactly 3 items → PASS (3 judges created)
    ⊨ each judge yields score, feedback → PASS (all 3 produce both fields)

  Output: §judges[] = [
    {criterion: "warmth", score: 6, feedback: "..."},
    {criterion: "professionalism", score: 8, feedback: "..."},
    {criterion: "personalization", score: 5, feedback: "..."}
  ]
```

**Critical ambiguity**: Does each judge get its own independent execution of
greeting-v0, or do they all evaluate the SAME execution? The program says "each
judge instantiates" — suggesting independent executions. But greeting-v0 is an
LLM call, so three independent instantiations could produce three different
greetings. The judges would then be scoring different messages, which defeats
the purpose of multi-criterion evaluation. A runtime would likely want to
execute greeting-v0 ONCE and share the result, but the program text says
"instantiates" (plural, per-judge).

**Step 3: aggregate (⊢ — soft cell)**

```
Input:  evaluate→§judges (the array of judge results)
Output: quality, avg-score, feedback-summary
```

This cell has `⊢=` annotations inside it — crystallized sub-computations:

```
aggregate:
  Receives §judges = [{score: 6, ...}, {score: 8, ...}, {score: 5, ...}]

  ⊢= avg-score ← sum(judges.score) / length(judges)
     = (6 + 8 + 5) / 3 = 6.33

  ⊢= quality ← if avg-score ≥ 7 then "good" else "needs-improvement"
     = "needs-improvement" (6.33 < 7)

  ∴ body: Combine all feedback into feedback-summary
  → feedback-summary = "Warmth (6/10): Polite but generic — 'wonderful to
     connect' feels formulaic. Professionalism (8/10): Appropriate tone.
     Personalization (5/10): Name appears mechanically — 'Hello Alice' is a
     slot-fill."

  Oracles checked:
    ⊨ quality ∈ {"good", "needs-improvement"} → PASS
    ⊨ feedback-summary mentions each judge's feedback → PASS

  Output: quality = "needs-improvement", avg-score = 6.33,
          feedback-summary = "..."
```

**Interesting**: This cell mixes `⊢=` (crystallized/deterministic) and `∴`
(oracle/LLM). The `avg-score` and `quality` computations are pure arithmetic —
no LLM needed. But combining feedback into a summary IS an LLM task (it requires
natural language synthesis). So aggregate is a hybrid cell: partially crystallized,
partially soft.

**Step 4: evolve (⊢∘ — loop cell)**

```
⊢∘ evolve(greeting-v0, name ≡ "Alice")
  through aggregate, improve
  until aggregate→quality = "good"
  max 3
```

The `⊢∘` sigil denotes iteration. Cold-read interpretation: "evolve greeting-v0
by cycling through aggregate and improve until quality is good, up to 3
iterations."

This is the control flow hub. It orchestrates the loop:

```
Iteration 1:
  1. Execute evaluate(§greeting-v0, test-name="Alice") → §judges[]
  2. Execute aggregate(§judges) → quality="needs-improvement", avg-score=6.33
  3. Check termination: quality = "good"? NO
  4. Execute improve(§greeting-v0, feedback-summary, quality)
     → §greeting-v0' (rewritten cell)
  5. Replace greeting-v0 with greeting-v0' for next iteration

Iteration 2:
  1. Execute evaluate(§greeting-v0', test-name="Alice") → §judges[]
  2. Execute aggregate(§judges) → quality=?, avg-score=?
     Suppose: warmth=8, professionalism=8, personalization=7 → avg=7.67
     quality = "good"
  3. Check termination: quality = "good"? YES → EXIT LOOP
```

**Step 5: improve (⊢ — soft cell)**

```
Input:  §greeting-v0 (current cell definition)
        aggregate→feedback-summary
        aggregate→quality
Output: §greeting-v0' (rewritten cell definition)
```

This is where the metaprogramming happens. The improve cell receives a CELL
DEFINITION and REWRITES it:

```
improve (iteration 1):
  Receives:
    §greeting-v0 = the cell whose ∴ body is
      "Write a warm, professional greeting for «name»."
    feedback-summary = "Warmth: generic. Personalization: mechanical."
    quality = "needs-improvement"

  ∴ body: Read feedback-summary. Rewrite the ∴ body of §greeting-v0 to
    address the feedback. Preserve the given/yield/⊨ signature.

  LLM rewrites the ∴ body:
    Old: "Write a warm, professional greeting for «name»."
    New: "Write a greeting for «name» that feels personally crafted —
      use their name mid-sentence rather than as a formulaic opener,
      and express genuine warmth through specific well-wishes rather
      than stock phrases."

  Oracles checked:
    ⊨ §greeting-v0' has same given/yield signature as §greeting-v0
      → given: name. yield: message. PASS (unchanged)
    ⊨ §greeting-v0' preserves all ⊨ constraints from §greeting-v0
      → ⊨ message mentions «name»: preserved ✓
      → ⊨ message is 1-2 sentences: preserved ✓
      → ⊨ message has warm but professional tone: preserved ✓
      → PASS

  Output: §greeting-v0' (rewritten cell with improved ∴ body)
```

The "Liskov substitution for cells" comment in the program is precise: the
improved cell must be a drop-in replacement. Same interface, different
implementation. The `⊨` constraints serve as the behavioral contract.

**Step 6: final-output (⊢ — soft cell)**

```
Input:  evolve→§greeting-v0' (the evolved cell definition)
        aggregate→avg-score (from the last iteration)
Output: result, evolution-rounds
```

```
final-output:
  Receives §greeting-v0' (the improved cell after evolution)
  Receives avg-score (from last iteration, e.g. 7.67)

  Instantiates §greeting-v0' with name ≡ "Bob"
  Executes it → message = "I'm so glad to have the chance to work with
    you, Bob — wishing you a truly great start to the week."

  Oracles checked:
    ⊨ result is a greeting that mentions "Bob" → PASS
    ⊨ evolution-rounds ≤ 3 → PASS (2 rounds)

  Output: result = "I'm so glad to have the chance to work with you,
    Bob — wishing you a truly great start to the week."
    evolution-rounds = 2
```

**Full execution summary:**

| Step | Cell | Type | LLM Calls | Output |
|------|------|------|-----------|--------|
| 1 | greeting-v0 | template | 0 (not directly executed) | — |
| 2 | evaluate | ⊢⊢ spawner | 3 (judges) + 3 (greeting instances) = 6 | §judges[] |
| 3 | aggregate | ⊢ hybrid | 1 (feedback synthesis) | quality, avg-score, summary |
| 4 | evolve | ⊢∘ loop | 0 (controller) | orchestrates iterations |
| 5 | improve | ⊢ soft | 1 (rewrite ∴ body) | §greeting-v0' |
| — | (iteration 2) | | | |
| 6 | evaluate (round 2) | ⊢⊢ | 6 | §judges[] |
| 7 | aggregate (round 2) | ⊢ | 1 | quality="good" |
| 8 | improve (round 2) | ⊢ | 0 (quality="good" → return unchanged) | §greeting-v0' |
| 9 | final-output | ⊢ | 1 (instantiate with "Bob") | result, evolution-rounds |

**Total LLM calls (2-iteration run): 16**

---

### 2. Which cells crystallize? Which must stay soft? Why?

**Crystallized (⊢=):**

- **avg-score computation** (inside aggregate): Pure arithmetic —
  `sum(scores) / length(scores)`. No LLM needed. The `⊢=` is inline within a
  `⊢` cell, marking a sub-expression as deterministic.
- **quality computation** (inside aggregate): A conditional —
  `if avg-score ≥ 7 then "good" else "needs-improvement"`. Pure logic.

These MUST crystallize because their correctness is trivially verifiable and
LLM involvement would introduce unnecessary variance. Arithmetic doesn't
benefit from "creativity."

**Must stay soft (⊢):**

- **greeting-v0**: The entire point is LLM-generated natural language. A
  crystallized greeting is a static string — it can't adapt to different names
  or incorporate feedback.
- **evaluate/judge cells**: Evaluating "warmth" or "personalization" requires
  judgment. No deterministic function can score these criteria.
- **aggregate (∴ body)**: Synthesizing feedback from multiple judges into a
  coherent summary is a natural language task.
- **improve**: Rewriting a cell's ∴ body to address feedback is the most
  creative task in the pipeline — pure metaprogramming via LLM.
- **final-output**: Instantiating the evolved greeting with a new name requires
  LLM execution.

**The evolve controller (⊢∘)** is interesting — it's neither crystallized nor
soft in the usual sense. It's a control flow primitive. The `until` and `max`
clauses make it deterministic in structure (it's a bounded while-loop), but it
orchestrates soft cells. The loop itself is mechanical; its body is not.

**Cannot crystallize (fundamental limit):**

The improve cell is the hardest to crystallize because it performs
*code generation* — rewriting the ∴ body of another cell. This is inherently
open-ended. You could imagine crystallizing the "check if quality is good →
return unchanged" branch, but the rewrite branch requires LLM creativity.

The judges are the second hardest. "Is this greeting warm?" is a
quintessentially soft question. You could build a rubric-based scoring system
(check for exclamation marks, positive adjectives, etc.), but that defeats the
purpose of using LLM judgment.

---

### 3. Trace every oracle check. Show PASS/FAIL with reasoning.

**Notation**: `[CELL] ⊨ constraint → RESULT (reasoning)`

**Iteration 1:**

```
[evaluate] ⊨ §judges[] has exactly 3 items
  → PASS (spawned exactly 3 judges: warmth, professionalism, personalization)

[evaluate] ⊨ each judge yields score, feedback
  → PASS (each judge produced both fields)

[aggregate] ⊨ quality ∈ {"good", "needs-improvement"}
  → PASS ("needs-improvement" is in the set)

[aggregate] ⊨ feedback-summary mentions each judge's feedback
  → PASS (summary includes warmth, professionalism, and personalization
    feedback — this is checked by the runtime, not the LLM, so it's a
    substring/semantic check)

[improve] ⊨ §greeting-v0' has same given/yield signature as §greeting-v0
  → PASS (given: name, yield: message — unchanged)

[improve] ⊨ §greeting-v0' preserves all ⊨ constraints from §greeting-v0
  → PASS (all three constraints retained verbatim in the rewritten cell)
```

**Iteration 2:**

```
[evaluate] ⊨ §judges[] has exactly 3 items → PASS (same structure)

[evaluate] ⊨ each judge yields score, feedback → PASS

[aggregate] ⊨ quality ∈ {"good", "needs-improvement"}
  → PASS ("good" is in the set)

[aggregate] ⊨ feedback-summary mentions each judge's feedback → PASS

[improve] ⊨ §greeting-v0' has same given/yield signature
  → PASS (quality="good" → cell returned unchanged, signature trivially same)

[improve] ⊨ §greeting-v0' preserves all ⊨ constraints → PASS (unchanged)
```

**Final:**

```
[final-output] ⊨ result is a greeting that mentions "Bob"
  → PASS (greeting contains "Bob")

[final-output] ⊨ evolution-rounds ≤ 3
  → PASS (2 rounds, within max of 3)
```

**Oracle check summary:**

| Iteration | Cell | Checks | All Pass? |
|-----------|------|--------|-----------|
| 1 | evaluate | 2 | Yes |
| 1 | aggregate | 2 | Yes |
| 1 | improve | 2 | Yes |
| 2 | evaluate | 2 | Yes |
| 2 | aggregate | 2 | Yes |
| 2 | improve | 2 | Yes |
| final | final-output | 2 | Yes |
| **Total** | | **14** | **Yes** |

**No FAIL cases shown** because the program has no `⊨?` recovery clauses. Every
oracle is a plain `⊨` — if any fails, the behavior is undefined (no retry, no
⊥ emission, no skip). The program assumes all oracle checks pass. This is a
significant gap: what happens when improve produces a §greeting-v0' that
doesn't preserve the signature? The program has no error handling for oracle
failure.

**The missing ⊨? clauses**: Compare this to the Round 10 programs, which had
explicit `⊨? on failure: retry max N` and `on exhaustion: error-value(⊥)`.
This program has none of that machinery. Every oracle is an assertion, not a
recoverable check. This makes the program simpler but more fragile.

---

### 4. What's the minimum number of LLM calls needed? Which cells are LLM-free?

**Best case: quality="good" on iteration 1 (1 loop cycle):**

| Cell | LLM Calls | Notes |
|------|-----------|-------|
| greeting-v0 (template) | 0 | Definition only, not executed |
| evaluate | 6 | 3 greeting instances + 3 judge evaluations |
| aggregate | 1 | Feedback synthesis (⊢= parts are free) |
| improve | 0 | quality="good" → return unchanged (no rewrite) |
| final-output | 1 | Instantiate greeting with "Bob" |
| **Total** | **8** | |

**Worst case: max 3 iterations, quality never reaches "good":**

| Iteration | evaluate | aggregate | improve | Subtotal |
|-----------|----------|-----------|---------|----------|
| 1 | 6 | 1 | 1 | 8 |
| 2 | 6 | 1 | 1 | 8 |
| 3 | 6 | 1 | 0* | 7 |
| final-output | — | — | — | 1 |
| **Total** | | | | **24** |

*Iteration 3's improve: If quality is STILL "needs-improvement" after 3
iterations, does improve run? The `⊢∘ evolve` says `max 3` — is this 3
iterations of the full `through aggregate, improve` cycle, or 3 checks of the
`until` condition? If `max 3` means 3 loop iterations, then improve runs on
iteration 3 but the loop exits regardless. If `max 3` means 3 evaluations,
improve might not run on the last one. Ambiguous.

**LLM-free cells:**

1. **evolve (⊢∘)** — Pure control flow. Checks termination condition, manages
   iteration count. Zero LLM calls.
2. **avg-score (⊢= inside aggregate)** — Arithmetic.
3. **quality (⊢= inside aggregate)** — Conditional logic.
4. **improve (when quality="good")** — Returns input unchanged. The `∴` body
   says "If quality = good, return §greeting-v0 unchanged." This branch is
   deterministic — no LLM needed.

**Ambiguous:**

- **greeting-v0 oracle checks**: Do the `⊨` checks on greeting-v0 count as LLM
  calls? `⊨ message mentions «name»` could be a string search (LLM-free).
  `⊨ message is 1-2 sentences` could be sentence-counting (LLM-free). But
  `⊨ message has a warm but professional tone` is a judgment call — does the
  runtime use an LLM to verify this, or is it checked by the same LLM call
  that generated the message? If oracles are separate LLM calls, add 1 per
  greeting instance for the "tone" check, increasing worst-case by 9.

**The evaluate cell's internal structure is the biggest cost driver.** Each
iteration spawns 3 judges, each of which instantiates greeting-v0 (1 LLM call)
and evaluates it (1 LLM call) = 6 calls per iteration. This is O(judges ×
iterations). With 3 judges and 3 max iterations, that's 18 LLM calls just for
evaluation — 75% of the worst-case total.

**Optimization opportunity**: Execute greeting-v0 ONCE per iteration and share
the result across all judges. This would reduce evaluate from 6 to 4 calls per
iteration (1 shared greeting + 3 judge evaluations), saving 2 calls per
iteration = 6 calls in the worst case. The program text says "each judge
instantiates," which prevents this optimization.

---

### 5. Rate the overall program clarity 1-10. Could you maintain this program?

**Rating: 7/10.**

**What works exceptionally well:**

1. **The evolution loop is elegant.** `⊢∘ evolve(greeting-v0, name ≡ "Alice")
   through aggregate, improve until aggregate→quality = "good" max 3` is
   remarkably readable. On cold read, I understand: "evolve greeting-v0 by
   looping through aggregate and improve until quality is good, max 3 times."
   That's a complex control flow pattern expressed in one line.

2. **Cell-as-value (§) is powerful and clear.** The `§` sigil immediately
   signals "I'm passing a cell definition, not a cell's output." This enables
   the metaprogramming pattern (improve receives a cell and rewrites it)
   without confusion. The distinction between `greeting-v0→message` (the output)
   and `§greeting-v0` (the cell itself) is clean.

3. **Liskov substitution for cells is a great design principle.** The improve
   cell's contract — "preserve given/yield/⊨ signature" — is exactly the right
   constraint. It ensures the evolved cell is a drop-in replacement. This is the
   kind of constraint that prevents metaprogramming from becoming chaos.

4. **The crystallized sub-expressions (⊢=) inside aggregate are well-placed.**
   Marking arithmetic as `⊢=` makes it obvious which parts are deterministic.
   The reader knows immediately: avg-score and quality are computed, not
   generated.

5. **The overall architecture is sound.** Generate → Evaluate (multi-judge) →
   Aggregate → Improve → Repeat is a well-known pattern (similar to
   constitutional AI, RLHF reward modeling, etc.). The cell notation makes the
   data flow explicit.

**What doesn't work:**

1. **The spawner (⊢⊢) semantics are unclear.** Does `⊢⊢` mean "this cell
   creates other cells"? Does each spawned judge become a full cell with its own
   given/yield/⊨? Or are the judges just LLM calls inside evaluate's body? The
   `∴` body describes the judges in prose, but doesn't give them cell syntax.
   The output is `§judges[]` — an array of cell references? Or an array of
   results? The `§` prefix suggests cells, but the `[]` suggests data.

2. **The `until all criteria processed` clause on evaluate is confusing.** The
   ∴ body says "create 3 judge cells." The `until` says "until all criteria
   processed." But the criteria are hardcoded (warmth, professionalism,
   personalization) — there's no dynamic discovery of criteria. The `until` and
   `max 5` suggest evaluate might create MORE than 3 judges if "not all criteria
   are processed," but the ∴ body says exactly 3. Contradiction? Or is `until`
   a termination condition for the spawning process itself (stop spawning when
   all criteria have a judge)?

3. **The evolve cell's relationship to evaluate is implicit.** `⊢∘ evolve`
   says `through aggregate, improve` but doesn't mention evaluate. Yet the
   full loop requires evaluate to run first (aggregate receives evaluate's
   output). Is evaluate automatically re-executed because aggregate depends on
   it? Or does evolve implicitly include all upstream cells? The data dependency
   graph says evaluate must re-run, but the `through` clause doesn't mention it.

4. **No error handling whatsoever.** No `⊨?` recovery clauses, no `⊥`
   propagation, no retry logic. If any oracle fails, the program is in undefined
   territory. For a program that's ALL about iterative improvement (where early
   iterations are expected to be imperfect), the absence of error handling is
   conspicuous.

5. **The "same or different LLM output" problem.** Each judge instantiates
   greeting-v0 independently. LLM calls are non-deterministic. Three judges
   might evaluate three different greetings. This makes the scores
   incomparable — a low warmth score on greeting A and a high professionalism
   score on greeting B don't tell you anything about a single greeting's
   quality. This is a semantic bug in the program design, not a syntax issue.

**Could I maintain this program?**

Yes, with caveats. The high-level structure is clear enough to modify
confidently. I could:
- Add a new judge (add a criterion to evaluate's ∴ body)
- Change the quality threshold (modify the `⊢=` in aggregate)
- Add more evolution rounds (change `max 3`)
- Test with a different name (change `test-name ≡ "Alice"`)

I could NOT confidently:
- Add error handling (no `⊨?` patterns to follow in this program)
- Change the spawner behavior (⊢⊢ semantics are unclear)
- Reason about the evolve loop's interaction with evaluate (implicit dependency)
- Predict behavior when the LLM produces poor outputs (no failure model)

**Comparison to prior rounds:**
- More ambitious than R9-R10 (meta-programming, cell evolution)
- Cleaner high-level design but weaker error handling
- The `§` and `⊢∘` notation carry significant weight — if you understand them,
  the program is elegant; if you don't, it's opaque

---

## New Syntax Elements (Cold Read Evaluation)

| Element | Score | Cold-Read Interpretation | Correct? |
|---------|-------|--------------------------|----------|
| `§` (cell reference) | 8/10 | "The cell itself as a value" — section symbol naturally reads as "reference to a section/definition" | Highly likely correct |
| `⊢⊢` (spawner) | 5/10 | "Meta-turnstile — creates cells rather than computing values" — could also mean "doubly validated" or "second-order assertion" | Uncertain |
| `⊢∘` (loop) | 6/10 | "Composed turnstile — iterate/compose" — the `∘` (composition) symbol suggests repeated application | Plausible but fragile |
| `§greeting-v0'` (prime) | 9/10 | "Modified version of the cell" — standard mathematical prime notation | Almost certainly correct |
| `through X, Y` | 8/10 | "Loop body consists of steps X and Y" — reads naturally | Clear |
| `until condition` | 9/10 | "Loop exit condition" — plain English | Crystal clear |
| `max N` | 9/10 | "Maximum iterations" — unambiguous | Crystal clear |
| `⊢= X ← expr` | 8/10 | "Crystallized: X is defined as expr (pure computation)" — consistent with prior rounds | Clear |
| `given §cell` | 7/10 | "This cell receives another cell as input" — mixes data flow with meta-level | New usage, somewhat clear |

**Average: 7.7/10**

The loop control syntax (`through`, `until`, `max`) is the clearest part — it's
essentially plain English. The meta-programming syntax (`§`, `⊢⊢`) is the
weakest — these sigils carry heavy semantic load and require inference from
context.

---

## Key Insights

### 1. Cell Evolution as Liskov Substitution

The improve cell's contract — "preserve given/yield/⊨ signature" — is a
behavioral subtyping constraint. The evolved cell must be substitutable for
the original in any context that uses it. This is a strong design principle
that prevents evolution from breaking the program.

In traditional software: you refactor the implementation, the interface stays
stable. Here: the LLM rewrites the `∴` body (implementation), the
given/yield/⊨ (interface) must be preserved. The oracle checks on improve
enforce this invariant.

### 2. The Spawner Pattern Needs Formalization

`⊢⊢` is the most under-specified construct. Questions that need answers:
- Do spawned cells have their own oracle checks?
- Can a spawner create spawners (is spawning recursive)?
- Are spawned cells scoped to the spawner or globally visible?
- Is `§judges[]` an array of live cells or an array of completed results?
- What happens if a spawned cell fails?

### 3. Implicit Data Flow Dependencies

The evolve loop says `through aggregate, improve` but aggregate depends on
evaluate. This means either:
- (a) The runtime automatically re-executes upstream dependencies (evaluate is
  re-run because aggregate's `given` references evaluate's output), or
- (b) The `through` clause is incomplete and should read
  `through evaluate, aggregate, improve`

If (a), the runtime has a dependency resolver that figures out the execution
order from the `given` clauses. This is powerful but invisible — the reader
has to mentally reconstruct the full dependency graph.

If (b), the program has a bug.

### 4. Cost Model: O(judges × iterations)

The dominant cost is the evaluate cell. Each iteration spawns N judges, each
making 2 LLM calls (instantiate + evaluate). With 3 judges and 3 max iterations,
worst case is 24 LLM calls. The program's cost scales linearly with both the
number of judges and the number of iterations. Adding a 4th judge criterion
adds 8 LLM calls (2 per iteration × 4 iterations worst case). This cost model
should be explicit in the program.

### 5. Non-determinism in Judge Evaluation

The most significant semantic issue: each judge independently instantiates
greeting-v0, potentially getting a different greeting. The judges' scores
are then averaged, but they're scoring different texts. This is like having
three film critics review different cuts of a movie and averaging their ratings.

The fix is conceptually simple: execute greeting-v0 once, pass the result to
all judges. But the current syntax (`each judge instantiates §greeting-v0`)
doesn't support this pattern. You'd need something like:

```
⊢⊢ evaluate
  given §greeting-v0
  given test-name ≡ "Alice"
  let sample ← instantiate(§greeting-v0, name ≡ test-name)
  yield §judges[]
  ...
```

This introduces `let` bindings for shared intermediate values — a new construct
the current syntax doesn't have.
