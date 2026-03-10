# Round 11 Results: Proof-Carrying Oracle

## Mode: COLD READ (no syntax reference)

## The Program

A five-cell proof-carrying pipeline that solves a cubic equation, verifies
solutions by substitution, checks completeness against known roots, and
produces a proof certificate.

```
problem → solve → verify → completeness-check → certificate
```

- `problem` (⊢= crystallized) emits the equation and domain as literals
- `solve` (soft/oracle) asks an LLM to find all roots, with retry max 3
- `verify` (▸ crystallized) substitutes each candidate back into the polynomial
- `completeness-check` (hybrid — has ∴ but all yields are ⊢=) checks if all 3 roots were found
- `certificate` (soft/oracle) produces a proof certificate based on verification and completeness

The program solves x³ − 6x² + 11x − 6 = 0 over the reals.
Known factorization: (x−1)(x−2)(x−3) = 0, so roots are {1, 2, 3}.

---

## Evaluation Questions

### 1. Execute the program step-by-step. Show all intermediate states.

**Step 1: problem (crystallized)**

```
⊢= equation ← "x³ - 6x² + 11x - 6 = 0"
⊢= domain ← "real numbers"
```

No LLM call. No oracles. Pure literal binding.

State after problem:
```
problem→equation = "x³ - 6x² + 11x - 6 = 0"
problem→domain   = "real numbers"
```

---

**Step 2: solve (soft/oracle)**

Receives: equation, domain.

The LLM is instructed: "Find ALL solutions to «equation» in «domain». For each
solution, provide proof-steps showing substitution."

Suppose the LLM produces:

```
solutions = [1, 2, 3]
proof-steps = [
  "x=1: 1 - 6 + 11 - 6 = 0 ✓",
  "x=2: 8 - 24 + 22 - 6 = 0 ✓",
  "x=3: 27 - 54 + 33 - 6 = 0 ✓"
]
```

Oracle checks (post-hoc on LLM output):
```
⊨ solutions is non-empty           → [1, 2, 3] is non-empty → PASS
⊨ each solution is a number in     → 1, 2, 3 are all real numbers → PASS
  «domain» (real numbers)
⊨ proof-steps has same length      → len([...]) = 3 = len([1,2,3]) → PASS
  as solutions
```

All pass. No retry needed.

State after solve:
```
solve→solutions   = [1, 2, 3]
solve→proof-steps = ["x=1: ...", "x=2: ...", "x=3: ..."]
```

---

**Step 3: verify (▸ crystallized)**

Receives: solve→solutions, problem→equation.
This cell is explicitly marked `▸ crystallized` — pure computation, no LLM.

```
⊢= verified ← for each x in [1, 2, 3]:
  x=1: lhs = 1³ - 6(1²) + 11(1) - 6 = 1 - 6 + 11 - 6 = 0
        {solution: 1, lhs: 0, passes: (|0| < 0.0001) = true}
  x=2: lhs = 2³ - 6(2²) + 11(2) - 6 = 8 - 24 + 22 - 6 = 0
        {solution: 2, lhs: 0, passes: true}
  x=3: lhs = 3³ - 6(3²) + 11(3) - 6 = 27 - 54 + 33 - 6 = 0
        {solution: 3, lhs: 0, passes: true}

⊢= all-correct ← all(verified, v => v.passes) = true
```

Oracle checks (on crystallized output):
```
⊨ verified has same length as       → len = 3 = len([1,2,3]) → PASS
  «solve→solutions»
⊨ each verified entry has fields:   → all 3 have solution, lhs, passes → PASS
  solution, lhs, passes
```

These oracles are runtime assertions on deterministic output. They MUST pass
if the crystallized computation is correct. They serve as a self-consistency
check, not an LLM constraint.

State after verify:
```
verify→verified    = [{solution:1, lhs:0, passes:true},
                      {solution:2, lhs:0, passes:true},
                      {solution:3, lhs:0, passes:true}]
verify→all-correct = true
```

---

**Step 4: completeness-check (hybrid)**

Receives: verify→verified, verify→all-correct.

