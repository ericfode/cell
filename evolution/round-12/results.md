# Round 12 Results: T3 — Multi-Agent Negotiation (Cold Read)

**Polecat**: thunder | **Date**: 2026-03-10 | **Rating**: 8/10

## Program Overview

8 cells modeling a three-party real estate negotiation (buyer, seller, mediator)
across 3 rounds with ⊥ propagation on rejection or walk-away. The program sets up
an adversarial deadzone ($150K gap between buyer budget $800K and seller minimum
$950K) that must be bridged through creative terms.

The program is a linear DAG with fan-out at setup (→ buyer-strategy, seller-strategy,
mediator-assessment) that re-converges at round-1, then flows sequentially through
rounds 2–3 → resolution → post-mortem.

---

## Q1: Step-by-Step Execution (All Intermediate States)

### Cell: `setup` (⊢= + ∴ hybrid)

**Inputs**: Hardcoded givens (item, buyer-budget=800000, seller-minimum=950000, max-rounds=5).

**Crystallized computation**:
```
deadzone ← 950000 - 800000 = 150000
```

**LLM call**: ∴ generates `negotiation-context` — describes the property, market
conditions, and the $150K deadzone.

**Oracles**:
- `⊨ negotiation-context mentions the property and both parties' constraints` → PASS (LLM output must reference warehouse + constraints)
- `⊨ deadzone = 150000` → PASS (deterministic, always true — tautological oracle on ⊢=)

**State after**: `{negotiation-context: <text>, deadzone: 150000}`

### Cells: `buyer-strategy`, `seller-strategy`, `mediator-assessment` (parallel fan-out)

These three cells depend only on setup outputs and are **independent** — they can
execute in parallel (or any order).

**buyer-strategy**:
- Inputs: `setup→negotiation-context`, `setup→buyer-budget` (800000)
- LLM call: Generate opening-offer, strategy, concessions[]
- Oracles: opening-offer < 800000 ∧ opening-offer > 0 ∧ |concessions| ≥ 2 ∧ strategy is 2-4 sentences
- Expected state: e.g. `{opening-offer: 650000, strategy: "Collaborative but firm...", concessions: ["quick close", "as-is purchase", "flexible timeline"]}`

**seller-strategy**:
- Inputs: `setup→negotiation-context`, `setup→seller-minimum` (950000)
- LLM call: Generate asking-price, strategy, walk-away-triggers[]
- Oracles: asking-price > 950000 ∧ |walk-away-triggers| ≥ 2 ∧ strategy is 2-4 sentences
- Expected state: e.g. `{asking-price: 1100000, strategy: "Start high, concede slowly...", walk-away-triggers: ["offer below 900K", "unreasonable timeline demands"]}`

**mediator-assessment**:
- Inputs: `setup→negotiation-context`, `setup→deadzone` (150000)
- Crystallized: `feasibility ← "possible"` (since 100000 < 150000 ≤ 200000)
- LLM call: Generate bridging-strategies[]
- Oracles: feasibility ∈ {"likely","possible","unlikely"} ∧ |bridging-strategies| ≥ 3 ∧ each explains gap reduction
- Expected state: `{feasibility: "possible", bridging-strategies: ["seller financing", "earnout", "phased closing", ...]}`

