# Cell Syntax Discovery — Design

**Date**: 2026-03-10
**Status**: Approved

## What Cell Is

Cell is the formula language for the LLM spreadsheet. Like Excel's formula
language operates on the spreadsheet substrate, Cell operates on the bead graph
— a DAG of tasks with inputs, outputs, and dependencies.

Cell is not a batch pipeline DSL. It is a self-bootstrapping metacircular
language where:

- Each cell execution produces beads on the graph frontier
- Cells can spawn new cells and rewire the graph within their scope
- Termination is not guaranteed — the graph evolves continuously
- cell-zero applies constant distillation pressure, crystallizing LLM cells into
  deterministic processes
- Interface contracts (inputs/outputs) freeze once set; implementations evolve

**The pretend test**: hand a Cell program to a raw LLM with no tooling. It
should be able to eval-one (execute the next ready cell) and produce correct
output. The act of token production IS execution. The LLM's "RAM" is the
accumulated task outputs; its "CPU" is token generation.

**Immutability constraint**: cells can only rewrite unexecuted beads, create new
beads, or add edges to already-executed cells. The past is frozen; only the
frontier is mutable.

## Problem

The current Cell syntax was designed for parseability, not LLM-native execution.
Markers like `##/`, `#/`, `format>`, and explicit wire declarations are
parser-oriented ceremony that may hinder the pretend test.

The syntax itself should be subject to distillation — discovered through the
same crystallization process that Cell programs undergo.

## Approach: Evolutionary Syntax Discovery

Start from LLM-native first principles. Ask LLMs to invent syntax for
computation graphs, test whether they can execute and distill what they invented,
evolve the best candidates through mutation and selection.

This is meta-circular: the syntax is found through Cell's own
generate → execute → distill → score → mutate loop.

## The Discovery Formula

A beads formula (since Cell syntax is what we're discovering) with 7 cells:

### Cells

1. **seed** (llm) — Generate N syntax variants
   - Input: description of a two-step program (greet + wrap)
   - Prompt: "Write this program in whatever notation feels most natural.
     Invent a format."
   - Output: N syntax candidates

2. **execute** (llm, map over candidates) — Pretend-test each variant
   - Input: one syntax candidate
   - Prompt: "Execute the next ready step. Show: which step, its inputs, its
     output."
   - Output: execution trace per candidate

3. **oracle-execute** (llm) — Score execution accuracy
   - Score 0-1: did the LLM identify the right cell, use correct inputs,
     produce valid output?

4. **distill** (llm, map over candidates) — Test crystallization
   - Input: syntax candidate + execution trace
   - Prompt: "Rewrite the first cell as a deterministic script. No LLM needed."
   - Output: distilled variant per candidate

5. **oracle-distill** (llm) — Score distillation quality
   - Score 0-1: does the distilled version preserve semantics?

6. **rank** (llm) — Combine scores, rank, propose mutations
   - Top 3 get mutation proposals (swap delimiters, change ref syntax, vary
     structure, combine features)

7. **report** (llm) — Summarize findings
   - Convergent patterns, highest-scoring features, next iteration focus

### Wires

```
seed → execute → oracle-execute → distill → oracle-distill → rank → report
```

### Test Case

A two-step program:
1. "greet": takes `name`, produces `{ message: str }`
2. "wrap": depends on greet, takes `greet.message`, produces
   `{ text: str, emoji: str }`

Small enough to test quickly. Has: inputs, dependencies, structured output, and
a distillable first step.

### Scoring

| Criterion | Weight | Measures |
|-----------|--------|----------|
| Execute accuracy | 50% | Correct cell identification, inputs, valid output |
| Distill quality | 30% | Deterministic replacement preserves semantics |
| Readability | 20% | Fresh LLM can explain what the program does |

No parsability criterion — Cell bootstraps its own parser through distillation.

### Iteration

1. Round 1: seed generates 5-10 variants from scratch
2. Score each on 3 criteria
3. Top 3 get mutated (3 mutations each = 9 new variants)
4. Round 2: test 9 mutants + 3 originals
5. Repeat until a variant scores >0.9 on all criteria or max iterations hit

Immutability applies: seed beads are frozen once produced. Mutations become new
seed beads. The graph grows forward.

## Outputs

- Ranked syntax candidates with scores
- Execution traces (proof LLMs can run them)
- Distillation attempts (proof LLMs can crystallize them)
- Mutation history (how syntax evolved)

## Next Steps

1. Take winning syntax
2. Write Cell spec update
3. Rewrite example files
4. Let cell-forge bootstrap a parser from new syntax
