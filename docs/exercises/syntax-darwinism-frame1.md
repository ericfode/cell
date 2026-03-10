# Syntax Darwinism — Frame 1

*Exercise bead: ce-vkiy*
*Generation: 0 → 1*

## SEED

```
candidates = ["literate", "dialogue", "spreadsheet", "letter", "blocks", "hybrid"]
program = "hello(name): greet the user, then wrap the greeting with an emoji"
generation = 0
```

## EXPRESS

Each candidate syntax writes the same program: `hello(name)` with two cells
(greet → wrap).

### 1. Literate

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

### 2. Dialogue

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

### 3. Spreadsheet

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

### 4. Letter

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

### 5. Blocks

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

### 6. Hybrid

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

## EVAL-ONE

For each expression, I read it cold with `name = "Alice"` and execute the next
ready cell.

### 1. Literate — execute greet

**Reading cold:** The `## greet` section has no `(after ...)` clause, so it's
ready. The `## wrap (after greet)` section depends on greet.

**Prompt construction:** The section body under `## greet` is the prompt:
> You are friendly and concise.
> Say hello to Alice in one sentence.

**Execution:** "Hello, Alice — welcome!"

**Output:** `{ message: "Hello, Alice — welcome!" }`

**Confidence: 8/10** — Clear which cell is ready, clear what the prompt is. Minor
issue: no explicit system/user separation — the entire section body is ambiguous
about prompt role. "You are friendly and concise" reads as system instruction, but
nothing enforces that. Also `Produces:` could be confused with part of the prompt.

### 2. Dialogue — execute GREET

**Reading cold:** GREET has no `(after ...)`. WRAP has `(after GREET)`. GREET is ready.

**Prompt construction:**
- System: "You are friendly and concise."
- User: "Say hello to Alice in one sentence."

**Execution:** "Hello, Alice — great to see you!"

**Output:** `{ message: "Hello, Alice — great to see you!" }`

**Confidence: 9/10** — System/user split is explicit and unambiguous. The `[expect]`
clearly defines output shape. Dependency is obvious. The only friction: UPPERCASE
cell names feel like shouting, and `[expect]` could be confused with an assertion
rather than a format spec.

### 3. Spreadsheet — execute greet

**Reading cold:** `greet = ask(...)` has no cell references in its args. `wrap = ask(greet, ...)`
depends on greet. So greet is ready.

**Prompt construction:**
- System: "You are friendly and concise."
- User: "Say hello to Alice in one sentence."

**Execution:** "Hey Alice, nice to meet you!"

**Output:** `{ message: "Hey Alice, nice to meet you!" }`

**Confidence: 7/10** — Dependencies are implicit in function args, which is elegant
but requires careful reading. The `ask()` wrapper creates ambiguity: am I supposed
to evaluate `ask()` as a function call, or extract the prompt from inside it? The
system/user labels inside `ask()` parentheses feel cramped. For a cold reader, the
parenthesized structure competes with the prose content.

### 4. Letter — execute greet

**Reading cold:** `--- greet ---` has no `Encl:` line. `--- wrap ---` has `Encl: greet`.
So greet is ready.

**Prompt construction:**
- Role (system): "You are friendly and concise."
- Body (user): "Say hello to Alice in one sentence."

**Execution:** "Hello there, Alice!"

**Output:** `{ message: "Hello there, Alice!" }`

**Confidence: 7/10** — The letter metaphor is charming and `Role:` / body / `Reply with:`
are clear. But `--- greet ---` delimiters are noisy. `Encl:` for dependencies is
creative but not immediately obvious (I had to think "enclosure = dependency").
The `To: LLM` line is redundant (who else?). Multi-line body is natural, which is
a strength for longer prompts.

### 5. Blocks — execute greet

**Reading cold:** `greet : llm` has no `<-` dependency. `wrap : llm <- greet`
depends on greet. So greet is ready.

**Prompt construction:** The indented text block is the prompt:
> You are friendly and concise.
> Say hello to Alice in one sentence.