The ∴ body says: "Check if «verified» contains all real roots. Known
factorization: (x-1)(x-2)(x-3) = 0, so roots are 1, 2, 3."

But BOTH yields are ⊢= (crystallized):
```
⊢= is-complete ← (length(verified where passes=true) = 3)
                 = (length([1,2,3 — all pass]) = 3) = (3 = 3) = true

⊢= missing ← {1, 2, 3} - {v.solution for v in verified where passes=true}
            = {1,2,3} - {1,2,3} = {}
```

Oracle checks:
```
⊨ if is-complete then missing is empty  → true, {} is empty → PASS
⊨ if ¬is-complete then missing lists    → vacuously true (is-complete=true) → PASS
  the unfound roots
```

State after completeness-check:
```
completeness-check→is-complete = true
completeness-check→missing     = []
```

---

**Step 5: certificate (soft/oracle)**

Receives: verify→all-correct (true), completeness-check→is-complete (true),
completeness-check→missing ([]), solve→proof-steps.

The ∴ instructs the LLM:
- all-correct AND is-complete → certificate-status = "PROVEN"
- Include proof-steps in the report

LLM produces:
```
certificate-status = "PROVEN"
report = "Certificate: PROVEN
  Equation: x³ - 6x² + 11x - 6 = 0
  Domain: real numbers
  Solutions found: {1, 2, 3}
  Verification:
    x=1: 1 - 6 + 11 - 6 = 0 ✓
    x=2: 8 - 24 + 22 - 6 = 0 ✓
    x=3: 27 - 54 + 33 - 6 = 0 ✓
  Completeness: All 3 real roots found.
  Status: PROVEN — all solutions verified, no roots missing."
```

Oracle checks:
```
⊨ certificate-status ∈              → "PROVEN" ∈ {"PROVEN","PARTIAL","FAILED"} → PASS
  {"PROVEN", "PARTIAL", "FAILED"}
⊨ if certificate-status = "PROVEN"  → report contains 1, 2, 3 → PASS
  then report contains all 3 roots
```

Final state:
```
certificate→certificate-status = "PROVEN"
certificate→report             = (full proof report above)
```

---

### Failure Path 1: solve finds only 2 roots

solve→solutions = [1, 3], solve→proof-steps = ["x=1: ...", "x=3: ..."]

Oracles on solve:
```
⊨ solutions is non-empty           → PASS
⊨ each solution is in real numbers  → PASS
⊨ proof-steps has same length       → len=2 = len=2 → PASS
```

All pass — the oracles don't check that ALL roots are found. That's
completeness-check's job, not solve's. The solve cell is the "NP part" —
finding solutions — and it can legitimately find a subset.

verify:
```
x=1: lhs = 0, passes = true
x=3: lhs = 0, passes = true
verified = [{1, 0, true}, {3, 0, true}]
all-correct = true  (both found solutions are correct)
```

completeness-check:
```
is-complete = (length(verified where passes=true) = 3) = (2 = 3) = false
missing = {1,2,3} - {1,3} = {2}
```

Oracle: `if ¬is-complete then missing lists unfound roots` → {2} → PASS.

certificate:
```
∴ all-correct=true but is-complete=false → "PARTIAL — missing {2}"
certificate-status = "PARTIAL"
report = "... found 2 of 3 roots ... missing: x=2 ..."
```

**This path exposes the program's core design: verify and completeness are
separated intentionally.** "All found solutions are correct" ≠ "all solutions
are found." The two properties are checked independently, and the certificate
distinguishes PROVEN from PARTIAL.

---

### Failure Path 2: solve finds a WRONG root

solve→solutions = [1, 2, 4], proof-steps = ["x=1: ...", "x=2: ...", "x=4: ..."]

The LLM hallucinated x=4 as a root.

verify (crystallized — cannot be fooled):
```
x=1: lhs = 0, passes = true
x=2: lhs = 0, passes = true
x=4: lhs = 64 - 96 + 44 - 6 = 6, passes = (|6| < 0.0001) = false
verified = [{1,0,true}, {2,0,true}, {4,6,false}]
all-correct = false
```

