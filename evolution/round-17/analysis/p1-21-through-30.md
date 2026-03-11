# Round 16 Program Analysis: Programs 21-30

Analysis for R17 evolution cycle. Each program assessed against the Cell v0.1 spec
for feature usage, correctness, spec gaps, reusable patterns, and quality.

---

## Program 21: self-correcting-translator

**Domain**: Translation round-trip verification with iterative correction.

### Features exercised well

- **`⊢∘`**: Textbook use as a correction loop. `refine(translate) through back-translate, diff, correct until diff->acceptable = true max 5`. Clean convergence in 2 iterations.
- **`⊢=`**: Source cell uses `⊢=` correctly for deterministic text binding.
- **`⊨`**: Rich conditional oracles on `diff` (`if drift-score <= 1 then acceptable = true`). Four oracles on `diff` create an interlocking correctness net.
- **`⊨?`**: Recovery policy on `correct` with failure context feedback (`retry with drifted-segments appended`).
- **`«»`**: Guillemets used naturally throughout for interpolation (`«source->text»`, `«translate->spanish-text»`).

### Awkward/broken

- **Line 80**: `⊢∘ refine(translate)` — the spec says `⊢∘` takes a cell and parameters, but `translate` has no explicit parameter override here. The `through` clause implies translate's output is replaced by `correct->corrected-spanish`, but this replacement semantic is not specified in v0.1. The trace (frame 4-5) shows the corrected text flowing back as the new `translate->spanish-text`, which is reasonable but relies on implicit substitution.
- **Lines 52-55**: The four conditional oracles on `diff` use `if...then` predicates that create overlapping cases. The LLM correctly evaluates N/A for inapplicable branches, but the spec does not define how conditional oracles interact with each other or what "N/A" means formally.

### Spec gaps exposed

1. **`⊢∘` output substitution**: How does `correct->corrected-spanish` replace `translate->spanish-text` in the next iteration? The spec says "parameterized fixed-point combinator" but does not specify which cell's output gets swapped and how the plumbing reconnects.
2. **Conditional oracle semantics**: `if X then Y` oracles need formal treatment. When the precondition is false, is the oracle vacuously true, skipped, or N/A? The trace treats it as N/A but the spec is silent.

### Reusable patterns

- **Back-translation verification**: The translate->back-translate->diff->correct cycle is a general pattern for any lossy transformation: compress/decompress fidelity, paraphrase stability, format conversion round-trips.
- **Segment-level correction**: Only drifted segments are retranslated (locality of repair), preventing cascade destabilization. Generalizes to any "fix only what's broken" pattern.

### Quality rating

**Exemplary**. Compact (84 lines), clean dataflow, converges in 2 iterations with observable drift reduction, excellent frame trace with detailed LLM reasoning. The observations correctly identify the NP/P asymmetry of translation vs verification.

---

## Program 22: fact-checked-article

**Domain**: Article generation with per-claim spawned fact-checkers and iterative correction.

### Features exercised well

- **`⊢⊢`**: `spawn-fact-checkers` spawns 18 independent fact-check cells from `claims[]`. Correct use of spawner for embarrassingly parallel verification.
- **`⊢∘`**: `fact-check-loop(generate-article) through spawn-fact-checkers, aggregate-results, rewrite-article until all-pass max 3`. Converges in 2 iterations.
- **`⊨`**: Aggregate-results has tight interlocking oracles (`pass-count + fail-count + uncertain-count = length(checkers)`). Mathematical consistency enforced.
- **`⊨?`**: Recovery on `rewrite-article` with failed-claims context.
- **`«»`**: Used to splice claim text into spawned cell definitions.

### Awkward/broken

- **Line 63**: `given spawn-fact-checkers->§checkers` — aggregate-results takes the list of spawned cell *definitions* as input. But what it actually needs are the *outputs* (verdicts) from those cells, not their definitions. The trace (frame 21) shows the LLM interpreting this as "collect verdicts from all spawned cells," which is the right behavior but the `§` reference is semantically wrong. It should be `fact-check-*->verdict` or similar wildcard.
- **Line 104**: `⊢∘ fact-check-loop(generate-article)` — the loop should feed `rewrite-article->article-text'` back as `generate-article->article-text` for the next iteration, but the substitution mechanics are unclear. The trace handles it correctly but the program text is ambiguous.

