# CZ Exercise: Mixed Hard/Soft Cells — Simulation Trace

*Exercise bead: ce-azfv*
*Program: `docs/examples/mixed-hard-soft.cell`*

## Program Under Test

Three cells on the crystallization spectrum:

| Cell | Turnstile | Kind | Substrate | Role |
|------|-----------|------|-----------|------|
| solve | ⊢ | soft | LLM | Find x (NP search) |
| substitute | ⊢= | hard | Classical | Verify x (P check) |
| explain | ⊢ | soft | LLM | Interpret result |

## cell-zero Evaluation: How ⊢= Differs from ⊢

### Phase 1: read-graph

```
cells = [solve, substitute, explain]
edges = [
  solve→x        → substitute.given[0]
  solve→x        → explain.given[0]
  solve→proof    → explain.given[1]
  substitute→holds → explain.given[2]
]
```

Initial state (h0): all yields unbound. Two `given` values are pre-bound:
- `solve.equation ≡ "2x + 3 = 11"`
- `substitute.equation ≡ "2x + 3 = 11"`

### Phase 2: check-inputs (h0)

- **solve**: all givens bound (equation ≡ "2x+3=11") → READY
- **substitute**: given solve→x unbound → BLOCKED
- **explain**: given solve→x, solve→proof, substitute→holds unbound → BLOCKED

ready-cells = [solve]

### Phase 3: pick-cell → solve (only candidate)

---

## PATH A: Correct Answer (x=4)

### Iteration 1: Evaluate solve

**Phase 4 (evaluate):** Cell has ∴ body → invoke LLM substrate.

The LLM receives:
```
Solve "2x + 3 = 11" for x. Show your work as proof (list of steps).
```

Tentative outputs:
- x = 4
- proof = ["2x + 3 = 11", "2x = 11 - 3", "2x = 8", "x = 8/2", "x = 4"]

**Phase 5 (spawn-claims):** One oracle: `⊨ x is a number`

This is a **semantic oracle** (requires judgment, not exact value match).
cell-zero spawns a claim cell with a ∴ body:
```
⊢ claim-solve-oracle-1
  given tentative-x ≡ 4
  yield pass
  ∴ Is «tentative-x» a number?
```

**Phase 6 (check-claims):** LLM evaluates claim → pass ✓ (4 is a number)

**Phase 7 (decide):** all-pass = true → FREEZE

State transition h0 → h1:
```
⊢ solve
  given equation ≡ "2x + 3 = 11"
  yield x ≡ 4, proof ≡ ["2x + 3 = 11", "2x = 11 - 3", "2x = 8", "x = 8/2", "x = 4"]
```

### Iteration 2: check-inputs (h1)

- **solve**: FROZEN
- **substitute**: given solve→x now bound (≡ 4) ✓, equation bound ✓ → READY
- **explain**: solve→x bound ✓, solve→proof bound ✓, but substitute→holds still unbound → BLOCKED

ready-cells = [substitute]

### Iteration 2: Evaluate substitute

**Phase 4 (evaluate):** Cell has ⊢= body → **classical substrate** (NOT LLM).

cell-zero sees `⊢=` and switches to deterministic evaluation:
```
⊢= holds ← eval(2 * solve→x + 3) = 11
```

Bind solve→x = 4 from state:
```
holds ← eval(2 * 4 + 3) = 11
holds ← eval(8 + 3) = 11
holds ← eval(11) = 11
holds ← true
```

This is **pure computation**. No LLM invocation. No ambiguity. The classical
substrate evaluates the expression and produces an exact result.

Tentative output: holds = true

**Phase 5 (spawn-claims):** One oracle: `⊨ holds = true`

This is a **deterministic oracle** — exact value check. cell-zero spawns a
claim cell with a ⊢= body (not ∴):
```
⊢= claim-substitute-oracle-1
  given tentative-holds ≡ true
  yield pass
  ⊢= pass ← (tentative-holds = true)
```

**Phase 6 (check-claims):** Classical evaluation → pass ✓ (true = true)

