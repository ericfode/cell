# Round 16 Program Analysis (Programs 01-10)

Phase 1 analysis for R17 evolution cycle. Each program assessed against the
Cell v0.1 spec for feature usage, syntax issues, spec gaps, reusable patterns,
and overall quality.

---

## 01 — Research Plan Evolver

**Program**: `evolution/round-16/programs/01-research-plan-evolver.cell`
**Frames**: `evolution/round-16/frames/01-research-plan-evolver-frames.cell`

### Features exercised well

- **`⊢∘` evolution loop** (line 122-134): Correctly wires `evolve(hypothesize, problem->statement)` through `revise-hypotheses` with a convergence-score threshold. The loop ran 2 iterations, refining hypotheses from generic to focused. The `until revise-hypotheses->convergence-score >= 8` condition is a clean semantic gate.
- **`⊢⊢` spawner** (lines 53-78): `spawn-experiments` correctly spawns 3 experiment cells per iteration from a `section-experiment-template` definition. The spawner re-fires each iteration with different feasible experiments — demonstrating dynamic re-spawning under evolution.
- **`section` quotation** (line 56): `given section-experiment-template` passes the template cell definition as data for instantiation.
- **`guillemet` interpolation**: Used correctly throughout all soft cells for splicing upstream values into prompts.
- **`models` oracles**: Well-calibrated mix of deterministic (`length(hypotheses) >= 3`), structural (`each experiment maps to exactly one hypothesis`), and semantic (`hypotheses are mutually distinct`) assertions.

### Awkward/broken

- **Wildcard deps `experiment-*->result`** (lines 93-94): `collect-results` uses `given experiment-*->result` to gather dynamically spawned outputs. This pattern works but the spec says nothing about wildcard dependency syntax. Under `evolve-loop`, the wildcard must re-resolve each iteration as new experiment cells replace old ones — correct behavior, but unspecified.
- **Template formalization** (lines 67-78 vs 79-90): The template is described in BOTH a comment block inside the spawner AND as a separate `experiment-template` cell. Redundant. The comment block could be removed; the `section-experiment-template` reference is sufficient.
- **No `recover` handler**: The program lacks any `recover?` block. If any experiment cell fails, there is no recovery policy — the entire graph stalls.
- **Pass-through cells**: `problem` (lines 10-14) is a data cell that yields what it receives from `given`. This pattern works but feels like boilerplate — a bare `given` with `identical` binding that yields the same name.

### Spec gaps exposed

1. **Wildcard dependency syntax** (`experiment-*->result`): Not in the spec. Needs formal definition — when does `*` match, how does it compose with spawners, what happens when the match set changes across `evolve-loop` iterations?
2. **Template instantiation syntax**: The spawner's `therefore` body describes instantiation in natural language. Need explicit syntax like `spawn from section-template with { hypothesis: h, desc: e } for each (h, e) in feasible`.
3. **Spawner re-fire semantics under `evolve-loop`**: When `evolve-loop` restarts, do previous spawned cells get dropped? The frames show they do (iteration 2 spawns experiment-3/4/5, not re-running 0/1/2), but the spec doesn't define this.

### Reusable patterns

- **Hypothesis-experiment-evidence pipeline**: `hypothesize -> design-experiments -> evaluate-feasibility -> spawn-experiments -> collect-results -> revise-hypotheses`. This is a generic research loop that any investigation domain could adopt.
- **Infeasibility as signal**: The `evaluate-feasibility` cell filters experiments, and infeasibility shapes which hypotheses get evidence. Treating filter results as information (not just rejection) is a powerful pattern.
- **Convergence-score gating**: Using a numeric score with threshold (`>= 8`) as the `evolve-loop` termination condition. Clean, general, reusable.

### Quality rating

**Exemplary** — The most complex Cell program in R16 (14 total cells, 6 spawned, 2 iterations, 18 eval-one steps). Demonstrates evolution, spawning, oracle-gated convergence, and dynamic re-spawning working together. The frame trace is rich and the observations are insightful. The only weaknesses are unspecified wildcard syntax and missing recovery handlers.

---

## 02 — Self-Improving Prompt

**Program**: `evolution/round-16/programs/02-self-improving-prompt.cell`
**Frames**: `evolution/round-16/frames/02-self-improving-prompt-frames.cell`

### Features exercised well

- **`evolve-hard` (`hard-turnstile`)** (lines 15-61, 63-66): Two crystallized data cells (`sample-code`, `criteria`) using `hard-turnstile code assign` for deterministic string assignment. Clean and correct.
- **`section` quotation for rewriting** (lines 94, 96, 98-101): `improve` takes `given section-summarize` (the cell definition as data) and yields `section-summarize'` (the rewritten version). This is the canonical use of `section` — metacircular cell rewriting.
- **`evolve-loop` evolution** (lines 106-109): `evolve(summarize, sample-code->code identical sample-code->code)` through `judge, improve` until `judge->score >= 8`. The loop ran 3 iterations (score 4 -> 6 -> 8), with each iteration targeted by specific judge feedback.
- **Interface freeze verification** (lines 103-104): `models section-summarize' has same given/yield signature as guillemet-section-summarize-guillemet` — the Liskov oracle that prevents `evolve-loop` from breaking the dependency graph.

