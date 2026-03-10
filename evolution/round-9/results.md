# Round 9 Results: Spawner-Halting

## Cold Read Evaluation

Mode: COLD READ — no syntax reference consulted.

## Evaluation Questions

### 1. Can you trace the spawner's output? How many cells get created?

**Yes.** The trace is readable from cold.

**seed-topic** produces 3 follow-ups. The spawner `⊢⊢ explore` takes those
follow-ups plus the §-quoted template of seed-topic, and creates 3 new cells
at depth 1. Each of those cells also yields 3 follow-ups (same signature as
seed-topic), so depth 2 would spawn up to 9 more — but `max 9` caps total
spawned cells. With 3 already spawned, only 6 more fit under the cap.

**Total spawned by ⊢⊢**: 9 (3 at depth 1, 6 at depth 2).
**Total cells in the program**: 11 (seed-topic + 9 spawned + synthesis).

The trace is straightforward to follow. The tree structure is clear:
```
seed-topic (depth 0)
├── cell-1 (depth 1) → 3 follow-ups
│   ├── cell-4 (depth 2)
│   ├── cell-5 (depth 2)
│   └── [capped]
├── cell-2 (depth 1) → 3 follow-ups
│   ├── cell-6 (depth 2)
│   ├── cell-7 (depth 2)
│   └── [capped]
└── cell-3 (depth 1) → 3 follow-ups
    ├── cell-8 (depth 2)
    ├── cell-9 (depth 2)
    └── [capped]
```

**Ambiguity**: The cap cuts in mid-branch. Which depth-2 cells get spawned and
which get dropped? The program doesn't specify ordering. In practice this likely
doesn't matter (all branches are equivalent in structure), but a deterministic
runtime would need a traversal order (BFS? DFS? Round-robin across branches?).

### 2. What happens when an oracle fails? Show the retry flow.

**There is no retry flow in this program.** The oracles use plain `⊨`
(assertions), not `⊨?` (recoverable assertions from Round 8). If any oracle
fails, the behavior is **undefined by this program**.

Failure scenarios:
- `⊨ summary is 2-3 sentences`: If the LLM generates 4 sentences, fail. No retry.
- `⊨ follow-ups has exactly 3 items`: If the LLM gives 2, fail. No retry.
- `⊨ total spawned cells ≤ 9`: This is a runtime invariant, not an LLM output
  check. It should never fail if `max 9` is enforced. Redundant with `max`.

**The oracle on spawned cells is interesting**:
`⊨ §new-cells[] each have same given/yield signature as «§seed-topic»`
This is a *structural* assertion on generated cells. If the spawner creates a
cell that doesn't match the template's signature, what happens? The spawner is
the runtime itself (not the LLM), so this oracle is checking the *spawning
mechanism*, not LLM output. This feels like a type-check, not an oracle.

**Observation**: This program would benefit from `⊨?` with exhaustion handlers.
The seed-topic oracles are the most likely to fail (LLM counting is unreliable),
and each spawned cell inherits the same oracles. A single oracle failure in any
of 9 spawned cells could crash the whole tree.

### 3. Does the program terminate? Why or why not?

**Yes, the program terminates.** Two independent guards ensure this:

1. **`until depth > 2`** — The spawner stops after depth 2. Even if every cell
   produces follow-ups, the spawner won't process depth-3 follow-ups.

2. **`max 9`** — Hard cap on total spawned cells. Even without the depth guard,
   the spawner cannot create more than 9 cells.

Either guard alone is sufficient for termination. Together they provide defense
in depth.

