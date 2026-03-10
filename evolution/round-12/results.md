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

# Round 12 Results: T1 — Code Review Pipeline

## Mode: COLD READ (no syntax reference)

## The Program

A 10-definition, 18+ runtime-instance code review pipeline. Input: a unified
diff adding a `verify_token` function with an SQL injection vulnerability.
Pipeline: parse → fan-out analysis (4 reviewers) → merge → prioritize →
fan-out fix generation → apply → fan-out re-analysis → final verdict.

**Cell inventory (10 definitions):**

| # | Cell | Type | Sigil | Purpose |
|---|------|------|-------|---------|
| 1 | `parse-diff` | regular | `⊢` | Parse unified diff into structured components |
| 2 | `analyze` | spawner | `⊢⊢` | Fan-out: spawn 4 reviewer cells |
| 3 | `§review-template` | template | `⊢ §` | Per-review-type analysis (security/perf/correctness/style) |
| 4 | `merge-reviews` | regular | `⊢` | Merge + deduplicate findings, determine severity |
| 5 | `prioritize` | regular | `⊢` | Convert findings to ranked action items |
| 6 | `generate-fixes` | spawner | `⊢⊢` | Fan-out: spawn fix cell per action item |
| 7 | `§fix-template` | template | `⊢ §` | Generate unified diff patch for one action item |
| 8 | `apply-fixes` | regular | `⊢` | Apply patches to original code |
| 9 | `re-analyze` | spawner | `⊢⊢` | Fan-out: re-run 4 reviews on patched code |
| 10 | `final-verdict` | regular | `⊢` | Produce verdict + report |

**Runtime instances (happy path with ~4 action items):**
10 definitions → 18 instances (4 reviewers + 4 fix cells + 4 re-reviewers + 6 regular/spawner cells).

---

## Evaluation Questions

### 1. Step-by-step execution with intermediate states

**Given diff:** Adds `verify_token(token)` to `auth.py` at line 42. Contains SQL
injection (`f'SELECT * FROM users WHERE id = {payload["uid"]}'`), unguarded
`jwt.decode`, and no token expiration check.

---

**Step 1: parse-diff**

```
Input:  diff-text (literal unified diff)
Output: files-changed = ["auth.py"]
        hunks = [{file: "auth.py", line-start: 42,
                  additions: [6 lines of verify_token], deletions: []}]
        language = "python"
Oracles: 3/3 PASS (see Q3)
Status: crystallized — all outputs determined
```

**Step 2: analyze (spawner)**

```
Input:  parse-diff→hunks, parse-diff→language
Action: Spawn 4 §review-template instances
        review-types = [security, performance, correctness, style]
Oracle: ⊨ §reviewers has exactly 4 → PASS
```

**Step 2a: §review-template[security]**

```
Input:  hunks, language="python", review-type="security"
Output: findings = [
          {auth.py:44, "SQL injection via f-string interpolation of payload['uid']",
           "Use parameterized query"},
          {auth.py:43, "jwt.decode without exception handling",
           "Wrap in try/except jwt.InvalidTokenError"},
          {auth.py:43, "No token expiration validation",
           "Pass algorithms=['HS256'], require=['exp']"}
        ]
        severity = "critical"
        confidence = 95
Oracles: 3/3 PASS
```

**Step 2b: §review-template[performance]**

```
Output: findings = [{auth.py:44, "f-string SQL slightly slower than parameterized", ...}]
        severity = "info", confidence = 60
Oracles: 3/3 PASS
```

**Step 2c: §review-template[correctness]**

```
Output: findings = [
          {auth.py:43, "jwt.decode exceptions uncaught", ...},
          {auth.py:46, "None return ambiguous — jwt failure vs missing user", ...}
        ]
        severity = "warning", confidence = 80
Oracles: 3/3 PASS
```

**Step 2d: §review-template[style]**

