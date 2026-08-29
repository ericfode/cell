# selection/v1

`selection/v1` is the comparative Stage 0 protocol for objective-specific evolution. The parent commits the objective, regression probes, objective probes, and metric before tutor invocation. Subzero then evaluates the parent baseline and every proposed candidate against that identical plan.

## Trial probes

Each deterministic probe binds one input event to its expected output slice:

```lisp
(probe
  (event <canonical event>)
  (expected-outputs (<canonical output> ...)))
```

Regression and objective suites must both be nonempty. A regression suite passes only when every probe matches. The current metric counts matching objective probes.

## Selection plan

```lisp
(selection-plan
  (abi selection/v1)
  (objective <canonical term>)
  (objective-hash "<term-hash>")
  (regression-probes (<probe> ...))
  (regression-probes-hash "<term-hash>")
  (objective-probes (<probe> ...))
  (objective-probes-hash "<term-hash>")
  (metric passed-objective-probes)
  (metric-hash "<term-hash>"))
```

Every hash binds the exact canonical field value. The hash of the complete plan is its plan root.

Stage 0 constructs this plan when it receives the `evolve` event. It runs the current parent world as the baseline before contacting the tutor, then includes the complete plan in the tutor request context:

```lisp
(selection-context
  (tutor-context <parent-defined context>)
  (selection-plan <selection-plan>))
```

The tutor may use the committed plan when producing lessons or a candidate, but cannot change it.

## Trial and fitness

Both baseline and candidate trials use:

```lisp
(trial
  (candidate <complete world or root>)
  (plan <selection-plan>))
```

Subzero compiles the candidate, runs regression probes followed by objective probes, and records an attested trace. Fitness is canonical and bound to the plan and metric:

```lisp
(fitness
  (abi selection/v1)
  (plan "<selection-plan hash>")
  (metric passed-objective-probes)
  (metric-hash "<term-hash>")
  (score <passed objective probes>)
  (total <objective probe count>))
```

A trial trace also binds the execution-time parent world and genome, candidate root, plan hash, objective hash, both probe-suite hashes, metric hash, outputs, event log, resource usage, safety checks, and violations.

## Promotion request

```lisp
(promote
  (candidate <complete world or root>)
  (plan <selection-plan>)
  (baseline "<attested parent trace root>")
  (baseline-candidate "<baseline parent world root>")
  (candidate-trace "<attested candidate trace root>")
  (claims <claims>))
```

Subzero accepts trace roots only from its attestation registry. The baseline world must contain the same genome as the promotion-time parent, and both traces must bind the exact plan and metric components. A fabricated root, changed plan, changed metric, or mismatched candidate fails evidence construction.

## Evidence and comparison

Promotion evidence binds the parent and candidate roots, parent genome, plan and component hashes, both trace roots, claims, aggregate resources, checks, and a comparison:

```lisp
(selection-comparison
  (abi selection/v1)
  (plan "<selection-plan hash>")
  (metric-hash "<term-hash>")
  (baseline-trace "<trace root>")
  (baseline-fitness "<fitness term-hash>")
  (candidate-trace "<trace root>")
  (candidate-fitness "<fitness term-hash>")
  (improved true-or-false))
```

`objective-improvement` passes only when both fitness values are valid under the same plan and metric, their totals match, and the candidate score is strictly greater than the baseline score. Equal fitness is not an improvement.

The parent admission function receives this evidence after Subzero enforces ABI, load, capability, and evidence-completeness gates. The Stage 0 parent additionally requires liveness, full regression success, replay compatibility, resource policy, strict objective improvement, checkable automatic claims, and complete evidence. Semantic claims produce `defer`.

## Replay

Recorded trial replay invokes no capability handlers. Replay verifies the original effect context and capability grant, reconstructs the exact output slice produced by each input probe, recomputes regression success and objective score, and requires the reconstructed checks and fitness to equal the attested trace. An incomplete trial must report zero objective fitness and cannot claim successful liveness, regression, or replay checks.