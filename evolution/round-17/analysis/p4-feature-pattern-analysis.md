# R17 Feature & Pattern Analysis (p4)

Comprehensive analysis of all 30 R17 Cell programs for v0.2 feature usage,
design patterns, and quality assessment.

---

## 1. Feature Usage Matrix

### Core Features

| # | Program | ⊢ | ⊢= | ⊢⊢ | ⊢∘ | ∴ | ⊨ | § | ⊥ | «» | Cells |
|---|---------|---|----|----|----|----|---|---|---|------|-------|
| 01 | research-plan-evolver | Y | N | Y | Y | Y | Y | Y | Y | Y | 10 |
| 02 | self-improving-prompt | Y | Y | N | Y | Y | Y | Y | N | Y | 6 |
| 03 | progressive-crystallization | Y | Y | N | Y | Y | Y | Y | Y | Y | 8 |
| 04 | self-building-test-suite | Y | N | Y | Y | Y | Y | Y | Y | Y | 10 |
| 05 | meta-cell-designer | Y | Y | Y | Y | Y | Y | Y | Y | Y | 10 |
| 06 | spec-hardener | Y | Y | N | Y | Y | Y | Y | Y | Y | 5 |
| 07 | recursive-debate | Y | Y | N | Y | Y | Y | Y | Y | Y | 8 |
| 08 | red-team-harden | Y | N | Y | Y | Y | Y | Y | Y | Y | 8 |
| 09 | negotiation-consensus | Y | Y | N | Y | Y | Y | N | Y | Y | 11 |
| 10 | socratic-teacher | Y | Y | N | Y | Y | Y | Y | Y | Y | 8 |
| 11 | fractal-task-planner | Y | N | Y | N | Y | Y | Y | Y | Y | 14 |
| 12 | recursive-requirement-extractor | Y | N | Y | Y | Y | Y | N | Y | Y | 9 |
| 13 | progressive-summarization | Y | Y | Y | N | Y | Y | N | Y | Y | 7 |
| 14 | dependency-graph-builder | Y | N | Y | Y | Y | Y | Y | Y | Y | 12 |
| 15 | recursive-explanation | Y | N | Y | Y | Y | Y | Y | Y | Y | 9 |
| 16 | evolution-simulator | Y | Y | N | Y | Y | Y | N | Y | Y | 8 |
| 17 | collaborative-world-builder | Y | Y | N | Y | Y | Y | Y | Y | Y | 8 |
| 18 | recursive-story-builder | Y | N | Y | Y | Y | Y | Y | Y | Y | 11 |
| 19 | code-generator-proof | Y | Y | N | Y | Y | Y | Y | Y | Y | 14 |
| 20 | language-designer | Y | Y | Y | Y | Y | Y | Y | N | Y | 6 |
| 21 | self-correcting-translator | Y | Y | N | Y | Y | Y | N | N | Y | 6 |
| 22 | fact-checked-article | Y | Y | Y | Y | Y | Y | Y | Y | Y | 10 |
| 23 | multi-oracle-gauntlet | Y | Y | N | Y | Y | Y | N | N | Y | 10 |
| 24 | proof-carrying-code | Y | Y | N | Y | Y | Y | Y | Y | Y | 11 |
| 25 | oracle-chain-builder | Y | Y | Y | Y | Y | Y | Y | Y | Y | 12 |
| 26 | cell-zero-exerciser | Y | Y | Y | Y | Y | Y | Y | Y | Y | 16 |
| 27 | self-optimizing-cell | Y | Y | N | Y | Y | Y | Y | Y | Y | 10 |
| 28 | program-algebra-prover | Y | Y | N | N | Y | Y | Y | N | Y | 15 |
| 29 | bootstrapper | Y | Y | Y | Y | Y | Y | Y | Y | Y | 12 |
| 30 | cell-spec-evolver | Y | Y | N | Y | Y | Y | Y | Y | Y | 12 |

### v0.2 Features

