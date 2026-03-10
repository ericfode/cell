# Exercise: Bottom Propagation Simulation

Simulating cell-zero's handling of ⊥ (bottom) on the test program.

## Test Program Graph

```
fetch-data ──→ parse ──→ summarize
     │
     └──────→ fallback
```

**Dependencies:**
- `parse` depends on `fetch-data→response`
- `summarize` depends on `parse→records`
- `fallback` depends on `fetch-data→response`

## Execution Trace

### Step 1: Graph Inspection (read-graph)

Cells extracted:
- `fetch-data` — givens: [url ≡ "https://api.example.com/data"], yields: [response]
- `parse` — givens: [fetch-data→response], yields: [records[]]
- `summarize` — givens: [parse→records], yields: [summary]
- `fallback` — givens: [fetch-data→response], yields: [backup-message]

Edges: fetch-data→parse, parse→summarize, fetch-data→fallback

### Step 2: check-inputs (iteration 1)

§state = { url ≡ "https://api.example.com/data" }

- **fetch-data**: all givens bound (url ≡ literal) → READY
- **parse**: fetch-data→response unbound → BLOCKED
- **summarize**: parse→records unbound → BLOCKED
- **fallback**: fetch-data→response unbound → BLOCKED

ready-cells = [fetch-data]

### Step 3: pick-cell → fetch-data (leaf, no deps)

### Step 4: evaluate fetch-data

The ∴ body says: "Fetch data from «url»."
URL is fake → HTTP request fails.

Oracle checking:
- ⊨ `response is valid JSON` → FAIL (no response at all)
- ⊨? on failure: retry with oracle.failures appended, max 1

**Retry 1:** Re-evaluate with failure context appended.
Still fake URL → FAIL again.

- ⊨? on exhaustion: `error-value(⊥)`

### Step 5: decide → BOTTOM

Retries exhausted. Exhaustion policy = `error-value(⊥)`.
Action: **bottom** — freeze fetch-data with `response ≡ ⊥`.

§state = { url ≡ "...", fetch-data.response ≡ ⊥ }

### Step 6: handle-bottom (Phase 5)

Downstream cells depending on fetch-data→response (now ⊥):
- **parse** — depends on fetch-data→response = ⊥
- **fallback** — depends on fetch-data→response = ⊥

Per cell-zero-sketch.cell Phase 5 rules:

**parse:**
- Has no ⊥? handler → "leave it blocked (⊥ propagates naturally — the cell is never ready)"
- parse stays blocked forever.
- Since parse never produces records, summarize also stays blocked forever.

**fallback:**
- Has no explicit ⊥? handler syntax (no `⊥? skip with:` or `⊥? error-value(⊥)`)
- The ∴ body *mentions* the ⊥ case: "If «fetch-data→response» is ⊥, produce a friendly error message."
- But per cell-zero's semantics, ⊥ handling is checked via **⊥? handler declarations**, not ∴ body content.
- No ⊥? handler → fallback stays blocked forever.

### Step 7: check-inputs (iteration 2)

§state = { url ≡ "...", fetch-data.response ≡ ⊥ }

- fetch-data: already frozen → not ready
- parse: given is ⊥, no ⊥? handler → BLOCKED (never ready)
- summarize: given unbound (parse not frozen) → BLOCKED
- fallback: given is ⊥, no ⊥? handler → BLOCKED (never ready)

ready-cells = [] → **QUIESCE**

### Final State

```
fetch-data: FROZEN (response ≡ ⊥)
parse:      BLOCKED FOREVER (⊥ propagates)
summarize:  BLOCKED FOREVER (transitive ⊥)
fallback:   BLOCKED FOREVER (⊥ propagates — despite ∴ body handling the case)
```

## Result

```json
{
  "exercise": "bottom-propagation",
  "steps": [
    {"step": 1, "cell": "fetch-data", "action": "evaluate", "result": "FAIL (fake URL)", "why": "HTTP request to fake URL fails"},
    {"step": 2, "cell": "fetch-data", "action": "retry (1/1)", "result": "FAIL", "why": "Same fake URL, retry exhausted"},
    {"step": 3, "cell": "fetch-data", "action": "bottom", "result": "response ≡ ⊥", "why": "Exhaustion policy: error-value(⊥)"},
    {"step": 4, "cell": "parse", "action": "handle-bottom", "result": "BLOCKED FOREVER", "why": "Depends on ⊥ output, no ⊥? handler"},
    {"step": 5, "cell": "summarize", "action": "handle-bottom", "result": "BLOCKED FOREVER", "why": "Transitive: depends on parse which is blocked"},
    {"step": 6, "cell": "fallback", "action": "handle-bottom", "result": "BLOCKED FOREVER", "why": "Depends on ⊥ output, no ⊥? handler (∴ body awareness doesn't count)"}
  ],
  "bottom_reached": ["parse", "summarize", "fallback"],
  "survived": [],
  "design_question": "Should cells be able to handle ⊥ in their ∴ body?",
  "feedback_for_morpheus": "The fallback cell is a strong motivating case. Its ∴ body explicitly handles ⊥, but cell-zero's current semantics require a ⊥? handler declaration — the ∴ body is opaque to the scheduler. Three options: (1) Add ⊥-aware scheduling where check-inputs inspects ∴ bodies for ⊥ mentions (breaks the clean separation between scheduling and evaluation). (2) Require authors to add explicit ⊥? handlers (e.g., '⊥? pass-through: evaluate with ⊥ as input'). (3) Introduce a 'given? fetch-data→response' (optional-given) that marks the input as nullable — the cell is ready even when the input is ⊥. Option 3 is cleanest: it preserves the scheduler/evaluator separation while letting cells opt into ⊥-awareness."
}
```

## Design Analysis

The core tension: **cell-zero separates scheduling (check-inputs) from evaluation (evaluate)**.
The scheduler doesn't read ∴ bodies — it only looks at structural declarations (given, yield, ⊨, ⊥?).

This means the `fallback` cell, which was *designed* to handle the failure case, is dead on arrival.
Its ∴ body says "If response is ⊥, produce a friendly error message" — but the scheduler
never lets it run because its input is ⊥ and there's no ⊥? declaration.

### Recommended: `given?` (optional-given) syntax

```
⊢ fallback
  given? fetch-data→response     ← nullable input, cell runs even if ⊥
  yield backup-message
  ...
```

This preserves the clean scheduling/evaluation boundary. The `?` on `given` tells
check-inputs: "this cell is ready even if this particular input is ⊥." The cell's
∴ body then receives ⊥ as a value and handles it however it wants.

This is analogous to `Option<T>` in Rust or `T | null` in TypeScript — the type
system (scheduler) knows the input can be absent, and the implementation handles it.