### Awkward/broken

- **`evolve-loop` binding syntax** (line 106): `evolve(summarize, sample-code->code identical sample-code->code)` is tautological — it binds `sample-code->code` to itself. The intent is to pass the input through, but the syntax reads oddly. Should this just be `evolve(summarize)` with implicit given preservation?
- **Oracle on summarize never enforced** (lines 74-75): `summarize` has oracles (`models summary identifies architectural patterns`) that FAIL in iteration 0 but the cell is frozen anyway. The frames explain this correctly (the `evolve-loop` drives retry, not the oracles), but it creates tension: oracles that fail without consequence feel ornamental. The spec should clarify that oracles on `evolve-loop`-managed cells are aspirational, not enforced.
- **`recover?` at file scope** (lines 111-112): `recover? on exhaustion: partial-accept(best)` appears at the END of the file, not attached to any specific cell. The spec shows `recover?` inside cell bodies. File-scope `recover?` is ambiguous — does it apply to `evolve-loop`?

### Spec gaps exposed

1. **Oracles on `evolve-loop`-managed cells**: When `evolve-loop` drives a cell's improvement, should that cell's own `models` assertions be enforced on each iteration? Or are they aspirational? The spec is silent.
2. **File-scope `recover?`**: The spec shows `recover?` inside cell blocks. A file-level `recover?` (not indented under any cell) has unclear scope.
3. **`evolve-loop` input binding syntax**: The `sample-code->code identical sample-code->code` pattern needs clarification — is it forwarding, rebinding, or something else?

### Reusable patterns

- **Judge + Improve separation**: Two distinct cells — `judge` evaluates and produces weaknesses, `improve` rewrites using those weaknesses. Different skills (evaluation vs rewriting) in different cells. Broadly applicable to any quality-improvement loop.
- **`evolve-loop` as prompt optimizer**: Write a bad `therefore` with good oracles. Let `evolve-loop` discover the right prompt. Humans write WHAT (oracles), machine discovers HOW (therefore evolution). This is the meta-pattern for Cell.
- **Score-gated convergence**: `until judge->score >= 8` with specific feedback per round.

### Quality rating

**Exemplary** — A clean, focused demonstration of the core Cell meta-pattern: soft cell evolution via `evolve-loop`. The 3-iteration arc (bad prompt -> pattern-aware -> full briefing) is compelling. The frame trace is detailed and the observations capture deep insights about oracle/evolution separation.

---

## 03 — Progressive Crystallization

**Program**: `evolution/round-16/programs/03-progressive-crystallization.cell`
**Frames**: `evolution/round-16/frames/03-progressive-crystallization-frames.cell`

### Features exercised well

- **Substrate transfer pipeline**: `solve-soft` (soft, `therefore`) -> `extract-pattern` -> `crystallize` -> `verify-crystal` -> `emit-crystallized` (produces `hard-turnstile` version). The entire program enacts the `turnstile -> hard-turnstile` transition documented in the spec's Crystallization section.
- **`section` quotation** (line 87): `emit-crystallized` takes `given section-solve-soft` to read the original cell definition and produce the crystallized replacement.
- **`refinement` annotation** (lines 96-97): `models if pass-all then crystallized-cell contains "refinement crystallized"` correctly references the refinement marker for substrate-transferred cells.
- **`recover?` with failure context** (lines 100-102): `recover? on failure: retry with guillemet-verify-crystal->failures-guillemet appended to prompt, max 2 attempts` — correct retry with feedback pattern per the spec.
- **Oracle-as-test-suite**: The `test-inputs`/`test-expected` data in `task` function as oracle data; `verify-crystal` runs them like unit tests.

### Awkward/broken

- **Too-easy problem**: "Top 3 largest numbers" is trivially crystallizable — `sort().take(min(3, len()))`. The crystallization gap between `therefore` and `hard-turnstile` is negligible. The program never exercises the failure/retry path. The "progressive" part of progressive crystallization was never tested.
- **No `evolve-loop`**: Despite the name suggesting iteration, this is a strictly linear 6-cell pipeline. No evolution, no spawning. The `recover?` on `emit-crystallized` could trigger retry, but it never fires because the crystal passes on first try.
- **Crystallized cell output format** (frame line 236-244): The yielded `crystallized-cell` is a string containing Cell syntax. But the spec doesn't define how one cell yields another cell's definition — is this just a string, or does it have structural meaning? Feels like `section` quotation should be the output type.

### Spec gaps exposed