| # | Program | file-scope ⊨? | wildcard deps | ⊢⊢ accum/repl | guard clauses | given? | ⊢∘ aspirational | ⊢= expr lang |
|---|---------|---------------|---------------|----------------|---------------|--------|-----------------|--------------|
| 01 | research-plan-evolver | Y | Y (experiment-*) | Y (replace) | N | N | Y | N |
| 02 | self-improving-prompt | Y | N | N | N | N | Y | N |
| 03 | progressive-crystallization | Y | N | N | Y (pass-all) | Y (feedback) | Y | Y |
| 04 | self-building-test-suite | Y | Y (edge-test-*) | Y (accumulate) | Y (coverage-score) | Y (ambiguities) | Y | Y |
| 05 | meta-cell-designer | Y | N | Y (accumulate) | Y (awkward-spots) | Y (critique) | Y | Y |
| 06 | spec-hardener | Y | N | N | N | N | Y | N |
| 07 | recursive-debate | Y | N | N | Y (weakest-side) | N | Y | N |
| 08 | red-team-harden | Y | Y (regression-test-*) | Y (accumulate) | Y (vulnerability) | Y (regression) | Y | N |
| 09 | negotiation-consensus | Y | N | N | N | N | Y | N |
| 10 | socratic-teacher | Y | Y (remedial-*) | Y (accumulate) | Y (understanding) | Y (misconceptions) | Y | N |
| 11 | fractal-task-planner | Y | Y (task-decomposer-*, step-decomposer-*, action-decomposer-*) | Y (accumulate) | Y (valid, feasible) | N | N | N |
| 12 | recursive-requirement-extractor | Y | Y (decomposer-*) | Y (accumulate) | Y (remaining-vague) | N | Y | N |
| 13 | progressive-summarization | Y | N | N | Y (acceptable) | Y (next-summary) | N | Y |
| 14 | dependency-graph-builder | Y | Y (analyzer-*, sub-analyzer-*) | Y (accumulate) | Y (is-acyclic) | Y (ordering/cycle) | Y | N |
| 15 | recursive-explanation | Y | Y (explainer-*) | Y (accumulate) | Y (remaining-hard) | N | Y | N |
| 16 | evolution-simulator | Y | N | Y (replace) | Y (converged, mean-fitness) | Y (mean-fitness) | Y | Y |
| 17 | collaborative-world-builder | Y | N | N | N | Y (backstory, customs, layout) | Y | N |
| 18 | recursive-story-builder | Y | Y (scene-*, beat-*) | Y (accumulate) | Y (consistency-score) | N | Y | N |
| 19 | code-generator-proof | Y | N | N | Y (fail-count, verdict) | N | Y | Y |
| 20 | language-designer | Y | Y (example-*) | Y (accumulate) | Y (is-clean) | N | Y | N |
| 21 | self-correcting-translator | Y | N | N | Y (acceptable) | N | Y | N |
| 22 | fact-checked-article | Y | Y (fact-check-*) | Y (replace) | Y (all-pass) | Y (uncertain-count) | Y | Y |
| 23 | multi-oracle-gauntlet | Y | N | N | N | N | Y | Y |
| 24 | proof-carrying-code | Y | N | N | Y (verdict) | Y (proof-patch) | Y | Y |
| 25 | oracle-chain-builder | Y | Y (refiner-*, check-*) | Y (accum + repl) | N | N | Y | Y |
| 26 | cell-zero-exerciser | Y | Y (spawn-claims-*) | Y (accumulate) | Y (all-pass) | Y (prior-failures) | Y | Y |
| 27 | self-optimizing-cell | Y | N | N | N | N | Y | Y |
| 28 | program-algebra-prover | Y | N | N | N | N | N | Y |
| 29 | bootstrapper | Y | Y (specialist-*, gap-filler-*) | Y (accumulate) | Y (is-complete) | Y (gap-filler) | Y | N |
| 30 | cell-spec-evolver | Y | N | N | Y (is-clean) | Y (remaining) | Y | Y |

---

## 2. v0.2 Feature Adoption Rates