```
Output: findings = [{auth.py:43, "SECRET_KEY as bare global", ...}]
        severity = "info", confidence = 70
Oracles: 3/3 PASS
```

**Step 3: merge-reviews**

```
Input:  4 §reviewers
Compute: has-critical ← TRUE (security reviewer severity = "critical")
Output: unified-findings = [
          1. SQL injection (critical, 95)  ← deduplicated from security+performance
          2. jwt.decode unhandled (critical→warning, 80-95)  ← deduplicated security+correctness
          3. No token expiration (warning, 80)
          4. None return ambiguity (warning, 80)
          5. SECRET_KEY as global (info, 70)
          6. f-string performance (info, 60)  ← subsumed by #1 but kept as info
        ]
        review-summary = "2 critical, 2 warning, 2 info. SQL injection must block merge."
Oracles: 3/3 PASS
```

**Step 4: prioritize**

```
Input:  unified-findings, has-critical=true
Compute: block-merge ← TRUE
Output: action-items = [
          {priority:1, "auth.py", "Fix SQL injection", parameterized query suggestion},
          {priority:2, "auth.py", "Add jwt.decode exception handling", try/except},
          {priority:3, "auth.py", "Add token expiration validation", require exp},
          {priority:4, "auth.py", "Disambiguate None return", specific exceptions}
        ]
        block-merge = true
Oracles: 3/3 PASS
```

**Step 5: generate-fixes (spawner)**

```
Input:  4 action-items, language="python"
Action: Spawn 4 §fix-template instances
```

**Steps 5a-5d: §fix-template instances**

Each generates a unified diff patch + explanation. Oracle checks: valid diff format,
explanation references original issue. On failure: retry max 2, then error-value(⊥).

**Step 6: apply-fixes**

```
Input:  4 fix-cells, diff-text
Compute: applied-count ← count(patches ≠ ⊥)  (likely 4)
         failed-count ← count(patches = ⊥)    (likely 0)
Output: patched-code = fixed verify_token with parameterized query,
        try/except, expiration check, specific exceptions
Oracles: ⊨ counts sum = 4 → PASS
         ⊨ syntactically valid Python → PASS
```

**Step 7: re-analyze (spawner)**

```
Input:  patched-code, language="python"
Action: Spawn 4 re-reviewer cells (security, performance, correctness, style)
        Each yields: resolved-findings[], new-findings[], regression (boolean)
Oracle: ⊨ §re-reviewers has exactly 4 → PASS
Note:   NO TEMPLATE DEFINED — see bug #1 below
```

**Step 8: final-verdict**

```
Input:  review-summary, has-critical=true, block-merge=true,
        applied-count=4, failed-count=0, 4 re-reviewers
Compute: can-merge ← ¬true ∨ (4>0 ∧ all(re-reviewers, ¬regression))
         = false ∨ (true ∧ true) = TRUE  (assuming no regressions)
Output: verdict = "APPROVE"
        report = "SQL injection found and fixed. 4/4 patches applied.
                  Re-analysis confirms no regressions."
        can-merge = true
Oracles: 4/4 PASS (verdict valid, conditions met, report mentions SQL injection)
```

---

### ⊥ Propagation Path (merge-reviews fails)

If merge-reviews exhausts its 1 retry → error-value(⊥):

```
merge-reviews → ⊥
  → prioritize: ⊥? skip → action-items=[], block-merge=true
    → generate-fixes: ⊥? skip → §fix-cells=[]
      → apply-fixes: ⊥? skip → patched-code=⊥, counts=0
        → re-analyze: ⊥? skip → §re-reviewers=[]
          → final-verdict: review-summary ⊥? skip →
              verdict="BLOCKED", report="Review system failed — manual review required"
```

The pipeline degrades gracefully to BLOCKED. Every cell in the chain has a ⊥? handler.

---

### 2. Crystallization analysis

**Crystallized computations (⊢= within cells):**

