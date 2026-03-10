# Round 13 Results: t4-quotation-roundtrip — § Quotation as Data (Cold Read)

**Polecat**: dust | **Date**: 2026-03-10 | **Rating**: 8/10

## Program Overview

5 cells testing the § (section-sign) quotation mechanism: cell definitions as
data, structural inspection without execution, definition modification, and
roundtrip verification.

Structure: `greet` (target cell) → `describe` (structural analysis via §) →
`rebind` (modify quoted definition) → `execute-modified` (run the modified
version) → `roundtrip` (compare original and modified outputs).

The program's central claim: §greet gives you the DEFINITION of greet as data,
not its output. You can inspect it structurally (describe), modify it (rebind),
execute the modification (execute-modified), and verify the roundtrip preserves
structure (roundtrip).

---

## Q1: Step-by-Step Execution (All Intermediate States)

### Dependency Graph

```
greet ──────────────────────────────────────── roundtrip
  §greet ──→ describe (no dep on greet output)      ↑
  §greet ──→ rebind (no dep on greet output)         │
                  ↓                                  │
             execute-modified ───────────────────────┘
```

### Ready Set at Start

Three cells are immediately ready:

- **greet**: `given name ≡ "Alice"` is an inline binding — all inputs bound.
- **describe**: `given §greet` — § gives the definition as data, always available
  at parse time. No dependency on greet executing.
- **rebind**: `given §greet` — same reasoning as describe.

This is the critical **data-not-executed** property: §greet is available BEFORE
greet executes. The definition is data, not a computed value.

### Execution Ordering (Kahn's Algorithm)

By confluence, the order among {greet, describe, rebind} doesn't matter.
I trace them in declaration order, but any interleaving produces the same
final state.

---

### Step 1: Cell `greet`

**Type**: ⊢ (soft — LLM required)

**Inputs**: `name ≡ "Alice"` (inline binding)

**LLM call**: "Write a one-sentence greeting for Alice."

**Expected output**: `message ≡ "Hello, Alice!"`

**Oracle checks**:
| Oracle | Result | Reasoning |
|--------|--------|-----------|
| `message contains «name»` | PASS | "Hello, Alice!" contains "Alice" |
| `message is exactly one sentence` | PASS | Single sentence with period |

**State after**: `greet→message ≡ "Hello, Alice!"`

---

### Step 2: Cell `describe`

**Type**: ⊢= (crystallized — no LLM)

**Inputs**: `§greet` — the full definition text of greet:
```
⊢ greet
  given name ≡ "Alice"
  yield message
  ∴ Write a one-sentence greeting for «name».
  ⊨ message contains «name»
  ⊨ message is exactly one sentence
```

**DATA-NOT-EXECUTED VERIFICATION**: describe receives §greet = the cell's
structural TEMPLATE. This is the definition text, not execution output.
Whether greet has already executed is irrelevant — § gives the definition,
not the state. No LLM call occurs in describe. The definition is pure data
operated on by ⊢= expressions.

**Crystallized computation**:
```
input-name ← first(given-names(§greet)) = "name"
yield-name ← first(yield-names(§greet)) = "message"
body-type  ← §greet contains ∴ → true → "soft"
```

**Oracle checks**:
| Oracle | Result | Reasoning |
|--------|--------|-----------|
| `input-name = "name"` | PASS | Tautological — ⊢= computed it from the definition |
| `yield-name = "message"` | PASS | Tautological — ⊢= computed it from the definition |
| `body-type = "soft"` | PASS | Tautological — §greet visibly contains ∴ |

**State after**: `{input-name: "name", yield-name: "message", body-type: "soft"}`

**Note**: All three oracles are tautological — they verify ⊢= computations
against values that are structurally determined by the input. The oracles
function as documentation/self-tests rather than meaningful constraints. This
is the R11 finding #5 recurring: oracles on crystallized cells are assertions,
not guardrails.

---

### Step 3: Cell `rebind`

**Type**: ⊢ (soft — LLM required)

**Inputs**: `§greet` — same definition text as describe received

**LLM call**: "Copy [greet definition] but replace the given name default
from 'Alice' to 'Bob'. All else stays identical."

