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

---

# Round 12 T2: Research Agent — Cold-Read Analysis

## Mode: COLD READ (no syntax reference)
## Analyst: polecat fury
## Bead: ce-atw

---

## The Program

A 10-cell iterative research agent that formulates hypotheses, searches literature,
classifies evidence, assesses knowledge gaps, and iteratively refines the hypothesis
through an evolution loop containing nested spawners. The program embodies the hardest
composition case in Cell: `⊢∘` evolution driving `⊢⊢` spawning.

**Top-level data flow:**
```
seed → search(⊢⊢) → extract-evidence → assess-gaps → refine-hypothesis(⊢∘) → synthesize
                                                            │
                                                            ├── revise
                                                            ├── design-experiments(⊢⊢)
                                                            ├── run-experiments(⊢⊢)
                                                            └── update-evidence
```

---

## Q1: Step-by-Step Execution (All Intermediate States)

### Phase 1: Initialization

**⊢ seed** (lines 1-12)
```
Input:  topic = "What causes antibiotic resistance to spread between bacterial species?"
LLM call: 1
Output:
  hypothesis = "Antibiotic resistance spreads between bacterial species primarily
                through horizontal gene transfer mechanisms including conjugation,
                transformation, and transduction, with conjugative plasmids being
                the dominant vector in clinical settings." (example)
  key-terms = ["horizontal gene transfer", "conjugative plasmids",
               "antibiotic resistance genes", "mobile genetic elements",
               "interspecies conjugation"]
  knowledge-gaps = [
    "What environmental conditions accelerate interspecies HGT?",
    "Which resistance genes are most frequently transferred between species?",
    "How does biofilm formation affect the rate of conjugative transfer?"
  ]

Oracle checks:
  ⊨ hypothesis is 1-2 sentences         → PASS (2 sentences)
  ⊨ key-terms has exactly 5 items       → PASS (5 items)
  ⊨ knowledge-gaps has exactly 3 items  → PASS (3 items)
  ⊨ each knowledge-gap ends with ?      → PASS (all 3 end with ?)
```

### Phase 2: Literature Search (Spawner)

**⊢⊢ search** (lines 14-26)
```
Input:  seed→key-terms (5 items)
Spawning: 5 cells (one per key-term), max 5
LLM calls: 5

Spawned cell 1 ("horizontal gene transfer"):
  queries = ["horizontal gene transfer bacterial species mechanisms",
             "HGT frequency clinical isolates"]
  papers = [
    {title: "Mechanisms of HGT in Gram-negative bacteria", abstract: "...", relevance: 0.9},
    {title: "HGT rates in hospital environments", abstract: "...", relevance: 0.85},
    {title: "Evolutionary dynamics of HGT", abstract: "...", relevance: 0.7}
    ... (3 per query × 2 queries = 6 papers)
  ]

Spawned cells 2-5: similar structure, 6 papers each

Total §queries output: 5 items (one per key-term)
Total papers: ~30 (5 cells × 2 queries × 3 papers)

Oracle checks:
  ⊨ §queries has same length as seed→key-terms (5=5)  → PASS
  ⊨ each query yields papers[] with at least 2 entries → PASS (6 each)
```

### Phase 3: Evidence Classification

**⊢ extract-evidence** (lines 28-47)
```
Input:  search→§queries (all 30 papers), seed→hypothesis
LLM call: 1
Output:
  supporting = [{paper-title, key-claim, relationship-reasoning}, ...]  (~15 papers)
  contradicting = [{paper-title, key-claim, relationship-reasoning}, ...] (~5 papers)
  neutral = [{paper-title, key-claim, relationship-reasoning}, ...]  (~10 papers)

Oracle checks:
  ⊨ supporting + contradicting + neutral = total papers  → PASS (15+5+10=30)
  ⊨ each entry has paper-title, key-claim, reasoning      → PASS
  ⊨ contradicting non-empty → at least one has counter-evidence → PASS

Recovery available:
  ⊨? on failure: retry with oracle.failures, max 2
  ⊨? on exhaustion: partial-accept(best)
```