| Cell | Field | Formula | Always deterministic? |
|------|-------|---------|-----------------------|
| merge-reviews | `has-critical` | `any(reviewers, r.severity = "critical")` | Yes |
| prioritize | `block-merge` | `has-critical` | Yes (identity) |
| apply-fixes | `applied-count` | `count(fix-cells where patch ≠ ⊥)` | Yes |
| apply-fixes | `failed-count` | `count(fix-cells where patch = ⊥)` | Yes |
| final-verdict | `can-merge` | `¬block-merge ∨ (applied-count>0 ∧ all(¬regression))` | Yes |

**No entire cell is ⊢= crystallized.** All top-level cells have `∴` instructions
requiring LLM execution. The crystallized elements are individual computed fields.

**Candidates for full crystallization:**

- **parse-diff**: Parsing a standard unified diff is algorithmic. Language detection
  can be done by file extension. This cell's `∴` instruction ("Parse «diff-text» into
  structured components") describes a deterministic algorithm. Could be `⊢=` with a
  diff parser implementation.

- **apply-fixes**: Applying unified diff patches is a well-defined algorithm (`patch`
  command). The only LLM-needing part is "if a patch conflicts with a previous patch,
  skip it" — but even conflict detection is deterministic. Syntax validation of the
  result could use a parser. Strong crystallization candidate.

**Must stay soft:**

- All `§review-template` instances — core LLM analytical work
- `merge-reviews` — deduplication requires semantic judgment
- `prioritize` — converting findings to actionable items requires judgment
- All `§fix-template` instances — generating patches requires LLM
- All re-reviewer instances — same as original reviewers
- `final-verdict` — writing the narrative report requires LLM

---

### 3. Oracle trace (every ⊨ check)

**parse-diff (3 checks):**

| # | Oracle | Result | Reasoning |
|---|--------|--------|-----------|
| 1 | `⊨ files-changed is non-empty` | PASS | `["auth.py"]` — 1 file |
| 2 | `⊨ each hunk has: file, line-start, additions[], deletions[]` | PASS | Standard diff structure |
| 3 | `⊨ language ∈ {python, javascript, ...}` | PASS | `"python"` from `.py` extension |

**§review-template (3 checks × 4 instances = 12 checks):**

| # | Oracle | Result | Reasoning |
|---|--------|--------|-----------|
| 4-7 | `⊨ each finding has: file, line, description, suggestion` | PASS ×4 | Structural format check |
| 8-11 | `⊨ severity ∈ {"critical", "warning", "info"}` | PASS ×4 | Enum constraint |
| 12-15 | `⊨ confidence ∈ [0, 100]` | PASS ×4 | Range constraint |

Recovery clauses: `⊨? on failure: retry max 2`, `⊨? on exhaustion: partial-accept(best)`

**merge-reviews (3 checks):**

| # | Oracle | Result | Reasoning |
|---|--------|--------|-----------|
| 16 | `⊨ unified-findings preserves all critical findings` | PASS | SQL injection preserved |
| 17 | `⊨ sorted by severity then confidence` | PASS | Critical first, then by confidence |
| 18 | `⊨ review-summary mentions counts` | PASS | "2 critical, 2 warning, 2 info" |

Recovery: `⊨? on failure: retry max 1`, `⊨? on exhaustion: error-value(⊥)`

**prioritize (3 checks):**

| # | Oracle | Result | Reasoning |
|---|--------|--------|-----------|
| 19 | `⊨ if block-merge then action-items[0].priority = 1` | PASS | block-merge=true, first item priority=1 |
| 20 | `⊨ each action-item has: priority, file, description, code-suggestion` | PASS | Structural format |
| 21 | `⊨ action-items sorted by priority ascending` | PASS | 1, 2, 3, 4 |

**§fix-template (2 checks × N instances):**