### Spec gaps exposed

1. **Spawned cell output aggregation**: No spec mechanism to collect outputs from dynamically spawned cells. The `specialist-*->findings` wildcard pattern (used in program 29) is one approach, but spawned cells named `fact-check-N` need either wildcard references or the spawner to aggregate.
2. **`§checkers[]` vs actual outputs**: The `§` sigil means "definition as data," but `aggregate-results` needs *executed outputs*. The spec conflates these in spawner contexts.

### Reusable patterns

- **Spawner-as-parallel-oracle**: Break one complex verification into N independent simple checks. Each spawned cell is a single-claim oracle. Maximally parallel.
- **Surgical rewriting**: Only sentences containing failed claims are modified. The `length(claims') = length(claims)` oracle prevents structural destabilization.
- **Editorial workflow formalization**: Writer -> fact-checkers -> editor -> revise -> loop. Real-world process made executable.

### Quality rating

**Exemplary**. The most impressive trace in the batch: 18 spawned fact-check cells, 2 real factual errors found (BitKeeper date conflation, GitHub co-founder attribution), surgical correction, convergence in 2 iterations. The frame trace is 765 lines of detailed reasoning.

---

## Program 23: multi-oracle-gauntlet

**Domain**: Multi-dimensional quality checking (5 independent oracle dimensions) on a monad explanation.

### Features exercised well

- **`⊢∘`**: `refine(explain) through oracle-structural, oracle-semantic, oracle-factual, oracle-stylistic, oracle-logical, gauntlet, rewrite until gauntlet->all-pass max 5`. Seven cells in the `through` chain.
- **`⊢= ▸ crystallized`**: `gauntlet` cell is crystallized (line 129): boolean conjunction, list concatenation, label collection. No LLM needed for aggregation. Demonstrates the "verification crystallizes before computation" principle.
- **`⊨`**: Each oracle cell has clean boolean-gated issue lists. If ok then issues empty; if not ok then issues non-empty with specifics.
- **`⊨?`**: Recovery on `rewrite` with failure-report context.
- **`«»`**: Interpolation of topic fields into oracle prompts.

### Awkward/broken

- **Lines 142-155**: The `⊢=` expressions in `gauntlet` use `collect()` and `concat()` which are not defined in the v0.1 spec. These appear to be pseudo-code for list operations. A real crystallized cell would need a defined expression language.
- **Line 188**: `⊨ revised-explanation is between 300 and 500 words` — this word-count oracle on the *rewrite* output is a good idea but means the rewrite must not just fix the specific error but also maintain length. This could conflict with targeted fixes.

### Spec gaps exposed

1. **Crystallized expression language**: `⊢=` cells use `collect()`, `concat()`, `¬` (negation), `∧` (conjunction) — none of these are specified in v0.1. The spec says "deterministic expression" but provides no grammar for what expressions are valid.
2. **Parallel oracle scheduling**: Five oracles are all ready simultaneously after `explain` freezes. The spec's Kahn's algorithm picks one, but the trace notes confluence guarantees the same result. The spec should explicitly bless parallel evaluation of independent ready cells.

### Reusable patterns

- **Multi-dimensional gauntlet**: N independent oracle cells check orthogonal quality dimensions, a crystallized aggregator computes pass/fail, a rewrite cell targets only failed dimensions. Re-run ALL oracles after any fix to detect regressions.
- **Crystallized aggregator**: Boolean conjunction over oracle results is inherently deterministic. This is the pattern: soft oracles -> hard aggregator -> conditional rewrite.

### Quality rating

**Exemplary**. The gauntlet pattern is the most broadly applicable oracle architecture in the batch. The trace catches a real semantic error (safeDivide argument order in Haskell) and fixes it surgically. The 5 parallel oracle cells demonstrate confluence in practice.

---

## Program 24: proof-carrying-code

**Domain**: Code generation + formal correctness proof for merge-sorted, with crystallized proof verifier.

### Features exercised well

