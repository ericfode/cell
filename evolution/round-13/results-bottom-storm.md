# Round 13 Results: t3-bottom-storm — Bottom Propagation Storm (Cold Read)

**Polecat**: thunder | **Date**: 2026-03-10 | **Rating**: 8/10

## Program Overview

7 cells. One deliberate ⊥ source (`source`) fans out to 6 downstream cells with
**mixed** bottom handlers: 2 cells have `⊥? skip with` (summarize, score), 1 has
`partial-accept` (critique), 2 have **no handler** (translate), 1 has `⊥? skip with`
on some inputs (fact-check), and a final `digest` cell that aggregates everything with
its own `⊥? skip with` handlers.

The topology is a **fan-out DAG** with a single root:

```
              source (⊥ origin)
         ┌───┬───┼───┬───┐
         ▼   ▼   ▼   ▼   ▼
    summarize score critique translate fact-check
         │    │    │     │  │     │  │
         └────┴────┴─────┴──┴─────┴──┘
                     ▼
                   digest
```

The core question: **when `source` produces ⊥, which downstream cells survive,
which crash, and what does `digest` ultimately see?**

---

## Q1: Step-by-Step Execution

### Execution Order (Kahn's algorithm)

All five downstream cells depend only on `source`, so after `source` completes,
they are all ready simultaneously. Kahn's can schedule them in any order. `digest`
depends on all five, so it runs last.

**Topological order**: `source` → {`summarize`, `score`, `critique`, `translate`, `fact-check`} → `digest`

### Path A: Happy Path (source succeeds)

#### Cell: `source`

**Input**: `query ≡ "Explain quantum gravity in exactly 3 words"`

**LLM call**: Must produce a 3-word answer about quantum gravity without using
"quantum" or "gravity". This is genuinely hard — the constraint is intentionally
adversarial.

**Plausible LLM output**: `answer ≡ "spacetime curves everything"`, `confidence ≡ 35`

**Oracle checks**:
| Oracle | Result | Reasoning |
|--------|--------|-----------|
| `answer is exactly 3 words` | PASS | "spacetime curves everything" = 3 words |
| `confidence ∈ [0, 100]` | PASS | 35 ∈ [0, 100] |
| `answer does not contain "quantum" or "gravity"` | PASS | Neither word appears |

**State after**: `{answer: "spacetime curves everything", confidence: 35}`

#### Cell: `summarize` (⊥? skip with handler — inactive in happy path)

**Input**: `source→answer = "spacetime curves everything"`

**LLM call**: Write a one-sentence summary expanding on "spacetime curves everything".

**Plausible output**: `summary ≡ "The phrase 'spacetime curves everything' captures the general-relativistic principle that mass and energy warp the fabric of spacetime, affecting the motion of all objects."`

**Oracle checks**:
| Oracle | Result | Reasoning |
|--------|--------|-----------|
| `summary is exactly one sentence` | PASS | One sentence (starts with "The", ends with ".") |
| `summary is between 10 and 50 words` | PASS | ~30 words |

**State after**: `{summary: "The phrase 'spacetime curves everything'..."}`

#### Cell: `score` (⊢= crystallized, ⊥? skip with handler — inactive)

**Input**: `source→confidence = 35`

**Crystallized computation** (no LLM call):
```
grade ← if 35 ≥ 80 → no; if 35 ≥ 60 → no; if 35 ≥ 40 → no; else "F"
grade ≡ "F"
pass ← 35 ≥ 60 = false
pass ≡ false
```

**Oracle checks**:
| Oracle | Result | Reasoning |
|--------|--------|-----------|
| `grade ∈ ["A", "B", "C", "F"]` | PASS | "F" is in the set |
| `pass = true ↔ grade ∈ ["A", "B"]` | PASS | pass=false ↔ grade="F" (not in ["A","B"]) |

**State after**: `{grade: "F", pass: false}`

#### Cell: `critique` (⊨? partial-accept — no ⊥? handler)

