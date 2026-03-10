# Round 12 Results: T4 — Self-Improving Compiler

## Mode: COLD READ (no syntax reference)

## The Program

A metacircular Cell compiler: a Cell program that reads a Cell program (itself
embedded as a quoted structure `§`), parses it into an AST, analyzes it for
optimizations, applies transformations, emits improved Cell, and verifies the
roundtrip. Eight top-level cells forming a pipeline with rich `⊥` propagation
throughout.

**Architecture (8 cells):**

```
source-program → parse → analyze → transform-crystallize → transform-add-handlers → emit → verify-roundtrip → meta-report
```

The input program (`§source`) is a simple 3-cell greeting pipeline:
`greet → respond → log`.

---

## Evaluation Questions

### 1. Execute the program step-by-step. Show all intermediate states.

**Cell 1: `source-program` (⊢, crystallized yield)**

```
source-program:
  Type: ⊢ with ⊢= yield
  Input: none (root cell)
  Action: yields §source as a quoted Cell program literal
  §source = the embedded 3-cell program (greet, respond, log)

  This is a ⊢= in disguise — the yield is a static quoted structure.
  No LLM needed. Pure data.

  Output: §source = §(⊢ greet ..., ⊢ respond ..., ⊢ log ...)
```

**Cell 2: `parse` (⊢, LLM-required)**

```
parse:
  Input: source-program→§source (the quoted Cell program)
  LLM task: Parse §source into an AST with nodes for each cell,
            count cells, extract dependency edges

  Expected output:
    ast = [
      {name: "greet", type: ⊢, givens: [name], yields: [message],
       body: "Write a greeting...", oracles: [mentions name, 1-2 sentences]},
      {name: "respond", type: ⊢, givens: [greet→message, tone≡"formal"],
       yields: [reply], body: "Write a «tone» reply...",
       oracles: [reply matches tone]},
      {name: "log", type: ⊢=, givens: [greet→message, respond→reply],
       yields: [entry], body: "{timestamp: now(), input: message, output: reply}",
       oracles: []}
    ]
    cell-count = 3 (computed via ⊢= — no LLM)
    dependency-edges = [
      {from: "greet", to: "respond", field: "message"},
      {from: "greet", to: "log", field: "message"},
      {from: "respond", to: "log", field: "reply"}
    ]

  Oracle checks:
    ⊨ cell-count = 3                                    → PASS (3 cells: greet, respond, log)
    ⊨ edges contains {greet→respond, field: message}    → PASS
    ⊨ edges contains {greet→log, field: message}        → PASS
    ⊨ edges contains {respond→log, field: reply}        → PASS
    ⊨ each AST node has: name, type, givens[], yields[],
      body, oracles[]                                    → PASS (structural check)

  Retry policy: on failure, retry with oracle.failures appended, max 2
  Exhaustion: error-value(⊥) — the whole pipeline can collapse here
```

**Cell 3: `analyze` (⊢, LLM-required)**

```
analyze:
  Input: parse→ast, parse→dependency-edges
  ⊥ handler: if parse→ast is ⊥, skip with opportunities=[],
             warnings=["Parse failed — cannot analyze"]

  LLM task: Analyze the AST for 5 categories of optimization:
    1. Crystallizable cells (deterministic ∴ body)
    2. Redundant oracle checks on ⊢= cells
    3. Missing ⊥ propagation handlers
    4. Unreachable cells
    5. Oracle coverage gaps

  Expected output:
    optimization-opportunities = [
      {cell: "log", type: "crystallize",
       reasoning: "log is already ⊢= — its body is a pure computation
       {timestamp, input, output}. No LLM needed."},
    ]
    warnings = [
      "respond has no ⊥ handler for greet→message"
    ]

  Oracle checks:
    ⊨ optimization-opportunities is non-empty           → PASS (log can be crystallized)
    ⊨ each opportunity has: cell-name, type, reasoning  → PASS
    ⊨ warnings includes "respond has no ⊥ handler..."   → PASS

  Note: greet and respond are genuinely LLM-dependent (creative text generation).
  log is already ⊢= in the source, so "crystallize" here confirms it.
  The real finding is the missing ⊥ handler on respond.
```