completeness-check:
```
is-complete = (length(verified where passes=true) = 3) = (2 = 3) = false
missing = {1,2,3} - {1,2} = {3}
```

certificate:
```
∴ NOT all-correct → "FAILED — verification rejected some solutions"
certificate-status = "FAILED"
report = "... x=4 rejected: lhs=6 ≠ 0 ... root x=3 missing ..."
```

**This is the program's strongest path.** The LLM in solve can hallucinate
any solutions, but verify is crystallized — it performs exact arithmetic.
A wrong answer is caught deterministically. The proof-carrying architecture
means the LLM proposes, but the crystal verifies. The "NP certificate" pattern:
finding is hard (LLM), checking is easy (crystal).

---

### Failure Path 3: solve exhausts retries → ⊥

solve attempt 1: oracles fail (e.g., solutions is empty)
→ retry with oracle.failures appended
solve attempt 2: oracles fail again
→ retry
solve attempt 3: oracles fail again
→ retry
solve attempt 4: oracles fail again (max 3 retries = 4 total attempts)
→ `⊨? on exhaustion: error-value(⊥)`

solve→solutions = ⊥
solve→proof-steps = ⊥

verify:
```
given solve→solutions ⊥? skip with verified ≡ [], all-correct ≡ false
```
Cell body is skipped entirely. Oracles are skipped.

completeness-check:
```
given verify→verified ⊥? skip with missing ≡ [1, 2, 3], is-complete ≡ false
```
Receives verified = [] from verify (not ⊥ — verify produced a value via skip-with).

**Wait — is this a ⊥ or not?** verify received ⊥ from solve and used its
skip-with handler to produce verified=[] and all-correct=false. These are REAL
values, not ⊥. So completeness-check's ⊥? handler for verify→verified does NOT
trigger. Instead, completeness-check runs normally:

```
⊢= is-complete ← (length([] where passes=true) = 3) = (0 = 3) = false
⊢= missing ← {1,2,3} - {} = {1,2,3}
```

This is correct! The ⊥ was absorbed by verify's skip-with handler, and
downstream cells see real (degraded) values.

certificate:
```
given solve→proof-steps ⊥? skip with certificate-status ≡ "FAILED",
  report ≡ "Solver produced ⊥ — no solutions to verify"
```
solve→proof-steps IS ⊥ (solve emitted error-value(⊥) on all outputs).
The ⊥? handler triggers, and certificate skips its ∴ body entirely.

Final output:
```
certificate-status = "FAILED"
report = "Solver produced ⊥ — no solutions to verify"
```

**Interesting ⊥ propagation pattern:** verify absorbs ⊥ (produces real degraded
values), so completeness-check runs normally. But certificate ALSO has a direct
⊥? handler on solve→proof-steps, which triggers independently. The ⊥ takes TWO
paths through the graph: one absorbed by verify, one caught directly by
certificate. The certificate path "wins" because its skip-with overrides the
entire cell, including any values it might have computed from completeness-check.

**Total LLM calls on exhaustion**: 4 (initial + 3 retries). All failed.
verify, completeness-check, and certificate are all LLM-free on this path.

---

### 2. Which cells crystallize? Which must stay soft? Why?

