# Cell Zero capability audit

Date: 2026-08-28

## Executive result

Cell Zero has a credible replayable substrate, a content-bound evolution protocol stack, durable Subzero execution, a useful derived event database, and one completed ecological gate. Its strongest property is that authoritative decisions and nondeterministic results are represented as canonical content-addressed terms and checked during replay.

The next investment should move from replay correctness inside one process to durable correctness across crashes and retries. The recommended milestone is **C1 Durable Effects and Projection Integrity**.

## Verification snapshot

- Main suite: 44 tests and 227 assertions passed.
- Laboratory suite: protocol and C0 smoke checks passed.
- C0 evidence records three independently seeded 10,000-history reports with all hard counters at zero.
- The temporal event database merge is published at `feature/event-db-indexing-projections` on `ericfode/cell`.
- Remote `main` is an unrelated Go history, so it was not overwritten or merged.

## Capability map

| Area | Maturity | Present capability | Main investment gap |
|---|---:|---|---|
| Canonical terms and store | 4/5 | Defensive immutable terms, canonical UTF-8 and integer encodings, SHA-256 identities, verified content-addressed storage, atomic object writes | Byte-aware limits, streaming paths, bounded graph traversal, cache lifecycle, stronger durability |
| Bounded evaluator | 4/5 | Closed first-order language, static validation, step/depth/output-node limits, canonical primitive boundary | Large atoms and expensive primitives are under-metered; parsing allocates before term bounds apply |
| `genome/v1` | 3/5 | Source hashes, safe paths, declared entry points, fresh materialization, disposable compiler process | Hostile-code sandboxing, wall-clock/memory/output bounds, measured usage, child-side source rehashing and invocation binding |
| `model/v1` | 4/5 | Exact request hashes, deterministic prompt rendering, bounded result bytes, transcript recording and fixtures | Prompt framing ambiguity, request-size ceilings, runtime budget and provenance binding |
| `tutor/v1` | 3/5 | Explicit lessons, candidate artifacts, request/response hashes, transcript fixtures | Typed selection context, claim semantics, candidate load evidence, size ceilings |
| `selection/v1` | 4/5 contract, 3/5 enforcement | Content-bound plans and fitness, attested baseline/candidate flow in Subzero, strict improvement comparison | A standalone evidence verifier and non-bypassable minimum promotion policy are not yet first-class protocol artifacts |
| Subzero runtime | 4/5 replay, 3/5 operations | Ordered effects, durable pending work, capability intersection, trials, promotion evidence, lineage, raw-root replay | Transactional live transitions, crash-safe effect dispatch, idempotency receipts, measured resource enforcement |
| Event database | 3/5 | Immutable EAV history, as-of views, joins, durable refs, subscriptions, replay-validated imports, nested projections | Projector versioning, conflict detection, durable watermarks, resumable reconciliation, indexes and incremental queries |
| Ecological laboratory | 3/5 prototype | Hidden distributions, separate organism/champion refs, hard zero counters, three-lineage stage rule, C0 evidence | Evidence fields are partly asserted rather than derived; no persistent challenge-scoped evidence compiler or fault matrix |
| Cell-zero/2 and Harbor | 2/5 experimental | Homoiconic evaluator and step terms, optional Harbor prompt adapter, paired-score selector, recorded artifacts | Host-boundary validation, result authentication, budgets, automated integration tests, successful promotion evidence, isolation from primary API |
| CI and conformance | 2/5 | One ASDF test entry point and deterministic local fixtures | No checked-in CI workflow, implementation matrix, adapter tests, script tests, fuzzing, or crash-injection lane |

## Strong capabilities worth preserving

### Canonical authority

The term store reconstructs and checks canonical node bytes and hashes at ingress and read time. Public accessors return defensive copies. This gives every protocol a stable identity layer and makes raw-root replay practical.

### Replayable nondeterminism

Subzero records effect intent before execution and replays recorded results without invoking capability handlers. Trial and promotion results receive stronger recomputation than ordinary external effects. Durable reopen reconstructs current state and lineage from raw roots.

### Content-bound evolution

`genome/v1`, `model/v1`, `tutor/v1`, and `selection/v1` bind source, prompts, responses, objectives, probes, metrics, candidates, and fitness to canonical roots. This is already enough to audit many classes of substitution or plan drift.

### Derived observability

The event database preserves exact payload terms and useful query projections without becoming replay authority. It survives observer failure, supports immutable views and subscriptions, validates imported logs by replay, and follows nested trial scopes.

### Ecological gating

C0 established the basic external laboratory shape: hidden generators, zero-tolerance correctness counters, replay without handlers, separate current/champion refs, and three independent lineages before stage advancement.

