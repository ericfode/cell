# gcd-steps.cell — Execution Trace

**Program**: `tools/cell-zero/tests/gcd-steps.cell`
**Pattern**: Deep linear chain (Euclidean algorithm unrolled)
**Result**: 4 frozen, 0 bottom — ALL CELLS FROZEN

## Cell Graph

```
step0 (a=48, b=18) → remainder=12
  └── step1 (prev-b=18, step0→remainder) → remainder=6
        └── step2 (prev-b=12, step1→remainder) → remainder=0
              └── result (step2→remainder, step1→remainder) → gcd=6
```

## Step-by-Step

| Step | Action | Cell | Output | Oracle |
|------|--------|------|--------|--------|
| 0 | freeze | step0 | remainder=12 | 48 % 18 = 12 ✓ |
| 1 | freeze | step1 | remainder=6 | 18 % 12 = 6 ✓ |
| 2 | freeze | step2 | remainder=0 | 12 % 6 = 0 ✓ |
| 3 | freeze | result | gcd=6 | if 0==0 then 6 else 0 → 6 ✓ |

**QUIESCENT** after 4 steps.

## What This Tests

- Deep 4-cell linear dependency chain — each cell waits for the previous
- Modular arithmetic: the `%` operator
- Conditional termination: `if step2→remainder == 0 then step1→remainder`
- Every cell has an oracle, all pass deterministically