**Note**: The feasibility oracle is **tautological** — `feasibility` is computed by ⊢= and
the oracle checks it's in the set. With deadzone=150000, it's always "possible". This
oracle can never fail. (Recurring pattern from R11 finding #2.)

### Cell: `round-1` (convergence point — first ⊥ risk)

**Inputs**: opening-offer, concessions (from buyer), asking-price, walk-away-triggers
(from seller), bridging-strategies (from mediator).

**LLM call**: Simulate Round 1 — buyer opens at $opening-offer, seller responds.

**Crystallized**:
```
round-1-status ← if seller-counter-1 = ⊥ then "rejected"
                  else if |buyer-offer-1 - seller-counter-1| < 50000 then "close"
                  else "ongoing"
```

**Oracle checks**:
- `buyer-offer-1 = opening-offer` — buyer leads with planned offer
- `seller-counter-1 ≠ ⊥ → seller-counter-1 ≤ asking-price` — seller doesn't counter above ask
- `round-1-status ∈ {"rejected", "close", "ongoing"}`

**Recovery**: `⊨? on failure: retry with oracle.failures max 1` then `error-value(⊥)`.

**Likely outcome**: With ~$650K offer vs ~$1.1M ask, gap is ~$450K. Status = "ongoing".
The seller is unlikely to reject outright (the offer is within the "insultingly low but
not walk-away" range). seller-counter-1 might be ~$1.05M.

**⊥ path**: If the opening offer triggers a walk-away trigger (e.g., below $900K with
a trigger "offer below $900K"), seller-counter-1 = ⊥, round-1-status = "rejected".
After retry+exhaustion → error-value(⊥). This ⊥ propagates forward.

### Cell: `round-2` (⊥ propagation gate)

**Inputs**: round-1 outputs + buyer concessions + bridging-strategies.

**⊥ guards** (lines 101-102):
```
given round-1→round-1-status ⊥? skip with buyer-offer-2 ≡ ⊥, ...round-2-status ≡ "collapsed"...
given round-1→seller-counter-1 ⊥? skip with ... (same collapsed state)
```

Two independent ⊥ guards on the same upstream cell. If round-1 produced ⊥ through
either path, round-2 collapses without an LLM call.

**LLM call** (happy path): Simulate Round 2 — buyer raises, seller lowers, mediator
introduces bridging strategy.

**Crystallized**:
```
round-2-status ← if round-1-status = "rejected" then "collapsed"
                  else if |buyer-offer-2 - seller-counter-2| < 25000 then "near-deal"
                  else "ongoing"
```

**Oracles**: buyer-offer-2 > buyer-offer-1 ∧ seller-counter-2 < seller-counter-1 (monotonic convergence).

**Recovery**: `⊨? on failure: retry max 1` then `partial-accept(best)`.

**Likely outcome**: Gap narrows. Buyer ~$750K, seller ~$1M, gap ~$250K. Status = "ongoing".

**⊥ exhaustion path**: `partial-accept(best)` — takes the best attempt even if oracles
fail. This is DIFFERENT from round-1's `error-value(⊥)`. The program prefers a
partially-valid round-2 over propagating ⊥.

### Cell: `round-3` (crunch time — second major ⊥ risk)

**Inputs**: round-2 outputs + bridging-strategies + walk-away-triggers.

**⊥ guard**: `round-2→round-2-status ⊥? skip with ...collapsed...`

**LLM call**: Final offers, creative terms package, walk-away trigger check.

**Crystallized**:
```
round-3-status ← if seller-counter-3 = ⊥ then "walked-away"
                  else if buyer-offer-3 ≥ seller-counter-3 then "deal"
                  else if |buyer-offer-3 - seller-counter-3| < 10000 then "split-the-difference"
                  else "impasse"
```

**Oracles**: round-3-status in valid set; deal requires buyer ≥ seller; creative-terms
references a bridging strategy.

**Recovery**: `retry max 2` then `error-value(⊥)`. Most generous retry budget (3 total
attempts). This is the critical cell — the program gives it the most chances.

**Likely outcome with $150K deadzone**: The buyer can't reach $950K (budget is $800K).
The creative-terms must bridge the remaining gap. If seller financing of $150K+ is
offered, seller-counter-3 could drop to ~$850K with creative terms valued at ~$100K,
making a "split-the-difference" or "deal" possible. Otherwise: "impasse".

**Walk-away trigger**: This is the second ⊥ injection point. If a trigger fires,
seller-counter-3 = ⊥ → "walked-away" → ⊥ propagates to resolution.

### Cell: `resolution` (final ⊥ gate + computation)

**⊥ guard**: `round-3→round-3-status ⊥? skip with outcome ≡ "FAILED"...`

**Crystallized**:
```
final-price ← "deal" → buyer-offer-3 | "split-the-difference" → avg | else ⊥
outcome ← final-price ≠ ⊥ ? "DEAL" : "NO-DEAL"
```

**LLM call**: Write analysis (3-5 paragraphs) about the negotiation.

**Oracles**: DEAL → price is number; DEAL → analysis explains bridging; NO-DEAL →
analysis explains why gap couldn't close; analysis is 3-5 paragraphs.

### Cell: `post-mortem` (pure computation + one LLM call)

**Crystallized**:
```
buyer-satisfaction ← final-price=⊥ → 0; ≤800K → 100; else linear decay
seller-satisfaction ← final-price=⊥ → 0; ≥950K → 100; else linear decay
efficiency-score ← NO-DEAL → 0; else avg(buyer, seller)
```

**LLM call**: Write verdict (1 paragraph).

**Oracles**: satisfaction ∈ [0,100], verdict mentions both parties.

**Key insight for satisfaction scores**: If the deal happens at a price between
$800K and $950K (the deadzone), BOTH satisfaction scores will be below 100.
buyer-satisfaction < 100 if price > $800K. seller-satisfaction < 100 if price < $950K.
Any deal that bridges the deadzone with price alone will leave both parties
partially dissatisfied. Only creative terms (valued separately from price) can
produce high satisfaction for both.

---

## Q2: Which Cells Crystallize? Which Must Stay Soft?

| Cell | Type | Crystallizes? | Reason |
|------|------|---------------|--------|
| setup | Hybrid | **Partial** — `deadzone` crystallizes (⊢=), `negotiation-context` stays soft (∴) | Context generation requires LLM |
| buyer-strategy | Soft | **No** | Strategy, offers, concessions all require LLM creativity |
| seller-strategy | Soft | **No** | Same — strategic reasoning needs LLM |
| mediator-assessment | Hybrid | **Partial** — `feasibility` crystallizes, `bridging-strategies` stays soft | Feasibility is a simple conditional; strategies need LLM |
| round-1 | Hybrid | **Partial** — `round-1-status` crystallizes (conditioned on LLM outputs), but the round simulation is soft | Status is deterministic from LLM-produced values |
| round-2 | Hybrid | **Partial** — same pattern as round-1 | |
| round-3 | Hybrid | **Partial** — same pattern | |
| resolution | Hybrid | **Partial** — `final-price`, `outcome` crystallize; `analysis` is soft | Price/outcome are deterministic; analysis needs LLM |
| post-mortem | Hybrid | **Mostly crystal** — satisfaction scores and efficiency are ⊢=; only `verdict` is soft | 3 of 4 yields are deterministic |

**Pattern**: Every cell except buyer-strategy and seller-strategy has at least one
crystallized output. The program separates "compute" from "create" within cells.
This is a strong design pattern — each cell does its deterministic bookkeeping
via ⊢= and delegates creative work to ∴.

**post-mortem is the most crystallized cell** (3/4 yields deterministic). It could
almost be split into a pure ⊢= cell + a separate verdict cell.

---

## Q3: Oracle Checks — PASS/FAIL Trace

| # | Cell | Oracle | Verdict | Reasoning |
|---|------|--------|---------|-----------|
| 1 | setup | `negotiation-context mentions property + constraints` | **PASS** | LLM is instructed to include these; straightforward prompt |
| 2 | setup | `deadzone = 150000` | **TAUTOLOGY** | Computed by ⊢=, always 150000. Can never fail. |
| 3 | buyer-strategy | `opening-offer < 800000` | **PASS** (likely) | LLM told to leave room; but could fail if LLM opens at exactly 800K |
| 4 | buyer-strategy | `opening-offer > 0` | **PASS** | Essentially impossible to fail |
| 5 | buyer-strategy | `concessions ≥ 2 items` | **PASS** (likely) | Prompt explicitly asks for concessions list |
| 6 | buyer-strategy | `strategy is 2-4 sentences` | **PASS** (likely) | But sentence counting is fuzzy |
| 7 | seller-strategy | `asking-price > 950000` | **PASS** (likely) | LLM told to start above minimum |
| 8 | seller-strategy | `walk-away-triggers ≥ 2` | **PASS** (likely) | Prompt asks for them |
| 9 | seller-strategy | `strategy is 2-4 sentences` | **PASS** (likely) | Same fuzzy counting |
| 10 | mediator | `feasibility ∈ set` | **TAUTOLOGY** | Computed by ⊢=; always "possible" |
| 11 | mediator | `bridging-strategies ≥ 3` | **PASS** (likely) | Prompt asks for multiple strategies |
| 12 | mediator | `each strategy explains gap reduction` | **SOFT CHECK** | Requires semantic judgment — can the runtime verify this? |
| 13 | round-1 | `buyer-offer-1 = opening-offer` | **FRAGILE** | Requires LLM to echo an exact number; could fail if LLM rounds or reinterprets |
| 14 | round-1 | `seller-counter ≠ ⊥ → counter ≤ asking-price` | **PASS** (likely) | Reasonable constraint |
| 15 | round-1 | `round-1-status ∈ set` | **TAUTOLOGY** | Computed by ⊢= from cell outputs |
| 16 | round-2 | `buyer-offer-2 > buyer-offer-1` | **PASS** (likely) | Monotonic increase is prompted |
| 17 | round-2 | `seller-counter-2 < seller-counter-1` | **PASS** (likely) | Monotonic decrease is prompted |
| 18 | round-2 | `round-2-status ∈ set` | **TAUTOLOGY** | Same ⊢= pattern |
| 19 | round-3 | `round-3-status ∈ set` | **TAUTOLOGY** | Same pattern |
| 20 | round-3 | `deal → buyer ≥ seller` | **TAUTOLOGY** | Follows from ⊢= definition of status |
| 21 | round-3 | `creative-terms mentions bridging strategy` | **SOFT CHECK** | Semantic verification needed |
| 22 | resolution | `DEAL → final-price is number` | **TAUTOLOGY** | ⊢= guarantees this |
| 23 | resolution | `DEAL → analysis explains bridging` | **SOFT CHECK** | Semantic, but well-prompted |
| 24 | resolution | `NO-DEAL → analysis explains failure` | **SOFT CHECK** | Semantic |
| 25 | resolution | `analysis is 3-5 paragraphs` | **PASS** (likely) | Length constraint, can count |
| 26 | post-mortem | `satisfaction ∈ [0,100]` | **TAUTOLOGY** | ⊢= with max(0,...) guarantees range |
| 27 | post-mortem | `verdict mentions both parties` | **SOFT CHECK** | Easy for LLM to satisfy |

**Summary**: 27 oracle checks total.
- **7 tautological** (#2, 10, 15, 18, 19, 20, 22, 26) — can never fail, computed by ⊢=
- **5 soft/semantic** (#12, 21, 23, 24, 27) — require judgment, can't be mechanically verified
- **1 fragile** (#13) — requires exact number echo from LLM
- **14 structural** — straightforward constraints on LLM output

The **fragile oracle** (#13, `buyer-offer-1 = opening-offer`) is notable. It asks the
LLM to produce a specific number that was itself LLM-generated in a prior cell. The
round-1 cell must echo it exactly. If the LLM reinterprets (e.g., buyer opens at
$650K but round-1 LLM says "buyer opens at $660K"), this oracle fails and triggers
retry. This is the most likely failure point in the happy path.

---

## Q4: Minimum LLM Calls and LLM-Free Cells

### LLM-Free Computations

No cell is **entirely** LLM-free — every cell has at least one ∴ block or needs LLM
judgment. However, the ⊢= portions within cells are LLM-free:

- `setup.deadzone` — arithmetic
- `mediator-assessment.feasibility` — conditional
- `round-{1,2,3}-status` — conditional from LLM outputs
- `resolution.final-price`, `resolution.outcome` — conditional
- `post-mortem.{buyer,seller}-satisfaction`, `efficiency-score` — arithmetic

**13 ⊢= computations are LLM-free** across the 8 cells.

### Minimum LLM Calls (Happy Path)

| Cell | LLM Calls | Notes |
|------|-----------|-------|
| setup | 1 | negotiation-context |
| buyer-strategy | 1 | strategy + offers |
| seller-strategy | 1 | strategy + offers |
| mediator-assessment | 1 | bridging strategies |
| round-1 | 1 | negotiation simulation |
| round-2 | 1 | negotiation simulation |
| round-3 | 1 | negotiation simulation |
| resolution | 1 | analysis |
| post-mortem | 1 | verdict |
| **Total** | **9** | |

### Maximum LLM Calls (All Retries Exhausted)

| Cell | Max Calls | Calculation |
|------|-----------|-------------|
| setup | 1 | No retry configured |
| buyer-strategy | 1 | No retry configured |
| seller-strategy | 1 | No retry configured |
| mediator-assessment | 1 | No retry configured |
| round-1 | 2 | 1 initial + 1 retry (max 1) |
| round-2 | 2 | 1 initial + 1 retry (max 1) |
| round-3 | 3 | 1 initial + 2 retries (max 2) |
| resolution | 1 | No retry configured |
| post-mortem | 1 | No retry configured |
| **Total** | **13** | |

### ⊥ Collapse Path (Best Case)

If round-1 fails and exhausts → ⊥:
- round-1: 2 calls (initial + retry)
- round-2: **0** (⊥? skip)
- round-3: **0** (⊥? skip)
- resolution: **0** (⊥? skip, but wait — resolution's ⊥ guard produces "FAILED" with analysis="Negotiation collapsed before resolution", which is a literal string, not an LLM call)
- post-mortem: **1** (no ⊥ guard! it always runs because its inputs are computed, not ⊥)

Actually — checking post-mortem more carefully: it takes `resolution→outcome`, `resolution→final-price`, `resolution→analysis`. These are all populated by the skip-with defaults ("FAILED", ⊥, "Negotiation collapsed..."). The ⊢= formulas for satisfaction use `final-price = ⊥ → 0`, so they work. The verdict ∴ still runs. Total on ⊥ path:

**setup(1) + buyer(1) + seller(1) + mediator(1) + round-1(2) + post-mortem(1) = 7 calls**

Confirmed: ⊥ propagation saves 2-6 LLM calls (rounds 2-3 + resolution analysis).
This validates the R11 finding "exhaustion is cheaper than late success."

---

## Q5: Program Clarity Rating — 8/10

**Strengths:**
- **Excellent domain mapping**: The negotiation metaphor is instantly legible. Rounds,
  offers, counters, walk-away triggers — all map cleanly to Cell primitives.
- **Progressive ⊥ propagation**: Each round's ⊥? guard is clear about what causes
  collapse and what the collapsed state looks like.
- **Hybrid ⊢=/∴ pattern**: Every cell computes what it can deterministically and
  delegates only the creative parts to LLM. This is the right pattern.
- **Explicit skip-with values**: Every ⊥? skip provides full default state. No ambiguity
  about what downstream cells receive on failure.
- **Graduated retry budgets**: round-1 gets 1 retry, round-2 gets 1, round-3 gets 2.
  More retries at the critical point. Smart design.

**Weaknesses:**
- **`max-rounds` declared but unused**: setup declares `max-rounds ≡ 5` but only 3
  rounds are actually implemented. This is a dead given that suggests the program was
  designed for 5 rounds but implemented with 3. A reader wonders: where are rounds 4-5?
- **round-2 has redundant ⊥ guards**: Lines 101-102 guard on both `round-1-status` and
  `seller-counter-1` independently. But if round-1-status = ⊥, then ALL of round-1's
  outputs are ⊥ (including seller-counter-1). The second guard is redundant with the
  first unless partial ⊥ is possible (some yields ⊥, others not). The semantics of
  partial cell failure are unclear.
- **Tautological oracles add noise**: 7 of 27 oracles can never fail. They clutter the
  program with false confidence checks.
- **`partial-accept(best)` is under-specified**: round-2's exhaustion handler. What is
  "best"? Best of the failed attempts? Which metric? This recovery strategy is vague
  compared to round-1/round-3's clean `error-value(⊥)`.

**Could I maintain this program?** Yes. The structure is linear and predictable. Each
round follows the same pattern (inputs → LLM simulation → crystallized status → oracles
→ recovery). Adding round-4 would be mechanical. The main maintenance risk is the
growing number of `given` lines as rounds accumulate history.

---

## Q6: Fragility Analysis — What Breaks If You Remove Any Single Cell?

| Removed Cell | Impact | Severity |
|-------------|--------|----------|
| **setup** | Everything breaks — all cells depend on negotiation-context, budget, or minimum | **FATAL** |
| **buyer-strategy** | round-1 has no opening-offer or concessions; entire buyer side collapses | **FATAL** |
| **seller-strategy** | round-1 has no asking-price or walk-away-triggers; entire seller side collapses | **FATAL** |
| **mediator-assessment** | round-1 loses bridging-strategies; rounds 2-3 lose mediation input. Negotiation could still proceed (buyer/seller can negotiate directly) but the deadzone-bridging mechanism is gone | **HIGH** — deal much less likely without mediator |
| **round-1** | round-2 has no inputs, ⊥? guards fire, entire negotiation collapses to "collapsed" | **FATAL** — but gracefully (⊥ propagation works correctly) |
| **round-2** | round-3 has no inputs, ⊥? guard fires, collapses to "collapsed" | **FATAL** — but gracefully |
| **round-3** | resolution has no inputs, ⊥? guard fires, collapses to "FAILED" | **FATAL** — but gracefully |
| **resolution** | post-mortem has no outcome/price/analysis; satisfaction all 0 | **HIGH** — post-mortem still computes but meaninglessly |
| **post-mortem** | No downstream consumers. Program produces a deal but no evaluation. | **LOW** — the negotiation itself is complete |

**Key insight**: The program has **excellent graceful degradation** for round removals.
If any round cell is removed, the ⊥? guards propagate the failure cleanly through all
downstream rounds to a "FAILED" resolution. This is exactly what adversarial ⊥
propagation should look like — the ⊥ doesn't crash the program, it routes through the
failure track to a well-defined terminal state.

**The mediator is the only "optional" actor** — removing it degrades the negotiation
quality but doesn't cause structural failure. This reflects the real-world role of a
mediator: helpful but not structurally required.

**post-mortem is a pure leaf node** — removing it has zero impact on the negotiation
outcome. It's an observer, not a participant.

---

## Q7: Trust Boundaries

### Must Be Trusted (LLM output accepted at face value)

| Cell | Trusted Output | Risk |
|------|---------------|------|
| buyer-strategy | `opening-offer`, `strategy`, `concessions` | LLM could give strategically incoherent advice |
| seller-strategy | `asking-price`, `strategy`, `walk-away-triggers` | Walk-away triggers define ⊥ injection points — LLM controls when negotiation dies |
| round-1,2,3 | Negotiation simulation | LLM plays both sides; no adversarial separation |
| resolution | `analysis` text | Pure narrative — trusted for coherence |
| post-mortem | `verdict` text | Pure narrative |

### Verified (Oracle-Checked)

| Cell | Verified Property | Strength |
|------|------------------|----------|
| buyer-strategy | offer < budget, offer > 0, ≥2 concessions | **Medium** — structural only, not strategic quality |
| seller-strategy | price > minimum, ≥2 triggers | **Medium** |
| mediator | ≥3 strategies, each explains gap reduction | **Soft** — "explains gap reduction" is semantic |
| rounds 1-3 | Monotonic convergence, status validity | **Strong** — prevents degenerate negotiations |
| resolution | DEAL → price is number, analysis covers topic | **Medium** |

### Trust Boundary Analysis

**The critical trust boundary is at the round cells.** The LLM simultaneously plays
buyer, seller, and mediator within each round's ∴ prompt. There's no mechanism ensuring
the LLM doesn't "cheat" — e.g., having the buyer magically know the seller's minimum,
or having the seller concede unrealistically fast.

The oracles provide **behavioral constraints** (monotonic convergence, valid statuses)
but not **strategic integrity**. You can verify the negotiation follows the rules without
verifying it follows realistic negotiation dynamics.

**Walk-away triggers are a trust-critical input.** The seller-strategy cell's LLM
output defines the triggers that cause ⊥ in round-3. This means the LLM indirectly
controls whether the program enters the ⊥ path. If the LLM generates an easily-triggered
walk-away condition (e.g., "any offer below $950K"), the negotiation is designed to fail.
There's no oracle checking that walk-away triggers are *reasonable*.

**The ⊢= computations are fully trustworthy** — all satisfaction scores, statuses, prices,
and outcomes are deterministic from LLM-produced values. The trust boundary is
precisely at the LLM/crystal boundary.

---

## Additional Analysis: Adversarial ⊥ Propagation

This program was specifically designed to test adversarial ⊥ propagation (per R11
synthesis request). Here's the trace of every failure path:

### ⊥ Injection Points

1. **round-1: seller rejects** → seller-counter-1 = ⊥ → round-1-status = "rejected"
   → After retry+exhaustion: error-value(⊥) → round-1 yields ⊥

2. **round-2: oracle failure** → Monotonic convergence violated → After
   retry+exhaustion: partial-accept(best) → round-2 yields degraded-but-not-⊥ values

3. **round-3: seller walks away** → seller-counter-3 = ⊥ → round-3-status = "walked-away"
   → After retry+exhaustion: error-value(⊥) → round-3 yields ⊥

4. **round-3: impasse** → round-3-status = "impasse" → resolution computes
   final-price = ⊥, outcome = "NO-DEAL" — this is a **value-level ⊥**, not a cell-level ⊥

### ⊥ Propagation Chains

**Chain A** (early rejection): round-1→⊥ → round-2 ⊥?skip("collapsed") → round-3 ⊥?skip("collapsed") → resolution ⊥?skip("FAILED") → post-mortem(all zeros)

**Chain B** (walk-away): round-1→ok → round-2→ok → round-3→⊥ → resolution ⊥?skip("FAILED") → post-mortem(all zeros)

**Chain C** (impasse, no ⊥): round-1→ok → round-2→ok → round-3→"impasse" → resolution computes NO-DEAL with ⊥ price → post-mortem(all zeros)

**Key observation**: Chains A and C produce the same post-mortem result (all zeros)
but through different mechanisms. Chain A uses structural ⊥ propagation (⊥? skip with).
Chain C uses value-level ⊥ (final-price = ⊥ within a non-⊥ cell). The program
conflates two different failure modes into the same terminal state.

### The partial-accept Asymmetry

round-2's exhaustion handler is `partial-accept(best)` while round-1 and round-3 use
`error-value(⊥)`. This creates an asymmetry in the ⊥ propagation:

- round-1 failure → ⊥ cascades through rounds 2-3 (total collapse)
- round-2 failure → degraded values propagate (partial execution continues)
- round-3 failure → ⊥ stops at resolution (late collapse)

This is **intentional and correct** for negotiation semantics: round-2 is the "middle
ground" where you'd rather keep negotiating with imperfect state than give up. But it's
**under-specified** — "best" has no defined metric.

### Multi-Failure Scenario

Can multiple ⊥ injection points fire simultaneously? Only if round-1 succeeds but produces
values that cause BOTH round-2 and round-3 to fail. Since round-3 depends on round-2,
these are sequential, not simultaneous. The DAG is linear after the initial fan-out, so
there's no true "simultaneous failure" possible in rounds 2-3.

However, the initial fan-out (buyer-strategy, seller-strategy, mediator-assessment) COULD
have simultaneous failures if oracle retry was configured. Currently these cells have no
⊨? recovery, so they can't produce ⊥ — they either pass all oracles or the program has
no defined behavior. **This is a gap**: what happens if buyer-strategy's LLM produces
opening-offer = 800000 (exactly equal to budget, violating < constraint)?

**Answer**: Undefined. No recovery handler. The runtime would need to either:
(a) error without ⊥ semantics (hard failure), or
(b) implicitly retry (undefined behavior).

This is a design gap — the strategy cells should have ⊨? handlers.

---

## Summary of Findings

| Category | Finding |
|----------|---------|
| **Bug**: max-rounds unused | `max-rounds ≡ 5` declared but only 3 rounds implemented |
| **Bug**: redundant ⊥ guard | round-2 line 102 is redundant with line 101 (unless partial ⊥ exists) |
| **Bug**: missing recovery | buyer-strategy and seller-strategy have no ⊨? handlers |
| **Design**: partial-accept undefined | "best" has no metric in round-2's exhaustion handler |
| **Design**: tautological oracles | 7/27 oracles can never fail (⊢= outputs) |
| **Design**: fragile oracle | round-1's `buyer-offer-1 = opening-offer` requires exact LLM echo |
| **Strength**: graceful ⊥ degradation | Round removal → clean collapse via ⊥? guards |
| **Strength**: hybrid ⊢=/∴ pattern | Clean separation of deterministic and creative work |
| **Strength**: graduated retry budgets | Critical cells get more retries |
| **Strength**: explicit skip-with values | Every failure path has well-defined defaults |

**Overall Assessment**: This is the strongest ⊥ propagation program in the Cell evolution
series. It demonstrates both structural ⊥ (cell-level failure) and value-level ⊥
(final-price = ⊥ within a successful cell), graduated recovery strategies (error-value
vs partial-accept), and multi-hop ⊥ cascades. The adversarial scenario (buyer can't
afford seller's minimum) creates natural ⊥ pressure without artificial contrivance.

The main gaps are in under-specification (`partial-accept`, missing ⊨? on strategy cells)
and unnecessary complexity (unused max-rounds, redundant ⊥ guards, tautological oracles).