1. **Crystallization output format**: When a cell produces a crystallized replacement, what is the yield type? A string? A `section`-typed value? The spec says `section` is quotation but doesn't define "yielding a cell definition as a replacement."
2. **`hard-turnstile` expression language**: `crystallize` yields `hard-turnstile result assign sort(guillemet-input-guillemet, descending).take(min(3, len(guillemet-input-guillemet)))` — but the spec doesn't define what expressions are valid in `hard-turnstile` bodies beyond the `assign` syntax. What built-in functions exist? What's the type system?
3. **Failure path for crystallization**: The spec discusses crystallization boundaries but doesn't specify what happens when `verify-crystal` fails and retries are exhausted. Does the program yield `bottom`? Does the soft cell persist?

### Reusable patterns

- **Crystallization pipeline**: `solve (soft) -> extract-pattern -> crystallize -> verify -> emit (hard)`. A general recipe for any soft-to-hard transition.
- **Oracle-as-test-suite**: Using `given test-inputs`/`given test-expected` as oracle data for verification. Clean separation of specification from implementation.
- **Permanently-soft crystallizer cells**: `extract-pattern`, `crystallize`, `emit-crystallized` must stay soft — they are the "warm layer" that enables others to go cold.

### Quality rating

**Adequate** — Correctly demonstrates substrate transfer, but the trivially-easy problem means the interesting failure paths are never exercised. The frame trace observations honestly note this ("THIS PROBLEM WAS TOO EASY"). A harder problem that forces retry or fails to crystallize would make this exemplary.

---

## 04 — Self-Building Test Suite

**Program**: `evolution/round-16/programs/04-self-building-test-suite.cell`
**Frames**: `evolution/round-16/frames/04-self-building-test-suite-frames.cell`

### Features exercised well

- **`spawner` with recursive edge discovery** (lines 81-96): `spawn-edge-tests` creates test cells from `edge-test-template`, each of which yields `deeper-edges[]` — discovered sub-edges. The spawner fires twice across 2 `evolve-loop` iterations (8 cells in iteration 1, 7 in iteration 2).
- **`evolve-loop` evolution** (lines 160-163): `evolve(discover-edge-cases, ...)` through `assess-coverage, refine-test-suite` until `assess-coverage->coverage-score >= 8`. Converges in 2 iterations as coverage plateaus at spec ambiguities.
- **Wildcard deps** (lines 120-122): `assess-coverage` uses `given edge-test-*->result`, `given edge-test-*->verdict`, `given edge-test-*->deeper-edges` to gather all spawned test results. Three wildcards in one cell.
- **Three-valued test verdict**: `edge-test-template` yields `verdict in { "pass", "fail", "ambiguous" }` — the "ambiguous" verdict makes spec gaps VISIBLE rather than masked.
- **File-scope `recover?`** (lines 196-199): `recover? on failure: retry ... max 3` and `recover? on exhaustion: partial-accept(best)`.

### Awkward/broken

- **`evolve-loop` binding** (line 160): `evolve(discover-edge-cases, run-tests->results identical run-tests->results)` — same tautological binding as program 02. The intent is to pass `run-tests->results` through to `discover-edge-cases`, but the syntax is confusing.
- **Spawner + `evolve-loop` interaction complexity**: The spawner fires inside the `evolve-loop`, creating cells that are gathered by wildcard deps, which feed into `assess-coverage`, which feeds into the convergence check. This 3-layer interaction (evolution wrapping spawning wrapping wildcard gathering) is powerful but verges on hard to reason about. The spec has no guidance on composing these features.
- **Redundant observations**: The frame trace repeats "date parsing is a perfect Cell problem" in multiple observation cells.

### Spec gaps exposed

1. **Spawner inside `evolve-loop`**: When a spawner fires inside an `evolve-loop` iteration, are previously-spawned cells retained or replaced? The frames show iteration 2 spawning NEW edge-test cells (numbered sequentially from iteration 1), suggesting accumulation. But program 01 showed replacement. Which is correct? The spec needs to define this.
2. **Wildcard dep resolution timing**: `edge-test-*` must resolve to all matching cells. But when does matching occur — at parse time, at ready-set computation, or at evaluation time? The set of matching cells changes as spawners fire.
3. **Three-valued verdicts**: The `{ "pass", "fail", "ambiguous" }` pattern is powerful but not in the spec. The spec uses `check/cross` for pass/fail. Adding "ambiguous" (or `?`) as a first-class oracle result would formalize this discovery.

### Reusable patterns

- **Self-expanding test suite**: `discover-edge-cases -> spawn-edge-tests -> edge-test-* -> assess-coverage` — tests that generate more tests. The `deeper-edges[]` output from each edge test feeds future spawning rounds.
- **Ambiguity as valuable output**: `spec-questions[]` in the final output converts ambiguous test results into questions for the spec author. Test suites that discover spec gaps, not just code bugs.
- **Coverage plateau detection**: The `evolve-loop` terminates when remaining gaps are spec ambiguities (not testable edges). The coverage oracle distinguishes test gaps from spec gaps.

### Quality rating

**Exemplary** — The most feature-dense program in R16, exercising `evolve-loop`, `spawner`, wildcards, three-valued verdicts, and recursive edge discovery in a single coherent design. 25 eval-one frames, 22 total tests generated, 5 spec ambiguities discovered. The domain (date parsing) is a perfect match for Cell's adaptive exploration.

