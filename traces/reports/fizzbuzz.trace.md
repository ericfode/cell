# fizzbuzz.cell — Execution Trace

**Program**: `tools/cell-zero/tests/fizzbuzz.cell`
**Pattern**: Guard dispatch (5-way branch, 3→⊥)
**Result**: 2 frozen, 3 bottom — ALL RESOLVED

## Cell Graph

```
classify (n=15) → label="fizzbuzz"
├── handle-fizzbuzz [guard label="fizzbuzz"] → output="FizzBuzz!"  ✓ FROZEN
├── handle-fizz    [guard label="fizz"]      → ⊥  (guard false)
├── handle-buzz    [guard label="buzz"]      → ⊥  (guard false)
└── handle-number  [guard label="number"]    → ⊥  (guard false)
```

## Step-by-Step

| Step | Action | Cell | Output | Oracle |
|------|--------|------|--------|--------|
| 0 | freeze | classify | label='fizzbuzz' | label="fizzbuzz" ✓ |
| 1 | skip→⊥ | handle-fizz | — | guard "fizz"≠"fizzbuzz" |
| 1 | skip→⊥ | handle-buzz | — | guard "buzz"≠"fizzbuzz" |
| 1 | skip→⊥ | handle-number | — | guard "number"≠"fizzbuzz" |
| 1 | freeze | handle-fizzbuzz | output='FizzBuzz!' | output="FizzBuzz!" ✓ |

**QUIESCENT** after 2 steps.

## What This Tests

- Nested if/then/else expression evaluation (4-level deep)
- Guard clause dispatch: only the matching branch executes
- Non-matching guard cells go ⊥ (bottom) — correct Cell semantics
- Oracle verification on both classify and handle-fizzbuzz
