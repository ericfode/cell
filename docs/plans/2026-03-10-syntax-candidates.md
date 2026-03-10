# Cell Syntax Candidates — Morpheus Dreaming

**Bead**: ce-hyl
**Date**: 2026-03-10
**Principle**: The syntax must pass the pretend test. An LLM reading it cold
should be able to eval-one (execute the next ready cell). Prompts must be
visually distinct from logic.

---

## Design Tensions

1. **Prompts vs logic**: Prompts are natural language (long, flowing). Logic is
   structural (short, precise). They must coexist without one corrupting the other.
2. **Readability vs parsability**: LLMs read prose. Parsers need delimiters.
   But if an LLM can parse it, a parser can too (eventually, via distillation).
3. **Eval-one clarity**: Looking at the program + current state, it must be
   obvious which cell executes next and what its inputs are.
4. **Self-reference**: The syntax must be able to describe modifications to
   programs written in itself (graph operations).

## Lessons from the Masters

**Lisp**: Code is data. The program is a data structure the interpreter walks.
Cell programs should be data structures an LLM walks. But NOT s-expressions —
LLMs are bad at matching parens.

**Forth**: Start with nothing, bootstrap everything. The entire language is
defined in terms of a few primitives. Cell's "primitives" are: produce output,
reference input, depend on cell, rewrite graph.

**Smalltalk**: Everything is a message. A cell doesn't "call" another cell — it
sends it a message (its inputs) and receives a response (its output). The prompt
IS the message.

**Spreadsheets**: Formulas are inline, reactive, referential. `=A1+B1` is
simultaneously a declaration and a computation. Cell formulas should feel this
natural.

**Haskell**: Types constrain. The effect algebra (proven in Lean) tells us that
cell composition is a graded monad. The syntax should make composition natural.

**Datalog**: Declarative. You state what's true, not how to compute it. A Cell
program states what each cell produces given its inputs — the runtime decides
execution order.

---

## Candidate 1: "Literate" — Markdown-native

Inspired by: literate programming (Knuth), Jupyter notebooks

The Cell program IS a markdown document. Headings are cells. Code blocks are
scripts. Everything else is prompts. Dependencies are hyperlinks.

```markdown
# hello

Needs: name (string, required)

## greet

You are friendly and concise.

Say hello to {name} in one sentence.

Produces: { message: string }

## wrap (after greet)

You format messages for display.

Take this greeting and add an appropriate emoji:
{greet.message}

Produces: { text: string, emoji: string }
```

**Prompt/logic separation**: Prompts are prose paragraphs. Logic is in the
heading line (`after greet`) and `Produces:` / `Needs:` declarations.

**Eval-one test**: Read the doc. Find a section with no `after` dependencies
(or whose dependencies are done). That's the next cell. The section body IS
the prompt. `Produces:` tells you the output shape.

**Pros**:
- LLMs are pre-trained on millions of markdown documents
- Zero new syntax to learn — it IS markdown
- Renders beautifully in any viewer
- Prompts dominate visually (they ARE the document)

**Cons**:
- How do you distinguish system vs user prompt sections?
- Script cells need special handling (code blocks?)
- Graph operations feel awkward in prose
- No obvious place for oracles

---

## Candidate 2: "Dialogue" — Conversation-shaped

Inspired by: chat transcripts, play scripts, screenwriting

A Cell program looks like a scripted conversation. Each cell is a "scene"
between the system and the LLM. Dependencies are stage directions.

```
HELLO
  needs name

GREET
  [system] You are friendly and concise.
  [user]   Say hello to {name} in one sentence.
  [expect] { message: string }

WRAP (after GREET)
  [system] You format messages for display.
  [user]   Take this greeting and add an appropriate emoji:
           {greet.message}
  [expect] { text: string, emoji: string }
```

**Prompt/logic separation**: `[system]` and `[user]` tags are explicit. Logic
is in the cell header line and `[expect]` declarations.

**Eval-one test**: Find a cell whose `after` dependencies are satisfied. The
`[system]` and `[user]` blocks are the prompt. `[expect]` is the output shape.

**Pros**:
- Very close to how chat APIs actually work (system/user/assistant messages)
- LLMs understand conversation format natively
- Clear visual separation of prompt roles
- Compact

**Cons**:
- The `[tags]` feel parser-oriented
- Doesn't feel like a "programming language"
- Graph operations don't have a natural place
- Script cells would need a `[bash]` or `[script]` tag

---

## Candidate 3: "Spreadsheet" — Formula-first

Inspired by: Excel, Google Sheets, reactive programming

Each cell IS a formula. The syntax focuses on what each cell computes from
what inputs. Prompts are the "formula body."

```
hello(name):

  greet = ask(
    system: You are friendly and concise.
    user:   Say hello to {name} in one sentence.
  ) -> { message: string }

  wrap = ask(greet,
    system: You format messages for display.
    user:   Add an emoji to: {greet.message}
  ) -> { text: string, emoji: string }
```

**Prompt/logic separation**: `ask(...)` is the prompt invocation. Everything
outside `ask()` is logic (assignment, dependencies, output type).

**Eval-one test**: Find a cell whose referenced cells (in the `ask()` args)
all have values. Evaluate it. The `ask()` body is the prompt.

