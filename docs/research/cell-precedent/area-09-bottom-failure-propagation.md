# Area 9: Bottom/Failure Propagation — Prior Art Survey

Research ID: ce-it4b (polecat/guzzle)

## Overview

Cell's bottom (⊥) represents the absence of a value. When a cell cannot produce
output, it propagates ⊥ to downstream cells. Cells can have ⊥? handlers that
provide fallback values. The frozen set forms a lattice under the "more defined"
ordering, with ⊥ as bottom. This connects Cell to several deep traditions in
logic, programming languages, and database theory.

---

## 1. Domain Theory and Scott Semantics

### 1a. Dana Scott — Domain Theory (1970s)

- **Title**: "Data types as lattices" / "Continuous Lattices" / Domain Theory foundations
- **Authors**: Dana Scott, with later contributions by Christopher Strachey
- **Year**: 1970-1976
- **Key insight**: Introduced the bottom element (⊥) as the "undefined" or
  "nonterminating" value in a complete partial order (CPO). Every domain has a
  least element ⊥, and functions on domains must be Scott-continuous (preserve
  directed suprema). This provides the mathematical foundation for reasoning
  about partial computation.
- **How Cell relates**: Cell's ⊥ directly inherits Scott's concept, but extends
  it beyond "nontermination" to "absence of value" in a dataflow network. In
  Scott domains, ⊥ represents a computation that never returns; in Cell, ⊥
  means a cell that has not (yet) produced a value, which is semantically
  richer — it includes LLM failure, missing data, and deliberate absence.
