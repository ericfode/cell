# Cell Repo Cleanup Recommendations: Reducing Agent Noise

**Date**: 2026-03-13
**Bead**: ce-kd0
**Surveyor**: polecat rust

---

## Executive Summary

The cell repo is ~85% active code. The main sources of agent confusion are: a
dual parser system with no documented canonical choice, a dormant Lean4
formalization that signals active formal verification, and an experimental ML
tool with unclear status. The evolution directory (4.5M) is large but justified
as design-decision source-of-truth. Overall the repo is well-organized; cleanup
is targeted, not sweeping.

---

## Inventory Snapshot

| Area | Size | Files | Status |
|------|------|-------|--------|
| Go code (`cmd/`, `internal/`) | 14.6K lines | 30 | Active |
| Python tools (`tools/`) | 4.8K lines | 15 | Mixed |
| Lean4 formalization (`lean4/`) | 4.7K lines | 16 | Dormant |
| Documentation (`docs/`) | 1.5M | 80 | Current |
| Examples (`docs/examples/`) | 424K | 50 | Active test corpus |
| Evolution (`evolution/`) | 4.5M | 254 | Reference archive |
| Config (`.gitignore`, `go.mod`, etc.) | — | 5 | Clean |

---

## Priority 1: High-Impact, Low-Effort

### 1.1 Document the Dual Parser Canonical Choice

**Problem**: `internal/cell/` (basic parser, 1.7K lines) and `internal/cell/parser/`
(extended parser, 7K lines) both parse `.cell` files. `cmd/cell/main.go` tries
extended first, falls back to basic. No documentation says which is canonical.

**Agent impact**: An agent modifying parsing logic doesn't know which parser to
touch. Bug fixes may go to the wrong one. New features may be added to the basic
parser when the extended parser is the real target.

**Recommendation**: Add a deprecation comment to `internal/cell/ast.go`:
```go
// Package cell contains the basic/legacy parser.
// The canonical parser is internal/cell/parser/.
// This package is retained as fallback for files using the original
// cell { type, prompt, refs } syntax. New features go in parser/.
```

And update CLAUDE.md with:
```
## Parser Architecture
The canonical parser is `internal/cell/parser/`. The basic parser in
`internal/cell/` is legacy fallback only. New work targets the extended parser.
```

**Effort**: 15 minutes. **Impact**: Eliminates the #1 source of agent confusion.

### 1.2 Mark Lean4 as Archive/Aspirational

**Problem**: `lean4/BeadCalculus/` contains 4.7K lines of formal proofs. No recent
commits target it. No CI builds it. No code imports it. It's beautiful work, but
it signals "active formal verification" when there is none.

**Agent impact**: An agent exploring the codebase may spend significant time reading
Lean4 code thinking it's load-bearing, or may try to update proofs when modifying
semantics.

**Recommendation**: Add `lean4/README.md`:
```markdown
# Lean4 BeadCalculus Formalization

**Status: Archive / Aspirational**

This directory contains formal proofs of Cell's computational properties
(confluence, monotonicity, DAG correctness) in Lean 4. It is not actively
maintained and is not part of the build or test pipeline.

The formalization was created to establish theoretical foundations. It should
be treated as reference material, not as a source of truth for current
implementation behavior.

Do not modify these files unless specifically tasked with formal verification work.
```

**Effort**: 5 minutes. **Impact**: Prevents agents from going down a 4.7K-line rabbit hole.

### 1.3 Clarify cell-validator Tool Status

**Problem**: `tools/cell-validator/` is an ML-based syntax classifier using tinygrad.
Added recently (4 commits), but not integrated into the CLI or any pipeline. No
README explains whether it's proof-of-concept, active development, or abandoned.

**Agent impact**: An agent exploring tools/ may try to integrate it, debug it, or
include it in build steps when it's experimental.

**Recommendation**: Add `tools/cell-validator/README.md`:
```markdown
# Cell Validator (Experimental)

Character-level transformer classifier for validating .cell syntax.
Uses tinygrad for a minimal ML pipeline.

**Status: Experimental proof-of-concept**

Not integrated into the main CLI. Training data is derived from
docs/examples/ .cell files. This is exploratory work to see if ML-based
validation is viable for syntax checking.
```

**Effort**: 5 minutes. **Impact**: Prevents wasted agent effort on experimental code.

---

## Priority 2: Moderate Impact

### 2.1 Add Status Markers to tools/ Subdirectories

**Problem**: `tools/` contains three subdirectories with different maturity levels:
- `cell-zero/` — Core infrastructure, actively used
- `eval-one/` — Active, proves mechanizability
- `cell-validator/` — Experimental (see 1.3)

**Agent impact**: No way to know which tools are production vs experimental without
reading all the code.

**Recommendation**: Add `tools/README.md`:
```markdown
# Cell Tools

| Tool | Status | Purpose |
|------|--------|---------|
| cell-zero/ | **Active** | Cell evaluation engine: dispatch, beads integration, orchestration |
| eval-one/ | **Active** | Minimal executor proving Cell is mechanizable via Kahn's algorithm |
| cell-validator/ | **Experimental** | ML-based syntax validation (not integrated) |
```

**Effort**: 10 minutes. **Impact**: Quick orientation for agents entering tools/.

### 2.2 Document polecat.go Standalone Limitation

