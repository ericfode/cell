# model/v1

`model/v1` is Cell-zero's frozen provider-neutral text-completion ABI. It is a capability transport. It does not contain an agent loop, tool execution, tutor policy, model selection, or credentials.

A future tutor capability may use Autolith to produce demonstrations, critiques, curricula, and candidate successors. That protocol is separate from `model/v1`.

## Request

```lisp
(model-request
  (abi model/v1)
  (kind complete)
  (prompt
    ((text (value "Return one term: "))
     (term (value (objective "improve")))))
  (limits
    (model-limits
      (max-output-bytes 262144))))
```

`kind` is `complete` in version 1.

Prompt parts are ordered:

- `text` contributes its string verbatim.
- `term` contributes the canonical textual projection produced by `write-term`.

The rendered prompt is therefore deterministic. `max-output-bytes` bounds the UTF-8 result accepted by Cell-zero.

Model identity, endpoint, reasoning effort, sampling parameters, retry policy, and provider authentication are adapter configuration. They are intentionally absent from the request.

## Result

A successful capability call has effect status `ok` and returns:

```lisp
(model-result
  (abi model/v1)
  (request-hash "<term-hash of the exact model-request>")
  (text "provider completion")
  (finish-reason complete)
  (usage
    (model-usage
      (input-tokens 120)
      (output-tokens 45))))
```

`finish-reason` is `complete`, `length`, or `unknown`.

Token counts are nonnegative integers or the symbol `unknown`. Token usage is observational. It does not replace Subzero's effect, event, and evaluator resource accounting.

An unsuccessful capability call has effect status `error` and returns:

```lisp
(model-failure
  (abi model/v1)
  (request-hash "<term-hash of the exact model-request>")
  (kind provider-error)
  (message "provider call failed"))
```

Failure messages must be safe for durable logs. Adapters must not include credentials or raw authorization responses.

## Hashing

All hashes are uppercase canonical `term-hash` strings.

- `request-hash` binds a result or failure to the exact request term.
- Transcript `response-hash` binds the recorded response term.
- No second hash encoding is defined by this ABI.

## Credentials

Credential selection is host-only configuration:

```lisp
(model-credential
  (abi model/v1)
  (ref "autolith/default"))
```

`ref` is a nonsecret opaque selector. Credential values never appear in a model request, model result, model transcript, Genesis genome, or Subzero log. The Autolith adapter resolves the selector through Autolith's existing provider credential manager.

## Transcript and fixture replay

```lisp
(model-transcript
  (abi model/v1)
  (exchanges
    ((model-exchange
       (request <model-request>)
       (request-hash "<term-hash>")
       (status ok)
       (response <model-result>)
       (response-hash "<term-hash>")
       (usage
         (resource-usage
           (effects 1)
           (eval-steps 0)
           (events 1)))))))
```

A fixture adapter consumes exchanges in order. Each live request must be term-equal to the recorded request. The adapter then returns the recorded status, response, and resource usage exactly.

Subzero replay remains stronger: replaying an existing effect log invokes no capability handler at all.

## Genesis authority

Genesis constructs `model-request` terms in hereditary code. For candidate generation, the model returns only text. Genesis invokes the bounded `parse-term` evaluator primitive, extracts the proposed candidate, constructs the trial effect, and leaves promotion to the current parent.

The host adapter may:

- render prompt parts
- call a provider
- normalize text and usage
- return a bound result or failure
- record the canonical exchange

It cannot install a child, construct a capsule from provider-specific objects, fabricate trials, or bypass parent admission.