- **Technique Cell could adopt**: The information ordering (x ⊑ y means "y is
  at least as defined as x") maps directly to Cell's crystallization — a soft
  cell that becomes hard moves "up" in the information ordering.

### 1b. Gordon Plotkin — PCF (1977)

- **Title**: "LCF Considered as a Programming Language"
- **Authors**: Gordon Plotkin
- **Year**: 1977
- **Key insight**: Formalized Programming Computable Functions (PCF) as a typed
  functional language where ⊥ corresponds to non-termination. Every type is
  "lifted" with a bottom element, and the fixed-point combinator Y finds least
  fixed points of continuous functions. This gave precise semantics to recursion
  via ⊥.
- **How Cell differs**: PCF's ⊥ is a single undifferentiated "divergence." Cell
  could benefit from PCF's denotational approach but needs to handle multiple
  *reasons* for ⊥ (LLM refusal, timeout, data not yet available, deliberate
  suppression). Cell's ⊥? handlers are a practical reification of what PCF
  leaves implicit.
- **Technique Cell could adopt**: PCF's strategy of treating every type as a
  pointed CPO (with ⊥) is exactly what Cell does with its cell types. The
  full-abstraction results for PCF via game semantics could inform Cell's
  oracle verification semantics.

### 1c. Knaster-Tarski Fixed Point Theorem

- **Title**: "A Lattice-Theoretical Fixpoint Theorem and its Applications"
- **Authors**: Alfred Tarski (building on Bronisław Knaster)
- **Year**: 1955
- **Key insight**: For any monotone function on a complete lattice, the set of
  fixed points itself forms a complete lattice. In particular, a least fixed
  point always exists. This is the mathematical backbone of recursive program
  semantics — loop/recursion meanings are defined as least fixed points.
- **How Cell relates**: Cell's dataflow evaluation is essentially fixed-point
  computation. The Kahn network semantics guarantees a unique least fixed
  point. Cell's ⊥ is the bottom of the lattice from which computation
  proceeds upward. The Knaster-Tarski theorem guarantees that Cell's iterative
  evaluation converges.
- **Technique Cell could adopt**: The ascending Kleene chain (⊥ ⊑ f(⊥) ⊑
  f(f(⊥)) ⊑ ...) is literally how Cell's spawner fills in cell values
  iteratively. Cell should explicitly document this connection.

---

## 2. Kahn Process Networks and Dataflow

### 2a. Gilles Kahn — Kahn Process Networks (1974)

- **Title**: "The Semantics of a Simple Language for Parallel Programming"
- **Authors**: Gilles Kahn
- **Year**: 1974
- **Key insight**: Deterministic processes communicating via unbounded FIFO
  channels compute continuous functions on streams. The network has a unique
  least fixed point. Processes are monotonic — reading more input can only
  produce more output. This ensures deterministic behavior regardless of
  scheduling.
- **How Cell relates**: Cell explicitly adopts Kahn-style dataflow. The
  monotonicity requirement maps to Cell's rule that cells cannot "un-produce"
  values. ⊥ propagation in Cell is the natural consequence of a process
  blocking on an input that never arrives — the downstream channel remains
  empty (⊥).
- **How Cell improves**: Kahn networks assume all processes eventually produce
  output or block forever. Cell adds explicit ⊥ as a *value* that can be
  observed and handled (via ⊥? handlers), making failure a first-class citizen
  rather than mere divergence. This is a significant semantic extension.
- **Technique Cell could adopt**: Kahn's proof that monotone + continuous
  implies a unique fixed point should be formalized for Cell's mixed
  hard/soft cell networks.

### 2b. Reactive Streams — Error Propagation (2010s)

- **Title**: Reactive Streams Specification / Project Reactor / RxJava
- **Authors**: Various (Lightbend, Netflix, Pivotal, Red Hat)
- **Year**: 2013-present
- **Key insight**: In reactive streams, errors are terminal events that stop the
  sequence and propagate downstream. Operators like `onErrorResume()`,
  `retry()`, and `onErrorReturn()` provide recovery strategies. Three signal
  types: value, error, completion.
- **How Cell relates**: Reactive streams' error-as-terminal-event is analogous
  to Cell's ⊥ propagation. But Cell's ⊥? handlers are more principled — they
  allow local recovery without terminating the stream, and they compose within
  the dataflow graph rather than being ad-hoc operator chains.
- **How Cell differs**: Reactive streams collapse all failures into a single
  error channel. Cell's ⊥ is more nuanced — it participates in the lattice
  ordering, and ⊥? handlers can provide typed fallbacks. Reactive streams
  also lack the notion of "crystallization" (a soft error becoming a hard
  value).
- **Technique Cell could adopt**: The `retryWhen()` operator pattern — retry
  with backoff and predicate — could inform Cell's evolution loops where a
  soft cell retries LLM evaluation.

---

## 3. Three-Valued and Four-Valued Logic

### 3a. Stephen Cole Kleene — Strong Three-Valued Logic (1938)

- **Title**: "On Notation for Ordinal Numbers" / "Introduction to Metamathematics"
- **Authors**: Stephen Cole Kleene
- **Year**: 1938 / 1952
- **Key insight**: Introduced a three-valued logic with values {T, F, U}
  (unknown). The connectives AND, OR, NOT have truth tables where U
  propagates: T AND U = U, F AND U = F, T OR U = T, F OR U = U. This
  captures the behavior of partially defined predicates.
- **How Cell relates**: Kleene's U is semantically close to Cell's ⊥. The
  propagation rules for Kleene logic (U infects results unless the other
  operand is "strong enough" to determine the outcome) mirror how Cell's ⊥
  propagates through deterministic cells.
- **How Cell differs**: Cell generalizes beyond truth values to arbitrary data
  types. Cell's ⊥ is not "unknown truth" but "absent value." Cell's ⊥?
  handlers have no counterpart in Kleene logic.
- **Technique Cell could adopt**: Kleene's "strong" tables (where some
  operations can short-circuit around U) should inform Cell's ⊥ propagation
  rules. For boolean cells, `false AND ⊥ = false` and `true OR ⊥ = true`
  should be valid short-circuits.

### 3b. Jan Łukasiewicz — Three-Valued Logic (1920)

- **Title**: "O logice trojwartosciowej" (On Three-Valued Logic)
- **Authors**: Jan Łukasiewicz
- **Year**: 1920
- **Key insight**: First formal three-valued logic, with the third value
  representing "possible" or "indeterminate." Differs from Kleene in
  implication: "unknown → unknown" is TRUE (not unknown). This captures the
  intuition that an indeterminate statement trivially implies itself.
- **How Cell relates**: Łukasiewicz's treatment of the third value as
  "possible" rather than "unknown" resonates with Cell's soft cells — a soft
  cell's output is "possible but not yet crystallized." The implication
  difference matters for Cell's oracle (⊨) semantics.
- **Technique Cell could adopt**: Łukasiewicz implication could model the
  relationship between soft cell outputs — if both are uncertain, the
  implication between them is trivially satisfied, matching Cell's approach
  to evolving proofs.

### 3c. Nuel Belnap — Four-Valued Logic (1977)

