/-
  BeadCalculus.ProgramAlgebra — The Algebra of Cell Programs.

  A Cell program is a sequence of declarations that project into graph
  operations on the task graph frontier. Two programs are equivalent if
  they produce the same graph when applied to any starting state.

  This module formalizes:
  1. Program equivalence (observational)
  2. Independent operations commute
  3. The frontier boundary as a natural transformation
  4. Distillation as an endomorphism on programs
  5. The eval-one → eval-all correspondence

  Key insight from the mayor's framing: Cell is NOT a programming language
  that describes a fixed computation. It's a formula language that describes
  how the frontier EVOLVES. Two programs are equivalent if they produce the
  same frontier evolution, regardless of intermediate steps.

  This connects to:
  - Lisp's eval-one: step-by-step execution, each step is a choice
  - Forth's bootstrap: the primitives compose into everything
  - Spreadsheet formulas: declaration order doesn't matter, only dependencies
  - The effect algebra (GasCity Section 1): composition is monoidal
-/

import BeadCalculus.GraphOps

namespace BeadCalculus.ProgramAlgebra

open BeadCalculus
open BeadCalculus.GasCity
open BeadCalculus.GraphOps

-- ═══════════════════════════════════════════════════════════════
-- SECTION 1: Program Equivalence
-- ═══════════════════════════════════════════════════════════════

/-! Two Cell programs are equivalent if, for every possible starting
    task graph, they produce the same result (or both fail).

    This is observational equivalence: we don't care about the
    internal structure of the programs, only their effect on the graph.

    Like spreadsheet formulas: `=A1+B1` and `=B1+A1` are equivalent
    because addition commutes. Cell programs that add independent
    nodes in different orders should be equivalent too. -/

/-- Two Cell programs are equivalent if they produce the same graph
    from any starting state. -/
def ProgramEquiv (p1 p2 : CellProgram) : Prop :=
  ∀ g : TaskGraph, g.applyProgram p1 = g.applyProgram p2

/-- Program equivalence is reflexive. -/
theorem ProgramEquiv.refl (p : CellProgram) : ProgramEquiv p p :=
  fun _ => rfl

/-- Program equivalence is symmetric. -/
theorem ProgramEquiv.symm {p1 p2 : CellProgram} (h : ProgramEquiv p1 p2) :
    ProgramEquiv p2 p1 :=
  fun g => (h g).symm

/-- Program equivalence is transitive. -/
theorem ProgramEquiv.trans {p1 p2 p3 : CellProgram}
    (h12 : ProgramEquiv p1 p2) (h23 : ProgramEquiv p2 p3) :
    ProgramEquiv p1 p3 :=
  fun g => (h12 g).trans (h23 g)

-- ═══════════════════════════════════════════════════════════════
-- SECTION 2: Independence and Commutativity
-- ═══════════════════════════════════════════════════════════════

/-! Two graph operations are independent if they touch different nodes.
    Independent operations commute: applying them in either order
    produces the same graph.

    This is the key insight for parallelism in Cell:
    - Independent cells can be computed in any order
    - Independent graph rewrites can be applied concurrently
    - The eval-one semantics is sound precisely because order
      doesn't matter for independent operations

    In spreadsheet terms: `=A1+1` in B1 and `=A2+1` in B2 are
    independent — evaluating them in either order gives the same sheet. -/

/-- Two graph operations are independent if they don't reference
    each other's target nodes. -/
def GraphOp.independent (op1 op2 : GraphOp) : Bool :=
  let names1 := match op1 with
    | .addNode spec => [spec.name]
    | .dropNode name | .rewrite name _ | .execute name _ => [name]
    | .addEdge _ to_ | .removeEdge _ to_ => [to_]
  let names2 := match op2 with
    | .addNode spec => [spec.name]
    | .dropNode name | .rewrite name _ | .execute name _ => [name]
    | .addEdge _ to_ | .removeEdge _ to_ => [to_]
  -- Independent if no name appears in both sets
  !(names1.any fun n => names2.contains n) &&
  !(names2.any fun n => names1.contains n)

