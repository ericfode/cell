# Cell-zero/1

A Common Lisp substrate for parent-gated, replayable evolutionary worlds.

Cell-zero represents worlds, programs, effects, evidence, logs, and lineage as canonical content-addressed terms. A parent genome reacts to events, requests effects, trials candidate worlds in isolated subzeros, authenticates the resulting traces, and alone decides whether a candidate is promoted.

## Properties

- Canonical atom/cell terms with deterministic SHA-256 roots
- Filesystem-backed content-addressed storage with verified atomic publication
- A bounded, first-order, pure evaluator
- Effects sealed to their exact world and genome context
- Capability grants and request-bound result events
- Candidate trials with independent state, logs, outputs, and resource limits
- Trial evidence bound to candidate, parent genome, probe suite, and replayed trace
- Parent-controlled admission and atomic world-root promotion
- Append-only hash-chained event logs and lineage records
- Raw-root replay without invoking capability handlers
- Durable named manifests that recover queued and pending effects

External effects are at-least-once across a crash after handler invocation and before result publication. Handlers can deduplicate using the sealed effect's `term-hash`.

## Load and test

```lisp
(asdf:load-asd #P"/path/to/cell-zero.asd")
(asdf:load-system "cell-zero")
(asdf:test-system "cell-zero")
```

## Boot demonstration

```lisp
(let ((demo (cell-zero:run-boot-demo)))
  (list :initial (cell-zero:boot-demo-initial-root demo)
        :accepted (cell-zero:boot-demo-accepted-final-root demo)
        :rejected (cell-zero:boot-demo-rejected-final-root demo)))
```

`run-boot-demo` produces one accepted compatible child and one rejected self-accepting but inert child. Both branches are replayed from their initial world root and event-log root, with zero handler calls during replay.

Pass `:directory` to retain the object store:

```lisp
(cell-zero:run-boot-demo :directory #P"./demo-store/")
```

## Durable worlds

```lisp
(let* ((store (cell-zero:make-term-store :directory #P"./world-store/"))
       (world (cell-zero:make-genesis-world))
       (subzero (cell-zero:make-subzero store world :name "main")))
  (cell-zero:submit-event subzero
    (cell-zero:sexp->term '(event (kind evolve) (objective "improve"))))
  ;; Register handlers, then drain recorded effects.
  (cell-zero:run-until-idle subzero))

(let* ((store (cell-zero:make-term-store :directory #P"./world-store/"))
       (subzero (cell-zero:reopen-subzero store "main")))
  ;; Re-register process-local handlers before draining recovered work.
  subzero)
```

## Evaluator language

Programs use `(program (parameters (...)) (body ...))`. Expressions are limited to `quote`, `var`, `if`, `let*`, and calls to a fixed primitive set. Evaluation meters validation, expression steps, primitive argument traversal, nesting depth, and intermediate/output size.