### Phase 4: Gap Assessment (Hybrid Cell)

**⊢ assess-gaps** (lines 48-62)
```
Input:  extract-evidence→supporting, extract-evidence→contradicting, seed→knowledge-gaps

Crystallized computation (no LLM needed for these):
  ⊢= filled-gaps ← filter(knowledge-gaps, g => any(supporting ++ contradicting, e => e.addresses(g)))
     Example: ["Which resistance genes are most frequently transferred?"] (1 filled)
  ⊢= remaining-gaps ← knowledge-gaps - filled-gaps
     Example: ["What environmental conditions accelerate interspecies HGT?",
               "How does biofilm formation affect conjugative transfer?"] (2 remaining)

LLM call: 1 (for new-gaps identification only)
  new-gaps = ["Does sub-inhibitory antibiotic concentration promote HGT?"] (example)

Oracle checks:
  ⊨ filled-gaps ∪ remaining-gaps = seed→knowledge-gaps  → PASS (1+2=3)
  ⊨ each new-gap is a question not in original gaps       → PASS
```

### Phase 5: Evolution Loop (⊢∘ refine-hypothesis)

**⊢∘ refine-hypothesis** (lines 64-73)
```
Initial state:
  §current-hypothesis = seed→hypothesis
  Loop body: revise → design-experiments → run-experiments → update-evidence
  Termination: remaining-gaps is empty ∨ confidence ≥ 0.8
  Max: 3 iterations
```

#### Iteration 1:

**⊢ revise** (lines 75-95)
```
Input:  §current-hypothesis = seed→hypothesis, contradicting (5 papers),
        remaining-gaps (2 items)
LLM call: 1
Output:
  §revised-hypothesis = "Antibiotic resistance spreads between bacterial species
    primarily through conjugative plasmids carrying integron-associated gene
    cassettes, with transfer rates significantly elevated in polymicrobial
    biofilm environments and under sub-inhibitory antibiotic pressure."
  revision-reasoning = "Narrowed from 'HGT mechanisms' to conjugative plasmids
    with integrons based on [Paper X] evidence. Added biofilm and sub-inhibitory
    conditions based on contradicting evidence from [Paper Y]."

Oracle checks:
  ⊨ revised more specific than current         → PASS (added integrons, biofilms, conditions)
  ⊨ reasoning cites evidence                   → PASS (cites Papers X, Y)
  ⊨ same given/yield signature preserved        → PASS
```

**⊢⊢ design-experiments** (lines 97-112)
```
Input:  remaining-gaps (2) ∪ new-gaps (1) = 3 gaps total
        revise→§revised-hypothesis
Spawning: 3 cells (one per gap), max 6
LLM calls: 3
Output: §experiments = [
  {prediction: "Biofilm conditions increase conjugation frequency 10x",
   confirming: "Transfer rates >10x in biofilm vs planktonic",
   refuting: "No significant difference in transfer rates"},
  {prediction: "Sub-inhibitory tetracycline promotes tet-gene transfer",
   confirming: "Increased tet-gene detection in sub-MIC cultures",
   refuting: "No change or decrease in tet-gene prevalence"},
  {prediction: "Environmental stress accelerates HGT via SOS response",
   confirming: "SOS induction correlates with increased HGT markers",
   refuting: "SOS response has no effect on transfer frequency"}
]

Oracle checks:
  ⊨ §experiments has at least length(remaining-gaps) items (3 ≥ 2) → PASS
  ⊨ each has testable prediction                                    → PASS
```

**⊢⊢ run-experiments** (lines 114-133)
```
Input:  §experiments (3 items)
Spawning: 3 cells, max 6
LLM calls: 3
Output: §results = [
  {classification: "confirms", confidence: 75},
  {classification: "confirms", confidence: 60},
  {classification: "inconclusive", confidence: 40}
]

Oracle checks:
  ⊨ §results same length as §experiments (3=3)           → PASS
  ⊨ each has classification ∈ {confirms,refutes,inconclusive} → PASS
  ⊨ each has confidence ∈ [0,100]                         → PASS
```