---

## 05 — Meta-Cell Designer

**Program**: `evolution/round-16/programs/05-meta-cell-designer.cell`
**Frames**: `evolution/round-16/frames/05-meta-cell-designer-frames.cell`

### Features exercised well

- **`section` quotation as program-output**: `design-cells` yields `section-program` — an entire Cell program as a value. Downstream cells (`trace-readiness`, `simulate-oracles`, `critique`) inspect, analyze, and rewrite this program. This is Cell's metacircular capability in action.
- **`hard-turnstile` for static data** (lines 21-25): `cell-spec` uses multiple `hard-turnstile` assignments for `symbols`, `execution-model`, and `patterns`. Clean encoding of reference data as deterministic cells.
- **`evolve-loop` for design convergence** (lines 144-152): `evolve(design-cells, ...)` through `critique, redesign` until `length(critique->problems) = 0`. Converges in 2 iterations (5 problems found, all fixed, zero remaining).
- **Design verification pipeline**: `design-cells -> trace-readiness -> simulate-oracles -> critique -> redesign`. The designed program is checked for scheduling validity, oracle quality, and design problems before acceptance.

### Awkward/broken

- **`evolve-loop` parameter explosion** (line 144): `evolve(design-cells, decompose->components, decompose->dataflow, cell-spec->symbols, cell-spec->execution-model)` passes 4 extra bindings. The spec shows `evolve(cell, input)` with one or two params. This 5-parameter form stretches the syntax.
- **`redesign->section-program'` access** (line 155): `emit-program` takes `given redesign->section-program'`. The prime mark on a `section`-prefixed name is unusual — `section-program'` means "the rewritten version of the program definition." The syntax is legal per spec but dense.
- **Structural vs semantic convergence**: The convergence condition `length(critique->problems) = 0` is structurally clean but semantically hollow — `critique` could simply stop finding problems (LLM exhaustion) rather than there being no problems left. Same issue as 06-spec-hardener.

### Spec gaps exposed

1. **`evolve-loop` with many parameters**: The spec shows `evolve(cell, input)`. Multi-parameter forms like `evolve(cell, a, b, c, d)` need specification — are these all forwarded as givens?
2. **Nested `section` values**: When `section-program` contains a Cell program that itself uses `section` quotation (the designed program has `given section-vuln-scanner-template`), how deep does quotation nest? Is the inner `section` evaluated or treated as literal text?
3. **Programs-that-write-programs validation**: How does the runtime verify that `section-program` is valid Cell syntax? Is there a structural check, or is it just a string that happens to be parseable?

### Reusable patterns

- **Meta-design loop**: `decompose -> design -> analyze -> critique -> redesign`. Any problem that can be decomposed into components and checked for design quality can use this pipeline.
- **Oracle quality as design criterion**: `simulate-oracles` classifies each oracle as deterministic/semantic/ambiguous/tautological. This is a general technique for improving oracle design in any Cell program.
- **Self-designing programs**: The output of this program is itself a valid Cell program. Cell programs that produce Cell programs — the metacircular aspiration made concrete.

### Quality rating

**Exemplary** — Demonstrates Cell's deepest capability: programs that write programs. The designed code-review system is itself a well-structured Cell program with spawners, crystallized cells, and proof-carrying patterns. The critique/redesign loop found and fixed 5 genuine oracle quality issues. The frame trace is thorough and the observations are insightful.

---

## 06 — Spec Hardener

**Program**: `evolution/round-16/programs/06-spec-hardener.cell`
**Frames**: `evolution/round-16/frames/06-spec-hardener-frames.cell`

### Features exercised well

- **Adversarial `evolve-loop`** (line 104-107): `harden(oracle-spec)` through `attack, defend, judge-fix` until `attack->severity = "none"`. This is `evolve-loop` used for adversarial convergence rather than cooperative improvement — same combinator, different topology.
- **`section` for spec-as-data** (lines 49, 67, 85): `attack` reads `section-oracle-spec`, `defend` reads it and yields `section-oracle-spec'`, `judge-fix` compares both. Clean metacircular use: the Cell spec section is itself a value being operated on by Cell.
- **Three-role separation**: `attack` (find ambiguities), `defend` (fix them), `judge-fix` (verify fixes). Each role has clear responsibilities, explicit inputs, and distinct oracle assertions.
- **`hard-turnstile` for literal spec text** (lines 13-46): `oracle-spec` uses `hard-turnstile text assign` to embed the Oracle System spec section as a deterministic string value.

### Awkward/broken

- **`evolve-loop` target syntax** (line 104): `harden(oracle-spec)` names the evolving cell but the spec's `evolve-loop` syntax is `evolve(cell, input)`. Using a different verb (`harden` vs `evolve`) is a creative deviation — it reads well but isn't spec-conformant. The `evolve-loop` symbol is `evolve-loop` (evolution combinator), not a general "name your own combinator" syntax.
- **No max on iterations before none** (line 107): `max 4` is the safety bound, but convergence depends entirely on the attacker's capability. A stronger attacker might never yield "none." The `max` is essential here but feels arbitrary.
- **`recover?` on `judge-fix`** (lines 100-102): Attached to `judge-fix`, not to the `evolve-loop`. This is correct (retry the judge, not the whole loop), but the placement could confuse readers.

