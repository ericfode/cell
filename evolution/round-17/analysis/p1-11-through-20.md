# Round 16 Program Analysis: Programs 11-20

Analysis for R17 evolution cycle. Each program assessed on features exercised,
issues found, spec gaps exposed, reusable patterns, and quality.

---

## Program 11: fractal-task-planner

**Purpose**: Recursive decomposition of a goal into sub-goals, tasks, steps, and
atomic actions across 4 levels. Oracle validation at each level.

### Features exercised well

- **`⊢⊢` spawner**: Used at three levels (spawn-task-decomposers,
  spawn-step-decomposers, spawn-action-decomposers) to create fan-out from one
  level to the next. Spawner count is data-driven (bound to input list length).
- **`⊨` oracles**: Deterministic oracles (length bounds, `valid ∈ {true,false}`)
  and semantic oracles (MECE checks) at every level. The validate-level-N cells
  act as structural gates preventing garbage propagation.
- **`⊨?` recovery**: Each validate cell has `retry with oracle.failures max 2`,
  though the trace never triggered them.
- **`«»` interpolation**: Used consistently in `∴` blocks to splice parent values
  into child prompts.
- **`§` quotation**: Template cells (task-decomposer-template, etc.) passed via
  `§` to spawners.

### Awkward/broken

- **Lines 93-94**: `given task-decomposer-*→tasks` uses a wildcard glob pattern
  `*` that the spec does not define. The spec shows `→` for single cell output
  access but says nothing about collecting outputs from dynamically spawned sets
  of cells. This is the most-used undocumented feature across the fractal
  programs.
- **Lines 117, 165**: `until length(step-decomposer-cells) = total-task-count`
  references `total-task-count` which is never defined as a given or yield
  anywhere. It appears to be an implicit aggregation of all task counts across
  multiple spawned cells.
- **Lines 203-210**: `assemble-plan` takes 7 `given` inputs including four
  wildcard references. The cell signature is massive -- there is no mechanism to
  group or namespace these inputs.

### Spec gaps exposed

1. **Wildcard/glob cell references**: `task-decomposer-*→tasks` is used
   everywhere but has no spec support. Need syntax for "collect outputs from all
   cells matching a pattern."
2. **Implicit aggregation**: No way to express "sum of all X→hours" or "count of
   all X→items" without a dedicated cell. The spec needs a collect/reduce pattern.
3. **Template instantiation naming**: When `⊢⊢` spawns from `§template`, the
   resulting cells are named `template-1`, `template-2`, etc. The naming
   convention is assumed but not specified.
4. **Spawner `max` bounds**: The `max 60` on action-decomposers is a crucial
   halting mechanism, but the spec only mentions `max` in the context of `⊢∘`,
   not `⊢⊢`.

### Reusable patterns

- **Decompose-validate-spawn fractal**: The pattern of decompose (soft cell) ->
  validate (oracle gate) -> spawn (fan-out to next level) repeats identically at
  each level. This is a general-purpose recursive decomposition pattern.
- **Cross-cutting validation**: validate-level-2 reads from ALL task-decomposer
  cells simultaneously to check for inter-group issues that no individual cell
  can detect.
- **Hours as convergence metric**: Using estimated-hours summed across all leaves
  to validate top-level feasibility. Aggregate metrics computed bottom-up.

### Quality rating

**Exemplary** -- The most structurally ambitious program in the set.
Demonstrates fractal self-similarity, exponential fan-out under control, and
oracle gating at every level. The wildcard syntax gap is serious but the program
design is sound.

---

## Program 12: recursive-requirement-extractor

**Purpose**: Takes a vague request ("Build me a chat app"), extracts explicit and
implicit requirements, decomposes vague ones, and loops until all are concrete.

### Features exercised well

- **`⊢∘` evolution loop** (line 142): Evolves extract-implicit through
  collect-requirements and refine-vague until completeness >= 9. Clean use of
  convergence threshold on a semantic score.
- **`⊢⊢` spawner** (lines 78-83): Spawns one decomposer per vague requirement,
  with count driven by `assess-concreteness→vague` length.