**Expected output**: `§greet'` =
```
⊢ greet
  given name ≡ "Bob"
  yield message
  ∴ Write a one-sentence greeting for «name».
  ⊨ message contains «name»
  ⊨ message is exactly one sentence
```

**Oracle checks**:
| Oracle | Result | Reasoning |
|--------|--------|-----------|
| `§greet' has same given/yield signature as §greet` | PASS | Same structure: `given name`, `yield message` |
| `§greet'.given.name default = "Bob"` | PASS | Default changed from "Alice" to "Bob" |

**State after**: `rebind→§greet'` bound to modified definition.

**Modification trace**: The ONLY change is `given name ≡ "Alice"` → `given name ≡ "Bob"`.
The ∴ body, yield declaration, and oracle assertions are identical. The interface
freeze oracle (`same given/yield signature`) enforces Liskov substitution for cells.

---

### Step 4: Cell `execute-modified`

**Type**: ⊢ (soft — LLM required, meta-evaluation)

**Inputs**: `rebind→§greet'` — the modified definition with name ≡ "Bob"

**LLM call**: "Execute [modified greet definition] — interpret its ∴ body
'Write a one-sentence greeting for Bob.' with its bound givens."

**Expected output**: `modified-message ≡ "Hello, Bob!"`

**Oracle checks**:
| Oracle | Result | Reasoning |
|--------|--------|-----------|
| `modified-message contains "Bob"` | PASS | "Hello, Bob!" contains "Bob" |
| `modified-message is exactly one sentence` | PASS | Single sentence |

**State after**: `execute-modified→modified-message ≡ "Hello, Bob!"`