**⊢ update-evidence** (lines 135-152)
```
Input:  §results, extract-evidence→supporting (15), extract-evidence→contradicting (5)
LLM call: 1 (for ∴ merging)
Output:
  updated-supporting = supporting + [experiment-1-result, experiment-2-result] = 17 items
  updated-contradicting = contradicting = 5 items (no refutations)
  (inconclusive experiment-3 not classified)

Crystallized:
  ⊢= confidence ← (17 / (17 + 5 + 1)) * (avg(75, 60, 40) / 100)
                  = (17/23) * (58.33/100)
                  = 0.739 * 0.583
                  = 0.431

Oracle checks:
  ⊨ updated-supporting ⊇ supporting   → PASS (17 ⊇ 15)
  ⊨ updated-contradicting ⊇ contradicting → PASS (5 ⊇ 5)
  ⊨ confidence ∈ [0.0, 1.0]           → PASS (0.431)

Check termination: remaining-gaps empty (NO, still 2) ∨ confidence ≥ 0.8 (NO, 0.431)
→ CONTINUE to iteration 2
```

#### Iteration 2:

**⊢ revise**: §current-hypothesis = iteration-1's §revised-hypothesis. Further
refines based on same contradicting evidence and same remaining-gaps. LLM call: 1.

**⊢⊢ design-experiments**: Same gaps (2 remaining + 1 new = 3). Designs new
experiments testing the further-refined hypothesis. LLM calls: 3.

**⊢⊢ run-experiments**: Runs 3 experiments. LLM calls: 3.