- **`⊨` oracles**: Mix of deterministic (`length >= 3`, `∈ {true,false}`) and
  semantic (`each sub-requirement is more specific than the original`). The
  concreteness oracle bootstraps from vague judgment to concrete spec.
- **`«»` interpolation**: Effective use of negative interpolation -- `Do NOT
  include requirements already in «extract-explicit→requirements»` (line 53).

### Awkward/broken

- **Line 142**: `⊢∘ evolve(extract-implicit, request→text,
  extract-explicit→requirements)` -- the spec shows `⊢∘ evolve(cell-name)` with
  a simple target. Passing multiple fixed arguments to the evolution target is
  undocumented syntax. What are the second and third arguments? Fixed bindings
  for the evolved cell's inputs?
- **Lines 113-114**: `given decomposer-*→sub-requirements` and
  `decomposer-*→all-concrete` use the same undocumented wildcard pattern as P11.
- **Line 128-140**: `refine-vague` exists as a fallback for still-vague
  requirements after decomposition, but its relationship to the `⊢∘` loop is
  unclear. Is it part of the evolution `through` chain or a separate step?

### Spec gaps exposed

1. **`⊢∘` with fixed bindings**: The spec shows `⊢∘ evolve(cell, ...)` but does
   not document what the extra arguments mean. Are they frozen inputs for each
   iteration? This needs specification.
2. **Confidence-weighted requirements**: The program invents a
   certain/likely/possible classification that maps naturally to priority. The
   spec has no notion of confidence or soft priority on yields.
3. **Wildcard cell reference**: Same gap as P11.

### Reusable patterns

- **Explicit/implicit separation**: First extract what is literally stated, then
  what is implied. This two-phase extraction avoids contamination.
- **Concreteness oracle as recursion control**: The `all-concrete` flag on each
  decomposer controls whether that branch needs further recursion. Semantic
  judgment as recursion termination.
- **Confidence classification**: certain/likely/possible attached to implicit
  requirements enables natural MVP prioritization.

### Quality rating

**Exemplary** -- Elegant use of `⊢∘` + `⊢⊢` together. The program transforms 5
words into 32 testable requirements through oracle-driven decomposition. The
`⊢∘` argument syntax is non-standard but the overall design is excellent.

---

## Program 13: progressive-summarization

**Purpose**: Halves a document repeatedly. Oracle checks fidelity at each level.
When fidelity drops below threshold, `⊥` stops the recursion.

### Features exercised well

- **`⊥` as stop signal** (frame trace line 351): `yield next-summary = ⊥` is
  used correctly as a semantic signal that further compression is meaningless,
  not as an error. This is the cleanest demonstration of `⊥` in the set.
- **`⊢⊢` spawner for recursion** (lines 93-104): `recurse-compression` spawns
  new summarize/check/compress chains for each level. Recursion via frontier
  growth rather than `⊢∘`.
- **`⊢=` hard cell** (lines 12-40): The document cell uses `⊢=` for both text
  and word-count. Mixed hard bindings within a single cell.
- **`⊨` oracle with semantic fidelity**: The check-fidelity oracle distinguishes
  "acceptable loss" from "critical concept lost" -- a judgment no word count can
  make.

### Awkward/broken

