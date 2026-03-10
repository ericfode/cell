# Round 4: Verifiable Oracles

## Goal

Find Cell programs where oracles can be checked MECHANICALLY —
not just by LLM judgment. This is the seed of crystallization:
oracles that can be replaced by deterministic code.

## Test programs

### T1: Arithmetic (fully deterministic oracle)
Compute fibonacci. Oracle checks exact numeric equality.
Can a Cell express computation that crystallizes completely?

### T2: Round-trip factoring (compositional oracle)
Factor a cell, run both original and factored version.
Oracle: outputs must match. This is a REAL oracle —
it doesn't require understanding, just equality.

### T3: Sort verification (structural oracle)
Sort a list. Oracle checks:
- Output is sorted (each element ≤ next)
- Output is a permutation of input (same elements)
Both are mechanically checkable.

### T4: Self-description (metacircular oracle)
A cell describes its own structure. Oracle checks the
description against the actual cell definition.
This tests the § quoting mechanism under oracle pressure.

## Scoring
- Can an LLM execute it correctly? (pretend test)
- Are the oracles unambiguous enough to be code?
- Does the program feel natural in Cell syntax?
- Does the oracle naturally suggest its own implementation?