**Inputs**: `source→answer = "spacetime curves everything"`, `source→confidence = 35`

**LLM call**: Critique the answer with confidence 35.

**Plausible output**: `criticism ≡ "The phrase oversimplifies by implying spacetime itself is the active agent — in general relativity, matter tells spacetime how to curve, not the reverse."`

**Oracle checks**:
| Oracle | Result | Reasoning |
|--------|--------|-----------|
| `criticism is 1-2 sentences` | PASS | One sentence |
| `criticism identifies a specific weakness` | PASS | Identifies directionality error |

**State after**: `{criticism: "The phrase oversimplifies..."}`

#### Cell: `translate` (NO ⊥? handler)

**Input**: `source→answer = "spacetime curves everything"`

**LLM call**: Translate to Spanish and French.

**Plausible output**:
- `spanish ≡ "el espaciotiempo lo curva todo"`
- `french ≡ "l'espace-temps courbe tout"`

**Oracle checks**:
| Oracle | Result | Reasoning |
|--------|--------|-----------|
| `spanish is not English` | PASS | Spanish text |
| `french is not English` | PASS | French text |
| `spanish ≠ french` | PASS | Different languages |

**State after**: `{spanish: "el espaciotiempo lo curva todo", french: "l'espace-temps courbe tout"}`

#### Cell: `fact-check` (⊥? skip with on both inputs)

**Inputs**: `source→answer = "spacetime curves everything"`, `source→confidence = 35`

**LLM call**: Fact-check scientific defensibility.

**Plausible output**: `verdict ≡ "PLAUSIBLE"`, `evidence ≡ "Einstein's field equations describe how mass-energy curves spacetime geometry, which in turn governs motion — consistent with the claim."`

**Oracle checks**:
| Oracle | Result | Reasoning |
|--------|--------|-----------|
| `verdict ∈ ["PLAUSIBLE", "DUBIOUS", "WRONG"]` | PASS | "PLAUSIBLE" |
| `evidence is one sentence citing a specific fact` | PASS | Cites Einstein's field equations |

**State after**: `{verdict: "PLAUSIBLE", evidence: "Einstein's field equations..."}`

#### Cell: `digest` (⊢= with ⊥? handlers — inactive in happy path)

**Inputs**: All six dependencies are bound (no ⊥).

**Crystallized computation** (no LLM call):
```
report ← "## Bottom Storm Report\n\n" ++
  "**Summary:** The phrase 'spacetime curves everything'...\n" ++
  "**Grade:** F (pass: false)\n" ++
  "**Critique:** The phrase oversimplifies...\n" ++
  "**Translations:** ES=el espaciotiempo lo curva todo / FR=l'espace-temps courbe tout\n" ++
  "**Fact-check:** PLAUSIBLE — Einstein's field equations...\n"
```

**Oracle checks**:
| Oracle | Result | Reasoning |
|--------|--------|-----------|
| `report contains "Bottom Storm Report"` | PASS | Header present |
| `report contains grade and verdict` | PASS | Contains "F" and "PLAUSIBLE" |

**Final output**: Complete report with all sections populated.

---

### Path B: ⊥ Storm (source fails — THE INTERESTING CASE)

The third oracle (`answer does not contain "quantum" or "gravity"`) is the most
likely failure point. An LLM answering about quantum gravity will instinctively
use those words. After 1 retry, exhaustion triggers `error-value(⊥)`.

**source produces**: `answer ≡ ⊥`, `confidence ≡ ⊥`

Now the storm begins. Each downstream cell receives ⊥ on one or both inputs.

#### Cell: `summarize` — HAS ⊥? handler

`given source→answer ⊥?` → **TRIGGERS**

`skip with summary ≡ "Source failed; no answer to summarize."`

**No LLM call.** No oracles fire. The cell produces a valid fallback.

**State**: `{summary: "Source failed; no answer to summarize."}`

**Cost**: 0 LLM calls. Graceful degradation.

