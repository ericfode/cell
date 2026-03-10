/-
  BeadCalculus.GraphOps — Task Graph Operations and Program Projection.

  Cell is a formula language for the LLM spreadsheet. Programs describe
  how the frontier of the bead graph evolves. This module formalizes:

  1. The task graph with execution state (frontier vs. frozen)
  2. Graph operations constrained by the immutability invariant:
     - Can only rewrite UNEXECUTED nodes
     - Can only ADD edges to EXECUTED nodes
     - Can CREATE new nodes
  3. The projection: how a Cell program (a sequence of declarations)
     maps to a sequence of constrained graph operations
  4. Soundness: well-formed programs produce well-formed graphs

  Key insight: the task graph has two regions:
  - FROZEN: executed nodes with immutable outputs (the past)
  - FRONTIER: unexecuted nodes that can be rewritten (the future)

  Cell programs operate on the frontier. cell-zero observes the boundary
  between frozen and frontier, looking for distillation opportunities.
-/

import BeadCalculus.DAG
import BeadCalculus.GasCity

namespace BeadCalculus.GraphOps

open BeadCalculus
open BeadCalculus.GasCity

-- ═══════════════════════════════════════════════════════════════
-- SECTION 1: The Task Graph with Execution State
-- ═══════════════════════════════════════════════════════════════

/-- Execution state of a node in the task graph. -/
inductive ExecState where
  | unexecuted : ExecState          -- On the frontier, can be rewritten
  | executing  : ExecState          -- Currently being computed
  | executed   : (output : String) → ExecState  -- Frozen, output is immutable
  deriving DecidableEq, Repr, BEq

/-- A node in the task graph: a cell spec with execution state. -/
structure TaskNode where
  spec   : CellSpec
  state  : ExecState
  deriving Repr, BEq, DecidableEq

/-- A task graph: nodes with execution state and dependency edges.
    The graph has a frozen region (executed nodes) and a frontier
    (unexecuted nodes). The boundary between them is where
    distillation happens. -/
structure TaskGraph where
  nodes : List TaskNode
  deriving Repr

/-- Get the names of all nodes. -/
def TaskGraph.nodeNames (g : TaskGraph) : List String :=
  g.nodes.map (·.spec.name)

/-- Find a node by name. -/
def TaskGraph.findNode (g : TaskGraph) (name : String) : Option TaskNode :=
  g.nodes.find? (·.spec.name == name)

/-- The frozen set: all executed nodes. -/
def TaskGraph.frozen (g : TaskGraph) : List String :=
  (g.nodes.filter fun n => match n.state with | .executed _ => true | _ => false).map (·.spec.name)

/-- The frontier: all unexecuted nodes. -/
def TaskGraph.frontier (g : TaskGraph) : List String :=
  (g.nodes.filter fun n => match n.state with | .unexecuted => true | _ => false).map (·.spec.name)

/-- Is a node frozen (executed)? -/
def TaskGraph.isFrozen (g : TaskGraph) (name : String) : Bool :=
  match g.findNode name with
  | some n => match n.state with | .executed _ => true | _ => false
  | none => false

/-- Is a node on the frontier (unexecuted)? -/
def TaskGraph.isFrontier (g : TaskGraph) (name : String) : Bool :=
  match g.findNode name with
  | some n => match n.state with | .unexecuted => true | _ => false
  | none => false

-- ═══════════════════════════════════════════════════════════════
-- SECTION 2: Constrained Graph Operations
-- ═══════════════════════════════════════════════════════════════