**Cell 4: `transform-crystallize` (⊢, LLM-required)**

```
transform-crystallize:
  Input: parse→ast, analyze→optimization-opportunities
  ⊥ handler: if analyze→optimization-opportunities is ⊥,
             skip with §transformed-ast = parse→ast, changes-made = []

  LLM task: Apply crystallization. For each opportunity:
    - Change cell type ⊢ → ⊢=
    - Convert ∴ body to formula
    - Remove tautological oracles
    But don't change cells that genuinely need LLM.

  Expected output:
    §transformed-ast = same ast but log confirmed as ⊢=
    changes-made = [
      {cell: "log", change: "confirmed ⊢= type, no oracle changes needed
       (log already had no oracles and was already ⊢=)"}
    ]

  Oracle checks:
    ⊨ changes-made lists each transformation with before/after  → PASS
    ⊨ §transformed-ast preserves all dependency edges           → PASS
    ⊨ log cell has type ⊢=                                     → PASS (was already ⊢=)
    ⊨ greet cell still has type ⊢                               → PASS (needs LLM)

  Retry policy: on failure, retry max 2; on exhaustion: partial-accept(best)

  Key insight: This is mostly a no-op — log was already ⊢= in the source.
  The compiler correctly identifies there's little crystallization to do.
```

**Cell 5: `transform-add-handlers` (⊢, LLM-required)**

```
transform-add-handlers:
  Input: transform-crystallize→§transformed-ast, analyze→warnings
  ⊥ handlers:
    - if §transformed-ast is ⊥, skip with §hardened-ast = parse→ast, handlers-added = []
    - if warnings is ⊥, skip with §hardened-ast = §transformed-ast, handlers-added = []

  LLM task: For each warning about missing ⊥ handlers:
    - Add ⊥? skip with clause to affected cell
    - Choose fail-safe defaults

  Expected output:
    §hardened-ast = transformed-ast but with respond cell gaining:
      given greet→message ⊥? skip with reply ≡ "Error: upstream failed"
    handlers-added = [
      {cell: "respond", given-edge: "greet→message",
       skip-with: {reply: "Error: upstream failed"}}
    ]

  Oracle checks:
    ⊨ handlers-added lists each handler with cell-name, given-edge, skip-with  → PASS
    ⊨ respond has ⊥? handler for greet→message                                 → PASS
    ⊨ skip-with values are fail-safe                                            → PASS

  Retry: max 1; exhaustion: partial-accept(best)
```

**Cell 6: `emit` (⊢, LLM-required)**

```
emit:
  Input: transform-add-handlers→§hardened-ast, parse→cell-count
  ⊥ handler: if §hardened-ast is ⊥, skip with output-program = source-program→§source,
             diff-summary = "No transformations applied (upstream failures)"

  LLM task: Convert hardened AST back to Cell syntax. Write diff-summary.

  Expected output:
    output-program = Cell source with:
      - greet: unchanged (⊢, still needs LLM)
      - respond: now has `given greet→message ⊥? skip with reply ≡ "Error: upstream failed"`
      - log: unchanged (already ⊢=)
    diff-summary = "Added ⊥ handler to respond for greet→message edge.
                    log confirmed as crystallized (⊢=). No other changes."

  Oracle checks:
    ⊨ output-program contains exactly 3 cell definitions              → PASS (cell-count=3)
    ⊨ output-program is syntactically valid Cell                       → PASS (LLM generates valid syntax)
    ⊨ diff-summary mentions each transformation                       → PASS
    ⊨ log cell uses ⊢=                                                → PASS
    ⊨ respond cell has ⊥? handler                                     → PASS

  Retry: max 2; exhaustion: error-value(⊥)
```