- **`⊢= ▸ crystallized`**: `verify-proof` (line 118) is the showcase. Six structural checks (`has-loop-invariant`, `invariant-references`, `has-monotone-quantity`, etc.) run without LLM. This IS the NP/P split: LLM generates proof (NP), crystallized verifier checks structure (P).
- **`⊢∘`**: `evolve(generate-proof) through verify-proof, fill-gaps until verdict = "proof complete" max 3`. Proof repair loop.
- **`§`**: `generate-code` yields `§implementation` — code-as-data for potential further analysis.
- **`⊨`**: Oracles on generate-proof enforce proof completeness (`at least 5 logical steps`, `invariants includes loop invariant referencing i, j, result`).
- **`⊨? on exhaustion`**: Lines 217-220 — `partial-accept(best)` at the program level as fallback.

### Awkward/broken

- **Line 171**: `⊢∘ evolve(generate-proof, spec->preconditions = spec->preconditions)` — the second parameter re-binds a value to itself. This appears to be an attempt to pass extra context to the evolution loop, but the syntax is unusual and not clearly specified in v0.1.
- **Lines 126-142**: The crystallized verifier uses `has-loop-invariant()`, `invariant-references()`, `proof-covers()`, `missing-from()` — all undefined helper functions. The trace just marks them as boolean checks, but a real crystallized cell needs these to be defined.
- **Lines 217-220**: `⊨? on failure` and `⊨? on exhaustion` appear at program-level (no enclosing cell). The spec shows these inside cells, not as top-level directives.

### Spec gaps exposed

1. **`⊢∘` parameter passing**: How does `⊢∘ evolve(generate-proof, spec->preconditions = spec->preconditions)` work? The spec shows `⊢∘ evolve(greet, name = "Alice")` but doesn't explain how extra bound values flow into the iteration.
2. **Crystallized helper function library**: `⊢=` cells need builtin operations for string matching, list operations, structural checks. The spec has no standard library.
3. **Program-level `⊨?`**: Recovery policies outside any cell scope need definition.

### Reusable patterns

- **Dual evidence channels**: Tests (empirical) and formal proof (deductive) are independent evidence. Neither subsumes the other. The certificate bundles both.
- **Proof gap-filling loop**: Generate proof -> verify structure -> fill gaps -> re-verify. This is the interactive theorem prover workflow as a Cell `⊢∘`.
- **Crystallization boundary at P/NP**: Generating the proof is soft. Checking proof structure is hard. The boundary aligns with computational complexity.

### Quality rating

**Exemplary**. The most theoretically significant program in the batch. Demonstrates Cell's killer pattern (proof-carrying computation) on a concrete algorithm. The trace converges in 1 iteration (proof was complete on first generation), with a 6-step correctness argument covering initialization, sortedness preservation, permutation, and termination.

---

## Program 25: oracle-chain-builder

**Domain**: Recursive oracle decomposition — from "the API design is good" to 15 crystallized leaf checks.

### Features exercised well

- **`⊢⊢`**: Two spawners: `spawn-sub-decomposers` (spawns refiner cells for soft sub-oracles) and `spawn-crystallizers` (spawns `⊢= ▸ crystallized` check cells for all leaves). Layered spawning.
- **`⊢∘`**: `refine-loop(decompose) through spawn-sub-decomposers, collect-results until soft-count' = 0 max 3`. Converges in 1 iteration (all soft -> structural/deterministic in one pass).
- **`⊢= ▸ crystallized`**: 15 spawned leaf checks are crystallized: `contains()`, `all-segments-match()`, `count-matches()`. Also `verify-coverage` as final crystallized verdict.
- **`§`**: Spawned cells referenced as `§refiners[]` and `§leaf-checks[]`.
- **`⊨`**: Classification constraints (`each classification in {"soft", "structural", "deterministic"}`), count constraints (`soft-count = count of "soft"`).

### Awkward/broken