## Highest-leverage investments

### P0. Durable effect broker and crash semantics

Use the sealed effect root as a stable idempotency key. Persist dispatch claims, completion receipts, and explicit uncertain outcomes. Define behavior for crashes before dispatch, after dispatch, before result commit, during commit, and after commit. Ordinary handlers need a reconciliation contract rather than blind retry.

First slice:

1. Add a canonical effect-execution receipt.
2. Add deterministic crash injection around `reserve-next-effect` and `complete-pending-effect`.
3. Reopen and reconcile pending work without duplicating a logical effect.
4. Expose the lifecycle in the event database.

### P0. Verifying evidence compiler

Laboratory attestations should be derived from raw reports, roots, logs, budgets, and challenge descriptors. They should not accept correctness booleans directly from callers.

First slice:

1. Define canonical raw-report and aggregate-manifest terms.
2. Bind reports to challenge, generator, candidate, lineage, seed, runtime, and source roots.
3. Recompute counters and budget status during ingestion.
4. Publish the aggregate root before advancing `lab/champion`.

### P0. Hostile-code resource isolation

The disposable source-genome process is an isolation boundary, but it is not yet a sandbox. Add process deadlines, memory and output ceilings, environment scrubbing, filesystem/network restrictions, child-side source rehashing, and measured usage.

### P1. Transactional Subzero transitions

Stage authoritative log, state, queue, counters, lineage, and manifest updates before publication. On compare-and-swap failure, either roll back or fence the stale instance. Deliver projection work after authority commits.

### P1. Versioned projection and reconciliation

Bind projection sources to a projector version and output digest. Add durable watermarks, retry, lag/error reporting, preflight validation of nested logs, and deterministic rebuild into a fresh named ref. Reusing an idempotency source with different facts should signal a conflict.

### P1. Persistent indexes and incremental subscriptions

The current event database scans visible datoms for every clause and reruns complete subscriptions after each transaction. Add current-state and EAV indexes, persistent source lookup, checkpoints, and delta evaluation before increasing production volume.

### P1. Byte-aware resource accounting

Add maximum input bytes, atom payload bytes, integer bit length, serialized output bytes, and storage-object bytes. Charge expensive primitives before allocation. Replace recursive store and snapshot traversals with bounded iterative traversal.

### P1. Conformance and CI

Add a checked-in CI lane covering supported SBCL versions, canonical golden vectors, malformed store data, source-genome process limits, replay and crash points, event database concurrency, laboratory evidence verification, scripts, and the Python Harbor adapter.

### P2. Experimental surface isolation

Move Cell-zero/2 and Harbor support into a separate ASDF system/package or explicit optional feature. Publish a formal ABI if the experiment remains active. Its current evidence demonstrates identity tracking and tie retention, not successful evolutionary promotion.

## Recommended next milestone

### C1 Durable Effects and Projection Integrity

C1 should extend C0 with a laboratory-side effect ledger and deterministic crash schedules. It should measure both authoritative Subzero recovery and exact reconstruction of the derived event database.

Required hidden cases:

- crash before effect dispatch;
- crash after dispatch but before result recording;
- crash during result and manifest commit;
- duplicate, late, and reordered results;
- timeout and explicit uncertain outcome;
- stale durable writer;
- observer projection failure and later reconciliation;
- live versus rebuilt versus reopened event database equivalence;
- nested trial import failure and resume;
- inherited C0 malformed-input and replay cases.

Hard counters:

- replay state or output mismatch;
- capability handler call during replay;
- dispatch without committed intent;
- duplicate logical effect application;
- result without reservation;
- lost committed intent or result;
- unauthorized capability dispatch;
- projection mismatch or unreconciled lag;
- invalid promotion;
- laboratory error.

Completion gate:

1. Three fresh lineage roots and three distinct hidden-seed roots.
2. At least 10,000 histories per lineage.
3. Every hard counter is zero.
4. C0 inherited regressions pass.
5. Live, rebuilt, and reopened projections agree for current, history, and as-of queries.
6. Resource budgets pass from measured data.
7. The verifying evidence compiler accepts the reports and publishes one aggregate manifest root.

## Suggested implementation order

1. Specify C1 terms and effect-ledger counters.
2. Implement crash injection and execution receipts.
3. Implement the evidence compiler.
4. Add projector versions, watermarks, and rebuild comparison.
5. Run small deterministic matrices in tests.
6. Run three hidden 10,000-history lineages and publish evidence.

## Provenance

The audit used direct source and test inspection, successful main and laboratory test runs, and focused recursive reviews. Curated review transcripts are stored in `docs/transcripts/2026-08-28-capability-exploration.md`.
