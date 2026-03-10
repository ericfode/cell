# Round 10 Results: Bottom-Propagation

## Mode: COLD READ (no syntax reference)

## The Program

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

## Design Observations

### What works well

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
