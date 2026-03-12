# fibonacci-crystal.cell — Execution Trace

**Program**: `tools/cell-zero/tests/fibonacci-crystal.cell`
**Pattern**: Soft cells → recurrence oracle → crystallization → crystal verification
**Result**: 6 frozen, 0 bottom — ALL CELLS FROZEN
**Previously**: 4 frozen, 2 bottom (crystallize and verify-crystal went ⊥ due to guard bug)

## Cell Graph

```
fib (n=10, ∴ soft)         → result=55
fib-prev (n=9, ∴ soft)     → result=34
fib-prev2 (n=8, ∴ soft)    → result=21
  └── verify-recurrence (hard: 55 = 34 + 21) → holds=True
        └── crystallize (∴ soft, §fib quotation) → §fib'="⊢= result ← ...", is-faithful=True
              └── verify-crystal (∴ soft) → approved=True
```

## Step-by-Step

| Step | Action | Cell | Output | Oracle |
|------|--------|------|--------|--------|
| 0 | freeze | fib | result=55 | (soft, no oracle) |
| 1 | freeze | fib-prev | result=34 | (soft, no oracle) |
| 2 | freeze | fib-prev2 | result=21 | (soft, no oracle) |
| 3 | freeze | verify-recurrence | holds=True | holds=true ✓ (55==34+21) |
| 4 | freeze | crystallize | §fib'="⊢= result ← if n <= 1 then n else fib(n-1) + fib(n-2)", is-faithful=True | (soft, no oracle) |
| 5 | freeze | verify-crystal | approved=True | conditional oracle ✓ |

**QUIESCENT** after 6 steps.

## Bug Fixed

Guard evaluation compared `str(True)` ("True") with Cell literal `"true"` —
always failed, causing crystallize to be skipped. Fix: normalize Python bools
to lowercase for guard comparison in `find_ready.py:eval_guard()`.

## What This Tests

- **Fusion semantics**: soft cells (LLM) produce fib(10)=55, fib(9)=34, fib(8)=21
- **Recurrence oracle**: hard cell verifies 55 = 34 + 21 (property-based, not answer-based)
- **§ quotation**: crystallize receives §fib (the source code of the fib cell)
- **Guard clause with boolean**: `given verify-recurrence→holds where holds = true`
- **Crystallization**: LLM reads the soft cell, writes a deterministic ⊢= replacement
- **Crystal verification**: second LLM pass confirms the crystal is faithful
- **Full pipeline**: soft → verify → crystallize → verify-crystal (the Cell self-improvement loop)
