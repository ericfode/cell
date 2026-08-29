# tutor/v1

`tutor/v1` is the structured Stage 0 boundary between a heritable parent genome and an Autolith-hosted tutor. The tutor may return replayable lessons and one optional candidate artifact. It cannot mutate the running world, execute trials, decide admission, or install a successor.

## Request

```lisp
(tutor-request
  (abi tutor/v1)
  (kind evolve)
  (objective <canonical term>)
  (parent <complete parent world>)
  (context <canonical tutor context>))
```

The complete parent world includes its `genome/v1` source bundle and current state. `request-hash` values are the canonical `term-hash` of this exact request.

## Lessons

```lisp
(tutor-lesson
  (kind instruction)
  (content <canonical term>))
```

Lessons are explicit data. A lesson-only result updates the parent's lesson state and creates no trial or lineage entry.

## Candidate artifact

```lisp
(candidate-artifact
  (abi candidate/v1)
  (genome <genome/v1 source bundle>)
  (state <initial canonical state>)
  (claims
    (claims
      (automatic (...))
      (semantic (...))))
  (lessons (...)))
```

The artifact separates a candidate genome and initial state from the tutor transport. It contains no authority to run itself or approve its own installation.

## Result and failure

```lisp
(tutor-result
  (abi tutor/v1)
  (request-hash "<term-hash>")
  (lessons (<tutor-lesson> ...))
  (candidate <candidate-artifact or ()>))
```

```lisp
(tutor-failure
  (abi tutor/v1)
  (request-hash "<term-hash>")
  (kind host-error)
  (message "safe durable message"))
```

A valid candidate result causes the current parent genome to construct a trial effect. Subzero enforces the trial envelope and returns attested evidence. The current parent then constructs a promotion request and executes its own admission function.

## Hosted recording and standalone fixture

A hosted handler can be wrapped with `make-recording-tutor-handler`. The transcript contains exact requests, statuses, responses, hashes, and resource usage:

```lisp
(tutor-transcript
  (abi tutor/v1)
  (exchanges
    ((tutor-exchange
       (request <tutor-request>)
       (request-hash "<term-hash>")
       (status ok)
       (response <tutor-result>)
       (response-hash "<term-hash>")
       (usage <resource-usage>)))))
```

`make-tutor-fixture-handler` consumes those exchanges in order and requires each standalone request to be term-equal to its hosted request. Existing Subzero event-log replay remains handler-free.

`model/v1` remains the provider-neutral text-completion transport for task answers. Model result text is not interpreted as a hereditary world.