**Note**: This cell performs meta-evaluation — it takes a cell definition (data)
and executes it. This is the "unquotation" step of the roundtrip. execute-modified
can NEVER crystallize because it interprets arbitrary ∴ bodies. It sits on the
crystallization boundary identified in the spec (§8: "Any cell that executes
§-referenced cells is an interpreter").

---

### Step 5: Cell `roundtrip`

**Type**: ⊢ (soft — LLM required)

**Inputs**:
- `greet→message ≡ "Hello, Alice!"`
- `execute-modified→modified-message ≡ "Hello, Bob!"`

**LLM call**: "Compare 'Hello, Alice!' and 'Hello, Bob!'. Do they share
the same greeting structure, differing only in the name?"

**Expected output**:
- `same-structure ≡ true`
- `name-only-diff ≡ true`

**Oracle checks**:
| Oracle | Result | Reasoning |
|--------|--------|-----------|
| `same-structure ∈ {true, false}` | PASS | Tautological — boolean is always in {true, false} |
| `name-only-diff = same-structure` | PASS | Both true |

**State after**: `{same-structure: true, name-only-diff: true}`

**Final document state** (all yields bound — is-done):
```
greet→message           ≡ "Hello, Alice!"
describe→input-name     ≡ "name"
describe→yield-name     ≡ "message"
describe→body-type      ≡ "soft"
rebind→§greet'          ≡ [modified definition]
execute-modified→modified-message ≡ "Hello, Bob!"
roundtrip→same-structure ≡ true
roundtrip→name-only-diff ≡ true
```

---

## Q2: Which Cells Crystallize? Which Must Stay Soft? Why?

| Cell | Type | Crystallizes? | Reason |
|------|------|---------------|--------|
| `greet` | ⊢ | **No** — must stay soft | NL greeting generation requires LLM judgment. No deterministic function produces greetings. |
| `describe` | ⊢= | **Yes** — fully crystallized | Structural analysis of a definition. Pure computation: extract given-names, yield-names, check for ∴. Zero LLM involvement. |
| `rebind` | ⊢ | **Potentially** — depends on § representation | If § gives structured data (AST), rebinding a default is a deterministic tree operation: `§greet.given[0].default ← "Bob"`. If § gives raw text, rebinding requires NL understanding of syntax. **This is a spec gap this program surfaces.** |
| `execute-modified` | ⊢ | **Never** — permanently soft | Meta-evaluator. Interprets arbitrary ∴ bodies. This is `eval` — the crystallization boundary. |
| `roundtrip` | ⊢ | **No** — must stay soft | Structural comparison of NL texts requires LLM judgment. "Same structure with different name" is a semantic judgment. |

**Key insight**: describe and rebind operate on the SAME input (§greet) with
very different crystallization profiles. describe is purely structural (⊢=),
while rebind is soft (∴). This reveals that § quotation enables BOTH crystallized
and soft operations on cell definitions — the quotation mechanism is
crystallization-neutral.

**The rebind crystallization question**: If Cell's § mechanism provides structured
access to definitions (like an AST), then rebind reduces to
`set(§greet, "given.name.default", "Bob")` — fully crystallizable. If § provides
raw text, rebind requires NL parsing. The spec says § gives "a cell's definition
as data" but doesn't specify the data format. This program makes the question
concrete and urgent.

---

## Q3: Oracle Check Trace (Complete)

| # | Oracle | Cell | Result | Tautological? |
|---|--------|------|--------|---------------|
| 1 | `message contains «name»` | greet | PASS | No — LLM could omit the name |
| 2 | `message is exactly one sentence` | greet | PASS | No — LLM could produce multiple |
| 3 | `input-name = "name"` | describe | PASS | **Yes** — ⊢= extracted from §greet |
| 4 | `yield-name = "message"` | describe | PASS | **Yes** — ⊢= extracted from §greet |
| 5 | `body-type = "soft"` | describe | PASS | **Yes** — §greet visibly has ∴ |
| 6 | `§greet' has same signature as §greet` | rebind | PASS | No — LLM could change structure |
| 7 | `§greet'.given.name default = "Bob"` | rebind | PASS | No — LLM could rebind wrong |
| 8 | `modified-message contains "Bob"` | execute-modified | PASS | No — meta-eval could fail |
| 9 | `modified-message is exactly one sentence` | execute-modified | PASS | No — meta-eval could produce multiple |
| 10 | `same-structure ∈ {true, false}` | roundtrip | PASS | **Yes** — boolean tautology |
| 11 | `name-only-diff = same-structure` | roundtrip | PASS | No — LLM could disagree |

**Total**: 11 oracle checks. 4 tautological (3 in describe, 1 in roundtrip).

**Oracle quality**: 7/11 oracles are meaningful constraints that could actually
fail. The 3 tautological oracles in describe are the R11 pattern recurring (⊢=
cells with tautological oracles). The boolean-range oracle in roundtrip is
vacuous. Overall oracle quality is better than word-life (which had 5
tautological oracles out of 12 in non-loop cells).

---

## Q4: LLM Call Count

| Cell | LLM calls | Why |
|------|-----------|-----|
| `greet` | 1 | NL greeting generation |
| `describe` | 0 | Fully ⊢= (crystallized) |
| `rebind` | 1 | NL text manipulation of definition |
| `execute-modified` | 1 | Meta-evaluation of ∴ body |
| `roundtrip` | 1 | NL comparison of texts |
| **Total** | **4** | |

**LLM-free cells**: describe (pure structural analysis via ⊢=).

**Minimum LLM calls**: 4 (no retries needed in happy path).

**Maximum LLM calls**: 4 + retries. rebind and execute-modified have no ⊨?
recovery policy defined, so oracle failures would produce ⊥. Only greet could
potentially retry (if ⊨? were specified), but it isn't — another gap.

**Cost assessment**: 4 LLM calls is minimal. This program is a proof-of-concept
for § semantics, not a stress test. Compare to word-life's 101 calls.

---

## Q5: Program Clarity Rating

**Rating: 8/10**

**Strengths**:
- Clean demonstration of § quotation at each stage: quote → inspect → modify → execute → compare
- The dependency graph makes data-not-executed visible: describe and rebind take §greet, not greet→output
- describe as a fully crystallized cell shows § enables ⊢= operations on definitions
- The interface freeze oracle (`same given/yield signature`) connects to the spec's Liskov substitution principle
- Minimal cell count — 5 cells, no bloat, each with a distinct role

**Weaknesses**:
- No ⊨? recovery policies on any cell — if an oracle fails, behavior is unspecified
- The `roundtrip` cell's `name-only-diff = same-structure` oracle conflates two properties: structural similarity and name-only difference. These could be separate checks.
- Missing: a cell that demonstrates § on a crystallized (⊢=) cell, to test whether quotation of hard cells differs from quotation of soft cells

**Could I maintain this?** Yes. The data flow is linear and each cell's purpose is self-documenting. A new developer could trace the quotation lifecycle in under 5 minutes.

---

## Q6: Data-Not-Executed Verification

This is the central property the program tests. Analysis:

### What "data-not-executed" means

When `describe` receives `§greet`, it gets the DEFINITION — the structural
template (given/yield/∴/⊨). It does NOT get execution results. greet's ∴ body
is not interpreted, no LLM call is made for greet's behalf, and greet→message
remains unbound from describe's perspective.

### Evidence from the execution trace

1. **describe fires without greet executing**: describe's only input is §greet
   (the definition as data). It has no dependency on greet→message. In Kahn's
   algorithm, describe is ready at step 0, before greet might execute.

2. **describe is fully ⊢=**: All of describe's computations are crystallized
   structural operations on the definition text. No LLM call occurs. If §greet
   triggered execution, describe would need to handle the LLM output — but
   it doesn't.

3. **rebind also fires without greet executing**: Same argument. rebind takes
   §greet and modifies the definition. It never touches greet→message.

4. **Confluence preserves the property**: Whether greet fires before or after
   describe/rebind, the results are identical. §greet always gives the same
   definition regardless of execution state. This is because § captures the
   TEMPLATE (structural definition), not the STATE (with yield bindings).

### The deeper question

Does § give the definition at PARSE TIME (static, immutable) or at REFERENCE
TIME (potentially reflecting execution state)?

If §greet captured execution state, then after greet executes:
- §greet would include `yield message ≡ "Hello, Alice!"`
- describe's ⊢= could extract the computed value
- This would break data-not-executed

The program assumes § gives the static definition. This is consistent with
the spec ("passes a cell's definition as data, not its output") but the spec
could be more explicit about what "definition" includes. Recommendation:
clarify that § captures the structural template (given/yield/∴/⊨ declarations)
without yield bindings.

---

## Q7: Trust Boundaries

| Cell | Trust Level | Reasoning |
|------|-------------|-----------|
| `greet` | **Must be verified** | LLM generates greeting. Oracles check name inclusion and sentence count — reasonable constraints. |
| `describe` | **Trusted** (verified by ⊢=) | Pure structural computation. Cannot produce wrong results given correct input. Tautological oracles confirm this. |
| `rebind` | **Must be verified** | LLM modifies definition. Interface freeze oracle is the critical guardrail — prevents structural changes. But no oracle checks that ONLY the name default changed (body, oracles could be silently modified). **Gap: need oracle checking §greet' body = §greet body.** |
| `execute-modified` | **Must be verified** | Meta-evaluation. Trust depends entirely on the quality of §greet' (which depends on rebind). Cascading trust: execute-modified trusts rebind to produce a valid definition. |
| `roundtrip` | **Must be verified** | LLM compares texts. The comparison is subjective ("same structure") but bounded by the oracle. |

### Trust Chain

```
TRUSTED                    MUST VERIFY
┌──────────┐               ┌─────────────────┐
│ describe │               │ rebind           │
│ (⊢= on   │               │  ⚠ could modify  │
│  §greet)  │               │    body silently  │
└──────────┘               ├─────────────────┤
                           │ execute-modified │
                           │  (meta-eval,     │
                           │   trusts rebind)  │
                           ├─────────────────┤
                           │ greet            │
                           │  (LLM greeting)   │
                           ├─────────────────┤
                           │ roundtrip        │
                           │  (LLM comparison) │
                           └─────────────────┘
```

**Critical gap in rebind**: The oracle checks signature preservation and name
default change, but does NOT verify that the ∴ body, other givens, yields,
or oracles are unchanged. A malicious or confused LLM could return §greet'
with a modified ∴ body ("Write an insult for «name»") that passes both oracles.
Fix: add `⊨ body(§greet') = body(§greet)` or `⊨ §greet' differs from §greet only in given.name default`.

---

## Friction Points

### 1. § Data Format Unspecified (MAJOR)

The spec says § gives "a cell's definition as data" but doesn't specify what
kind of data. Is it:
- **Raw text** (the literal source code of the cell declaration)?
- **Structured data** (an AST-like object with named fields)?
- **Something in between** (a document fragment)?

This matters because:
- describe's `first(given-names(§greet))` assumes structural access
- rebind's modification assumes the definition is manipulable
- If § is raw text, `given-names()` needs a parser → describe might not be ⊢=

**Recommendation**: Define § as giving structured data (AST). This enables
crystallized operations (describe) while preserving the "definition as data"
semantics. Raw text quotation should use a different mechanism (e.g., `§§greet`
for raw source).

### 2. Rebind Safety Gap (MEDIUM)

The `same given/yield signature` oracle is necessary but insufficient. It checks
the INTERFACE but not the IMPLEMENTATION. rebind could change the ∴ body, add
oracles, or remove them. Need: `⊨ §greet' differs from §greet only at given.name.default`.

### 3. Meta-Evaluation Semantics (MEDIUM)

execute-modified "executes" §greet' via its ∴ body. But what does this mean
operationally? Does the LLM:
- Read the full §greet' definition and interpret its ∴ as instructions?
- Or does the Cell runtime instantiate §greet' as a new cell and run eval-one?

The first interpretation (LLM interprets) makes execute-modified a soft
meta-evaluator. The second (runtime instantiation) would make execute-modified
a runtime primitive, not a ∴-driven cell. The spec's eval-one description
suggests the second model, but execute-modified is written as the first.

### 4. No ⊨? Recovery Policies (MINOR)

None of the 5 cells define ⊨? handlers. If any oracle fails, behavior is
unspecified. For a proof-of-concept program this is acceptable, but a
production version should specify retry policies at minimum for rebind
(which has the highest failure risk).

### 5. Missing: § on Crystallized Cells (MINOR)

The program only quotes a soft cell (greet has ∴). What happens when you
quote a crystallized cell (one with ⊢=)? Does § capture the ⊢= expression?
Can you modify and re-execute it? A second test cell (e.g., a ⊢= arithmetic
cell) would make the quotation roundtrip more complete.

---

## Specific Recommendations for Cell v0.1 Spec

### From This Program

1. **Define § data format** — Specify whether § gives structured data (AST)
   or raw text. This program assumes structured access (`given-names()`,
   `yield-names()`, `contains ∴`). If these are valid ⊢= operations, § must
   give structured data.

2. **Clarify § vs execution state** — State explicitly: § gives the static
   template (declarations without yield bindings), not the current execution
   state. This is the data-not-executed invariant.

3. **Add body-preservation oracle pattern** — For cells that modify definitions
   (like rebind), the spec should recommend an oracle pattern that verifies
   only the intended changes were made: `⊨ §modified differs from §original
   only at <path>`.

4. **Define meta-evaluation** — When a cell's ∴ says "execute this definition,"
   does the LLM interpret it, or does the runtime handle it? The answer
   determines whether meta-evaluators can be tested independently.

### Confirming Prior Findings

5. **Tautological oracle pattern persists** (R11 #5, R13 word-life) — 4/11
   oracles are tautological in this program. The pattern is consistent:
   ⊢= cells always have tautological oracles.

6. **Crystallization boundary confirmed** — execute-modified can never
   crystallize (it interprets arbitrary ∴ bodies). This matches the spec's
   "any cell that executes §-referenced cells is an interpreter" principle.

7. **Interface freeze works** — The `same given/yield signature` oracle
   successfully constrains rebind's output. This validates the Liskov
   substitution principle for cells from the spec.

---

## Confidence Rating

**Confidence: 9/10**

High confidence in the execution trace. The program is small (5 cells, 4 LLM
calls) with clear data flow. The quotation semantics are well-exercised.

**Uncertainty sources**:
1. Whether rebind's LLM output would EXACTLY preserve the ∴ body (the
   safety gap). In practice, LLMs tend to faithfully copy text when instructed,
   but edge cases exist (reformatting, synonym substitution).
2. The exact form of §greet — whether the Cell runtime provides it as
   structured data or raw text affects describe's crystallization status.
3. Whether roundtrip's "same structure" judgment is stable across LLMs —
   different models might disagree on what constitutes structural similarity.