#### Cell: `score` — HAS ⊥? handler (⊢= cell)

`given source→confidence ⊥?` → **TRIGGERS**

`skip with grade ≡ "X", pass ≡ false`

**No computation** (⊢= body skipped entirely). No oracles fire.

**State**: `{grade: "X", pass: false}`

**Cost**: 0 LLM calls. Graceful degradation.

**Note**: The fallback value `grade ≡ "X"` is NOT in the oracle's valid set
`["A", "B", "C", "F"]`. This is correct — oracles don't fire on skip-with values
(R11 finding #4). But if an oracle DID fire, it would FAIL. This surfaces the
tension: skip-with values live outside the oracle contract.

#### Cell: `critique` — NO ⊥? handler on either input

`source→answer ≡ ⊥` — no `⊥?` handler declared for this dependency.
`source→confidence ≡ ⊥` — no `⊥?` handler declared for this dependency.

**⊥ PROPAGATES.** The cell cannot execute because its inputs are ⊥.

`critique→criticism ≡ ⊥`

**Cost**: 0 LLM calls. Unhandled bottom — the cell never fires.

**The key question**: What does ⊥ propagation look like for a cell with NO handler?
Three possible semantics:
1. **Silent skip**: All yields become ⊥. The cell is treated as if it never existed.
2. **Error**: Runtime raises an error — unhandled ⊥ is a program bug.
3. **Spec gap**: The Cell spec doesn't define this case.

**I execute option 1** (silent skip) because it's consistent with the overall ⊥
propagation philosophy: ⊥ flows through the DAG until caught. An uncaught ⊥
just keeps flowing. This is the "bottom storm" — ⊥ is wind, handlers are
windbreaks. No windbreak = ⊥ passes through.

#### Cell: `translate` — NO ⊥? handler

`source→answer ≡ ⊥` — no handler.

**⊥ PROPAGATES.** Both outputs become ⊥.

`translate→spanish ≡ ⊥`, `translate→french ≡ ⊥`

**Cost**: 0 LLM calls.

**This is the harshest casualty.** `translate` has NO mechanism to handle ⊥.
In a real system, you'd want at least a fallback: "Translation unavailable."
The program intentionally omits this to test the unhandled case.

#### Cell: `fact-check` — HAS ⊥? handler on BOTH inputs

`given source→answer ⊥?` → **TRIGGERS** first handler:
`skip with verdict ≡ "N/A", evidence ≡ "Source produced no answer."`

Since the first `⊥?` already fired, the cell is already skipped. The second
handler (`given source→confidence ⊥?`) is moot — the cell already has its
skip-with values.

**State**: `{verdict: "N/A", evidence: "Source produced no answer."}`

**Cost**: 0 LLM calls. Graceful degradation.

**Semantic question**: If both inputs are ⊥, and there are two `⊥?` handlers,
which one fires? I execute "first match wins" — the first `given ... ⊥?` that
matches takes effect. This is unspecified in the Cell syntax.

#### Cell: `digest` — HAS ⊥? handlers on most inputs

Now `digest` receives:
- `summarize→summary = "Source failed; no answer to summarize."` (NOT ⊥ — handler caught it)
- `score→grade = "X"`, `score→pass = false` (NOT ⊥ — handler caught it)
- `critique→criticism = ⊥` (UNHANDLED — no handler in critique)
- `translate→spanish = ⊥` (UNHANDLED — no handler in translate)
- `translate→french = ⊥` (UNHANDLED — no handler in translate)
- `fact-check→verdict = "N/A"` (NOT ⊥ — handler caught it)
- `fact-check→evidence = "Source produced no answer."` (NOT ⊥ — handler caught it)

**Which ⊥? handlers fire in digest?**

`digest` has `⊥?` handlers for: `summarize→summary`, `critique→criticism`,
`translate→spanish`, `translate→french`, `fact-check→verdict`.

Of these, the ⊥ values are: `critique→criticism`, `translate→spanish`, `translate→french`.

All three have handlers in `digest`. **The first matching ⊥? fires:**

`given critique→criticism ⊥?` → TRIGGERS:
`skip with report ≡ "## Bottom Storm Report\n\n⊥ propagation reached digest — upstream failures."`

**Digest skips its ⊢= body entirely.** The report is the fallback string.

**Note**: Even though `summarize`, `score`, and `fact-check` successfully caught ⊥
with their handlers and produced valid values, those values are **never used** because
`digest` itself got hit by the critique and translate ⊥ values. The handlers in the
middle layer caught some ⊥, but the unhandled ones (`critique`, `translate`) punched
through to the final cell and triggered its fallback.

**This is the "storm" pattern**: One ⊥ at the source creates a cascade where
handlers at different layers catch different branches, but any single unhandled
branch can poison the final output.

---

### Path B Summary: The ⊥ Propagation Map

```
source → ⊥
  ├─→ summarize:  CAUGHT (⊥? skip with) → "Source failed..."
  ├─→ score:      CAUGHT (⊥? skip with) → grade="X", pass=false
  ├─→ critique:   UNHANDLED → ⊥ propagates
  ├─→ translate:  UNHANDLED → ⊥ propagates (both outputs)
  └─→ fact-check: CAUGHT (⊥? skip with) → verdict="N/A"

digest inputs:
  summarize→summary     = "Source failed..."  ← OK (caught upstream)
  score→grade           = "X"                 ← OK (caught upstream)
  score→pass            = false               ← OK (caught upstream)
  critique→criticism    = ⊥                   ← BOTTOM (uncaught)
  translate→spanish     = ⊥                   ← BOTTOM (uncaught)
  translate→french      = ⊥                   ← BOTTOM (uncaught)
  fact-check→verdict    = "N/A"               ← OK (caught upstream)
  fact-check→evidence   = "Source produced..." ← OK (caught upstream)

digest: ⊥? handler fires → fallback report
```

**Result**: 3/5 downstream cells gracefully degraded. 2/5 propagated ⊥. The
final `digest` cell's fallback activates because the uncaught ⊥ from critique
and translate reaches it. The storm is partially contained but not fully stopped.

---

## Q2: Which cells crystallize? Which must stay soft? Why?

| Cell | Type | Crystallizes? | Reason |
|------|------|---------------|--------|
| `source` | ⊢ | **No** | LLM must generate a creative 3-word answer. Inherently non-deterministic. |
| `summarize` | ⊢ | **No** | LLM expands a phrase into a sentence. No deterministic function for this. |
| `score` | ⊢= | **Yes — fully crystallized** | Pure conditional arithmetic on `confidence`. No LLM involvement. |
| `critique` | ⊢ | **No** | LLM identifies a specific weakness. Requires judgment. |
| `translate` | ⊢ | **No** | Translation requires LLM. (Could theoretically use a deterministic translation API, but as modeled it's soft.) |
| `fact-check` | ⊢ | **No** | Scientific fact-checking requires LLM judgment. |
| `digest` | ⊢= | **Yes — fully crystallized** | Pure string concatenation. All inputs are strings; the formula is deterministic. |

**Key insight**: Only `score` and `digest` crystallize. Both are ⊢= cells —
pure computation over their inputs. The remaining 5 cells all require LLM calls.
This is a much higher soft-to-crystal ratio (5:2) than word-life's (3:2),
reflecting the fan-out architecture where each branch requires independent judgment.

**Crystallization of ⊥? handlers**: The skip-with values in `summarize`, `score`,
`fact-check`, and `digest` are themselves crystallized — they're literal constants.
So ⊥ handling is always deterministic, even when the cell's normal path is soft.
This is a nice property: error recovery is always cheap and predictable.

---

## Q3: Oracle Check Trace (Complete)

### Happy Path Oracle Trace

| # | Cell | Oracle | Result | Reasoning |
|---|------|--------|--------|-----------|
| 1 | source | `answer is exactly 3 words` | PASS | "spacetime curves everything" = 3 words |
| 2 | source | `confidence ∈ [0, 100]` | PASS | 35 ∈ [0, 100] |
| 3 | source | `answer does not contain "quantum" or "gravity"` | PASS | Neither word present |
| 4 | summarize | `summary is exactly one sentence` | PASS | Ends with period, no internal sentence breaks |
| 5 | summarize | `summary is between 10 and 50 words` | PASS | ~30 words |
| 6 | score | `grade ∈ ["A", "B", "C", "F"]` | PASS | "F" is in set |
| 7 | score | `pass = true ↔ grade ∈ ["A", "B"]` | PASS | false ↔ "F" ∉ {"A","B"} |
| 8 | critique | `criticism is 1-2 sentences` | PASS | One sentence |
| 9 | critique | `criticism identifies a specific weakness` | PASS | Names directionality issue |
| 10 | translate | `spanish is not English` | PASS | Spanish text |
| 11 | translate | `french is not English` | PASS | French text |
| 12 | translate | `spanish ≠ french` | PASS | Different languages |
| 13 | fact-check | `verdict ∈ [PLAUSIBLE, DUBIOUS, WRONG]` | PASS | "PLAUSIBLE" |
| 14 | fact-check | `evidence cites a specific fact` | PASS | Cites Einstein's field equations |
| 15 | digest | `report contains "Bottom Storm Report"` | PASS | Header present |
| 16 | digest | `report contains grade and verdict` | PASS | "F" and "PLAUSIBLE" present |

**Total: 16 oracle checks, all PASS.**

### ⊥ Path Oracle Trace

When `source` produces ⊥, NO downstream oracles fire. All cells either:
- Fire their `⊥? skip with` (bypassing oracles), or
- Propagate ⊥ silently (no execution, no oracles)

**Total in ⊥ path**: 3 oracle checks (source's initial attempt + 1 retry attempt = 6,
but after exhaustion, 0 downstream). Actually: source fires oracles on its first
attempt (some FAIL), retries once (oracles FAIL again), then exhausts → ⊥.

**Source oracle trace in ⊥ path**:

Attempt 1:
| Oracle | Result | Reasoning |
|--------|--------|-----------|
| `answer is exactly 3 words` | ??? | Depends on LLM output |
| `confidence ∈ [0, 100]` | ??? | Depends on LLM output |
| `answer does not contain "quantum" or "gravity"` | **FAIL** (likely) | LLM likely says "quantum gravity unifies" |

Retry (attempt 2, with `«oracle.failures»` appended):
| Oracle | Result | Reasoning |
|--------|--------|-----------|
| `answer does not contain "quantum" or "gravity"` | **FAIL** (possible) | Even with the hint, LLM may still use these words |

Exhaustion → `error-value(⊥)`.

**Downstream**: 0 oracle checks. All skipped or propagated.

**Total in ⊥ path**: 6 oracle checks on source (3 per attempt × 2 attempts), 0 downstream.

---

## Q4: LLM Call Count

### Happy Path

| Cell | LLM Calls | Notes |
|------|-----------|-------|
| source | 1 | One generation attempt |
| summarize | 1 | One sentence expansion |
| score | 0 | ⊢= crystallized |
| critique | 1 | One critique (+ potential retry via partial-accept) |
| translate | 1 | One translation call (both languages) |
| fact-check | 1 | One fact-check |
| digest | 0 | ⊢= crystallized |
| **Total** | **5** | |

**Minimum**: 5 LLM calls (no retries needed).

**Maximum**: 5 + 2 (source retries) + 2 (critique retries) = 9 LLM calls.
But source retries → ⊥ path, which eliminates downstream calls. So max in
happy path is 5 + 2 (critique partial-accept retries) = 7.

### ⊥ Path

| Cell | LLM Calls | Notes |
|------|-----------|-------|
| source | 2 | Initial + 1 retry, then ⊥ |
| summarize | 0 | ⊥? handler, no LLM |
| score | 0 | ⊥? handler, no LLM |
| critique | 0 | ⊥ propagates, no LLM |
| translate | 0 | ⊥ propagates, no LLM |
| fact-check | 0 | ⊥? handler, no LLM |
| digest | 0 | ⊥? handler, no LLM |
| **Total** | **2** | |

**This confirms R11 finding #6: "Exhaustion is cheaper than late success."**
The ⊥ path costs 2 LLM calls total. The happy path costs 5-7. Bottom propagation
converts 5 downstream LLM calls into 0 — they become free deterministic skip-with
operations.

---

## Q5: Program Clarity Rating

**Rating: 8/10**

**Strengths**:
- The fan-out topology is immediately clear from the `given` declarations
- Mixed handlers create a natural "defense in depth" pattern — easy to see
  which cells are protected and which are exposed
- The ⊥ propagation story is readable: follow each `given ... ⊥?` to trace survival
- `score` as ⊢= is clean — the if/else chain is unambiguous
- `digest` as ⊢= with string concatenation is the right choice — no LLM needed for assembly
- The adversarial oracle on `source` (no "quantum" or "gravity") is clever —
  it makes ⊥ genuinely likely, not just a theoretical possibility

**Weaknesses**:
- `digest` has 5 separate `⊥?` handlers, all producing the same fallback string.
  This is verbose. A single "any input ⊥?" handler would be cleaner.
- The `critique` cell lacks a `⊥?` handler with no obvious reason. Is this
  intentional (to test unhandled ⊥) or a bug? The program's intent is ambiguous.
- Same for `translate` — no handler. Two cells without handlers feels like either
  a design choice or two bugs. The program should signal which.
- `fact-check` has two `⊥?` handlers for two inputs that will always be ⊥ together
  (both come from `source`). The second handler is dead code in practice.
- The `score` fallback `grade ≡ "X"` violates the oracle contract `grade ∈ ["A","B","C","F"]`.
  This surfaces the skip-with-vs-oracle tension but may confuse a maintainer.

**Could I maintain this?** Yes. The fan-out structure is simple, and the
mixed-handler pattern is the most interesting part. A maintainer would need to
understand ⊥ propagation semantics, but the program teaches that by example.

---

## Q6: Fragility Analysis (What breaks if you remove each cell?)

| Removed Cell | Impact | Severity |
|-------------|--------|----------|
| `source` | **Total failure.** All 5 downstream cells have unbound inputs. Nothing executes. | CRITICAL |
| `summarize` | `digest` loses summary input. If `summarize→summary` is ⊥, `digest`'s first `⊥?` handler fires → fallback report. Or if no implicit ⊥, `digest` can't compute `report`. Either way, `digest` degrades. Other cells unaffected. | LOW |
| `score` | `digest` loses grade and pass inputs. `digest` has no `⊥?` handler for `score→grade` or `score→pass`. **Unhandled ⊥ in digest** — but `score` has no `⊥?` handler on its own input either. Wait — `score` DOES have a `⊥?` handler. If `score` is removed entirely, `digest` gets ⊥ for `score→grade` and `score→pass`, which have no handlers in `digest`. **`digest` can't execute.** Actually, `digest` is ⊢= — it concatenates all inputs. If `score→grade` is undefined (cell removed), the ⊢= formula fails. | MEDIUM |
| `critique` | `digest` loses criticism input. `digest` has a `⊥?` handler for `critique→criticism` → fallback report fires. Other cells unaffected. | LOW |
| `translate` | `digest` loses spanish and french. `digest` has `⊥?` handlers for both → fallback fires. Other cells unaffected. | LOW |
| `fact-check` | `digest` loses verdict and evidence. `digest` has `⊥?` handler for verdict → fallback fires. | LOW |
| `digest` | All upstream cells execute normally but their results are never assembled. The program produces 5 independent outputs instead of one report. Data exists, no synthesis. | LOW |

**Fragility gradient**: source >>> score > everything else

**Key finding**: `source` is the single point of failure — appropriate for a
program designed to test fan-out from a single ⊥ origin. The fan-out cells
themselves are surprisingly resilient to removal because `digest` has `⊥?`
handlers for most inputs. The program is **fragile at the root, resilient at
the leaves** — the inverse of word-life's loop structure where every loop cell
is critical.

---

## Q7: Trust Boundaries

| Cell | Trust Level | Reasoning |
|------|-------------|-----------|
| `source` | **Must be verified — actively adversarial** | The oracle set is designed to make the LLM fail. The "no quantum/gravity" constraint is a trap. This is the least trusted cell in the program. |
| `summarize` | **Must be verified** | LLM expansion of an arbitrary phrase. Oracle checks basic structure (length, sentence count) but not semantic accuracy. |
| `score` | **Trusted (⊢=)** | Pure conditional arithmetic. The if/else chain is deterministic and verifiable by inspection. |
| `critique` | **Must be verified, lowest oracle quality** | The oracle "identifies a specific weakness (not a generic disclaimer)" is subjective — what counts as "specific" vs "generic"? This is the hardest oracle to evaluate. |
| `translate` | **Must be verified** | Translation quality is hard to oracle-check. "Is not English" is a very weak check — gibberish would pass. "spanish ≠ french" prevents copying but doesn't verify accuracy. |
| `fact-check` | **Must be verified** | Scientific fact-checking is inherently uncertain. "PLAUSIBLE" vs "DUBIOUS" is a judgment call. The evidence oracle ("cites a specific fact") is decent but doesn't verify the fact is correct. |
| `digest` | **Trusted (⊢=)** | Pure string concatenation. Deterministic. |

### Trust Boundary Map

```
TRUSTED                    MUST VERIFY                 ADVERSARIAL
┌──────────┐              ┌──────────────┐            ┌───────────┐
│ score    │              │ summarize    │            │ source    │
│ (⊢= arith)│             │ (LLM expand) │            │ (trap     │
│          │              │              │            │  oracle)  │
│ digest   │              │ critique     │            └───────────┘
│ (⊢= concat)│            │ (subjective) │
│          │              │              │
│          │              │ translate    │
│          │              │ (weak oracle)│
│          │              │              │
│          │              │ fact-check   │
│          │              │ (uncertain)  │
└──────────┘              └──────────────┘
```

**Critical gap**: `translate`'s oracles are the weakest in the program. "Is not English"
can be satisfied by any non-English text, including incorrect translations, random
words, or other languages entirely. A stronger oracle would require a back-translation
check or a second LLM as judge.

---

## Confidence Rating

**Confidence: 8/10**

High confidence in the execution trace and the ⊥ propagation map. The fan-out
topology is simple and deterministic once you know each cell's handler status.

**Uncertainty sources**:
1. Whether `source` actually fails — the LLM might find a valid 3-word answer that
   avoids "quantum" and "gravity" (e.g., "spacetime curves everything"). In that case,
   the ⊥ storm never happens and it's just a normal fan-out program.
2. The semantics of unhandled ⊥ in cells without `⊥?` handlers — I assumed "silent
   skip to ⊥" but the spec could define it differently (runtime error, explicit ⊥
   declaration required, etc.).
3. Multiple `⊥?` handlers on the same cell — I assumed "first match wins" but the
   spec doesn't define priority ordering.
4. Whether oracles fire on skip-with values — I assumed no (per R11 finding #4),
   but the spec is silent on this.

---

## Friction Points

### 1. Unhandled ⊥ Semantics (MAJOR — spec gap)

When a cell receives ⊥ on an input and has NO `⊥?` handler, what happens? Three
possible answers:

| Option | Behavior | Implication |
|--------|----------|-------------|
| Silent propagation | All yields become ⊥ | ⊥ flows freely through the DAG |
| Runtime error | Program halts with "unhandled bottom" | Forces explicit error handling everywhere |
| Compile-time error | Program rejected if any ⊥-producing path lacks handlers | Safest but most restrictive |

This program tests option 1 (silent propagation) by intentionally omitting handlers
on `critique` and `translate`. The spec should define which option applies.

**Recommendation**: Option 1 (silent propagation) with an optional `⊥!` annotation
that marks a cell as "must handle" — a compile-time check that all ⊥-producing
inputs have handlers.

### 2. Multiple ⊥? Handler Priority (MEDIUM — spec gap)

`fact-check` has two `⊥?` handlers. `digest` has five. When multiple inputs are ⊥
simultaneously, which handler wins?

Options:
- **First match** (textual order): Simple, predictable, what I executed
- **Most specific** (deepest in the dependency chain): Complex, may not always have a clear winner
- **All match** (handlers compose): Would need a merging strategy for conflicting skip-with values

**Recommendation**: First match (textual order). Simple, deterministic, easy to reason about.

### 3. Dead ⊥? Handlers (MINOR — design smell)

`fact-check`'s second handler (`given source→confidence ⊥?`) can never independently
fire — whenever `source→confidence ≡ ⊥`, `source→answer ≡ ⊥` too (they come from the
same cell). The first handler always fires first. This is dead code.

A linter could warn: "⊥? handler for `source→confidence` is unreachable because
`source→answer` is always ⊥ when `source→confidence` is ⊥ (same source cell)."

### 4. Redundant Digest Handlers (MINOR — verbosity)

All five `⊥?` handlers in `digest` produce the same fallback string. This violates
DRY. A single "catch-all" handler would be cleaner:

```
⊥? on any: skip with report ≡ "## Bottom Storm Report\n\n⊥ propagation reached digest."
```

The spec doesn't have catch-all `⊥?` syntax. Adding it would reduce boilerplate
in fan-in cells that aggregate many potentially-⊥ inputs.

### 5. Skip-With vs Oracle Contract (MEDIUM — tension identified)

`score` has `grade ∈ ["A", "B", "C", "F"]` as an oracle, but its `⊥?` handler
sets `grade ≡ "X"`. This violates the oracle contract. This is intentional (per
R11: oracles don't fire on skip-with values), but it means:

- The oracle contract describes the HAPPY PATH type
- Skip-with values can have a DIFFERENT type
- A type-checker analyzing the program would need to know that ⊥? skip-with
  values bypass oracle constraints

This is a feature, not a bug — but it should be documented.

---

## Specific Recommendations for Cell v0.1 Spec

### From This Program

1. **Define unhandled ⊥ semantics** — What happens when a cell receives ⊥ with
   no `⊥?` handler? This is the most important spec gap this program surfaces.
   Recommend: silent propagation (yields become ⊥) with optional `⊥!` annotation.

2. **Define ⊥? handler priority** — When multiple inputs are ⊥, which `⊥?` fires?
   Recommend: first match in textual order.

3. **Add catch-all ⊥? syntax** — `⊥? on any:` for cells with many ⊥-producing inputs.
   Reduces boilerplate in fan-in aggregation cells.

4. **Warn on dead ⊥? handlers** — When two inputs always fail together (same source
   cell), the second handler is unreachable. A linter should flag this.

### Confirming Prior Findings

5. **Oracle bypass on skip-with confirmed** (R11 #4) — `score`'s `grade ≡ "X"` would
   fail the `grade ∈ ["A","B","C","F"]` oracle. Skip-with MUST bypass oracles.

6. **⊥ propagation cost advantage confirmed** (R11 #6) — ⊥ path costs 2 LLM calls
   vs happy path's 5-7. Bottom is cheap.

7. **Tautological oracle pattern** (R11 #2) — `score`'s `grade ∈ [...]` oracle on a
   ⊢= cell can never fail if the if/else chain is correct. This is an assertion, not
   a constraint. Less prevalent here than in word-life (1 tautological vs 4).