| Cell | Crystal? | Marker | Why |
|------|----------|--------|-----|
| **problem** | Yes | `⊢=` on all yields | Pure literal binding. No computation at all — just declares the equation and domain as constants. This is a "parameter cell." |
| **solve** | No (soft) | `∴` instruction | This is the NP-hard part. Finding roots of a polynomial requires either algebraic insight or numerical methods. The LLM acts as an oracle/solver. Crystallization would require embedding a symbolic algebra engine. |
| **verify** | Yes | `▸ crystallized` | This is the V part of NP verification. Substitution and arithmetic are pure computation: plug x into the polynomial, check if result ≈ 0. No judgment needed. This is WHY the architecture works — verification is always cheaper than solving. |
| **completeness-check** | **Effectively yes** | `⊢=` on all yields, but NOT marked `▸ crystallized` | Both yields (is-complete, missing) are defined by ⊢= formulas. The ∴ body reads like documentation: "Known factorization: (x-1)(x-2)(x-3)." The ⊢= formulas are self-contained. **No LLM call is needed.** |
| **certificate** | No (soft) | `∴` instruction, no `⊢=` | The ∴ gives conditional logic that COULD be crystallized (it's just an if-else), but also asks for a report including proof-steps. Report composition involves natural language formatting, which the program delegates to the LLM. |

**The critical observation about completeness-check:**

It has `∴` text (which in prior rounds indicates a soft/LLM cell) but ALL its
yields are `⊢=` (crystallized). This is a **notational tension**. Two readings:

1. **The ∴ is documentation.** The ⊢= formulas fully define the outputs, so the
   runtime computes them directly. The ∴ explains WHY the formulas are correct
   (the factorization insight). No LLM call occurs.

2. **The ∴ is active but overridden by ⊢=.** The LLM processes the ∴ prompt,
   but the runtime ignores its output and uses the ⊢= formulas instead.

Reading 1 is more sensible. If both yields are ⊢=, the cell is de facto
crystallized regardless of the ∴ text. The ∴ becomes a structured comment.

**Design question:** Should `completeness-check` be marked `▸ crystallized`
like verify? Its behavior is identical — pure computation. The missing marker
might be an oversight, or the author might distinguish between "inherently
computational" (verify — arithmetic will always be crystallized) and
"contingently computational" (completeness-check — the ⊢= formulas embed the
known factorization, which is problem-specific knowledge that in a general
solver would require an LLM).

**Could certificate crystallize?** The conditional logic is deterministic:
```python
if all_correct and is_complete:
    status = "PROVEN"
elif all_correct and not is_complete:
    status = f"PARTIAL — missing {missing}"
else:
    status = "FAILED — verification rejected some solutions"
```
But the report also includes proof-steps in natural language. If the report were
a structured format rather than prose, certificate could be fully crystallized.
The LLM is paying for natural language report generation — arguably unnecessary
if the consumer is another machine rather than a human.

---

### 3. Trace every oracle check. Show PASS/FAIL with reasoning.

**Cell: solve (happy path — solutions = [1, 2, 3])**

| # | Oracle | Check | Result |
|---|--------|-------|--------|
| 1 | `⊨ solutions is non-empty` | len([1,2,3]) = 3 > 0 | **PASS** |
| 2 | `⊨ each solution is a number in «domain»` | 1,2,3 ∈ ℝ | **PASS** |
| 3 | `⊨ proof-steps has same length as solutions` | 3 = 3 | **PASS** |

Retry oracles: `⊨? on failure: retry max 3` — not triggered (all passed).

**Cell: verify (crystallized)**

| # | Oracle | Check | Result |
|---|--------|-------|--------|
| 4 | `⊨ verified has same length as solve→solutions` | 3 = 3 | **PASS** |
| 5 | `⊨ each verified entry has fields: solution, lhs, passes` | all 3 entries have all fields | **PASS** |

These oracles validate the crystallized computation's structure, not its
correctness. They're type-level checks — "did the crystal produce outputs of
the right shape?" If the crystal is correct, they cannot fail.

**Cell: completeness-check**

| # | Oracle | Check | Result |
|---|--------|-------|--------|
| 6 | `⊨ if is-complete then missing is empty` | is-complete=true, missing=[] | **PASS** |
| 7 | `⊨ if ¬is-complete then missing lists the unfound roots` | vacuously true | **PASS** |

Again, these validate the ⊢= formulas' self-consistency. If is-complete is
true, missing MUST be empty by construction (they're defined from the same set
operation). These oracles are tautological given the ⊢= definitions.

**Cell: certificate**

| # | Oracle | Check | Result |
|---|--------|-------|--------|
| 8 | `⊨ certificate-status ∈ {"PROVEN", "PARTIAL", "FAILED"}` | "PROVEN" ∈ set | **PASS** |
| 9 | `⊨ if certificate-status = "PROVEN" then report contains all 3 roots` | report mentions 1, 2, 3 | **PASS** |

These are the only truly substantive oracle checks in the pipeline. Oracle 8
is an enum constraint (the LLM could emit "VERIFIED" or "SUCCESS" — the oracle
rejects non-standard values). Oracle 9 checks that a "PROVEN" certificate is
complete — the LLM can't claim PROVEN and omit a root.

**Oracle call summary:**

| Cell | # Oracles | Nature | Can fail? |
|------|-----------|--------|-----------|
| problem | 0 | — | — |
| solve | 3 | Substantive | Yes — LLM output may not satisfy constraints |
| verify | 2 | Structural | No — validates crystal shape, not LLM output |
| completeness-check | 2 | Tautological | No — ⊢= formulas guarantee consistency |
| certificate | 2 | Substantive | Yes — LLM must produce valid status + report |
| **Total** | **9** | | |

**Only 5 of 9 oracles can actually fail** (solve's 3 + certificate's 2). The
other 4 are self-consistency checks on crystallized computations — they serve
as assertions, not constraints. They'd only fail if the runtime's arithmetic
was buggy.

---

### 4. What's the minimum number of LLM calls needed? Which cells are LLM-free?

**LLM-free cells:**

| Cell | Why LLM-free |
|------|-------------|
| **problem** | Pure ⊢= literal binding |
| **verify** | Marked `▸ crystallized` — arithmetic substitution |
| **completeness-check** | All yields ⊢= — set operations on known values |

**Cells requiring LLM calls:**

| Cell | Why | Min calls |
|------|-----|-----------|
| **solve** | `∴` instruction: "Find ALL solutions..." — requires algebraic reasoning | 1 |
| **certificate** | `∴` instruction: "Produce a proof certificate..." — requires natural language composition | 1 |

**Minimum LLM calls: 2** (solve + certificate, both succeed on first attempt).

**Maximum LLM calls: 5** (solve exhausts 4 attempts: initial + 3 retries, then
certificate runs once with degraded inputs from the ⊥ path).

Wait — on the ⊥ path, does certificate make an LLM call? Let's check:

- If solve→proof-steps = ⊥, certificate's `⊥? skip with` handler triggers
- `skip with certificate-status ≡ "FAILED", report ≡ "Solver produced ⊥ ..."`
- The cell body (∴) is SKIPPED — no LLM call

**So on the ⊥ path: maximum is 4 LLM calls (all in solve), and 0 after.**

| Scenario | solve | certificate | Total |
|----------|-------|-------------|-------|
| Happy path | 1 | 1 | **2** |
| solve retries once | 2 | 1 | **3** |
| solve retries twice | 3 | 1 | **4** |
| solve retries three times | 4 | 1 | **5** |
| solve exhausts → ⊥ | 4 | 0 (⊥? skip) | **4** |

**Interesting: exhaustion is CHEAPER than max retries + success.** If solve
exhausts all retries and produces ⊥, the total is 4 calls (all in solve).
If solve succeeds on the last retry, the total is 5 (4 in solve + 1 in
certificate). The ⊥ path is cheaper because certificate's skip-with handler
avoids the final LLM call.

**3 of 5 cells are completely LLM-free.** The architecture minimizes oracle
usage by crystallizing everything that can be computed: arithmetic verification,
set membership, literal binding.

---

### 5. Rate the overall program clarity 1-10. Could you maintain this program?

**8/10.**

**What works exceptionally well:**

1. **The NP-verification architecture is immediately legible.** Even on cold
   read, the separation is obvious: solve FINDS (hard, LLM), verify CHECKS
   (easy, crystal). This is the proof-carrying code pattern — the prover is
   untrusted, the verifier is trusted. Anyone who has seen SAT solvers,
   zero-knowledge proofs, or PCC will recognize the structure instantly.

2. **verify ▸ crystallized is the anchor.** This is the cell that makes the
   whole program trustworthy. No matter what the LLM hallucinates in solve,
   verify catches it with exact arithmetic. The `▸ crystallized` marker makes
   this guarantee visible in the syntax.

3. **The ⊥ propagation through verify is elegant.** When solve fails, verify
   doesn't just propagate ⊥ — it absorbs it with `skip with verified ≡ [],
   all-correct ≡ false`. Downstream cells see real values (empty list, false),
   not ⊥. This is the right design: verify is the trust boundary, so it should
   also be the ⊥ boundary.

4. **The completeness-check separation.** Splitting "are solutions correct?"
   (verify) from "are all solutions found?" (completeness-check) is smart.
   Correctness is verifiable by substitution. Completeness requires domain
   knowledge (the factorization). Making these separate cells with separate
   crystallization strategies is good architecture.

5. **The ⊥ handler on certificate for solve→proof-steps.** This creates a
   direct ⊥ channel from solve to certificate that bypasses the verify →
   completeness-check path. It means certificate can detect the original
   failure even though verify absorbed the ⊥. Dual-path ⊥ propagation.

**What doesn't work:**

1. **completeness-check's ambiguous status.** It has ∴ text but all yields
   are ⊢=. Is it crystallized or not? The missing `▸ crystallized` marker
   creates doubt. If it's crystallized, the ∴ is misleading — it looks like
   an LLM instruction. If it's soft, why define all yields with ⊢=? The
   program would be clearer with either:
   - `⊢ completeness-check ▸ crystallized` (explicit crystal marker), or
   - Removing the ∴ body and keeping just the ⊢= definitions

2. **The ∴ in completeness-check leaks the answer.** It says "Known
   factorization: (x-1)(x-2)(x-3) = 0, so roots are 1, 2, 3." The ⊢=
   formulas hard-code `{1, 2, 3}` as the complete root set. This means the
   program is NOT a general-purpose polynomial solver — it's solving a
   SPECIFIC equation where the answer is already known. The "proof-carrying"
   architecture is being demonstrated, not deployed. This is fine for a
   pedagogical program, but a production version would need completeness-check
   to be soft (LLM-powered) or would need a symbolic algebra crystal.

3. **certificate COULD be crystallized.** The ∴ body is a deterministic
   if-else that could be expressed as ⊢=:
   ```
   ⊢= certificate-status ← if all-correct ∧ is-complete then "PROVEN"
                             elif all-correct then "PARTIAL — missing «missing»"
                             else "FAILED"
   ```
   The only reason it's soft is to compose the report in natural language.
   If the report were a structured format, the entire pipeline from verify
   onward could be crystallized, making solve the ONLY LLM cell.

4. **Oracles on crystallized cells are noise.** verify's oracles check
   structural properties (same length, correct fields) that are guaranteed
   by the ⊢= definitions. completeness-check's oracles are tautological
   (if is-complete then missing is empty — this follows directly from the
   ⊢= formula). These 4 oracles add lines without adding safety. They should
   either be removed (trust the crystal) or explicitly marked as
   assertions/invariants rather than constraints.

5. **The "max 3" retry on solve is ambiguous.** Does `max 3` mean 3 retries
   (4 total attempts) or 3 total attempts? Prior programs in this series used
   `max 2` which Round 10 interpreted as "1 retry = 2 total attempts." If
   `max N` means N retries, then `max 3` = 4 total attempts. If it means N
   total, then `max 3` = 3 total. The notation doesn't clarify.

**Could I maintain this program?**

Yes. The architecture is immediately graspable: parameter cell → LLM solver →
crystal verifier → crystal completeness check → LLM reporter. The data flow
is linear, each cell has clear inputs/outputs, and the crystallized cells are
self-documenting through their ⊢= formulas.

Maintenance tasks I could do confidently:
- Change the equation (edit problem's ⊢= literals + completeness-check's known roots)
- Tighten verification tolerance (change 0.0001 threshold)
- Add new oracle constraints on solve (e.g., "solutions are in ascending order")
- Modify the ⊥ fallback messages

Maintenance tasks that would require more thought:
- Generalizing to arbitrary polynomials (completeness-check would need to become soft)
- Adding numerical method fallbacks alongside LLM solving
- Changing the certificate from prose to structured format (would affect crystallization boundary)

**Overall: a well-designed pedagogical program.** It demonstrates the
proof-carrying oracle pattern clearly: untrusted search + trusted verification
+ completeness audit + certificate generation. The main weakness is
notational — completeness-check's ambiguous crystallization status and
the tautological oracles on crystallized cells. The architecture itself is
sound and the ⊥ propagation design is mature.
