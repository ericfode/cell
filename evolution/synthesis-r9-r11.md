# Cross-Round Synthesis: R9 → R10 → R11

## The Depth-3 Chain

Three iterative rounds where each round's synthesis fed the next round's design:

- **R9** (Spawner Mechanics & Oracle Recovery): Identified ⊥ propagation as biggest gap
- **R10** (⊥ Propagation, Templates, Oracle-Spawner): Introduced `⊥? skip with`, found composition gaps
- **R11** (Integration — Full Execution Model): Combined ALL features, found semantic bugs

**12 test programs**, **12 polecat cold-reads** (11/12 returned results), **~3000 lines of analysis**.

## Feature Maturity Assessment

### Tier 1: Ready for Spec (8+ consistently)

| Feature | Final Score | Evidence |
|---------|------------|---------|
| `§` quoting (cell-as-value) | 100% | Every polecat across 3 rounds understood immediately |
| `⊢=` crystallization | 9.5/10 | Universally clear, correctly distinguishes LLM from deterministic |
| `∴` soft body | 9/10 | Natural language instruction, no cold-read confusion |
| `⊨` oracle constraint | 9/10 | Direct, verifiable, well-understood |
| Proof-carrying computation | 9/10 | NP-solve + P-verify pattern clean and powerful |
| eval-one (Kahn's) | 9/10 | Metacircular evaluation works, reference implementation viable |
| Self-crystallization | 9/10 | `∴` → `⊢=` transition clear, verification-before-computation sound |

### Tier 2: Needs Clarification (7-8)

| Feature | Final Score | Open Questions |
|---------|------------|---------------|
| `⊥? skip with` | 8/10 | Must bypass oracles (confirmed). Skip-with values vs downstream invariants (0/0 bug). |
| `⊨? on failure/exhaustion` | 8/10 | "max N" ambiguity. Oracle-level retry vs cell-level retry unclear. |
| Template instantiation | 8/10 | § copy-bind works but no `let` binding for shared intermediates |
| `until` / `max` (halting) | 9/10 | Clear syntax but unclear whether max counts retries or attempts |
| Liskov substitution | 8/10 | Good principle, needs formal statement in spec |

### Tier 3: Needs Redesign (< 7)

| Feature | Final Score | Issues |
|---------|------------|--------|
| `⊢⊢` spawner | 5.5/10 | Scope undefined, oracle inheritance unclear, recursive spawning undefined, `§judges[]` ambiguous (cells or results?) |
| `⊢∘` evolution loop | 6/10 | `through` clause doesn't mention all dependencies, relationship to upstream cells implicit |
| Frontier growth | 6/10 | Not retested in R11 but underlying ⊢⊢ issues persist |

## Discovered Design Principles

### 1. ⊥ as Control Flow Fence (R10)

`⊥? skip with` creates a mode switch between oracle execution and deterministic
fallback — Railway Oriented Programming in Cell. Confirmed in R11: skip must
bypass oracles entirely.

### 2. Exhaustion is Cheaper Than Late Success (R11)

⊥ propagation converts downstream LLM calls into free deterministic operations.
A pipeline that fails early and propagates ⊥ uses fewer total LLM calls than
one that succeeds on the last retry. This has optimization implications.

### 3. Templates Collapse Spawning to Map (R10)

Template instantiation reduces `⊢⊢` to `map(template, list)`. This suggests
splitting spawner into:
- `⊢⊢-map`: deterministic fan-out (template × list)
- `⊢⊢-tree`: recursive generation (follow-ups spawn follow-ups)

### 4. Execution Metadata is a Hidden Data Channel (R10)

Spawned cells expose execution history (oracle.failures, exhaustion events).
`oracle.failures` appears in `⊨? on failure: retry with «oracle.failures»`
but is never declared as a `given` or `yield`. This implicit state needs
explicit handling.

### 5. Oracles on Crystals Are Assertions, Not Constraints (R11)

4 of 9 oracles in the proof-carrying pipeline can never fail (they validate
properties guaranteed by ⊢= formulas). Cell should distinguish:
- `⊨` — runtime constraint (can fail, triggers ⊨? recovery)
- Assert/invariant — compile-time checkable, never fails at runtime

### 6. The Crystallization Paradox (R11)

A program whose purpose is to PRODUCE crystallized cells may itself not be
crystallized. The self-crystallizing harness has 5 cells but only 2 are ⊢=.
The certifier cell is soft. This isn't a bug — it's inherent to the
bootstrapping nature of certification.

### 7. Metacircular Oracle Checking Breaks Levels (R11)

When eval-one executes inner cells, it must check inner oracles. But eval-one
is itself an LLM executing a ∴ instruction. This means the LLM is asked to
verify predicates that should be verified by the runtime. The spec must define
which level checks oracles.

## Bugs Found

| Bug | Source | Severity | Fix |
|-----|--------|----------|-----|
| 0/0 false positive | T1 R11 | High | `all-passed ← (pass-count = total) ∧ (total > 0)` |
| Judges score different texts | T3 R11 | Medium | Add `let` binding for shared instantiation |
| `through` clause incomplete | T3 R11 | Medium | Either auto-resolve deps or require explicit listing |
| Skip-with may violate downstream oracles | T1/T4 R11 | Medium | Convention or runtime check needed |
| `max N` ambiguous | Multiple | Low | Define as total attempts (not retries) |

## Spec Actions

### Must Do (blocking v0.1)

1. Define `⊥? skip with` semantics: bypasses body AND oracles
2. Define `max N`: N = total attempts (initial + retries), not retry count
3. Resolve `⊢⊢` spawner: scope, oracle inheritance, `§result[]` typing
4. Define `⊢∘` dependency resolution: explicit `through` vs implicit from `given`
5. Formalize `∴` on `⊢=` cells: documentation-only (no LLM call)

### Should Do (v0.1 quality)

6. Add `let` binding for shared intermediate values
7. Distinguish `⊨` (constraint) from `⊨!` (assertion/invariant)
8. Formalize Liskov substitution for `improve`-type cells
9. Define oracle.failures as explicit execution metadata
10. Document the exhaustion-is-cheaper property

### Nice to Have (v0.2)

11. Split `⊢⊢` into `⊢⊢-map` and `⊢⊢-tree`
12. Add cost annotations (expected LLM calls per cell)
13. Formal semantics for level-crossing in metacircular evaluation

## Statistics

- **Programs written**: 12 (4 per round)
- **Polecat cold-reads**: 12 (11 returned results; 1 R9 polecat failed)
- **Total analysis**: ~3000 lines across all polecats
- **Unique syntax elements tested**: 14 (⊢, ⊢=, ⊢⊢, ⊢∘, ∴, ⊨, ⊨?, ⊥, ⊥?, §, «», ≡, →, ▸)
- **Bugs discovered**: 5
- **Design principles extracted**: 7
- **Spec actions identified**: 13
- **Average clarity improvement**: R9 7.0 → R10 7.25 → R11 7.75 (0.375/round)

## Next Steps

The depth-3 iterative chain is complete. The biggest remaining gap is `⊢⊢`
spawner semantics (5.5/10 and falling). The "big ones" should stress-test:
- Large-scale spawner programs (10+ cells)
- Deep composition (spawner within spawner within evolution loop)
- Adversarial ⊥ propagation (multiple simultaneous failures in a DAG)
- Real-world domain programs (not pedagogical examples)