### Spec gaps exposed

1. **`evolve-loop` verb naming**: The spec defines `evolve-loop evolve(cell, input)`. Program uses `evolve-loop harden(oracle-spec)`. Can the verb be anything? Or must it always be `evolve`?
2. **Adversarial termination semantics**: `until attack->severity = "none"` means the attacker decides when to stop. This is fundamentally different from cooperative `evolve-loop` where a judge scores convergence. Should the spec distinguish these patterns?
3. **Evolving a `hard-turnstile` cell**: `oracle-spec` is a `hard-turnstile` cell (deterministic text). The `evolve-loop` replaces its output with `section-oracle-spec'` — transforming a hard cell's value. Is this legal? The spec says `evolve-loop` rewrites soft cells. Rewriting a hard cell's yield is semantically different.

### Reusable patterns

- **Attack/Defend/Judge triple**: A general pattern for adversarial specification improvement. Applicable to any artifact that needs hardening: specs, policies, security configurations, API contracts.
- **Adversarial `evolve-loop`**: Using `evolve-loop` with `until attacker-finds-nothing` as convergence. The attacker's exhaustion is the termination signal.
- **Metacircular spec validation**: Cell program that hardens Cell's own spec. The ambiguities found are genuine (timing of claim cell spawning, cell-zero nature, oracle promotion semantics).

### Quality rating

**Exemplary** — Elegant and focused. Only 4 cells + the evolving spec, yet demonstrates adversarial convergence, metacircular validation, and three-role separation. The 3-iteration arc (critical -> moderate -> none) is clean. The real ambiguities found in the Oracle System spec section are a genuine contribution to spec quality.

---

## 07 — Recursive Debate

**Program**: `evolution/round-16/programs/07-recursive-debate.cell`
**Frames**: `evolution/round-16/frames/07-recursive-debate-frames.cell`

### Features exercised well

- **Dual-cell `evolve-loop`** (lines 93-96): `debate(argue-for, argue-against)` through `judge-round, refine` until `judge-round->improved = false`. This evolves TWO cells through a single loop — adversarial co-evolution where each side improves in response to the other.
- **`section` quotation for dual rewriting** (lines 73-74, 78): `refine` takes `section-argue-for` and `section-argue-against`, yields `section-argue-for'` and `section-argue-against'`. Only the weaker side's `therefore` changes — the stronger side's definition passes through unchanged.
- **Fixpoint detection** (line 70): `models if improved = false then (for-score >= 8 and against-score >= 8) or (scores unchanged from prior round)`. The oracle precisely captures the termination semantics: both high quality, or no progress.
- **Alternating refinement**: The frame trace shows FOR refined in rounds 0 and 2, AGAINST in round 1. Scores oscillated (FOR: 5->7->7->8, AGAINST: 6->5->8->8) as each side responded to the other's strongest point.

### Awkward/broken

- **`evolve-loop` multi-cell syntax** (line 93): `debate(argue-for, argue-against)` passes two cells to `evolve-loop`. The spec shows `evolve(cell, input)` with a single cell. Multi-cell evolution is not specified — does `evolve-loop` natively support co-evolution, or is this an extension?
- **Unchanged cells re-evaluated** (frames lines 242-260): `argue-against` was not rewritten in iteration 1 but gets re-evaluated with the same `therefore` and same inputs, producing the same output. In a real runtime, this should be cached. The spec says nothing about caching unchanged cells under `evolve-loop`.
- **Custom verb again**: `debate(argue-for, argue-against)` uses `debate` instead of `evolve`. Same issue as program 06.
- **`judge-round` oracle reference to "prior round"** (line 70): The oracle says "scores unchanged from prior round" but there's no mechanism to access prior round scores within the cell's data. The judge must REMEMBER previous scores, which requires state outside the cell graph.

### Spec gaps exposed

1. **Multi-cell `evolve-loop`**: Spec defines evolution over one cell. Co-evolving multiple cells simultaneously needs specification — ordering, which cell gets rewritten, how the loop body coordinates multiple targets.
2. **Caching under `evolve-loop`**: When a cell's `therefore` and inputs are unchanged between iterations, should it be re-evaluated? The spec's monotonicity property suggests no (same inputs = same outputs), but this assumes deterministic LLM evaluation.
3. **Cross-round state**: The `improved` flag requires comparing current scores to previous scores. No mechanism in Cell for accessing prior iteration state. The judge must carry this information in its prompt context (via `evolve-loop` rewriting), but this is implicit.

### Reusable patterns