**Phase 7 (decide):** all-pass = true → FREEZE

State transition h1 → h2:
```
⊢= substitute
  given solve→x          -- resolved to 4
  given equation ≡ "2x + 3 = 11"
  yield holds ≡ true
```

### Iteration 3: check-inputs (h2)

- **solve**: FROZEN
- **substitute**: FROZEN
- **explain**: solve→x ≡ 4 ✓, solve→proof ≡ [...] ✓, substitute→holds ≡ true ✓ → READY

ready-cells = [explain]

### Iteration 3: Evaluate explain

**Phase 4 (evaluate):** Cell has ∴ body → invoke LLM substrate.

The LLM receives (with interpolation):
```
If true is true, explain the solution
["2x + 3 = 11", "2x = 11 - 3", "2x = 8", "x = 8/2", "x = 4"]
in plain English.
If false, say "The solution x=4 is WRONG because substitution failed."
```

Tentative output:
- explanation = "The equation 2x + 3 = 11 is solved by first subtracting 3 from both sides to get 2x = 8, then dividing both sides by 2 to find x = 4. Substituting back: 2(4) + 3 = 11 confirms the answer is correct."

**Phase 5 (spawn-claims):** Two oracles:
1. `⊨ explanation mentions the value of x` — semantic (LLM)
2. `⊨ if substitute→holds then explanation is positive` — semantic (LLM)

Both spawn claim cells with ∴ bodies.

**Phase 6 (check-claims):**
1. Does "...x = 4..." mention the value of x? → pass ✓
2. substitute→holds is true, and explanation is positive → pass ✓

**Phase 7 (decide):** all-pass = true → FREEZE

State transition h2 → h3:
```
⊢ explain
  given solve→x          -- resolved to 4
  given solve→proof      -- resolved to [...]
  given substitute→holds -- resolved to true
  yield explanation ≡ "The equation 2x + 3 = 11 is solved by..."
```

### check-inputs (h3): ready-cells = [] → QUIESCE

**Path A final state (h3):** All cells frozen, all oracles passed.

---

## PATH B: Wrong Answer (x=5)

### Iteration 1: Evaluate solve (LLM produces wrong answer)

**Phase 4 (evaluate):** ∴ body → LLM substrate. This time the LLM errs:

Tentative outputs:
- x = 5
- proof = ["2x + 3 = 11", "2x = 11 - 3", "2x = 8", "x = 8/3", "x ≈ 5"]

(The LLM made an arithmetic error in the last step.)

**Phase 5-6 (oracle check):** `⊨ x is a number` → pass ✓ (5 is a number)

Note: this oracle is **too weak** to catch the error. It only checks the type,
not the value. This is by design — the *structural* oracle on solve doesn't
verify correctness, only format. Correctness checking is delegated to substitute.

**Phase 7 (decide):** FREEZE

State h0 → h1:
```
⊢ solve
  given equation ≡ "2x + 3 = 11"
  yield x ≡ 5, proof ≡ ["2x + 3 = 11", "2x = 11 - 3", "2x = 8", "x = 8/3", "x ≈ 5"]
```

### Iteration 2: Evaluate substitute (catches the error)

**Phase 4 (evaluate):** ⊢= body → classical substrate.

```
⊢= holds ← eval(2 * solve→x + 3) = 11
```

Bind solve→x = 5:
```
holds ← eval(2 * 5 + 3) = 11
holds ← eval(10 + 3) = 11
holds ← eval(13) = 11
holds ← false
```

**The hard cell catches the soft cell's error.** This is deterministic — no
LLM judgment required. `2*5+3 = 13 ≠ 11`. The answer is wrong. Period.

Tentative output: holds = false

**Phase 5 (spawn-claims):** `⊨ holds = true`

Deterministic claim cell:
```
⊢= claim-substitute-oracle-1
  given tentative-holds ≡ false
  yield pass
  ⊢= pass ← (tentative-holds = true)
```