| # | Oracle | Result | Reasoning |
|---|--------|--------|-----------|
| 22-25 | `⊨ patch is valid unified diff format` | PASS ×4 | Format check |
| 26-29 | `⊨ explanation references original issue description` | PASS ×4 | Content check |

Recovery: `⊨? on failure: retry max 2`, `⊨? on exhaustion: error-value(⊥)`

**apply-fixes (2 checks):**

| # | Oracle | Result | Reasoning |
|---|--------|--------|-----------|
| 30 | `⊨ applied-count + failed-count = length(fix-cells)` | PASS | Arithmetic identity (⊢= guaranteed) |
| 31 | `⊨ patched-code is syntactically valid` | PASS | Assuming valid patches |

**re-analyze (1 check on spawner):**

| # | Oracle | Result | Reasoning |
|---|--------|--------|-----------|
| 32 | `⊨ §re-reviewers has exactly 4 items` | PASS | 4 review types |

Note: Individual re-reviewer oracles are **undefined** — no template specifies them.
See bug #1.

**final-verdict (4 checks):**

| # | Oracle | Result | Reasoning |
|---|--------|--------|-----------|
| 33 | `⊨ verdict ∈ {"APPROVE", "REQUEST_CHANGES", "BLOCKED"}` | PASS | "APPROVE" ∈ set |
| 34 | `⊨ if has-critical ∧ applied-count = 0 then "BLOCKED"` | N/A | applied-count = 4, condition false |
| 35 | `⊨ if any(re-reviewers, regression) then "REQUEST_CHANGES"` | N/A | No regressions assumed |
| 36 | `⊨ report mentions SQL injection` | PASS | Critical finding, must appear in report |

**Total: 36 oracle checks** (happy path with 4 action items). Plus up to 8 retry-triggered
rechecks on §review-template, 1 on merge-reviews, and 8 on §fix-template = 53 max.

---

### 4. LLM call analysis

**Minimum calls (happy path, 4 action items):**

| Cell | LLM calls | Notes |
|------|-----------|-------|
| parse-diff | 1 | Could be 0 (deterministic parser candidate) |
| §review-template ×4 | 4 | 1 per reviewer |
| merge-reviews | 1 | Dedup + summarize |
| prioritize | 1 | Convert to action items |
| §fix-template ×4 | 4 | 1 per fix |
| apply-fixes | 1 | Could be 0 (deterministic patcher candidate) |
| re-reviewer ×4 | 4 | 1 per re-reviewer |
| final-verdict | 1 | Write verdict + report |
| **Total** | **17** | **Or 15 if parse-diff + apply-fixes crystallized** |

**Maximum calls (all retries exhausted):**
- §review-template: 4 × 3 (initial + 2 retries) = 12
- merge-reviews: 1 × 2 (initial + 1 retry) = 2
- §fix-template: 4 × 3 = 12
- Others: same = 7
- **Maximum: 33 calls**

**LLM-free elements:**
- All `⊢=` computed fields (has-critical, block-merge, counts, can-merge)
- Spawner controllers (analyze, generate-fixes, re-analyze) — they instantiate templates, no LLM
- parse-diff and apply-fixes — crystallization candidates (currently soft but algorithmically solvable)

---

### 5. Clarity rating: 7/10

**Strengths:**
- Clean linear pipeline with fan-out/fan-in pattern is natural for code review
- Consistent `⊢=` for deterministic computations — clearly separates judgment from formula
- Excellent ⊥ propagation: every cell has `⊥? skip with` handlers forming a complete
  degradation chain down to "BLOCKED"
- Template mechanism (`§`) effectively avoids code duplication for reviewer and fix cells
- The embedded diff with a real SQL injection makes the program concrete and testable
- Oracle recovery strategy is well-layered: retry → partial-accept or error-value(⊥)

**Weaknesses:**
- **Missing §re-reviewer template** — the program's most serious gap (see bugs below)
- `analyze` spawner has `max 6` but requires exactly 4 items — ambiguous whether the
  extra 2 are retry headroom or a bug