**Execution:** "Hello, Alice!"

**Output:** `{ message: "Hello, Alice!" }`

**Confidence: 8/10** — Clean and minimal. `<-` and `->` read naturally as data
flow. The prompt body is visually dominant. Same issue as literate: no system/user
split — the whole indented block is ambiguous about prompt role. `: llm` type
annotation is clear but might confuse LLMs into thinking they need to emit
that type.

### 6. Hybrid — execute greet

**Reading cold:** `greet` has no `<-`. `wrap <- greet` depends on greet. So greet
is ready.

**Prompt construction:**
- System: "You are friendly and concise."
- User: "Say hello to Alice in one sentence."

**Execution:** "Hi Alice, lovely to meet you!"

**Output:** `{ message: "Hi Alice, lovely to meet you!" }`

**Confidence: 9/10** — Best of both worlds. `[system]`/`[user]` from dialogue
combined with `<-`/`->` from blocks. Clean, minimal, unambiguous. The indentation
structure from blocks makes it readable, the tags from dialogue make prompt roles
explicit. Only nitpick: `[system]` and `[user]` tags might feel parser-oriented
rather than natural.

## SCORES

| Candidate | Confidence | Key Strength | Key Weakness |
|-----------|-----------|--------------|--------------|
| literate | 8 | Zero new syntax, renders everywhere | No system/user split |
| dialogue | 9 | Explicit prompt roles, maps to API | UPPERCASE feels dated |
| spreadsheet | 7 | Dependencies in formula args | ask() wrapper creates ambiguity |
| letter | 7 | Natural metaphor, long prompts | Noisy delimiters, Encl: opaque |
| blocks | 8 | Minimal, clean data flow | No system/user split |
| hybrid | 9 | Combines best features | Tags might feel parser-ish |

## CULL

**Surviving** (top half, ceil(6/2) = 3): dialogue (9), hybrid (9), literate (8)

**Eliminated** (bottom half): blocks (8), spreadsheet (7), letter (7)

### Reasoning

**spreadsheet eliminated (7):** The `ask()` function wrapper creates a
fundamental tension — when an LLM reads `greet = ask(system: ..., user: ...)`,
it's unclear whether to evaluate this as a function call or extract the prompt
content. The parenthesized structure makes long prompts cramped. Dependencies
hidden in function arguments require careful parsing. The abstraction adds
friction rather than clarity.

**letter eliminated (7):** The `--- name ---` delimiters are syntactic noise
that doesn't help the LLM understand the program. `Encl:` for dependencies is
creative but requires a mental mapping step ("enclosure = I depend on this").
The `To: LLM` line is redundant. While the letter metaphor is charming for
simple cases, it doesn't scale — script cells, oracles, and graph operations
have no natural expression in the epistolary format.

**blocks eliminated (8):** Scored well on minimalism and data flow, but loses
the tiebreak against literate because blocks and literate share the same
weakness (no system/user split) while literate has the additional strength of
rendering as valid markdown everywhere. Blocks' `: llm` type annotation is
information that could be inferred. The real decider: literate's markdown
rendering means programs are their own documentation — a property blocks
doesn't have.

**Note on tiebreak (blocks vs literate, both 8):** This was the closest call.
Blocks is arguably cleaner for execution, but literate wins on ecosystem
compatibility. A blocks program requires a Cell-aware tool to view. A literate
program renders in GitHub, VS Code, Notion, or any browser. For a language
that claims "the document IS the program IS the state," being a valid document
format matters.

## Result JSON