- **Title**: "A Useful Four-Valued Logic"
- **Authors**: Nuel D. Belnap
- **Year**: 1977
- **Key insight**: Four truth values: True, False, Both (contradictory), Neither
  (no information). Organized as a bilattice with two orderings — a truth
  ordering (F ≤ T) and an information/knowledge ordering (Neither ≤ Both).
  Designed for question-answering systems receiving information from multiple
  possibly-contradictory sources.
- **How Cell relates**: This is deeply relevant to Cell. Cell's soft cells can
  produce uncertain outputs from LLMs, and multiple cells might give
  contradictory evidence. Belnap's logic provides a framework for handling
  this: a cell could be in state Neither (⊥, no value yet), True, False, or
  Both (contradictory evidence from different soft cells).
- **How Cell improves**: Cell adds crystallization — values move from Neither
  toward True/False as computation progresses. Belnap's logic is static;
  Cell's is dynamic and directional.
- **Technique Cell could adopt**: The bilattice structure with separate truth
  and information orderings could give Cell a formal framework for tracking
  both "what we know" and "how confident we are." The information ordering
  maps to crystallization progress.

### 3d. Melvin Fitting — Bilattices and Logic Programming (1991)

- **Title**: "Bilattices and the Semantics of Logic Programming"
- **Authors**: Melvin Fitting
- **Year**: 1991
- **Key insight**: Extended Belnap's four-valued logic to a general framework
  for logic programming using bilattices. Developed a fixed-point semantics
  for logic programs over arbitrary bilattice truth value spaces. The two
  orderings (truth and knowledge) allow separating "what is true" from "what
  we know."
- **How Cell relates**: Fitting's bilattice semantics is perhaps the closest
  existing formal framework to Cell's semantics. Logic programs with
  incomplete information map to Cell documents with pending soft cells.
  The fixed-point semantics aligns with Cell's Kahn-style evaluation.
- **Technique Cell could adopt**: Fitting's approach of using arbitrary
  bilattices (not just {T, F, Both, Neither}) as truth value spaces could
  let Cell define custom confidence lattices for different domains. The
  immediate consequence operator Φ_P could serve as a model for Cell's
  spawner.

---

## 4. SQL NULL Semantics

### 4a. E.F. Codd — NULL in the Relational Model (1979)

- **Title**: "Extending the Database Relational Model to Capture More Meaning"
- **Authors**: E.F. Codd
- **Year**: 1979 (building on 1975 FDT Bulletin paper)
- **Key insight**: Introduced NULL as a marker for missing data in relational
  databases. Any arithmetic with NULL produces NULL (NULL propagation).
  Comparisons with NULL produce UNKNOWN (three-valued logic). Only rows where
  the WHERE clause evaluates to TRUE are returned — UNKNOWN rows are excluded.
- **How Cell relates**: SQL's NULL propagation is the most widely deployed
  system of "bottom propagation" in computing. Cell's ⊥ is semantically
  similar but more principled. SQL NULL conflates "unknown," "inapplicable,"
  and "missing" — Codd himself later proposed distinguishing these. Cell
  could be more precise.
- **How Cell differs**: SQL NULL is famously problematic (NULL != NULL is not
  FALSE but UNKNOWN). Cell's ⊥ should avoid this trap — `⊥ == ⊥` should be
  ⊥ (not some third value), and ⊥? handlers provide clean recovery. Cell
  treats ⊥ as truly "no value" rather than SQL's ambiguous "might be a value."
- **Technique Cell could adopt**: The lesson from SQL is cautionary: distinguish
  different reasons for absence. Cell should consider multiple bottom values
  (⊥_timeout, ⊥_refused, ⊥_pending) or at least metadata on ⊥ explaining
  the cause.

### 4b. Franconi & Tessaris — On the Logic of SQL Nulls (2012)

- **Title**: "On the Logic of SQL Nulls"
- **Authors**: Enrico Franconi, Sergio Tessaris
- **Year**: 2012
- **Key insight**: Formalized SQL's null semantics and showed that SQL's
  three-valued logic for nulls is more complex than it appears — the
  interaction between NULL, aggregation, grouping, and quantification creates
  subtle semantic issues. Proposed cleaner formalizations.
- **How Cell relates**: Cell should learn from SQL's decades of null-related
  bugs. The key lesson is that ⊥ must interact cleanly with all language
  features, not just basic operations.
- **Technique Cell could adopt**: Their formal treatment of how NULLs interact
  with aggregation is relevant to Cell's collection operations over cell
  groups.

---

## 5. Option/Maybe Types and Monadic Error Handling

### 5a. Haskell — Maybe Monad