- Large program (18+ runtime cells) with no visual dependency aid
- Two separate fan-out/fan-in cycles (analyze→merge, re-analyze→final-verdict) make
  the control flow harder to trace than a simple pipeline

**Could you maintain this program?** Yes, with caveats. The pipeline structure is
self-documenting — each cell's role is clear from its name and position. The ⊥
propagation logic is the hardest part to reason about, but the explicit `⊥? skip with`
annotations make it tractable. Would want tooling for dependency graph visualization
at this scale.

---

### 6. Fragility analysis (remove any single cell)

| Removed Cell | Impact | Severity |
|-------------|--------|----------|
| `parse-diff` | **Fatal.** No input data. Entire pipeline has no hunks or language. | CRITICAL |
| `analyze` | **Fatal.** No reviewers spawned. merge-reviews has no input. | CRITICAL |
| `§review-template` | **Fatal.** analyze has no template to instantiate. | CRITICAL |
| `merge-reviews` | **Graceful degradation.** prioritize fires `⊥? skip`: action-items=[], block-merge=true. Cascades through generate-fixes, apply-fixes, re-analyze. final-verdict's `⊥? skip` on review-summary fires → verdict="BLOCKED", report="Review system failed". | SAFE |
| `prioritize` | **Graceful degradation.** generate-fixes fires `⊥? skip`: §fix-cells=[]. Same cascade → BLOCKED. | SAFE |
| `generate-fixes` | **Graceful degradation.** apply-fixes fires `⊥? skip` → BLOCKED. | SAFE |
| `§fix-template` | **Fatal.** generate-fixes has no template → can't spawn fix cells. | CRITICAL |
| `apply-fixes` | **Partial failure.** re-analyze fires `⊥? skip` on patched-code. But final-verdict depends on apply-fixes→applied-count and apply-fixes→failed-count with **no ⊥? handlers**. These values are undefined. | BUG |
| `re-analyze` | **Graceful degradation.** final-verdict fires `⊥? skip` on §re-reviewers → can-merge=false. | SAFE |
| `final-verdict` | **Output loss.** All analysis completes but no verdict emitted. Intermediate data survives but product is missing. | CRITICAL |

**Key finding:** The pipeline is most fragile at the edges (parse-diff, final-verdict)
and at template definitions (§review-template, §fix-template). The middle of the
pipeline (merge-reviews through re-analyze) degrades gracefully via ⊥ propagation.

**Bug: apply-fixes removal exposes undefined ⊥ handling in final-verdict.**
final-verdict depends on `apply-fixes→applied-count` and `apply-fixes→failed-count`
but has no `⊥? skip with` clause for these inputs. If apply-fixes fails, these values
are undefined.

---

### 7. Trust boundaries

**Layer 1: Fully trusted (no runtime verification)**

| Cell | Why trusted | Risk |
|------|-------------|------|
| `parse-diff` | Oracles only check structure (non-empty, fields present), not correctness. If parser misidentifies language or line numbers, all downstream analysis is wrong. | LOW — deterministic enough to crystallize |
| `merge-reviews` deduplication | Oracle checks sorting and completeness but not whether dedup was correct. Could incorrectly merge distinct findings, losing information. | MEDIUM — semantic judgment |

**Layer 2: Format-verified but semantically trusted**

| Cell | What's verified | What's trusted |
|------|----------------|----------------|
| `§review-template` | Finding structure (file, line, desc, suggestion), severity enum, confidence range | Whether the analysis is *correct* — did it find all real issues? Did it report false positives? |
| `§fix-template` | Patch format (valid unified diff), explanation references original | Whether the patch actually fixes the issue without introducing new bugs |
| `final-verdict` | Verdict enum, conditional constraints, SQL injection mention | Whether the narrative report accurately represents the data |

**Layer 3: Cross-verified (downstream cells verify upstream)**