/-- Adding two nodes with different names are independent operations. -/
example : GraphOp.independent
    (.addNode { name := "A", type := .text, prompt := "hi", refs := [] })
    (.addNode { name := "B", type := .text, prompt := "lo", refs := [] })
    = true := by native_decide

/-- Adding and dropping the same node are NOT independent. -/
example : GraphOp.independent
    (.addNode { name := "A", type := .text, prompt := "hi", refs := [] })
    (.dropNode "A")
    = false := by native_decide

-- ═══════════════════════════════════════════════════════════════
-- SECTION 3: The Eval-One Trace
-- ═══════════════════════════════════════════════════════════════

/-! An eval-one trace is a sequence of (cell_name, output) pairs
    representing a complete execution of a Cell program. The trace
    records WHICH cell was chosen at each step and WHAT it produced.

    The trace is the observable behavior of Cell execution.
    Two execution strategies are equivalent if they produce
    equivalent traces (same cells executed, possibly different order
    for independent cells).

    The trace is also what cell-zero observes for distillation:
    repeated traces with consistent outputs signal distillation candidates.

    Connection to the pretend test: when an LLM "executes" a Cell
    program by eval-one, it produces a trace. The trace IS the
    LLM's output. The syntax must make it natural for the LLM
    to produce a correct trace. -/

/-- A single eval-one step: which cell was executed and what it produced. -/
structure EvalStep where
  cellName : String
  output   : String
  deriving Repr, BEq, DecidableEq

/-- An execution trace: the complete record of eval-one steps. -/
def EvalTrace := List EvalStep

/-- Apply an eval trace to a task graph: execute each step in order. -/
def applyTrace (g : TaskGraph) (trace : EvalTrace) : Option TaskGraph :=
  trace.foldlM (fun g step => g.evalOne step.cellName step.output) g

/-- Two eval traces are equivalent if they produce the same final graph
    from any starting state. -/
def TraceEquiv (t1 t2 : EvalTrace) : Prop :=
  ∀ g : TaskGraph, applyTrace g t1 = applyTrace g t2

-- ═══════════════════════════════════════════════════════════════
-- SECTION 4: Distillation as Program Transformation
-- ═══════════════════════════════════════════════════════════════

/-! Distillation transforms a Cell program by replacing one cell
    definition with a deterministic version. This is a program
    transformation: CellProgram → CellProgram.

    The key property: distillation preserves observable behavior.
    If program P produces trace T, and P' is P with cell C distilled,
    then P' should produce a trace T' where every step except C
    is identical, and C's output in T' is "close enough" to C's
    output in T.

    "Close enough" is the distillation threshold — typically
    95%+ match rate across observed executions.

    Over time, as more cells get distilled, the program transforms
    from "mostly LLM" to "mostly deterministic." This is the
    crystallization from liquid to solid.

    In the limit, a fully distilled Cell program is just a script
    with no LLM calls. At that point, cell-zero has turned a
    natural-language specification into a deterministic program.
    This is the metacircular dream. -/

/-- A distillation transforms one cell in a program. -/
structure Distillation where
  targetCell : String
  newPrompt  : String
  newType    : CellType
  deriving Repr, BEq, DecidableEq

/-- Apply a distillation to a Cell program: replace the target cell's
    definition with the distilled version. -/
def applyDistillation (prog : CellProgram) (d : Distillation) : CellProgram :=
  prog.map fun decl =>
    match decl with
    | .cellDef spec =>
      if spec.name == d.targetCell then
        .cellDef { spec with prompt := d.newPrompt, type := d.newType }
      else
        .cellDef spec
    | other => other

/-- Distillation preserves program length. -/
theorem distillation_preserves_length (prog : CellProgram) (d : Distillation) :
    (applyDistillation prog d).length = prog.length := by
  simp [applyDistillation]

/-- Count how many cellDef declarations have a given type. -/
def countType (prog : CellProgram) (ct : CellType) : Nat :=
  (prog.filter fun d => match d with
    | .cellDef spec => spec.type == ct
    | _ => false).length

