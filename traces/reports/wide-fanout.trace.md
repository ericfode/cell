# wide-fanout.cell — Execution Trace

**Program**: `tools/cell-zero/tests/wide-fanout.cell`
**Pattern**: Fan-out/fan-in (1 source → 5 consumers → 1 merge)
**Result**: 7 frozen, 0 bottom — ALL CELLS FROZEN

## Cell Graph

```
source (n=10) → val=10
├── plus-one   → result=11    (val + 1)
├── times-two  → result=20    (val * 2)
├── squared    → result=100   (val * val)
├── negated    → result=-10   (0 - val)
├── halved     → result=5.0   (val / 2)
└── merge-all  → total=126.0  (11 + 20 + 100 + -10 + 5)
```

## Step-by-Step

| Step | Action | Cell | Output | Oracle |
|------|--------|------|--------|--------|
| 0 | freeze | source | val=10 | 10=10 ✓ |
| 1 | freeze | plus-one | result=11 | 11=11 ✓ |
| 2 | freeze | times-two | result=20 | 20=20 ✓ |
| 3 | freeze | squared | result=100 | 100=100 ✓ |
| 4 | freeze | negated | result=-10 | -10=-10 ✓ |
| 5 | freeze | halved | result=5.0 | 5.0=5 ✓ |
| 6 | freeze | merge-all | total=126.0 | 126.0=126 ✓ |

**QUIESCENT** after 7 steps.

## What This Tests

- Wide parallel dependency: 5 cells all depend on `source`, could execute in parallel
- Fan-in: `merge-all` has 5 given clauses, waits for all 5 consumers
- Mixed arithmetic: addition, multiplication, negation, division
- Numeric type handling: division produces 5.0 (float), oracle accepts 5.0==5