**Phase 6 (check-claims):** Classical evaluation → **FAIL** ✗ (false ≠ true)

**This is the critical moment.** The oracle on substitute says `holds = true`,
but holds is false. What happens next depends on whether substitute has a ⊨?
recovery policy.

**Phase 7 (decide):** Oracle failed, no ⊨? on substitute → **BOTTOM**

substitute's yield is frozen as ⊥:
```
⊢= substitute
  given solve→x          -- resolved to 5
  given equation ≡ "2x + 3 = 11"
  yield holds ≡ ⊥
```

**Wait — is this right?** Let's reconsider.

The oracle `⊨ holds = true` asserts that holds MUST be true. When solve
produces x=5, the deterministic computation yields holds=false, which
*violates* the oracle. But the oracle is on **substitute**, not on **solve**.

There are two interpretations:
1. **Oracle as contract:** ⊨ holds = true means "substitute guarantees holds=true".
   This would mean substitute itself failed — the oracle fires on substitute.
2. **Oracle as assertion on output:** ⊨ holds = true checks the output value.
   When holds=false, the oracle fails, and the cell goes to ⊥.

Under interpretation (2) — which aligns with the spec — substitute goes to ⊥.
This means explain gets `substitute→holds ≡ ⊥`.

But this loses information. The value `false` is meaningful — it tells explain
that the answer was wrong. Going to ⊥ throws that away.

**Better design (insight for morpheus):** The oracle on substitute should be
removed or changed. The ⊢= cell should always freeze its output (true or false),
since the computation itself can't fail. The oracle `⊨ holds = true` is
**misplaced** — it turns a meaningful false into an uninformative ⊥.

**For this simulation, we trace BOTH sub-paths:**

### Path B1: Oracle fires → ⊥ (strict spec interpretation)

State h1 → h2:
```
⊢= substitute
  yield holds ≡ ⊥
```

explain depends on substitute→holds. With holds ≡ ⊥ and no ⊥? handler:
explain is **permanently blocked**. The program quiesces with explain unfrozen.

This is **suboptimal** — the meaningful error signal is lost.

### Path B2: No oracle on substitute (recommended design)

If substitute had no `⊨ holds = true` oracle:

State h1 → h2:
```
⊢= substitute
  yield holds ≡ false
```

explain becomes READY with substitute→holds ≡ false.

### Iteration 3 (Path B2): Evaluate explain

**Phase 4 (evaluate):** ∴ body → LLM substrate.

The LLM receives:
```
If false is true, explain the solution [...] in plain English.
If false, say "The solution x=5 is WRONG because substitution failed."
```

Tentative output:
- explanation = "The solution x=5 is WRONG because substitution failed. Plugging x=5 into 2x+3 gives 13, not 11."

**Phase 5-6 (oracle checks):**
1. `⊨ explanation mentions the value of x` → "x=5" present → pass ✓
2. `⊨ if substitute→holds then explanation is positive` → substitute→holds is
   false, so the conditional is vacuously true → pass ✓

**Phase 7 (decide):** FREEZE

State h2 → h3:
```
⊢ explain
  yield explanation ≡ "The solution x=5 is WRONG because substitution failed..."
```

QUIESCE. Program complete with error correctly reported.

---

## Simulation Results (JSON)

