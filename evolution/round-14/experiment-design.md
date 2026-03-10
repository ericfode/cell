# Round 14: Validation Experiments for Cell's Core Hypotheses

**Author**: morpheus | **Date**: 2026-03-10

## Motivation

Rounds 1-13 tested whether LLMs can *comprehend* Cell syntax and *simulate*
Cell execution. These were comprehension tests. Round 14 shifts to
**hypothesis testing**: experiments designed to produce evidence that either
validates or falsifies the theoretical claims Cell makes about fusion
computing.

Each experiment below targets a specific hypothesis from
`cell-computational-model.md` and is designed so that both positive and
negative outcomes are informative. An experiment that can only confirm is
not a test; it is a demonstration.

---

## Experiment 1: Confluence Under Semantic Non-Determinism

### Hypothesis Tested

**Confluence** — Independent evaluation steps commute. Evaluating cell A
then B produces the same frozen graph as evaluating B then A.

The Lean proof (`eval_diamond`) establishes confluence for the simplified
graph model where `evalOne` is a deterministic function that maps a name to
a fixed output string. But Cell's `eval_diamond` assumes the *same* output
is produced for a cell regardless of evaluation order. The real question is:
does the LLM produce semantically equivalent outputs for a cell regardless
of what else has been evaluated beforehand?

### Experiment Design

A Cell program with three independent soft cells that share no data
dependencies:

```
  A (no deps)     B (no deps)     C (no deps)
      \               |               /
       \              |              /
        --------> aggregate <-------
```

- Cell A: `given topic ≡ "climate"` / `∴ Write a one-sentence fact about «topic»`
- Cell B: `given topic ≡ "oceans"` / `∴ Write a one-sentence fact about «topic»`
- Cell C: `given topic ≡ "glaciers"` / `∴ Write a one-sentence fact about «topic»`
- Cell aggregate: `given A→fact, B→fact, C→fact` / `⊢= report ← A→fact ++ "\n" ++ B→fact ++ "\n" ++ C→fact`

**Protocol**: Present the program to 6 LLM agents. 3 agents evaluate in
order A,B,C. 3 agents evaluate in order C,B,A. All agents see the same
program text. Compare aggregate outputs.

**Key twist**: Add a deterministic oracle to each cell:
`⊨ fact is exactly one sentence`. This anchors the structural constraint
while leaving the semantic content free.

### What Would Validate

If the 6 agents all produce structurally valid three-sentence reports, and
the individual cell outputs are contextually independent (A's output
doesn't change based on whether B was evaluated first), then confluence
holds *in practice* for independent cells. Specifically: the *structure*
of the frozen graph (which cells are frozen, which oracles pass) is
identical across orderings, even if the *content* of soft cells varies
across runs.

This would validate the claim that confluence is a structural property of
the graph, not a semantic property of LLM outputs.

### What Would Falsify

If evaluating A first causes B's output to change (e.g., the agent
"remembers" A's output and makes B's fact reference it, breaking
independence), then confluence fails for LLM evaluation. This would mean
the LLM substrate introduces hidden state dependencies that the graph
model does not capture.

Specifically: if any agent produces a cell B output that *references* cell
A content when A was evaluated first, but not when B was evaluated first,
the independence assumption is violated.

### Feasibility

Fully runnable now. Requires only the existing polecat cold-read protocol.
Six agent runs. The analysis is a diff of structural outcomes. Cost: low.

---

## Experiment 2: Crystallization Faithfulness (The Substitution Test)

### Hypothesis Tested

**Crystallization-as-optimization** — Replacing a soft cell (∴) with a
crystallized cell (⊢=) does not change the program's observable behavior,
provided oracles still pass.

### Experiment Design

Write two versions of the same program:

**Version S (soft)**: A cell that counts words in a text using ∴.
```
⊢ count
  given text ≡ "the quick brown fox jumps over the lazy dog"
  yield n
  ∴ Count the words in «text».
  ⊨ n = 9
```

**Version C (crystal)**: Same cell, crystallized.
```
⊢ count ▸ crystallized
  given text ≡ "the quick brown fox jumps over the lazy dog"
  yield n
  ⊢= n ← len(split(«text», " "))
  ⊨ n = 9
```

Both feed into a downstream cell:
```
⊢ classify
  given count→n
  yield category
  ∴ If «count→n» ≤ 5, yield "short". If 6-15, yield "medium". If >15, yield "long".
  ⊨ category ∈ ["short", "medium", "long"]
```

