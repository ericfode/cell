# Round 10 Results: Bottom-Propagation & Escalation Chain

## Mode: COLD READ (no syntax reference)

## The Program

---

## Evaluation 1: Bottom-Propagation

A four-cell weather pipeline: **parse-input** → **validate** → **forecast** → **format-output**.

- `parse-input` takes a raw weather string, produces structured data + confidence score
- `validate` checks physical plausibility of parsed values
- `forecast` generates a 6-hour weather prediction from validated data
- `format-output` (⊢= crystallized) assembles a markdown report

The new syntax under evaluation: `given x→y ⊥? skip with ...` — explicit
bottom-propagation handlers on individual data flow edges.

## Evaluation Questions

### 1. Trace the execution including all failure paths.

**Happy path (everything succeeds):**

```
parse-input:
  Input: "temperature: hot, humidity: 97%, wind: NNW 15mph"
  LLM parses → structured = {temperature: ?, humidity: 97, wind-speed: 15, wind-dir: NNW}
  confidence = ? (depends on "hot" → numeric conversion)
  Oracles checked: ⊨ fields present, ⊨ confidence ∈ [0,100], ⊨ temperature numeric
  All pass → yields structured, confidence

validate:
  Receives structured, confidence
  Checks physical plausibility
  temperature ∈ [-100, 150]°F, humidity ∈ [0, 100]%, wind-speed ∈ [0, 300]mph
  confidence >= 50 (or else low-confidence warning)
  yields validated=true, warnings=[] (or with warnings if marginal)

forecast:
  Receives validated=true, warnings=[], structured
  Generates 6-hour prediction citing ≥2 input fields
  yields prediction (1-3 sentences), basis

format-output:
  Pure computation (⊢=), no LLM
  Assembles markdown report from prediction + basis + warnings
  yields report
```

**Failure path 1: parse-input oracle fails once, retries, succeeds.**

```
parse-input (attempt 1):
  LLM outputs structured where temperature is non-numeric (e.g., "hot")
  ⊨ temperature is numeric (°F) → FAILS
  ⊨? on failure: retry with oracle.failures appended
parse-input (attempt 2):
  LLM sees previous failure context, outputs temperature = 95 (guessing from "hot")
  All oracles pass → yields structured, confidence
  (pipeline continues as happy path)
```

**Failure path 2: parse-input exhausts retries → ⊥.**

```
parse-input (attempt 1): oracle fails
  ⊨? on failure: retry (attempt 1 of 2)
parse-input (attempt 2): oracle fails again
  ⊨? on failure: retry (attempt 2 of 2)
parse-input (attempt 3): oracle fails again
  ⊨? on exhaustion: error-value(⊥)
  parse-input→structured = ⊥
  parse-input→confidence = ⊥

validate:
  given parse-input→structured → receives ⊥
  ⊥? skip with validated ≡ false, warnings ≡ ["upstream parse failed (⊥)"]
  (The ∴ body and ⊨ oracles are SKIPPED entirely)

forecast:
  given parse-input→structured → receives ⊥
  ⊥? skip with prediction ≡ "Unable to forecast: input parse failed", basis ≡ "N/A"
  (ALSO checks given validate→validated, but we never get there because
   parse-input→structured ⊥? triggers first)

format-output:
  Receives prediction = "Unable to forecast: input parse failed"
  Receives basis = "N/A"
  Receives warnings = ["upstream parse failed (⊥)"]
  ⊢= assembles degraded report with warning section
```

**Failure path 3: parse-input succeeds but validate itself fails with ⊥.**

This path is interesting: `validate` has no `⊨?` recovery clause. Its oracles
are plain `⊨` assertions (`validated is true if all values are physically
plausible`). These aren't really oracle constraints — they're tautological
descriptions of what validate does. If the LLM produces garbage for validate,
the behavior is undefined (no retry, no ⊥ emission).

However, `forecast` has `given validate→validated ⊥? skip with ...`, suggesting
the program expects validate CAN produce ⊥. But validate has no `⊨? on
exhaustion: error-value(⊥)` clause. **This is a gap** — the ⊥ handler on
forecast's input from validate will never trigger unless there's an implicit
mechanism for cells to produce ⊥ on uncaught failure.

**Failure path 4: forecast itself fails.**

`forecast` has no `⊨?` recovery either. Its oracles (`prediction is 1-3
sentences`, `basis references at least 2 fields`) are plain `⊨`. If the LLM
generates a 5-sentence prediction, it fails with no retry. format-output has
no ⊥? handler for forecast's outputs, so this failure propagates as... what?
Undefined.

**Maximum oracle calls**: 3 (initial) + 2 (retries on parse-input) = 5 total
LLM calls. validate and forecast each get 1 call (no retries). format-output
gets 0 (⊢= crystallized).

### 2. What does the program output when everything succeeds? When parse-input fails with ⊥?

**When everything succeeds:**

```markdown
## Weather Forecast

With current conditions showing high temperatures around 95°F, 97% humidity,
and NNW winds at 15mph, expect continued hot and muggy conditions over the
next 6 hours with possible afternoon thunderstorms.

**Basis:** Temperature (95°F) indicates extreme heat; humidity (97%) suggests
precipitation potential; NNW wind (15mph) may bring slight cooling.
```

(The exact text would be LLM-generated. The structure is fixed by format-output's
⊢= template. No warnings section because warnings is empty.)

**When parse-input fails with ⊥:**

```markdown
## Weather Forecast

Unable to forecast: input parse failed

**Basis:** N/A

**Warnings:**
- upstream parse failed (⊥)
```

This output is entirely deterministic. Every value was supplied by `⊥? skip with`
clauses — no LLM was consulted after parse-input's exhaustion. The ⊥ propagated
through validate (which skipped to produce a canned warning) and forecast (which
skipped to produce a canned prediction), and format-output crystallized them into
a report. **The entire degraded path is LLM-free.**

This is a strong design property: ⊥ propagation converts an oracle pipeline into
a deterministic fallback path.

### 3. Is the `given x ⊥? skip with ...` syntax clear on cold read? Rate 1-10.

**7/10.**

**What works:**
- The `⊥?` sigil is visually striking — you notice it immediately. The `?` suffix
  naturally reads as "what if?" or "check for condition."
- `skip with` is plain English. "If this input is ⊥, skip the cell body and use
  these values instead." That's immediately parseable.
- Placement after the `given` clause makes the scope clear: this handler is
  specific to THIS input edge, not the whole cell. You can have different ⊥
  handlers for different inputs (forecast has two: one for structured, one for
  validated).

**What doesn't work:**

- **`⊥?` looks like a type annotation, not a control flow construct.** On first
  read, `given parse-input→structured ⊥?` could mean "this input has type
  bottom-or-something" rather than "if this input IS bottom, do something."
  The control flow semantics only become clear when you read `skip with`.

- **The placement is confusing.** The `⊥? skip with` clause appears AFTER the
  `∴` and `⊨` sections of the cell, as a kind of postscript. This means you read
  the cell's logic first, then discover at the end "oh, all that might be skipped."
  It would be clearer if the ⊥ handler appeared next to the `given` it guards:
  ```
  given parse-input→structured  ⊥? skip with validated ≡ false, ...
  given parse-input→confidence
  ```
  rather than at the bottom of the cell body.

- **Multiple ⊥? handlers create combinatorial ambiguity.** Forecast has:
  ```
  given parse-input→structured ⊥? skip with prediction ≡ "...", basis ≡ "N/A"
  given validate→validated ⊥? skip with prediction ≡ "...", basis ≡ "N/A"
  ```
  What if BOTH inputs are ⊥? Which handler wins? Are they evaluated in order
  (first match wins)? Merged? This matters because the two handlers produce
  different prediction strings.

- **`skip with` vs `skip to` vs `default`.** The keyword `skip` implies "don't
  run the cell at all." But `with` implies "run it WITH these values." The
  semantics are "substitute these outputs and skip execution," which `skip with`
  captures, but `default` or `fallback` might be more intuitive.

**Overall**: The intent is immediately clear (handle ⊥ inputs gracefully). The
mechanics take a second reading. The combinatorial case (multiple ⊥? handlers)
is the real weak point.

### 4. Does ⊥ propagation make the program more or less readable?

**More readable. Significantly.**

Compare this program to a hypothetical version without ⊥ propagation:

**Without ⊥ propagation** (Round 8 style), each downstream cell would need to
check if its inputs are valid inside the `∴` body:
```
⊢ validate
  given parse-input→structured
  ∴ If «structured» is missing or invalid, set validated=false
     and warnings=["upstream failed"]. Otherwise, check plausibility...
```
The failure handling is buried in prose instructions to the LLM, mixed with
the happy-path logic. The LLM has to understand and implement the branching.

**With ⊥ propagation** (this program), failure handling is separated from logic:
```
⊢ validate
  given parse-input→structured
  ∴ Check «structured» for physically plausible values...
  given parse-input→structured ⊥? skip with validated ≡ false, warnings ≡ [...]
```
The `∴` body only describes the happy path. The `⊥? skip with` clause is a
declarative, deterministic fallback that the RUNTIME handles — the LLM never
sees it.

**This is the key insight: ⊥ propagation separates the oracle path from the
failure path.** The LLM only runs when inputs are valid. Failures are handled
mechanically. This is analogous to Maybe/Option monadic short-circuiting in
typed FP languages, but made explicit and readable in the cell syntax.

**Readability gains:**
1. Each cell's `∴` body is simpler (happy path only)
2. Failure behavior is visible at the cell boundary, not hidden in prose
3. The degraded output path is fully traceable without running any LLM
4. The reader can mentally "fold away" the ⊥ handlers on first read, then
   unfold them when analyzing failure paths

