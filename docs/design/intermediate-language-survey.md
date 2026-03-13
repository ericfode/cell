# Survey: Intermediate Declaration Language for Cell

**Date**: 2026-03-13
**Status**: Draft
**Problem**: Cell has two inconsistent surface syntaxes that prevent deterministic
parsing and reliable transformation to beads.

---

## The Problem

Cell currently has **two surface syntaxes** that share an abstract grammar but
diverge completely in concrete form:

### Syntax A — "Markdown-recipe" (Go parser exists)
```
## molecule-name
  # cell-name : llm
    - dependency
    system> You are helpful.
    user> Do the thing with {{input}}.
    format> output { field: type }
    ```oracle
    assert output.field > 0;
    ```
  #/
##/
```

### Syntax B — "Turnstile-spec" (no parser, used in v0.2 spec + evolution rounds)
```
⊢ cell-name
  given dependency→field
  yield output
  ∴ Do the thing with «input».
  ⊨ output satisfies property
```

**The consequences:**
1. LLMs write either format (or hybrids) depending on context in their window
2. The Go parser only handles Syntax A; Syntax B programs are unparseable
3. The v0.2 spec describes Syntax B; the 48+ example files use Syntax A
4. `cell-to-beads.py` can't reliably transform either — it would need two parsers
5. We can't tell if an LLM "executing" a Cell program is actually following the
   rules or just generating plausible-looking text

**What we need:** A single intermediate form that is:
- **Deterministically parseable** (existing parser libraries, battle-tested)
- **LLM-native** (common in training data; passes the pretend test)
- **Graph-friendly** (naturally represents DAGs with typed nodes and edges)
- **Text-heavy-friendly** (prompts are multi-line natural language)
- **Homoiconic-ish** (Cell programs that generate Cell programs)
- **Transformable to beads** (unambiguous 1:1 mapping to `bd create` + `bd dep add`)

---

## Evaluation Criteria

| Criterion | Weight | What it measures |
|-----------|--------|------------------|
| **Deterministic parsing** | 25% | Battle-tested parsers exist; no ambiguity in grammar |
| **LLM fluency** | 25% | How naturally LLMs read/write it (training data prevalence) |
| **Graph expressiveness** | 20% | DAG nodes, edges, typed metadata, multi-valued outputs |
| **Prose comfort** | 15% | Multi-line strings, embedded natural language, comments |
| **Homoiconicity** | 10% | Programs that manipulate programs (quotation, metaprogramming) |
| **Tooling ecosystem** | 5% | Editors, linters, formatters, schema validation |

---

## Candidates

### 1. S-Expressions (Lisp-like)

**What it is:** Parenthesized prefix notation. The canonical homoiconic format.

**Cell example:**
```scheme
(cell sort
  (given (data items))
  (yield sorted)
  (soft "Sort «items» in ascending order.")
  (oracle "sorted is a permutation of «data→items»")
  (oracle "sorted is in ascending order")
  (on-failure (retry 2 (with-context oracle.failures))))

(cell verify-permutation
  (given (sort sorted) (data items))
  (yield is-permutation)
  (hard (= is-permutation (= (multiset sorted) (multiset items))))
  (oracle (= is-permutation true)))
```

| Criterion | Score | Notes |
|-----------|-------|-------|
| Deterministic parsing | 10/10 | Trivial grammar. Every Lisp parser works. |
| LLM fluency | 7/10 | LLMs can write s-exprs but less fluent than Python/YAML |
| Graph expressiveness | 9/10 | Natural for tree/graph data; references just work |
| Prose comfort | 4/10 | Multi-line strings awkward in parens; prompts feel cramped |
| Homoiconicity | 10/10 | *The* homoiconic format. Code-as-data is inherent. |
| Tooling | 7/10 | Emacs, tree-sitter, many parser libs. No schema validation |

**Weighted: 7.9/10**

**Strengths:** Unbeatable for metaprogramming. `§quotation` maps directly to
quasiquote. Cell programs generating Cell programs is trivial. Parser is 50 lines.
**Weaknesses:** Prose-heavy content looks bad. LLMs sometimes lose track of
nesting depth. Not "document-is-program" — it's clearly a program.