**Cell 7: `verify-roundtrip` (⊢ with ⊢= component, LLM-required)**

```
verify-roundtrip:
  Input: source-program→§source, emit→output-program
  ⊥ handler: if output-program is ⊥, skip with preserves-semantics=false,
             preserves-structure=false, improvements=[]

  LLM task: Compare original vs improved program.

  preserves-structure = cell-count(§source) = cell-count(output-program)
    → This is ⊢= (pure computation): 3 = 3 → true

  LLM checks:
    1. All cells present with same names                → yes (greet, respond, log)
    2. All dependency edges preserved                   → yes
    3. All oracles preserved (except tautological)      → yes
    4. Improvements are genuine                         → yes

  Expected output:
    preserves-semantics = true
    preserves-structure = true (⊢= computed)
    improvements = [
      "log confirmed as ⊢= (crystallized)",
      "respond gained ⊥? handler for greet→message"
    ]

  Oracle checks:
    ⊨ preserves-semantics is true                       → PASS
    ⊨ improvements lists ≥2 items                       → PASS (2 items)
    ⊨ if ¬preserves-structure then improvements
      mentions what changed                              → N/A (structure preserved)
```

**Cell 8: `meta-report` (⊢ with ⊢= component, LLM-required)**

```
meta-report:
  Input: verify-roundtrip→preserves-semantics, verify-roundtrip→improvements,
         emit→diff-summary, analyze→optimization-opportunities, analyze→warnings

  compiler-quality = ⊢= computed:
    preserves-semantics=true ∧ length(improvements)=2 ≥ 2
    → "good"

  LLM task: Write summary report covering:
    - Optimizations identified (log crystallizable, respond missing ⊥ handler)
    - Transformations applied (confirm ⊢= for log, add ⊥ handler to respond)
    - Roundtrip verification (semantics preserved, structure preserved)
    - Meta-meta-analysis (could the compiler itself be improved?)

  Oracle checks:
    ⊨ report mentions each optimization opportunity     → PASS
    ⊨ report mentions roundtrip verification            → PASS
    ⊨ compiler-quality ∈ {good, adequate, broken}       → PASS ("good")
    ⊨ if quality = "good" then report concludes positively → PASS

  Final output: compiler-quality = "good", comprehensive report
```

---

### 2. Which cells crystallize? Which must stay soft? Why?

| Cell | Type | Crystallizes? | Reason |
|------|------|---------------|--------|
| `source-program` | ⊢ (but ⊢= yield) | **Yes** — fully crystallized | The yield is a static `⊢=` assignment of a quoted literal `§(...)`. No LLM call needed. It's pure data. |
| `parse` | ⊢ | **No** — must stay soft | Parsing a Cell program from its textual/quoted form into a structured AST requires language understanding. The `cell-count` sub-yield is ⊢= (pure count), but the main `ast` and `dependency-edges` yields need LLM reasoning to extract structure. |
| `analyze` | ⊢ | **No** — must stay soft | Identifying optimization opportunities requires semantic reasoning about what's deterministic, what's missing, what's unreachable. This is inherently a judgment task. |
| `transform-crystallize` | ⊢ | **No** — must stay soft | Applying AST transformations (changing types, converting bodies) requires understanding Cell semantics. Though the actual transformation here is near-trivial (log is already ⊢=), the general case needs LLM. |
| `transform-add-handlers` | ⊢ | **No** — must stay soft | Choosing appropriate fail-safe defaults and inserting ⊥ handlers requires semantic judgment about what "safe" means for each cell. |
| `emit` | ⊢ | **No** — must stay soft | Converting AST back to syntactically valid Cell requires code generation, a creative/structural task. |
| `verify-roundtrip` | ⊢ (with ⊢= sub) | **Partially** | `preserves-structure` is ⊢= (numeric comparison). But `preserves-semantics` and `improvements` require LLM reasoning to compare two programs semantically. |
| `meta-report` | ⊢ (with ⊢= sub) | **Partially** | `compiler-quality` is ⊢= (conditional formula). But the `report` narrative requires LLM to synthesize findings. |