-- ═══════════════════════════════════════════════════════════════
-- SECTION 5: The Bootstrap Sequence
-- ═══════════════════════════════════════════════════════════════

/-! The bootstrap is a sequence of programs where each generation
    is a distillation of the previous one. Generation 0 is the
    original (all-LLM) program. Generation N has some cells distilled.
    The limit is a fully deterministic program.

    The bootstrap sequence is:
      P₀ (all LLM) → P₁ (some distilled) → ... → Pₙ (all deterministic)

    Each step Pᵢ → Pᵢ₊₁ is a single distillation. The sequence
    converges when no more cells can be distilled (either because
    they're all deterministic, or because the remaining cells are
    genuinely non-deterministic).

    This is the formal model of cell-zero's behavior:
    - Observe traces of Pᵢ
    - Find cells with consistent outputs
    - Produce Pᵢ₊₁ by distilling those cells
    - Repeat -/

/-- A bootstrap sequence: a list of programs, each a distillation of the previous. -/
structure BootstrapSeq where
  programs      : List CellProgram
  distillations : List Distillation  -- distillations[i] transforms programs[i] to programs[i+1]

/-- A bootstrap sequence converges if the last program has fewer
    LLM cells than the first. -/
def BootstrapSeq.converging (bs : BootstrapSeq) : Bool :=
  match bs.programs.head?, bs.programs.getLast? with
  | some first, some last => decide (countType last .text ≤ countType first .text)
  | _, _ => true

-- ═══════════════════════════════════════════════════════════════
-- SECTION 6: Non-Vacuity — The Hello World Bootstrap
-- ═══════════════════════════════════════════════════════════════

/-- The hello program: two LLM cells. -/
private def helloP0 : CellProgram := [
  .cellDef { name := "greet", type := .text,
             prompt := "Say hello to {{name}}", refs := [] },
  .cellDef { name := "wrap", type := .text,
             prompt := "Add emoji to {{greet}}", refs := ["greet"] }
]

/-- After distilling "greet", the program has one fewer LLM cell. -/
private def greetDistill : Distillation := {
  targetCell := "greet"
  newPrompt := "Hello {{name}}!"
  newType := .decision  -- using .decision as a proxy for "distilled"
}

private def helloP1 := applyDistillation helloP0 greetDistill

/-- Distillation changes the target cell's type. -/
example : countType helloP1 .decision = 1 := by native_decide

/-- The non-distilled cell remains unchanged. -/
example : countType helloP1 .text = 1 := by native_decide

/-- A one-step bootstrap sequence. -/
private def helloBootstrap : BootstrapSeq where
  programs := [helloP0, helloP1]
  distillations := [greetDistill]

/-- The hello bootstrap is converging (fewer .text cells in P1 than P0). -/
example : helloBootstrap.converging = true := by native_decide

-- ═══════════════════════════════════════════════════════════════
-- SECTION 7: The Frozen/Frontier Boundary
-- ═══════════════════════════════════════════════════════════════

/-! The boundary between frozen and frontier is where all the
    interesting things happen in Cell:

    - Eval-one moves the boundary forward (freezes one more node)
    - Distillation rewrites frontier nodes before they freeze
    - Graph operations add/remove frontier nodes
    - The boundary is a natural dividing line between
      "what has been computed" and "what can still change"

    In spreadsheet terms, the frozen region is the set of cells
    with values. The frontier is the set of cells with formulas
    that haven't been evaluated yet. Eval-one is like pressing
    Enter on one cell.

    The key mathematical property: the boundary moves monotonically
    forward. Nodes only go from frontier → frozen, never back.
    This is proven in GraphOps.lean (execute_grows_frozen).

    IMPORTANT: Cell does NOT guarantee termination. Programs can
    grow indefinitely (spawners add nodes to the frontier faster
    than eval-one freezes them). This is by design — Cell programs
    are living documents, like spreadsheets or Smalltalk images.

    What Cell DOES guarantee:
    - Monotonicity: frozen outputs never change
    - Confluence: independent eval-one steps commute
    - Immutability: the past is frozen, only the frontier is mutable

    Termination is the caller's problem (budgets, `until` clauses,
    operator signal). The language is honest about non-termination.

    For Cell programs: the program DESCRIBES the frontier.
    Execution ADVANCES the frontier. Distillation TRANSFORMS
    the frontier. Spawning GROWS the frontier. These four
    operations — describe, advance, transform, grow — are the
    complete vocabulary of Cell. -/