---

### 2. Starlark (Deterministic Python)

**What it is:** A strict, deterministic subset of Python used by Bazel/Buck.
No I/O, no imports, guaranteed termination. Well-specified.

**Cell example:**
```python
cell(
    name = "sort",
    given = ["data→items"],
    yield_ = ["sorted"],
    soft = "Sort «items» in ascending order.",
    oracle = [
        "sorted is a permutation of «data→items»",
        "sorted is in ascending order",
    ],
    on_failure = retry(max = 2, with_context = "oracle.failures"),
)

cell(
    name = "verify-permutation",
    given = ["sort→sorted", "data→items"],
    yield_ = ["is-permutation"],
    hard = "is-permutation ← multiset(sorted) = multiset(items)",
    oracle = ["is-permutation = true"],
)
```

| Criterion | Score | Notes |
|-----------|-------|-------|
| Deterministic parsing | 9/10 | Well-specified grammar; reference Go/Java/Rust implementations |
| LLM fluency | 10/10 | Python is the #1 language in LLM training data |
| Graph expressiveness | 7/10 | Function calls + kwargs model nodes well; edges via string refs |
| Prose comfort | 7/10 | Triple-quoted strings, but f-strings not available |
| Homoiconicity | 5/10 | Not homoiconic, but LLMs can generate Starlark strings reliably |
| Tooling | 8/10 | Python editors work; Starlark LSP exists; linters available |

**Weighted: 8.2/10**

**Strengths:** LLMs write Python-like syntax more reliably than any other format.
Deterministic semantics (no side effects, termination guaranteed). The `cell()`
function call pattern is immediately comprehensible. Existing Starlark implementations
in Go (github.com/nicholasgasior/gostarlark), Rust, Java.
**Weaknesses:** Not homoiconic — generating programs that generate programs requires
string manipulation. `yield` is a Python keyword (must use `yield_`). String-based
references ("sort→sorted") still need a second parsing pass.

---

### 3. CUE

**What it is:** A typed configuration language from Google (by Marcel van Lohuizen,
co-creator of Go). Superset of JSON with types, constraints, and unification.

**Cell example:**
```cue
package cell

sort: #Cell & {
    given: ["data→items"]
    yield: ["sorted"]
    body: #Soft & {
        prompt: "Sort «items» in ascending order."
    }
    oracle: [
        "sorted is a permutation of «data→items»",
        "sorted is in ascending order",
    ]
    on_failure: {
        retry: 2
        with_context: "oracle.failures"
    }
}

verify_permutation: #Cell & {
    given: ["sort→sorted", "data→items"]
    yield: ["is-permutation"]
    body: #Hard & {
        expr: "is-permutation ← multiset(sorted) = multiset(items)"
    }
    oracle: ["is-permutation = true"]
}

#Cell: {
    given:       [...string]
    yield:       [...string]
    body:        #Soft | #Hard
    oracle?:     [...string]
    on_failure?: {retry: int, with_context: string}
}
#Soft: {prompt: string}
#Hard: {expr: string}
```

| Criterion | Score | Notes |
|-----------|-------|-------|
| Deterministic parsing | 10/10 | Rigorous spec; reference Go implementation |
| LLM fluency | 5/10 | Niche language; limited training data |
| Graph expressiveness | 9/10 | Structs + references + constraints model graphs well |
| Prose comfort | 7/10 | Multi-line strings, but quoting rules are unfamiliar |
| Homoiconicity | 6/10 | Templates and comprehensions, not true code-as-data |
| Tooling | 8/10 | LSP, formatter, schema validation, Go SDK |

**Weighted: 7.3/10**

**Strengths:** Built-in type system means the schema IS the validator. Constraints
like `retry: >0 & <=5` catch invalid programs at parse time. Unification semantics
are ideal for Cell's crystallization (soft and hard are just different completions
of the same structure). Go implementation aligns with existing Cell codebase.
**Weaknesses:** LLMs struggle with CUE syntax — it's too niche. The unification
model is powerful but confusing even for human developers. Training data gap is
a serious problem for the pretend test.