- **Alternating adversarial refinement**: Only the weaker side is refined each round. This prevents drift (both sides changing simultaneously without engaging) and creates a response chain. Essential for dialectic convergence.
- **Fixpoint as exhaustion, not agreement**: `improved = false` when both sides reach 8/8 — they DISAGREE but are at high quality. Dialectic fixpoint is not consensus; it's exhaustion of easy improvements.
- **Judge as curriculum designer**: Each round's feedback targets the most productive direction for improvement. The judge doesn't just score — it identifies WHERE to invest effort.

### Quality rating

**Exemplary** — The most philosophically interesting program. Dual-cell co-evolution through adversarial pressure, with the debate producing novel insights (fiduciary trust, information asymmetry, structural safeguards) that neither side started with. The frame trace captures genuine intellectual progression across 4 iterations and 16 eval-one steps.

---

## 08 — Red Team Harden

**Program**: `evolution/round-16/programs/08-red-team-harden.cell`
**Frames**: `evolution/round-16/frames/08-red-team-harden-frames.cell`

### Features exercised well

- **`evolve-loop` with artifact accumulation** (lines 114-128): `evolve(red-team, target-code->code identical harden->patched-code)` runs 5 full iterations. Each iteration finds a vulnerability, patches it, verifies the patch, and spawns a regression test. The regression tests ACCUMULATE across iterations — each round adds to the set.
- **`spawner` for regression tests** (lines 83-98): `spawn-regression-test` creates one regression test cell per iteration. These cells join the growing `regression-tests` set that constrains future patches. The spawner fires once per `evolve-loop` iteration.
- **Code evolution through patching**: The target code evolves from a 3-line naive login function to a 30+ line hardened version with bcrypt, timing-safe comparison, rate limiting, and bounded state. Each patch is minimal and verified.
- **`recover?` on `verify-patch`** (lines 80-81): Correct placement — retry verification with failure context.

### Awkward/broken

- **`evolve-loop` binding complexity** (line 114): `evolve(red-team, target-code->code identical harden->patched-code)` — the binding says "feed harden's patched code back as target-code's code for the next iteration." This is correct but syntactically dense. The `identical` binds the NEXT iteration's input to the CURRENT iteration's output.
- **`regression-tests[]` as implicit accumulator** (lines 27, 37, 49, 67): `red-team`, `harden`, and `verify-patch` all take `given regression-tests[]` but the spec has no accumulator syntax. The program relies on the runtime to grow this list as `spawn-regression-test` fires. This is a critical semantic gap.
- **Max iterations hit** (frame line 900-906): The `evolve-loop` ran all 5 iterations without the red-team yielding "none." The code could be hardened further (no logging, no CAPTCHA). The max bound is essential but means the termination is budgetary, not semantic.
- **Wildcard deps in `security-report`** (lines 132-133): `given regression-test-*->passes` and `given regression-test-*->explanation` gather all accumulated tests. Same unspecified wildcard pattern as programs 01 and 04.

### Spec gaps exposed

1. **Accumulator semantics**: `regression-tests[]` grows across `evolve-loop` iterations. The spec defines monotonicity for frozen yields, but not for list values that grow by spawner accumulation. How does a `given` reference a list that new cells are being added to?
2. **`evolve-loop` with output-to-input binding**: `target-code->code identical harden->patched-code` pipes one cell's output as another cell's input for the next iteration. This is powerful but the spec only shows `evolve(cell, input)` where `input` is a fixed given.
3. **Non-semantic termination**: When `evolve-loop` hits `max` without the `until` condition being met, what is the final state? The patched code from the last iteration? The best code? The spec's `recover? on exhaustion: partial-accept(best)` applies to retries, not to `evolve-loop` max.

### Reusable patterns

- **Adversarial accumulation loop**: `red-team -> harden -> verify -> spawn-regression -> (repeat)`. Each round adds a permanent regression test. The test set grows monotonically, preventing regression. Any security hardening, quality improvement, or refactoring task could use this.
- **Code-as-evolving-value**: The target code passes through the `evolve-loop` as a value that gets patched each round. The code IS the state being improved.
- **Regression-as-spawned-cells**: Each regression test is a first-class cell in the graph, with its own oracles and verification logic. Not a row in a list — a living entity.

### Quality rating

**Exemplary** — The most practically useful program in R16. Demonstrates a real-world security workflow: red-team, patch, verify, regress, repeat. The 5-iteration arc evolves a naive 3-line function into hardened production code with bcrypt, timing-safe comparison, rate limiting, and bounded state management. The accumulating regression test pattern is Cell's killer feature for iterative improvement tasks.

---

## 09 — Negotiation Consensus

**Program**: `evolution/round-16/programs/09-negotiation-consensus.cell`
**Frames**: `evolution/round-16/frames/09-negotiation-consensus-frames.cell`

### Features exercised well

