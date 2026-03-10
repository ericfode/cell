# Round 14 Results: Evolution Loop Stress Tests — Synthesis

**Dispatcher**: morpheus (crew) | **Date**: 2026-03-10

## Dispatch Summary

Fractal dispatch test: crew member (morpheus) dispatched 3 beads to polecats
using `gt sling`. All three completed autonomously.

| Variant | Polecat | Bead | Result Bead | Status |
|---------|---------|------|-------------|--------|
| distillation-loop | dust | ce-nj5k | ce-b5sd | Crystallized frame 1 |
| syntax-darwinism | ghoul | ce-vkiy | (inline DESIGN) | 3 survivors, 3 culled |
| oracle-adversary | guzzle | ce-r1wk | ce-msiw | Attacker wins frame 1 |

Prior oracle-adversary runs (Mayor-dispatched): ce-jg6f (opus/radrat), ce-f5d3
(sonnet/nitro), ce-luk5 (dust). All from ce-zeoi.

---

## V1: Distillation Loop — Crystallization via ⊢∘

**Result**: Template crystallized on frame 1 (match_score = 0.92).

### Execution Trace

1. **seed**: prompt = "Explain quantum entanglement..." / temperature = 1.0 / generation = 0
2. **generate**: Produced 2-sentence response using magic dice analogy
3. **distill**: Extracted template with 9 variables (concrete_objects, connection_description, etc.)
4. **test-distilled**: Filled template with "magic coins" / "atoms" / "galaxy" → match_score 0.92
5. **decide**: is_crystallized = (0.92 ≥ 0.9) → **true**

### Analysis

**What worked well**:
- ⊢∘ loop structure cleanly separates iteration steps via `through`
- `partial-accept(best)` exhaustion policy on distill/test-distilled prevents hard failure
- The `§` prefixed yields (§response, §template, §variables) correctly signal "this is LLM output"
- Frame-by-frame execution was unambiguous — dust executed exactly one iteration

**What's interesting**:
- Crystallization happened on frame 1 — the template was good enough immediately
- This means for this prompt, the loop's `max 20` is way over-provisioned
- The 0.92 score means the template *almost perfectly* captures the original
- The template has genuine abstraction: replacing "dice" with "coins" preserves meaning

**Spec questions raised**:
- The `⊢= decide` cell uses `§match-score ≥ 0.9` — this is a pure comparison on LLM output. Should this be ⊢= (deterministic) or does the § make it soft?
- `⊢= test-distilled` is declared deterministic but contains `∴` (natural language instruction). The `⊢=` declaration seems wrong — this is a soft cell.

---

## V2: Syntax Darwinism — Tournament Elimination

**Result**: 3 survivors after frame 1. Dialogue and hybrid lead.

### Scores (cold-read eval-one confidence)

| Candidate | Score | Status |
|-----------|-------|--------|
| dialogue | 9 | SURVIVED |
| hybrid | 9 | SURVIVED |
| literate | 8 | SURVIVED |
| blocks | 8 | ELIMINATED |
| spreadsheet | 7 | ELIMINATED |
| letter | 7 | ELIMINATED |

### Analysis

**What worked well**:
- The tournament structure is elegant — ⊢∘ naturally models "repeat until one remains"
- The `cull` step correctly eliminated bottom half (3 of 6)
- Confidence scores are intuitive and differentiate candidates

**What's interesting**:
- **dialogue and hybrid tied at 9** — both use tag-based structure ([system]/[user])
- **literate survived at 8** — markdown-based, familiar to LLMs
- **blocks eliminated despite scoring 8** — tie-breaking went against it (bottom half = 3)
- **spreadsheet and letter scored lowest** — formula syntax and letter format confused cold readers

**Convergence check** (vs earlier Mayor-dispatched sonnet run): No prior syntax-darwinism
result bead found for comparison. This is the first execution.

**Spec implications**:
- Tag-based syntaxes ([system]/[user]) score highest for cold-read executability
- This is evidence FOR the dialogue/hybrid direction and AGAINST the current ⊢/⊨ symbol-heavy syntax
- However: the eval-one test used a trivial program. Complex programs may reward structure differently.

---

## V3: Oracle Adversary — Red-Team via ⊢∘

**Result**: Attacker wins frame 1. Challenge hardened with meaningfulness constraint.