---

### 4. HCL (HashiCorp Configuration Language)

**What it is:** The language behind Terraform. Designed specifically for declaring
resources with attributes and dependencies.

**Cell example:**
```hcl
cell "sort" {
  given = ["data→items"]
  yield = ["sorted"]

  soft {
    prompt = <<-EOT
      Sort «items» in ascending order.
    EOT
  }

  oracle {
    assert = "sorted is a permutation of «data→items»"
  }
  oracle {
    assert = "sorted is in ascending order"
  }

  on_failure {
    retry       = 2
    with_context = "oracle.failures"
  }
}

cell "verify-permutation" {
  given = ["sort→sorted", "data→items"]
  yield = ["is-permutation"]

  hard {
    expr = "is-permutation ← multiset(sorted) = multiset(items)"
  }

  oracle {
    assert = "is-permutation = true"
  }
}
```

| Criterion | Score | Notes |
|-----------|-------|-------|
| Deterministic parsing | 9/10 | Well-specified; hclparse library in Go |
| LLM fluency | 8/10 | Terraform is widely used; LLMs write HCL well |
| Graph expressiveness | 9/10 | Resource blocks + attribute references are DAG-native |
| Prose comfort | 9/10 | Heredocs (`<<-EOT`), multi-line strings, comments |
| Homoiconicity | 3/10 | Not designed for metaprogramming at all |
| Tooling | 9/10 | LSP, formatter, validator, Go SDK (hashicorp/hcl) |

**Weighted: 8.1/10**

**Strengths:** HCL was literally designed for "declare named resources with typed
attributes and dependency relationships." The `cell "name" { ... }` pattern maps
perfectly to Cell declarations. Heredocs handle prompts beautifully. The Go parser
(`hashicorp/hcl`) is production-grade and battle-tested by Terraform's massive
user base. LLMs write it fluently because Terraform is common in training data.
**Weaknesses:** Zero homoiconicity. Cell programs that generate Cell programs would
require string templating, not structural manipulation. HCL's expression language
is limited (no user-defined functions). The `resource "type" "name"` pattern from
Terraform might cause LLMs to hallucinate Terraform-specific syntax.

---

### 5. KDL (KDL Document Language)

**What it is:** A modern document language designed as "XML/JSON/YAML done right."
Node-based, with typed arguments and properties.

**Cell example:**
```kdl
cell "sort" {
    given "data→items"
    yield "sorted"

    soft {
        prompt "Sort «items» in ascending order."
    }

    oracle "sorted is a permutation of «data→items»"
    oracle "sorted is in ascending order"

    on-failure retry=2 with-context="oracle.failures"
}

cell "verify-permutation" {
    given "sort→sorted"
    given "data→items"
    yield "is-permutation"

    hard {
        expr "is-permutation ← multiset(sorted) = multiset(items)"
    }

    oracle "is-permutation = true"
}
```

| Criterion | Score | Notes |
|-----------|-------|-------|
| Deterministic parsing | 9/10 | Formal spec; parsers in Go, Rust, JS, Python |
| LLM fluency | 3/10 | Very new language; minimal training data |
| Graph expressiveness | 8/10 | Nodes with children model graphs well |
| Prose comfort | 8/10 | Raw strings, multi-line strings, good for prose |
| Homoiconicity | 7/10 | Nodes-as-data is structural; better than HCL, worse than s-exprs |
| Tooling | 5/10 | Growing but immature; tree-sitter grammar exists |

**Weighted: 6.1/10**

**Strengths:** Clean, modern, designed from lessons learned from XML/JSON/YAML/TOML.
The node-based structure (node name + arguments + properties + children) maps well
to cells. No YAML footguns (Norway problem, etc.).
**Weaknesses:** The LLM fluency gap is fatal. LLMs have almost no KDL in their
training data. They'll hallucinate syntax constantly. This directly violates the
pretend test requirement.

---

### 6. EDN (Extensible Data Notation)