- **N-way parallel evaluation**: Four perspective cells (`perspective-cto`, `perspective-senior`, `perspective-junior`, `perspective-investor`) all become ready simultaneously after `question` is frozen. Confluence guarantees order doesn't matter. In a parallel runtime, all four could execute simultaneously.
- **Multiple `evolve-loop` loops** (lines 160-178): Four separate `evolve-loop` declarations, one per perspective, all sharing the same mediator and convergence condition (`mediate->consensus-score >= 8`). Each perspective revises independently.
- **Mediator pattern** (lines 70-98): `mediate` is a synchronization barrier that waits for all N perspectives, identifies common ground and disagreements, and produces a consensus score. Reusable for any N-party decision.
- **Reasoned concession tracking**: The frame trace shows the Senior shifting from Rust to TypeScript with specific conditions (strict config, modular architecture). The Junior shifted from Python to TypeScript for specific reasons (career growth, full-stack). Not averaging — reasoning.

### Awkward/broken

- **Four separate `evolve-loop` declarations** (lines 160-178): Four `evolve-loop evolve(perspective-X, question->text)` blocks that all share the same `through mediate, revise-X` pattern and `until` condition. This is verbose and repetitive. If there were 10 perspectives, you'd need 10 `evolve-loop` blocks. The spec needs a way to evolve N cells through a shared loop body.
- **Revision cells duplicate perspective logic** (lines 100-158): `revise-cto`, `revise-senior`, `revise-junior`, `revise-investor` are nearly identical — same structure, same oracle pattern. Only the role description differs. This begs for parameterization (like a template).
- **Mediator as sole convergence judge**: The mediator's `consensus-score` is the only convergence gate. But the mediator is a single LLM evaluation — there's no cross-check. A biased mediator could declare consensus prematurely.
- **`evolve-loop` coordination**: Four parallel `evolve-loop` loops sharing one mediator. The spec doesn't define how multiple `evolve-loop` loops interact. Do they all re-evaluate `mediate` independently? Or does `mediate` evaluate once per round with all four revised inputs?

### Spec gaps exposed

1. **Multi-agent `evolve-loop`**: Four `evolve-loop` blocks sharing one mediator and convergence condition. The spec needs to define coordination: do they evaluate in lockstep? Can one perspective converge early while others continue?
2. **`evolve-loop` over parameterized cells**: The four revision cells are structurally identical. Need syntax for `evolve-loop` over a parameterized set, e.g., `evolve-loop for each perspective in [cto, senior, junior, investor]`.
3. **N-way synchronization barrier**: `mediate` waits for all N perspectives before evaluating. The spec's eval-one model evaluates one cell at a time. A synchronization barrier that requires multiple cells to be frozen before a downstream cell becomes ready is implicit but not formalized.

### Reusable patterns

- **Mediator pattern**: `N perspectives -> mediator -> N revisions -> mediator (repeat)`. A general consensus protocol for any multi-stakeholder decision.
- **Concession with conditions**: Perspectives shift positions by extracting conditions (Senior: "TypeScript IF strict config AND modular architecture"). The oracle `models reasoning addresses at least one item from mediate->disagreements` forces engagement with disagreements.
- **Asymmetric concession costs**: Parties with more at stake negotiate harder for conditions. The negotiation dynamics emerge naturally from the Cell structure.

### Quality rating

**Adequate** — Demonstrates N-way parallel evaluation and multi-party consensus well. The domain (programming language selection) is engaging and the frame trace shows realistic negotiation dynamics. Downgraded from exemplary because the four duplicate `evolve-loop` blocks and four near-identical revision cells suggest the need for parameterization that the spec doesn't support. The program works but exposes a real expressiveness limitation.

---

## 10 — Socratic Teacher

**Program**: `evolution/round-16/programs/10-socratic-teacher.cell`
**Frames**: `evolution/round-16/frames/10-socratic-teacher-frames.cell`

### Features exercised well

- **`evolve-loop` for adaptive teaching** (lines 89-92): `teach(ask)` through `simulate-student, evaluate, design-followup` until `evaluate->understanding-level = "solid"`. The question evolves from generic to targeted based on specific misconceptions discovered each round. 4 iterations (partial -> partial -> partial -> solid).
- **`spawner` for remedial accumulation** (lines 94-105): `spawn-remedials` creates targeted remedial cells for each misconception discovered. 4 remedials spawned across 4 iterations. These accumulate as a reusable misconception library.
- **`section` for question rewriting** (lines 72, 75): `design-followup` takes `section-ask` and yields `section-ask'`. The rewrite is conditional on understanding level: "none" -> simpler, "partial" -> target misconception, "solid" -> advance.
- **Adaptive difficulty scaling**: The questions naturally progressed: prerequisites (parallel work) -> per-file tracking -> merge vs rebase visual -> shared-branch rebase trap. Each question adapted to the specific misconception from the previous round.
- **Simulated student realism**: The student's trajectory (vague -> wavering -> confidently wrong -> correctly derived) mirrors real learning without changing `simulate-student`'s `therefore` block.

### Awkward/broken

