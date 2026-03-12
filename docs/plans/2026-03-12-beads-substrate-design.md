# Beads Substrate for Cell-Zero

**Date**: 2026-03-12
**Status**: Design
**Bead**: ce-tgah

## Summary

Cell programs execute via beads. Each cell becomes a bead. Dependencies become
blocking relationships. `bd ready` replaces `find_ready.py`. Soft cells dispatch
to polecats. Hard cells evaluate locally. The language develops itself.

## Concept Mapping

| Cell | Beads |
|------|-------|
| Cell `⊢ name` | `bd create "name"` |
| `given X→Y` | `bd dep add <this> <X-bead-id>` |
| Cell is ready | `bd ready` (all blockers closed) |
| `yield name ≡ val` | `bd update --set-metadata yield_name=val` |
| Frozen | `bd close <id>` |
| Bottom `⊥` | `bd close <id>` + label `bottom` |
| Soft body `∴` | Bead description |
| Hard body `⊢=` | Metadata `body_type=hard`, `expr=...` |
| Oracle `⊨` | Child bead, type=task, label=oracle |
| Spawner `⊢⊢` | Creates child beads |
| Guard `where` | Metadata `guard_expr=...` (checked before dispatch) |

## Components

### 1. cell-to-beads (loader)

`tools/cell-zero/cell-to-beads.py <program.cell>`

Parses .cell file, creates one bead per cell with:
- Title = cell name
- Description = ∴ body (soft) or "⊢= expr" (hard)
- Label = `cell`, `soft`/`hard`/`spawner`/`evolution`
- Metadata: `body_type`, `expr` (hard), `yield_names`, `givens` (JSON)
- Dependencies via `bd dep add`
- Default values stored in metadata

Returns a mapping file: `cell-name → bead-id`

### 2. beads-eval-loop (orchestrator)

`tools/cell-zero/beads-eval-loop <mapping-file>`

Loop:
1. `bd ready --json` → find claimable beads with label=cell
2. Pick first ready bead
3. Check guard expressions (read metadata, evaluate against closed deps' yields)
4. Dispatch:
   - Hard: read expr from metadata, evaluate via Python, store yields in metadata
   - Soft: compose prompt from description + resolved inputs, dispatch to agent
5. Create oracle claim beads (children of the cell bead)
6. Check oracle claims
7. `bd close` (freeze) or retry or bottom
8. Loop until `bd ready` returns nothing

### 3. beads-dispatch-soft

For soft cells, two modes:
- **Agent mode**: Use Claude Code Agent tool (when running inside Claude Code)
- **Polecat mode**: `gt sling` the oracle bead to a polecat (when running in Gas Town)

### 4. Yield value storage

Yield values stored as bead metadata:
```
bd update <id> --set-metadata '{"yield_sum": 8, "yield_count": 3}'
```

Downstream beads read upstream yields:
```
bd show <upstream-id> --json | jq '.metadata.yield_sum'
```

### 5. Guard checking

Before dispatching a ready bead:
1. Read its `guard_expr` from metadata
2. Read the upstream bead's yield values
3. Evaluate guard expression
4. If false → `bd close <id>` with label `bottom`

## Use Case: Cell Developing Cell

Write a `.cell` program where cells describe real development tasks:

```
⊢ design-parser
  yield parser-spec
  ∴ Design a parser for Cell v0.2 syntax. Cover all symbols,
    cell declarations, given/yield, oracles, guards, spawners.

⊢ implement-parser
  given design-parser→parser-spec
  yield parser-code
  ∴ Implement the parser described in «design-parser→parser-spec»
    as a Python module.

⊢ test-parser
  given implement-parser→parser-code
  yield test-results
  ∴ Write tests for the parser. Test each syntax element.
  ⊨ test-results contains "all pass"
```

Each cell becomes a bead. `design-parser` dispatches to a polecat.
When it completes, `implement-parser` becomes ready. And so on.

## Architecture

```
.cell file
    │
    ▼
cell-to-beads.py ──► bd create (N beads) + bd dep add (edges)
    │
    ▼
beads-eval-loop ───► bd ready → pick → dispatch → oracle → close
    │                    ▲                                   │
    │                    └───────────────────────────────────┘
    ▼
QUIESCENT (all beads closed)
```

## Differences from JSON Substrate

| JSON substrate | Beads substrate |
|----------------|-----------------|
| State in /tmp dir | State in Dolt DB |
| find_ready.py | `bd ready` |
| JSON files per cell | Beads with metadata |
| In-process dispatch | Polecat dispatch possible |
| Single machine | Distributed (Gas Town) |
| Ephemeral | Persistent + versioned |
| No parallelism | Confluence → parallel dispatch |

## Implementation Order

1. Write `cell-to-beads.py` (parser already exists, just create beads)
2. Write `beads-eval-loop` bash script
3. Test with add-double.cell (pure hard, no LLM needed)
4. Test with greet-shout.cell (soft cell, needs agent dispatch)
5. Write a "develop Cell" .cell program and run it for real