**What it is:** Clojure's data format. Like JSON but with keywords, sets, tagged
literals, and comments.

**Cell example:**
```clojure
{:cell/sort
 {:given [:data/items]
  :yield [:sorted]
  :body {:type :soft
         :prompt "Sort «items» in ascending order."}
  :oracle ["sorted is a permutation of «data→items»"
           "sorted is in ascending order"]
  :on-failure {:retry 2 :with-context :oracle/failures}}

 :cell/verify-permutation
 {:given [:sort/sorted :data/items]
  :yield [:is-permutation]
  :body {:type :hard
         :expr "is-permutation ← multiset(sorted) = multiset(items)"}
  :oracle ["is-permutation = true"]}}
```

| Criterion | Score | Notes |
|-----------|-------|-------|
| Deterministic parsing | 9/10 | Simple grammar; parsers in many languages |
| LLM fluency | 5/10 | Clojure is niche; LLMs sometimes confuse with other Lisps |
| Graph expressiveness | 9/10 | Keywords as identifiers, sets for dependencies, maps for metadata |
| Prose comfort | 5/10 | Multi-line strings exist but feel foreign in EDN |
| Homoiconicity | 9/10 | Data IS code in Clojure ecosystem; structural manipulation natural |
| Tooling | 6/10 | Clojure ecosystem; limited outside it |

**Weighted: 7.1/10**

**Strengths:** Keywords (`:cell/sort`, `:given`) make references first-class
without quoting. Tagged literals (`#cell/ref sort→sorted`) could encode Cell
references as typed data. Sets for unordered dependencies.
**Weaknesses:** LLM fluency is moderate — Clojure is in training data but not
dominant. Namespace-qualified keywords are powerful but confusing. Not commonly
used outside the Clojure world.

---

### 7. Dhall

**What it is:** A typed, total (termination-guaranteed) configuration language.
Functions, records, unions, imports, but no side effects and no recursion.

**Cell example:**
```dhall
let Cell = { given : List Text, yield : List Text, body : Body, oracle : List Text }
let Body = < Soft : { prompt : Text } | Hard : { expr : Text } >

let sort : Cell = {
    given = ["data→items"],
    yield = ["sorted"],
    body = Body.Soft { prompt = "Sort «items» in ascending order." },
    oracle = [
        "sorted is a permutation of «data→items»",
        "sorted is in ascending order"
    ]
}

let verify-permutation : Cell = {
    given = ["sort→sorted", "data→items"],
    yield = ["is-permutation"],
    body = Body.Hard { expr = "is-permutation ← multiset(sorted) = multiset(items)" },
    oracle = ["is-permutation = true"]
}

in [sort, verify-permutation]
```

| Criterion | Score | Notes |
|-----------|-------|-------|
| Deterministic parsing | 10/10 | Formal spec, reference Haskell impl, proven total |
| LLM fluency | 3/10 | Very niche; minimal training data |
| Graph expressiveness | 8/10 | Records + unions model nodes; functions for templates |
| Prose comfort | 7/10 | Multi-line strings via `''...''`; text interpolation |
| Homoiconicity | 4/10 | Typed but not homoiconic; functions help but not code-as-data |
| Tooling | 6/10 | LSP exists; dhall-to-json, dhall-to-yaml converters |

**Weighted: 5.9/10**

**Strengths:** Totality guarantee means Cell programs in Dhall provably terminate
at the *declaration* level (the program DAG itself, not execution). Type system
catches malformed cells. Union types model Soft/Hard body distinction perfectly.
**Weaknesses:** LLM fluency is critically low. The Haskell-flavored syntax confuses
LLMs. Niche community means poor training data coverage. Overkill for what's
essentially a data format.

---

### 8. Structured Markdown (Pandoc AST / MyST)

**What it is:** Keep Cell's "document-is-program" philosophy but use a well-defined
Markdown dialect with deterministic parsing (e.g., CommonMark + structured
directives from MyST).

**Cell example:**
````markdown
```{cell} sort
:given: data→items
:yield: sorted
:type: soft

Sort «items» in ascending order.
```

```{oracle} sort
sorted is a permutation of «data→items»
```

