;;;; genomes/stage0.lisp

(defpackage #:cell-zero.stage0.genome
  (:use #:cl)
  (:export #:react #:admit))

(in-package #:cell-zero.stage0.genome)

(defun list-term (&rest values)
  (apply #'cell-zero:term-list values))

(defun field-pair (name value)
  (list-term (cell-zero:make-symbol-atom name) value))

(defun tagged (tag &rest fields)
  (apply #'list-term (cell-zero:make-symbol-atom tag) fields))

(defun required (term name)
  (let* ((absent (cell-zero:make-symbol-atom "stage0-field-absent"))
         (value (cell-zero:term-field term name absent)))
    (when (cell-zero:term-equal value absent)
      (error "Missing Stage 0 field ~A" name))
    value))

(defun field (term name &optional (default (cell-zero:empty-term)))
  (cell-zero:term-field term name default))

(defun symbol-name-of (term)
  (unless (and (cell-zero:atom-p term)
               (eq (cell-zero:atom-kind term) :symbol))
    (error "Expected symbol term"))
  (cell-zero:atom-value term))

(defun integer-of (term)
  (unless (and (cell-zero:atom-p term)
               (eq (cell-zero:atom-kind term) :integer))
    (error "Expected integer term"))
  (cell-zero:atom-value term))

(defun tagged-p (term tag)
  (and (cell-zero:cell-p term)
       (let ((actual (cell-zero:term-tag term)))
         (and (cell-zero:atom-p actual)
              (eq (cell-zero:atom-kind actual) :symbol)
              (string= (cell-zero:atom-value actual) tag)))))

(defun term-elements (term)
  (cell-zero:term-list-elements term))

(defun terms-list (terms)
  (apply #'list-term terms))

(defun reaction (state outputs effects)
  (tagged "reaction"
          (field-pair "state" state)
          (field-pair "outputs" (terms-list outputs))
          (field-pair "effects" (terms-list effects))))

(defun effect (id capability request budget)
  (tagged "effect"
          (field-pair "id" (cell-zero:make-integer-atom id))
          (field-pair "capability" (cell-zero:make-symbol-atom capability))
          (field-pair "request" request)
          (field-pair "budget" budget)))

(defun pending (id kind &rest fields)
  (apply #'tagged "pending"
         (field-pair "id" (cell-zero:make-integer-atom id))
         (field-pair "kind" (cell-zero:make-symbol-atom kind))
         fields))

(defun add-list-field (term name value)
  (cell-zero:append-term-field term name value))

(defun replace-field (term name value)
  (cell-zero:put-term-field term name value))

(defun record-event (state event)
  (add-list-field state "history" event))

(defun list-without-field-value (list-term field-name value)
  (terms-list
   (remove-if
    (lambda (entry)
      (cell-zero:term-equal (field entry field-name) value))
    (term-elements list-term))))

(defun state-without-pending (state event effect-id)
  (replace-field
   (record-event state event)
   "pending"
   (list-without-field-value (required state "pending") "id" effect-id)))

(defun find-by-field (list-term field-name value)
  (find-if
   (lambda (entry)
     (cell-zero:term-equal (field entry field-name) value))
   (term-elements list-term)))

(defun next-effect-id (state)
  (integer-of (required state "next-effect-id")))

(defun state-with-pending (state item)
  (let ((id (integer-of (required item "id"))))
    (replace-field
     (add-list-field state "pending" item)
     "next-effect-id"
     (cell-zero:make-integer-atom (1+ id)))))

(defun request-hash-term (request)
  (cell-zero:make-string-atom (cell-zero:term-hash request)))

(defun effect-status-ok-p (event)
  (string= (symbol-name-of (required event "status")) "ok"))

(defun task-request (event data)
  (cell-zero:make-model-request
   (list
    (cell-zero:make-model-text-part
     (cell-zero:atom-value (required data "task-model-prompt")))
    (cell-zero:make-model-term-part (field event "task" event)))
   :max-output-bytes
   (integer-of (required data "model-max-output-bytes"))))

(defun react-to-task (state event data)
  (let* ((id (next-effect-id state))
         (request (task-request event data))
         (item (pending id "task"
                        (field-pair "request" request)
                        (field-pair "request-hash" (request-hash-term request))))
         (next-state (state-with-pending (record-event state event) item)))
    (reaction
     next-state nil
     (list (effect id "model" request (required data "model-budget"))))))

(defun react-to-evolve (state event data world)
  (let* ((id (next-effect-id state))
         (request
           (cell-zero:make-tutor-request
            (required event "objective") world
            :context (required data "tutor-context")))
         (item (pending id "evolve"
                        (field-pair "request" request)
                        (field-pair "request-hash" (request-hash-term request))
                        (field-pair "objective" (required event "objective"))))
         (next-state (state-with-pending (record-event state event) item)))
    (reaction
     next-state nil
     (list (effect id "tutor" request (required data "tutor-budget"))))))

(defun pending-for-result (state event)
  (find-by-field (required state "pending") "id"
                 (required event "effect-id")))

(defun model-result-matches-p (event pending-item)
  (and (effect-status-ok-p event)
       (cell-zero:model-result-valid-p
        (required event "response")
        (required pending-item "request"))))

(defun tutor-result-matches-p (event pending-item)
  (and (effect-status-ok-p event)
       (cell-zero:tutor-result-valid-p
        (required event "response")
        (required pending-item "request"))))

(defun react-to-task-result (state event pending-item)
  (let ((next-state
          (state-without-pending state event (required event "effect-id"))))
    (if (model-result-matches-p event pending-item)
        (reaction
         next-state
         (list (tagged "answer"
                       (field-pair
                        "text"
                        (cell-zero:make-string-atom
                         (cell-zero:model-result-text
                          (required event "response"))))))
         nil)
        (reaction
         next-state
         (list (tagged "model-failure"
                       (field-pair "reason"
                                   (cell-zero:make-symbol-atom
                                    "invalid-model-result"))))
         nil))))

(defun append-lessons (state lessons)
  (reduce (lambda (next lesson)
            (add-list-field next "lessons" lesson))
          lessons :initial-value state))

(defun malformed-candidate-reaction (state)
  (let* ((rejection
           (tagged "branch"
                   (field-pair "status" (cell-zero:make-symbol-atom "rejected"))
                   (field-pair "reason"
                               (cell-zero:make-symbol-atom "malformed-candidate"))))
         (next-state (add-list-field state "candidate-branches" rejection)))
    (reaction next-state (list rejection) nil)))

(defun candidate-trial-reaction (state data artifact)
  (if (not (cell-zero:candidate-artifact-valid-p artifact))
      (malformed-candidate-reaction state)
      (let* ((id (next-effect-id state))
             (candidate (cell-zero:candidate-artifact-world artifact))
             (claims (cell-zero:candidate-artifact-claims artifact))
             (branch
               (tagged "branch"
                       (field-pair "artifact" artifact)
                       (field-pair "candidate" candidate)
                       (field-pair "claims" claims)
                       (field-pair "status"
                                   (cell-zero:make-symbol-atom "proposed"))))
             (trial-pending
               (pending id "trial"
                        (field-pair "candidate" candidate)
                        (field-pair "claims" claims)))
             (next-state
               (state-with-pending
                (add-list-field state "candidate-branches" branch)
                trial-pending))
             (request
               (tagged "trial"
                       (field-pair "candidate" candidate)
                       (field-pair "events" (required data "probes")))))
        (reaction
         next-state nil
         (list (effect id "trial" request (required data "trial-budget")))))))

(defun react-to-tutor-result (state event pending-item data)
  (let ((base-state
          (state-without-pending state event (required event "effect-id"))))
    (if (not (tutor-result-matches-p event pending-item))
        (reaction
         base-state
         (list (tagged "tutor-failure"
                       (field-pair "reason"
                                   (cell-zero:make-symbol-atom
                                    "invalid-tutor-result"))))
         nil)
        (let* ((result (required event "response"))
               (candidate (cell-zero:tutor-result-candidate result))
               (lessons
                 (append (cell-zero:tutor-result-lessons result)
                         (if candidate
                             (cell-zero:candidate-artifact-lessons candidate)
                             nil)))
               (next-state (append-lessons base-state lessons)))
          (if candidate
              (candidate-trial-reaction next-state data candidate)
              (reaction
               next-state
               (list (tagged "tutor-update"
                             (field-pair "lessons" (terms-list lessons))))
               nil))))))

(defun react-to-trial-result (state event pending-item data)
  (let* ((response (required event "response"))
         (trace (field response "trace"))
         (base-state
           (state-without-pending state event (required event "effect-id"))))
    (if (cell-zero:term-equal trace (cell-zero:empty-term))
        (reaction
         base-state
         (list (tagged "trial-failed"
                       (field-pair "response" response)))
         nil)
        (let* ((id (next-effect-id base-state))
               (candidate (required pending-item "candidate"))
               (claims (required pending-item "claims"))
               (promotion-pending
                 (pending id "promote"
                          (field-pair "candidate" candidate)
                          (field-pair "claims" claims)))
               (next-state (state-with-pending base-state promotion-pending))
               (request
                 (tagged "promote"
                         (field-pair "candidate" candidate)
                         (field-pair "trials" (list-term trace))
                         (field-pair "claims" claims))))
          (reaction
           next-state nil
           (list (effect id "promote" request
                         (required data "admission-budget"))))))))

(defun react-to-effect-result (state event data)
  (let ((pending-item (pending-for-result state event)))
    (if (null pending-item)
        (reaction (record-event state event) nil nil)
        (let ((kind (symbol-name-of (required pending-item "kind"))))
          (cond
            ((string= kind "task")
             (react-to-task-result state event pending-item))
            ((string= kind "evolve")
             (react-to-tutor-result state event pending-item data))
            ((string= kind "trial")
             (react-to-trial-result state event pending-item data))
            (t
             (reaction (record-event state event) nil nil)))))))

(defun react-to-promotion-result (state event)
  (let* ((next-state
           (replace-field
            (record-event state event)
            "pending"
            (list-without-field-value
             (required state "pending") "id" (required event "effect-id"))))
         (output
           (tagged "promotion-result"
                   (field-pair "decision" (required event "decision"))
                   (field-pair "candidate" (required event "candidate"))
                   (field-pair "reason" (required event "reason")))))
    (reaction next-state (list output) nil)))

(defun react (state event data world)
  (let ((kind (symbol-name-of (required event "kind"))))
    (cond
      ((string= kind "task") (react-to-task state event data))
      ((string= kind "evolve") (react-to-evolve state event data world))
      ((string= kind "effect-result")
       (react-to-effect-result state event data))
      ((string= kind "promotion-result")
       (react-to-promotion-result state event))
      (t
       (reaction (record-event state event) nil nil)))))

(defun check-status (checks name)
  (let ((pair
          (find-if
           (lambda (check)
             (let ((parts (term-elements check)))
               (and (= (length parts) 2)
                    (string= (symbol-name-of (first parts)) name))))
           (term-elements checks))))
    (and pair (symbol-name-of (second (term-elements pair))))))

(defun first-failed-check (checks requirements)
  (find-if
   (lambda (requirement)
     (not (string= (or (check-status checks (symbol-name-of requirement)) "missing")
                   "pass")))
   (term-elements requirements)))

(defun admit (candidate evidence data)
  (declare (ignore candidate))
  (let* ((checks (required evidence "checks"))
         (requirements (required data "admission-requirements"))
         (failed (first-failed-check checks requirements))
         (claims (required evidence "claims"))
         (semantic (term-elements (required claims "semantic"))))
    (cond
      (failed
       (tagged "admission"
               (field-pair "decision" (cell-zero:make-symbol-atom "reject"))
               (field-pair
                "reason"
                (tagged "check-failed" (field-pair "check" failed)))))
      (semantic
       (tagged "admission"
               (field-pair "decision" (cell-zero:make-symbol-atom "defer"))
               (field-pair "reason"
                           (cell-zero:make-symbol-atom
                            "requires-human-judgment"))))
      (t
       (tagged "admission"
               (field-pair "decision" (cell-zero:make-symbol-atom "accept"))
               (field-pair "reason"
                           (cell-zero:make-symbol-atom
                            "all-parent-tests-pass")))))))