- **`spawner` missing `max` and `until`** (lines 94-96): `spawn-remedials` has no `until` or `max` constraint. The spec shows spawners with both. Without bounds, the spawner fires once per `evolve-loop` iteration but there's no explicit termination check on the spawner itself.
- **`spawner` + `evolve-loop` interaction**: `spawn-remedials` depends on `evaluate->misconceptions`, which changes each `evolve-loop` iteration. The spawner fires each iteration with DIFFERENT misconceptions. But the previously spawned remedials persist. Is this correct? Should remedials from iteration 0 survive to iteration 3?
- **Remedials never evaluated**: The spawned remedial cells (lines 94-105, frames lines 142-171) are created but never executed in the trace. They "await future students" but this means the program produces artifacts it doesn't use. The `evolve-loop` doesn't incorporate remedial feedback.
- **Student-derived rule not captured**: The student derives "rebase local, merge shared" in their answer (frame line 493), but this insight exists only in `simulate-student->answer`. No cell captures it as a verified learning outcome. A `verify-understanding` cell that checks whether the student's rule is correct would close the loop.

### Spec gaps exposed

1. **`spawner` without bounds**: The spec shows `until` and `max` on spawners. Can a spawner omit both? What bounds its execution? In this program, it fires exactly once per `evolve-loop` iteration because `evaluate->misconceptions` changes, but this is implicit.
2. **Accumulated vs replaced spawned cells under `evolve-loop`**: Program 01 shows spawned cells being replaced between iterations. This program shows them accumulating. Both behaviors make sense for their domains, but the spec needs to define which is default and how to select the other.
3. **`evolve-loop` + `spawner` composition semantics**: When `evolve-loop` and `spawner` operate in the same program, their interactions are complex. The spec should define the order of operations: does `evolve-loop` unfreeze happen before or after `spawner` accumulation?

### Reusable patterns

- **Adaptive questioning loop**: `ask -> student -> evaluate -> design-followup -> (repeat)`. A general Socratic teaching pattern. The question adapts; the student model is fixed; evaluation identifies misconceptions; followup targets them.
- **Misconception library via `spawner`**: Remedial cells accumulate as `evolve-loop` iterates. Future students with the same misconception can be routed directly to the matching remedial. Teaching produces curriculum.
- **Conditional `therefore` rewriting**: `design-followup` uses `understanding-level` to determine rewrite strategy (simpler/targeted/advance). The oracle verifies the rewrite matches the level. General pattern for adaptive difficulty.
- **Student-derived knowledge**: The student derives the rule, not the teacher. Socratic method embodied in Cell's structure: the rule appears in `simulate-student->answer`, not in `ask->question`.

### Quality rating

**Exemplary** — The most pedagogically sophisticated program. The 4-iteration teaching arc is realistic and well-paced: prerequisites -> misconception identification -> targeted probe -> student derivation. The spawned remedial library is a genuine contribution to reusable curriculum generation. The student simulation is impressively calibrated, tracking real learning progression without changing its own `therefore` block. Minor issues (remedials never evaluated, missing verification cell) don't undermine the core design.

---

## Cross-Program Summary

### Feature coverage across programs 01-10

| Feature | 01 | 02 | 03 | 04 | 05 | 06 | 07 | 08 | 09 | 10 |
|---------|----|----|----|----|----|----|----|----|----|----|
| `turnstile` | Y | Y | Y | Y | Y | Y | Y | Y | Y | Y |
| `hard-turnstile` | - | Y | - | - | Y | Y | Y | - | - | Y |
| `spawner` | Y | - | - | Y | - | - | - | Y | - | Y |
| `evolve-loop` | Y | Y | - | Y | Y | Y | Y | Y | Y | Y |
| `models` | Y | Y | Y | Y | Y | Y | Y | Y | Y | Y |
| `recover?` | - | Y | Y | Y | - | Y | - | Y | - | - |
| `section` | Y | Y | Y | - | Y | Y | Y | - | - | Y |
| `guillemets` | Y | Y | Y | Y | Y | Y | Y | Y | Y | Y |
| wildcards | Y | - | - | Y | - | - | - | Y | - | - |

### Top spec gaps requiring R17 attention

1. **Wildcard dependency syntax** (`cell-*->field`): Used in 01, 04, 08 but not in the spec.
2. **`evolve-loop` multi-cell evolution**: Programs 07 and 09 evolve 2+ cells. Spec shows only one.
3. **Spawner behavior under `evolve-loop`**: Accumulate vs replace? Programs 01 and 10 disagree.
4. **`evolve-loop` verb naming**: Programs 06 (`harden`), 07 (`debate`), 10 (`teach`) use custom verbs. Spec shows only `evolve`.
5. **Accumulator/growing-list semantics**: Program 08's `regression-tests[]` grows across iterations. No spec support.
6. **Three-valued oracle results**: Program 04's `{pass, fail, ambiguous}` pattern is powerful but not in spec.
7. **N-way synchronization barriers**: Program 09's mediator waits for 4 cells. Implicit but not formalized.

### Quality distribution

- **Exemplary**: 01, 02, 04, 05, 06, 07, 08, 10 (8 of 10)
- **Adequate**: 03, 09 (2 of 10)
- **Problematic**: none

R16 produced consistently high-quality programs. The two "adequate" ratings are for programs that work correctly but either chose too-easy a problem (03) or exposed expressiveness limitations they couldn't work around (09).