```{oracle} sort
sorted is in ascending order
```

```{cell} verify-permutation
:given: sort→sorted, data→items
:yield: is-permutation
:type: hard
:expr: is-permutation ← multiset(sorted) = multiset(items)
```

```{oracle} verify-permutation
is-permutation = true
```
````

| Criterion | Score | Notes |
|-----------|-------|-------|
| Deterministic parsing | 7/10 | CommonMark is specified; MyST adds directives. But edge cases. |
| LLM fluency | 9/10 | Markdown is the second most natural format for LLMs |
| Graph expressiveness | 5/10 | Flat document model; DAG structure is implicit, not structural |
| Prose comfort | 10/10 | *Is* prose. Document-is-program fully realized. |
| Homoiconicity | 6/10 | LLMs can generate markdown; structural manipulation is string-based |
| Tooling | 7/10 | Pandoc, MyST, tree-sitter-markdown; but directive specs vary |

**Weighted: 7.4/10**

**Strengths:** Preserves the "document-is-program" philosophy that is Cell's
philosophical core. LLMs write markdown more naturally than almost anything.
Prompts are just the body text — no quoting, no escaping, no ceremony.
**Weaknesses:** Markdown was not designed for structured data. Even with MyST
directives, the DAG structure is implicit (ordering in document ≠ dependency
order). Edge cases in CommonMark parsing are notorious. The "deterministic parsing"
claim is weaker than it looks — Markdown has many interacting rules.

---

## Comparison Matrix

| Candidate | Parse | LLM | Graph | Prose | Homo | Tool | **Weighted** |
|-----------|-------|-----|-------|-------|------|------|:------------:|
| S-expressions | 10 | 7 | 9 | 4 | 10 | 7 | **7.9** |
| **Starlark** | 9 | 10 | 7 | 7 | 5 | 8 | **8.2** |
| CUE | 10 | 5 | 9 | 7 | 6 | 8 | 7.3 |
| **HCL** | 9 | 8 | 9 | 9 | 3 | 9 | **8.1** |
| KDL | 9 | 3 | 8 | 8 | 7 | 5 | 6.1 |
| EDN | 9 | 5 | 9 | 5 | 9 | 6 | 7.1 |
| Dhall | 10 | 3 | 8 | 7 | 4 | 6 | 5.9 |
| Structured MD | 7 | 9 | 5 | 10 | 6 | 7 | 7.4 |

---

## Recommendation: Top 3

### Tier 1: Starlark (8.2/10) — "The pragmatist's choice"

**Why:** LLMs write Python better than anything. Starlark is a deterministic subset
of Python with no I/O, guaranteed termination, and well-specified semantics. The
cell-to-beads transformation becomes a simple Starlark evaluation: execute the file,
get a list of cell declarations, create beads.

**The killer advantage:** When an LLM "pretend tests" a Starlark Cell program, it's
just reading Python. Zero learning curve. Zero syntax confusion. The format is
invisible — the LLM sees function calls it already understands.

**The risk:** Not homoiconic. Cell programs that generate Cell programs would need
to construct Starlark source as strings. But Cell's `§quotation` could be implemented
as a wrapper that serializes a cell struct to Starlark source — the metaprogramming
is one level removed, not impossible.

