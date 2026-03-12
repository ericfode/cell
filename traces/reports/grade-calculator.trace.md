# grade-calculator.cell — Execution Trace

**Program**: `tools/cell-zero/tests/grade-calculator.cell`
**Pattern**: 5-way guard dispatch (score→grade→feedback)
**Result**: 2 frozen, 3 bottom — ALL RESOLVED

## Cell Graph

```
assign-grade (score=85) → grade="B"
├── handle-a    [guard grade="A"] → ⊥
├── handle-b    [guard grade="B"] → feedback="Good job!"  ✓ FROZEN
├── handle-c    [guard grade="C"] → ⊥
└── handle-fail [guard grade="F"] → ⊥
```

## Step-by-Step

| Step | Action | Cell | Output | Oracle |
|------|--------|------|--------|--------|
| 0 | freeze | assign-grade | grade='B' | grade="B" ✓ |
| 1 | skip→⊥ | handle-a | — | guard "A"≠"B" |
| 1 | skip→⊥ | handle-c | — | guard "C"≠"B" |
| 1 | skip→⊥ | handle-fail | — | guard "F"≠"B" |
| 1 | freeze | handle-b | feedback='Good job!' | feedback="Good job!" ✓ |

**QUIESCENT** after 2 steps.

## What This Tests

- Complex 5-level nested if/then/else: `if score >= 90 then "A" else if score >= 80 then "B" else ...`
- Guard clause on string equality across 4 branches (no handle-d, so missing grade "D" goes unmatched)
- Only the correct branch executes; all others → ⊥