**Summary:** Only `source-program` is fully crystallized. `verify-roundtrip` and
`meta-report` each have one ⊢= sub-yield (pure computation) embedded in an
otherwise soft cell. The remaining 5 cells are fully soft — they require LLM
reasoning for their primary outputs.

---

### 3. Trace every oracle check. Show PASS/FAIL with reasoning.

**parse (5 oracles + retry policy):**

| Oracle | Result | Reasoning |
|--------|--------|-----------|
| `⊨ cell-count = 3` | PASS | The source program has exactly 3 cells: greet, respond, log. `cell-count` is ⊢= computed via `count(cells in §source)`, so this is deterministic. |
| `⊨ dependency-edges contains {greet→respond, message}` | PASS | `respond` has `given greet→message`, creating this edge. |
| `⊨ dependency-edges contains {greet→log, message}` | PASS | `log` has `given greet→message`. |
| `⊨ dependency-edges contains {respond→log, reply}` | PASS | `log` has `given respond→reply`. |
| `⊨ each AST node has required fields` | PASS | Structural constraint — the prompt asks for these fields explicitly. |
| `⊨? on failure: retry max 2` | N/A (happy path) | Would fire if any above oracle fails. |
| `⊨? on exhaustion: error-value(⊥)` | N/A (happy path) | Would produce ⊥ after 3 total attempts. |

**analyze (3 oracles):**

| Oracle | Result | Reasoning |
|--------|--------|-----------|
| `⊨ optimization-opportunities is non-empty` | PASS | `log` is identifiable as crystallizable (already ⊢=, purely deterministic body). |
| `⊨ each opportunity has: cell-name, type, reasoning` | PASS | Structural constraint enforced by prompt. |
| `⊨ warnings includes "respond has no ⊥ handler for greet→message"` | PASS | `respond` takes `given greet→message` with no `⊥?` clause. If `greet` fails, `respond` has no fallback. This is a genuine gap. |

**transform-crystallize (4 oracles + retry):**

| Oracle | Result | Reasoning |
|--------|--------|-----------|
| `⊨ changes-made lists each transformation with before/after` | PASS | Even if the only "change" is confirming log's existing ⊢= type, that counts. |
| `⊨ §transformed-ast preserves all dependency edges` | PASS | Crystallization doesn't change edges — only cell types and bodies. |
| `⊨ log cell has type ⊢=` | PASS | log was already ⊢= in source; transformation confirms or maintains this. |
| `⊨ greet cell still has type ⊢` | PASS | greet generates creative text — cannot be crystallized. |
| `⊨? retry max 2, exhaustion: partial-accept(best)` | N/A (happy path) | |

**transform-add-handlers (3 oracles + retry):**

