# Cell-zero/2

A homoiconic Common Lisp substrate for self-describing, parent-selected evolutionary capsules.

Cell Zero represents code, evaluators, capsules, events, effects, traces, and lineage as canonical content-addressed terms. A capsule carries its own evaluator, transition program, state, capability policy, probe policy, and successor-selection rule. Those artifacts are ordinary terms and can be inspected, hashed, interpreted, proposed, trialed, and inherited by the system itself.

## Boundary

The immutable host is limited to substrate mechanics:

- canonical atom and cell terms
- deterministic SHA-256 identity and storage
- a bounded recursive reduction kernel
- capability transport and resource accounting
- structural capsule loading
- append-only traces and lineage publication

Semantic behavior lives in the capsule. The Cell-zero/2 evaluator is a Cell Zero program term which interprets the same language it is written in. The capsule step program authors model requests, constructs runner trials, compares their returned observations, and selects the complete successor capsule.

The Cell-zero/1 replayable-world API remains available for compatibility.

## Load and test

```lisp
(asdf:load-asd #P"/path/to/cell-zero.asd")
(asdf:load-system "cell-zero")
(asdf:test-system "cell-zero")
```

The suite checks self-interpretation, recursive term programs, capsule closure, structural rejection, endogenous candidate trials, hereditary selection policy, lineage, replay, storage, and resource bounds.

## Self-interpretation

```lisp
(cell-zero:homoiconic-evaluator-self-check)
;; => T
```

A task request is produced entirely by the evaluator and step terms carried inside the capsule:

```lisp
(let ((capsule (cell-zero:make-homoiconic-genesis-capsule)))
  (cell-zero:homoiconic-task-prompt capsule "Implement the requested task."))
```

## Evolution

```lisp
(let* ((parent (cell-zero:make-homoiconic-genesis-capsule))
       (candidate
         (cell-zero:make-homoiconic-genesis-capsule
          :task-context "Inspect, implement, verify, and repair."))
       (cell (cell-zero:make-homoiconic-cell
              (cell-zero:make-term-store) parent)))
  (cell-zero:register-homoiconic-handler
   cell "model"
   (cell-zero:make-scripted-homoiconic-model-handler candidate))
  (cell-zero:register-homoiconic-handler
   cell "runner"
   (cell-zero:make-scripted-homoiconic-runner-handler
    (lambda (capsule event)
      (declare (ignore event))
      (values t (if (cell-zero:term-equal capsule candidate) 1 0)
              (cell-zero:empty-term)))))
  (cell-zero:submit-homoiconic-event
   cell (cell-zero:sexp->term
         '(event (kind evolve) (objective "improve"))))
  (cell-zero:run-homoiconic-until-idle cell)
  (cell-zero:homoiconic-cell-current-root cell))
```

The model and runner are capability transports. Candidate interpretation, paired trial construction, score comparison, retention, and promotion are capsule behavior.

## Harbor and Terminal-Bench

`harbor_adapter.cell_zero:CellZeroCodex` subclasses Harbor's Codex adapter and obtains its task prompt from a live Cell-zero/2 capsule:

```sh
PYTHONPATH=. harbor run \
  --path /path/to/terminal-bench-task \
  --agent harbor_adapter.cell_zero:CellZeroCodex \
  --model gpt-5.6-sol \
  --agent-kwarg "task_context=Inspect the interface, implement, and run tests." \
  --agent-env CODEX_FORCE_AUTH_JSON=true
```

`scripts/select-harbor-successor.lisp` feeds paired Harbor rewards back through the capsule's runner capability and writes the selected complete capsule plus a content-addressed evolution record.

The reproducible Terminal-Bench run metadata and strict tie-retention result are recorded in [`evidence/`](evidence/README.md). Harbor decimal rewards are normalized to exact integer terms before the hereditary comparison.
