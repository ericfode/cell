# R14 Frame 0 Results: Syntax Darwinism — Cold Read Tournament

**Evaluator**: polecat guzzle (cold read, no prior syntax training)
**Date**: 2026-03-10
**Program**: Translate & Verify (4-cell pipeline)

---

## Evaluation Criteria (each 1-10)

1. **Cold-read clarity**: Can the structure be parsed on first read?
2. **Feature expression**: Does syntax naturally accommodate all Cell features?
3. **Ambiguity resistance**: Are there parsing ambiguities or confusable constructs?
4. **Density**: Information per line (conciseness without sacrificing clarity)
5. **Extensibility**: Could the syntax accommodate spawners, loops, future features?

---

## S1: Turnstile (`⊢`, `∴`, `⊨`)

**Cold-read clarity: 8/10**
The `⊢` symbol is recognizable from formal logic ("proves"/"entails"). `given`/`yield`
are natural English keywords that immediately convey input/output. The structure is
instantly parseable: cell header → inputs → outputs → instruction → oracles. The `⊢=`
modifier for crystallized cells is a natural extension ("proves deterministically").

**Feature expression: 9/10**
All features map naturally to syntax: `⊢` (cell), `⊢=` (crystallized), `∴` (instruction),
`⊨` (oracle), `⊨?` (recovery), `⊥?` (bottom skip), `≡` (constant). Each feature has
its own dedicated symbol with a clear semantic role. The `given`/`yield` keywords clearly
separate inputs from outputs.

**Ambiguity resistance: 7/10**
The `⊢` family (`⊢`, `⊢=`, `⊢∘`, `⊢⊢`) uses compositional prefixes, which is elegant
but means 4 similar-looking symbols. In dense code, `⊢` vs `⊢=` could be missed. The
`«»` reference quoting adds visual noise but is unambiguous. The `⊨` vs `⊨?` distinction
is clear (presence/absence of `?`).

**Density: 8/10**
Compact without being cryptic. `⊢ seed` is 6 characters. Oracle lines like
`⊨ confidence ∈ [0.0, 1.0]` are both dense and readable. The `⊨? on failure:` block
is slightly verbose but clear.

**Extensibility: 9/10**
The `⊢` prefix family extends naturally — `⊢∘` (loop), `⊢⊢` (spawner) already work.
New modifiers could be added (`⊢?` for conditional, `⊢!` for side-effect) without
breaking existing syntax. The keyword+sigil approach is compositional.

**Total: 41/50**

---

## S2: Proof-Style (`theorem`, `proof:`, `check:`)

**Cold-read clarity: 9/10**
Maximum readability. Every keyword is a full English word: `theorem`, `assume`, `show`,
`proof`, `check`, `recover`, `fallback`, `compute`. No Unicode symbols to look up.
The mental model maps naturally: "given assumptions, show outputs by following proof,
then check constraints."

**Feature expression: 7/10**
Standard cells and oracles map well. The distinction between `compute:` (crystallized)
and `proof:` (soft/LLM) is clear but uses different sections rather than a uniform
modifier. Recovery (`recover:`) and bottom handling (`fallback:`) are clear individually
but feel like ad-hoc keyword additions. The `: String` / `: Float` type annotations
add visual noise — Cell enforces types via oracles, not declarations.

**Ambiguity resistance: 9/10**
Very low ambiguity. Each section has a unique keyword header. No sigil overloading.
No symbols that could be confused with each other. The cost is verbosity.

**Density: 5/10**
Most verbose candidate. `assume seed→phrase : String` uses 28 characters for what
S1 does in `given seed→phrase` (15 characters). The section headers (`proof:`,
`check:`, `recover:`) add structural lines. Total program length ~50% longer than S1.

**Extensibility: 7/10**
Adding loops requires a new section keyword (`evolve:` or `iterate:`). Adding spawners
requires another (`spawn:`). Each new Cell feature means a new keyword, risking
proliferation. However, the section-based structure is naturally extensible if you
accept growing vocabulary.

**Total: 37/50**

---

## S3: Natural-Minimal (`cell`, `in:`, `out:`, `do:`, `ok:`)

**Cold-read clarity: 9/10**
Maximum accessibility. `cell`, `in`, `out`, `do`, `ok` are basic English words
understood by any reader. The colon-delimited keys feel like a config file. A
non-programmer could roughly parse this program.

**Feature expression: 6/10**
Basic cells and oracles work fine. But crystallized computation creates category
confusion: `set:` (constant binding) vs `compute:` (deterministic formula) vs `do:`
(LLM instruction) — three different keywords for three levels of computation that
S1 handles with just `≡`, `⊢=`, and `∴`. The `retry:`, `fail:`, `if-bottom:` keywords
are clear but feel like ad-hoc patches.

**Ambiguity resistance: 7/10**
`set:` could be mistaken for variable assignment. `compute:` vs `set:` — when do you
use which? `{var}` interpolation using braces conflicts with JSON/set notation
(confusable with `{"faithful", "drifted"}`). The `ok:` prefix is clear but doesn't
distinguish oracle severity.

**Density: 7/10**
Keywords are short but lines tend longer due to natural English. The `do:` section
flows naturally but occupies more vertical space than S1's `∴` block.

**Extensibility: 5/10**
Each new Cell feature requires a new keyword. Loops → `loop:`, `until:`. Spawners →
`spawn:`, `each:`. No composable primitive; the syntax is a flat keyword vocabulary
that grows linearly with features.

**Total: 34/50**

---

## S4: Lambda-Math (`λ`, `∴`, `⊨`)