**Readability costs:**
1. The `⊥? skip with` clauses at the bottom of cells feel like afterthoughts
2. The combinatorial problem (multiple ⊥? handlers) adds cognitive load
3. It's a new concept to learn — `⊥` as a value, not just a logical symbol

**Net: +3 readability.** The separation of concerns alone justifies the mechanism.

### 5. What's still ambiguous?

**Critical ambiguities:**

1. **validate has no ⊥ emission mechanism.** Forecast handles `validate→validated ⊥?`
   but validate itself never produces ⊥. It has plain `⊨` oracles with no `⊨? on
   exhaustion: error-value(⊥)` clause. Is there an implicit rule that any cell whose
   oracles fail (without ⊨? recovery) produces ⊥ on all outputs? If so, that should
   be stated. If not, the ⊥ handler in forecast is dead code.

2. **Multiple ⊥? handler precedence.** Forecast has two ⊥? handlers (for
   structured and validated). When both inputs are ⊥, which handler's `skip with`
   values are used? Options: (a) first-match in source order, (b) last-match
   overwrites, (c) error (conflicting handlers). The handlers produce different
   prediction strings ("input parse failed" vs "validation failed"), so this
   matters.

3. **Partial ⊥.** When parse-input returns `error-value(⊥)`, does ⊥ apply to
   ALL its yields (both structured and confidence), or could one yield be ⊥ and
   the other valid? The program seems to assume all-or-nothing (the ⊥ handler
   in validate only checks `parse-input→structured`, not `parse-input→confidence`),
   but this is implicit. What if a cell partially fails — produces some yields
   but not others?

4. **⊥ vs skip vs error.** Three concepts in play:
   - `error-value(⊥)` — the cell explicitly emits ⊥ as its output
   - `⊥? skip with ...` — the downstream cell substitutes default values
   - Unhandled oracle failure — ??? (undefined in this program)

   The relationship between these three isn't clear. Is unhandled oracle failure
   the same as ⊥? Or is it a hard error that stops the pipeline? The program
   only shows the explicit `error-value(⊥)` → `⊥? skip with` path. The implicit
   failure path is unspecified.

5. **Does ⊥? skip with bypass oracles?** When validate triggers its ⊥ handler
   (`skip with validated ≡ false, warnings ≡ [...]`), are validate's own `⊨`
   oracles checked against the substituted values? The oracle says `⊨ validated
   is true if all values are physically plausible` — but we just set validated=false.
   Does this oracle fail? Or does `skip` mean "skip EVERYTHING including oracles"?
   If oracles are skipped, the ⊥ handler is a privileged escape hatch that
   bypasses verification.

6. **"temperature: hot" is intentionally unparseable.** The input string contains
   "hot" where a numeric °F value is expected. This is clearly designed to test
   the parse-input oracle. But the program's oracle says `⊨ temperature is
   numeric (°F)` — this will fail on first attempt (the LLM can't magically
   convert "hot" to a number without guessing). Is the intent that the LLM
   should guess (hot ≈ 95°F) or that it should fail? The confidence score
   suggests guessing is expected (low confidence = uncertain parse). But the
   oracle demands numeric output, which forces a guess regardless.

7. **⊥ handler on format-output is missing.** If forecast produces ⊥ (which
   can't happen currently since forecast has no ⊥ emission, but hypothetically),
   format-output has no ⊥? handler. Its `⊢=` crystallization would try to
   concatenate ⊥ with strings. What does `"## Weather Forecast\n\n" ++ ⊥` produce?
   The crystallized computation hasn't been defined over ⊥ values.

**Minor ambiguities:**

8. **`confidence` flow through validate.** Parse-input yields confidence, validate
   receives it via `given parse-input→confidence`, and the ∴ says "if confidence
   < 50, add a low-confidence warning." But validate's ⊥ handler only covers
   `parse-input→structured`, not `parse-input→confidence`. If structured is valid
   but confidence is somehow ⊥ (partial failure), validate runs its ∴ body with
   a ⊥ confidence value.

9. **The `≡` in skip-with clauses.** `validated ≡ false` uses ≡ (identity/definition),
   not ← (assignment from ⊢=) or = (equality check from ⊨). Is ≡ a fourth
   assignment operator, or is it reusing the literal-binding syntax from `given
   raw ≡ "..."`? If the latter, that's elegant — the skip-with clause literally
   binds the yields, same as given binds inputs.

10. **Oracle retry scope.** Parse-input has `⊨? on failure: retry max 2`. Does
    this mean each individual oracle gets 2 retries, or the entire cell gets 2
    retries total? If the temperature oracle fails but the confidence oracle
    passes, does the retry re-run the whole cell or just re-check temperature?

---

## Evaluation 2: Escalation Chain

A four-cell pipeline exploring escalation, recovery, and degraded-mode propagation:

```
risky-computation → escalation-handler → downstream-consumer → audit-trail
```

- `risky-computation` attempts an LLM task with retry (max 1) and escalates on exhaustion
- `escalation-handler` catches the escalation via `⊥?`, produces either a pass-through or fallback
- `downstream-consumer` formats the output, appending "System Notes" if escalation occurred
- `audit-trail` crystallizes a structured record of pipeline health

## Evaluation Questions

### 1. Trace the execution when risky-computation succeeds.

**Step 1: risky-computation**
- Receives prompt = "Summarize the plot of a novel that doesn't exist yet."
- Oracle (LLM) generates a summary
- Three `⊨` constraints checked post-hoc:
  - summary is 2-4 sentences — PASS
  - summary describes a coherent narrative arc — PASS
  - summary mentions at least one named character — PASS
- All pass → yields `summary`

**Step 2: escalation-handler**
- `given risky-computation ⊥? catch escalation` — risky-computation did NOT escalate
- Takes the success path in ∴:
  - `recovery-output` = risky-computation→summary (pass-through)
  - `escalation-log` = empty
- Constraints checked:
  - "if escalation occurred then escalation-log is non-empty" — vacuously true (no escalation)
  - "if escalation occurred then recovery-output starts with 'Unable to complete'" — vacuously true
  - "if no escalation then recovery-output = risky-computation→summary" — TRUE

**Step 3: downstream-consumer**
- Receives recovery-output (the real summary) and escalation-log (empty)
- recovery-output is a real summary → format it nicely
- escalation-log is empty → NO "System Notes" section
- Yields `final-report`: a nicely formatted summary
- Constraints: well-formatted ✓, "System Notes" rule vacuously true ✓

**Step 4: audit-trail**
- Receives escalation-log (empty) and final-report
- ⊢= crystallizes audit-record (pure computation, no oracle):
  - `had-escalation`: false
  - `escalation-context`: empty
  - `final-output-length`: length(final-report)
  - `pipeline-status`: "clean"
- Constraints: pipeline-status ∈ {"clean", "degraded"} ✓; "if had-escalation then degraded" vacuously true ✓

**Total oracle calls**: 1 (risky-computation's initial attempt).
**Pipeline status**: clean.

### 2. Trace the execution when risky-computation exhausts retries and escalates.

**Step 1: risky-computation — attempt 1**
- Oracle generates a summary
- One or more `⊨` constraints fail (e.g. summary is 5 sentences, or no named character)
- `⊨? on failure:` triggers → retry with `oracle.failures` appended to prompt

**Step 1: risky-computation — attempt 2 (retry)**
- Oracle receives the original prompt + failure context from attempt 1
- Generates a new summary
- `⊨` constraints checked again → FAIL (still doesn't meet criteria)
- `max 1` exhausted (1 retry = 2 total attempts)
- `⊨? on exhaustion:` triggers → escalate with context: "risky-computation failed after 2 attempts"
- risky-computation does NOT yield a summary — it produces an escalation signal (⊥?)

**Step 2: escalation-handler — catches escalation**
- `given risky-computation ⊥? catch escalation` — the `⊥?` clause activates
- "escalation" is now bound to the escalation context string
- Takes the escalation path in ∴:
  - `escalation-log` = the escalation context ("risky-computation failed after 2 attempts")
  - `recovery-output` = "Unable to complete. Reason: risky-computation failed after 2 attempts"
- Constraints:
  - "if escalation occurred then escalation-log is non-empty" — TRUE ✓
  - "if escalation occurred then recovery-output starts with 'Unable to complete'" — TRUE ✓
  - "if no escalation then recovery-output = risky-computation→summary" — vacuously true ✓

**Step 3: downstream-consumer**
- Receives recovery-output ("Unable to complete. Reason: ...") and escalation-log (non-empty)
- recovery-output is a fallback message → note the failure gracefully
- escalation-log is non-empty → append "System Notes" section
- Yields `final-report`: graceful failure notice + System Notes
- Constraints: well-formatted ✓, "System Notes" present ✓

**Step 4: audit-trail**
- Crystallizes audit-record:
  - `had-escalation`: true
  - `escalation-context`: "risky-computation failed after 2 attempts"
  - `final-output-length`: length(final-report)
  - `pipeline-status`: "degraded"
- Constraints: pipeline-status ∈ {"clean", "degraded"} ✓; "if had-escalation then degraded" ✓

**Total oracle calls**: 2 (initial attempt + 1 retry). Both failed.
**Pipeline status**: degraded.

### 3. Is the `given x ⊥? catch escalation` syntax clear? Rate 1-10.

**Rating: 6/10**

**What works:**
- **⊥ as failure is PL-standard.** Bottom (⊥) universally means "computation that doesn't
  produce a value." Using it for escalation — a computation that gave up — is a natural fit.
- **`?` suffix is consistent.** Throughout Cell, `?` means "conditional/maybe": `⊨?` is a
  contingent constraint, `⊥?` is a contingent failure. The pattern holds.
- **`catch` is familiar.** Anyone who's written try/catch instantly gets the intent. The
  escalation-handler is a catch block expressed as a cell.
- **Embedding in `given` is elegant.** The dependency graph itself encodes error handling.
  No separate try/catch syntax needed — the DAG IS the control flow.

**What doesn't work:**
- **`given` is now overloaded.** Previously, `given X→field` meant "I need X's output."
  Now `given X ⊥? catch escalation` means "I handle X's failure." These are semantically
  opposite: one says "give me your success," the other says "give me your failure." Putting
  both in `given` muddies the clause's meaning.
- **"escalation" is a phantom binding.** The word `escalation` after `catch` appears to be
  a name binding — the handler's ∴ references the escalation context. But the binding
  mechanism isn't explicit. Is `escalation` a variable? A keyword? Can I name it something
  else (`catch err`)? The program relies on it without defining it.
- **⊥? vs ⊥ confusion.** In R9, `error-value(⊥)` used ⊥ as a typed absence value
  (a cell yields ⊥). Here, ⊥? is a control-flow mechanism (a cell escalates). These are
  different concepts using the same symbol: ⊥-as-value vs ⊥-as-signal.
- **No visual marker on the catching cell.** `escalation-handler` is a regular `⊢` cell.
  Nothing in its header signals "I'm an error handler." The `⊥?` is buried in the `given`
  clause. Compare with `⊢⊢` for spawners — that has a distinct glyph. Error handlers
  arguably deserve one too.

**Cold read verdict:** I understood it on first reading, but I had to re-read the `given`
clause twice to be sure. The intent is clear; the mechanics are not.

### 4. Does the escalation → catch → degrade pattern feel natural in Cell?

**Yes, mostly (7/10).** The pattern maps cleanly onto Cell's dataflow model:

**The core insight is strong:** Escalation is data, not control flow. When
risky-computation fails, it doesn't throw an exception — it produces an escalation
*signal* that flows through the DAG like any other output. The escalation-handler
consumes that signal and produces a degraded result. Downstream cells don't know
or care whether they're receiving a real result or a fallback — they just consume
`recovery-output`. This is the monadic error pattern (Result/Either) expressed in
Cell's graph language.

**What feels natural:**
- **Graceful degradation as a first-class pattern.** Most languages bolt error handling
  onto the side. Cell makes it a pipeline stage. The escalation-handler IS a cell, with
  its own oracles and ∴ logic. This means recovery logic is verified just like normal logic.
- **The audit-trail captures pipeline health automatically.** Because escalation state
  flows through `given` dependencies, the audit cell can observe it without special hooks.
  The ⊢= crystallization of `pipeline-status` is clean.
- **Conditional ⊨ constraints work well here.** "if escalation occurred then X" is a
  natural way to write oracles that adapt to the pipeline's state. The vacuous truth
  of the "wrong branch" constraints is logically sound.

**What feels forced:**
- **The escalation-handler cell is boilerplate.** Its ∴ is essentially a switch statement:
  "if escalated, do fallback; if succeeded, pass through." This is pure plumbing. In most
  languages, this would be a one-liner (`result.unwrap_or(fallback)`). Dedicating an entire
  cell to it feels heavyweight.
- **Two cells (risky-computation + escalation-handler) to express try/catch.** The `⊨? on
  exhaustion: escalate` in risky-computation pushes the signal, and escalation-handler
  catches it. This splits a single concept (try-with-fallback) across two cells. A more
  integrated syntax might combine them: `⊨? on exhaustion: yield fallback "Unable to
  complete"` — keeping recovery inside the cell that fails.
