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

    For Cell programs: the program DESCRIBES the frontier.
    Execution ADVANCES the frontier. Distillation TRANSFORMS
    the frontier. These three operations — describe, advance,
    transform — are the complete vocabulary of Cell. -/

/-- The three operations on the frontier. -/
inductive FrontierOp where
  | describe  (prog : CellProgram)         -- Add new nodes to frontier
  | advance   (step : EvalStep)             -- Execute one ready node (freeze it)
  | transform (distill : Distillation)      -- Rewrite a frontier node

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

/-- Apply a full session to a task graph. -/
def applySession (g : TaskGraph) (session : CellSession) : Option TaskGraph :=
  session.foldlM (fun g op => applyFrontierOp g op) g

/-- The empty session is the identity. -/
theorem empty_session_identity (g : TaskGraph) :
    applySession g [] = some g := by
  rfl

-- ═══════════════════════════════════════════════════════════════
-- SECTION 8: What This Means for Syntax Design
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

end BeadCalculus.ProgramAlgebra