**Cold-read clarity: 7/10**
Familiar to anyone who knows lambda calculus, but that's a narrow audience. The
inline signature (`λ translate : seed.phrase, seed.target-lang → translation, confidence`)
packs inputs, name, and outputs into one line — efficient but dense. The mix of
`λ` declarations with `⊢=` sub-notations and `⊥?` from S1 creates a hybrid that
borrows from two worlds.

**Feature expression: 8/10**
All features expressible. The inline signature is very compact. But the inconsistency
between `λ` (cell declaration) and `⊢=` (crystallized sub-computation) means the
syntax doesn't have a single unifying principle. Why `λ` at top level but `⊢=` inside?
The recovery notation `⊨? retry(2, append(...))` uses function-call syntax that
looks different from the rest.

**Ambiguity resistance: 6/10**
`→` in the signature conflicts with `→` as data flow reference (`seed→phrase` uses
the same arrow). Is `seed.phrase` different from `seed→phrase`? Both appear in the
program. The compressed recovery syntax `⊨? exhaust → ⊥` uses yet another meaning
for `→`.

**Density: 9/10**
Most compact candidate. The lambda signature line carries everything. Oracle lines
are terse. The total program is ~25% shorter than S1.

**Extensibility: 7/10**
Lambda notation extends naturally to higher-order cells (cells that take cells as
arguments). But the inconsistency between `λ` and `⊢=` would worsen as new features
add more sub-notations.

**Total: 37/50**

---

## S5: Conversation (`@name()`, `?` checks)

**Cold-read clarity: 7/10**
The `@` prefix is familiar from social media, decorators, and email. `?` for oracles
is intuitive ("is this true?"). But the body text (LLM instruction) has NO explicit
delimiter — it's just free text between the signature and the first `?` line. This
relies on convention, not syntax.

**Feature expression: 6/10**
Basic cells and oracles work. But crystallized computation uses `#=` which is not
self-explanatory (why `#`?). The `!⊥` for bottom-skip is clever but cryptic. `??` for
oracle recovery is visually similar to `?` — easy to miss the doubled character.

**Ambiguity resistance: 5/10**
The instruction body has no explicit boundary. If instruction text contains a line
starting with `?`, the parser can't distinguish it from an oracle. `??` vs `?` is a
visual-similarity hazard that would cause real bugs. `!⊥` uses two unrelated symbols
(`!` for "not" + `⊥` for "bottom") to mean "on bottom".

**Density: 8/10**
Compact. The `@name(inputs) → outputs` signature is concise. Oracle lines are short.
But the lack of body delimiters trades structural safety for visual brevity.

**Extensibility: 5/10**
Adding features means more sigil variants: loops (`@∘`?), spawners (`@@`?). The `@`
prefix is already overloaded in most programming contexts. The `?`/`??` pattern doesn't
scale to `???` for a third level.

**Total: 31/50**

---

## S6: Arrow-Chain (`⟶`, `「」`, `◈`)

**Cold-read clarity: 6/10**
The Japanese brackets `「」` are visually striking and unambiguous as instruction
delimiters, but unfamiliar to most readers. `◈` (diamond) for oracles suggests "check
point" but is not self-evident. The colon-prefix cell declaration (`translate:`) is
clean. `⟶` as data flow arrow is intuitive.

**Feature expression: 7/10**
All features map, but each uses a different, seemingly arbitrary Unicode symbol:
`⟶` (flow), `「」` (instruction), `◈` (oracle), `◈?` (recovery), `⊥⟶` (bottom skip),
`═` (crystallized). This is a large symbol vocabulary with no compositional principle
connecting them.

**Ambiguity resistance: 8/10**
All symbols are visually distinct — virtually no chance of confusing `◈` with `⟶` or
`「」` with `═`. The `「」` brackets provide explicit instruction boundaries (solving
S5's worst problem). Individual constructs are unambiguous.

**Density: 8/10**
Compact. The colon-signature style is clean. The `「」` brackets add only 2 characters
of overhead per instruction. Total program length is comparable to S1.

**Extensibility: 6/10**
Each new feature needs a new arbitrary Unicode symbol. Unlike S1's compositional `⊢`
family, S6's symbols have no shared root. Adding loops might use `∞⟶`? Spawners
`⟹`? There's no principled way to derive new symbols.

**Total: 35/50**

---

## Frame 0 Scoreboard

| Candidate | Clarity | Features | Ambiguity | Density | Extensibility | Total |
|-----------|---------|----------|-----------|---------|---------------|-------|
| **S1 turnstile** | 8 | 9 | 7 | 8 | 9 | **41** |
| **S2 proof-style** | 9 | 7 | 9 | 5 | 7 | **37** |
| **S4 lambda-math** | 7 | 8 | 6 | 9 | 7 | **37** |
| S6 arrow-chain | 6 | 7 | 8 | 8 | 6 | 35 |
| S3 natural-minimal | 9 | 6 | 7 | 7 | 5 | 34 |
| S5 conversation | 7 | 6 | 5 | 8 | 5 | 31 |

## Cull: Bottom 3 Eliminated

| Eliminated | Score | Fatal Flaw |
|------------|-------|------------|
| **S5 conversation** | 31 | Ambiguity: no instruction delimiter, `?`/`??` confusion |
| **S3 natural-minimal** | 34 | Extensibility: flat keyword vocab doesn't scale to loops/spawners |
| **S6 arrow-chain** | 35 | Extensibility: arbitrary symbols with no compositional principle |

## Survivors → Frame 1

| Survivor | Score | Strength | Weakness |
|----------|-------|----------|----------|
| **S1 turnstile** | 41 | Best overall balance; compositional `⊢` family | `⊢` family can look similar |
| **S2 proof-style** | 37 | Best clarity + ambiguity resistance | Verbose; 50% more tokens than S1 |
| **S4 lambda-math** | 37 | Best density; most compact | `→` overloading; hybrid borrowing from S1 |