- **Line 91**: `⊨ length(§refiners) = decompose->soft-count` — checking the count of *spawned cell definitions* against a numeric field. This works conceptually but mixes the `§` (definition) namespace with numeric comparison.
- **Lines 130-162**: `spawn-crystallizers` spawns cells with template-like `⊢= holds <- <deterministic check>` where the angle brackets indicate a placeholder. The actual check logic is not Cell syntax — it is left as pseudo-code for the LLM to fill in during spawning.
- **Lines 205-209**: `⊨? on failure` and `⊨? on exhaustion` on `verify-coverage` which is a crystallized cell. Recovery policies on `⊢=` cells are meaningless — deterministic cells cannot fail oracle checks (the oracle just re-checks the same deterministic result).

### Spec gaps exposed

1. **Spawned cell templates**: The `<deterministic check of oracle-text against artifact>` placeholder (line 151) is not valid Cell syntax. How does a spawner specify the `⊢=` body of a dynamically generated cell?
2. **`⊨?` on crystallized cells**: If a `⊢=` cell is deterministic, its oracles are contracts, not guardrails. Retry is pointless. The spec should clarify that `⊨?` is only meaningful on soft cells.
3. **Oracle classification taxonomy**: The "soft/structural/deterministic" classification drives the decomposition logic but is not part of the spec. This is a useful meta-concept that could be formalized.

### Reusable patterns

- **Recursive oracle refinement**: Any vague quality assertion can be mechanically decomposed into a tree of specific, checkable assertions. Soft oracle -> N structural/deterministic sub-oracles -> crystallized leaf checks. Generalizes to: legal compliance, safety analysis, code review criteria.
- **Two-phase spawning**: First `⊢⊢` spawns refiners (analytical), second `⊢⊢` spawns verifiers (checking). The refiners produce the oracle tree; the verifiers instantiate it as executable checks.
- **Amplification ratio**: 1 vague oracle -> 5 sub-oracles -> 15 leaf checks. The decomposition amplifies verification surface 15x while making each individual check trivial.

### Quality rating

**Exemplary**. The most architecturally ambitious program in the batch. Demonstrates that soft oracles are not a dead end — they decompose into hard checks. The trace produces a beautiful hierarchy tree. Minor issues with `⊨?` on crystallized cells and spawned cell template syntax.

---

## Program 26: cell-zero-exerciser

**Domain**: Metacircular execution — cell-zero evaluating p1-parallel-confluence, traced as a Cell program.

### Features exercised well

- **`§`**: Deep use of quotation. `§p1-parallel-confluence` as program-as-data, `§cell-zero.read-graph` as kernel function reference, `§claim-cells[]` for spawned oracle claims. This is the most thorough exercise of the `§` system in the batch.
- **`⊢=`**: Extensive use for deterministic phases: `pick-cell-0` through `pick-cell-4`, `evaluate-config`, `evaluate-combine`, `decide-0` through `decide-4`. Hard cells form the skeleton of the eval-one loop.
- **`⊨`**: Oracle checks on inner-level state (`cells = [config, poet, scientist, child, combine]`, `edges = [...]`). Asserts precise structural properties of the parsed target program.

### Awkward/broken

- **Line 32**: `given §cell-zero.read-graph` — this references a cell-zero kernel function with dot notation (`cell-zero.read-graph`), which is not defined in v0.1. The spec has no module or namespace system.
- **Lines 72-73, 267-268**: `⊢= pick-cell-0` (line 72) and `⊢= pick-cell-3` (line 267) are declared with `⊢=` prefix on the cell declaration itself, not just in the body. This is inconsistent — sometimes the cell is `⊢ name` with `⊢=` in the body, sometimes the whole cell is `⊢= name`. The spec only shows `⊢= expr` inside a cell body, not as a cell declaration modifier.
- **Lines 267-270**: `⊢= pick-cell-3` has no `given` clause — it just yields `§target-3 <- child` with no input dependencies. This makes it schedulable at any time, which is incorrect in the eval-one trace (it should only run after child becomes ready). Missing dependency on prior state.

### Spec gaps exposed

1. **Module/namespace syntax**: `§cell-zero.read-graph` implies a module system (cell-zero is a module, read-graph is a cell within it). The spec has no dot-notation for qualified cell references.
2. **`⊢=` as cell declaration prefix**: Is `⊢= cell-name` a valid shorthand for a fully deterministic cell? The spec only shows `⊢= expr` as a body form and `⊢ name ▸ crystallized` for crystallized cells.
3. **Eval-one state threading**: The exerciser manually threads state between frames (`invoke-check-inputs-0` -> `pick-cell-0` -> `evaluate-config` -> `spawn-claims-0` -> ...). There is no Cell construct for sequential state threading within a single execution trace.