| Feature | Count | Rate | Notes |
|---------|-------|------|-------|
| **file-scope ⊨?** | 30/30 | **100%** | Universal adoption. Every program has it. |
| **⊢∘ aspirational oracles** | 27/30 | **90%** | Missing in 11 (no ⊢∘), 13 (no ⊢∘), 28 (no ⊢∘). |
| **guard clauses** (given ... where) | 22/30 | **73%** | Primary use: conditional dispatch (pass/fail branching). |
| **⊢⊢ accumulate/replace** | 19/30 | **63%** | 15 accumulate, 3 replace, 1 both. 11 programs have no spawner. |
| **given?** (optional deps) | 16/30 | **53%** | Most common: tolerating ⊥ from guard-skipped cells. |
| **wildcard deps** (cell-*→field) | 16/30 | **53%** | Always paired with ⊢⊢ spawners. |
| **⊢= expression language** | 15/30 | **50%** | Validated against v0.2 primitives. Includes crystallized verifiers. |
| **⊢∘ evolution loop** | 27/30 | **90%** | Only 11, 13, 28 lack ⊢∘. |

### Adoption tiers

- **Tier 1 (universal)**: file-scope ⊨? (100%)
- **Tier 2 (near-universal)**: ⊢∘ loops (90%), aspirational oracles (90%)
- **Tier 3 (majority)**: guard clauses (73%), ⊢⊢ modes (63%)
- **Tier 4 (half)**: given? (53%), wildcard deps (53%), ⊢= expr lang (50%)

### Feature co-occurrence patterns

- **guard clauses + given?**: 12/30 (40%) -- guard skips cell, downstream uses given? for ⊥
- **⊢⊢ + wildcard deps**: 16/16 (100%) -- every spawner program uses wildcards to collect
- **⊢⊢ replace + ⊢∘**: 3/3 (100%) -- replace mode always inside evolution loops
- **⊢= expr lang + ▸ crystallized**: 10/15 (67%) -- most validated ⊢= cells are marked crystallized

---

## 3. Design Pattern Catalog

### 3.1 Attacker-Defender-Judge (ADJ)
**Programs**: 06, 07, 08

Three-role adversarial loop. Attacker finds flaws, defender fixes, judge validates.
⊢∘ loops until attacker finds nothing or judge rules all fixed.

**Canonical example**: 06-spec-hardener
- `attack` finds ambiguities in oracle spec
- `defend` rewrites spec to close them
- `judge-fix` rules if fixes work
- `⊢∘ harden` until `attack→severity = "none"`

**Variant in 08**: Attacker (red-team) finds vulnerabilities, defender (harden)
patches code, verification is split from judgment, regression tests accumulate.

### 3.2 Spawner-Then-Collect (STC)
**Programs**: 01, 04, 05, 08, 10, 11, 12, 14, 15, 18, 20, 22, 25, 26, 29

Most common pattern. ⊢⊢ spawns N cells from a template, wildcard deps
collect their outputs into a single downstream cell.

**Canonical example**: 04-self-building-test-suite
- `⊢⊢ spawn-edge-tests` creates per-edge-case test cells
- `assess-coverage` collects via `edge-test-*→result` + `edge-test-*→verdict`

**Sub-variants**:
- **Accumulate** (04, 08, 10, 11, 14, 15, 18, 25, 29): spawned cells persist across ⊢∘ iterations
- **Replace** (01, 22, 25): spawned cells discarded each iteration, fresh set created
- **Multi-level** (11, 18): spawners spawn spawners (fractal decomposition)

### 3.3 Oracle-Gated Convergence (OGC)
**Programs**: 01, 02, 03, 04, 05, 07, 08, 09, 10, 12, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23, 24, 25, 26, 27, 29, 30

Nearly universal. ⊢∘ loops with an `until` condition that checks a quality score
or boolean from a judgment/evaluation cell.

**Canonical example**: 23-multi-oracle-gauntlet
- 5 independent oracle dimensions (structural, semantic, factual, stylistic, logical)
- Crystallized aggregator computes `all-pass`
- ⊢∘ loops until `gauntlet→all-pass = true`

### 3.4 Staged Pipeline (SP)
**Programs**: 03, 11, 13, 19, 24, 28

Linear multi-stage processing where output of stage N feeds stage N+1.
Distinguished from STC by its sequential rather than parallel nature.

**Canonical example**: 03-progressive-crystallization
- `solve-soft` (LLM) -> `extract-pattern` -> `crystallize` (⊢=) -> `verify-crystal` -> `refine-crystal`
- Substrate transfer: ∴ body progressively replaced with ⊢= expression

### 3.5 Co-Evolution
**Programs**: 07, 09, 17

