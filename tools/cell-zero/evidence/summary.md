# Cell-via-Beads Evidence Summary

Date: 2026-03-12

## Pipeline

1. Parse `.cell` file via `parse.py`
2. Load cells into beads via `cell-to-beads.py` (one bead per cell, dependencies tracked)
3. Run eval loop via `beads-eval-loop.py` (find-ready, dispatch, oracle-check, decide)
4. Verify QUIESCENT output with correct oracle checks

## Programs Run

### 1. add-double.cell (2 cells, pure hard)
- **Result**: QUIESCENT after 2 steps
- **Cells**: add (sum=8), double (result=16)
- **Oracles**: 2/2 pass (deterministic)
- **Status**: ALL CELLS FROZEN

### 2. abs-value.cell (3 cells, guards + bottom propagation)
- **Result**: QUIESCENT after 2 steps
- **Cells**: check-sign (sign="negative"), negate (result=7), pass-through (bottom)
- **Oracles**: 2/2 pass (deterministic), 1 guard-skipped to bottom
- **Status**: All cells resolved (2 frozen, 1 bottom)
- **Tests**: guard dispatch, bottom propagation, conditional branching

### 3. chain-four.cell (4 cells, linear dependency chain)
- **Result**: QUIESCENT after 4 steps
- **Cells**: step1 (a=6), step2 (b=16), step3 (c=32), step4 (d=26)
- **Oracles**: 4/4 pass (deterministic)
- **Status**: ALL CELLS FROZEN

### 4. greet-shout.cell (2 cells, soft + hard, --dry-run)
- **Result**: QUIESCENT after 2 steps (dry-run mode, no API key)
- **Status**: ALL CELLS FROZEN (soft cell produces placeholder in dry-run)

### 5. min-max-range.cell (3 cells, list primitives)
- **Result**: QUIESCENT after 3 steps
- **Cells**: find-min (minimum=1), find-max (maximum=9), compute-range (range=8)
- **Oracles**: 3/3 pass (deterministic)
- **Status**: ALL CELLS FROZEN

### 6. triangle-area.cell (2 cells, nested conditionals)
- **Result**: QUIESCENT after 2 steps
- **Cells**: compute-area (area=24), classify-size (size="medium")
- **Oracles**: 2/2 pass (deterministic)
- **Status**: ALL CELLS FROZEN

## Bugs Fixed

### 1. if/then/else syntax not supported in eval_hard
- **File**: `beads-eval-loop.py`
- **Problem**: Cell uses `if X then Y else Z`, Python needs `Y if X else Z`
- **Fix**: Added regex-based conversion with support for nested ternaries
- **Affected programs**: abs-value.cell, triangle-area.cell

## Coverage

| Feature | Tested By |
|---------|-----------|
| Basic arithmetic | add-double, chain-four |
| Dependency resolution | chain-four (4 levels), add-double |
| Guard dispatch | abs-value |
| Bottom propagation | abs-value (pass-through) |
| Conditional branching (if/then/else) | abs-value, triangle-area |
| Nested conditionals | triangle-area |
| List primitives (min, max) | min-max-range |
| Soft cell dispatch (LLM) | greet-shout (dry-run) |
| Oracle checking | all programs |
| Quiescence detection | all programs |