| Upstream | Verified by | How |
|----------|------------|-----|
| §review-template findings | re-analyze | Re-reviewers check if original findings were real |
| §fix-template patches | re-analyze | Re-reviewers check if fixes resolved issues |
| §fix-template patches | apply-fixes | Syntax validation oracle on patched-code |

**The critical trust gap:** No oracle can verify "did the security reviewer find ALL
critical vulnerabilities?" The oracle checks format, not recall. If the security
reviewer misses the SQL injection, the entire pipeline produces a false APPROVE.
This is inherently unverifiable without a ground-truth oracle — the oracle would
need to be smarter than the reviewer.

**Trust topology:**
```
parse-diff (TRUSTED — could crystallize)
    ↓
§reviewers (FORMAT-VERIFIED, semantically trusted)
    ↓
merge-reviews (FORMAT-VERIFIED, dedup trusted)
    ↓
prioritize (FORMAT-VERIFIED)
    ↓
§fix-cells (FORMAT-VERIFIED → CROSS-VERIFIED by re-analyze)
    ↓
apply-fixes (FORMAT-VERIFIED — syntax check on result)
    ↓
re-analyze (FORMAT-VERIFIED — but re-reviewers could also miss things)
    ↓
final-verdict (FORMAT-VERIFIED + conditional constraints)
```

---

## Bugs and Issues Found

### Bug 1: Missing §re-reviewer template (CRITICAL)

`re-analyze` spawner yields `§re-reviewers[]` but no template is defined. The
re-reviewers need to yield `resolved-findings[], new-findings[], regression` — a
different schema than `§review-template` (which yields `findings[], severity,
confidence`). Either:
- A `§re-review-template` should be defined, or
- `§review-template` needs a variant mode, or
- The language has an implicit template mechanism not shown here

As written, `re-analyze` has no template to instantiate.

### Bug 2: apply-fixes → final-verdict ⊥ gap (MEDIUM)

`final-verdict` depends on `apply-fixes→applied-count` and
`apply-fixes→failed-count` but has no `⊥? skip with` clause for these inputs.
If `apply-fixes` itself fails (not just its fix-cells input), these values are
undefined. Fix: add `given apply-fixes→applied-count ⊥? skip with ...` to
final-verdict.

### Bug 3: analyze spawner max 6 vs exactly 4 (LOW)

`analyze` has `max 6` iterations but oracle requires `§reviewers has exactly 4`.
If `max` means "maximum iterations including retries of failed spawns," this is
correct (4 + 2 retry headroom). If `max` means "maximum items yielded," then
oracle #4 never fires until exactly 4 succeed, and the spawner stops at 6
attempts regardless. The semantics are ambiguous.

### Bug 4: re-analyze has no recovery clauses (LOW)

Unlike `§review-template` which has `⊨? on failure: retry` and `⊨? on
exhaustion: partial-accept`, the re-analyze spawner and its (undefined) template
have no recovery strategy. If a re-reviewer fails, behavior is undefined.

### Observation: Tautological oracle in apply-fixes

`⊨ applied-count + failed-count = length(fix-cells)` is guaranteed by the ⊢=
definitions of applied-count and failed-count. This oracle can never fail — it's
an assertion, not a constraint. Cell could benefit from distinguishing `⊨` (can
fail) from `⊨!` (invariant assertion).

---

## Summary

| Metric | Value |
|--------|-------|
| Cell definitions | 10 |
| Runtime instances (happy path, 4 actions) | 18 |
| Oracle checks | 36 (happy path) |
| LLM calls (minimum) | 17 (or 15 with crystallization) |
| LLM calls (maximum) | 33 |
| Bugs found | 4 |
| Clarity rating | 7/10 |
| ⊥ degradation | Graceful — all paths lead to BLOCKED |
| Crystallization candidates | 2 cells (parse-diff, apply-fixes) |
| Trust gap | Reviewer recall unverifiable |