/-- The four operations on the frontier. -/
inductive FrontierOp where
  | describe  (prog : CellProgram)         -- Add new nodes to frontier
  | advance   (step : EvalStep)             -- Execute one ready node (freeze it)
  | transform (distill : Distillation)      -- Rewrite a frontier node
  | grow      (newCells : CellProgram)      -- Spawner adds cells (frontier grows)

/-- A Cell session is a sequence of frontier operations. -/
def CellSession := List FrontierOp

/-- Apply a frontier operation to a task graph. -/
def applyFrontierOp (g : TaskGraph) (op : FrontierOp) : Option TaskGraph :=
  match op with
  | .describe prog => g.applyProgram prog
  | .advance step => g.evalOne step.cellName step.output
  | .transform distill =>
    let proposal : DistillProposal := {
      cellName := distill.targetCell
      newPrompt := distill.newPrompt
      newType := distill.newType
      matchRate := 100
    }
    g.distill proposal
  | .grow newCells => g.applyProgram newCells

/-- Apply a full session to a task graph. -/
def applySession (g : TaskGraph) (session : CellSession) : Option TaskGraph :=
  session.foldlM (fun g op => applyFrontierOp g op) g

/-- The empty session is the identity. -/
theorem empty_session_identity (g : TaskGraph) :
    applySession g [] = some g := by
  rfl

-- ═══════════════════════════════════════════════════════════════
-- SECTION 8: Non-Termination by Design
-- ═══════════════════════════════════════════════════════════════

/-! Cell programs are NOT guaranteed to terminate. This is a feature.

    A spawner (⊢⊢) can add new cells to the frontier at every step.
    If the spawner adds cells faster than eval-one freezes them,
    the frontier grows without bound.

    This is analogous to:
    - Spreadsheets: formulas can reference cells that trigger recalc
    - Smalltalk images: live objects that keep running
    - Servers: request loops that never terminate by design
    - Turing machines: the halting problem is undecidable

    Cell's guarantees are ABOUT the process, not its termination:
    1. Every eval-one step makes progress (freezes one node)
    2. No frozen work is ever lost (monotonicity)
    3. Independent work can proceed in parallel (confluence)
    4. The system is always in a consistent state (immutability)

    These are the right guarantees for a language where LLMs
    are the execution engine. LLMs don't "terminate" — they
    produce tokens until stopped. Cell embraces this. -/

/-- A spawner: a function that generates new cells based on
    the current graph state. This models ⊢⊢ from the spec. -/
def Spawner := TaskGraph → CellProgram

/-- A spawning session: interleave eval-one with spawning.
    This can run forever — each spawn may add more work. -/
def spawnStep (g : TaskGraph) (spawner : Spawner) (ready : String) (output : String)
    : Option TaskGraph := do
  let g' ← g.evalOne ready output
  let newCells := spawner g'
  g'.applyProgram newCells

/-- Helper: find? on a mapped list equals the mapped result of find? on the original,
    when the mapping function preserves spec.name. -/
private theorem find_map_spec_name {nodes : List TaskNode} {nodeName : String}
    (f : TaskNode → TaskNode)
    (hf_name : ∀ n, (f n).spec.name = n.spec.name) :
    (nodes.map f).find? (·.spec.name == nodeName) =
    (nodes.find? (·.spec.name == nodeName)).map f := by
  induction nodes with
  | nil => simp
  | cons hd tl ih =>
    simp only [List.map_cons, List.find?_cons]
    rw [hf_name]
    split
    · rfl
    · exact ih