**Pros**:
- Dependencies are explicit in the formula (like `=A1+B1` references A1)
- Output types are clear (`-> { type }`)
- Feels like a real programming language
- Script cells: `run(bash: "echo hello")` — uniform syntax

**Cons**:
- The `ask()` function feels artificial
- Prompts inside parentheses get visually cramped
- Multi-paragraph prompts are awkward inside function calls
- LLMs might try to "evaluate" the function rather than produce the prompt

---

## Candidate 4: "Letter" — Epistolary

Inspired by: letters, memos, RFCs, Smalltalk message passing

Each cell is a letter from the programmer to the LLM. The letter has a header
(metadata) and a body (the prompt). Dependencies are "enclosures."

```
-- hello: a greeting program
-- needs: name (string)

--- greet ---
To: LLM
Role: You are friendly and concise.

Say hello to {name} in one sentence.

Reply with: { message: string }
---

--- wrap ---
To: LLM
Role: You format messages for display.
Encl: greet

Take this greeting and add an appropriate emoji:
{greet.message}

Reply with: { text: string, emoji: string }
---
```

**Prompt/logic separation**: Header lines (`To:`, `Role:`, `Encl:`, `Reply with:`)
are logic. Everything else is the prompt body. Like email headers vs body.

**Eval-one test**: Find a letter whose `Encl:` dependencies are answered.
Send it. The body is the prompt. `Reply with:` is the expected format.

**Pros**:
- Very natural metaphor — you're sending messages
- Headers cleanly separate metadata from content
- Multi-paragraph prompts are natural (it's a letter body)
- `Encl:` for dependencies is intuitive

**Cons**:
- `--- name ---` delimiters are parser-oriented
- Script cells don't fit the letter metaphor well
- Graph operations have no natural expression
- Feels more like config than code

---

## Candidate 5: "Blocks" — Indentation-driven

Inspired by: Python, YAML, Haskell (layout rule), Forth (words)

Structure is determined entirely by indentation. No closing delimiters. Cell
type is inferred from content. Prompts are indented text blocks.

```
hello
  name : string required

  greet : llm
    You are friendly and concise.

    Say hello to {name} in one sentence.

    -> { message : string }

  wrap : llm <- greet
    You format messages for display.

    Take this greeting and add an emoji:
    {greet.message}

    -> { text : string, emoji : string }
```

**Prompt/logic separation**: The cell header line (`greet : llm`) is logic.
Indented text below is the prompt. `->` declares output type. `<-` declares
dependencies.

**Eval-one test**: Find a cell whose `<-` dependencies have outputs. The
indented body (minus the `->` line) is the prompt.

**Pros**:
- Minimal syntax — no delimiters, no closing tags
- Prompts are visually dominant (they're the big indented blocks)
- `<-` and `->` are intuitive for data flow
- Script cells: just indent a code block
- Very close to how LLMs format structured text in responses

**Cons**:
- Indentation sensitivity can cause subtle bugs
- No way to distinguish system vs user prompt sections
- Where do oracles go?
- Multi-level nesting (molecules containing cells) might get confusing

---

## Candidate 6: "Hybrid" — Best of all worlds

Takes the best ideas from each candidate:
- From Literate: markdown rendering, prose-first
- From Dialogue: `[system]`/`[user]` tags for prompt roles
- From Spreadsheet: `{ref}` for dependencies, `->` for outputs
- From Blocks: indentation for structure, no closing delimiters

```
hello
  name : string required

  greet
    [system] You are friendly and concise.
    [user]   Say hello to {name} in one sentence.
    -> { message : string }

  wrap <- greet
    [system] You format messages for display.
    [user]   Take this greeting and add an emoji:
             {greet.message}
    -> { text : string, emoji : string }
```

**Prompt/logic separation**: Header line is logic. `[system]`/`[user]` tags
separate prompt roles. `->` declares output. `<-` declares dependencies.

**Eval-one test**: Find a cell with no `<-` or whose `<-` targets have values.
The `[system]` and `[user]` blocks are the prompt parts. `->` is the format.

**Pros**:
- Minimal but unambiguous
- Prompt roles are clear
- Dependencies and outputs read naturally (`<-` input, `->` output)
- Cell type is inferred (has `[system]`/`[user]` = llm, has code block = script)
- No closing delimiters

**Cons**:
- Still has `[tags]` — is that too parser-oriented?
- Graph operations need a syntax (maybe `!` prefix verbs?)
- Oracle blocks need a home

---

## What to test

For the syntax discovery formula (ce-s6y), test these candidates on:

1. **Pretend test (eval-one)**: give each to an LLM, ask "execute the next
   ready cell given name=Alice." Score correctness.
2. **Distillation test**: after execution, ask "rewrite the greet cell as a
   deterministic template." Score whether the distilled version preserves semantics.
3. **Readability test**: give each to a fresh LLM, ask "what does this program
   do?" Score accuracy of explanation.

**Hypothesis**: Candidates 1 (Literate) and 5/6 (Blocks/Hybrid) will score
highest because they match what LLMs naturally produce in their training data.

**Wild card**: The actual winner might be something none of these capture — a
syntax that emerges from asking LLMs to invent their own.
