# Round 10: ⊥ Propagation, Template Instantiation, Oracle-Spawner Interaction

## Focus
Three critical gaps from Round 9:
1. **⊥ propagation**: What happens when upstream fails? (fail-fast vs fail-soft vs skip)
2. **Template instantiation**: What does § copying mean mechanically?
3. **Oracle retry on spawned cells**: How does failure feedback work through ⊢⊢?

## What We're Testing

### T1: Bottom Propagation Pipeline
A 4-cell pipeline where the first cell can fail with ⊥. Tests whether agents
understand how ⊥ flows through dependencies and what downstream cells do.
Introduces explicit `given x ⊥? skip` syntax for fail-soft handling.

### T2: Template Instantiation
A spawner that uses § to create cells from a template, with explicit
instantiation syntax showing what gets copied and what gets overridden.
Tests whether the mechanics of § copying are clear.

### T3: Oracle Retry on Spawned Cells
A spawner that creates cells with ⊨? clauses, and a meta-oracle that
monitors retry counts across all spawned cells. Tests the interaction
between spawning and oracle recovery.

### T4: Exhaustion Escalation Chain
A multi-level escalation: oracle fails → retry → exhaust → escalate →
meta-handler catches escalation → produces degraded output. Tests the
full failure lifecycle.

## Evaluation Questions (all variants)
1. Trace the execution including all failure paths.
2. What does the program output when everything succeeds? When the first cell fails?
3. Is the failure handling syntax clear on cold read? Rate 1-10.
4. Does ⊥ propagation make the program more or less readable?
5. What's still ambiguous?