Multiple ⊢∘ targets evolve simultaneously, sharing feedback cells.
Circular dependencies resolved via given? and ⊥ on iteration 0.

**Canonical example**: 17-collaborative-world-builder
- 3 creator cells (geography, history, culture) with given? cross-references
- `check-consistency` oracle detects contradictions
- `⊢∘ co-evolve(geography, history, culture)` evolves all three

**Variant in 09**: 4 perspective cells share a single mediator; 4 separate
⊢∘ declarations with shared `through` and `until`.

### 3.6 Proof-Carrying Computation (PCC)
**Programs**: 19, 24, 28

LLM generates solution (NP), crystallized verifier checks (P). Two-cell split:
structural checks (⊢=) + semantic gap-finding (∴). Guard-dispatched certificates.

**Canonical example**: 24-proof-carrying-code
- `generate-code` produces implementation
- `generate-proof` produces correctness argument
- `verify-proof-structure` (⊢= crystallized) checks structural properties
- `verify-proof-gaps` (∴ soft) finds semantic gaps
- `fill-gaps` patches the proof
- `⊢∘ evolve` loops until proof complete

### 3.7 Guard-Gated Dispatch (GGD)
**Programs**: 03, 04, 07, 08, 11, 13, 14, 16, 19, 21, 22, 24, 26, 29, 30

Uses `given x where condition` to route execution to exactly one of N
mutually exclusive handler cells. Skipped cells yield ⊥.

**Canonical example**: 19-code-generator-proof
- `analyze-failures` has `where fail-count > 0`
- `skip-analysis` has `where fail-count = 0`
- Exactly one fires; other yields ⊥

**Notable in 30**: The awkward-program fragment IS the motivating example
for guard clauses -- the program discovers its own v0.2 solution.

### 3.8 Self-Referential / Metacircular
**Programs**: 02, 05, 26, 27, 30

Program reasons about its own structure or about other Cell programs
using § quotation as data.

**Canonical example**: 26-cell-zero-exerciser
- Feeds `§p1-parallel-confluence` into cell-zero's evaluation loop
- Each cell traces one phase: read-graph, check-inputs, pick-cell,
  evaluate, spawn-claims, check-claims, decide
- Cell evaluating Cell -- metacircular execution trace

### 3.9 Genetic Algorithm / Tournament
**Programs**: 16

Population-based evolution with selection, crossover, mutation, and
fitness evaluation. ⊢∘ replace mode simulates generational evolution.

**Canonical example**: 16-evolution-simulator
- Population of 6 logo concepts
- `evaluate-fitness` scores each
- `select-and-crossover` keeps top 3, creates 3 offspring
- `⊢∘ evolve replace` until fitness converges or stagnates

### 3.10 Zero-Start Bootstrap
**Programs**: 29

Starts with zero domain cells. Meta-cell analyzes the task, decides what
capabilities are needed, spawns specialist cells, evaluates coverage,
spawns gap-fillers for what's missing. Two-phase spawning.

**Canonical example**: 29-bootstrapper
- `analyze-needs` decides what cells to create from nothing
- `spawn-specialists` creates first wave
- `evaluate-completeness` finds gaps
- `spawn-gap-fillers` creates second wave (guard-gated on is-complete)
- `⊢∘ bootstrap` iterates until quality-score >= 7

---

## 4. Quality Tier List

### EXEMPLARY (10 programs)

Programs that demonstrate deep understanding of Cell's fusion model,
use v0.2 features naturally, have well-structured dataflow, meaningful
oracles, and interesting domain applications.