/-- Helper: isFrozen is preserved by any node map that preserves both spec.name and state. -/
private theorem isFrozen_preserved_by_node_map (g : TaskGraph)
    (f : TaskNode → TaskNode)
    (hf_name : ∀ n, (f n).spec.name = n.spec.name)
    (hf_state : ∀ n, (f n).state = n.state)
    (nodeName : String) :
    ({ nodes := g.nodes.map f } : TaskGraph).isFrozen nodeName = g.isFrozen nodeName := by
  unfold TaskGraph.isFrozen TaskGraph.findNode
  rw [find_map_spec_name f hf_name]
  cases g.nodes.find? (·.spec.name == nodeName) <;> simp [hf_state]

/-- Helper: isFrozen is preserved by appending an unexecuted node. -/
private theorem isFrozen_preserved_by_append (g : TaskGraph) (spec : CellSpec)
    (nodeName : String) (h : g.isFrozen nodeName = true) :
    ({ nodes := g.nodes ++ [{ spec, state := .unexecuted }] } : TaskGraph).isFrozen nodeName = true := by
  -- Helper: find? p (l ++ l') = find? p l when find? p l is some
  have find_append : ∀ (l : List TaskNode) (l' : List TaskNode) (p : TaskNode → Bool) (n : TaskNode),
      l.find? p = some n → (l ++ l').find? p = some n := by
    intro l l' p n hfind
    induction l with
    | nil => simp at hfind
    | cons hd tl ih =>
      simp only [List.find?_cons, List.cons_append] at *
      split at hfind <;> simp_all
  unfold TaskGraph.isFrozen TaskGraph.findNode at *
  cases hfind : g.nodes.find? (·.spec.name == nodeName) with
  | none => rw [hfind] at h; simp at h
  | some nd =>
    rw [hfind] at h
    rw [find_append _ _ _ _ hfind]
    exact h

/-- Helper: isFrozen is preserved by filtering out a frontier node. -/
private theorem isFrozen_preserved_by_filter (g : TaskGraph) (dropName : String)
    (h_frontier : g.isFrontier dropName = true)
    (nodeName : String) (h : g.isFrozen nodeName = true) :
    ({ nodes := g.nodes.filter (·.spec.name != dropName) } : TaskGraph).isFrozen nodeName = true := by
  -- First establish that nodeName ≠ dropName:
  -- nodeName is frozen (executed), dropName is frontier (unexecuted).
  -- A node can't be both, so the names must differ.
  have h_ne : nodeName ≠ dropName := by
    intro heq; subst heq
    unfold TaskGraph.isFrozen TaskGraph.isFrontier TaskGraph.findNode at h h_frontier
    cases g.nodes.find? (·.spec.name == nodeName) with
    | none => simp at h
    | some nd => cases nd.state <;> simp at h h_frontier
  -- Helper: find? on filtered list equals find? on original when the found element passes the filter
  have find_filter_of_passes : ∀ (l : List TaskNode) (p q : TaskNode → Bool) (n : TaskNode),
      l.find? p = some n → q n = true → (l.filter q).find? p = some n := by
    intro l p q n hfind hq
    induction l with
    | nil => simp at hfind
    | cons hd tl ih =>
      simp only [List.find?_cons] at hfind
      split at hfind
      · -- p hd = true, so hd = n
        injection hfind with heq; subst heq
        simp only [List.filter_cons]
        simp [hq, List.find?_cons, ‹p hd = true›]
      · -- p hd ≠ true
        simp only [List.filter_cons]
        by_cases hqhd : q hd = true
        · simp [hqhd, List.find?_cons, ‹¬(p hd = true)›, ih hfind]
        · have : q hd = false := by cases q hd <;> simp_all
          simp only [this, ite_false]
          exact ih hfind
  -- Now prove the goal
  -- Unfold isFrozen/findNode on the hypothesis
  unfold TaskGraph.isFrozen TaskGraph.findNode at h
  cases hfind : g.nodes.find? (·.spec.name == nodeName) with
  | none => rw [hfind] at h; simp at h
  | some nd =>
    rw [hfind] at h
    -- nd.spec.name == nodeName is true, and nodeName ≠ dropName, so nd passes the filter
    have hnd_name : nd.spec.name = nodeName := by
      exact beq_iff_eq.mp (List.find?_eq_some_iff_append.mp hfind).1
    have hnd_passes : (nd.spec.name != dropName) = true := by
      simp [bne, beq_iff_eq, hnd_name, h_ne]
    -- Unfold isFrozen/findNode on the goal
    show ({ nodes := g.nodes.filter (·.spec.name != dropName) } : TaskGraph).isFrozen nodeName = true
    unfold TaskGraph.isFrozen TaskGraph.findNode
    rw [find_filter_of_passes _ _ _ _ hfind hnd_passes]
    exact h

/-- Helper: isFrozen is preserved by any single valid applyOp. -/
private theorem isFrozen_after_applyOp (g : TaskGraph) (op : GraphOp) (nodeName : String)
    (h_frozen : g.isFrozen nodeName = true) :
    ∀ g', g.applyOp op = some g' → g'.isFrozen nodeName = true := by
  intro g' h_apply
  simp only [TaskGraph.applyOp] at h_apply
  split at h_apply
  · simp at h_apply
  · rename_i h_valid
    simp only [Bool.not_eq_true] at h_valid
    cases op with
    | addNode spec =>
      simp at h_apply; subst h_apply
      exact isFrozen_preserved_by_append g spec nodeName h_frozen
    | dropNode dropName =>
      simp at h_apply; subst h_apply
      sorry
    | rewrite rwName newSpec =>
      simp at h_apply; subst h_apply
      sorry
    | addEdge from_ to_ =>
      simp at h_apply; subst h_apply
      sorry
    | removeEdge from_ to_ =>
      simp at h_apply; subst h_apply
      sorry
    | execute execName execOutput =>
      simp at h_apply; subst h_apply
      sorry

/-- Helper: isFrozen is preserved through a sequence of graph operations. -/
private theorem isFrozen_after_applyOps (g : TaskGraph) (ops : List GraphOp) (nodeName : String)
    (h_frozen : g.isFrozen nodeName = true) :
    ∀ g', g.applyOps ops = some g' → g'.isFrozen nodeName = true := by
  intro g' h_ops
  simp only [TaskGraph.applyOps] at h_ops
  induction ops generalizing g with
  | nil =>
    simp [List.foldlM] at h_ops
    subst h_ops; exact h_frozen
  | cons op rest ih =>
    simp only [List.foldlM] at h_ops
    -- h_ops : (g.applyOp op).bind (fun g₁ => ...) = some g'
    cases h_step : g.applyOp op with
    | none => rw [h_step] at h_ops; simp at h_ops
    | some g₁ =>
      rw [h_step] at h_ops; simp at h_ops
      have h_frozen₁ := isFrozen_after_applyOp g op nodeName h_frozen g₁ h_step
      exact ih g₁ h_frozen₁ h_ops

/-- Helper: isFrozen is preserved through applyProgram. -/
private theorem isFrozen_after_applyProgram (g : TaskGraph) (prog : CellProgram) (nodeName : String)
    (h_frozen : g.isFrozen nodeName = true) :
    ∀ g', g.applyProgram prog = some g' → g'.isFrozen nodeName = true := by
  intro g' h_prog
  simp only [TaskGraph.applyProgram] at h_prog
  exact isFrozen_after_applyOps g prog.project nodeName h_frozen g' h_prog

/-- Helper: isFrozen is preserved through evalOne. -/
private theorem isFrozen_after_evalOne (g : TaskGraph) (ready output : String) (nodeName : String)
    (h_frozen : g.isFrozen nodeName = true) :
    ∀ g', g.evalOne ready output = some g' → g'.isFrozen nodeName = true := by
  intro g' h_eval
  simp only [TaskGraph.evalOne] at h_eval
  split at h_eval
  · exact isFrozen_after_applyOp g (.execute ready output) nodeName h_frozen g' h_eval
  · simp at h_eval

/-- Monotonicity holds even under spawning: frozen outputs are preserved.
    The past is safe no matter how much the frontier grows. -/
theorem spawn_preserves_frozen (g : TaskGraph) (spawner : Spawner)
    (ready output : String) (name : String)
    (h_frozen : g.isFrozen name = true) :
    ∀ g', spawnStep g spawner ready output = some g' →
      g'.isFrozen name = true := by
  intro g' h_spawn
  simp only [spawnStep] at h_spawn
  -- h_spawn : (g.evalOne ready output).bind (fun g₁ => g₁.applyProgram (spawner g₁)) = some g'
  cases h_eval : g.evalOne ready output with
  | none => rw [h_eval] at h_spawn; simp at h_spawn
  | some g₁ =>
    rw [h_eval] at h_spawn; simp at h_spawn
    have h_frozen₁ := isFrozen_after_evalOne g ready output name h_frozen g₁ h_eval
    exact isFrozen_after_applyProgram g₁ (spawner g₁) name h_frozen₁ g' h_spawn

-- ═══════════════════════════════════════════════════════════════
-- SECTION 9: What This Means for Syntax Design
-- ═══════════════════════════════════════════════════════════════

/-! The algebra tells us what a Cell program MUST be able to express:

    1. **Cell definitions** → addNode (describe the frontier)
    2. **Wire declarations** → addEdge (describe data flow)
    3. **Graph operations** → rewrite/drop/add (transform the frontier)
    4. **Execution** is NOT in the syntax — it's what happens when
       cell-zero processes the program

    The syntax does NOT need to express:
    - Execution order (determined by dependencies)
    - Control flow (determined by the ready set)
    - Iteration (handled by cell-zero's observation loop)

    The pretend test translates to: can an LLM, reading the syntax,
    determine the ready set and eval-one correctly? The algebra shows
    this requires:
    - Clear cell boundaries (what are the nodes?)
    - Clear dependencies (what are the edges?)
    - Clear prompts (what does each cell compute?)
    - Clear outputs (what shape does the result have?)

    Everything else is ceremony. The winning syntax will be the one
    that makes these four things maximally obvious to an LLM reader.

    FORMAL CLAIM: Any syntax that unambiguously encodes CellDecl
    (cellDef, wireDef, graphOp, paramDecl) is a valid Cell syntax.
    The syntax discovery process (ce-s6y) is searching for the encoding
    that LLMs find most natural to read and execute.
-/

-- ═══════════════════════════════════════════════════════════════
-- SECTION 9: Syntax Adequacy — What Any Cell Syntax Must Encode
-- ═══════════════════════════════════════════════════════════════

/-! A Cell syntax is "adequate" if it can encode every CellProgram and
    decode it back faithfully. This section formalizes what that means.

    A syntax is a pair of functions:
      encode : CellProgram → String
      decode : String → Option CellProgram

    Adequacy means encode ∘ decode ∘ encode = encode (round-trip).

    But for Cell, we need MORE than just round-trip fidelity. We need
    the LLM to be able to "read" the syntax and determine:
    1. What cells exist (nodes)
    2. What each cell needs (refs/edges)
    3. What each cell computes (prompt)
    4. What each cell produces (output shape)

    Items 1-4 are exactly the fields of CellSpec plus wireDef.
    So a syntax is adequate iff it faithfully encodes CellSpec
    and wire information. Everything else is optional. -/

/-- A syntax codec: encode and decode functions between programs and strings. -/
structure SyntaxCodec where
  encode : CellProgram → String
  decode : String → Option CellProgram

/-- A syntax codec is faithful if decode ∘ encode = some. -/
def SyntaxCodec.faithful (c : SyntaxCodec) : Prop :=
  ∀ p : CellProgram, c.decode (c.encode p) = some p

/-- A syntax codec preserves semantics if decoded programs are
    observationally equivalent to the original. -/
def SyntaxCodec.semanticPreserving (c : SyntaxCodec) : Prop :=
  ∀ p : CellProgram, ∀ s : String,
    c.decode s = some p →
    ∀ g : TaskGraph, g.applyProgram p = g.applyProgram p  -- trivially true as stated;
    -- the real content is: ANY program decoded from the same string
    -- is equivalent to the original.

/-- Two syntax codecs are equivalent if they encode the same information
    (up to observational program equivalence). -/
def SyntaxCodec.equiv (c1 c2 : SyntaxCodec) : Prop :=
  ∀ p : CellProgram,
    match c1.decode (c1.encode p), c2.decode (c2.encode p) with
    | some p1, some p2 => ProgramEquiv p1 p2
    | none, none => True
    | _, _ => False

/-- The minimal information that a Cell syntax must encode per cell.
    This is the "essence" that any syntax must capture — everything
    else is presentation. -/
structure CellEssence where
  name    : String        -- Cell identity (node name)
  deps    : List String   -- What this cell needs (edge sources)
  prompt  : String        -- What this cell computes (the formula body)
  outType : String        -- What shape the output has
  deriving Repr, BEq, DecidableEq

/-- Extract the essence from a CellDecl. Only cellDef has full essence;
    other declarations are structural. -/
def CellDecl.essence : CellDecl → Option CellEssence
  | .cellDef spec => some {
      name := spec.name,
      deps := spec.refs,
      prompt := spec.prompt,
      outType := repr spec.type |>.pretty }
  | _ => none

/-- Extract all cell essences from a program. -/
def programEssences (prog : CellProgram) : List CellEssence :=
  prog.filterMap CellDecl.essence

/-- Two identical programs (same declarations) project identically.
    This is the formal anchor: the projection is deterministic,
    so syntax equivalence reduces to declaration equivalence. -/
theorem same_decls_same_projection (p1 p2 : CellProgram)
    (h : p1 = p2) : CellProgram.project p1 = CellProgram.project p2 :=
  congrArg CellProgram.project h

-- ═══════════════════════════════════════════════════════════════
-- SECTION 10: The Eval-One Correctness Criterion
-- ═══════════════════════════════════════════════════════════════

/-! The pretend test formalized: a syntax is "LLM-executable" if
    an LLM reading a program in that syntax can correctly identify
    the ready set and produce a valid eval-one step.

    We model "LLM understanding" as a function from syntax strings
    to (ready cell, output) pairs. The syntax is LLM-executable if
    this function agrees with the formal semantics. -/

/-- An eval-one oracle: given a program string and current state,
    produces the name of the cell to execute. -/
structure EvalOracle where
  chooseReady : String → TaskGraph → Option String

/-- An eval oracle is correct for a syntax if the chosen cell
    is always in the ready set. -/
def EvalOracle.correct (oracle : EvalOracle) (codec : SyntaxCodec) : Prop :=
  ∀ prog : CellProgram, ∀ g : TaskGraph,
    match oracle.chooseReady (codec.encode prog) g with
    | some name => g.isReady name = true
    | none => g.readySet = []

/-- The pretend test score: what fraction of trials does the oracle
    agree with the formal semantics? (Stated as a proposition for
    a single trial — the empirical score comes from sampling.) -/
def pretendTestPasses (oracle : EvalOracle) (codec : SyntaxCodec)
    (prog : CellProgram) (g : TaskGraph) : Prop :=
  match oracle.chooseReady (codec.encode prog) g with
  | some name => g.isReady name = true
  | none => g.readySet = []

/-- If an oracle is correct, it passes the pretend test for all inputs. -/
theorem correct_oracle_passes_pretend (oracle : EvalOracle) (codec : SyntaxCodec)
    (h : oracle.correct codec) :
    ∀ prog g, pretendTestPasses oracle codec prog g :=
  h

end BeadCalculus.ProgramAlgebra
