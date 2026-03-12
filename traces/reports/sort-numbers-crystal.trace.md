# sort-numbers-crystal.cell — Execution Trace

**Program**: `tools/cell-zero/tests/sort-numbers-crystal.cell`
**Pattern**: Soft sort → dual property oracle → crystallization
**Result**: 4 frozen, 0 bottom — ALL CELLS FROZEN
**Previously**: 3 frozen, 1 pending (crystallize stuck because verify-permutation only yielded 1 of 2 values)

## Cell Graph

```
sort-them (∴ soft, numbers=[5,3,8,1,9,2,7,4,6]) → sorted=[1,2,3,4,5,6,7,8,9]
├── verify-permutation (hard, 2 yields) → same-length=True, same-sum=True
├── verify-ordered (∴ soft) → is-ordered=True
└── crystallize (∴ soft, requires all 3 above)
      → §sort-them'="⊢= sorted ← sorted(numbers)", is-faithful=True
```

## Step-by-Step

| Step | Action | Cell | Output | Oracle |
|------|--------|------|--------|--------|
| 0 | freeze | sort-them | sorted=[1,2,3,4,5,6,7,8,9] | (soft, no oracle) |
| 1 | freeze | verify-permutation | same-length=True, same-sum=True | both oracles ✓ |
| 2 | freeze | verify-ordered | is-ordered=True | is-ordered=true ✓ |
| 3 | freeze | crystallize | §sort-them'="⊢= sorted ← sorted(numbers)", is-faithful=True | conditional oracle ✓ |

**QUIESCENT** after 4 steps.

## Bug Fixed

**Multi-expression hard cell**: `verify-permutation` has two `⊢=` lines:
```
⊢= same-length ← len(sort-them→sorted) = len(numbers)
⊢= same-sum ← sum(sort-them→sorted) = sum(numbers)
```
Parser only kept the last expression (same-sum), so same-length was never
computed. Dispatch returned `{"same-length": <same-sum result>}` (wrong key).
Fix: parse.py now accumulates multi-line `⊢=` bodies, dispatch.py evaluates
each `name ← expr` independently and builds the output dict correctly.

## What This Tests

- **Multi-yield hard cell**: one cell, two `⊢=` expressions, two independent yields
- **Property-based oracles**: verify permutation (same length + same sum) AND ordering
- **Three independent verification paths** feeding into one crystallize cell
- **Guard clauses**: crystallize requires `same-sum = true` AND `is-ordered = true`
- **Crystallization**: LLM reads sort logic, produces `sorted(numbers)` as replacement