**However**, termination assumes:
- Oracle retries are bounded (or don't happen — see Q2).
- The spawner is the only entity that creates cells (synthesis doesn't spawn).
- `depth` is well-defined and monotonically increasing.

**The `∨ follow-ups all empty` clause is interesting**: It's an early-exit
condition, not a termination guard. If all follow-ups are empty at some depth,
the spawner stops early (before hitting depth or max limits). This handles the
case where the research topic is narrow and runs out of questions.

**Halting verdict**: The program is guaranteed to halt under reasonable
assumptions. The `until` + `max` double-guard is exactly the right pattern.
Compare to Round 8's frontier growth, which had NO halting condition and was
correctly flagged as non-terminating. This directly addresses that gap.

### 4. Rate the clarity of each new syntax element (⊢⊢, until, max) 1-10

**⊢⊢ (spawner cell): 7/10**

Strengths:
- Visually distinct from `⊢` — doubling signals "meta-level"
- Naturally reads as "this cell creates more cells"
- The § quoting of the template (`given §seed-topic`) makes the
  mechanism clear: "here's the blueprint, stamp out copies"

Weaknesses:
- Cold reading `⊢⊢` you might think "double assertion" rather than "spawner"
- The name `explore` does more work than `⊢⊢` itself — without that semantic
  hint, `⊢⊢` alone doesn't scream "spawner"
- No visual analog in existing languages. `⊢⊢` is arbitrary doubling.

**until: 9/10**

Nearly perfect. `until depth > 2 ∨ follow-ups all empty` reads as English.
The only minor issue is the implicit loop — `until` implies iteration, but
the iteration structure isn't spelled out. You infer the loop from context
(follow-ups feed the next depth). Reads clearly on first pass.

**max: 9/10**

`max 9` is immediately clear: "at most 9 spawned cells." No ambiguity.
Slight deduction because `max` as a keyword could conflict with a binding
name (what if someone has a variable called `max`?). Also, the interaction
with `until` isn't fully specified — does `max` count retries? Failed spawns?

### 5. What's ambiguous or underspecified?

**Critical ambiguities:**

1. **Depth semantics** — What is depth 0? Is seed-topic at depth 0, and the
   first batch of spawned cells at depth 1? Or does the spawner itself start
   at depth 0? The program says `until depth > 2`, which allows depths 0, 1,
   and 2 — but which cells are at which depth?

2. **Cap distribution** — When `max 9` cuts off spawning mid-depth, which
   branches get their children and which don't? No ordering is specified.
   This matters for fairness of exploration.

3. **Oracle failure propagation** — If a spawned cell's oracle fails, does
   the failure propagate to the spawner? Does it count against `max`? Is the
   cell retried, skipped, or does the whole tree fail?

4. **Template instantiation semantics** — `given §seed-topic` provides the
   template, but what exactly gets copied? Just the `∴` instructions? The
   `⊨` oracles too? The `given`/`yield` signature? What about the `given
   question ≡ "..."` — is the literal value overwritten, or is `≡` treated
   as a default?

5. **`follow-ups all empty` scope** — "All" follow-ups from which cells? All
   cells at the current depth? All cells ever produced? This is a halting
   condition, so precision matters.

6. **Spawner lifecycle** — Does `⊢⊢ explore` execute once (batch mode) or
   persist across depths (daemon mode)? The `until` suggests it loops, but
   the cell model typically has execute-once semantics.

7. **`seed-topic→follow-ups` vs depth-N follow-ups** — The spawner's `given`
   says `seed-topic→follow-ups`, but the ∴ body says spawned cells "also
   yield follow-ups, feeding the next depth level." How do depth-2 cells'
   follow-ups reach the spawner if the `given` only names `seed-topic`?

**Minor ambiguities:**

8. **`⊨ total spawned cells ≤ 9` redundancy** — This duplicates `max 9`. If
   they're different mechanisms (compile-time vs runtime), that should be
   explicit. If they're the same, one is noise.

9. **Synthesis input** — `given explore→§new-cells` takes the spawner's
   output. But does this include all 9 cells, or just the cells from the
   last depth? The § prefix on `new-cells` suggests these are cell
   *definitions*, not their outputs. Synthesis needs summaries (cell
   *outputs*), not definitions.

10. **Parallelism** — Are depth-1 cells executed in parallel? Can depth-2
    spawning begin before all depth-1 cells complete? The dataflow suggests
    yes (cells at the same depth are independent), but it's implicit.

## Summary Ratings

| Element | Score | Notes |
|---------|-------|-------|
| ⊢⊢ spawner | 7/10 | Concept works, glyph is arbitrary |
| until | 9/10 | Natural English, clear semantics |
| max | 9/10 | Immediately clear, minor edge cases |
| Halting guarantee | 8/10 | Double guard works, edge cases underspecified |
| Traceability | 8/10 | Can trace, but cap distribution unclear |
| Oracle story | 4/10 | Absent — needs ⊨? or explicit failure mode |
| Template instantiation | 5/10 | § quoting elegant but mechanics undefined |

**Overall: 7/10** — The spawner-halting syntax directly addresses Round 8's
frontier growth gap. The `until` + `max` termination pattern is sound and
clear. Main weakness is oracle failure handling (not addressed at all) and
template instantiation semantics (how exactly does § copying work?).

## Key Discovery: The Spawner's Dual Nature

The spawner `⊢⊢` has a tension: it's both a **cell** (has given/yield/∴/⊨)
and a **loop** (has until/max). Regular cells execute once. Spawners iterate.
This breaks the uniform cell model.

Two design paths:
1. **Spawner as special cell** — `⊢⊢` is a distinct construct with loop
   semantics. Simple but adds a second execution model.
2. **Spawner as recursive cell** — The spawner emits cells that can themselves
   be spawners. More powerful but harder to guarantee termination (need
   decreasing depth parameter or fuel).

The current design takes path 1 (⊢⊢ is special). This is probably right for
now — path 2 is Turing-complete and requires a proof of termination.

## Cumulative Scores (all rounds)

- § quoting: 100% comprehension, universally natural
- ⊢= crystallization: 8/10
- ⊢∘ evolution loop: 8/10
- Proof-carrying computation: 9/10
- eval-one metacircular: 9/10
- Self-crystallization: 9/10
- Cell-as-agent: 8/10
- Oracle failure recovery ⊨?: 7/10
- Frontier growth: 6/10 (syntax gap — Round 8)
- **Spawner-halting (⊢⊢ + until + max): 7/10** (addresses frontier gap, oracle story missing)