### Reusable patterns

- **Three-level metacircular trace**: The outer program (exerciser) traces the middle program (cell-zero) evaluating the inner program (p1-parallel-confluence). Each level is a valid Cell document. This is the metacircular money shot.
- **Eval-one phase decomposition**: read-graph -> check-inputs -> pick-cell -> evaluate -> spawn-claims -> check-claims -> decide. This 7-phase cycle can template any cell-zero implementation.
- **Confluence annotation**: The trace explicitly marks confluence points ("CONFLUENCE! any ordering of {poet, scientist, child} produces the same final state"). This annotation style should be standard in Cell traces.

### Quality rating

**Adequate**. Ambitious and conceptually rich — a Cell program tracing cell-zero is the ultimate test of metacircularity. But the syntax issues are significant: `⊢=` as cell prefix, dot notation for modules, missing dependencies on `pick-cell-3`. The program sacrifices syntactic correctness for conceptual demonstration. The frame trace is thorough and correctly demonstrates confluence, fusion, and oracle-claim protocol.

---

## Program 27: self-optimizing-cell

**Domain**: Analyze a Cell program for redundancies, optimize, re-execute, compare semantics.

### Features exercised well

- **`⊢∘`**: `optimize(propose-optimization) through analyze-redundancy, ..., compare until semantics-preserved and step-delta >= 0 max 3`. Multi-condition convergence with conjunction.
- **`§`**: `§p2-spawner-cascade` as program-as-data for analysis. `§source-program->§program` correctly passes the quoted definition.
- **`⊢= ▸ crystallized`**: `compare` cell is crystallized for semantic comparison and step-delta computation. Good crystallization boundary — comparison is deterministic given the outputs.
- **`⊨?`**: Lines 164-169 — recovery with context ("Previous optimization changed semantics") and `partial-accept(best where semantics-preserved = true)` with a predicate on the partial-accept.
- **`⊨`**: Well-structured oracles on `propose-optimization` (`optimized-text has fewer lines`, `changes describes each modification`).

### Awkward/broken

- **Lines 140-149**: The `compare` cell is marked `▸ crystallized` but its `⊢=` body for `semantics-preserved` says `original-output and optimized-output address the same question with equivalent factual content`. This is a semantic judgment, not a deterministic computation. A crystallized cell should not require LLM judgment to evaluate. The trace resolves this by noting the outputs are identical (trivially true), but the cell definition is semantically wrong.
- **Line 154**: `⊢∘ optimize(propose-optimization, source-program->program-text)` — the second parameter passes `source-program->program-text` as extra context. The syntax for passing additional bound values to `⊢∘` is not specified in v0.1.
- **Lines 15-48**: The `source-program` cell embeds another Cell program as a string literal. This is the right approach (quoting), but the embedded program uses escaped quotes (`\"`) which makes it hard to read and error-prone.

### Spec gaps exposed

1. **Crystallization validity**: No mechanism to verify that a `⊢=` body is actually deterministic. `semantics-preserved <- (original-output and optimized-output address the same question...)` is soft, not hard.
2. **`⊢∘` with extra parameters**: The `source-program->program-text` parameter on the evolution loop needs formal treatment.
3. **`partial-accept` with predicates**: `partial-accept(best where semantics-preserved = true)` adds a filtering predicate to exhaustion handling. The spec only shows `partial-accept(best)` without predicates.

### Reusable patterns

- **Self-optimization loop**: analyze -> propose -> execute-both -> compare -> accept/reject. This is the general pattern for any program transformation that must preserve semantics.
- **Tautological oracle detection**: `⊢= x <- v` followed by `⊨ x = v` is always a tautology. This is the most common waste pattern in Cell programs and can be detected statically.
- **Until-oracle redundancy**: Spawner `until` clauses and `⊨` assertions on the same property are redundant. Keep the `until` (structural), drop the oracle.

### Quality rating