### Convergence Across Runs

| Run | Model | Polecat | Attack Vector | Attacker Wins? |
|-----|-------|---------|---------------|----------------|
| ce-msiw | default | guzzle | Repeat "rust" 17 times | YES |
| ce-jg6f | opus | radrat | Repeat "rust" 17 times | YES |
| ce-f5d3 | sonnet | nitro | (instructions only — no JSON result) | — |
| ce-luk5 | default | dust | (instructions only — no JSON result) | — |

**Both completed runs found the IDENTICAL loophole**: repeating the word "rust" in
5-7-5 pattern technically satisfies "haiku about rust" while conveying nothing.

### Hardened Challenges (both converged)

- **guzzle**: "...must use at least 5 distinct words and convey a specific technical concept"
- **radrat (opus)**: "...that conveys at least one specific technical concept or feature of Rust"

Both independently added a "meaningfulness" constraint — strong convergence signal.

### Analysis

**What worked well**:
- The attack/judge/evolve pattern is genuinely useful for oracle hardening
- Multiple polecats finding the same loophole validates the pattern's reliability
- The evolved challenges are strictly better than the original

**What's interesting**:
- The first loophole found is always the most obvious (degenerate repetition)
- Frame 2 would test whether subtler loopholes exist after the obvious one is closed
- This maps directly to Cell's oracle trust model: ⊨ assertions need adversarial testing

**Spec implications**:
- Oracle assertions (⊨) should have a standard "adversarial audit" step
- The evolve-challenge pattern could become a Cell stdlib primitive for oracle hardening
- `⊨? on failure: retry` is insufficient — you need `⊨? on attack: harden`

---

## Cross-Variant Findings

### 1. ⊢∘ Works as Designed
All three variants used ⊢∘ (evolution loop) and all three executed correctly.
Polecats understood `through`, `until`, `max`, and frame-by-frame semantics
without confusion. The loop construct is the most battle-tested Cell feature.

### 2. Frame Execution is Natural
Polecats executed exactly one frame when asked. No over-running, no confusion
about loop boundaries. The `through` clause + explicit frame instructions make
loop body execution unambiguous.

### 3. ⊢= Confusion Persists
`test-distilled` in distillation-loop is declared ⊢= (deterministic) but contains
`∴` (semantic instruction). This is a spec inconsistency that confuses the
crystallization semantics. Rule: ⊢= means NO LLM calls, period.

### 4. Tag-Based Syntax Leads Cold-Read Scores
Syntax darwinism shows dialogue/hybrid (tag-based) beating the current symbol-heavy
syntax family. This is a data point, not a conclusion — needs more programs tested.

### 5. Oracle Adversary Converges
Multiple independent polecats find identical loopholes and produce nearly identical
hardenings. This means adversarial oracle testing is deterministic enough to be
formalized as a Cell pattern.

## Dispatch Mechanics Assessment

The fractal dispatch test succeeded. Key observations:

| Aspect | Result |
|--------|--------|
| gt sling from crew to polecats | WORKS — 3/3 dispatched successfully |
| Auto-convoy creation | WORKS — each sling created a convoy |
| Polecat autonomy | WORKS — all 3 completed without intervention |
| Result collection | MIXED — 2/3 created result beads, 1 inlined in DESIGN |
| Bead lifecycle | PARTIAL — polecats didn't always close source beads |
| Cross-model convergence | STRONG — oracle-adversary produced identical findings |

### Issues Found

1. **Chrome had stale session** — first sling failed, had to target a different polecat
2. **Source beads not auto-closed** — ce-nj5k and ce-r1wk stayed in_progress after polecat completion. Manual close needed.
3. **Inconsistent result format** — ghoul inlined results in bead DESIGN field; dust/guzzle created separate result beads
4. **Missing JSON in some oracle-adversary runs** — ce-f5d3 and ce-luk5 had instructions but no result data

## Next Steps

1. **Frame 2 dispatches**: Run frame 2 for oracle-adversary (test subtler loopholes) and syntax-darwinism (tournament continues with 3 candidates)
2. **Spec fix**: Clarify that ⊢= means no ∴ instructions allowed
3. **Result format standard**: Require all polecats to create result beads with JSON
4. **Stale session handling**: Add pre-flight session check to gt sling
