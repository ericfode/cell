;;;; src/package.lisp

(defpackage #:cell-zero
  (:use #:cl)
  (:shadow #:atom #:cell)
  (:export
   ;; Conditions
   #:cell-zero-error
   #:malformed-term
   #:store-error
   #:evaluation-error
   #:evaluation-budget-exhausted
     #:exhausted-budget-kind
   #:protocol-error
   #:resource-budget-exhausted
   #:resource-budget-kind
   ;; Hashes and octets
   #:sha256-octets
   #:sha256-hex
   #:hex-octets
   ;; Terms
   #:term
   #:atom
   #:cell
   #:term-p
   #:atom-p
   #:cell-p
   #:atom-kind
   #:atom-value
   #:cell-left
   #:cell-right
   #:term-hash
   #:make-atom
   #:make-symbol-atom
   #:make-string-atom
   #:make-integer-atom
   #:make-bytes-atom
   #:make-cell
   #:term-list
   #:term-list-elements
   #:sexp->term
   #:term->sexp
   #:read-term
   #:write-term
   #:term-equal
   #:term-size
   #:term-tag
   #:term-field
   #:term-fields
   #:put-term-field
   #:append-term-field
   #:term-truth-p
   #:true-term
   #:false-term
   #:empty-term
   ;; Storage
   #:term-store
   #:make-term-store
   #:store-directory
   #:store-put
   #:store-get
   #:store-exists-p
   ;; Evaluator
   #:evaluation-limits
   #:make-evaluation-limits
   #:evaluation-usage
   #:usage-steps
   #:usage-max-depth
   #:usage-output-size
   #:validate-program
   #:evaluate-program
   ;; Subzero
   #:subzero
   #:make-subzero
   #:subzero-store
   #:subzero-initial-root
   #:subzero-current-root
   #:subzero-current-world
   #:subzero-outputs
   #:subzero-log-root
   #:subzero-lineage-root
   #:subzero-snapshot-root
   #:subzero-trace-roots
   #:subzero-handler-calls
   #:subzero-ref-name
   #:subzero-manifest-root
   #:subzero-manifest-generation
   #:subzero-max-effects
   #:subzero-max-events
   #:subzero-max-eval-steps
   #:register-capability-handler
   #:submit-event
   #:run-until-idle
   #:replay-from-roots
   #:persist-subzero
   #:reopen-subzero
   #:world-valid-p
   #:world-genome
   #:world-state
   #:genome-react
   #:genome-admit
   #:genome-data
   #:genome-hash
   ;; Genesis and demonstration
   #:make-genesis-world
   #:make-compatible-candidate
   #:make-broken-self-accepting-candidate
   #:make-scripted-model-handler
   #:run-boot-demo
   #:boot-demo-result
   #:boot-demo-store
   #:boot-demo-initial-root
   #:boot-demo-accepted-log-root
   #:boot-demo-accepted-final-root
   #:boot-demo-accepted-lineage-root
   #:boot-demo-rejected-log-root
   #:boot-demo-rejected-final-root
   #:boot-demo-rejected-lineage-root))

(defpackage #:cell-zero.tests
  (:use #:cl #:cell-zero)
  (:shadowing-import-from #:cell-zero #:atom #:cell)
  (:export #:run-tests))