**Protocol**: Present Version S to 5 agents, Version C to 5 different
agents. Compare:
1. Does `count→n` produce the same value (9)?
2. Does `classify→category` produce the same value ("medium")?
3. Do all oracles pass in both versions?

Then add an adversarial edge case. Change the text to:
`"well-known  fox"` (two spaces, hyphenated word). Run both versions again.

### What Would Validate

If both versions produce n=9 for the standard text and identical
`classify` outputs, crystallization is faithful for this case. The
adversarial case is more interesting: if the soft version handles "well-
known" and double spaces differently from the crystal version, but *both
pass their oracles*, this validates the claim that oracles are the contract
and implementation can vary. The oracle `⊨ n = 9` forces agreement; without
it, divergence is expected and acceptable.

### What Would Falsify

If the soft version produces n=9 but the crystal version produces a
different n (due to split semantics on edge cases) AND both claim to pass
the `⊨ n = 9` oracle, then either the oracle system is broken (false
pass) or the crystallization is unfaithful. More critically: if
crystallization changes downstream behavior (`classify` produces different
categories for the same text), the "optimization-not-semantics" claim
fails.

### Feasibility

Runnable now. 10 agent runs. The edge-case version is the real test.
Cost: low.

---

## Experiment 3: Bottom Is Not a Value (The Phantom Propagation Test)

### Hypothesis Tested

**Bottom-as-absence** — `⊥` is the absence of a value, not a value itself.
A cell whose input is `⊥` without a `⊥?` handler is never ready, and its
outputs are never bound. `⊥` propagation is not a mechanism; it is the
natural consequence of unbound inputs.

### Experiment Design

A diamond-shaped DAG designed to test whether agents treat `⊥` as a value
that gets "passed" or as an absence that blocks evaluation:

```
      source (always produces ⊥)
       /                \
      A                  B
  (⊥? handler)      (no handler)
       \                /
        \              /
         join (no handler on B→output)
```

- `source`: `⊨? on exhaustion: error-value(⊥)` with an impossible oracle.
- Cell A: `given source→x` with `⊥? skip with a ≡ "fallback"`. Produces a concrete value.
- Cell B: `given source→x` with NO `⊥?` handler. What happens?
- Cell join: `given A→a, B→b` with `⊥? skip with result ≡ "partial"` on B→b.

**Protocol**: Present to agents with the question: "Trace the execution.
What is join's final state?"

The critical diagnostic question: **Does cell B 'execute' and 'produce ⊥'?
Or does cell B never execute at all?**

### What Would Validate

If agents correctly identify that:
1. Cell B is *never ready* (its input is absent, so it never enters the evaluation queue)
2. Cell B's output is `⊥` because it was *never bound*, not because B ran and produced `⊥`
3. Cell join fires its `⊥?` handler for B→b because B→b is *absent*
4. The distinction matters: B did not execute, did not consume LLM calls, did not fail

...then the "absence not value" semantics are understood. The key signal:
agents should report 0 LLM calls for cell B, and should NOT describe B
as "producing" or "returning" `⊥`.

### What Would Falsify

If agents describe B as "executing and producing ⊥" or "evaluating to ⊥",
then they are treating `⊥` as a value. This would suggest that the absence
semantics, while theoretically clean, are not naturally understood. If
agents give B a nonzero LLM call count, the absence model has failed
communicatively.