**⊢ update-evidence**: Merges with ORIGINAL evidence (not accumulated — see Bug #1).
With better experiments: say 2 confirms (confidence 80, 70) + 1 confirms (65).
```
  updated-supporting = 15 + 3 = 18
  updated-contradicting = 5
  confidence = (18/24) * (71.67/100) = 0.75 * 0.717 = 0.538
```
Still < 0.8 → CONTINUE to iteration 3.

#### Iteration 3 (final, max reached):

Similar structure. Say confidence reaches 0.62. Loop exits (max 3 reached).
```
Final outputs:
  refined-hypothesis = (3x-revised version)
  confidence = 0.62
  revision-log = [revision-1-reasoning, revision-2-reasoning, revision-3-reasoning]
```

### Phase 6: Synthesis

**⊢ synthesize** (lines 154-178)
```
Input:  refined-hypothesis, confidence=0.62, revision-log (3 entries),
        supporting (15), contradicting (5), filled-gaps (1), remaining-gaps (2)
LLM call: 1

Crystallized:
  ⊢= conclusion-strength ← confidence ≥ 0.5 → "moderate"

Output:
  report = "Research report: Starting from hypothesis about HGT mechanisms...
            [cites 3+ pieces of evidence]... 1 of 3 gaps filled, 2 remain...
            Conclusion: moderate confidence (0.62)"
  conclusion-strength = "moderate"

Oracle checks:
  ⊨ report mentions original and final hypothesis → PASS
  ⊨ report cites ≥ 3 evidence pieces              → PASS
  ⊨ report lists remaining gaps                    → PASS
  ⊨ conclusion-strength matches confidence         → PASS (0.62 → "moderate")
```

---

## Q2: Crystallization Analysis

### Crystallized (⊢= — deterministic, LLM-free):

| Cell / Formula | Type | Why Crystallized |
|---------------|------|------------------|
| `assess-gaps.filled-gaps` | ⊢= formula | Pure filter operation over structured data |
| `assess-gaps.remaining-gaps` | ⊢= formula | Set subtraction — deterministic |
| `update-evidence.confidence` | ⊢= formula | Arithmetic on lengths and averages |
| `synthesize.conclusion-strength` | ⊢= formula | Threshold comparison on confidence |

### Must Stay Soft (LLM-required):

| Cell | Why Soft |
|------|----------|
| `seed` | Hypothesis formulation requires creative scientific reasoning |
| `search` spawned cells | Query formulation and paper simulation require domain knowledge |
| `extract-evidence` | Classifying paper-hypothesis relationships requires judgment |
| `assess-gaps` (new-gaps only) | Identifying unexpected findings requires inference beyond the structured data |
| `revise` | Hypothesis revision integrating contradictions requires scientific reasoning |
| `design-experiments` spawned cells | Experiment design requires creative/scientific thinking |
| `run-experiments` spawned cells | Simulating experiment outcomes requires domain knowledge |
| `update-evidence` (∴ portion) | Merging experiment results into evidence categories requires judgment |
| `synthesize` (report) | Writing a coherent research narrative requires language generation |

### Hybrid Cells:

**assess-gaps** is the most interesting case — it's a **partially crystallized cell**.
`filled-gaps` and `remaining-gaps` are ⊢= (deterministic), but `new-gaps` requires
LLM inference. This means the cell cannot be fully crystallized, but the crystallized
portions can be computed without an LLM call, and the LLM call is scoped to just
identifying emergent gaps.

**update-evidence** is similar: the ∴ instruction (merging) requires an LLM, but
`confidence` is a ⊢= formula computed from the LLM's output.

---

## Q3: Oracle Trace (All Checks)

### seed (4 checks, 0 retries available)
| # | Oracle | Result | Reasoning |
|---|--------|--------|-----------|
| 1 | `⊨ hypothesis is 1-2 sentences` | PASS | LLM instructed explicitly; easy constraint |
| 2 | `⊨ key-terms has exactly 5 items` | PASS | Count constraint — LLM can follow |
| 3 | `⊨ knowledge-gaps has exactly 3 items` | PASS | Count constraint |
| 4 | `⊨ each knowledge-gap is a question (ends with ?)` | PASS | Format constraint |

**Risk**: seed has NO retry/exhaustion handlers. If any oracle fails, the cell
produces ⊥ with no recovery path. For a root cell, this kills the entire program.
This is a fragility hotspot (see Q6).

### search (2 checks)
| # | Oracle | Result | Reasoning |
|---|--------|--------|-----------|
| 5 | `⊨ §queries has same length as seed→key-terms` | PASS | Spawner count matches input count |
| 6 | `⊨ each query yields papers[] with at least 2 entries` | PASS | 6 papers per query (3 per sub-query × 2) |

### extract-evidence (3 checks + retry)
| # | Oracle | Result | Reasoning |
|---|--------|--------|-----------|
| 7 | `⊨ supporting + contradicting + neutral = total papers` | PASS | Exhaustive classification |
| 8 | `⊨ each entry has paper-title, key-claim, reasoning` | PASS | Structural check |
| 9 | `⊨ if contradicting non-empty → specific counter-evidence` | PASS | Given scientific topic, contradictions likely |

Recovery: max 2 retries, then partial-accept(best). This is well-protected.

### assess-gaps (2 checks)
| # | Oracle | Result | Reasoning |
|---|--------|--------|-----------|
| 10 | `⊨ filled-gaps ∪ remaining-gaps = seed→knowledge-gaps` | PASS | **Tautological** — guaranteed by ⊢= formulas |
| 11 | `⊨ each new-gap is a question not in original gaps` | PASS | Novelty check on LLM output |

**Note**: Oracle #10 is tautological — the ⊢= formulas for filled-gaps and
remaining-gaps mathematically guarantee this property. This is an assertion, not a
constraint. Same pattern identified in R11-T2 (proof-carrying oracle).

### revise (3 checks + retry) — per iteration
| # | Oracle | Result | Reasoning |
|---|--------|--------|-----------|
| 12 | `⊨ revised more specific than current` | PASS/FAIL | Subjectivity risk — "more specific" is judgment-dependent |
| 13 | `⊨ reasoning cites evidence` | PASS | Structural check |
| 14 | `⊨ same given/yield signature` | PASS | Behavioral subtyping (Liskov) — structural check |

Oracle #12 is the weakest — "more specific" is subjective and hard to verify
mechanically. An LLM oracle checking another LLM's output for "specificity" is
essentially self-grading.

### design-experiments (2 checks) — per iteration
| # | Oracle | Result | Reasoning |
|---|--------|--------|-----------|
| 15 | `⊨ §experiments ≥ length(remaining-gaps)` | PASS | Count check |
| 16 | `⊨ each has testable prediction` | PASS | Structural check, but "testable" is subjective |

### run-experiments (2 checks + retry) — per iteration
| # | Oracle | Result | Reasoning |
|---|--------|--------|-----------|
| 17 | `⊨ §results same length as §experiments` | PASS | Count match |
| 18 | `⊨ each has classification ∈ {confirms, refutes, inconclusive}, confidence ∈ [0,100]` | PASS | Enum + range check |

Recovery: max 1 retry, then error-value(⊥). The ⊥ case triggers update-evidence's
skip-with handler.

### update-evidence (3 checks) — per iteration
| # | Oracle | Result | Reasoning |
|---|--------|--------|-----------|
| 19 | `⊨ updated-supporting ⊇ supporting` | PASS | Superset check |
| 20 | `⊨ updated-contradicting ⊇ contradicting` | PASS | Superset check |
| 21 | `⊨ confidence ∈ [0.0, 1.0]` | PASS | **Tautological** — guaranteed by ⊢= formula's arithmetic |

Oracle #21 is tautological: the formula's structure (ratio × ratio) always produces
a value in [0,1] given non-negative inputs.

### synthesize (4 checks)
| # | Oracle | Result | Reasoning |
|---|--------|--------|-----------|
| 22 | `⊨ report mentions original and final hypothesis` | PASS | Structural/content check |
| 23 | `⊨ report cites ≥ 3 evidence pieces` | PASS | Count check |
| 24 | `⊨ report lists remaining gaps` | PASS | Content check |
| 25 | `⊨ conclusion-strength matches confidence` | PASS | **Tautological** — both derived from same confidence value via ⊢= |

Oracle #25 is tautological: conclusion-strength is computed from confidence via ⊢=,
so they cannot disagree.

**Summary**: 25 oracle checks per full execution (with 3 tautological). Per iteration
of the evolution loop, 10 additional checks. Total for 3 iterations: 25 + 20 = 45 checks.

---

## Q4: LLM Call Analysis

### LLM-Free Components:
- `assess-gaps.filled-gaps` (⊢= filter)
- `assess-gaps.remaining-gaps` (⊢= set subtraction)
- `update-evidence.confidence` (⊢= arithmetic)
- `synthesize.conclusion-strength` (⊢= threshold)

### Call Count:

| Phase | Cell | Calls (min) | Calls (max) | Notes |
|-------|------|-------------|-------------|-------|
| Pre-loop | seed | 1 | 1 | No retry handler |
| Pre-loop | search (5 spawned) | 5 | 5 | One per key-term |
| Pre-loop | extract-evidence | 1 | 3 | +2 retries possible |
| Pre-loop | assess-gaps | 1 | 1 | For new-gaps only |
| **Pre-loop subtotal** | | **8** | **10** | |
| Per iteration | revise | 1 | 3 | +2 retries |
| Per iteration | design-experiments | 1-6 | 6 | One per gap |
| Per iteration | run-experiments | 1-6 | 12 | +1 retry each, or ⊥ |
| Per iteration | update-evidence | 1 | 1 | ∴ portion only |
| **Per iteration subtotal** | | **4-14** | **22** | |
| Post-loop | synthesize | 1 | 1 | |
| | | | | |
| **Total (1 iteration)** | | **13** | **33** | |
| **Total (3 iterations)** | | **21** | **77** | |

**Minimum path** (17 LLM calls): All oracles pass first time, 1 iteration with
minimum gaps (1 remaining + 0 new = 1 experiment), confidence hits 0.8.

**Realistic path** (~30-35 calls): Most oracles pass, 2-3 iterations, 3 experiments
per iteration, occasional retries.

**Maximum path** (77 calls): Every retry used, max 3 iterations, 6 experiments per
iteration, all run-experiments retry once.

### ⊥ Path Cost Analysis

If `run-experiments` exhausts retries → `error-value(⊥)`, then `update-evidence`
triggers its `⊥? skip with` handler: `updated-supporting ≡ supporting,
updated-contradicting ≡ contradicting, confidence ≡ 0.0`. This skips the LLM call
in update-evidence AND guarantees confidence = 0.0 < 0.8, forcing the loop to continue
(or exit at max). Consistent with R11 finding: ⊥ propagation converts downstream
LLM calls into free deterministic operations.

---

## Q5: Overall Clarity Rating: 7/10

### Strengths:
- **Pipeline structure is clear**: The seed→search→extract→assess→refine→synthesize
  flow reads naturally as a research workflow
- **Oracle constraints are well-specified**: Count checks, type checks, range checks
  are concrete and verifiable
- **Recovery paths are thoughtful**: extract-evidence and revise both have
  retry+partial-accept; run-experiments has retry+⊥; update-evidence has ⊥? skip with
- **The ⊢= formulas are excellent**: confidence calculation and conclusion-strength
  are precisely specified with no ambiguity
- **The § (cell-as-value) usage is consistent**: §queries, §experiments, §results,
  §current-hypothesis, §revised-hypothesis all clearly mark cells-as-data

### Weaknesses:
- **Evolution loop variable binding is implicit** (what binds §current-hypothesis to
  §revised-hypothesis across iterations? Nothing in the syntax makes this explicit)
- **Evidence accumulation bug** (see Bug #1 below)
- **Remaining-gaps stale reference bug** (see Bug #2 below)
- **"More specific" oracle is subjective** — oracle #12 depends on LLM judgment about
  LLM output, which is self-grading
- **seed has no recovery** — a root cell with 4 oracles and zero retry handlers is
  a single point of failure for the entire program

### Could I maintain this program?

Yes, with caveats. The top-level flow is immediately comprehensible. The individual
cells are well-specified. The main maintenance challenge is the evolution loop — its
implicit variable binding, stale reference issues, and the interaction between
nested spawners and the loop's termination condition would require careful attention
during any modification. I'd rate maintainability at 6/10 (the nested ⊢∘+⊢⊢ composition
is inherently complex, but the program doesn't do enough to make it explicit).

---

## Q6: Fragility Analysis (Single-Cell Removal)

| If Removed | Impact | Severity |
|------------|--------|----------|
| **seed** | Entire program dead — no hypothesis, no key-terms, no knowledge-gaps. Everything depends on seed. | FATAL |
| **search** | extract-evidence has no papers. ⊥ propagates through rest of pipeline. No evidence → confidence = 0 → "weak" conclusion on empty report. | CRITICAL |
| **extract-evidence** | No evidence classification → assess-gaps has no input → ⊥ propagates → refine-hypothesis has nothing to refine. | CRITICAL |
| **assess-gaps** | refine-hypothesis loses remaining-gaps and new-gaps inputs. The evolution loop has no gaps to address → design-experiments spawns nothing → empty experiments → run-experiments does nothing → update-evidence skips → confidence = 0.0. Loop runs 3 times doing nothing productive. | HIGH |
| **revise** | Evolution loop body is broken — can't advance §current-hypothesis. Loop runs 3 times with the same hypothesis. design-experiments still works (uses original gaps), but there's no hypothesis refinement. The loop becomes pure experiment-running with no learning. | HIGH |
| **design-experiments** | No experiments → run-experiments has nothing → update-evidence triggers ⊥ skip → confidence = 0.0 every iteration → loop runs 3 times, always "no experiments to run". | HIGH |
| **run-experiments** | update-evidence gets ⊥ → skip with confidence = 0.0. Same as design-experiments removal but one level deeper. | HIGH |
| **update-evidence** | Evolution loop never computes confidence → termination condition `confidence ≥ 0.8` can never be evaluated. Depends on runtime behavior — might default to false (loop runs max 3) or error out. | HIGH |
| **synthesize** | Program runs completely but produces no output. All computation is wasted. The refined hypothesis exists but is never communicated. | MODERATE |

**Most fragile cell**: `seed` — zero redundancy, zero recovery, everything depends on it.

**Least fragile cell**: `synthesize` — removing it loses the output but doesn't break
any computation. All upstream cells complete normally.

**Structural observation**: The linear pipeline topology means every cell is a single
point of failure for all downstream cells. There's no redundancy or alternative paths.
The ⊢⊢ spawners provide width (parallel processing) but not depth (alternative routes).

---

## Q7: Trust Boundaries

### Must Be Trusted (No External Verification Possible):

| Cell | Why Trusted |
|------|-------------|
| `seed` | Hypothesis quality determines the entire research direction. No oracle can verify that a hypothesis is "good" — only that it's structurally valid. A well-formed but scientifically nonsensical hypothesis passes all oracles. |
| `revise` | "More specific" oracle is self-grading. The LLM judges its own output's specificity. A trivially-specific revision ("only on Tuesdays") passes the oracle but degrades research quality. |
| `search` spawned cells | Paper simulation is entirely fabricated by the LLM. No oracle verifies that papers are real or that abstracts are plausible. The entire evidence base rests on trusted hallucination. |
| `run-experiments` spawned cells | Experiment results are simulated. No oracle checks scientific plausibility of results — only structural validity (enum + range). An experiment "confirming" with confidence 95 is trusted at face value. |

### Verified (Oracles Provide Real Constraints):

| Cell | Verification Quality |
|------|---------------------|
| `extract-evidence` | **Good** — exhaustive classification (sum check), structural completeness, counter-evidence requirement. Still trusts LLM judgment for classification accuracy, but the oracles catch gross failures. |
| `assess-gaps` | **Partial** — filled/remaining gap computation is crystallized (trustworthy). New-gap identification is trusted (LLM decides what's "new"). The ⊢= formulas are the trust anchor. |
| `update-evidence` | **Good** — superset checks ensure no evidence is lost. Confidence formula is crystallized. The ∴ merging is trusted but bounded by the formula. |
| `synthesize` | **Good** — content checks (mentions hypotheses, cites evidence, lists gaps) provide real verification. The conclusion-strength is crystallized. |

### Trust Boundary Map:

```
TRUSTED ZONE                    VERIFIED ZONE
(LLM output accepted           (Oracles catch failures)
 on structural validity only)

  seed ─────────────────────→ extract-evidence
  search (spawned cells) ───→    (sum check, structure)
                                    │
                              assess-gaps
                                (⊢= crystallized core)
                                    │
  revise ───────────────────→ update-evidence
  design-experiments ──────→    (superset check, ⊢= confidence)
  run-experiments ─────────→      │
                              synthesize
                                (content checks, ⊢= strength)
```

The **critical trust boundary** is between `search` and `extract-evidence`. Everything
in the trusted zone produces fabricated data (fake papers, fake experiment results).
The verified zone tries to reason about this fabricated data consistently. The oracles
ensure *internal consistency* but cannot verify *external validity*.

This is the fundamental limitation: the program is an internally-consistent reasoning
engine operating on hallucinated evidence. The trust boundary is at the program's
interface with reality — and this program has no such interface (it simulates everything).

---

## Bugs and Design Issues

### Bug #1: Evidence Accumulation Failure

`update-evidence` takes `extract-evidence→supporting` and `extract-evidence→contradicting`
as inputs — the ORIGINAL evidence, not the accumulated evidence from previous iterations.

In iteration 2, update-evidence merges iteration-2 experiment results with the original
extract-evidence output, discarding iteration-1's experiment results entirely.

**Impact**: The confidence formula only considers original evidence + current iteration's
experiments. Evidence doesn't accumulate across iterations. Each iteration starts fresh,
making convergence to confidence ≥ 0.8 much harder than intended.

**Fix**: update-evidence in iteration N should receive iteration-(N-1)'s
`updated-supporting` and `updated-contradicting` as inputs. This requires either:
- An explicit loop-variable mechanism for evidence (like §current-hypothesis)
- A `given §prev-supporting` pattern within the evolution body

### Bug #2: Stale Remaining-Gaps

The `until remaining-gaps is empty ∨ confidence ≥ 0.8` termination condition references
`remaining-gaps`, but nothing in the loop body updates it. The loop receives
`assess-gaps→remaining-gaps` once, and this value never changes.

**Impact**: The `remaining-gaps is empty` disjunct is dead code — it can only be true
if assess-gaps produced no remaining gaps (in which case, why enter the loop?). The
effective termination is just `confidence ≥ 0.8 ∨ iteration = max`.

**Fix**: The loop body should include a re-assessment step that updates remaining-gaps
based on experiment results. E.g., add a `re-assess` cell after `update-evidence` that
checks if new evidence fills any remaining gaps.

### Bug #3: seed Has No Recovery

The root cell has 4 oracle checks and zero retry/exhaustion handlers. If any oracle fails
(e.g., LLM produces 4 key-terms instead of 5), the entire program fails with no recovery.
Every other substantial cell has retry handlers.

**Fix**: Add `⊨? on failure: retry with oracle.failures, max 2` and a reasonable
exhaustion strategy (partial-accept or error-value).

### Bug #4: Empty Experiments Edge Case

If remaining-gaps = 0 AND new-gaps = 0 (all gaps filled, no new gaps), then
design-experiments spawns 0 cells, producing `§experiments = []`. run-experiments
receives empty input, produces `§results = []`. update-evidence then computes
`avg(results.confidence)` on an empty list — undefined behavior.

**Fix**: Handle the empty-experiments case explicitly in update-evidence, or add a
guard: `⊨ §experiments has at least 1 item` (but this would fail on the empty case).
Better: add `if §experiments is empty then skip update-evidence`.

### Bug #5: Oracle Self-Grading in revise

Oracle #12 (`⊨ §revised-hypothesis is more specific than §current-hypothesis`) asks
the oracle (likely another LLM call or the same LLM) to judge whether the LLM's output
is "more specific" than its input. This is self-grading — the same model class that
produced the output judges its quality. The oracle provides no independent verification.

**Not a bug per se**, but a trust boundary concern. Possible mitigation: define
"specificity" in terms of structural properties (more conditions, narrower scope
language, additional mechanisms cited) rather than subjective judgment.

---

## Summary

| Metric | Value |
|--------|-------|
| Total named cells | 10 |
| Spawner cells | 3 (search, design-experiments, run-experiments) |
| Evolution loops | 1 (refine-hypothesis) |
| Crystallized formulas | 4 (⊢=) |
| Oracle checks (per full run) | 25 base + 10 per iteration = up to 55 |
| Tautological oracles | 3 (#10, #21, #25) |
| LLM calls (min/realistic/max) | 17 / 30-35 / 77 |
| Clarity rating | 7/10 |
| Bugs found | 5 |
| Nesting depth | 3 (program → ⊢∘ evolution → ⊢⊢ spawner → spawned cell with ⊨? retry) |

This is the most complex Cell program analyzed to date. The nested ⊢∘ + ⊢⊢ composition
works structurally — the data flows are coherent and the oracle coverage is thorough.
The main issues are semantic: evidence doesn't accumulate (Bug #1), gaps don't update
(Bug #2), and the root cell is unprotected (Bug #3). These are fixable without
restructuring the program.

The trust boundary analysis reveals a fundamental property of research-simulation
programs: internal consistency ≠ external validity. The oracles ensure the program
reasons consistently about its fabricated data, but nothing grounds that data in reality.
This is appropriate for the program's stated purpose (an agent that *formulates and
refines* hypotheses) but would be a critical gap if the output were treated as actual
research findings.