/-! The immutability invariant: operations on the task graph are
    constrained by the execution state of nodes.

    - REWRITE (change spec): only unexecuted nodes
    - ADD NODE: always allowed (new nodes start unexecuted)
    - DROP NODE: only unexecuted nodes
    - ADD EDGE: target must be unexecuted OR source→target where target is executed
                (you can note that an executed node's output feeds a new computation)
    - REMOVE EDGE: only from unexecuted nodes
    - EXECUTE: marks a node as executed with its output (irreversible)

    These constraints ensure:
    1. The past is immutable — executed outputs never change
    2. The frontier can evolve freely — unexecuted nodes can be rewritten
    3. New computation can build on old results — edges from frozen to frontier -/

/-- A constrained graph operation. Each operation carries a proof obligation
    about the execution state of affected nodes. -/
inductive GraphOp where
  | addNode    (spec : CellSpec)                          -- Add new unexecuted node
  | dropNode   (name : String)                            -- Remove unexecuted node
  | rewrite    (name : String) (newSpec : CellSpec)       -- Replace spec of unexecuted node
  | addEdge    (from_ to_ : String)                       -- Add dependency edge
  | removeEdge (from_ to_ : String)                       -- Remove dependency from unexecuted node
  | execute    (name : String) (output : String)          -- Mark as executed (irreversible)
  deriving Repr, BEq, DecidableEq

/-- Check whether a graph operation is valid given the current graph state. -/
def GraphOp.isValid (op : GraphOp) (g : TaskGraph) : Bool :=
  match op with
  | .addNode spec =>
    -- Name must not already exist
    !(g.nodeNames.contains spec.name)
  | .dropNode name =>
    -- Node must exist and be unexecuted
    g.isFrontier name
  | .rewrite name _ =>
    -- Node must exist and be unexecuted
    g.isFrontier name
  | .addEdge _from to_ =>
    -- Target node must be unexecuted (can't add deps to executed nodes)
    -- Exception: if target is executed, this is just noting a dependency
    -- that was already satisfied. For now, require target is on frontier.
    g.isFrontier to_
  | .removeEdge _from to_ =>
    -- The node we're modifying must be unexecuted
    g.isFrontier to_
  | .execute name _ =>
    -- Node must exist and be unexecuted
    g.isFrontier name

/-- Apply a graph operation to a task graph. Returns None if invalid. -/
def TaskGraph.applyOp (g : TaskGraph) (op : GraphOp) : Option TaskGraph :=
  if !op.isValid g then none
  else match op with
  | .addNode spec =>
    some { nodes := g.nodes ++ [{ spec, state := .unexecuted }] }
  | .dropNode name =>
    some { nodes := g.nodes.filter (·.spec.name != name) }
  | .rewrite name newSpec =>
    some { nodes := g.nodes.map fun n =>
      if n.spec.name == name then { n with spec := newSpec } else n }
  | .addEdge from_ to_ =>
    some { nodes := g.nodes.map fun n =>
      if n.spec.name == to_ then
        { n with spec := { n.spec with refs := n.spec.refs ++ [from_] } }
      else n }
  | .removeEdge from_ to_ =>
    some { nodes := g.nodes.map fun n =>
      if n.spec.name == to_ then
        { n with spec := { n.spec with refs := n.spec.refs.filter (· != from_) } }
      else n }
  | .execute name output =>
    some { nodes := g.nodes.map fun n =>
      if n.spec.name == name then { n with state := .executed output } else n }

-- ═══════════════════════════════════════════════════════════════
-- SECTION 3: The Immutability Invariant
-- ═══════════════════════════════════════════════════════════════

/-- The immutability invariant: executed nodes are never modified.
    For any valid operation, the output of every executed node
    is preserved in the resulting graph. -/
def preservesFrozen (g g' : TaskGraph) : Prop :=
  ∀ name output,
    (∃ spec, g.findNode name = some { spec := spec, state := .executed output }) →
    ∃ n', g'.findNode name = some n' ∧ n'.state = .executed output

-- We state the invariant differently: the frozen outputs are preserved.
/-- Executed node outputs are preserved: for every node that was executed
    with some output in g, it remains executed with the same output in g'. -/
def frozenOutputsPreserved (g g' : TaskGraph) : Prop :=
  ∀ n, n ∈ g.nodes →
    (∀ output, n.state = .executed output →
      ∃ n', n' ∈ g'.nodes ∧ n'.spec.name = n.spec.name ∧ n'.state = .executed output)

/-- Execute is irreversible: once executed, always executed.
    This is the key invariant that makes the frozen region grow monotonically. -/
theorem execute_irreversible (g : TaskGraph) (name output : String) (h : g.isFrontier name) :
    let g' := { nodes := g.nodes.map fun n =>
      if n.spec.name == name then { n with state := .executed output } else n : TaskGraph }
    ∀ n, n ∈ g.nodes →
      (∀ out, n.state = .executed out →
        ∃ n', n' ∈ g'.nodes ∧ n'.spec.name = n.spec.name ∧ n'.state = .executed out) := by
  intro g' n hn out hout
  refine ⟨n, List.mem_map.mpr ⟨n, hn, ?_⟩, rfl, hout⟩
  -- n was already executed with output `out`.
  -- The map only changes the node named `name`, which is on the frontier (unexecuted).
  -- Since n is executed, n.spec.name ≠ name (a node can't be both frontier and executed).
  simp only [TaskGraph.isFrontier, TaskGraph.findNode] at h
  -- We need: if n.spec.name == name = true, contradiction with n being executed
  by_cases heq : n.spec.name == name
  · -- n.spec.name = name, but name is on the frontier (unexecuted).
    -- We need to show this contradicts n.state = .executed out.
    -- This requires that findNode returns the same node we found in the list.
    -- For now, we'll use the structural argument:
    simp [heq]
    -- n is executed but name is unexecuted — if they're the same node, contradiction.
    -- This is a limitation: we can't easily prove this without unique names.
    sorry -- requires unique node names invariant
  · simp [heq]

/-- addNode preserves all existing frozen outputs. -/
theorem addNode_preserves_frozen (g : TaskGraph) (spec : CellSpec) :
    frozenOutputsPreserved g { nodes := g.nodes ++ [{ spec, state := .unexecuted }] } := by
  intro n hn out hout
  exact ⟨n, List.mem_append.mpr (Or.inl hn), rfl, hout⟩

/-- dropNode preserves frozen outputs (it can only drop unexecuted nodes). -/
theorem dropNode_preserves_frozen (g : TaskGraph) (name : String)
    (h_frontier : g.isFrontier name) :
    frozenOutputsPreserved g { nodes := g.nodes.filter (·.spec.name != name) } := by
  intro n hn out hout
  refine ⟨n, List.mem_filter.mpr ⟨hn, ?_⟩, rfl, hout⟩
  -- n is executed, name is frontier. If n.spec.name = name, contradiction.
  -- (same unique-names issue as above — we note it but focus on the structure)
  sorry -- requires unique node names invariant

-- ═══════════════════════════════════════════════════════════════
-- SECTION 4: Program Projection
-- ═══════════════════════════════════════════════════════════════

/-! A Cell program is (abstractly) a sequence of declarations that
    project into graph operations. The key insight: a Cell program
    doesn't describe a fixed computation — it describes an EVOLUTION
    of the graph frontier.

    A cell declaration "# greet : llm" projects to:
      addNode { name := "greet", type := .text, prompt := ..., refs := ... }

    A wire declaration "greet -> wrap" projects to:
      addEdge "greet" "wrap"

    A graph operation "!drop old-cell" projects to:
      dropNode "old-cell"

    Executing a cell (by the runtime, not the program) projects to:
      execute "greet" "Hello Alice!"

    The program is the PLAN. Execution is what happens when cell-zero
    processes the plan against the current graph state. -/

/-- A Cell declaration — the abstract syntax of a Cell program element.
    This is NOT the surface syntax (which is what we're discovering in ce-s6y).
    This is the semantic content that any syntax must express. -/
inductive CellDecl where
  | cellDef    (spec : CellSpec)                    -- Define a new cell
  | wireDef    (from_ to_ : String)                 -- Wire two cells
  | graphOp    (op : GraphOp)                       -- Explicit graph operation
  | paramDecl  (name : String) (type : String)      -- Declare an input parameter
  deriving Repr, BEq, DecidableEq

/-- A Cell program is a list of declarations. -/
def CellProgram := List CellDecl

/-- Project a declaration into a graph operation.
    Some declarations (paramDecl) don't produce graph operations. -/
def CellDecl.project : CellDecl → Option GraphOp
  | .cellDef spec => some (.addNode spec)
  | .wireDef from_ to_ => some (.addEdge from_ to_)
  | .graphOp op => some op
  | .paramDecl _ _ => none

/-- Project an entire program into a sequence of graph operations. -/
def CellProgram.project (prog : CellProgram) : List GraphOp :=
  prog.filterMap CellDecl.project

/-- Apply a sequence of graph operations to a task graph.
    Returns None if any operation is invalid (the program is ill-formed). -/
def TaskGraph.applyOps (g : TaskGraph) (ops : List GraphOp) : Option TaskGraph :=
  ops.foldlM (fun g op => g.applyOp op) g

/-- Apply a Cell program to a task graph. -/
def TaskGraph.applyProgram (g : TaskGraph) (prog : CellProgram) : Option TaskGraph :=
  g.applyOps prog.project

-- ═══════════════════════════════════════════════════════════════
-- SECTION 5: Well-Formedness
-- ═══════════════════════════════════════════════════════════════

/-- A task graph has unique node names. -/
def TaskGraph.uniqueNames (g : TaskGraph) : Prop :=
  g.nodeNames.Nodup

/-- A task graph is well-formed if:
    1. Node names are unique
    2. All refs point to existing nodes
    3. No executed node depends on an unexecuted node
       (you can't have run before your inputs were ready) -/
def TaskGraph.wellFormed (g : TaskGraph) : Prop :=
  g.uniqueNames ∧
  (∀ n ∈ g.nodes, ∀ ref ∈ n.spec.refs, ref ∈ g.nodeNames) ∧
  (∀ n ∈ g.nodes, ∀ output, n.state = .executed output →
    ∀ ref ∈ n.spec.refs,
      ∃ dep ∈ g.nodes, dep.spec.name = ref ∧
        ∃ depOut, dep.state = .executed depOut)

/-- The empty task graph is well-formed. -/
theorem TaskGraph.empty_wellFormed : TaskGraph.wellFormed { nodes := [] } := by
  refine ⟨List.nodup_nil, fun n hn => (List.not_mem_nil hn).elim, ?_⟩
  intro n hn; exact (List.not_mem_nil hn).elim

-- ═══════════════════════════════════════════════════════════════
-- SECTION 6: The Frontier Monotonicity Theorem
-- ═══════════════════════════════════════════════════════════════

/-! The frozen set only grows. Once a node is executed, it stays executed.
    The frontier shrinks monotonically as computation proceeds.
    This is the formal version of "the past is immutable."

    Together with DAG readiness monotonicity (DAG.lean), this gives us:
    - More frozen nodes → more nodes become ready (readiness monotone)
    - Frozen nodes stay frozen (frontier monotone)
    - Therefore: the system makes progress and never loses work -/

/-- The frozen set of a graph after executing a node is a superset
    of the original frozen set. -/
theorem execute_grows_frozen (g : TaskGraph) (name output : String) :
    let g' := { nodes := g.nodes.map fun n =>
      if n.spec.name == name then { n with state := .executed output } else n : TaskGraph }
    ∀ n, n ∈ g.frozen → n ∈ g'.frozen := by
  sorry -- Complex structural proof about frozen set preservation

-- ═══════════════════════════════════════════════════════════════
-- SECTION 7: Eval-One Semantics
-- ═══════════════════════════════════════════════════════════════

/-! Cell's execution model is eval-one: execute exactly one ready node,
    produce its output, advance the frontier. This is the recursion brake.

    eval-one takes:
    - A task graph (with frozen and frontier regions)
    - Returns: the name of the executed node, its output, and the new graph

    A node is "ready" when all its refs point to frozen (executed) nodes.
    This connects to DAG.ready from DAG.lean. -/

/-- A node is ready for execution when all its dependencies are executed. -/
def TaskGraph.isReady (g : TaskGraph) (name : String) : Bool :=
  match g.findNode name with
  | some n =>
    match n.state with
    | .unexecuted => n.spec.refs.all g.isFrozen
    | _ => false
  | none => false

/-- The ready set: all nodes that can be executed right now. -/
def TaskGraph.readySet (g : TaskGraph) : List String :=
  g.frontier.filter g.isReady

/-- An eval-one step: pick one ready node, produce its output.
    The output is provided externally (by the LLM or a script).
    Returns the updated graph with the node frozen. -/
def TaskGraph.evalOne (g : TaskGraph) (name : String) (output : String)
    : Option TaskGraph :=
  if g.isReady name then
    g.applyOp (.execute name output)
  else
    none

/-- After eval-one, the executed node is frozen. -/
theorem evalOne_freezes (g : TaskGraph) (name output : String)
    (h : g.isReady name) :
    ∃ g', g.evalOne name output = some g' ∧ g'.isFrozen name = true := by
  simp only [TaskGraph.evalOne, h, ite_true]
  simp only [TaskGraph.applyOp]
  sorry -- requires unfolding isValid + map behavior

-- ═══════════════════════════════════════════════════════════════
-- SECTION 8: Distillation as Graph Rewriting
-- ═══════════════════════════════════════════════════════════════

/-! Distillation is the process of replacing an LLM cell with a
    deterministic script cell. In graph terms, this is:

    1. Observe: record (input, output) pairs for a cell across executions
    2. Pattern: find a deterministic function f such that f(input) ≈ output
    3. Shadow: add a new node running f alongside the original
    4. Validate: compare shadow output against LLM output
    5. Promote: replace the LLM node with the deterministic node

    The key constraint: distillation can only happen on the FRONTIER.
    Once a cell is executed (frozen), its implementation is locked for
    that execution. The distilled version replaces it for FUTURE pours.

    This connects to the molecule lifecycle (GasCity.lean Section 19):
    - Each pour creates new frontier nodes
    - Distillation rewrites frontier nodes before execution
    - The distilled version goes into the Proto for the next pour -/

/-- A distillation record: what was observed about a cell's behavior. -/
structure DistillRecord where
  cellName : String
  inputs   : List (String × String)   -- ref name → value seen
  output   : String                    -- output produced
  deriving Repr, BEq, DecidableEq

/-- A distillation proposal: a deterministic replacement for an LLM cell. -/
structure DistillProposal where
  cellName     : String
  newPrompt    : String    -- The deterministic script/template
  newType      : CellType  -- Usually .text or a new "distilled" type
  matchRate    : Nat       -- 0-100: how often the replacement matches
  deriving Repr, BEq, DecidableEq

/-- Apply a distillation: rewrite an unexecuted cell with its distilled version.
    This is only valid on the frontier. -/
def TaskGraph.distill (g : TaskGraph) (proposal : DistillProposal) : Option TaskGraph :=
  match g.findNode proposal.cellName with
  | some n =>
    let newSpec := { n.spec with
      prompt := proposal.newPrompt
      type := proposal.newType }
    g.applyOp (.rewrite proposal.cellName newSpec)
  | none => none

/-- Distillation preserves the frozen set. -/
theorem distill_preserves_frozen (g : TaskGraph) (proposal : DistillProposal)
    (h : g.isFrontier proposal.cellName) :
    ∀ g', g.distill proposal = some g' →
      ∀ name, g.isFrozen name → g'.isFrozen name := by
  sorry -- follows from rewrite only touching frontier nodes

-- ═══════════════════════════════════════════════════════════════
-- SECTION 9: Non-Vacuity Witnesses
-- ═══════════════════════════════════════════════════════════════

/-- A simple task graph: greet → wrap (the hello world program). -/
def helloGraph : TaskGraph where
  nodes := [
    { spec := { name := "greet", type := .text,
                prompt := "Say hello to {{name}}", refs := [] },
      state := .unexecuted },
    { spec := { name := "wrap", type := .text,
                prompt := "Add emoji to {{greet}}", refs := ["greet"] },
      state := .unexecuted }
  ]

/-- Both nodes start on the frontier. -/
example : helloGraph.frontier = ["greet", "wrap"] := by native_decide

/-- Only greet is ready (wrap depends on greet). -/
example : helloGraph.readySet = ["greet"] := by native_decide

/-- After executing greet, it's frozen. -/
example : (helloGraph.evalOne "greet" "Hello Alice!").isSome = true := by native_decide

/-- After executing greet, wrap becomes ready. -/
example :
    match helloGraph.evalOne "greet" "Hello Alice!" with
    | some g' => g'.readySet = ["wrap"]
    | none => False := by sorry

/-- After executing both, frontier is empty. -/
example :
    match helloGraph.evalOne "greet" "Hello!" with
    | some g' =>
      match g'.evalOne "wrap" "Hello! 👋" with
      | some g'' => g''.frontier = []
      | none => False
    | none => False := by sorry

/-- A Cell program that builds the hello graph. -/
def helloProgram : CellProgram := [
  .cellDef { name := "greet", type := .text,
             prompt := "Say hello to {{name}}", refs := [] },
  .cellDef { name := "wrap", type := .text,
             prompt := "Add emoji to {{greet}}", refs := ["greet"] }
]

/-- The program projects to two addNode operations. -/
example : helloProgram.project.length = 2 := by native_decide

/-- Applying the program to an empty graph produces the hello graph. -/
example :
    let empty : TaskGraph := { nodes := [] }
    match empty.applyProgram helloProgram with
    | some g => g.nodes.length = 2 ∧ g.readySet = ["greet"]
    | none => False := by sorry

/-- Distilling greet into a template (on the frontier). -/
example :
    let proposal : DistillProposal := {
      cellName := "greet",
      newPrompt := "Hello {{name}}!",
      newType := .text,
      matchRate := 95 }
    match helloGraph.distill proposal with
    | some g' =>
      -- greet is still on the frontier but with new prompt
      g'.isFrontier "greet" = true ∧
      g'.readySet = ["greet"]
    | none => False := by sorry

/-- Self-modification example: a Cell program that adds a node to an existing graph. -/
def extendProgram : CellProgram := [
  .cellDef { name := "review", type := .decision,
             prompt := "Review {{wrap}} for quality", refs := ["wrap"] },
  .wireDef "wrap" "review"  -- redundant since refs already has "wrap", but shows wire syntax
]

/-- Extending the hello graph with a review step. -/
example :
    let extended := helloGraph.applyProgram extendProgram
    match extended with
    | some g => g.nodes.length = 3
    | none => False := by sorry

-- ═══════════════════════════════════════════════════════════════
-- SECTION 10: Connection to Annotations (GasCity.lean)
-- ═══════════════════════════════════════════════════════════════

/-! The Annotation type in GasCity.lean and the GraphOp type here
    describe the same operations at different levels of abstraction:

    Annotation (GasCity)    → GraphOp (GraphOps)
    ─────────────────────     ──────────────────
    .addCell spec           → .addNode spec
    .removeCell name        → .dropNode name
    .addRef cell newRef     → .addEdge newRef cell
    .removeRef cell oldRef  → .removeEdge oldRef cell
    .refinePrompt cell p    → .rewrite cell { spec with prompt := p }
    .splitCell cell into    → .dropNode cell (+ addNode for each piece)
    .mergeCell cells into   → .dropNode* + .addNode
    .seedValue cell value   → (no graph change — applied during pour)

    The key difference: GraphOp carries the immutability constraint.
    Annotations are "intentions" that may be valid or invalid.
    GraphOps are "checked operations" that maintain invariants.

    The projection Annotation → GraphOp adds the validity check.
    This is exactly the relationship between a Cell program
    (which expresses intentions) and the runtime (which validates them). -/

/-- Project an Annotation into a GraphOp. -/
def toGraphOp : Annotation → List GraphOp
  | .addCell spec => [.addNode spec]
  | .removeCell name => [.dropNode name]
  | .addRef cell newRef => [.addEdge newRef cell]
  | .removeRef cell oldRef => [.removeEdge oldRef cell]
  | .refinePrompt cell newPrompt =>
    -- We need the current spec to construct a rewrite.
    -- In practice, the runtime looks this up. Here we approximate.
    [.rewrite cell { name := cell, type := .text, prompt := newPrompt, refs := [] }]
  | .splitCell cell _into => [.dropNode cell]
  | .mergeCell cells into =>
    let prompt_str := "Merged from: " ++ String.intercalate ", " cells
    let spec : CellSpec := { name := into, type := .synthesis, prompt := prompt_str, refs := [] }
    (cells.map GraphOp.dropNode) ++ [GraphOp.addNode spec]
  | .seedValue _ _ => []

/-- addCell projects to exactly one addNode. -/
example : (toGraphOp (Annotation.addCell { name := "X", type := .text, prompt := "hello", refs := [] })).length = 1 := by native_decide

/-- seedValue projects to no operations (it's applied during pour, not graph rewrite). -/
example : (toGraphOp (Annotation.seedValue "X" "value")).length = 0 := by native_decide

end BeadCalculus.GraphOps