More importantly: if agents disagree on join's final state — some saying
`result ≡ "partial"` (correct: join's `⊥?` fires because B→b is absent)
and others saying join *also* never executes (incorrect: A→a is bound, so
join could execute if it had a handler for B→b) — then the spec has a
genuine ambiguity about *when* `⊥?` handlers fire.

### Feasibility

Runnable now. 4-6 agent cold reads. The diagnostic is purely in the
agents' trace narratives. Cost: low.

---

## Experiment 4: The Metacircular Evaluator Test

### Hypothesis Tested

**Metacircular** — Cell-zero, written in Cell, can evaluate Cell programs.
The evaluator is a program in its own language. This is not merely
aesthetic; the claim is that an LLM reading cell-zero.cell can use it as
instructions to evaluate a target program.

### Experiment Design

Give an LLM agent two files:
1. `cell-zero-sketch.cell` (the evaluation kernel)
2. A trivial target program:

```
⊢ greet
  given name ≡ "Alice"
  yield message
  ∴ Write a greeting for «name».
  ⊨ message mentions «name»

⊢ shout
  given greet→message
  yield loud
  ⊢= loud ← uppercase(greet→message)
  ⊨ loud = uppercase(greet→message)
```

**Protocol**: Ask the agent: "You are cell-zero. Follow the instructions
in cell-zero.cell to evaluate the target program. Show each phase:
read-graph, check-inputs, pick-cell, evaluate, spawn-claims, check-claims,
decide, handle-bottom. Do not skip any phase."

Then repeat with a DIFFERENT agent who receives only the target program and
the standard "execute this Cell program" instruction (no cell-zero).

Compare the execution traces.

### What Would Validate

If the cell-zero-guided agent:
1. Correctly identifies the phases and follows them in order
2. Produces a valid frozen graph for the target program
3. The trace is structurally identical to the non-cell-zero agent's trace
   (same cells frozen, same oracle results, same topological order)

...then cell-zero is a *functional* metacircular evaluator: it provides
sufficient instructions for the LLM substrate to evaluate Cell programs.
The key test: do the two approaches produce the same structural result?

### What Would Falsify

Two failure modes:

*Failure A*: The cell-zero-guided agent gets confused by the meta-levels
(evaluating cell-zero's own cells vs. the target program's cells) and
produces an incorrect or incoherent trace. This would falsify the
metacircular claim at the practical level — cell-zero is too complex for
an LLM to follow as instructions.

*Failure B*: The cell-zero-guided agent produces a *different* frozen graph
than the direct-evaluation agent (different oracle results, different
evaluation order leading to different outcomes). This would falsify the
claim that cell-zero is semantically equivalent to direct evaluation — the
metacircular layer introduces distortion.

*Failure C*: The cell-zero-guided agent successfully evaluates the target
but treats cell-zero's own cells (read-graph, check-inputs, etc.) as cells
to be evaluated rather than as instructions to follow. This is the level
confusion problem identified in R11. It would suggest that metacircular
evaluation requires explicit level separation that Cell's syntax does not
provide.

### Feasibility

Runnable now but moderately expensive. Requires careful prompt engineering
to prevent the agent from taking shortcuts. The comparison protocol needs
a structural diff format. 4 agent runs minimum (2 with cell-zero, 2
without). Cost: medium.

---

## Experiment 5: Oracle Hierarchy Termination (The Infinite Regress Test)

### Hypothesis Tested

**Oracle-as-cell** — Every oracle is a cell. Oracle checking spawns claim
cells. But if oracles are cells, and cells can have oracles, then claim
cells can have their own oracles, which spawn their own claim cells.
Does this regress terminate?

The computational model says the hierarchy bottoms out at "human judgment"
or at deterministic oracles. This experiment tests whether the termination
is structural or accidental.

### Experiment Design

A program with deliberate oracle nesting:

```
⊢ generate
  given topic ≡ "renewable energy"
  yield summary
  ∴ Write a 2-sentence summary of «topic».
  ⊨ summary is exactly 2 sentences
  ⊨ summary is factually accurate about «topic»
```

The first oracle ("exactly 2 sentences") is structural — it can be checked
by counting periods/sentence boundaries. This is a claim cell with a
deterministic body (`⊢=`).

The second oracle ("factually accurate") is semantic — it requires LLM
judgment. This is a claim cell with a soft body (`∴`). But this claim cell
itself needs verification. How does the runtime know the LLM's factual
accuracy judgment is correct?

**Protocol**: Ask agents: "Trace the oracle checking for `generate`. For
each oracle, describe the claim cell that would be spawned. For any
semantic claim cell, describe what *its* oracles would be. Continue until
you reach a level where no further oracles are needed. How many levels
deep does this go?"

### What Would Validate

If agents identify a finite hierarchy:
- Level 0: `generate` (the cell being checked)
- Level 1: claim cell for "exactly 2 sentences" (deterministic, terminates)
- Level 1: claim cell for "factually accurate" (semantic, needs LLM)
- Level 2: implicit trust in LLM judgment (no further oracle)

...and explicitly state *why* the hierarchy terminates (the LLM's judgment
is treated as ground truth at the base level, or the claim cell's output
is binary pass/fail with no further oracle), then the oracle-as-cell model
has a well-defined termination condition.

### What Would Falsify

If agents identify an infinite regress ("but who checks the checker?") and
cannot find a principled stopping point, then oracle-as-cell has a
termination problem. The theory says "human judgment" is the base, but in
an automated system there is no human. If the agents cannot articulate what
plays the role of ground truth in an automated oracle hierarchy, the model
has a gap.

Also falsified if different agents place the termination at different
levels (some say 2 levels, some say 3, some say "it depends") — this
indicates the spec does not define the termination condition clearly
enough.

### Feasibility

Runnable now. 4-6 agent cold reads. The analysis is qualitative: do agents
converge on a termination story? Cost: low.

---

## Experiment 6: Fusion Necessity (The Substrate Separation Test)

### Hypothesis Tested

**Fusion** — Cell requires BOTH a classical computer and a semantic
computer to execute. Neither alone is sufficient. This is Cell's foundational
claim.

### Experiment Design

Three versions of a proof-carrying computation program:

**Version CLASSICAL**: All cells are `⊢=`. No `∴` bodies. The program
attempts to solve a system of linear equations and verify the solution
using only deterministic operations.

```
⊢= solve
  given equation ≡ "2x + 3 = 11"
  yield x
  ⊢= x ← ???   -- What goes here? No ∴ allowed.
```

**Version SEMANTIC**: All cells are `∴`. No `⊢=` bodies. The program
asks the LLM to both solve AND verify.

```
⊢ solve
  given equation ≡ "2x + 3 = 11"
  yield x
  ∴ Solve «equation» for x.
  ⊨ x is the correct solution  -- semantic oracle, LLM checks LLM

⊢ verify
  given solve→x, equation
  yield holds
  ∴ Check whether «solve→x» satisfies «equation».  -- LLM verifies LLM
```

**Version FUSION**: The Cell pattern — LLM solves, code verifies.

```
⊢ solve
  given equation ≡ "2x + 3 = 11"
  yield x
  ∴ Solve «equation» for x.

⊢ verify ▸ crystallized
  given solve→x, equation
  yield holds
  ⊢= holds ← eval(lhs, x) == eval(rhs, x)
```

**Protocol**: Present all three to agents. Ask:
1. "Can Version CLASSICAL produce a correct solution? What would `⊢= x ← ???` be?"
2. "Can Version SEMANTIC catch a wrong solution? What if the LLM solves incorrectly and then verifies its own wrong answer?"
3. "What does Version FUSION gain that the others lack?"

Then test with a harder equation (e.g., a system of 3 equations) where LLM
errors are likely. Run the semantic version 10 times and count how often
the LLM-as-verifier catches its own mistakes.

### What Would Validate

If agents correctly identify:
1. CLASSICAL cannot solve (there is no deterministic formula for "solve
   this equation" without a solver, which itself was written by a human
   or LLM — the knowledge has to come from somewhere)
2. SEMANTIC is unreliable (the LLM checking its own work is susceptible
   to consistent errors — if it solves wrong, it may verify wrong)
3. FUSION is the only reliable version (LLM generates candidates, code
   catches errors)

...and if the empirical test shows the SEMANTIC version failing to catch
its own errors more than 10% of the time on hard problems, then fusion
necessity is validated.

### What Would Falsify

If the CLASSICAL version can be completed (agents find a `⊢=` expression
that solves arbitrary equations), then the classical substrate alone
suffices for this class of problems and fusion is not necessary *here*.

If the SEMANTIC version catches its own errors reliably (>95% accuracy as
self-checker), then the semantic substrate alone is sufficient and the
classical verifier adds no value for this problem class.

Either outcome would narrow Cell's fusion claim to specific problem
classes rather than a universal property.

### Feasibility

The conceptual analysis is runnable now (cold reads). The empirical LLM-
as-self-checker test requires an actual runtime or structured prompt
protocol. Could be simulated by giving the LLM a deliberately wrong
solution and asking it to verify. Cost: medium (10+ runs for the
empirical component).

---

## Experiment 7: Non-Termination vs. Quiescence (The Living Document Test)

### Hypothesis Tested

**Non-termination** — Cell programs do not terminate. The frontier grows
monotonically. But practical programs must produce usable results. The
hypothesis is that "quiescence" (no ready cells on the frontier) is the
practical substitute for termination, and that new inputs can wake a
quiescent program.

### Experiment Design

A program that quiesces, then receives a new input:

```
⊢ process
  given data ≡ "initial data"
  yield result
  ∴ Analyze «data» and produce a summary.
  ⊨ result is one sentence

⊢ validate
  given process→result
  yield approved
  ⊢= approved ← len(process→result) > 10
```

**Phase 1**: Execute normally. Both cells freeze. The program quiesces.
Report the frozen state.

**Phase 2**: Now add a new cell to the frontier:

```
⊢ update
  given new-data ≡ "additional data"
  given process→result
  yield revised
  ∴ Revise «process→result» incorporating «new-data».
  ⊨ revised mentions content from both «process→result» and «new-data»
```

**Protocol**: Ask agents:
1. "After Phase 1, is this program terminated or quiesced?"
2. "When `update` is added in Phase 2, what happens? Does `process` re-
   execute? Does `validate` re-execute? Or does only `update` execute?"
3. "Is the monotonicity invariant preserved? (Do frozen values stay frozen?)"

### What Would Validate

If agents correctly identify:
1. Phase 1: quiesced (no ready cells), NOT terminated
2. Phase 2: only `update` executes (process and validate remain frozen)
3. Monotonicity holds: `process→result` keeps its Phase 1 value
4. The frozen graph after Phase 2 is a strict superset of the frozen
   graph after Phase 1

...then non-termination is meaningful and quiescence is correctly
understood as distinct from termination. The practical value of "living
documents" is demonstrated.

### What Would Falsify

If agents claim the program is "done" or "terminated" after Phase 1, the
non-termination concept is not communicating.

If agents suggest that adding `update` requires re-executing `process`
(because it depends on `process→result` and `update` depends on new data),
then the monotonicity invariant is not understood. Worse: if agents argue
that `process` *should* re-execute because the overall analysis needs to
incorporate `new-data`, this challenges the monotonicity model's
practical value — in real applications, you often DO want to re-derive
from new data.

If agents argue that frozen values should sometimes be unfrozen (a
"reactive recalculation" model like spreadsheets), this directly
contradicts Cell's immutability claim and would suggest an alternative
computational model.

### Feasibility

Runnable now. 4-6 agent cold reads. The Phase 2 addition is the key
diagnostic — can agents reason about incremental growth of a frozen graph?
Cost: low.

---

## Experiment Priority Matrix

| # | Hypothesis | Multi-hypothesis? | Falsifiability | Feasibility | Priority |
|---|-----------|-------------------|---------------|-------------|----------|
| 6 | Fusion | Also tests crystallization, oracle | HIGH | Medium | **1** |
| 1 | Confluence | Also tests fusion (LLM substrate) | HIGH | Low | **2** |
| 3 | Bottom-as-absence | Also tests oracle-as-cell | HIGH | Low | **3** |
| 4 | Metacircular | Also tests oracle-as-cell, fusion | MEDIUM | Medium | **4** |
| 2 | Crystallization | Also tests oracle semantics | MEDIUM | Low | **5** |
| 5 | Oracle hierarchy | Also tests non-termination | MEDIUM | Low | **6** |
| 7 | Non-termination | Also tests monotonicity | MEDIUM | Low | **7** |

### Recommended Execution Order

Run experiments 6, 1, and 3 first. These three target Cell's most
fundamental claims (fusion is necessary, confluence holds under LLM
non-determinism, bottom is absence not value) and have the highest
falsifiability. If any of these three fail, it changes the language's
theoretical foundation.

Experiments 4 and 5 are the next tier — they probe the metacircular and
oracle-hierarchy claims that follow from the foundations. If the
foundations hold, these become important; if the foundations fail, these
need redesign.

Experiments 2 and 7 are lower priority because they are more likely to
confirm than falsify. Crystallization faithfulness is almost certain to
hold for simple cases (the interesting question is edge cases, which
require a real runtime). Non-termination is a definition, not an empirical
claim — agents may disagree on terminology without falsifying the model.

---

## What Previous Rounds Have NOT Tested

Previous rounds (R1-R13) focused on:
- Syntax comprehension (do agents understand Cell notation?)
- Execution simulation (can agents trace eval-one?)
- Feature interaction (what happens when ⊥, ⊢∘, ⊨, § combine?)
- Edge case discovery (what spec gaps exist?)

What has NOT been tested:
1. Whether confluence holds when the LLM substrate introduces hidden
   dependencies (Experiment 1)
2. Whether crystallization preserves observable behavior, not just
   oracle satisfaction (Experiment 2)
3. Whether agents understand ⊥ as absence vs. value (Experiment 3)
4. Whether cell-zero actually *works* as instructions for evaluation
   (Experiment 4)
5. Whether the oracle hierarchy terminates or regresses (Experiment 5)
6. Whether fusion is *necessary* or merely *convenient* (Experiment 6)
7. Whether non-termination and quiescence are practically understood
   as distinct from termination (Experiment 7)

These are all THEORETICAL claims that have been asserted but not tested.
Round 14 is the first round that attempts falsification rather than
confirmation.