- **The escalation-handler must know the upstream cell's output schema.** The constraint
  `if no escalation then recovery-output = risky-computation→summary` directly references
  risky-computation's yield field. If you swap in a different upstream cell, the handler
  breaks. The catch is tightly coupled to the throw.

**Overall:** The pattern works. The DAG-as-error-handling approach is genuinely interesting
and consistent with Cell's philosophy. The main cost is verbosity — what would be
`try { ... } catch { fallback }` in a procedural language requires two cells and explicit
data threading.

### 5. What's still ambiguous?

#### Critical

**1. Binding semantics of `catch escalation`.**
Is `escalation` a name binding, a keyword, or syntactic sugar? The ∴ body of
escalation-handler references the escalation context implicitly ("Log the escalation
context in «escalation-log»"), but the `catch escalation` clause doesn't show how the
context becomes accessible. Can you write `catch e` and reference `e` in the ∴? Or is
`escalation` a reserved term? This is the most important ambiguity — it determines
whether ⊥? is a general mechanism or a one-off pattern.

**2. What does escalation-handler receive when risky-computation succeeds?**
The `given risky-computation ⊥? catch escalation` clause activates on failure. But on
success, what does escalation-handler receive? The ∴ says "pass through its summary as
recovery-output," implying it receives the summary. But how? Through the `⊥?` clause?
Through a separate `given risky-computation→summary`? The program only has ONE given
clause for risky-computation, yet it needs to handle both outcomes. Does `⊥?` implicitly
provide both the success value AND the escalation signal?

**3. ⊥ propagation without a handler.**
If escalation-handler didn't exist, what happens to risky-computation's escalation?
Does ⊥ propagate to downstream-consumer? Does the pipeline abort? Does the runtime
error? This program carefully provides a handler, but the language needs to define
what happens when escalation goes uncaught. Options:
- (a) Pipeline aborts (fail-fast)
- (b) ⊥ propagates through all dependent cells (fail-soft)
- (c) Compile error — `⊨? on exhaustion: escalate` requires a ⊥? consumer

#### Significant

**4. `max 1` semantics — retries or total attempts?**
"retry ... max 1" — is this 1 retry (2 total attempts) or 1 total attempt? The
exhaustion message says "failed after 2 attempts," implying max 1 = 1 retry = 2
attempts. But this is the ∴ body saying "2 attempts," not the syntax defining it.
The `max N` semantics should be unambiguous from the syntax alone.

**5. Escalation context schema.**
The escalation carries context: "risky-computation failed after 2 attempts." Is this
a raw string, a structured object (with fields like `cell`, `attempts`, `failures[]`),
or a Cell value? The escalation-handler references it as prose in ∴, but audit-trail
stores it as `escalation-context` in a ⊢= record. The schema of escalation data
affects how it can be consumed programmatically.

**6. Oracle scope in escalation-handler.**
escalation-handler has oracles like `⊨ if escalation occurred then escalation-log is
non-empty`. The predicate "if escalation occurred" — how does the runtime evaluate this?
Is it checking whether the `⊥?` clause activated? Is there an implicit boolean? The
oracle references a condition ("escalation occurred") that isn't bound to a named
value anywhere in the program.

**7. Can escalation-handler itself escalate?**
If escalation-handler's ⊨ constraints fail, what happens? It has plain `⊨` (not `⊨?`),
so no retry mechanism. If a catch block fails, does the pipeline abort? Can you chain
`⊥?` handlers (catch-of-a-catch)? The program doesn't test this, but the language
needs to define it.

#### Minor

**8. Conditional oracle expressiveness.**
The oracles use natural-language conditionals: "if escalation occurred then X." This
works for a cold reader, but is hard to verify mechanically. A runtime checking these
oracles needs to parse the conditional structure. Would be cleaner as:
`⊨ escalation → escalation-log ≠ ∅` (using → as implication).

**9. Redundancy between escalation-handler and audit-trail.**
Both cells inspect escalation state. escalation-handler determines the pipeline path;
audit-trail records it. But audit-trail could derive `had-escalation` from
`escalation-log is not empty` — it doesn't need escalation-handler to tell it. The
two cells have overlapping concerns. Is this intentional (defense in depth) or
structural overhead?

**10. downstream-consumer's ignorance.**
downstream-consumer doesn't know whether recovery-output is real or fallback — it
checks `escalation-log` to decide. But the program could have designed it to be
truly oblivious (just format whatever recovery-output says). The fact that it
inspects escalation-log means it IS aware of the error handling mechanism. True
degraded-mode transparency would mean downstream-consumer never sees escalation-log.

## Syntax Element Clarity (Cold Read)

| Element | Score | Notes |
|---------|-------|-------|
| `⊥?` (escalation signal) | 6/10 | PL-standard ⊥, but overloaded with R9's error-value(⊥) |
| `catch escalation` | 5/10 | Familiar keyword, phantom binding, unclear scope |
| `given X ⊥? catch` | 6/10 | Elegant embedding in DAG, but overloads `given` |
| `⊨? on failure:` | 9/10 | Crystal clear, natural language retry trigger |
| `⊨? on exhaustion:` | 8/10 | Unambiguous — all retries spent, time to escalate |
| `escalate with context:` | 8/10 | Intent is clear, context schema undefined |
| `⊢=` audit crystallization | 9/10 | Clean, deterministic, reads perfectly |
| Conditional `⊨` | 7/10 | Readable but hard to verify mechanically |

**Average**: 7.3/10

---

## Evaluation 3: Template Instantiation

A four-cell code review pipeline with explicit template instantiation:

- `review-template` — a reusable cell template (not executed directly)
- `code-samples` — pure computation, yields 3 literal code snippets
- `review-all` — spawner (⊢⊢), instantiates the template once per snippet
- `triage` — collects review results, counts critical findings, creates action items

## Evaluation Questions

### 1. Trace the execution including all failure paths.

**Happy path:**

```
code-samples ──snippets[3]──→ review-all ──§reviews[3]──→ triage
                                  ↑
                            §review-template
```

**Step 0: code-samples** (pure computation via ⊢=)
- No oracle, no LLM. Yields `snippets[]` = 3 literal strings.
- Cannot fail (deterministic).

**Step 1: review-all** (spawner ⊢⊢)
- Receives: `code-samples→snippets` (3 items), `§review-template` (cell definition)
- For each snippet, instantiates the template:
  - Copy given/yield/∴/⊨ from review-template
  - Bind `code-snippet ≡ <snippet>`
  - Name: review-template-1, review-template-2, review-template-3
- Yields: `§reviews[] = [§review-template-1, §review-template-2, §review-template-3]`
- The spawner does NOT execute the instantiated cells — it produces cell
  *definitions* (§-quoted). Execution is deferred to triage.

**Step 2: triage** receives §reviews[3]
- ∴ says "Execute each review cell. Collect results."
- This triggers execution of all 3 instantiated review cells.
- Each review cell calls an LLM to review its bound code-snippet.
- Collects: issues[], severity, summary from each.
- ⊢= critical-count ← count(reviews where severity ∈ {"critical", "major"})
- Yields: critical-count, action-items[].

**Expected results by snippet:**

| # | Snippet | Expected severity | Reasoning |
|---|---------|-------------------|-----------|
| 1 | Python `login` with f-string SQL | **critical** | Classic SQL injection |
| 2 | Rust `add(a, b) -> a + b` | **clean** | Trivially correct, type-safe |
| 3 | JS `fetchData` — no error handling | **minor** or **major** | Missing try/catch, no status check |

**Failure paths:**

**F1: Oracle failure on an instantiated review cell.**
Each review-template-N inherits 3 oracles:
- `severity ∈ {"clean", "minor", "major", "critical"}` — LLM must use exact enum values
- `summary is exactly one sentence` — LLM must not produce 2+ sentences
- `issues[] is empty iff severity = "clean"` — bidirectional constraint

If the LLM returns `severity = "moderate"` or gives a 2-sentence summary, the
oracle fails on that specific instance. **No ⊨? recovery exists.** Behavior is
undefined — hard failure.

This is the most likely failure path. LLMs frequently violate exact-enum
constraints (writing "Critical" instead of "critical") and length constraints
(producing a run-on summary).

**F2: Oracle failure on review-all.**
- `§reviews[] has same length as snippets` — structural check on the spawner.
  Fails if the spawner skips a snippet or creates extras. Since the spawner is
  the runtime (not the LLM), this should only fail on a bug in the spawner
  implementation. Acts as a type-check/assertion.
- `each review has same yield signature as §review-template` — structural
  check that instantiation preserved the yield fields. Again a type-check.

These are meta-level checks on the spawning mechanism, not LLM output checks.
They catch implementation bugs, not oracle failures.

**F3: Oracle failure on triage.**
- `action-items is non-empty if critical-count > 0` — if the LLM finds
  critical issues but produces no action items, this fails. One-directional:
  doesn't require action-items to be empty when critical-count = 0.
- `each action-item references the specific code snippet and issues found` —
  structural check. Fails if action items are vague/generic.

**F4: Upstream failure propagation.**
If review-template-1 fails (oracle violation), what happens to triage?
Options (all unspecified):
- (a) Triage receives partial results (2 of 3) → critical-count is wrong
- (b) Triage never executes (blocked by upstream failure)
- (c) Triage receives an error marker and must handle it

The program doesn't specify. This is the same ⊥-propagation gap identified
in Round 9.

**F5: `max 5` never triggered.**
With 3 snippets, the spawner creates 3 cells. Max 5 is headroom. If
code-samples were extended to 6+ snippets, max 5 would cap instantiation
and the oracle `§reviews[] has same length as snippets` would fail
(5 reviews ≠ 6 snippets). This is an internal contradiction — the oracle
demands completeness but `max` allows truncation.

### 2. What does the spawner produce? Show the instantiated cells.

The spawner `review-all` produces 3 instantiated cells. Here they are
in full, showing the copy-and-bind mechanism:

**review-template-1:**
```
⊢ review-template-1
  given code-snippet ≡ "def login(user, pw): return db.query(f'SELECT * FROM users WHERE name={user} AND pass={pw}')"
  yield issues[], severity, summary

  ∴ Review «code-snippet» for bugs, style issues, and security problems.
    List each «issue» with a description.
    Rate overall «severity» as: clean, minor, major, critical.
    Write a one-sentence «summary».

  ⊨ severity ∈ {"clean", "minor", "major", "critical"}
  ⊨ summary is exactly one sentence
  ⊨ issues[] is empty if and only if severity = "clean"
```

**review-template-2:**
```
⊢ review-template-2
  given code-snippet ≡ "fn add(a: i32, b: i32) -> i32 { a + b }"
  yield issues[], severity, summary

  ∴ Review «code-snippet» for bugs, style issues, and security problems.
    List each «issue» with a description.
    Rate overall «severity» as: clean, minor, major, critical.
    Write a one-sentence «summary».

  ⊨ severity ∈ {"clean", "minor", "major", "critical"}
  ⊨ summary is exactly one sentence
  ⊨ issues[] is empty if and only if severity = "clean"
```

**review-template-3:**
```
⊢ review-template-3
  given code-snippet ≡ "async function fetchData() { const res = await fetch(url); return res.json(); }"
  yield issues[], severity, summary

  ∴ Review «code-snippet» for bugs, style issues, and security problems.
    List each «issue» with a description.
    Rate overall «severity» as: clean, minor, major, critical.
    Write a one-sentence «summary».

  ⊨ severity ∈ {"clean", "minor", "major", "critical"}
  ⊨ summary is exactly one sentence
  ⊨ issues[] is empty if and only if severity = "clean"
```

**Observations on the instantiation:**

1. **Structure is identical** — all 3 cells have the same yield, ∴, and ⊨.
   Only the `given` binding differs. This is exactly the point of templates:
   parameterized reuse.

2. **The `given` changes from unbound to bound** — `review-template` has
   `given code-snippet` (a parameter). Each instance has
   `given code-snippet ≡ <value>` (a binding). The `≡` operator converts
   a free variable into a concrete value.

3. **Oracles are copied verbatim** — the ∴ instructions say "Preserve all
   oracles from the template." The oracles reference `severity`, `issues[]`,
   and `summary` — all of which are yields of the instance, so they remain
   well-scoped. No oracle needs modification during instantiation.

4. **The § prefix on `reviews[]` in the yield means the spawner produces
   cell references, not executed results.** The cells exist but haven't
   run. Triage must execute them.

### 3. Is the template instantiation syntax clear? Rate 1-10.

**Template instantiation overall: 8/10**

This is the clearest spawner program so far. The reason: the ∴ body of
`review-all` explicitly spells out the instantiation algorithm:

> - Copy given/yield/∴/⊨ from the template
> - Bind code-snippet ≡ <the snippet>
> - Preserve all oracles from the template
> - The instantiated cell inherits the template's name with a suffix

This is unprecedented in prior rounds. Previous spawners (R9) left the
instantiation mechanism implicit — you had to infer what "stamp out copies"
meant. Here it's procedural documentation embedded in the cell's own
instructions. The cell tells you exactly what it does.

**Breakdown by element:**

| Element | Score | Notes |
|---------|-------|-------|
| `§review-template` as input | 9/10 | § clearly marks "this is a cell definition, not a value" |
| `given §review-template` on ⊢⊢ | 8/10 | Natural — the spawner takes a template as input |
| `yield §reviews[]` | 8/10 | § on yield means "I produce cell definitions" |
| `≡` for binding | 9/10 | Mathematical identity — reads as "is defined as" |
| Copy given/yield/∴/⊨ | 7/10 | Clear as prose, but: is this a deep copy? What about nested §? |
| Name suffixing (-1, -2, -3) | 8/10 | Simple, predictable naming convention |
| `until all snippets processed` | 9/10 | English-clear termination |
| `max 5` | 7/10 | Clear intent, but contradicts the length oracle (see F5 above) |

**What makes this work:** The template is *explicitly a cell* (marked with ⊢)
that happens to have an unbound `given`. This is different from R9's approach
where the template relationship was more implicit. Here, `review-template` is
a first-class program entity — you can read it, understand it, and predict
what its instances will look like.

**What doesn't quite work:** The ∴ body does double duty — it's both an
instruction to the LLM ("for each snippet, instantiate...") and a specification
of the instantiation algorithm ("copy given/yield/∴/⊨"). Is the LLM supposed
to perform the instantiation? Or is the runtime? If the runtime does it, the
∴ is documentation, not instruction. If the LLM does it, we're asking the
LLM to generate cell definitions, which is fragile.

### 4. Does the § copy mechanism make sense (copy given/yield/∴/⊨, bind new values)?

**Yes, with caveats. Rating: 7/10.**

**What works:**

The § copy mechanism is essentially **macro expansion** or **template
stamping**. This is a well-understood pattern:

1. Define a template with free variables (`given code-snippet`)
2. For each input, create a copy with the variable bound (`code-snippet ≡ value`)
3. Everything else (yield signature, instructions, oracles) is preserved

This is analogous to:
- C++ template instantiation (`template<typename T>` → concrete type)
- Lisp quasiquoting (`` ` `` + `,` for splicing)
- Functional programming's partial application (bind one arg, leave the rest)

The mechanism is clean because the template and its instances share the same
*kind* — they're all cells (⊢). An instance is just a fully-bound cell where
all `given` parameters have concrete values. This means:
- The runtime needs only one execution model (cells)
- Oracles work unchanged (they reference yields, not givens)
- The ∴ instructions work unchanged (they reference «code-snippet» which
  is now bound)

**What's unclear:**

1. **Deep vs shallow copy.** "Copy given/yield/∴/⊨" — what if the template's
   ∴ references another cell via §? Is that reference copied by reference
   (shared) or by value (deep-cloned)? In this program it doesn't matter
   (review-template references nothing), but for nested templates it would.

2. **Multiple unbound givens.** This template has one `given` (code-snippet).
   What if a template has `given x` and `given y`? Does each instantiation
   bind all of them? Can you partially bind (bind x, leave y free) to create
   a partially-instantiated template? The syntax doesn't address this.

3. **Oracle scope after binding.** The oracles reference `severity`, `issues[]`,
   `summary` — all yields. They don't reference `code-snippet` (the bound
   given). But what if an oracle *did* reference the given? Like
   `⊨ summary mentions «code-snippet»`. After binding, `code-snippet` has a
   concrete value. Does the oracle become
   `⊨ summary mentions "def login(user, pw)..."`? Or does it remain symbolic?

4. **Who performs the copy?** The ⊢⊢ spawner's ∴ describes the algorithm, but
   is the spawner itself a runtime primitive (the system knows how to copy
   cells), or is this an LLM-mediated operation (the LLM generates new cell
   source text)? If the latter, the LLM could introduce errors in the copy.
   If the former, the ∴ is just documentation and the real semantics are
   hardcoded.

5. **Identity after instantiation.** review-template-1 inherits the template's
   name with a suffix. But is review-template-1 a *new* cell or a *modified
   copy* of review-template? Can the original template be instantiated again?
   (Yes, presumably — the template isn't consumed.) Can two instantiations
   of the same template with the same binding be distinguished? (They'd have
   different suffixes: -1 vs -4, say.)

**The mechanism is sound for the simple case shown here.** One template, one
free variable, flat structure. The questions above only arise for more complex
patterns (nested templates, multiple bindings, cross-references).

### 5. What's still ambiguous?

**Critical ambiguities:**

1. **Who executes the instantiated cells — and when?**
   The spawner `review-all` produces `§reviews[]` (cell references). The triage
   cell's ∴ says "Execute each review cell." But execution is a runtime
   operation, not an LLM operation. Is triage *asking the runtime* to execute
   the cells? Or is triage *itself* executing them (calling the LLM for each)?
   The distinction matters: if the runtime executes review cells in parallel,
   triage just collects results. If triage executes them sequentially in its
   own LLM context, it sees each review's output and can aggregate on the fly.

2. **The `max 5` / length-oracle contradiction.**
   Oracle: `§reviews[] has same length as snippets` (demands 3 reviews for 3
   snippets). But `max 5` implies the spawner *might not* process all snippets.
   If code-samples yielded 7 snippets, the spawner would create 5 (capped),
   the oracle would demand 7, and the oracle would fail. The `max` and the
   oracle are in tension. Which takes precedence? Is `max` a hard cap that
   the oracle must accommodate? Or does the oracle override `max` (you *must*
   create all of them)?

3. **Template as a cell vs template as a type.**
   `review-template` is declared with `⊢` — it's a cell. But it's never
   executed directly. Its sole purpose is to be copied. Is a template a
   special kind of cell (like an abstract class)? Or is any cell with an
   unbound `given` implicitly a template? If the latter, what prevents the
   runtime from trying to execute review-template itself (and failing because
   code-snippet is unbound)?

4. **The `≡` binding semantics.**
   `Bind code-snippet ≡ <the snippet>` uses ≡ (logical identity). But in
   `code-samples`, `⊢= snippets ← [...]` uses ← (assignment). Are ≡ and ←
   the same operation? Prior rounds used ← exclusively for ⊢= crystallized
   values. Here ≡ appears in a different context (binding a template
   parameter). If they're different: ← is computation, ≡ is substitution.
   That's a meaningful distinction but it's never stated.

5. **Oracle inheritance vs oracle composition.**
   Instantiated cells inherit oracles from the template. But triage also has
   oracles that reference the reviews. There are now two layers of oracle
   checking:
   - Layer 1: Each review-template-N has its own oracles (severity ∈ {...}, etc.)
   - Layer 2: Triage has oracles about the collection (action-items non-empty, etc.)

   If review-template-1 passes its own oracles but triage's oracle fails,
   which cell is "wrong"? If review-template-1 fails its own oracle, does
   triage even run? The oracle layers interact but there's no defined
   evaluation order or error propagation model.

6. **The spawner's ∴ is specification, not instruction.**
   The ∴ body of review-all describes an algorithm (copy, bind, preserve,
   name). But ∴ is normally an instruction to an LLM oracle. Is the spawner's
   ∴ executed by the runtime (deterministic) or by an LLM (probabilistic)?
   If deterministic, ∴ is overloaded — sometimes it means "ask the LLM" and
   sometimes "run this algorithm." If LLM-mediated, the LLM is being asked to
   perform structured code generation, which is fragile.

   Compare: `code-samples` uses `⊢=` to mark pure computation. The spawner
   uses `⊢⊢` but no `⊢=` — yet its ∴ describes a deterministic operation.
   Should spawner instantiation be `⊢=`-like (pure, no LLM)?

**Minor ambiguities:**

7. **Suffix collision.** If the program had two spawners using the same
   template, both would produce `review-template-1`, `review-template-2`, etc.
   Name collision. Need scoping or a qualified prefix (spawner-name/template-N).

8. **Empty snippets edge case.** If `code-samples` yielded an empty list,
   review-all would produce 0 reviews. The `until all snippets processed`
   clause is trivially satisfied. triage would receive an empty §reviews[].
   ⊢= critical-count ← 0. Oracle: `action-items is non-empty if critical-count > 0`
   — vacuously true. The program works but produces a vacuous result.

9. **`⊨ each review has same yield signature as §review-template`** —
   This oracle checks structural equivalence. But "same yield signature"
   could mean: (a) same field names, (b) same field names AND types,
   (c) same field names AND types AND oracle constraints. The depth of
   "sameness" is unspecified.

10. **Triage's ⊢= and ∴ coexist.** Triage has both a ∴ (LLM instruction)
    and a ⊢= (deterministic computation). The ⊢= computes critical-count.
    But the ∴ also says "Count how many reviews have severity = critical or
    major." Is the LLM supposed to count? Or does ⊢= handle counting and the
    ∴ only handles action-items? The division of labor between ∴ (LLM) and
    ⊢= (deterministic) within a single cell isn't clear.


---

## Evaluation 4: Oracle-Retry-Spawned

## The Program

A four-cell test harness: **test-cases** → **run-tests** → **test-report**, with
**transform-template** as a quoted blueprint that the spawner instantiates per case.

- `test-cases` is pure crystallization (⊢=), yields 4 literal test cases
- `transform-template` is a template cell with oracles and recovery (⊨?)
- `run-tests` (⊢⊢ spawner) instantiates the template once per case, adding a
  case-specific oracle
- `test-report` collects results, classifies pass/fail/exhausted

This is the first program to combine all three mechanisms: spawning (⊢⊢),
oracle recovery (⊨?), and template instantiation (§) in a single pipeline.

## Cold Read Evaluation

### Q1: Trace the execution including oracle retries on spawned cells.

**Full trace:**

**Phase 1 — Data (deterministic)**

`test-cases` executes. Pure ⊢= crystallization — no LLM call. Yields:
```
cases = [
  {input: "hello world", expected: "HELLO WORLD"},
  {input: "café",        expected: "CAFÉ"},
  {input: "",            expected: ""},
  {input: "123 abc",     expected: "123 ABC"}
]
```

**Phase 2 — Spawning (⊢⊢ run-tests)**

The spawner receives `test-cases→cases` (4 items) and `§transform-template`
(the quoted cell blueprint). For each case, it instantiates the template:

```
case[0]: text ≡ "hello world"
  Oracles (inherited from template):
    ⊨ result = uppercase("hello world")     [template oracle, instantiated]
    ⊨ result has same length as "hello world"
    ⊨ result contains no lowercase letters
  Oracle (added by spawner):
    ⊨ result = "HELLO WORLD"                [case-specific, from case.expected]
  Recovery (inherited):
    ⊨? on failure: retry with oracle.failures, max 2
    ⊨? on exhaustion: error-value(⊥)

case[1]: text ≡ "café"    → same structure, expected = "CAFÉ"
case[2]: text ≡ ""        → same structure, expected = ""
case[3]: text ≡ "123 abc" → same structure, expected = "123 ABC"
```

Total spawned cells: 4 (one per case).
Total cells in the program: 6 (test-cases + transform-template + run-tests +
4 spawned test-runs - but transform-template is never executed, only quoted).
Effectively: 5 executing cells + 1 template.

**Phase 3 — Execution of spawned cells (oracle retry)**

Each spawned test-run cell executes independently:

```
test-run[0] ("hello world"):
  Attempt 1: LLM converts "hello world" → "HELLO WORLD"
  Oracle check: result = uppercase(text)? ✓
                same length? ✓
                no lowercase? ✓
                result = "HELLO WORLD"? ✓
  → PASS (1 oracle call)

test-run[1] ("café"):
  Attempt 1: LLM converts "café" → "CAFE"      [common LLM error: drops accent]
  Oracle check: result = uppercase(text)? depends on uppercase("café") definition
                same length? ✓ (4 chars)
                no lowercase? ✓
                result = "CAFÉ"? ✗            [accent dropped]
  → ⊨? on failure: append {oracle.failures: ["result ≠ CAFÉ"]} to prompt
  Attempt 2: LLM retries with failure context → "CAFÉ"
  Oracle check: all pass
  → PASS (2 oracle calls)

  [OR if attempt 2 also fails:]
  → ⊨? on exhaustion: error-value(⊥)
  → result = ⊥ (3 oracle calls total? See ambiguity in Q5)
```

**Phase 4 — Reporting (test-report)**

`test-report` receives §test-runs (4 cells with their results).
Uses ⊢= crystallization to compute counts — no LLM needed.

**Maximum oracle calls**: 4 cells × 3 attempts each = 12 (worst case).
**Minimum oracle calls**: 4 (all pass on first attempt).
**Zero oracle calls** on: test-cases (⊢=), run-tests (spawner, not oracle),
test-report (⊢= counts).

The DAG:
```
test-cases ──cases──→ run-tests ──§test-runs──→ test-report
                         ↑
              §transform-template
```

### Q2: What happens when a test case fails all retries? Show the exhaustion flow.

**Exhaustion flow for a single spawned cell (e.g., "café"):**

```
┌─ Attempt 1 ─────────────────────────────────────────┐
│  LLM prompt: "Convert «café» to uppercase."         │
│  LLM output: "CAFE"                                 │
│  Oracle check:                                       │
│    ⊨ result = uppercase("café")  → ambiguous (*)    │
│    ⊨ same length                 → ✓                │
│    ⊨ no lowercase                → ✓                │
│    ⊨ result = "CAFÉ"             → ✗ FAIL           │
│  → ⊨? on failure fires                              │
└──────────────────────────────────────────────────────┘
         │
         ▼ oracle.failures = [{constraint: "result = CAFÉ", got: "CAFE"}]
┌─ Attempt 2 ─────────────────────────────────────────┐
│  LLM prompt: "Convert «café» to uppercase."         │
│    + "Previous failures: result was CAFE, expected   │
│      CAFÉ. Preserve diacritics."                     │
│  LLM output: "CAFE"  [still wrong]                  │
│  Oracle check: ⊨ result = "CAFÉ" → ✗ FAIL           │
│  → ⊨? on failure: max 2 reached                     │
└──────────────────────────────────────────────────────┘
         │
         ▼ retries exhausted
┌─ ⊨? on exhaustion ──────────────────────────────────┐
│  error-value(⊥)                                      │
│  Cell yields: result = ⊥                             │
│  oracle.failures preserved in cell metadata          │
└──────────────────────────────────────────────────────┘
         │
         ▼
test-report receives: {result: ⊥, exhaustion: true,
  failures: [{attempt: 1, got: "CAFE"}, {attempt: 2, got: "CAFE"}]}
```

**Key observations:**

1. **⊥ is a value, not an exception.** The cell completes normally — it yields
   `result = ⊥` rather than crashing. This is the "typed absence" pattern from
   Round 9's `error-value(⊥)`. The pipeline continues; test-report can still
   count and report on the failure.

2. **Failure history is preserved.** The `oracle.failures` context accumulates
   across retries. The test-report's final oracle (`⊨ report includes
   oracle.failures history for each exhausted test`) demands this history be
   surfaced. This creates an implicit data channel: failure metadata flows from
   spawned cells up to the reporter.

3. **The exhaustion is contained.** One cell's exhaustion doesn't crash the
   whole pipeline. Other test-run cells continue independently. This is
   fail-soft at the cell level, fail-transparent at the pipeline level.

### Q3: How does the test-report cell know which tests were exhausted vs passed?

**Three separate detection mechanisms, each using ⊢= crystallization:**

```
⊢= pass-count     ← count(test-runs where all oracles passed)
⊢= fail-count     ← count(test-runs where result = ⊥)
⊢= exhausted-count ← count(test-runs where ⊨? on exhaustion fired)
```

**Detection 1 — pass-count**: Checks whether "all oracles passed." This is
straightforward if the runtime tracks oracle pass/fail status per cell. The
test-report reads each cell's oracle status as metadata.

**Detection 2 — fail-count**: Checks `result = ⊥`. This uses the value channel,
not metadata. A cell that exhausted retries yields ⊥ as its result. The
test-report can detect this purely from the cell's output. No metadata needed.

**Detection 3 — exhausted-count**: Checks `⊨? on exhaustion fired`. This is an
*event query* — it asks whether a specific recovery clause triggered. This
requires execution metadata that goes beyond the cell's output values.

**The tension**: Detection 2 uses data (⊥ is a value), but Detection 3 uses
execution events. This implies the test-report has access to a richer execution
record than just yields:

```
cell output = {result: "HELLO WORLD"}           → passed
cell output = {result: ⊥}                       → failed (detectable from value)
cell metadata = {exhaustion_fired: true,         → exhausted (detectable from events)
                 oracle_failures: [...]}
```

**This is a significant design decision.** The program treats spawned cells as
transparent — their execution history (not just their outputs) is visible to
downstream cells. This contrasts with a pure dataflow model where cells only
see each other's yields.

**The oracle on test-report reinforces this:**
```
⊨ report includes oracle.failures history for each exhausted test
```
This demands that `oracle.failures` — an internal execution artifact of each
spawned cell — be accessible to test-report. The failure history must flow
through the pipeline as inspectable data.

**Implied model**: Spawned cells (§test-runs) are not opaque. The parent
(test-report) can inspect:
- Output values (result)
- Oracle pass/fail status
- Recovery events (exhaustion fired)
- Failure history (oracle.failures)

This is closer to an "execution trace" model than a pure "value passing" model.
It's powerful for testing/auditing scenarios but raises questions about cell
encapsulation in other contexts.

### Q4: Rate the clarity of inherited ⊨? clauses on spawned cells (1-10)

**6/10**

**What works:**

The *intent* is clear. When I read:
```
∴ For each case in «test-cases→cases», instantiate «§transform-template»:
    - Bind text ≡ case.input
    - Add oracle: ⊨ result = case.expected
    - Each instantiated cell inherits ⊨? clauses from template
```

I understand: each spawned cell gets the template's retry logic. The word
"inherits" correctly suggests the ⊨? clauses are copied, not shared. Each
spawned cell has its own retry budget. This is the right mental model.

The spawner's oracle reinforces it:
```
⊨ each test-run has same ⊨? clauses as «§transform-template»
```
This is an oracle *about the spawning mechanism itself* — a meta-assertion that
the runtime correctly inherited the recovery clauses. Novel and useful.

**What doesn't work:**

1. **Inheritance is specified in prose (∴), not syntax.** The instruction
   "Each instantiated cell inherits ⊨? clauses from template" is in the
   natural-language body, not in the formal structure. There's no syntactic
   marker that says "copy recovery clauses." Compare with `given`, `yield`,
   `⊨` — all structural. Inheritance is instructional.

   This means a runtime could miss it. An LLM interpreting the ∴ might or
   might not inherit ⊨? clauses — it's a suggestion, not a mandate.

2. **The `Add oracle` pattern mixes with inheritance.** The spawner both
   *adds* a new oracle (`⊨ result = case.expected`) and *inherits* existing
   ones from the template. How do added and inherited oracles compose?
   Are they AND-ed? Do they share the same retry budget? If the inherited
   oracles pass but the added oracle fails, does ⊨? on failure fire?

3. **`max 2` — per oracle or per cell?** The template says `retry... max 2`.
   If a spawned cell has 4 oracles (3 inherited + 1 added) and different
   oracles fail on different attempts, does each oracle get 2 retries, or
   does the cell as a whole get 2 retry cycles? The "all oracles checked
   together" interpretation seems intended, but it's not explicit.

4. **No syntax for conditional inheritance.** What if you want to inherit
   oracles but NOT ⊨? clauses? Or inherit ⊨? but change `max`? The
   all-or-nothing inheritance model is simple but inflexible.

**Score breakdown:**

| Aspect | Score | Notes |
|--------|-------|-------|
| Intent comprehension | 9/10 | Crystal clear what's meant |
| Formal specificity | 4/10 | Prose instruction, not syntax |
| Composition rules | 4/10 | Added + inherited oracle interaction unclear |
| Retry budget scoping | 5/10 | Per-cell vs per-oracle ambiguous |
| Overall cold-read | 6/10 | Understand the goal, can't verify the mechanics |

### Q5: What's still ambiguous?

**Critical:**

1. **`max 2` semantics.** Does `retry... max 2` mean 2 retries (3 total
   attempts) or 2 total attempts (1 initial + 1 retry)? This is the classic
   off-by-one from Round 9, still unresolved. For a test harness this matters:
   it determines whether worst-case oracle calls are 8 (4 cells × 2) or
   12 (4 cells × 3).

2. **Oracle composition on spawned cells.** Each spawned cell has 4 oracles:
   3 inherited from the template, 1 added by the spawner. Questions:
   - Are all 4 checked after each attempt?
   - If oracle 1 passes but oracle 4 fails, is that a "failure" that triggers ⊨??
   - On retry, are ALL oracles re-checked, or only the failed ones?
   - Does `oracle.failures` include all 4, or only the ones that failed?

   The natural reading is "all oracles checked together, any failure triggers
   retry, all re-checked on retry." But this isn't specified.

3. **`result = uppercase(text)` vs `result = case.expected` redundancy.**
   The template has `⊨ result = uppercase(«text»)` and the spawner adds
   `⊨ result = case.expected`. For well-formed test cases, these say the same
   thing (`uppercase("hello world") = "HELLO WORLD"`). But they're different
   mechanisms:
   - `uppercase(«text»)` is a function call — who evaluates it? The oracle
     system needs a built-in `uppercase` function, or it's delegated to the LLM.
   - `case.expected` is a literal comparison.

   If the `uppercase()` function disagrees with `case.expected` (e.g., on
   locale-dependent characters like "café"), the oracles contradict each other.
   The cell would be unfulfillable — every attempt fails, exhaustion guaranteed.

4. **Execution metadata accessibility.** `test-report` uses `where ⊨? on
   exhaustion fired` — a query over execution events. This implies cells
   expose their execution trace, not just their yields. But the program
   doesn't declare this. Is execution metadata always accessible to downstream
   cells? Only for §-referenced cells? Only for cells spawned by ⊢⊢?

**Significant:**

5. **`test-report` receives `§test-runs`, not results.** The `given` says
   `run-tests→§test-runs` — the § prefix means these are cell references, not
   values. So test-report receives cell *definitions* (or handles). The ∴ says
   "Execute each test-run cell" — meaning test-report is the executor, not
   run-tests. This is subtle: the spawner *creates* the cells, but the reporter
   *executes* them. Who owns the retry budget? If test-report executes them,
   does it also manage the ⊨? recovery? Or did the spawner already execute
   them and test-report just reads results?

   Two readings:
   - **Lazy**: run-tests creates cell definitions, test-report executes them.
     The cells are "thunks" — deferred computations.
   - **Eager**: run-tests spawns AND executes the cells, test-report receives
     completed results. The § prefix is just "these came from cells."

   The ∴ in test-report ("Execute each test-run cell") suggests lazy evaluation,
   which is a significant execution model choice.

6. **`max 10` on run-tests.** There are only 4 test cases. `max 10` can never
   be hit. Is this a safety cap (like R9's `max 5` on 3 handlers), or does it
   hint that `run-tests` might spawn MORE than one cell per case (e.g., retry
   at the spawner level)? If a spawned cell exhausts and yields ⊥, does the
   spawner retry with a fresh instantiation? `max 10` would allow up to 2.5
   retries per case at the spawner level. But nothing in the program text
   suggests spawner-level retry.

7. **`pass-count + fail-count = length(test-runs)` — is exhausted a subset
   of failed?** The oracle says pass + fail = total. The `exhausted-count`
   oracle says `exhausted-count ≤ fail-count`. This means exhausted tests
   ARE counted as failed. But logically, a cell could fail its oracles on
   attempt 1 and succeed on attempt 2 — is it "passed" or "failed"? The
   counting uses final state (⊥ or not), not attempt history. A cell that
   retried and eventually passed counts as passed.

**Minor:**

8. **Empty string test case.** `{input: "", expected: ""}` — the template's
   ∴ says "Convert «text» to uppercase." With empty text, the LLM receives
   "Convert  to uppercase." The double guillemets around nothing might confuse
   the LLM. The oracle `result has same length as text` requires length 0.
   This is a legitimate edge case that tests oracle recovery on degenerate input.

9. **`oracle.failures` schema.** What data structure per failure? Just the
   constraint text? The attempted result? The attempt number? The test-report
   demands `oracle.failures history for each exhausted test`, implying a
   structured record per attempt, but the format is unspecified.

10. **Parallel execution of spawned cells.** The 4 test-run cells are
    independent. Can they execute in parallel? The program doesn't specify.
    If lazy (test-report executes them), the order depends on test-report's
    implementation. If eager (run-tests executes them), the spawner could
    parallelize. Neither is specified.



## Design Observations

### What works well

**Bottom-propagation:**
- **Separation of oracle and failure paths.** The ∴ body is happy-path only.
  The ⊥? handlers are declarative fallbacks. The LLM only runs when inputs
  are good. This is the cleanest failure handling in the Cell syntax so far.

- **Deterministic degraded output.** When parse-input fails with ⊥, the entire
  downstream path is deterministic — no LLM calls needed. The program produces
  a well-formed report explaining the failure. This is a genuine engineering
  property: graceful degradation with predictable output.

- **⊢= in format-output.** The pure computation cell remains excellent. No LLM
  involvement, no oracles to fail, just deterministic string assembly. The
  interaction with ⊥ propagation is the open question.

- **Per-edge ⊥ handlers.** Having `⊥? skip with` on individual `given` clauses
  (not on the whole cell) is more expressive than a single catch-all. Forecast
  can distinguish "parse failed" from "validation failed" and produce different
  messages for each. This is like pattern matching on failure causes.

### What needs work

- **Implicit ⊥ emission.** The program only shows explicit `error-value(⊥)` on
  parse-input. Other cells (validate, forecast) can theoretically fail but have
  no ⊥ emission mechanism. Either make implicit failure → ⊥ a language rule, or
  require every cell that might fail to declare `⊨? on exhaustion: error-value(⊥)`.

- **⊥ handler placement.** Currently at the bottom of the cell, after ∴ and ⊨.
  This means you read the happy path, then discover it might not run. Moving ⊥
  handlers adjacent to the `given` they guard would make control flow clearer:
  ```
  given parse-input→structured  ⊥? skip with validated ≡ false, ...
  given parse-input→confidence
  yield validated, warnings[]
  ∴ ...
  ```

- **Combinatorial ⊥ handlers need precedence rules.** When multiple inputs can
  be ⊥, the language needs to specify evaluation order. First-match-wins (source
  order) is simplest and most readable.

- **⊥ in crystallized computations.** Format-output's `⊢=` needs defined behavior
  when inputs contain ⊥. Options: (a) ⊥ propagates through ⊢= (the whole report
  is ⊥), (b) ⊥ stringifies as a sentinel value, (c) ⊢= cells must also have ⊥?
  handlers.

## Summary Ratings

| Element | Score | Notes |
|---------|-------|-------|
| `⊥? skip with` (cold read) | 7/10 | Intent clear, mechanics take second read |
| ⊥ propagation (readability) | 8/10 | Strong separation of oracle/failure paths |
| Per-edge handlers | 8/10 | Expressive, like failure pattern matching |
| Deterministic degraded path | 9/10 | Major design win — no LLM on failure |
| ⊥ emission mechanism | 4/10 | Only explicit on one cell, implicit rules missing |
| Combinatorial ⊥ handling | 3/10 | Undefined when multiple inputs are ⊥ |
| ⊥ in crystallized (⊢=) cells | 3/10 | Undefined behavior on ⊥ inputs |
| Traceability | 8/10 | All paths traceable, ⊥ path fully deterministic |

**Overall: 7/10** — Bottom-propagation directly addresses Round 9's biggest gap
(what happens when upstream cells fail?). The `⊥? skip with` syntax is a clean
answer for the common case. The mechanism falters on edge cases: multiple ⊥
inputs, implicit ⊥ emission, and interaction with crystallized computation. The
deterministic degraded path is the strongest design property discovered so far.

## Key Discovery: ⊥ as a Control Flow Fence

The `⊥? skip with` mechanism creates a **control flow fence** between the oracle
domain and the failure domain. Above the fence (no ⊥), cells run normally with
LLM oracle calls. Below the fence (⊥ detected), cells produce deterministic
fallback values without consulting the LLM.

This is more than error handling — it's a **mode switch**. The pipeline has two
modes: oracle mode (normal) and propagation mode (degraded). The `⊥?` syntax
marks the transition point. Once you cross the fence, you stay in propagation
mode for the rest of the pipeline.

This resembles the Railway Oriented Programming pattern (Scott Wlaschin), where
a pipeline has a "happy track" and an "error track," and once you switch to the
error track, you stay there. The Cell syntax makes this pattern explicit and
visible in the program text.

**Design implication**: If ⊥ propagation is a mode switch (not just a value),
then the language should formalize this. A cell in propagation mode doesn't run
its ∴, doesn't call oracles, and produces deterministic outputs. The `skip with`
clause defines those outputs. This is already what the program does — but it's
implicit. Making it explicit (cells have two execution modes) would resolve most
of the ambiguities identified above.

**Escalation chain:**

- **Escalation as data flow.** The most significant design choice. Escalation isn't
  an exception that unwinds the stack — it's a signal that flows through the dependency
  graph. This means the DAG itself encodes the error-handling topology. You can read
  the pipeline's failure behavior from its structure.

- **Degraded-mode propagation.** The pattern shows how a pipeline can degrade gracefully
  without aborting. downstream-consumer doesn't crash when upstream fails — it receives
  a fallback value. This is the Result/Either monad expressed as a cell pipeline.

- **⊢= audit record.** The crystallized audit-trail is excellent. Pure computation,
  no oracle needed, captures pipeline health as structured data. This is exactly what
  observability should look like in Cell.

- **Separation of concerns.** Each cell has a single job: try, catch, format, record.
  The pipeline reads as a story: attempt → handle failure → present result → log.

### What needs work

- **`given` overloading.** Using the same clause for data dependencies AND error handling
  conflates two fundamentally different relationships. Consider a separate keyword:
  `catches risky-computation ⊥` or `on-escalation risky-computation`.

- **Handler boilerplate.** The escalation-handler is a switch statement disguised as a
  cell. Consider inline recovery: `⊨? on exhaustion: yield recovery-output ← "Unable
  to complete. Reason: ..."` — keeping recovery inside the failing cell.

- **⊥ symbol collision.** R9 used ⊥ as a value (error-value(⊥)), R10 uses ⊥? as a
  control signal. These need to be explicitly distinguished or unified. Is ⊥ a value
  that a cell yields, or a signal that the runtime propagates?

- **Escalation-handler receives success data through unclear mechanism.** On the
  success path, escalation-handler passes through risky-computation's summary. But
  the only `given` clause is `given risky-computation ⊥? catch escalation`. How does
  it access the summary? Does `⊥?` implicitly provide the success value when there's
  no escalation? This dual-use is powerful but invisible.

## Overall Rating

**Escalation chain: 7/10**

The escalation → catch → degrade pattern is a genuine contribution. It shows how
Cell's dataflow model can express graceful degradation without exceptions or control
flow — escalation IS data, flowing through the DAG like any other output. The audit
crystallization is clean. The conditional oracles work.

The main weaknesses are syntactic: `given` overloading, phantom bindings, ⊥ symbol
collision with R9. These are fixable without changing the core pattern.

**Template instantiation:**

- **Templates as first-class cells.** The template is just a cell (⊢) with
  an unbound given. No new construct needed to define templates. This is
  elegant — the existing cell model stretches to cover parameterization.

- **Explicit instantiation algorithm.** The spawner's ∴ spells out copy/bind/
  preserve/name. This eliminates the ambiguity from R9 where "stamp out
  copies" was vague. A reader can predict exactly what the instantiated
  cells look like.

- **The § sigil carries its weight.** In review-all, three distinct uses of §:
  - `given §review-template` — input is a cell definition
  - `yield §reviews[]` — output is cell definitions
  - `⊨ each review has same yield signature as «§review-template»` — oracle
    compares against the template's structure

  The § consistently means "cell reference, not value." It's doing real work
  differentiating meta-level (cell definitions) from object-level (data).

- **The test cases are well-chosen.** The 3 code snippets span:
  critical (SQL injection), clean (safe Rust), minor (missing error handling).
  This exercises the full severity enum and the bidirectional oracle
  (issues[] empty iff clean). A real test of the template mechanism.

- **⊢= in triage for deterministic aggregation.** Counting is not an LLM
  task. Using ⊢= for critical-count is correct — it's a pure function over
  structured data. This continues the good pattern from R9.

**Template instantiation — what needs work:**

- **Spawner ∴ is documentation, not computation.** The copy/bind/preserve
  algorithm is deterministic. It should be marked as such — either with ⊢=
  or with a new marker indicating "this spawner's instantiation is mechanical,
  not oracle-mediated."

- **No oracle recovery on instantiated cells.** This is the third program
  in a row that creates cells with oracles but provides no ⊨? recovery path.
  The template's oracles are strict (`severity ∈ {...}` requires exact match).
  In practice, LLMs frequently violate these exact constraints. Without
  recovery, a single case-sensitivity error in one review crashes the pipeline.

- **The max/oracle contradiction needs resolution.** Either remove `max` when
  completeness is required, or weaken the oracle to `§reviews[] has length ≤
  snippets`. The current formulation is self-contradictory for inputs > 5.

- **Execution trigger is hidden in prose.** "Execute each review cell" in
  triage's ∴ is a critical runtime operation buried in natural language. Cell
  execution should be a syntactic operation, not a prose instruction. Perhaps:
  `given review-all→§reviews (execute)` or a new keyword like `invoke`.

**Oracle-retry-spawned:**

- **The test harness pattern is natural.** Template + spawner + reporter is a
  recognizable pattern from software testing. Anyone who has used parameterized
  tests (pytest, JUnit) would recognize this immediately. Cell's version adds
  oracle-based verification instead of assertions, which fits the LLM context.

- **⊢= crystallization in test-report is exactly right.** Counting pass/fail
  is a pure computation — no LLM needed. Using ⊢= for the counts and ⊨ for
  the invariants (pass + fail = total) separates concerns cleanly.

- **error-value(⊥) as containment.** The exhaustion handler yields ⊥ instead
  of crashing the pipeline. This is essential for a test harness — you want to
  report failures, not abort on them. The ⊥ value flows through the pipeline
  as data, letting test-report inspect and count it.

- **Meta-oracle on spawning.** `⊨ each test-run has same ⊨? clauses as
  §transform-template` is a structural assertion about the spawning process
  itself. This is a type-check on the runtime.

**Oracle-retry-spawned — what needs work:**

- **Inheritance semantics need formalization.** The phrase "inherits ⊨? clauses"
  is in prose. This should be a syntactic feature.

- **Oracle composition rules are missing.** When a spawned cell has both
  inherited and added oracles, the interaction rules need to be explicit.

- **Lazy vs eager execution of §-cells is ambiguous.** The program can be read
  both ways (spawner executes vs reporter executes). This is a fundamental
  execution model question.

- **Execution metadata as implicit data channel.** `test-report` queries
  execution events (`where ⊨? on exhaustion fired`), but this capability isn't
  declared. A cell's execution trace should be explicitly available (or not).

## Syntax Element Clarity: Oracle-Retry-Spawned (Cold Read)

| Element | Score | Notes |
|---------|-------|-------|
| `⊢= cases ← [...]` | 9/10 | Pure data, crystal clear |
| `§transform-template` as given | 8/10 | § as "blueprint" is intuitive |
| `⊢⊢ run-tests` spawner | 7/10 | Clear with context, glyph still arbitrary |
| `text ≡ case.input` binding | 8/10 | ≡ as "bind to" reads naturally |
| `⊨? on failure: retry...` | 7/10 | Intent clear, mechanics uncertain |
| `⊨? on exhaustion: error-value(⊥)` | 7/10 | Terminal-but-not-crashing is clear |
| `oracle.failures` accumulation | 6/10 | Implicit schema, implicit scoping |
| `⊨ result = case.expected` (added oracle) | 8/10 | Clean parameterized assertion |
| `where ⊨? on exhaustion fired` (in ⊢=) | 5/10 | Event query in value expression — surprising |
| Inherited ⊨? clauses | 6/10 | Prose, not syntax |

**Average: 7.1/10**

## Rating: Oracle-Retry-Spawned

**Oracle-retry on spawned cells: 7/10**

The program successfully demonstrates the composition of three previously
independent features (spawning, oracle recovery, template instantiation) into
a coherent test harness. The pattern is immediately recognizable and the
intent reads clearly from cold.

The main weakness is that the *composition rules* are underspecified. Each
feature works individually (spawning from R9, ⊨? from R8, ⊢= from earlier),
but their interaction — oracle composition, inheritance semantics, execution
metadata flow — is left to prose and implication.

## Key Discovery: The Execution Metadata Problem

This program reveals a fundamental tension in Cell's design. Cells communicate
through two channels:

1. **Value channel**: yields (result, pass-count, etc.) — explicit, typed, declared
2. **Metadata channel**: execution events (oracle.failures, exhaustion status) — implicit, untyped, undeclared

The test-report cell reads BOTH channels. Its ⊢= expressions query values
(`result = ⊥`) AND events (`⊨? on exhaustion fired`). But only the value channel
is declared in the cell's `given`/`yield` signature.

This means Cell has a hidden data flow that bypasses the formal dataflow graph.
Two design paths:

1. **Make metadata explicit.** Add `yield.meta` or similar: cells declare what
   execution metadata they expose.

2. **Keep metadata implicit but scoped.** Only cells that receive §-references
   (cell handles, not values) can query execution metadata. The § prefix grants
   metadata access.

## Summary Ratings: Template Instantiation

| Element | Score | Notes |
|---------|-------|-------|
| Template as cell (⊢ with unbound given) | 9/10 | Elegant reuse of existing construct |
| § copy mechanism | 7/10 | Sound for simple case, underspecified for complex |
| Explicit instantiation algorithm in ∴ | 8/10 | Major clarity improvement over R9 |
| ≡ binding operator | 9/10 | Natural mathematical notation |
| Spawner (⊢⊢) reuse from R9 | 8/10 | Consistent, proven construct |
| Oracle inheritance | 6/10 | Works but propagation/layering unspecified |
| Execution model | 5/10 | Who runs the instances? When? How? |
| max/oracle interaction | 4/10 | Contradictory — needs design resolution |

**Overall: 8/10** — This is the most readable Cell program to date. The
template instantiation mechanism is well-motivated (code review is a natural
map-over-list pattern), the § copy algorithm is explicitly documented, and the
test data exercises the mechanism thoroughly. The main gaps are the execution
model (who triggers instantiated cells?) and oracle failure propagation (still
unresolved from R9). The max/oracle contradiction is a design bug that needs
fixing.

## Key Discovery: Templates Collapse Spawning to Map

The template-instantiation pattern reduces `⊢⊢` from a general spawner to a
specific operation: **map a template over a list**. This is:

```
review-all = map(review-template, code-samples→snippets)
```

This is dramatically simpler than R9's spawners, which had recursive depth,
branching, and follow-up generation. Template instantiation is a *restricted*
form of spawning that trades power for clarity:

| | R9 spawner | R10 template instantiation |
|---|---|---|
| Input | Follow-ups (recursive) | Flat list (non-recursive) |
| Depth | Multi-level (until depth > N) | Single level (1:1 map) |
| Output | Varying cell structure | Uniform cell structure |
| Termination | Requires depth + max guards | Trivially bounded by list length |

This suggests a design split:
- **⊢⊢-map** (template instantiation): `given §template, given list → yield §instances[]`
  — simple, predictable, one level deep
- **⊢⊢-tree** (recursive spawning): `given §template, until/max → yield §tree`
  — powerful, needs termination proofs, multi-level

The current syntax conflates both under ⊢⊢. Distinguishing them would reduce
ambiguity considerably.

## Cumulative Scores (all rounds)
- § quoting: 100% comprehension, universally natural
- ⊢= crystallization: 8/10
- ⊢∘ evolution loop: 8/10
- Proof-carrying computation: 9/10
- eval-one metacircular: 9/10
- Self-crystallization: 9/10
- Cell-as-agent: 8/10
- Oracle failure recovery ⊨?: 7/10
- Frontier growth: 6/10 (syntax gap — Round 8)
- Oracle cascade: 7/10 (solid pattern, ⊥ propagation gap)
- Spawner-halting (⊢⊢ + until + max): 7/10 (addresses frontier gap, oracle story missing)
- Spawner-oracle composition: 7/10 (clean pipeline, oracle propagation gap)
- **Bottom-propagation (⊥? skip with): 7/10** (addresses ⊥ gap, combinatorial cases undefined)
- **Escalation chain (⊥? catch + degrade): 7/10** (genuine pattern, `given` overloading)
- **Template instantiation: 8/10** (clearest program yet, execution model gap)
- **Oracle-retry-spawned: 7/10** (features compose, interaction rules underspecified)