**Adequate**. Conceptually strong — a Cell program that optimizes other Cell programs. Finds real issues (tautological oracles, dead dependencies, redundant until/oracle). But the `compare` cell's crystallization is incorrect (soft judgment marked as hard), and the `⊢∘` parameter syntax is underspecified. The trace converges cleanly in 1 iteration with 4 valid optimizations.

---

## Program 28: program-algebra-prover

**Domain**: Prove equivalence of two Cell programs with different execution orders via confluence.

### Features exercised well

- **`⊢= ▸ crystallized`**: Seven crystallized cells (both programs' computation cells + `build-correspondence` + `verify-proof`). The computation cells are the subject; the verifiers are the prover. Cleanest demonstration of the crystallization spectrum.
- **`§`**: `§weighted-sum-A`, `§total-weight-A`, etc. as cell definitions passed to program-assembly cells.
- **`⊨`**: Rich oracles on correspondence (`matched-count + length(unmatched) = length(correspondence)`) and proof validity (5-way conjunction).
- **`⊨? on exhaustion`**: `partial-accept(best)` as graceful degradation.

### Awkward/broken

- **Lines 35-50, 82-96**: `program-A` and `program-B` are soft cells that take `§` references to crystallized cells and produce execution-order lists. But these cells exist primarily to annotate the ordering — they add ceremony without computation. The execution orders could be hard-coded as `⊢=` cells.
- **Lines 285-286**: `given weighted-average-A->average` and `given weighted-average-B->average` — the `equivalence-certificate` cell directly references the computation cells' outputs, creating a dependency on cells that are "inside" programs A and B. This breaks the abstraction boundary: the prover should only access outputs through the traces, not directly.
- **Lines 319-322**: Program-level `⊨? on failure` and `⊨? on exhaustion` outside any cell scope.

### Spec gaps exposed

1. **Abstraction boundaries**: When `§` is used to pass cell definitions into a program-assembly cell, should dependent cells be able to directly reference the original cell's outputs? Or should access be mediated through the assembly cell?
2. **Program-level recovery**: `⊨?` at file scope (not inside a cell) is used but not specified.
3. **Duplicate yield names**: `weighted-sum-A` and `weighted-sum-B` both yield `weighted-sum`. The spec does not address name collisions across cells with the same yield names.

### Reusable patterns

- **Confluence proof template**: (1) Dependency isomorphism (same graph shape), (2) Cell-wise equivalence (same `⊢=` bodies), (3) eval_diamond application (independent cells commute). This three-step proof works for any pair of programs differing only in evaluation order.
- **Correspondence table**: A crystallized cell that maps paired cells and checks value equality. General-purpose equivalence evidence.
- **Meta-level confluence**: The prover's own trace cells (trace-A, trace-B) are independent and could execute in either order — the prover exhibits the property it proves.

### Quality rating

**Adequate**. Theoretically important — makes Cell's confluence theorem concrete with actual numbers. But the program has structural issues: unnecessary soft cells for program assembly, broken abstraction boundaries on direct cell references, duplicate yield names. The 16-frame trace is thorough and the proof is well-structured.

---

## Program 29: bootstrapper

**Domain**: Zero-to-many cell spawning — start with nothing, meta-reason about what cells to create, iteratively fill gaps.

### Features exercised well

- **`⊢⊢`**: Two spawners: `spawn-specialists` (first wave, 5 domain cells from nothing) and `spawn-gap-fillers` (second wave, targeted gap cells). This is the purest form of Cell's self-bootstrapping property.
- **`⊢∘`**: `evolve(synthesize) through evaluate-completeness, spawn-gap-fillers, re-synthesize until quality-score >= 7 max 3`. Quality-driven convergence over an ensemble, not a single cell.
- **`⊨`**: Completeness oracles on `evaluate-completeness` (`is-complete in {true, false}`, `quality-score in 1..10`, `gaps are specific and addressable`). Actionable gap descriptions required.
- **`§`**: `§specialist-template` and `§gap-filler-template` as reusable cell templates for spawners.

### Awkward/broken

- **Lines 90-91**: `given specialist-*->findings` and `given specialist-*->recommendations` — the wildcard `*` notation for collecting outputs from dynamically named cells is not in the v0.1 spec. This appears in the source program being analyzed by program 27 as well (`answer-*->response`). It is a critical missing feature.
- **Line 203**: `⊢∘ evolve(synthesize, specialist-*->findings, specialist-*->recommendations, task->prompt)` — four parameters to the evolution combinator. The spec shows `⊢∘ evolve(greet, name = "Alice")` with one extra parameter. Multiple parameter passing is underspecified.
- **Line 242**: `⊨ polished-plan mentions ramen AND architecture in every time block` — "every time block" is vague. How many time blocks? The oracle's precision is low.
- **Lines 66-67**: `specialist-template` is defined as a regular `⊢` cell (line 66) but used as a template via `§specialist-template`. The spec does not explain how a cell definition serves as a template for spawner instantiation.

### Spec gaps exposed

1. **Wildcard cell references (`*`)**: `specialist-*->findings` is essential for programs that spawn dynamic numbers of cells. The spec needs to define wildcard/glob patterns for cell references.
2. **Template instantiation**: How does `⊢⊢` bind a template cell's `given purpose` and `given scope` with different values for each spawned instance? The spec's spawner section is thin on instantiation mechanics.
3. **`⊢∘` multi-parameter syntax**: Multiple bound values passed to the evolution combinator need formal grammar.
4. **Quality score oracle**: `quality-score in 1..10` uses range notation not defined in the spec.

### Reusable patterns

- **Zero-start bootstrap**: Start with no domain cells, meta-reason about what's needed, spawn specialists, evaluate completeness, spawn gap-fillers for what's missing. The two-wave pattern (broad then deep) is general.
- **Template polymorphism**: Same template shape (`given context -> yield findings + recommendations`), different bound purposes. This is Cell's version of parametric polymorphism.
- **Monotonic ensemble improvement**: Each `⊢∘` iteration spawns MORE cells, never removes them. The ensemble output is a superset of the previous iteration. Matches Cell's monotonicity guarantee.

### Quality rating

**Adequate**. The most ambitious bootstrapping demonstration in the batch. Starts from nothing and builds a complete Tokyo weekend itinerary through two waves of spawned cells. But the wildcard reference syntax (`specialist-*`), template instantiation mechanics, and multi-parameter `⊢∘` are all underspecified. The trace (61KB, largest in the batch) shows rich LLM-generated content with real Tokyo knowledge. The bootstrapping observations cell is insightful.

---

## Program 30: cell-spec-evolver

**Domain**: Cell evolves its own spec — write an awkward program, identify limitations, propose syntax changes, rewrite, evaluate.

### Features exercised well

- **`⊢∘`**: `evolve-spec(awkward-program) through identify-awkwardness, propose-spec-change, rewrite-program, evaluate-improvement until is-clean max 3`. Meta-level evolution of the spec itself.
- **`§`**: `§awkward-program` passes the program definition as data for analysis by `identify-awkwardness` and `rewrite-program`. Code-as-data for self-analysis.
- **`⊨`**: Well-designed oracles: `each severity in {1,2,3,4,5}`, `awkwardness-score = mean of all severities` (mathematical constraint), `code' does not contain 'N/A' hack patterns` (negative pattern matching).
- **`⊨?`**: Recovery on `evaluate-improvement` with specific retry context.
- **`⊢=`**: Observation cells (`obs-1` through `obs-5`) as standalone `⊢=` statements. Clean, but see issues below.

### Awkward/broken

- **Lines 255-277**: `obs-1` through `obs-5` use bare `⊢= obs-1 <- "..."` syntax without enclosing cell structure (no `yield`, no `given`). This is a shorthand not defined in v0.1. Earlier programs (26, 28) at least wrap observations in cells with `yield observation`.
- **Line 248**: `⊢∘ evolve-spec(awkward-program)` — the target is `awkward-program`, but the loop body rewrites `awkward-program->code`. The spec says `⊢∘` is a "parameterized fixed-point combinator over cell definitions," but here it evolves the program text content, not the cell definition itself.
- **Lines 33-110**: The `awkward-program` cell contains a complete nested Cell program as a string literal in `code`. While this is the right approach for meta-level analysis, the escaped quotes and nested `⊢` declarations make parsing ambiguous. Is the inner `⊢ classify` a real cell or string data?

### Spec gaps exposed

1. **Guard clauses / conditional dispatch**: This program IDENTIFIES the gap and PROPOSES a fix (guard clauses with `|`, variant cells, bottom propagation). The proposed v0.2 changes are well-designed and backward-compatible. This is the most actionable spec gap finding in the entire batch.
2. **Bare `⊢=` assignment**: `⊢= obs-1 <- "text"` without cell structure needs to be either blessed or rejected.
3. **Nested Cell programs as data**: Embedding Cell programs as string literals is fragile. A structured quotation mechanism (beyond `§`) for multi-cell programs would help.

### Reusable patterns

- **Self-referential awkwardness detection**: Write an intentionally awkward program, analyze it, propose fixes, rewrite, evaluate. The meta-loop is general: any language can evolve by identifying its own pain points.
- **Ironic self-demonstration**: The awkward program demonstrates the limitation it identifies. The evolver program itself would benefit from guard clauses. This recursive self-awareness is a powerful design validation technique.
- **Spec change proposal format**: Symbol + syntax + semantics + before/after + backward compatibility. This template structure should be standardized for all spec evolution proposals.

### Quality rating

**Exemplary**. The most strategically important program in the batch. It does not just exercise Cell — it evolves Cell. The guard clause proposal (with `|`, variant cells, and bottom propagation) is the strongest concrete output of R16. The trace converges in 1 iteration with awkwardness score dropping from 3.8 to 1.4. The five observation cells provide sharp meta-commentary. Minor syntax issues with bare `⊢=` assignments do not diminish the significance.

---

## Cross-Cutting Summary

### Spec gaps most urgently exposed

1. **Conditional dispatch / guard clauses** (P30): The N/A hack pattern appears in P30's specimen program and is identified as Cell's most painful limitation. The `|` guard proposal is ready for v0.2.
2. **Wildcard cell references** (P29, P22): `specialist-*->findings` is essential for spawner-based programs. No spec support.
3. **`⊢∘` substitution mechanics** (P21, P22, P24, P29): How does the evolution loop reconnect outputs from the `through` chain back to the target cell? Every program using `⊢∘` relies on implicit substitution.
4. **Crystallized expression language** (P23, P24, P25): `⊢=` cells use `collect()`, `concat()`, `contains()`, `missing-from()`, `has-loop-invariant()` — none defined. Need a standard library or expression grammar.
5. **Conditional oracle semantics** (P21, P22): `if X then Y` oracles need formal handling of the false-precondition case.

### Strongest patterns for reuse

1. **Multi-dimensional gauntlet** (P23): N independent oracles + crystallized aggregator + targeted rewrite + full re-check.
2. **Proof-carrying computation** (P24): LLM generates solution+proof, crystallized verifier checks proof structure.
3. **Recursive oracle refinement** (P25): Soft oracle -> decompose -> crystallize leaves.
4. **Zero-start bootstrap** (P29): Meta-reason about needed cells, spawn them, evaluate, spawn more.
5. **Back-translation verification** (P21): Round-trip fidelity check via translate->back-translate->diff.

### Quality distribution

| Program | Rating | Key strength |
|---------|--------|-------------|
| 21 | Exemplary | Cleanest `⊢∘` convergence, locality of repair |
| 22 | Exemplary | Best spawner use, real factual error detection |
| 23 | Exemplary | Definitive multi-oracle architecture |
| 24 | Exemplary | Cell's killer pattern made concrete |
| 25 | Exemplary | Most architecturally ambitious oracle decomposition |
| 26 | Adequate | Metacircular but syntactically rough |
| 27 | Adequate | Good optimization findings, broken crystallization |
| 28 | Adequate | Confluence proof, but structural ceremony |
| 29 | Adequate | Ambitious bootstrap, underspecified wildcards/templates |
| 30 | Exemplary | Strategically critical — evolves Cell itself |

Programs 21-25 and 30 are exemplary; programs 26-29 are adequate with specific fixable issues. No program is problematic. R16 represents a significant quality improvement over earlier rounds.