- **Lines 85-86**: `⊨ actual-word-count <= target-ratio * 347 * 1.1` hardcodes
  347 (the document's word count). Should reference `document→word-count`
  instead. This creates a coupling between oracle and literal value.
- **Line 75**: `given target-ratio ≡ 0.50` in compress-further -- this is a
  literal default, not piped from a previous cell. Each compression level should
  arguably receive a halved ratio, but the ratio stays fixed at 0.50.
- **Lines 93-104**: The `⊢⊢ recurse-compression` spawner reads from
  compress-further but also has `given document→text` -- it always compares back
  to the original. The spawner has a complex given signature mixing spawn-level
  and root-level data.

### Spec gaps exposed

1. **`⊥` propagation semantics**: The spec says `⊥` is produced on oracle
   exhaustion but doesn't specify how downstream cells handle `⊥` inputs. Here,
   `⊢⊢` checks `halted = true` separately rather than propagating `⊥` through
   the dataflow.
2. **Recursive spawner chaining**: `⊢⊢` spawning new instances of a
   {summarize, check, compress} chain is a powerful pattern but the spec doesn't
   describe how spawned chains connect to the parent graph. How do spawned cells
   reference parent-level cells (like `document→text`)?
3. **No `⊢∘` used**: This program achieves iterative deepening without `⊢∘`,
   using `⊢⊢` recursion instead. This shows `⊢⊢` and `⊢∘` have overlapping
   expressive power for iteration.

### Reusable patterns

- **`⊥` as natural termination**: Using `⊥` to signal "this question has no
  answer" rather than as an error. The spawner checks a boolean flag rather than
  propagating `⊥` directly.
- **Fidelity cliff detection**: Compression fidelity drops in phases (8 -> 5 ->
  3), revealing a phase transition where summaries shift from "compressed
  description" to "tagline." The oracle catches the cliff.
- **Always compare to original**: check-fidelity always compares against the
  original document, not the previous level's summary. Prevents drift
  accumulation.

### Quality rating

**Exemplary** -- Best demonstration of `⊥` semantics in the entire set. The
fidelity oracle catching the phase transition between "compressed" and "tagline"
is a genuinely interesting finding. The hardcoded 347 is a minor blemish.

---

## Program 14: dependency-graph-builder

**Purpose**: Analyzes a codebase (Gas Town) to build a two-level dependency
graph. Identifies modules, analyzes dependencies, validates acyclicity, decomposes
into sub-modules.

### Features exercised well

- **`⊢⊢` spawner** (two levels): spawn-dependency-analyzers (6 cells, one per
  module) and spawn-sub-module-analyzers (6 cells, one per module's internals).
  Same pattern at both levels.
- **`⊨` structural oracle**: validate-acyclicity implements topological sort via
  Kahn's algorithm as an LLM-evaluated oracle. The trace correctly finds the
  mayor<->witness cycle.
- **`⊨?` recovery** (line 96-97): retry with oracle.failures on
  validate-acyclicity.
- **`«»` interpolation**: Effective use in templates: `«module-name»
  («module-desc»)`.

### Awkward/broken

- **Lines 65, 99-104**: `given analyzer-*→depends-on` and
  `given sub-analyzer-*→sub-modules` use the undocumented wildcard pattern.
- **Line 80-81**: validate-acyclicity and spawn-sub-module-analyzers are both
  ready after build-adjacency (they share the same inputs). The trace executes
  them sequentially, but the program doesn't express whether they should be
  parallel or ordered. The sub-module analyzers don't depend on acyclicity
  results.
- **The dependency-analyzer-template** (lines 46-62) receives `given
  all-modules[]` but this is never bound by the spawner. The spawner binds
  `module-name` and `module-desc` per instance but `all-modules` needs to come
  from somewhere else. Template input binding conventions are underspecified.

### Spec gaps exposed

1. **Template input binding**: When `⊢⊢` spawns from a template, which inputs
   are per-instance (varying) and which are shared (same for all)? The spec
   doesn't distinguish these. `all-modules` should be shared across all analyzer
   instances.
2. **Cycle handling**: The program correctly identifies a cycle but has no
   mechanism to act on it. The spec's oracle system reports pass/fail but doesn't
   provide structured cycle-breaking actions.
3. **Two cells ready simultaneously**: validate-acyclicity and
   spawn-sub-module-analyzers can both proceed after build-adjacency. The program
   implicitly relies on confluence but doesn't express a preference.

### Reusable patterns

- **Two-level recursive graph construction**: Module-level analysis -> sub-module
  analysis using the same spawn-analyze-collect pattern at both levels.
- **Internal/external classification**: Each analyzer classifies its own
  dependencies, letting the collector separate internal edges from external ports.
- **Real architectural discovery**: The mayor<->witness cycle is a genuine
  finding. The oracle doesn't paper over the defect.

### Quality rating

**Exemplary** -- Produces a genuine architectural finding (the SCC between mayor
and witness). The two-level spawn pattern is clean. Template binding gap is the
main spec issue.

---

## Program 15: recursive-explanation

**Purpose**: Explains a concept, identifies hard terms, recursively explains them
until a "10-year-old comprehension" oracle passes.

### Features exercised well

- **`⊢∘` evolution loop** (line 120): Evolves explain through
  collect-explanations and deepen until leaf-score >= 9.
- **`⊢⊢` spawner** (lines 54-59): Spawns one explainer per hard term. Count
  driven by semantic assessment.
- **`⊨` comprehension oracle**: The assess-comprehension cell applies a
  "10-year-old test" to each jargon term. Semantic judgment as recursion control.
- **`§` quotation**: `§sub-explain-template` passed to spawner.

### Awkward/broken

- **Line 120**: `⊢∘ evolve(explain, concept→text)` passes concept→text as a
  fixed binding -- same undocumented syntax as P12.
- **Lines 87-88**: `given explainer-*→explanation` and
  `explainer-*→still-hard` use the wildcard pattern.
- **Line 46**: `"DAG (directed acyclic graph)"` appears in jargon-terms but is
  flagged as "not actually used in the explanation, listed in error" in the frame
  trace. The LLM's jargon extraction included a false positive, which the
  assess-comprehension cell handled gracefully by marking it "clear."
- **The `deepen` cell** (lines 107-118) exists but was never reached in the
  trace because `leaf-score = 10` converged in one iteration. Its relationship
  to the `⊢∘` loop is unclear -- is it the `through` mechanism or a separate
  fallback?

### Spec gaps exposed

1. **`⊢∘` with fixed bindings**: Same gap as P12.
2. **Recursion depth transparency**: The program has max 3 on `⊢∘` and max 5 on
   `⊢⊢`, but there is no way to query current recursion depth from within a
   cell. A depth counter would help cells adjust behavior.
3. **Wildcard cell reference**: Same gap as P11-P14.

### Reusable patterns

- **Comprehension oracle as recursion control**: `still-hard = true/false` on
  each sub-explanation naturally controls whether that branch deepens. Semantic
  judgment terminates branches independently.
- **Analogy as leaf explanation**: Every successful leaf used an analogy (glass
  of water, board game, whiteboard). Analogies are the "crystallized form" of
  explanations.
- **Self-demonstrating program**: The Cell program about confluence IS confluent
  (explainer cells are independent).

### Quality rating

**Adequate** -- Clean design but the trace converges too easily (one iteration,
no recursion exercised). The deepen cell and the `⊢∘` retry path were never
tested. A harder concept would stress the design better.

---

## Program 16: evolution-simulator

**Purpose**: Genetic algorithm for logo concepts. Population of 6, tournament
selection, crossover, mutation, fitness oracle, convergence via `⊢∘`.

### Features exercised well

- **`⊢∘` as genetic algorithm** (lines 86-89): `evolve(seed-population) through
  evaluate-fitness, select-and-crossover, judge-generation until converged`. This
  is the cleanest demonstration that `⊢∘` generalizes to GAs without special
  syntax.
- **`⊢=` hard cells** (lines 12-14): `brief` uses multiple `⊢=` bindings for
  name, style-direction, and constraints.
- **`⊨` fitness oracle**: Weighted scoring (brand 40%, memorability 25%,
  scalability 20%, constraints 15%) with both deterministic checks (count,
  permutation) and semantic judgment (brand fit).

### Awkward/broken

- **Line 86**: `⊢∘ evolve(seed-population)` evolves the population cell, but the
  through-chain (evaluate-fitness, select-and-crossover, judge-generation) reads
  from MULTIPLE cells including brief→style-direction. The spec doesn't clarify
  how `⊢∘` manages cells outside the target that need to participate in each
  iteration.
- **Lines 67-68**: `⊨ top 3 candidates are recognizable descendants of their
  parents` is a semantic oracle that is extremely difficult to verify even for an
  LLM. "Recognizable descendants" is subjective.
- **No `⊢⊢` spawner**: The population is fixed at 6 throughout. No frontier
  growth -- the GA works by replacing candidates, not spawning new cells. This is
  a valid design but means the program doesn't exercise `⊢⊢`.
- **Dual convergence without `⊥`**: Convergence checks both quality threshold
  (mean >= 8) and stagnation (mean <= previous). Stagnation stops the loop but
  doesn't produce `⊥`. The program treats "no improvement" and "good enough" as
  the same outcome.

### Spec gaps exposed

1. **`⊢∘` with multi-cell through-chains**: The through-chain includes three
   cells that read from each other AND from cells outside the chain (brief). The
   spec says `through` lists cells, but doesn't describe how external
   dependencies are managed across iterations.
2. **In-place replacement semantics**: select-and-crossover produces
   `next-candidates` which conceptually replaces `seed-population→candidates`
   for the next iteration. The spec says `⊢∘` rewrites the target cell's output,
   but the actual data flow involves multiple cells producing/consuming the
   population.
3. **No stagnation vs quality distinction**: The converged flag conflates two
   different termination conditions. The spec's `⊨?` has different exhaustion
   handlers but `⊢∘` only has `until` with a single boolean.

### Reusable patterns

- **`⊢∘` as GA loop**: evaluate -> select+crossover -> judge maps directly to
  the genetic algorithm loop. No GA-specific syntax needed.
- **Dual convergence criteria**: Quality threshold OR stagnation detection. Both
  are valid reasons to stop but carry different confidence.
- **Emergent solutions via crossover**: The winning design didn't exist in the
  seed population. It emerged from recombination -- the process discovers what no
  individual design step could.

### Quality rating

**Adequate** -- Demonstrates `⊢∘` as a GA cleanly, but the program is
structurally simple (no `⊢⊢`, no `⊥`, no `§` beyond brief). The fitness oracle
subjectivity is a concern.

---

## Program 17: collaborative-world-builder

**Purpose**: Three parallel creators (geography, history, culture) generate
content for a space station. Consistency oracle checks for contradictions. `⊢∘`
loop fixes them.

### Features exercised well

- **`⊢∘` convergence loop** (lines 116-119): Evolves geography through
  check-consistency and resolve-contradictions until consistent.
- **`§` quotation** (lines 103-105): `given §geography, §history, §culture`
  passed to resolve-contradictions so it can determine WHICH cell to rewrite.
  This is code-as-data for resolution planning.
- **`⊨` consistency oracle**: Cross-references outputs from three independent
  cells to find contradictions (sector count vs governance, timeline arithmetic,
  physical distances). Catches real bugs.

### Awkward/broken

- **Lines 19-23, 37-40, 55-58**: geography, history, and culture have CIRCULAR
  dependencies (each references the others' outputs). The spec says eval-one uses
  Kahn's algorithm which CANNOT resolve cycles. The frame trace resolves this by
  treating cross-references as "optional context" and running cells with partial
  inputs on the first pass. This is a fundamental departure from the spec's
  execution model.
- **Line 116**: `⊢∘ evolve(geography, seed→premise ≡ seed→premise)` has odd
  syntax with `≡` in the argument. This seems to mean "fix seed→premise to its
  current value across iterations." Not documented.
- **Lines 100-105**: resolve-contradictions receives `§geography, §history,
  §culture` but its `∴` block determines which cell to rewrite. The mechanism
  for actually TRIGGERING the rewrite is not expressed -- it just outputs
  `cells-to-rewrite[]` as data, and the `⊢∘` loop presumably acts on this.

### Spec gaps exposed

1. **Circular dependencies in soft cells**: The spec says eval-one follows
   Kahn's algorithm, which deadlocks on cycles. But soft cells (`∴`) can
   operate with partial inputs. Need spec language for "optional given" or
   "soft dependency" that allows execution with unbound inputs.
2. **`⊢∘` targeting rewrites to specific cells**: The resolution plan says
   "rewrite culture and history" but `⊢∘ evolve(geography, ...)` targets
   geography. How does the loop know to rewrite OTHER cells? The spec needs
   multi-cell evolution semantics.
3. **`⊢∘` with `≡` fixed-binding syntax**: Undocumented.
4. **Asymmetric rewrite**: Geography was unchanged, history and culture rewrote.
   The spec doesn't describe how `⊢∘` handles selective rewriting within a group
   of interdependent cells.

### Reusable patterns

- **Parallel-then-validate**: Independent creators generate content in parallel,
  then a global oracle checks cross-consistency. Fix contradictions, repeat.
- **Constraint strength ordering**: Physics > history > culture. The cell with
  the "harder" constraint keeps its output; softer cells yield.
- **Two-phase bootstrap for circular deps**: Generate independently (first pass),
  refine with cross-context (second pass).

### Quality rating

**Adequate** -- The creative output is rich and the consistency oracle catches
real bugs. But the circular dependency handling contradicts the spec's execution
model, making this program technically invalid under the current spec. The
pattern is valuable but needs spec support.

---

## Program 18: recursive-story-builder

**Purpose**: Three-level narrative: outline -> scenes (via `⊢⊢`) -> beats (via
`⊢⊢`). Bottom-up assembly, consistency check, `⊢∘` revision.

### Features exercised well

- **Multi-level `⊢⊢`** (lines 40-48, 81-88): Two spawner levels -- scenes from
  outline, beats from scenes. This is the deepest spawner nesting in the set.
- **`⊢∘` revision loop** (lines 178-181): Evolves assemble-story through
  check-consistency and revise until consistency >= 8.
- **`⊨` consistency oracle**: check-consistency examines the assembled story
  against the original outline, checking protagonist consistency, act fulfillment,
  theme emergence, and plot holes.
- **`«»` interpolation**: Used throughout templates to pass context: act-summary,
  protagonist, scene-number, etc.

### Awkward/broken

- **Lines 82-83**: `given scene-*→scene-text` and `scene-*→emotional-arc` use
  the wildcard pattern. Additionally, `length(scene-cells) × 2` in the `until`
  clause references `scene-cells` which is the OUTPUT of the previous spawner,
  not a direct input to this one.
- **Lines 87-88**: `until length(beat-cells) >= length(scene-cells) * 2` -- the
  `until` condition references a value from another cell's output
  (`scene-cells`). The spec shows `until` with direct comparison, not
  cross-references.
- **Line 178**: `⊢∘ evolve(assemble-story, assemble-scenes→assembled-scenes,
  outline→theme, outline→protagonist)` passes 3 fixed bindings. Same
  undocumented syntax as P12, P15.
- **Lines 115-126**: `assemble-scenes` needs to know which beats belong to which
  scene, but all beat outputs are collected via `beat-*→beat-text` without scene
  grouping. The mapping of beats to their parent scenes is implicit.

### Spec gaps exposed

1. **Spawner output grouping**: When `⊢⊢` spawns beats for scenes, the beats
   need to be associated with their parent scene. No spec mechanism for
   hierarchical grouping of spawned cells.
2. **`until` referencing external cells**: The spawner's `until` condition
   references `scene-cells` from a different spawner's output.
3. **Bottom-up assembly**: The program assumes a collect-all-then-assemble
   pattern, but the spec doesn't describe how assembly cells know the ordering
   of spawned cells.
4. **`⊢∘` with multiple fixed bindings**: Same gap as P12, P15.

### Reusable patterns

- **Multi-level spawn hierarchy**: outline -> scenes -> beats mirrors natural
  compositional structure. Each level uses a template with context from the level
  above.
- **Bottom-up assembly**: Beats assemble into scenes, scenes into story. Local
  coherence at each level; global coherence checked once at the top.
- **Beat-type classification**: action/dialogue/internal/description/revelation
  creates a structural fingerprint for rhythm analysis.

### Quality rating

**Adequate** -- The multi-level spawner is impressive and the story output is
compelling (the Kael narrative is genuinely well-crafted). But the consistency
threshold of 8 means the `⊢∘` loop converged without ever triggering `revise`,
leaving the revision path untested. The wildcard grouping problem is real.

---

## Program 19: code-generator-with-proof

**Purpose**: Generate binary search code, property tests, verify via simulated
execution, generate proof sketch, verify proof with crystallized checker. Full
proof-carrying computation.

### Features exercised well

- **`⊢=` crystallized verifier** (lines 162-189): `verify-proof ▸ crystallized`
  uses `⊢=` for structural proof checking. The verifier runs WITHOUT an LLM.
  This is the purest demonstration of the P/NP separation pattern.
- **`⊢∘` evolution loop** (lines 124-127): Evolves generate-code through
  run-tests, analyze-failures, rewrite-code until fail-count = 0. TDD cycle as
  a `⊢∘` loop.
- **`§` quotation** (lines 26, 108, 120): `§implementation` and
  `§implementation'` used to pass code as data. The interface freeze constraint
  is explicitly stated.
- **`⊨` layered assurance**: Three layers -- empirical tests (12 cases),
  deductive proof (7 steps), meta-verification (crystallized checker).
- **`⊨?` with exhaustion** (lines 223-226): `⊨? on exhaustion:
  partial-accept(best)` -- one of the few programs that uses the exhaustion
  handler.

### Awkward/broken

- **Lines 169-185**: The `⊢=` expressions in verify-proof use function-call
  syntax (`has-loop-invariant()`, `invariant-references()`, `missing-from()`)
  that looks like a programming language embedded in Cell. The spec doesn't
  define what expressions are valid inside `⊢=`. These functions are not
  primitive -- they would need to be defined elsewhere.
- **Lines 223-226**: `⊨? on failure:` and `⊨? on exhaustion:` appear at the
  END of the file, at module level rather than inside a cell. They seem to be
  global recovery policies, but the spec shows `⊨?` inside cell declarations.
- **Line 120**: `⊨ §implementation' has same given/yield signature as
  §generate-code` -- this oracle assertion references the § quotation of ANOTHER
  cell, not the current cell. Cross-cell quotation comparison.
- **Run-tests is simulated** (line 72): The `∴` block says "Simulate executing"
  the code. In a real runtime, run-tests should be a `⊢=` cell that actually
  executes the code. The simulation makes the test results unreliable.

### Spec gaps exposed

1. **`⊢=` expression language**: What can go inside a `⊢=` block? The spec
   shows simple expressions but this program uses multi-line boolean logic with
   function calls. Need a defined expression sublanguage.
2. **Code execution cells**: The spec has no mechanism for a cell to actually
   run code (as opposed to an LLM simulating execution). Need a `⊢!` or similar
   for side-effectful execution.
3. **Module-level `⊨?`**: The spec shows `⊨?` inside cells. Orphaned `⊨?` at
   file scope is not addressed.
4. **Cross-cell `§` comparison**: `§implementation' has same signature as
   §generate-code` requires comparing quotations of different cells. The spec
   doesn't describe cross-cell quotation operations.

### Reusable patterns

- **Proof-carrying computation**: LLM generates (NP) -> crystallized verifier
  checks (P). Neither trusts the other. Adversarial separation.
- **`⊢∘` as TDD cycle**: generate -> test -> analyze -> fix maps directly to
  red/green/refactor.
- **Layered assurance**: Tests (empirical) + proof (deductive) + verification
  (meta). Each catches different failure modes.
- **Crystallization boundary = complexity boundary**: `verify-proof` is
  crystallized because checking is P. `generate-code` and
  `generate-proof-sketch` stay soft because generating is NP.

### Quality rating

**Exemplary** -- The defining program for proof-carrying computation in Cell.
The crystallized verifier is the cleanest `⊢=` usage in the set. The `⊢=`
expression language gap and simulated execution are real issues, but the design
pattern is Cell's killer app.

---

## Program 20: language-designer

**Purpose**: Design a mini-DSL for cooking recipes. Draft grammar, write 3
examples, critique for awkwardness, redesign. `⊢∘` loop until clean.

### Features exercised well

- **`⊢∘` as design iteration** (lines 136-139): `refine(draft-dsl) through
  write-examples, critique, redesign until is-clean`. The evolution loop
  directly models the human DSL design process.
- **`§` quotation** (line 47): `given §draft-dsl` passes the DSL definition as
  data to the example writer, so it can see both the grammar AND the cell that
  produced it.
- **`⊨` multi-criteria oracle**: critique uses 5 categories (verbosity,
  ambiguity, readability, completeness, consistency) with severity scoring. The
  convergence criterion combines mean score AND max severity.
- **`⊢=` hard cells** (lines 13-14): domain uses `⊢=` for name and
  requirements array.
- **`⊨?` recovery** (lines 132-134): retry with awkward-parts context.

### Awkward/broken

- **Line 130**: `⊨ §redesign has same given/yield signature as «§draft-dsl»` --
  this mixes `§` quotation inside `«»` interpolation. `«§draft-dsl»` is unclear:
  is it the interpolated value of the quotation (the definition as a string), or
  the quotation itself as a value? The spec shows `§name` for quotation and
  `«name→output»` for value interpolation, but not `«§name»`.
- **Line 136**: `⊢∘ refine(draft-dsl)` uses the name `refine` instead of
  `evolve`. The spec shows `⊢∘ evolve(...)`. Is the name after `⊢∘` arbitrary
  or must it be `evolve`?
- **Lines 108-134**: redesign takes `draft-dsl→grammar` and `draft-dsl→explanation`
  separately but outputs `grammar'` and `explanation'`. The prime notation (')
  for evolved versions is used extensively. The spec mentions prime marks for
  versioning but notes "§greet''' doesn't scale."

### Spec gaps exposed

1. **`«§name»` syntax**: Interpolation of quotation is used but not defined in
   the spec. The spec lists `§name` and `«name→output»` separately.
2. **`⊢∘` combinator naming**: Is the name after `⊢∘` (`evolve`, `refine`)
   significant or arbitrary? The spec always shows `evolve`. If arbitrary, it's
   a naming convention issue. If fixed, `refine` is non-standard.
3. **Prime notation scaling**: The program uses `grammar'`, `explanation'`,
   `§implementation'`. The spec acknowledges this doesn't scale. Need versioning
   syntax beyond prime marks.
4. **Multi-output evolution**: `⊢∘` evolves `draft-dsl` but the redesign cell
   produces TWO outputs (grammar' and explanation'). How does `⊢∘` replace a
   cell with multiple yields?

### Reusable patterns

- **Critique-redesign cycle**: Write examples -> critique for usability -> fix
  grammar -> repeat. This is the standard DSL design loop formalized.
- **Example-driven validation**: Testing a grammar by writing examples in it
  and checking for awkwardness. The examples ARE the test suite.
- **Conservative patching**: redesign changes only what critique flagged.
  Preserves working constructs. This "minimum intervention" principle prevents
  oscillation.
- **Convergence via dual criteria**: mean severity <= 1.5 AND no single issue
  >= 4. Prevents "mostly clean with one disaster."

### Quality rating

**Exemplary** -- The `⊢∘` loop converges from 6 issues (mean 2.7, max 4) to
3 issues (mean 1.3, max 2) in two iterations. The "choose" block emerging from
the critique is a genuine DSL improvement. The frame trace shows the full
design iteration process. Minor spec syntax issues (`«§»`, `refine` vs
`evolve`) are the main concerns.

---

## Cross-program Summary

### Most critical spec gaps (by frequency across P11-P20)

| Gap | Programs affected |
|-----|-------------------|
| Wildcard cell references (`cell-*→output`) | P11, P12, P13, P14, P15, P18 |
| `⊢∘` fixed-binding argument syntax | P12, P15, P17, P18 |
| `⊢=` expression sublanguage | P19 |
| Circular/optional dependency handling | P17 |
| Template input binding (shared vs per-instance) | P11, P14 |
| Spawner output grouping/hierarchy | P18 |
| `⊢∘` combinator naming | P20 |
| `⊥` propagation semantics | P13 |
| `«§name»` quotation interpolation | P20 |
| Module-level `⊨?` | P19 |

### Best patterns for R17 adoption

1. **Decompose-validate-spawn fractal** (P11): Repeatable recursive structure
2. **`⊥` as natural termination** (P13): Bottom means "no answer," not "error"
3. **Proof-carrying computation** (P19): LLM generates, crystallized verifier checks
4. **Critique-redesign cycle** (P20): Example-driven iterative improvement
5. **Cross-cutting validation** (P11, P14, P17): Global oracle catches what local cells cannot

### Quality distribution

- **Exemplary**: P11 (fractal-task-planner), P12 (requirement-extractor), P13 (progressive-summarization), P14 (dependency-graph-builder), P19 (code-generator-with-proof), P20 (language-designer)
- **Adequate**: P15 (recursive-explanation), P16 (evolution-simulator), P17 (collaborative-world-builder), P18 (recursive-story-builder)