- **Title**: The Haskell Report / "A Fistful of Monads"
- **Authors**: Simon Peyton Jones, Philip Wadler, et al.
- **Year**: 1990 (Haskell 1.0), ongoing
- **Key insight**: `Maybe a = Nothing | Just a`. The bind operator (>>=)
  short-circuits on Nothing — if any step in a monadic chain produces Nothing,
  the whole chain produces Nothing. This is "bottom propagation" at the type
  level, but opt-in and explicit.
- **How Cell relates**: Cell's ⊥ propagation through hard cells is exactly
  Maybe-bind semantics. Cell's ⊥? handlers are analogous to `maybe` /
  `fromMaybe` (providing default values when Nothing is encountered).
- **How Cell differs**: Haskell's Maybe is explicitly threaded — the programmer
  writes monadic code. Cell's ⊥ propagation is implicit in the dataflow
  graph. This is arguably more natural for dataflow but requires clearer
  semantics about when ⊥ does and doesn't propagate.
- **Technique Cell could adopt**: The `Alternative` typeclass (`<|>`) which
  tries one computation and falls back to another on Nothing is a close match
  for Cell's ⊥? handlers and could inform their formal semantics.

### 5b. Rust — Option<T> and the ? Operator

- **Title**: The Rust Programming Language / std::option / Error Handling RFC
- **Authors**: Graydon Hoare, Rust community
- **Year**: 2010-present
- **Key insight**: `Option<T> = Some(T) | None`. The `?` operator propagates
  None (or Err) up the call stack — it's syntactic sugar for early return on
  absence. Rust eliminates null pointers entirely; all absence is explicit via
  Option/Result. The `?` operator on Option returns None to the caller if the
  value is None, otherwise extracts the inner value.
- **How Cell relates**: Rust's `?` is the closest existing syntax to Cell's ⊥
  propagation. In Rust, `?` on None causes the enclosing function to return
  None. In Cell, ⊥ on an input causes the cell to produce ⊥. The mechanism
  is strikingly similar but Cell operates at the dataflow level, not the
  function level.
- **How Cell differs**: Rust requires explicit `?` at each propagation point.
  Cell's propagation is automatic (unless ⊥? intercepts). Cell is more
  concise but potentially less explicit.
- **Technique Cell could adopt**: Rust's separation of `Option` (absence) from
  `Result` (error with reason) is a strong argument for Cell to carry error
  metadata with ⊥. Consider `⊥` vs `⊥(reason)`.

### 5c. Zig — Error Unions

- **Title**: Zig Language Reference / Error Handling Design
- **Authors**: Andrew Kelley, Zig community
- **Year**: 2016-present
- **Key insight**: Error unions (`!T`) combine a value type with an error set
  using `!` syntax. `try` propagates errors up the call stack. Error sets
  compose with `||`. Zig infers error sets automatically, and errors are
  checked at compile time. No hidden exceptions.
- **How Cell relates**: Zig's error unions are a potential model for Cell's ⊥
  carrying metadata — instead of a single ⊥, Cell could have typed ⊥ values
  where the "error set" indicates the cause (timeout, refusal, missing data).
- **Technique Cell could adopt**: Zig's error set composition (`||`) could
  inform how Cell composes ⊥ causes when multiple inputs to a cell are ⊥.

### 5d. Philip Wadler — Propositions as Types (2015)

- **Title**: "Propositions as Types"
- **Authors**: Philip Wadler
- **Year**: 2015
- **Key insight**: The Curry-Howard correspondence links types to propositions,
  programs to proofs, and evaluation to proof normalization. Sum types
  (A + B) correspond to disjunction; the unit type corresponds to truth; the
  empty type (Void/⊥) corresponds to falsity. Under Curry-Howard, Option<T>
  = T + 1 corresponds to "T or trivially true."
- **How Cell relates**: Cell's proof-carrying computation (oracle ⊨) is deeply
  connected to Curry-Howard. Cell's ⊥ as a type-level concept corresponds to
  logical falsity (ex falso quodlibet). The ⊥? handler corresponds to the
  logical principle of handling a disjunction — if the proof might be absent,
  provide an alternative.
- **Technique Cell could adopt**: Formalize Cell's ⊥ and ⊥? using
  Curry-Howard: a cell of type T actually has type T + ⊥, and ⊥? is the
  eliminator for this sum type.

---

## 6. Abstract Interpretation

### 6a. Cousot & Cousot — Abstract Interpretation (1977)