**Go implementation:** `go.starlark.net` (Google's official Go Starlark interpreter).

### Tier 1: HCL (8.1/10) — "The infrastructure choice"

**Why:** HCL was designed for *exactly this problem*: declaring named resources with
typed attributes and dependency relationships. The `cell "name" { given = [...] }`
pattern is HCL's native idiom. Heredocs handle prompts beautifully. The Go parser
is production-grade.

**The killer advantage:** Terraform proved that HCL can express massive dependency
graphs (thousands of resources) with clear, readable syntax. The `hashicorp/hcl`
library handles parsing, evaluation, and schema validation in one package.

**The risk:** Terraform contamination — LLMs might hallucinate `resource`, `provider`,
`data` blocks. No homoiconicity means `§quotation` has no structural analog.

**Go implementation:** `github.com/hashicorp/hcl/v2` (HashiCorp, battle-tested).

### Tier 2: S-Expressions (7.9/10) — "The purist's choice"

**Why:** Cell is metacircular. It bootstraps itself. Programs generate programs.
`§quotation` is literally quasiquote. S-expressions are the only format where
homoiconicity is not bolted on but inherent. If Cell's self-bootstrapping nature
is the priority, s-exprs are the right answer.

**The killer advantage:** `(quote ...)` maps to `§`. `(unquote ...)` maps to `«»`.
The entire quotation/interpolation system is just Lisp macros. A Cell program
that generates another Cell program is structurally identical to a Lisp macro
that generates Lisp code — the most battle-tested metaprogramming pattern in CS.

**The risk:** Prose comfort is genuinely poor. Prompts like "Sort the items in
ascending order, paying attention to edge cases where..." look bad wrapped in
parentheses. LLMs occasionally miscounts nesting depth.

**Go implementation:** Many options; trivial to write a custom one.

---

## Strategic Analysis

The choice depends on which of Cell's properties you prioritize:

| Priority | Best choice | Why |
|----------|-------------|-----|
| Get something working NOW | **Starlark** | LLMs already write it; Go impl exists; lowest friction |
| Long-term infrastructure | **HCL** | Designed for resource graphs; mature tooling; scales |
| Metacircularity above all | **S-expressions** | Homoiconicity is not optional for self-bootstrapping |
| Document-is-program philosophy | **Structured MD** | Prose-first; but weakest on deterministic parsing |

### The Hybrid Option

There's a strong case for using **two layers**:

1. **Human/LLM authoring layer**: Keep a prose-friendly format (the v0.2 turnstile
   syntax or structured markdown) for *writing* Cell programs
2. **Intermediate representation**: Use Starlark or S-expressions as the
   deterministic IR that `cell-to-beads` actually consumes

The authoring format would have a deterministic lowering to the IR. The IR would
have a deterministic transformation to beads. This separates "what humans/LLMs
write" from "what the toolchain consumes" — the same pattern as every real
compiler (source → AST → IR → machine code).

The v0.2 turnstile syntax would become a *surface syntax* that compiles to
the IR, rather than trying to be both human-readable AND machine-parseable.

### What This Means for cell-to-beads

Regardless of choice, the transformation pipeline becomes:

```
.cell file (any surface syntax)
    │
    ▼
Surface parser (turnstile → IR, or markdown → IR, or direct IR authoring)
    │
    ▼
IR (Starlark/HCL/S-expr) ← deterministic, validated, unambiguous
    │
    ▼
cell-to-beads (IR → bd create + bd dep add)
    │
    ▼
Beads execution substrate
```

The IR is the **single source of truth** for what a Cell program means. Multiple
surface syntaxes can target it. The cell-to-beads transformation is trivial because
the IR is unambiguous.

---

## Candidates NOT Recommended

| Candidate | Why not |
|-----------|---------|
| **YAML** | Already one of the two inconsistent syntaxes. Implicit type coercion ("Norway problem"), multiple string styles, indentation sensitivity all make it unreliable for deterministic transformation. |
| **TOML** | Already the other inconsistent syntax. Poor for nested structures; tables-of-tables syntax is confusing. |
| **JSON** | No comments, no multi-line strings, no trailing commas. Hostile to prose-heavy content. JSON5 helps but lacks ecosystem. |
| **Pkl** | Apple's config language. Too new, poor LLM training data, JVM-only runtime. |
| **Nickel** | Contract system is interesting but Nix-like syntax confuses LLMs. Tiny ecosystem. |
| **Nix** | Powerful but notoriously hard to parse correctly. Lazy evaluation semantics are orthogonal to Cell's needs. |
| **Protocol Buffers** | Schema-first is good but .proto files describe *types*, not *instances*. Text proto format for instances is not widely supported. |
| **GraphQL SDL** | Describes type schemas, not instance graphs. Wrong abstraction level. |
| **DOT/Graphviz** | Graph description but no metadata richness. Nodes can't carry structured attributes. |