| # | Program | Justification |
|---|---------|---------------|
| 04 | self-building-test-suite | Best STC exemplar. Recursive edge-case discovery, accumulate mode, guard-gated final-report/needs-more-work dispatch. 10 cells with clean dataflow. Tests discover their own gaps. |
| 08 | red-team-harden | Best ADJ exemplar. Adversarial loop with regression test accumulation -- the accumulate pattern enforces non-regression across iterations. Guard clauses on 4 cells. given? for optional regression context. |
| 19 | code-generator-proof | Best PCC exemplar. Honest split of verify-proof into structural (⊢=) and semantic (∴) cells. Guard-gated 3-tier certificate dispatch. 14 cells with clean proof-carrying pipeline. |
| 22 | fact-checked-article | Best replace-mode ⊢⊢ exemplar. Per-claim fact-checkers replaced each iteration with fresh verdicts. Crystallized aggregator. Guard-gated final/incomplete dispatch. |
| 24 | proof-carrying-code | Second PCC exemplar, equally strong. Two-cell verify split, guard-gated fill-gaps, given? for proof-patch tolerance. Clean convergence logic. |
| 25 | oracle-chain-builder | Uses BOTH accumulate and replace in different spawners. Recursive oracle decomposition from vague to deterministic. Crystallized check-template and verify-coverage cells. |
| 26 | cell-zero-exerciser | Most conceptually ambitious. Metacircular: Cell program tracing cell-zero's evaluation of another Cell program. 7 observation ⊢= cells. 16 total cells. Guard-gated decide-freeze/decide-rewrite. |
| 29 | bootstrapper | Unique zero-start pattern. Two-phase spawning (specialists then gap-fillers). Guard-gated second spawner. given? for ⊥ tolerance. Extensive observations. |
| 30 | cell-spec-evolver | Self-referential: discovers guard clauses by demonstrating their absence. Embeds v0.2 solution inside its own awkward-program. Guard-gated compile/iterate dispatch. |
| 17 | collaborative-world-builder | Best co-evolution exemplar. 3-way given? cross-references. Consistency oracle. § quotation for resolve-contradictions. Clean ⊥ handling on iteration 0. |

### ADEQUATE (14 programs)

Solid programs that use v0.2 features correctly but are less novel or
have simpler patterns. Good but not exceptional.

| # | Program | Justification |
|---|---------|---------------|
| 01 | research-plan-evolver | Good ⊢⊢ replace + ⊢∘ combination. Clean wildcard deps. But pattern (evolve hypotheses) is straightforward. |
| 03 | progressive-crystallization | Good substrate transfer demo (∴ -> ⊢=). given? for refine feedback. But crystallization is simulated, not real. |
| 05 | meta-cell-designer | Programs-writing-programs is ambitious, but the design-critique-redesign pattern is standard ADJ. |
| 07 | recursive-debate | Clean dual ⊢∘ with guard-gated refine-for/refine-against. But the debate pattern is well-trodden. |
| 09 | negotiation-consensus | 4-way ⊢∘ co-evolution is interesting. But the mediate-revise pattern is repetitive across 4 perspectives. 11 cells is high for the conceptual density. |
| 10 | socratic-teacher | Good adaptive teaching loop. guard + given? + accumulate all present. But the evaluate-then-redesign loop is standard. |
| 11 | fractal-task-planner | Most cells (14) among adequate tier. Multi-level spawners impressive. But NO ⊢∘ loop -- relies purely on spawner recursion and per-level ⊨? retry. |
| 12 | recursive-requirement-extractor | Solid recursive decomposition. But pattern (vague->concrete) is similar to 15, 25. |
| 14 | dependency-graph-builder | Two-level graph analysis with ⊢∘ refinement. Guard-gated handle-acyclic/handle-cycle. Good. |
| 15 | recursive-explanation | Clean comprehension-oracle recursion. Accumulate mode for monotonic tree growth. Standard. |
| 16 | evolution-simulator | Genetic algorithm in Cell is creative. Guard-gated convergence/stagnation reports. But simple population model. |
| 18 | recursive-story-builder | Multi-level spawners (acts -> scenes -> beats). ⊢∘ revision loop. Good but structurally similar to 11. |
| 20 | language-designer | DSL critique loop with spawned examples. Interesting domain. But only 6 cells -- minimal. |
| 27 | self-optimizing-cell | Self-referential optimization. Honest compare-semantics (moved from false ⊢= to ∴). Clean verdict crystallization. |

### PROBLEMATIC (6 programs)

Programs with issues: missing v0.2 features, minimal feature usage,
structural simplicity that underuses the language, or conceptual gaps.