**Problem**: `internal/cell/subzero/polecat.go` defines a `PolecatExecutor` that
returns `fmt.Errorf("polecat cell execution not supported in standalone mode")`.
No comment explains why.

**Agent impact**: An agent may try to implement polecat execution, not realizing it
requires the full Gas Town infrastructure and is deliberately stubbed.

**Recommendation**: Add a doc comment:
```go
// PolecatExecutor delegates cell execution to Gas Town polecat agents.
// In standalone mode (running the cell CLI directly), this is not supported
// because it requires the Gas Town multi-agent infrastructure.
// This executor is only functional when cell is running inside a Gas Town rig.
```

**Effort**: 5 minutes. **Impact**: Prevents agents from attempting to "fix" the stub.

### 2.3 Consolidate docs/frames/ into evolution/

**Problem**: `docs/frames/` contains 25 traced execution artifacts from evolutionary
rounds. These are reference data from the evolution process, stored separately
from the evolution rounds they came from.

**Agent impact**: An agent reading docs/ may not understand what "frames" are or how
they relate to evolution rounds. They're not design docs or specs — they're test
artifacts filed in the wrong location.

**Recommendation**: Move `docs/frames/` → `evolution/frames/` and add a one-line
README: "Traced execution artifacts from evolution rounds. Reference only."

**Effort**: 10 minutes. **Impact**: Keeps docs/ focused on documentation.

---

## Priority 3: Nice-to-Have

### 3.1 Archive Evolution Rounds 1-14

**Problem**: `evolution/` is 4.5M across 17 rounds. Rounds 1-14 are complete and
mostly historical. Rounds 15-17 contain active analysis used for current design
decisions.

**Agent impact**: An agent exploring evolution/ may read through 14 completed rounds
before finding the currently-relevant material.

**Recommendation**: Create `evolution/archive/` and move rounds 1-14 there. Add
`evolution/README.md` explaining that rounds 15-17 and the synthesis documents
are the active references.

**Effort**: 15 minutes. **Impact**: Helps agents find relevant evolution data faster.
**Risk**: May break references in synthesis documents. Check before moving.

### 3.2 Reduce Towers of Hanoi Test Files

**Problem**: `docs/examples/` contains three Towers of Hanoi files:
- `towers-of-hanoi-7.cell` (6K)
- `towers-of-hanoi-9.cell` (23K)
- `towers-of-hanoi-10.cell` (49K)

These are 78K combined — 18% of the examples directory — for a single algorithm.

**Agent impact**: Minimal, but bloats the examples directory.

**Recommendation**: Keep `towers-of-hanoi-7.cell` (demonstrates the pattern),
remove the 9 and 10 variants (they just have more disks).

**Effort**: 5 minutes. **Impact**: Minor cleanup.

### 3.3 Add CLAUDE.md Parser Guidance

**Problem**: The current CLAUDE.md only has beads configuration. It doesn't guide
agents on code structure.

**Recommendation**: Extend CLAUDE.md with:
```markdown
## Code Structure
- Canonical parser: `internal/cell/parser/` (extended syntax with molecules)
- Legacy parser: `internal/cell/` (basic `cell { }` syntax, fallback only)
- Executor: `internal/cell/subzero/` (topological sort + dispatch)
- CLI: `cmd/cell/main.go`
- Python tools: `tools/` (see tools/README.md for status)
- Formal proofs: `lean4/` (archive, not actively maintained)
```

**Effort**: 5 minutes. **Impact**: Every agent session starts with CLAUDE.md context.

---

## What NOT to Clean Up

These areas look potentially messy but are justified:

1. **evolution/** (4.5M) — Source of truth for language design decisions. The size
   is justified by the empirical methodology.

2. **docs/examples/** (50 files) — Active test corpus used by tools/cell-zero/.
   Well-organized by concept.

3. **docs/design/gas-city-*.md** (7 files) — Exploratory design for future
   ecosystem. Even if aspirational, they document architectural thinking.

4. **.beads/, .runtime/, .claude/** — Runtime infrastructure. Agents should
   ignore these (already in .gitignore where appropriate).

5. **Dual ASTs** — While the basic parser could be deprecated, it still serves
   as fallback. Document the relationship (Priority 1.1) rather than removing code.

---

## Summary: Effort vs Impact Matrix

| # | Recommendation | Effort | Impact | Priority |
|---|---------------|--------|--------|----------|
| 1.1 | Document canonical parser | 15 min | HIGH | P1 |
| 1.2 | Mark Lean4 as archive | 5 min | HIGH | P1 |
| 1.3 | Clarify cell-validator status | 5 min | HIGH | P1 |
| 2.1 | Add tools/ status README | 10 min | MEDIUM | P2 |
| 2.2 | Document polecat.go stub | 5 min | MEDIUM | P2 |
| 2.3 | Move frames/ to evolution/ | 10 min | MEDIUM | P2 |
| 3.1 | Archive evolution rounds 1-14 | 15 min | LOW | P3 |
| 3.2 | Remove large Hanoi variants | 5 min | LOW | P3 |
| 3.3 | Add CLAUDE.md code structure | 5 min | MEDIUM | P3 |

**Total estimated effort**: ~75 minutes for all items.
**Recommended first pass**: Items 1.1, 1.2, 1.3, and 3.3 (~30 minutes, highest ROI).