| Oracle | Result | Reasoning |
|--------|--------|-----------|
| `⊨ handlers-added lists handler with cell-name, given-edge, skip-with` | PASS | respond needs a handler for greet→message, which is the known gap. |
| `⊨ respond has ⊥? handler for greet→message` | PASS | This is the specific transformation being applied. |
| `⊨ skip-with values are fail-safe` | PASS | `reply ≡ "Error: upstream failed"` is fail-closed (doesn't pretend success). |
| `⊨? retry max 1, exhaustion: partial-accept(best)` | N/A (happy path) | |

**emit (5 oracles + retry):**

| Oracle | Result | Reasoning |
|--------|--------|-----------|
| `⊨ output-program contains exactly «cell-count» cell definitions` | PASS | cell-count=3, output has greet+respond+log = 3. |
| `⊨ output-program is syntactically valid Cell` | PASS | Assumes LLM generates valid syntax (a meaningful test — could fail). |
| `⊨ diff-summary mentions each transformation` | PASS | Two transformations: crystallize log (confirm), add ⊥ handler to respond. |
| `⊨ log cell uses ⊢=` | PASS | Preserved from source. |
| `⊨ respond cell has ⊥? handler` | PASS | Added by transform-add-handlers. |
| `⊨? retry max 2, exhaustion: error-value(⊥)` | N/A (happy path) | |

**verify-roundtrip (3 oracles):**

| Oracle | Result | Reasoning |
|--------|--------|-----------|
| `⊨ preserves-semantics is true` | PASS | The output program does everything the input did, plus ⊥ handling. Additive change preserves semantics. |
| `⊨ improvements lists ≥2 items` | PASS | At least: (1) log crystallization confirmed, (2) respond ⊥ handler added. |
| `⊨ if ¬preserves-structure then improvements mentions what changed` | N/A | preserves-structure = true, so this conditional doesn't fire. |

**meta-report (4 oracles):**

| Oracle | Result | Reasoning |
|--------|--------|-----------|
| `⊨ report mentions each optimization opportunity` | PASS | Report synthesizes all findings from analyze. |
| `⊨ report mentions roundtrip verification result` | PASS | Report includes verify-roundtrip outcomes. |
| `⊨ compiler-quality ∈ {good, adequate, broken}` | PASS | ⊢= formula yields "good" (semantics preserved ∧ ≥2 improvements). |
| `⊨ if quality = "good" then report concludes positively` | PASS | "good" → positive conclusion. |

**Total: 27 oracles across 7 cells. All PASS on happy path.**

---

### 4. What's the minimum number of LLM calls needed? Which cells are LLM-free?

**LLM-free cells:**
- `source-program` — pure ⊢= data yield, zero LLM calls

**LLM-free sub-computations within soft cells:**
- `parse`: `cell-count ← count(cells in §source)` is ⊢=
- `verify-roundtrip`: `preserves-structure ← cell-count(§source) = cell-count(output-program)` is ⊢=
- `meta-report`: `compiler-quality ← if ... then "good" ...` is ⊢=

**Minimum LLM calls (happy path): 6**

| Cell | LLM calls | Purpose |
|------|-----------|---------|
| source-program | 0 | Static data |
| parse | 1 | Parse §source → AST + edges |
| analyze | 1 | Identify optimizations + warnings |
| transform-crystallize | 1 | Apply crystallization transforms |
| transform-add-handlers | 1 | Add ⊥ handlers |
| emit | 1 | AST → Cell syntax |
| verify-roundtrip | 1 | Semantic comparison |
| meta-report | 1 | Write summary report |
| **Total** | **7** | |

Wait — recount. `source-program` is 0. The remaining 7 cells each need 1 LLM call.

**Minimum: 7 LLM calls** (happy path, no retries).

**Maximum (all retries exhausted):**
- parse: 1 + 2 retries = 3
- transform-crystallize: 1 + 2 retries = 3
- transform-add-handlers: 1 + 1 retry = 2
- emit: 1 + 2 retries = 3
- analyze, verify-roundtrip, meta-report: 1 each (no retry policies)

**Maximum: 3 + 1 + 1 + 3 + 2 + 3 + 1 + 1 = 15 LLM calls**

Correction — analyze, verify-roundtrip, and meta-report have no `⊨? on failure`
retry clauses. They either pass or they don't. So maximum retries only apply to
parse (3), transform-crystallize (3), transform-add-handlers (2), emit (3) = 11
for those, plus 3 for the non-retry cells = **14 total max**.

**Summary: 7 minimum, 14 maximum.**

---

### 5. Rate the overall program clarity 1-10. Could you maintain this program?

**Rating: 8/10**

**Strengths:**
- **Clear pipeline architecture.** Eight cells in a linear flow, each with a
  well-defined transformation step. The compiler phases (parse → analyze →
  transform → emit → verify) map to a textbook compiler pipeline.
- **Comprehensive ⊥ propagation.** Every cell that depends on upstream data has
  explicit `⊥?` handlers with sensible defaults. The failure modes are
  well-thought-out (e.g., analyze skips gracefully if parse fails).
- **Self-documenting oracles.** The oracle checks serve as both validation AND
  documentation of expected behavior. Reading the oracles tells you exactly what
  each cell is supposed to produce.
- **Metacircular elegance.** The program operates on itself — the `§source`
  contains a Cell program, and the compiler transforms it using Cell
  constructs. This is a compelling demonstration of Cell's expressiveness.
- **Graduated retry policies.** Different cells have different retry budgets
  based on their criticality. parse and emit get max 2 retries; handler
  addition gets max 1. This shows intentional design.

**Weaknesses:**
- **source-program is misleadingly typed.** It's declared as `⊢` but its yield
  is `⊢=`. The cell header should just be `⊢=` since no LLM is involved. This
  is the exact kind of thing the compiler's own `analyze` step would flag.
- **transform-crystallize may be near-vacuous.** The input program's only
  crystallizable cell (`log`) is already `⊢=`. The transform mostly confirms
  existing state rather than changing anything. The cell does real work in the
  general case but feels ceremonial here.
- **No parallelism.** transform-crystallize and transform-add-handlers are
  sequential but could theoretically run in parallel (they address orthogonal
  concerns on the same AST). Cell doesn't seem to have a `⊢⊢` spawner pattern
  here.
- **Meta-meta gap.** The meta-report asks "could the compiler itself be
  improved?" but the program doesn't actually act on that insight. A truly
  self-improving compiler would feed meta-report's suggestions back into a
  second pass. This is noted but not a real problem — it would create infinite
  recursion without a fixed-point check.

**Maintainability: Yes, with caveats.** The linear pipeline is easy to follow.
Each cell's purpose is clear from its name and oracles. Adding a new transform
phase would be straightforward (insert between existing transforms). The main
maintenance risk is the quoted `§source` — changing the input program requires
updating oracle expectations across multiple cells simultaneously.

---

### 6. What would break if you removed any single cell? (Fragility analysis)

| Removed Cell | Impact | Severity |
|--------------|--------|----------|
| `source-program` | **Total collapse.** Every downstream cell depends (transitively) on `§source`. No input → no pipeline. | CRITICAL |
| `parse` | **Total collapse.** `analyze`, `transform-crystallize`, `emit`, and `verify-roundtrip` all depend on parse outputs (ast, dependency-edges, cell-count). All would receive ⊥ or be unreachable. `analyze` would skip with empty results; transforms would pass through unchanged; emit would fall back to original source; verify would report failure. The compiler would output the original program unchanged with a "broken" quality rating. | CRITICAL |
| `analyze` | **Graceful degradation.** `transform-crystallize` and `transform-add-handlers` both have `⊥?` handlers for analyze outputs. With no analysis, both transforms would skip (pass-through). `emit` would emit the unchanged AST. The compiler would produce the original program with no improvements — quality = "adequate" (semantics preserved but <2 improvements). | MODERATE |
| `transform-crystallize` | **Partial degradation.** `transform-add-handlers` would receive the raw parse AST (its ⊥ handler falls back to parse→ast). Handlers would still be added to respond. emit would produce a partially improved program (⊥ handlers added but no crystallization confirmed). Quality likely "adequate". | LOW-MODERATE |
| `transform-add-handlers` | **Partial degradation.** `emit`'s `⊥?` handler falls back to `source-program→§source` (original program). The crystallization would be lost too since emit falls all the way back. Quality = "adequate" or "broken" depending on whether verify-roundtrip can still find improvements. | MODERATE |
| `emit` | **Output collapse.** `verify-roundtrip` would receive ⊥ for `output-program`, triggering its skip: preserves-semantics=false, preserves-structure=false. meta-report would rate quality as "broken". No improved program produced. | HIGH |
| `verify-roundtrip` | **No quality assurance.** meta-report would receive ⊥ for its inputs. But meta-report has NO explicit ⊥ handlers for its inputs! This is a gap — meta-report would likely fail or produce garbage. compiler-quality formula would evaluate with ⊥ inputs (preserves-semantics=⊥), yielding undefined behavior. | HIGH (also reveals a design gap) |
| `meta-report` | **No reporting but program still produced.** The improved program from emit still exists. The compiler "works" but produces no quality assessment. All upstream cells are unaffected. This is the safest cell to remove. | LOW |

**Fragility profile:** The pipeline is front-loaded in criticality. Removing
early cells (source-program, parse) causes total collapse. Removing middle cells
(analyze, transforms) triggers graceful degradation through ⊥ handlers. Removing
late cells (emit, verify, report) loses outputs but doesn't corrupt the pipeline.

**Notable gap discovered:** `meta-report` has NO `⊥?` handlers for any of its
5 inputs. If any upstream cell produces ⊥ that propagates to meta-report, the
behavior is undefined. This is the one fragility flaw in an otherwise
well-defended pipeline.

---

### 7. Where are the trust boundaries? (Which cells must be trusted vs verified?)

**Trust model:**

The Cell language has an inherent trust architecture: `⊢=` cells are
**trustworthy by construction** (deterministic computation), while `⊢` cells
with `∴` prompts are **untrusted** (LLM output) and must be **verified by
oracles** (`⊨`).

| Cell | Trust Level | Verification | Reasoning |
|------|-------------|--------------|-----------|
| `source-program` | **Fully trusted** | None needed | ⊢= yield — static data, no LLM involvement. The quoted program is exactly what the author wrote. |
| `parse` | **Untrusted, oracle-verified** | 5 oracles + retry | The LLM could hallucinate AST nodes, miss edges, or invent cells. Oracles verify structural correctness (cell count, edge presence, node fields). However, oracles don't verify *semantic* correctness of the AST — a subtly wrong parse that satisfies all structural checks would pass. |
| `analyze` | **Untrusted, oracle-verified** | 3 oracles | The LLM identifies optimization opportunities. Oracles verify the expected findings exist but don't verify completeness — the LLM could miss optimizations. The specific string-match oracle (`warnings includes "respond has no ⊥ handler..."`) is fragile — a semantically correct but differently worded warning would fail. |
| `transform-crystallize` | **Untrusted, oracle-verified** | 4 oracles + retry | Oracles verify specific expected outcomes (log is ⊢=, greet stays ⊢). Edge preservation oracle provides structural safety. But oracles don't verify that no other unintended changes were made. |
| `transform-add-handlers` | **Untrusted, oracle-verified** | 3 oracles + retry | Fail-safety oracle (`skip-with values are fail-safe`) is the most important — it's the only check that the defaults are actually safe. But this oracle is itself LLM-judged (what constitutes "fail-safe"?). |
| `emit` | **Untrusted, oracle-verified** | 5 oracles + retry | Syntactic validity oracle is critical. Cell-count oracle ensures no cells were lost or invented. But "syntactically valid Cell" is hard for an oracle to verify without a real parser — this is the weakest verification point. |
| `verify-roundtrip` | **Mixed trust** | 3 oracles | `preserves-structure` is ⊢= (trusted by construction). `preserves-semantics` is LLM-judged (untrusted — an LLM comparing two programs semantically). This is a significant trust concern: the verifier itself could be wrong. |
| `meta-report` | **Untrusted, oracle-verified** | 4 oracles | `compiler-quality` is ⊢= (trusted formula). The `report` narrative is LLM-generated. Oracles check for content inclusion but not correctness. |

**Key trust boundaries:**

1. **§source → parse**: The boundary between trusted input (static quoted
   program) and untrusted processing (LLM parsing). This is where all
   downstream trust originates. If parse is wrong, everything downstream
   operates on a false foundation — even with passing oracles.

2. **transform-\* → emit**: The boundary between AST manipulation (abstract
   structure) and code generation (concrete syntax). emit must produce valid,
   parseable Cell from an LLM-constructed AST. The "syntactically valid Cell"
   oracle is the only guard here, and it relies on the LLM to self-judge.

3. **emit → verify-roundtrip**: The verification boundary. This is supposed to
   catch errors from the entire pipeline. But `preserves-semantics` is itself
   LLM-judged — the guard is guarding itself with the same tool it's guarding
   against. This is the "quis custodiet ipsos custodes" problem.

4. **⊢= sub-computations** are islands of trust within untrusted cells:
   `cell-count`, `preserves-structure`, and `compiler-quality` are all
   deterministic formulas that don't depend on LLM output (only on structural
   properties of LLM outputs). These provide hard anchoring points in an
   otherwise LLM-dependent pipeline.