```json
{
  "cell": "evolve",
  "frame": 1,
  "express": [
    {"candidate": "literate", "code": "# hello\n\nNeeds: name (string, required)\n\n## greet\n\nYou are friendly and concise.\n\nSay hello to {name} in one sentence.\n\nProduces: { message: string }\n\n## wrap (after greet)\n\nYou format messages for display.\n\nTake this greeting and add an appropriate emoji:\n{greet.message}\n\nProduces: { text: string, emoji: string }"},
    {"candidate": "dialogue", "code": "HELLO\n  needs name\n\nGREET\n  [system] You are friendly and concise.\n  [user]   Say hello to {name} in one sentence.\n  [expect] { message: string }\n\nWRAP (after GREET)\n  [system] You format messages for display.\n  [user]   Take this greeting and add an appropriate emoji:\n           {greet.message}\n  [expect] { text: string, emoji: string }"},
    {"candidate": "spreadsheet", "code": "hello(name):\n\n  greet = ask(\n    system: You are friendly and concise.\n    user:   Say hello to {name} in one sentence.\n  ) -> { message: string }\n\n  wrap = ask(greet,\n    system: You format messages for display.\n    user:   Add an emoji to: {greet.message}\n  ) -> { text: string, emoji: string }"},
    {"candidate": "letter", "code": "-- hello: a greeting program\n-- needs: name (string)\n\n--- greet ---\nTo: LLM\nRole: You are friendly and concise.\n\nSay hello to {name} in one sentence.\n\nReply with: { message: string }\n---\n\n--- wrap ---\nTo: LLM\nRole: You format messages for display.\nEncl: greet\n\nTake this greeting and add an appropriate emoji:\n{greet.message}\n\nReply with: { text: string, emoji: string }\n---"},
    {"candidate": "blocks", "code": "hello\n  name : string required\n\n  greet : llm\n    You are friendly and concise.\n\n    Say hello to {name} in one sentence.\n\n    -> { message : string }\n\n  wrap : llm <- greet\n    You format messages for display.\n\n    Take this greeting and add an emoji:\n    {greet.message}\n\n    -> { text : string, emoji : string }"},
    {"candidate": "hybrid", "code": "hello\n  name : string required\n\n  greet\n    [system] You are friendly and concise.\n    [user]   Say hello to {name} in one sentence.\n    -> { message : string }\n\n  wrap <- greet\n    [system] You format messages for display.\n    [user]   Take this greeting and add an emoji:\n             {greet.message}\n    -> { text : string, emoji : string }"}
  ],
  "eval_one": [
    {"candidate": "literate", "cell_executed": "greet", "output": {"message": "Hello, Alice — welcome!"}, "confidence": 8},
    {"candidate": "dialogue", "cell_executed": "GREET", "output": {"message": "Hello, Alice — great to see you!"}, "confidence": 9},
    {"candidate": "spreadsheet", "cell_executed": "greet", "output": {"message": "Hey Alice, nice to meet you!"}, "confidence": 7},
    {"candidate": "letter", "cell_executed": "greet", "output": {"message": "Hello there, Alice!"}, "confidence": 7},
    {"candidate": "blocks", "cell_executed": "greet", "output": {"message": "Hello, Alice!"}, "confidence": 8},
    {"candidate": "hybrid", "cell_executed": "greet", "output": {"message": "Hi Alice, lovely to meet you!"}, "confidence": 9}
  ],
  "scores": [
    {"candidate": "literate", "score": 8},
    {"candidate": "dialogue", "score": 9},
    {"candidate": "spreadsheet", "score": 7},
    {"candidate": "letter", "score": 7},
    {"candidate": "blocks", "score": 8},
    {"candidate": "hybrid", "score": 9}
  ],
  "cull": {
    "surviving": ["dialogue", "hybrid", "literate"],
    "eliminated": ["blocks", "spreadsheet", "letter"],
    "reasoning": "spreadsheet (7): ask() wrapper creates execution ambiguity, cramped prompts. letter (7): noisy delimiters, Encl: dependency syntax is opaque, format doesn't scale to oracles/scripts. blocks (8): loses tiebreak to literate — same weakness (no system/user split) but literate renders as valid markdown everywhere, supporting the document-is-program principle."
  },
  "generation": 1,
  "until": "length(surviving) <= 1? false"
}
```
