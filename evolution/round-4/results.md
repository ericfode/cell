# Round 4 Results: Verifiable Oracles

## Key Discoveries

### 1. Oracle Spectrum
Oracles fall on a determinism spectrum:
- **Fully deterministic**: `result = 55`, `sorted is a permutation of items`
  → Can be replaced by code. Zero LLM needed.
- **Deterministic-after-commitment**: `reversed read backwards equals «text»`
  → Deterministic once you commit to an interpretation of "read backwards"
- **Semantic**: `answer addresses «query»`
  → Requires LLM judgment. Cannot crystallize without changing the contract.

### 2. Verification is easier to crystallize than computation
- `sort` (computation) has many valid algorithms → hard to crystallize
- `verify` (verification) has exactly one correct behavior → trivially crystallizable
- This is a DEEP property: checking is easier than doing

### 3. Structural oracles are sliding-window integrity checks
The fibonacci recurrence oracle `trace[k] = trace[k-1] + trace[k-2]`
catches a single corrupted entry AND propagates failures to 2 downstream
entries. This is like a checksum built into the execution trace.

### 4. Defense in depth: ⊨ oracles vs verification cells
- ⊨ oracles are type-level (checked by runtime, terse, authoritative)
- Verification cells are test-level (user code, detailed, inspectable)
- They catch DIFFERENT failure modes (binding integrity vs value correctness)

### 5. The metacircular bootstrap works
- `describe` can describe itself via §describe without paradox
- § creates clean use/mention separation (like Lisp's quote)
- Bootstrap sequence: external spec → LLM executes → crystallize → self-hosting
- `describe` is a PURE PARSER — first crystallization candidate

### 6. § quoting universally understood
All agents across all rounds understood § from context alone.
Zero confusion. Strong signal this is the right symbol.