- **Title**: "Abstract Interpretation: A Unified Lattice Model for Static
  Analysis of Programs by Construction or Approximation of Fixpoints"
- **Authors**: Patrick Cousot, Radhia Cousot
- **Year**: 1977
- **Key insight**: Program properties can be computed by abstract
  interpretation over a lattice. Concrete semantics is related to abstract
  semantics by a Galois connection. The abstract domain forms a complete
  lattice with ⊥ (no information) at the bottom and ⊤ (all states possible)
  at the top. Fixed-point computation on the abstract lattice soundly
  approximates the concrete program behavior.
- **How Cell relates**: Cell's frozen set forms a lattice that is structurally
  similar to an abstract domain. Starting from ⊥ (nothing known) and
  computing upward toward concrete values is analogous to abstract
  interpretation narrowing toward precise values.
- **How Cell improves**: Abstract interpretation is purely static analysis.
  Cell performs this lattice-climbing *at runtime* through evaluation and
  crystallization.
- **Technique Cell could adopt**: Widening and narrowing operators from
  abstract interpretation could help Cell handle infinite ascending chains in
  evolution loops (⊢∘) — widening prevents infinite iteration by
  over-approximating, then narrowing recovers precision.

### 6b. Denning — Lattice Model for Information Flow (1976)

- **Title**: "A Lattice Model of Secure Information Flow"
- **Authors**: Dorothy E. Denning
- **Year**: 1976
- **Key insight**: Security classifications form a lattice. Information may
  flow from lower to higher security levels but not vice versa. This
  lattice-based model provides a mathematical framework for enforcing
  information flow policies.
- **How Cell relates**: Cell's dataflow graph has a natural information flow
  direction. The lattice model could inform Cell's trust model — soft cell
  outputs (lower confidence) should not silently flow into hard cell
  contexts (higher confidence) without explicit crystallization/verification.
- **Technique Cell could adopt**: Denning's noninterference property
  (high-security inputs cannot influence low-security outputs) could be
  adapted for Cell: unverified soft cell outputs should not influence
  verified hard cell outputs without going through the oracle (⊨).

---

## 7. Design Pattern Approaches

### 7a. Null Object Pattern / Special Case Pattern

- **Title**: "Null Object" pattern / Fowler's "Special Case" pattern
- **Authors**: Bobby Woolf (Null Object, 1996); Martin Fowler (Special Case,
  2002)
- **Year**: 1996 / 2002
- **Key insight**: Instead of returning null/None, return an object that
  implements the expected interface but with neutral/default behavior. This
  eliminates null checks and provides type-safe "absence." The Special Case
  pattern generalizes this to domain-specific absent/error objects.
- **How Cell relates**: Cell's ⊥? handlers are the dataflow equivalent of the
  Null Object pattern — they provide a concrete fallback value when ⊥ would
  otherwise propagate. The key difference is that Cell makes ⊥ explicit in
  the evaluation semantics rather than hiding it behind an interface.
- **Technique Cell could adopt**: The principle that absent values should
  implement the same interface as present values is powerful. Cell could
  ensure that ⊥ carrying metadata still participates in the type system
  uniformly.

---

## 8. Algebraic Effects and Effect Systems

### 8a. Algebraic Effects and Handlers

- **Title**: "Programming with Algebraic Effects and Handlers" / Eff language
- **Authors**: Andrej Bauer, Matija Pretnar (Eff); Daan Leijen (Koka);
  Gordon Plotkin, John Power (algebraic effects theory)
- **Year**: 2003 (theory), 2012 (Eff), 2014-present (Koka, OCaml effects)
- **Key insight**: Algebraic effects generalize exceptions, state, I/O, and
  other computational effects into a unified framework. Effect handlers are
  "resumable exceptions" — when an effect is performed, the handler can
  inspect it and optionally *resume* the computation with a value. This
  subsumes try/catch (exceptions = non-resumable effects) and provides
  composable effect management.
- **How Cell relates**: Cell's ⊥? handlers are conceptually algebraic effect
  handlers. When a cell encounters ⊥, it "performs" an absence effect; the
  ⊥? handler handles this effect by providing a fallback value and resuming
  computation. This framing gives Cell's ⊥? a rigorous theoretical basis.
- **How Cell differs**: Algebraic effect handlers are typically function-scoped.
  Cell's ⊥? handlers are cell-scoped and operate within a dataflow graph.
  Also, Cell's ⊥ is not "raised" by code but emerges from the topology of
  the dataflow graph.