| # | Program | Issues |
|---|---------|--------|
| 02 | self-improving-prompt | Only 6 cells. No spawners, no wildcard deps, no guard clauses, no given?. The ⊢∘ loop is clean but the program is minimal. ⊨? at bottom of file (comment says file-scope but placement is end-of-file, not top). |
| 06 | spec-hardener | Only 5 cells. Clean ADJ pattern but minimal. No spawners, no wildcard deps, no guard clauses, no given?, no ⊢= expression language. |
| 13 | progressive-summarization | No ⊢∘ loop. The ⊢⊢ recurse-compression is supposed to create recursive chains, but the mechanism is vague -- spawning {summarize, check-fidelity, compress-further} chains is not well-specified as a ⊢⊢ body. |
| 21 | self-correcting-translator | Only 6 cells. No spawners, no wildcard deps, no given?. Guard clause exists but the program is minimal. Clean but thin. |
| 23 | multi-oracle-gauntlet | No spawners, no wildcard deps, no given?, no guard clauses. The 5-oracle parallel is interesting but structurally simple. Rewrite cell handles both pass/fail in-body rather than via guard dispatch. |
| 28 | program-algebra-prover | No ⊢∘ loop at all. 15 cells but mostly crystallized computation cells. No spawners, no wildcard deps, no given?, no guard clauses. The confluence proof is interesting but the program is static -- no evolution, no adaptation. |

---

## 5. Top 5 Most Interesting/Novel Programs

### 1. **26-cell-zero-exerciser** -- Metacircular evaluation trace

The most conceptually ambitious program in R17. It feeds another Cell program
(p1-parallel-confluence) into cell-zero's evaluation loop and traces each phase:
read-graph, check-inputs, pick-cell, evaluate, spawn-claims, check-claims, decide.
The program IS a Cell document tracing Cell evaluating Cell. This is the metacircular
evaluator made concrete.

Key innovations:
- 7 observation ⊢= cells documenting the evaluation semantics
- Guard-gated decide-freeze vs decide-rewrite (clean binary dispatch)
- ⊢∘ wraps the full eval-one cycle
- Demonstrates the fusion property: hard cells (pick-cell, decide-freeze) run
  classically while soft cells (evaluate, check-claims) require LLM

**Why it matters**: This is the closest any R17 program gets to implementing cell-zero
itself. It validates that cell-zero's evaluation loop can be expressed as a Cell program.

### 2. **29-bootstrapper** -- Zero-start self-assembly

Starts with literally zero domain cells. A meta-cell (analyze-needs) inspects
a natural language task and decides what specialist cells to create. Two-phase
spawning: broad coverage first (specialists), then targeted depth (gap-fillers).
⊢∘ iterates until quality converges.

Key innovations:
- Zero-start bootstrap: the program creates its own workforce
- Two-phase spawning pattern (broad then deep)
- Guard-gated second spawner (no gap-fillers when complete)
- Template polymorphism: same shape, different roles
- 8 extensive observation notes in a ⊢= cell

**Why it matters**: Demonstrates Cell's self-bootstrapping property at the program
level. The system reasons about its own capability gaps and fills them.

### 3. **30-cell-spec-evolver** -- Self-referential spec discovery

The program that discovers its own v0.2 features. Embeds an awkward v0.1 program
(content moderation with conditional dispatch), identifies why it's awkward (no
guard clauses), proposes guard clauses as a spec change, rewrites the program
using them, and evaluates the improvement. The R17 version already contains the
v0.2 solution inside its awkward-program fragment.

Key innovations:
- Self-referential irony: discovers the feature it already uses
- Embeds a complete Cell program as ⊢= data (awkward-program→code)
- Guard-gated compile-changes vs iterate-further dispatch
- 5 observation ⊢= cells documenting the meta-level insights

**Why it matters**: This is the "origin story" program for v0.2 guard clauses.
It validates the spec change by demonstrating the problem and the solution in one file.

### 4. **25-oracle-chain-builder** -- Recursive oracle decomposition

Takes a vague oracle ("the API design is good") and recursively decomposes it into
specific, deterministically-checkable leaf oracles. Uses BOTH accumulate (refiners
persist) and replace (crystallizers rebuilt) spawner modes in the same program.

Key innovations:
- Only R17 program using both accumulate and replace ⊢⊢ modes
- Recursive soft->structural->deterministic classification
- Crystallized check-template and verify-coverage cells
- Clean separation of refinement loop (oracle granularity) from crystallization (leaf checks)

