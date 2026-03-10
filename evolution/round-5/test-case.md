# Round 5: Crystallization + Oracle Failure

## Goal

Two questions:
1. What does it look like when a cell crystallizes?
   (∴ natural language → deterministic implementation)
2. What happens when an oracle fails?
   (retry? replace? escalate?)

## Test programs

### T1: Crystallized cell
A cell that has ALREADY been crystallized — its ∴ block
is replaced by deterministic logic. What does this look like?

### T2: Partial crystallization
A cell where SOME oracles have been crystallized into checks
but the ∴ body is still natural language.

### T3: Oracle failure → retry
A cell that might fail its oracle. What syntax expresses
"if oracle fails, try again"?

### T4: Oracle failure → evolve
A cell that fails its oracle and spawns a BETTER version
of itself. Self-modification under oracle pressure.

### T5: Mixed crystal/soft pipeline
A crystallized cell feeds into an LLM-interpreted cell.
Does composition work? Can you mix deterministic and
non-deterministic cells freely?