- **Technique Cell could adopt**: The algebraic effects framework could let
  Cell define custom effect types beyond ⊥ — e.g., "low-confidence" as an
  effect that handlers can intercept and handle (retry, fallback, escalate
  to oracle). Effect handler composition rules would give Cell principled
  semantics for nested ⊥? handlers.

---

## 9. Game Semantics and Divergence

### 9a. Abramsky & McCusker — Game Semantics for PCF

- **Title**: "Game Semantics" / Full Abstraction for PCF
- **Authors**: Samson Abramsky, Guy McCusker (also Hyland & Ong independently)
- **Year**: 1990s
- **Key insight**: Programs are modeled as strategies in a two-player game
  between the Program and the Environment. Divergence (⊥) corresponds to the
  program "passing forever" — never making a move. This gave the first
  syntax-free fully abstract model for PCF, distinguishing programs that
  denotational semantics equated.
- **How Cell relates**: The game-semantics view of ⊥ as "never responds" maps
  well to Cell's LLM cells — a soft cell that never produces output is
  literally "not playing its turn." Game semantics could provide Cell with a
  compositional model that distinguishes between different kinds of silence.
- **Technique Cell could adopt**: Game semantics distinguishes deadlock
  (waiting for input that never comes) from divergence (infinite internal
  computation). Cell could similarly distinguish ⊥_blocked (waiting on
  upstream ⊥) from ⊥_timeout (LLM took too long) from ⊥_refused (LLM
  declined to answer).

---

## Summary Table

| System/Paper | Year | ⊥ Concept | Cell Connection |
|---|---|---|---|
| Scott domains | 1970s | Least element, nontermination | Direct ancestor of Cell's ⊥ |
| Plotkin PCF | 1977 | Divergence in typed λ-calculus | Pointed CPO per type = Cell's cell types |
| Knaster-Tarski | 1955 | Least fixed point existence | Guarantees Cell's evaluation converges |
| Kahn networks | 1974 | Blocking = no output | Cell adds explicit ⊥ as observable value |
| Kleene 3VL | 1938 | Unknown (U) propagation | Model for ⊥ in boolean cells |
| Łukasiewicz 3VL | 1920 | Indeterminate → indeterminate = T | Model for soft cell implication |
| Belnap 4VL | 1977 | Neither/Both + info ordering | Bilattice for Cell's confidence tracking |
| Fitting bilattices | 1991 | Generalized truth spaces for LP | Custom lattices per Cell domain |
| Codd SQL NULL | 1979 | Missing data propagation | Cautionary tale: distinguish ⊥ reasons |
| Haskell Maybe | 1990 | Nothing short-circuits bind | Direct model for ⊥ propagation |
| Rust Option/? | 2010s | Explicit propagation operator | Closest syntax analog to Cell's ⊥ |
| Zig error unions | 2016 | Typed errors + propagation | Model for ⊥ with metadata |
| Cousot AI | 1977 | Abstract lattice, ⊥ = no info | Cell as runtime abstract interpretation |
| Algebraic effects | 2003+ | Resumable exceptions | Theory for Cell's ⊥? handlers |
| Game semantics | 1990s | Silence = never plays | Distinguishes kinds of Cell ⊥ |
| Reactive streams | 2013+ | Terminal error propagation | Operator patterns for recovery |

---

## Key Recommendations for Cell

1. **Formalize ⊥ via pointed CPOs**: Every Cell type T should be formally
   treated as T_⊥ (T lifted with bottom), following Scott/Plotkin.

2. **Adopt bilattice structure from Belnap/Fitting**: Use separate truth and
   information orderings to track both "what value" and "how confident."

3. **Carry metadata on ⊥**: Learn from SQL's mistakes and Rust/Zig's design.
   Consider `⊥(cause)` where cause ∈ {timeout, refused, blocked, pending}.

4. **Define ⊥? as algebraic effect handler**: Frame the ⊥? handler using
   algebraic effects theory for composable, principled fallback semantics.

5. **Implement Kleene short-circuits**: For boolean cells, adopt Kleene's
   strong tables where one operand can determine the result despite ⊥ on
   the other.

6. **Use widening from abstract interpretation**: For evolution loops (⊢∘),
   widening prevents infinite iteration by over-approximating and then
   narrowing.

7. **Prove unique fixed point via Kahn**: Formalize that Cell's evaluation
   strategy computes the unique least fixed point of the dataflow network,
   leveraging Kahn's theorem.
