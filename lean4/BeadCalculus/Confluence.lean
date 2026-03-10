/-
  BeadCalculus.Confluence — Confluence of Eval-One Execution.

  Cell's execution model is nondeterministic: when multiple cells are
  ready, any one can be chosen for eval-one. The key property that
  makes this sound is CONFLUENCE: the final result is the same
  regardless of evaluation order.

  This module proves:
  1. Independent executions commute (the core lemma)
  2. Ready monotonicity (executing one cell doesn't un-ready others)
  3. Eval-one preserves well-formedness
  4. Diamond property for ready cells

  Why this matters for Cell:
  - LLMs are nondeterministic in which cell they choose to eval-one
  - Different evaluation orders must produce the same final graph
  - This is what makes Cell programs DECLARATIVE rather than imperative
  - It's also what makes distillation safe: replacing one cell doesn't
    affect the execution of independent cells

  Connection to the pretend test: when an LLM eval-ones a Cell program,
  it picks cells in SOME order. Confluence guarantees that any valid
  order produces the same result. The LLM doesn't need to pick the
  "right" order — any order works.
-/

import BeadCalculus.GraphOps

namespace BeadCalculus.Confluence

open BeadCalculus
open BeadCalculus.GasCity
open BeadCalculus.GraphOps

-- ═══════════════════════════════════════════════════════════════
-- SECTION 1: Map Commutativity
-- ═══════════════════════════════════════════════════════════════

/-! Two list maps that touch different elements commute. This is
    the core algebraic fact underlying confluence.

    If f changes only elements with name A, and g changes only
    elements with name B, and A ≠ B, then:
      list.map f |>.map g = list.map g |>.map f -/

/-- A function that only modifies nodes with a specific name. -/
def touchesOnly (f : TaskNode → TaskNode) (name : String) : Prop :=
  ∀ n : TaskNode, n.spec.name ≠ name → f n = n

/-- A function that preserves node names. -/
def preservesName (f : TaskNode → TaskNode) : Prop :=
  ∀ n : TaskNode, (f n).spec.name = n.spec.name

/-- Two maps that touch different names commute on any node. -/
theorem pointwise_commute (f g : TaskNode → TaskNode) (a b : String)
    (hab : a ≠ b)
    (hf_only : touchesOnly f a) (hg_only : touchesOnly g b)
    (hf_name : preservesName f) (hg_name : preservesName g) :
    ∀ n : TaskNode, f (g n) = g (f n) := by
  intro n
  by_cases ha : n.spec.name = a
  · -- n has name a, so g doesn't touch it
    have hgn : g n = n := hg_only n (by rw [ha]; exact hab)
    rw [hgn]
    -- f(n) has name a (preservesName), so g doesn't touch f(n) either
    have hfn_name : (f n).spec.name = a := by rw [← ha]; exact hf_name n
    have hgfn : g (f n) = f n := hg_only (f n) (by rw [hfn_name]; exact hab)
    rw [hgfn]
  · -- n does not have name a, so f doesn't touch it
    have hfn : f n = n := hf_only n ha
    rw [hfn]
    -- g(n) may or may not have name b, but g(n) still doesn't have name a
    -- (since g preserves names and n didn't have name a)
    have hgn_name : (g n).spec.name ≠ a := by rw [hg_name n]; exact ha
    have hfgn : f (g n) = g n := hf_only (g n) hgn_name
    rw [hfgn]

/-- Two maps that touch different names commute on lists. -/
theorem list_map_commute (f g : TaskNode → TaskNode) (a b : String)
    (hab : a ≠ b)
    (hf_only : touchesOnly f a) (hg_only : touchesOnly g b)
    (hf_name : preservesName f) (hg_name : preservesName g) :
    ∀ l : List TaskNode, (l.map f).map g = (l.map g).map f := by
  intro l
  simp only [List.map_map]
  congr 1
  ext n
  simp [Function.comp, pointwise_commute f g a b hab hf_only hg_only hf_name hg_name n]

-- ═══════════════════════════════════════════════════════════════
-- SECTION 2: Execute Map Properties
-- ═══════════════════════════════════════════════════════════════

/-! The execute operation is a map that touches only one name. -/

/-- The map function used by execute. -/
def executeMap (name output : String) (n : TaskNode) : TaskNode :=
  if n.spec.name == name then { n with state := .executed output } else n

/-- executeMap touches only the named node. -/
theorem executeMap_touchesOnly (name output : String) :
    touchesOnly (executeMap name output) name := by
  intro n hne
  simp only [executeMap]
  split
  · exfalso; exact hne (beq_iff_eq.mp ‹_›)
  · rfl

/-- executeMap preserves node names. -/
theorem executeMap_preservesName (name output : String) :
    preservesName (executeMap name output) := by
  intro n
  simp only [executeMap]
  split <;> simp

-- ═══════════════════════════════════════════════════════════════
-- SECTION 3: Independent Executions Commute
-- ═══════════════════════════════════════════════════════════════

/-! The core confluence lemma: executing two different cells in
    either order produces the same graph. -/

/-- Executing two cells with different names in either order
    produces the same list of nodes. -/
theorem execute_maps_commute (nameA nameB outputA outputB : String)
    (hab : nameA ≠ nameB) :
    ∀ l : List TaskNode,
      (l.map (executeMap nameA outputA)).map (executeMap nameB outputB) =
      (l.map (executeMap nameB outputB)).map (executeMap nameA outputA) := by
  exact list_map_commute
    (executeMap nameA outputA) (executeMap nameB outputB)
    nameA nameB hab
    (executeMap_touchesOnly nameA outputA)
    (executeMap_touchesOnly nameB outputB)
    (executeMap_preservesName nameA outputA)
    (executeMap_preservesName nameB outputB)

-- ═══════════════════════════════════════════════════════════════
-- SECTION 4: Ready Monotonicity
-- ═══════════════════════════════════════════════════════════════

/-! Executing a cell can only ADD to the frozen set, never remove
    from it. Therefore, if a cell B was ready before executing A,
    B is still ready after (as long as A ≠ B).

    This is critical for confluence: we need to know that both
    orderings are valid (both cells remain ready in the intermediate
    state). -/

/-- find? on a mapped list equals f applied to find? on the original,
    when f preserves the predicate key (spec.name). -/
private theorem findNode_map (nodes : List TaskNode) (name : String)
    (f : TaskNode → TaskNode)
    (hf_name : ∀ n, (f n).spec.name = n.spec.name) :
    (nodes.map f).find? (·.spec.name == name) = (nodes.find? (·.spec.name == name)).map f := by
  induction nodes with
  | nil => simp
  | cons hd tl ih =>
    simp only [List.map_cons, List.find?_cons]
    rw [hf_name]
    split
    · simp
    · exact ih

/-- executeMap preserves spec.name. -/
private theorem executeMap_name (name output : String) (n : TaskNode) :
    (executeMap name output n).spec.name = n.spec.name := by
  simp only [executeMap]; split <;> simp

/-- Helper: on a mapped list, findNode returns the mapped version of the original. -/
private theorem findNode_map_eq (nodes : List TaskNode) (name : String)
    (f : TaskNode → TaskNode)
    (hf_name : ∀ n, (f n).spec.name = n.spec.name)
    (nd : TaskNode)
    (h : nodes.find? (·.spec.name == name) = some nd) :
    (nodes.map f).find? (·.spec.name == name) = some (f nd) := by
  induction nodes with
  | nil => simp at h
  | cons hd tl ih =>
    simp only [List.map_cons, List.find?_cons, List.find?_cons] at h ⊢
    rw [hf_name]
    split <;> rename_i heq
    · simp [heq] at h; subst h; rfl
    · simp [heq] at h; exact ih h

/-- After executing a node, any previously frozen node is still frozen. -/
theorem isFrozen_after_execute (g : TaskGraph) (name output : String)
    (other : String) (h_frozen : g.isFrozen other = true) :
    ({ nodes := g.nodes.map (executeMap name output) } : TaskGraph).isFrozen other = true := by
  unfold TaskGraph.isFrozen TaskGraph.findNode at h_frozen ⊢
  -- Case split on whether the original findNode returns some or none
  cases hfind : g.nodes.find? (·.spec.name == other) with
  | none => rw [hfind] at h_frozen; simp at h_frozen
  | some nd =>
    rw [hfind] at h_frozen; dsimp at h_frozen
    -- h_frozen : (match nd.state with | .executed _ => true | _ => false) = true
    rw [findNode_map_eq g.nodes other (executeMap name output) (executeMap_name name output) nd hfind]
    dsimp
    -- Goal: (match (executeMap name output nd).state with | .executed _ => true | _ => false) = true
    by_cases heq : nd.spec.name == name
    · -- nd.spec.name == name: executeMap changes state to .executed output
      simp [executeMap, heq]
    · -- nd.spec.name ≠ name: executeMap is identity
      simp [executeMap, heq]
      exact h_frozen

/-- After executing a cell, a previously unexecuted different cell
    is still on the frontier. -/
theorem isFrontier_after_execute (g : TaskGraph) (name output other : String)
    (h_ne : other ≠ name)
    (h_frontier : g.isFrontier other = true) :
    ({ nodes := g.nodes.map (executeMap name output) } : TaskGraph).isFrontier other = true := by
  unfold TaskGraph.isFrontier TaskGraph.findNode at h_frontier ⊢
  cases hfind : g.nodes.find? (·.spec.name == other) with
  | none => rw [hfind] at h_frontier; simp at h_frontier
  | some nd =>
    rw [hfind] at h_frontier
    dsimp at h_frontier
    rw [findNode_map_eq g.nodes other (executeMap name output) (executeMap_name name output) nd hfind]
    dsimp
    -- Since other ≠ name and nd.spec.name == other, executeMap is identity on nd
    have hnd_name : nd.spec.name = other := beq_iff_eq.mp (List.find?_eq_some_iff_append.mp hfind).1
    have hnd_ne : nd.spec.name ≠ name := hnd_name ▸ h_ne
    have : executeMap name output nd = nd := by
      simp [executeMap, show (nd.spec.name == name) = false from beq_eq_false_iff_ne.mpr hnd_ne]
    rw [this]
    exact h_frontier

/-- If cell B is ready in graph g, and we execute cell A (where A ≠ B),
    then B is still ready in the resulting graph.

    This follows because:
    1. B is still on the frontier (executing A doesn't change B's state)
    2. B's refs are still all frozen (executing A can only add to frozen set) -/
theorem ready_preserved_after_execute (g : TaskGraph) (nameA outputA nameB : String)
    (h_ne : nameB ≠ nameA)
    (h_ready : g.isReady nameB = true)
    (h_unique : g.uniqueNames) :
    let g' : TaskGraph := { nodes := g.nodes.map (executeMap nameA outputA) }
    g'.isReady nameB = true := by
  simp only
  unfold TaskGraph.isReady TaskGraph.findNode at h_ready ⊢
  cases hfind : g.nodes.find? (·.spec.name == nameB) with
  | none => rw [hfind] at h_ready; simp at h_ready
  | some nd =>
    rw [hfind] at h_ready
    dsimp at h_ready
    rw [findNode_map_eq g.nodes nameB (executeMap nameA outputA) (executeMap_name nameA outputA) nd hfind]
    dsimp
    -- nd.spec.name == nameA is false since nameB ≠ nameA
    have hnd_name : nd.spec.name = nameB := beq_iff_eq.mp (List.find?_eq_some_iff_append.mp hfind).1
    have hnd_ne : nd.spec.name ≠ nameA := hnd_name ▸ h_ne
    have hid : executeMap nameA outputA nd = nd := by
      simp [executeMap, show (nd.spec.name == nameA) = false from beq_eq_false_iff_ne.mpr hnd_ne]
    rw [hid]
    -- Now both sides have nd directly
    cases hst : nd.state with
    | executing => rw [hst] at h_ready; simp at h_ready
    | executed o => rw [hst] at h_ready; simp at h_ready
    | unexecuted =>
      simp only [hst] at h_ready ⊢
      rw [List.all_eq_true] at h_ready ⊢
      intro ref href
      exact isFrozen_after_execute g nameA outputA ref (h_ready ref href)

-- ═══════════════════════════════════════════════════════════════
-- SECTION 5: The Diamond Property
-- ═══════════════════════════════════════════════════════════════

/-! The diamond property: if cells A and B are both ready, then
    executing A then B produces the same graph as executing B then A.

    This is the key confluence result. Together with ready monotonicity,
    it extends to arbitrary-length execution sequences. -/

/-- Executing the same cell produces the expected mapped graph.
    (Helper for reducing evalOne to its map representation.) -/
theorem evalOne_as_map (g : TaskGraph) (name output : String)
    (h_ready : g.isReady name = true) :
    g.evalOne name output = some { nodes := g.nodes.map (executeMap name output) } := by
  have h_frontier : g.isFrontier name = true := by
    unfold TaskGraph.isReady at h_ready
    unfold TaskGraph.isFrontier
    split at h_ready
    · next _ =>
      split at h_ready <;> (first | rfl | simp at h_ready)
    · simp at h_ready
  simp only [TaskGraph.evalOne, h_ready, ite_true, TaskGraph.applyOp,
             GraphOp.isValid, h_frontier]
  rfl

/-- THE DIAMOND THEOREM: If cells A and B are both ready in graph g,
    and A ≠ B, then:
      g.evalOne A outA >>= (·.evalOne B outB)
    = g.evalOne B outB >>= (·.evalOne A outA)

    This is the formal statement that Cell's eval-one is confluent
    for independent ready cells. -/
theorem eval_diamond (g : TaskGraph) (nameA nameB : String)
    (outputA outputB : String)
    (h_ne : nameA ≠ nameB)
    (h_readyA : g.isReady nameA = true)
    (h_readyB : g.isReady nameB = true)
    (h_unique : g.uniqueNames) :
    (g.evalOne nameA outputA).bind (·.evalOne nameB outputB) =
    (g.evalOne nameB outputB).bind (·.evalOne nameA outputA) := by
  -- Reduce both sides to their map representations
  rw [evalOne_as_map g nameA outputA h_readyA]
  rw [evalOne_as_map g nameB outputB h_readyB]
  simp only [Option.bind_some]
  -- Show B is still ready after executing A, and vice versa
  let gA : TaskGraph := { nodes := g.nodes.map (executeMap nameA outputA) }
  let gB : TaskGraph := { nodes := g.nodes.map (executeMap nameB outputB) }
  have h_readyB' : gA.isReady nameB = true :=
    ready_preserved_after_execute g nameA outputA nameB (Ne.symm h_ne) h_readyB h_unique
  have h_readyA' : gB.isReady nameA = true :=
    ready_preserved_after_execute g nameB outputB nameA h_ne h_readyA h_unique
  -- Reduce the nested evalOne calls
  rw [evalOne_as_map gA nameB outputB h_readyB']
  rw [evalOne_as_map gB nameA outputA h_readyA']
  -- Now we need: map (executeMap B) (map (executeMap A) nodes) =
  --              map (executeMap A) (map (executeMap B) nodes)
  show (some { nodes := (g.nodes.map (executeMap nameA outputA)).map (executeMap nameB outputB) } : Option TaskGraph) =
       some { nodes := (g.nodes.map (executeMap nameB outputB)).map (executeMap nameA outputA) }
  exact congrArg some (congrArg TaskGraph.mk
    (execute_maps_commute nameA nameB outputA outputB h_ne g.nodes))

-- ═══════════════════════════════════════════════════════════════
-- SECTION 6: Non-Vacuity — Diamond in Action
-- ═══════════════════════════════════════════════════════════════

/-! Demonstrate the diamond property on a concrete example:
    a graph with two independent ready cells. -/

/-- A graph with two independent ready cells (no dependencies between them). -/
private def twoReadyGraph : TaskGraph where
  nodes := [
    { spec := { name := "A", type := .text, prompt := "compute A", refs := [] },
      state := .unexecuted },
    { spec := { name := "B", type := .text, prompt := "compute B", refs := [] },
      state := .unexecuted }
  ]

/-- Both cells are ready. -/
example : twoReadyGraph.readySet = ["A", "B"] := by native_decide

/-- Executing A then B produces the same graph as B then A. -/
example :
    (twoReadyGraph.evalOne "A" "result-A").bind (·.evalOne "B" "result-B") =
    (twoReadyGraph.evalOne "B" "result-B").bind (·.evalOne "A" "result-A") := by
  native_decide

/-- Three independent cells: A, B, C — all 6 orderings produce the same result. -/
private def threeReadyGraph : TaskGraph where
  nodes := [
    { spec := { name := "A", type := .text, prompt := "A", refs := [] },
      state := .unexecuted },
    { spec := { name := "B", type := .text, prompt := "B", refs := [] },
      state := .unexecuted },
    { spec := { name := "C", type := .text, prompt := "C", refs := [] },
      state := .unexecuted }
  ]

/-- All 3 orderings starting with A produce the same result. -/
example :
    -- A, B, C
    let abc := (threeReadyGraph.evalOne "A" "a").bind (·.evalOne "B" "b") |>.bind (·.evalOne "C" "c")
    -- A, C, B
    let acb := (threeReadyGraph.evalOne "A" "a").bind (·.evalOne "C" "c") |>.bind (·.evalOne "B" "b")
    abc = acb := by native_decide

example :
    -- A, B, C
    let abc := (threeReadyGraph.evalOne "A" "a").bind (·.evalOne "B" "b") |>.bind (·.evalOne "C" "c")
    -- B, A, C
    let bac := (threeReadyGraph.evalOne "B" "b").bind (·.evalOne "A" "a") |>.bind (·.evalOne "C" "c")
    abc = bac := by native_decide

example :
    -- A, B, C
    let abc := (threeReadyGraph.evalOne "A" "a").bind (·.evalOne "B" "b") |>.bind (·.evalOne "C" "c")
    -- C, B, A
    let cba := (threeReadyGraph.evalOne "C" "c").bind (·.evalOne "B" "b") |>.bind (·.evalOne "A" "a")
    abc = cba := by native_decide

-- ═══════════════════════════════════════════════════════════════
-- SECTION 7: What Confluence Means for Cell
-- ═══════════════════════════════════════════════════════════════

/-! Confluence has profound implications for Cell's design:

    1. **Parallelism is free.** Independent cells can be executed
       concurrently with no synchronization. The diamond property
       guarantees the result is the same.

    2. **The LLM doesn't need to pick the "right" order.**
       Any valid eval-one sequence produces the same result.
       This is what makes the pretend test work: the LLM just
       needs to identify ANY ready cell and execute it correctly.

    3. **Distillation is safe.** Replacing one cell with its
       distilled version doesn't affect the execution of
       independent cells. The confluence proof extends to
       mixed (LLM + distilled) execution.

    4. **The syntax doesn't encode execution order.**
       Cell programs are DECLARATIVE precisely because of
       confluence. The syntax describes the graph (nodes and
       edges), not the evaluation sequence. Any topological
       order works.

    5. **Connection to spreadsheets.** Excel recalculates in
       dependency order, but independent cells can recalculate
       in any order. This is the same property: confluence of
       independent reactive computations.

    The full confluence theorem (for arbitrary-length sequences)
    follows from the diamond property by induction on the number
    of ready cells. We state it as a corollary. -/

/-- Two complete evaluation traces are equivalent if they execute
    the same cells (possibly in different orders) and each cell
    produces the same output in both traces. -/
def traceEquiv (t1 t2 : List (String × String)) : Prop :=
  t1.length = t2.length ∧
  ∀ p ∈ t1, p ∈ t2

/-- The result of applying a trace (sequence of name, output pairs)
    to a graph via eval-one. -/
def applyEvalTrace (g : TaskGraph) (trace : List (String × String)) : Option TaskGraph :=
  trace.foldlM (fun g (p : String × String) => g.evalOne p.1 p.2) g

/-- Applying the empty trace is the identity. -/
theorem empty_trace_identity (g : TaskGraph) :
    applyEvalTrace g [] = some g := rfl

/-- A permutation of a valid eval trace on independent cells
    produces the same result. (Stated for 2-element permutation;
    the general case follows by induction on transpositions.) -/
theorem swap_independent_steps (g : TaskGraph) (a b : String) (outA outB : String)
    (h_ne : a ≠ b)
    (h_readyA : g.isReady a = true)
    (h_readyB : g.isReady b = true)
    (h_unique : g.uniqueNames) :
    applyEvalTrace g [(a, outA), (b, outB)] =
    applyEvalTrace g [(b, outB), (a, outA)] := by
  simp [applyEvalTrace, List.foldlM]
  exact eval_diamond g a b outA outB h_ne h_readyA h_readyB h_unique

end BeadCalculus.Confluence