**Why it matters**: Directly exercises the oracle system's design -- proving that
vague semantic assertions can be decomposed into concrete checkable properties.
This is the oracle hierarchy from the spec made executable.

### 5. **08-red-team-harden** -- Adversarial hardening with regression accumulation

The most practically useful ADJ variant. Red-teams code for vulnerabilities,
patches each one, and crucially ACCUMULATES regression tests that prevent
re-introduction of fixed vulnerabilities. Each iteration adds one permanent
regression test to the growing test suite.

Key innovations:
- Regression test accumulation across ⊢∘ iterations (accumulate mode)
- Guard clauses on 4 different cells (harden, verify-patch, spawn-regression-test, security-report)
- given? for optional regression context in red-team
- Red-team must find NEW vulnerabilities (regression tests block repeats)
- Clean termination: red-team yields vulnerability="none" when exhausted

**Why it matters**: Best demonstration of how ⊢⊢ accumulate + ⊢∘ evolution
interact. The accumulated artifacts (regression tests) become constraints on
future iterations, creating a ratchet that prevents quality regression.

---

## 6. Summary Statistics

### Totals

- **Total cells across all 30 programs**: ~300
- **Programs with ⊢∘ evolution loops**: 27/30 (90%)
- **Programs with ⊢⊢ spawners**: 19/30 (63%)
- **Programs with both ⊢∘ and ⊢⊢**: 18/30 (60%)
- **Programs with ⊢= crystallized cells**: 23/30 (77%)
- **Programs with § quotation**: 22/30 (73%)

### v0.2 feature combinations

Most common feature bundle (the "full v0.2 stack"):
`file-scope ⊨? + ⊢∘ aspirational + guard clauses + ⊢⊢ accumulate + wildcard deps + given?`

Programs with ALL six: 04, 08, 10, 14, 22, 26, 29 (7 programs, 23%)

### Pattern frequency

| Pattern | Count | Percentage |
|---------|-------|------------|
| Oracle-Gated Convergence | 27 | 90% |
| Spawner-Then-Collect | 15 | 50% |
| Guard-Gated Dispatch | 15 | 50% |
| Staged Pipeline | 6 | 20% |
| Attacker-Defender-Judge | 3 | 10% |
| Proof-Carrying Computation | 3 | 10% |
| Co-Evolution | 3 | 10% |
| Self-Referential/Metacircular | 5 | 17% |
| Genetic Algorithm | 1 | 3% |
| Zero-Start Bootstrap | 1 | 3% |

### Key findings for R18

1. **file-scope ⊨? is universal** -- every program has it. It can be considered
   mandatory boilerplate rather than an optional feature.

2. **guard clauses are the most impactful v0.2 addition** -- 73% adoption, and
   they enable clean conditional dispatch without wasted LLM calls. Programs
   without them (02, 06, 09, 21, 23, 28) tend to be simpler/thinner.

3. **⊢⊢ accumulate is far more common than replace** (15 vs 3). Replace is used
   only when fresh verdicts are needed (fact-checking, crystallization). This
   suggests accumulate should remain the default.

4. **The weakest programs are the smallest** -- 02, 06, 21 all have 5-6 cells
   and use few v0.2 features. Size correlates with feature utilization.

5. **The strongest programs combine ⊢∘ + ⊢⊢ + guard + given?** -- this four-feature
   bundle enables the richest patterns (ADJ with accumulation, zero-start bootstrap,
   guard-gated dispatch with ⊥ tolerance).

6. **No program uses ⊢∘ on multiple INDEPENDENT loops** -- when multiple ⊢∘ appear
   (07, 09), they share the same through/until chain. True multi-loop programs
   (e.g., an outer evolution loop containing an inner convergence loop) are absent.

7. **⊢= expression language usage is uneven** -- 50% adoption, mostly in crystallized
   verifiers and aggregators. Many programs that could benefit from ⊢= (simple
   computations) still use ∴ bodies. R18 could push for more honest crystallization.

8. **Observation ⊢= cells are emerging** -- 26 has 7, 29 has 1, 30 has 5. This
   pattern (⊢= with documentation strings) is becoming a meta-commentary convention.
   Worth formalizing or discouraging.