```json
{
  "exercise": "mixed-hard-soft",
  "path_a_correct": {
    "solve": {
      "x": 4,
      "proof": ["2x + 3 = 11", "2x = 11 - 3", "2x = 8", "x = 8/2", "x = 4"]
    },
    "substitute": {"holds": true},
    "explain": "The equation 2x + 3 = 11 is solved by first subtracting 3 from both sides to get 2x = 8, then dividing by 2 to find x = 4. Substituting back confirms: 2(4) + 3 = 11.",
    "all_oracles_pass": true,
    "iterations": 3,
    "llm_invocations": 2,
    "classical_invocations": 1
  },
  "path_b_wrong": {
    "solve": {
      "x": 5,
      "proof": ["2x + 3 = 11", "2x = 11 - 3", "2x = 8", "x = 8/3", "x ≈ 5"]
    },
    "substitute": {"holds": false, "oracle_⊨_holds=true": "FAIL"},
    "explain_b1_strict": "BLOCKED (substitute→holds ≡ ⊥, no ⊥? handler)",
    "explain_b2_no_oracle": "The solution x=5 is WRONG because substitution failed. Plugging x=5 into 2x+3 gives 13, not 11.",
    "oracles": {
      "solve_oracle_1": "pass (5 is a number — too weak to catch error)",
      "substitute_oracle_1": "FAIL (false ≠ true)",
      "explain_oracle_1": "pass (mentions x=5)",
      "explain_oracle_2": "pass (vacuously true — holds is false)"
    }
  },
  "crystallization_insight": "⊢= cells differ from ⊢ cells in three ways: (1) SUBSTRATE — ⊢= uses classical computation, ⊢ uses LLM; (2) DETERMINISM — ⊢= always produces the same output for the same inputs, ⊢ is stochastic; (3) COST — ⊢= is near-free (arithmetic), ⊢ costs an LLM call. The key insight is that ⊢= cells CANNOT fail computationally — they always produce a result. Failure only comes from oracle assertions on their output, which is a design choice, not an intrinsic property.",
  "proof_carrying_assessment": "The pattern works excellently. The solve→substitute→explain chain is a textbook example of NP/P asymmetry: finding x is hard (LLM), checking x is trivial (eval). The hard cell acts as an unforgeable checkpoint — no matter how convincing the LLM's 'proof' looks, the substitution check is decisive. This pattern WOULD catch real errors, as demonstrated in Path B. The one weakness is oracle design: putting ⊨ holds = true on substitute converts a meaningful false into uninformative ⊥.",
  "feedback_for_morpheus": "The ⊢= / ⊢ distinction is clear and powerful. Three edge cases found: (1) ORACLE ON HARD CELLS — ⊨ holds = true on substitute is counterproductive; the ⊢= cell's output (true/false) is itself the verification signal. An oracle asserting the output must be true turns a meaningful negative into ⊥. Recommendation: hard cells should generally not have oracles asserting specific output values, since their output IS the ground truth. (2) VACUOUS TRUTH — the oracle '⊨ if substitute→holds then explanation is positive' is vacuously true when holds=false. This is logically correct but may surprise users. Consider requiring explicit handling of both branches. (3) ORACLE WEAKNESS — '⊨ x is a number' on solve is too weak to catch wrong numbers. This is actually GOOD design (separation of concerns), but should be documented: solve's oracle checks format, substitute checks correctness."
}
```

## Key Findings

### 1. How cell-zero handles ⊢= vs ⊢

| Aspect | ⊢ (soft) | ⊢= (hard) |
|--------|----------|-----------|
| Substrate | LLM (semantic) | Classical (deterministic) |
| Invocation | Send ∴ body as prompt | Evaluate expression |
| Output | Stochastic, may vary | Deterministic, always same |
| Can fail? | Yes (oracle fail → retry/⊥) | Computation can't fail; oracle can fail |
| Cost | Expensive (LLM call) | Near-free (arithmetic) |
| Oracle claims | ∴ body (semantic check) | ⊢= body (exact check) |

### 2. Does eval use LLM or deterministic computation?

For `⊢= holds ← eval(2 * solve→x + 3) = 11`:
**Deterministic computation.** The `⊢=` turnstile is the signal. cell-zero's
`evaluate` phase explicitly branches: "If it has a ⊢= body: compute the
deterministic expression." No LLM involved.

### 3. Error detection works

Path B confirms: solve produces x=5 (wrong), substitute catches it with
`2*5+3 = 13 ≠ 11 → holds = false`. The hard cell is an unforgeable checkpoint.

### 4. Design issue: oracle on hard cells

The `⊨ holds = true` oracle on substitute is problematic — it converts the
meaningful `false` result into `⊥`. Hard cells should freeze their output
unconditionally; downstream cells should branch on the value.
