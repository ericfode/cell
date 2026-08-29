# Cell Zero

A replayable, parent-gated evolutionary substrate for ordinary Common Lisp source genomes.

Stage 0 uses [`genome/v1`](docs/genome-v1.md): a content-bound source bundle with compiled `react` and `admit` entry points. Subzero owns canonical storage, effects, resource envelopes, evidence, replay, and lineage publication. The current genome owns requests, state transitions, trials, and admission policy.

The homoiconic Cell-zero/2 capsule system remains available as an optional experimental lineage.

## Stage 0 boundaries

- [`model/v1`](docs/model-v1.md) transports deterministic text-completion requests and results. Model text is used for task answers, not interpreted as a hereditary world.
- [`tutor/v1`](docs/tutor-v1.md) transports explicit lessons and optional `candidate/v1` artifacts.
- [`genome/v1`](docs/genome-v1.md) carries ordinary Common Lisp source files, source hashes, entry points, and canonical genome data.
- The [temporal event database](docs/event-database.md) projects hash-chained Subzero activity into immutable EAV datoms with joins, as-of history, and live tails.
- Subzero runs source genomes through a disposable compiler process and never loads candidate packages into the parent Lisp image.
- Candidate trials and admission are authored by the current parent and enforced by Subzero.

## Load and test

```lisp
(asdf:load-asd #P"/path/to/cell-zero.asd")
(asdf:load-system "cell-zero")
(asdf:test-system "cell-zero")
```

The suite covers source-manifest validation, isolated compilation, model and tutor fixture replay, explicit lessons and artifacts, parent-owned trials and admission, accepted and rejected lineage replay, durable recovery, the legacy evaluator, and the optional homoiconic system.

## Task execution

```lisp
(let* ((store (cell-zero:make-term-store))
       (world (cell-zero:make-genesis-world))
       (cell (cell-zero:make-subzero store world)))
  (cell-zero:register-capability-handler
   cell "model"
   (cell-zero:make-scripted-model-handler :answer "done"))
  (cell-zero:submit-event
   cell (cell-zero:sexp->term
         '(event (kind task) (task "Implement the requested change."))))
  (cell-zero:run-until-idle cell)
  (cell-zero:subzero-outputs cell))
```

`make-genesis-world` returns a `genome/v1` world. Its controller is the ordinary source file [`genomes/stage0.lisp`](genomes/stage0.lisp), embedded into the canonical source bundle with a SHA-256 manifest.

## Evolution

```lisp
(let* ((store (cell-zero:make-term-store))
       (parent (cell-zero:make-genesis-world))
       (candidate (cell-zero:make-compatible-candidate))
       (cell (cell-zero:make-subzero store parent)))
  (cell-zero:register-capability-handler
   cell "model" (cell-zero:make-scripted-model-handler))
  (cell-zero:register-capability-handler
   cell "tutor" (cell-zero:make-scripted-tutor-handler candidate))
  (cell-zero:submit-event
   cell (cell-zero:sexp->term
         '(event (kind evolve) (objective "improve without regressions"))))
  (cell-zero:run-until-idle cell)
  (cell-zero:subzero-lineage-root cell))
```

The tutor returns a structured candidate artifact. The parent constructs the trial request, Subzero compiles and probes the candidate under intersected capabilities, replay verifies the trace, and the parent admission function decides `accept`, `reject`, or `defer`.

`make-recording-tutor-handler` records a hosted run. `make-tutor-fixture-handler` replays the exact requests and artifacts standalone. Raw event-log replay invokes no capability handlers.

## Event inspection

Attach `:event-database` to `make-subzero` to project each authoritative log entry automatically. Model projections include the `model/v1` request hash, exact rendered prompt, status, response, resource usage, and separately marked provider telemetry. Nested trial runs are linked to their parent scope and share the same queryable history. See [`docs/event-database.md`](docs/event-database.md).

## Optional homoiconic lineage

```lisp
(cell-zero:homoiconic-evaluator-self-check)
;; => T
```

`make-homoiconic-genesis-capsule`, `make-homoiconic-cell`, and the related runner APIs preserve the Cell-zero/2 self-interpreting experiment. Stage 0 does not depend on that representation.

## Harbor and Terminal-Bench

`harbor_adapter.cell_zero:CellZeroCodex` remains the Harbor adapter for the homoiconic experiment. `scripts/select-harbor-successor.lisp` feeds paired rewards through its runner capability and writes the selected capsule plus a content-addressed evolution record. Reproducible run metadata is under [`evidence/`](evidence/README.md).

## Ecological challenge laboratory

`cell-zero-lab.asd` is the external laboratory system. It keeps hidden generators outside the organism, applies lexicographic promotion gates, maintains separate durable `organism/current` and `lab/champion` refs, and requires three fresh lineages before stage advancement.

The prior C0 Event Eater attestations are under [`evidence/ecology/`](evidence/ecology/README.md).
