;;;; src/genesis.lisp

(in-package #:cell-zero)

;;; These helpers construct ordinary program terms. They are not evaluator
;;; extensions and no host function is embedded in a genome.

(defun %q (datum)
  (list 'quote datum))

(defun %v (name)
  (list 'var name))

(defun %call (name &rest arguments)
  (list* 'call name arguments))

(defun %if (test consequent alternate)
  (list 'if test consequent alternate))

(defun %let* (bindings body)
  (list 'let* bindings body))

(defun %field (term name)
  (%call 'field term (%q name)))

(defun %put-field (term name value)
  (%call 'put-field term (%q name) value))

(defun %append-field (term name value)
  (%call 'append-field term (%q name) value))

(defun %list (&rest values)
  (apply #'%call 'list values))

(defun %tagged (tag &rest fields)
  (apply #'%list (%q tag)
         (mapcar (lambda (field)
                   (%list (%q (first field)) (second field)))
                 fields)))

(defun %reaction (state outputs effects)
  (%tagged 'reaction
           (list 'state state)
           (list 'outputs outputs)
           (list 'effects effects)))

(defun %effect (id capability request budget)
  (%tagged 'effect
           (list 'id id)
           (list 'capability (%q capability))
           (list 'request request)
           (list 'budget budget)))

(defun %pending (id kind &rest fields)
  (apply #'%tagged 'pending
         (append (list (list 'id id)
                       (list 'kind (%q kind)))
                 fields)))

(defun %model-text-part (value)
  (%tagged 'text (list 'value value)))

(defun %model-term-part (value)
  (%tagged 'term (list 'value value)))

(defun %model-request (parts)
  (%tagged 'model-request
           (list 'abi (%q 'model/v1))
           (list 'kind (%q 'complete))
           (list 'prompt parts)
           (list 'limits
                 (%tagged 'model-limits
                          (list 'max-output-bytes
                                (%field (%v 'data) 'model-max-output-bytes))))))

(defun %model-pending (id kind request &rest fields)
  (apply #'%pending id kind
         (append (list (list 'request-hash (%call 'hash request))) fields)))

(defun %model-result-matches-p (response pending event-status)
  (%if
   (%call 'equal event-status (%q 'ok))
   (%if
    (%call 'equal (%call 'tag response) (%q 'model-result))
    (%if
     (%call 'equal (%field response 'abi) (%q 'model/v1))
     (%call 'equal (%field response 'request-hash)
            (%field pending 'request-hash))
     (%q 'false))
    (%q 'false))
   (%q 'false)))

(defun %state-with-recorded-event (state event)
  (%append-field state 'history event))

(defun %state-without-pending (state effect-id)
  (%put-field
   (%state-with-recorded-event state (%v 'event))
   'pending
   (%call 'remove-by-field (%field state 'pending) (%q 'id) effect-id)))

(defun make-task-reaction-expression ()
  (%let*
   `((id ,(%field (%v 'state) 'next-effect-id))
     (recorded-state ,(%state-with-recorded-event (%v 'state) (%v 'event)))
     (request
      ,(%model-request
        (%list
         (%model-text-part (%field (%v 'data) 'task-model-prompt))
         (%model-term-part (%field (%v 'event) 'task)))))
     (pending ,(%model-pending (%v 'id) 'task (%v 'request)))
     (next-state
      ,(%put-field
        (%append-field (%v 'recorded-state) 'pending (%v 'pending))
        'next-effect-id
        (%call 'integer+ (%v 'id) (%q 1))))
     (effect
      ,(%effect (%v 'id) 'model (%v 'request)
                (%field (%v 'data) 'model-budget))))
   (%reaction (%v 'next-state) (%q nil) (%list (%v 'effect)))))

(defun make-evolve-reaction-expression ()
  (%let*
   `((id ,(%field (%v 'state) 'next-effect-id))
     (recorded-state ,(%state-with-recorded-event (%v 'state) (%v 'event)))
     (request
      ,(%model-request
        (%list
         (%model-text-part (%field (%v 'data) 'evolution-model-prompt))
         (%model-text-part (%q (format nil "Objective:~%")))
         (%model-term-part (%field (%v 'event) 'objective))
         (%model-text-part (%q (format nil "~%Parent world:~%")))
         (%model-term-part (%v 'world))
         (%model-text-part (%q (format nil "~%Admission requirements:~%")))
         (%model-term-part
          (%field (%v 'data) 'admission-requirements)))))
     (pending ,(%model-pending (%v 'id) 'evolve (%v 'request)
                               (list 'objective (%field (%v 'event) 'objective))))
     (next-state
      ,(%put-field
        (%append-field (%v 'recorded-state) 'pending (%v 'pending))
        'next-effect-id
        (%call 'integer+ (%v 'id) (%q 1))))
     (effect
      ,(%effect (%v 'id) 'model (%v 'request)
                (%field (%v 'data) 'model-budget))))
   (%reaction (%v 'next-state) (%q nil) (%list (%v 'effect)))))

(defun make-task-result-expression ()
  (%let*
   `((effect-id ,(%field (%v 'event) 'effect-id))
     (pending ,(%call 'find-by-field (%field (%v 'state) 'pending)
                      (%q 'id) (%v 'effect-id)))
     (response ,(%field (%v 'event) 'response))
     (next-state ,(%state-without-pending (%v 'state) (%v 'effect-id))))
   (%if
    (%model-result-matches-p
     (%v 'response) (%v 'pending) (%field (%v 'event) 'status))
    (%reaction
     (%v 'next-state)
     (%list (%tagged 'answer
                     (list 'text (%field (%v 'response) 'text))))
     (%q nil))
    (%reaction
     (%v 'next-state)
     (%list (%tagged 'model-failure
                     (list 'reason (%q 'invalid-model-result))))
     (%q nil)))))

(defun make-malformed-candidate-expression ()
  (%let*
   `((base-state ,(%state-without-pending (%v 'state) (%v 'effect-id)))
     (rejection
      ,(%tagged 'branch
                (list 'status (%q 'rejected))
                (list 'reason (%q 'malformed-candidate))))
     (next-state ,(%append-field (%v 'base-state) 'candidate-branches
                                 (%v 'rejection))))
   (%reaction (%v 'next-state) (%list (%v 'rejection)) (%q nil))))

(defun make-candidate-result-expression ()
  (%let*
   `((response ,(%field (%v 'event) 'response))
     (effect-id ,(%field (%v 'event) 'effect-id))
     (pending ,(%call 'find-by-field (%field (%v 'state) 'pending)
                      (%q 'id) (%v 'effect-id))))
   (%if
    (%model-result-matches-p
     (%v 'response) (%v 'pending) (%field (%v 'event) 'status))
    (%let*
     `((parsed ,(%call 'parse-term (%field (%v 'response) 'text))))
     (%if
      (%call 'equal (%field (%v 'parsed) 'status) (%q 'ok))
      (%let*
       `((proposal ,(%field (%v 'parsed) 'value))
         (candidate ,(%field (%v 'proposal) 'candidate))
         (claims ,(%field (%v 'proposal) 'claims)))
       (%if
        (%call 'equal (%call 'tag (%v 'proposal)) (%q 'proposal))
        (%if
         (%call 'present? (%v 'candidate))
         (%let*
          `((base-state ,(%state-without-pending (%v 'state) (%v 'effect-id)))
            (id ,(%field (%v 'state) 'next-effect-id))
            (branch
             ,(%tagged 'branch
                       (list 'candidate (%v 'candidate))
                       (list 'claims (%v 'claims))
                       (list 'status (%q 'proposed))))
            (trial-pending
             ,(%pending (%v 'id) 'trial
                        (list 'candidate (%v 'candidate))
                        (list 'claims (%v 'claims))))
            (next-state
             ,(%put-field
               (%append-field
                (%append-field (%v 'base-state) 'candidate-branches (%v 'branch))
                'pending (%v 'trial-pending))
               'next-effect-id
               (%call 'integer+ (%v 'id) (%q 1))))
            (trial-request
             ,(%tagged 'trial
                       (list 'candidate (%v 'candidate))
                       (list 'events (%field (%v 'data) 'probes))))
            (effect
             ,(%effect (%v 'id) 'trial (%v 'trial-request)
                       (%field (%v 'data) 'trial-budget))))
          (%reaction (%v 'next-state) (%q nil) (%list (%v 'effect))))
         (make-malformed-candidate-expression))
        (make-malformed-candidate-expression)))
      (make-malformed-candidate-expression)))
    (make-malformed-candidate-expression))))

(defun make-trial-result-expression ()
  (%let*
   `((effect-id ,(%field (%v 'event) 'effect-id))
     (response ,(%field (%v 'event) 'response))
     (trace ,(%field (%v 'response) 'trace))
     (pending ,(%call 'find-by-field (%field (%v 'state) 'pending)
                      (%q 'id) (%v 'effect-id)))
     (candidate ,(%field (%v 'pending) 'candidate))
     (claims ,(%field (%v 'pending) 'claims)))
   (%if
    (%call 'present? (%v 'trace))
    (%let*
     `((base-state ,(%state-without-pending (%v 'state) (%v 'effect-id)))
       (id ,(%field (%v 'state) 'next-effect-id))
       (promotion-pending
        ,(%pending (%v 'id) 'promote
                   (list 'candidate (%v 'candidate))
                   (list 'claims (%v 'claims))))
       (next-state
        ,(%put-field
          (%append-field (%v 'base-state) 'pending (%v 'promotion-pending))
          'next-effect-id
          (%call 'integer+ (%v 'id) (%q 1))))
       (request
        ,(%tagged 'promote
                  (list 'candidate (%v 'candidate))
                  (list 'trials (%list (%v 'trace)))
                  (list 'claims (%v 'claims))))
       (effect
        ,(%effect (%v 'id) 'promote (%v 'request)
                  (%field (%v 'data) 'admission-budget))))
     (%reaction (%v 'next-state) (%q nil) (%list (%v 'effect))))
    (%let*
     `((next-state ,(%state-without-pending (%v 'state) (%v 'effect-id)))
       (failure ,(%tagged 'trial-failed
                          (list 'response (%v 'response)))))
     (%reaction (%v 'next-state) (%list (%v 'failure)) (%q nil))))))

(defun make-effect-result-expression ()
  (%let*
   `((effect-id ,(%field (%v 'event) 'effect-id))
     (pending ,(%call 'find-by-field (%field (%v 'state) 'pending)
                      (%q 'id) (%v 'effect-id)))
     (pending-kind ,(%field (%v 'pending) 'kind)))
   (%if
    (%call 'equal (%v 'pending-kind) (%q 'task))
    (make-task-result-expression)
    (%if
     (%call 'equal (%v 'pending-kind) (%q 'evolve))
     (make-candidate-result-expression)
     (%if
      (%call 'equal (%v 'pending-kind) (%q 'trial))
      (make-trial-result-expression)
      (%reaction (%state-with-recorded-event (%v 'state) (%v 'event))
                 (%q nil) (%q nil)))))))

(defun make-promotion-result-expression ()
  (%let*
   `((effect-id ,(%field (%v 'event) 'effect-id))
     (recorded-state ,(%state-with-recorded-event (%v 'state) (%v 'event)))
     (next-state
      ,(%put-field
        (%v 'recorded-state)
        'pending
        (%call 'remove-by-field (%field (%v 'state) 'pending)
               (%q 'id) (%v 'effect-id))))
     (output
      ,(%tagged 'promotion-result
                (list 'decision (%field (%v 'event) 'decision))
                (list 'candidate (%field (%v 'event) 'candidate))
                (list 'reason (%field (%v 'event) 'reason)))))
   (%reaction (%v 'next-state) (%list (%v 'output)) (%q nil))))

(defun make-genesis-react-program ()
  (let ((body
          (%let*
           `((kind ,(%field (%v 'event) 'kind)))
           (%if
            (%call 'equal (%v 'kind) (%q 'task))
            (make-task-reaction-expression)
            (%if
             (%call 'equal (%v 'kind) (%q 'evolve))
             (make-evolve-reaction-expression)
             (%if
              (%call 'equal (%v 'kind) (%q 'effect-result))
              (make-effect-result-expression)
              (%if
               (%call 'equal (%v 'kind) (%q 'promotion-result))
               (make-promotion-result-expression)
               (%reaction (%state-with-recorded-event (%v 'state) (%v 'event))
                          (%q nil) (%q nil)))))))))
    (sexp->term
     `(program
       (parameters (state event data world))
       (body ,body)))))

(defun make-genesis-admit-program ()
  (let ((body
          (%let*
           `((checks ,(%field (%v 'evidence) 'checks))
             (requirements ,(%field (%v 'data) 'admission-requirements))
             (failed ,(%call 'first-failed-check (%v 'checks)
                              (%v 'requirements)))
             (claims ,(%field (%v 'evidence) 'claims))
             (semantic ,(%field (%v 'claims) 'semantic)))
           (%if
            (%call 'present? (%v 'failed))
            (%tagged 'admission
                     (list 'decision (%q 'reject))
                     (list 'reason
                           (%tagged 'check-failed
                                    (list 'check (%v 'failed)))))
            (%if
             (%call 'nonempty? (%v 'semantic))
             (%tagged 'admission
                      (list 'decision (%q 'defer))
                      (list 'reason (%q 'requires-human-judgment)))
             (%tagged 'admission
                      (list 'decision (%q 'accept))
                      (list 'reason (%q 'all-parent-tests-pass))))))))
    (sexp->term
     `(program
       (parameters (candidate evidence data))
       (body ,body)))))

(defun make-always-accept-admit-program ()
  (sexp->term
   '(program
     (parameters (candidate evidence data))
     (body
      (call list
            (quote admission)
            (call list (quote decision) (quote accept))
            (call list (quote reason) (quote candidate-self-accepts)))))))

(defun make-inert-react-program ()
  (sexp->term
   '(program
     (parameters (state event data world))
     (body
      (call list
            (quote reaction)
            (call list (quote state) (var state))
            (call list (quote outputs) (quote nil))
            (call list (quote effects) (quote nil)))))))

(defun genesis-probes ()
  (sexp->term
   '((probe
      (event (event (kind task) (task "ping")))
      (expected-outputs ((answer (text "pong"))))))))

(defun genesis-data (&key (generation 0))
  (make-tagged-term
   "data"
   (make-field "generation" (make-integer-atom generation))
   (make-field "capabilities" (sexp->term '(model tutor trial promote)))
   (make-field "task-context" (sexp->term '(context (role cell-zero))))
   (make-field "model-max-output-bytes" (make-integer-atom 262144))
   (make-field
    "task-model-prompt"
    (make-string-atom
     (format nil "MODE: answer-task~%Return only the answer text.~%Task:~%")))
   (make-field
    "tutor-context"
    (sexp->term
     '(tutor-context
       (contract
        (lessons "Return explicit tutor/v1 lessons as canonical terms")
        (candidates "Return candidate/v1 artifacts containing genome/v1 source bundles")
        (authority "The parent runs trials and admission before installation")))))
   (make-field "model-budget"
               (sexp->term '(budget (max-effects 1))))
   (make-field "tutor-budget"
               (sexp->term '(budget (max-effects 1))))
   (make-field "trial-budget"
               (sexp->term
                '(budget
                  (capabilities (model))
                  (max-effects 8)
                  (max-events 24)
                  (max-eval-steps 500000))))
   (make-field "admission-budget"
               (sexp->term '(budget (max-eval-steps 20000))))
   (make-field "admission-requirements"
               (sexp->term
                '(abi-valid
                  loads
                  liveness-probe
                  regression-suite
                  replay-compatible
                  capability-policy
                  resource-policy
                  automatic-properties-checkable
                  evidence-complete)))
   (make-field "probes" (genesis-probes))))

(defun initial-state ()
  (sexp->term
   '(state
     (next-effect-id 1)
     (history ())
     (pending ())
     (candidate-branches ())
     (lessons ())
     (memories ())
     (task-state ()))))

(defun make-world (react admit data &optional (state (initial-state)))
  "Construct a legacy cell-zero/1 interpreted world."
  (make-tagged-term
   "world"
   (make-field
    "genome"
    (make-tagged-term
     "genome"
     (make-field "abi" (make-symbol-atom "cell-zero/1"))
     (make-field "react" react)
     (make-field "admit" admit)
     (make-field "data" data)))
   (make-field "state" state)))

(defun bundled-source-text (relative-path)
  (uiop:read-file-string
   (asdf:system-relative-pathname (asdf:find-system "cell-zero") relative-path)
   :external-format :utf-8))

(defun make-stage0-source-genome (&key (generation 0))
  (make-source-genome
   (list (make-genome-source "stage0.lisp"
                             (bundled-source-text "genomes/stage0.lisp")))
   (make-genome-entry-point "CELL-ZERO.STAGE0.GENOME" "REACT")
   (make-genome-entry-point "CELL-ZERO.STAGE0.GENOME" "ADMIT")
   (genesis-data :generation generation)))

(defun make-inert-source-genome (&key (generation 1))
  (make-source-genome
   (list (make-genome-source "inert.lisp"
                             (bundled-source-text "genomes/inert.lisp")))
   (make-genome-entry-point "CELL-ZERO.INERT.GENOME" "REACT")
   (make-genome-entry-point "CELL-ZERO.INERT.GENOME" "ADMIT")
   (genesis-data :generation generation)))

(defun make-source-world (genome &optional (state (initial-state)))
  (make-tagged-term
   "world"
   (make-field "genome" genome)
   (make-field "state" state)))

(defun make-genesis-world ()
  (make-source-world (make-stage0-source-genome :generation 0)))

(defun make-compatible-candidate ()
  (make-source-world (make-stage0-source-genome :generation 1)))

(defun make-broken-self-accepting-candidate ()
  "A loadable genome/v1 candidate that fails liveness but would admit itself."
  (make-source-world (make-inert-source-genome :generation 1)))

(defun mechanical-claims ()
  (sexp->term
   '(claims
     (automatic
      ((preserves-behavior regression-suite)
       (replayable replay-compatible)))
     (semantic ()))))

(defun make-compatible-candidate-artifact
    (&key (candidate (make-compatible-candidate))
          (claims (mechanical-claims))
          (lessons nil))
  (make-candidate-artifact
   (world-genome candidate) (world-state candidate) claims :lessons lessons))

(defun scripted-model-option (arguments key default)
  (let ((tail (member key arguments)))
    (if (and tail (rest tail)) (second tail) default)))

(defun make-scripted-model-handler (&rest arguments)
  "Return a deterministic model/v1 task transport.
Legacy candidate and claims arguments are accepted and ignored."
  (let ((answer (scripted-model-option arguments :answer "pong")))
    (lambda (subzero request budget effect)
      (declare (ignore subzero budget effect))
      (let ((prompt (render-model-prompt request)))
        (if (uiop:string-prefix-p "MODE: answer-task" prompt)
            (values "ok"
                    (make-model-result request answer)
                    (usage-term :effects 1 :events 1))
            (values "error"
                    (make-model-failure request "unknown-request"
                                        "unknown model/v1 prompt")
                    (usage-term :effects 1 :events 1)))))))

(defun make-scripted-tutor-handler
    (candidate &key (claims (mechanical-claims))
                    (lessons
                      (list
                       (make-tutor-lesson
                        "instruction"
                        (sexp->term
                         '(lesson
                           (topic source-evolution)
                           (content "Edit the genome/v1 source bundle; the parent owns admission.")))))))
  "Return a deterministic hosted tutor/v1 handler.
CANDIDATE may be a source world, a candidate/v1 artifact, or NIL for lessons only."
  (let ((artifact
          (cond
            ((null candidate) nil)
            ((candidate-artifact-valid-p candidate) candidate)
            (t
             (make-candidate-artifact
              (world-genome candidate) (world-state candidate) claims)))))
    (lambda (subzero request budget effect)
      (declare (ignore subzero budget effect))
      (values "ok"
              (make-tutor-result request :lessons lessons :candidate artifact)
              (usage-term :effects 1 :events 1)))))

(defstruct (boot-demo-result
             (:conc-name boot-demo-)
             (:constructor %make-boot-demo-result))
  store
  initial-root
  accepted-log-root
  accepted-final-root
  accepted-lineage-root
  rejected-log-root
  rejected-final-root
  rejected-lineage-root)

(defun last-lineage-decision (subzero)
  (when (subzero-lineage subzero)
    (symbol-term-value
     (required-field (car (last (subzero-lineage subzero))) "decision"))))

(defun assert-replay-match (live replay)
  (unless (and (string= (subzero-current-root live) (subzero-current-root replay))
               (string= (subzero-lineage-root live) (subzero-lineage-root replay))
               (= (length (subzero-outputs live)) (length (subzero-outputs replay)))
               (every #'term-equal (subzero-outputs live) (subzero-outputs replay))
               (zerop (subzero-handler-calls replay)))
    (error 'protocol-error :datum replay :reason "raw-root replay diverged from live execution"))
  t)

(defun register-demo-handlers (subzero candidate)
  (register-capability-handler subzero "model" (make-scripted-model-handler))
  (register-capability-handler subzero "tutor"
                               (make-scripted-tutor-handler candidate))
  subzero)

(defun run-boot-demo (&key directory)
  "Produce and replay one accepted and one rejected genome/v1 lineage."
  (let* ((store (make-term-store :directory directory))
         (genesis (make-genesis-world))
         (initial-root (store-put store genesis))
         (good-candidate (make-compatible-candidate))
         (accepted (make-subzero store genesis))
         (bad-candidate (make-broken-self-accepting-candidate))
         (rejected (make-subzero store genesis)))
    (register-demo-handlers accepted good-candidate)
    (submit-event accepted
                  (sexp->term
                   '(event
                     (kind evolve)
                     (objective "reduce model calls without changing behavior"))))
    (run-until-idle accepted)
    (unless (string= (last-lineage-decision accepted) "accept")
      (error 'protocol-error :datum accepted :reason "genesis did not accept compatible child"))
    (let* ((accepted-log (subzero-log-root accepted))
           (accepted-replay (replay-from-roots store initial-root accepted-log)))
      (assert-replay-match accepted accepted-replay)
      (register-demo-handlers rejected bad-candidate)
      (submit-event rejected
                    (sexp->term
                     '(event
                       (kind evolve)
                       (objective "install a self-accepting but inert child"))))
      (run-until-idle rejected)
      (unless (string= (last-lineage-decision rejected) "reject")
        (error 'protocol-error :datum rejected
               :reason "parent gate did not reject the broken child"))
      (let* ((rejected-log (subzero-log-root rejected))
             (rejected-replay (replay-from-roots store initial-root rejected-log)))
        (assert-replay-match rejected rejected-replay)
        (%make-boot-demo-result
         :store store
         :initial-root initial-root
         :accepted-log-root accepted-log
         :accepted-final-root (subzero-current-root accepted)
         :accepted-lineage-root (subzero-lineage-root accepted)
         :rejected-log-root rejected-log
         :rejected-final-root (subzero-current-root rejected)
         :rejected-lineage-root (subzero-lineage-root rejected))))))