**The metacircular trust paradox:** This program is a Cell compiler written in
Cell. If the program's own analysis is correct (respond needs a ⊥ handler), then
the compiler can improve the input. But the compiler itself has the same class of
issues it's fixing — `meta-report` lacks ⊥ handlers. The compiler doesn't
improve *itself*, only its input. This is intentional (avoiding infinite
recursion) but highlights that the trust model is one-directional: the compiler
trusts its own oracles to verify its work on the input program, but nothing
verifies the compiler's own structural soundness.

---

## Metacircular Analysis

This is the defining feature of T4. The program is Cell-on-Cell: a Cell program
that reads, analyzes, transforms, and emits Cell programs. The input happens to
be a simpler Cell program (the 3-cell greeting pipeline), but the compiler's
structure could operate on any Cell source.

**What makes this metacircular (and what doesn't):**

- **IS metacircular:** The compiler uses Cell constructs (⊢, ⊢=, ⊨, ⊥?, §) to
  manipulate programs that contain those same constructs. The `§source` quoting
  mechanism allows Cell to represent Cell programs as data.
- **IS NOT fully self-applicable:** The compiler doesn't operate on its own
  source code. It operates on a separate, simpler program. Running the compiler
  on itself would require the compiler's own 8-cell structure to be embedded as
  `§source`, and the analysis/transform phases would need to handle the
  compiler's own patterns (retry policies, ⊥ handlers, etc.).
- **The self-application thought experiment:** If you fed the compiler its own
  source, `analyze` would discover that `meta-report` lacks ⊥ handlers (the gap
  identified in question 6), `transform-add-handlers` would add them, and `emit`
  would produce an improved version of the compiler. This is genuinely
  self-improving — but only for one iteration. A fixed-point compiler would need
  to detect "no more improvements possible" and halt.

**The `§` quoting mechanism** is doing heavy lifting here. It allows a Cell
program to treat another Cell program as structured data (`§source`) rather than
as executable code. This is analogous to Lisp's quote/eval distinction — `§`
quotes, and parse/emit are effectively eval. The compiler is a Cell program
that *interprets* (via LLM) rather than *executes* (via runtime) its input.

---

## Summary

T4 is the most architecturally sophisticated program in Round 12. It
demonstrates that Cell can express metacircular compilation — reading, analyzing,
transforming, and emitting Cell programs — using the same constructs it operates
on. The pipeline is well-defended with ⊥ handlers (except for the meta-report
gap), oracles provide reasonable verification (with the caveat that semantic
checks are LLM-judged), and the linear flow is maintainable.

The program exposes a fundamental tension in LLM-based compilation: the verifier
(`verify-roundtrip`) uses the same LLM that produced the output it's verifying.
This is the "who watches the watchmen" problem, and Cell's answer — oracle
checks with retry and exhaustion policies — is pragmatic rather than provably
sound. The ⊢= sub-computations (cell-count, preserves-structure,
compiler-quality) provide islands of deterministic trust within the LLM-dependent
pipeline.

**Verdict:** 8/10 clarity, well-structured, genuinely metacircular (not just
self-referential), with one discovered design gap (meta-report ⊥ handling) and
one fundamental trust limitation (LLM verifying LLM output).
