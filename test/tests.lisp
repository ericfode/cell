;;;; test/tests.lisp

(in-package #:cell-zero.tests)

(defvar *tests* nil)
(defvar *assertions* 0)

(defmacro deftest (name &body body)
  `(progn
     (pushnew ',name *tests*)
     (defun ,name () ,@body)))

(defmacro is (form &optional description)
  `(progn
     (incf *assertions*)
     (unless ,form
       (error "Assertion failed~@[: ~A~]: ~S" ,description ',form))))

(defmacro signals (condition &body body)
  `(handler-case
       (progn ,@body
              (error "Expected condition ~S" ',condition))
     (,condition () t)))

(defun utf8 (string)
  (cell-zero::string-utf8-octets string))

(defun lineage-decisions (store root)
  (let* ((lineage (store-get store root))
         (entries (term-list-elements (term-field lineage "entries"))))
    (mapcar (lambda (entry)
              (cell-zero::symbol-term-value (term-field entry "decision")))
            entries)))

(defun make-temp-directory ()
  (let ((directory
          (merge-pathnames
           (format nil "cell-zero-tests-~D-~D/"
                   (get-universal-time) (random 1000000000))
           (uiop:temporary-directory))))
    (ensure-directories-exist (merge-pathnames "placeholder" directory))
    directory))

(deftest sha256-known-vector
  (is (string= (sha256-hex (utf8 "abc"))
               "BA7816BF8F01CFEA414140DE5DAE2223B00361A396177A9CB410FF61F20015AD")))

(deftest canonical-term-identity
  (let ((left (sexp->term '(world (genome (abi cell-zero/1)) (state))))
        (right (sexp->term '(world (genome (abi cell-zero/1)) (state))))
        (symbol (sexp->term 'alpha))
        (string (sexp->term "alpha")))
    (is (term-equal left right))
    (is (string= (term-hash left) (term-hash right)))
    (is (not (term-equal symbol string)))
    (is (equal (term->sexp left) (term->sexp right)))))

(deftest filesystem-store-verifies-raw-roots
  (let ((directory (make-temp-directory)))
    (unwind-protect
         (let* ((first-store (make-term-store :directory directory))
                (term (sexp->term '(root (value "persisted") (count 3))))
                (root (store-put first-store term))
                (second-store (make-term-store :directory directory))
                (loaded (store-get second-store root)))
           (is (term-equal term loaded))
           (is (string= root (term-hash loaded))))
      (uiop:delete-directory-tree directory :validate t :if-does-not-exist :ignore))))

(deftest evaluator-is-bounded-and-first-order
  (let ((program
          (sexp->term
           '(program
             (parameters (x))
             (body (call integer+ (var x) (quote 1)))))))
    (multiple-value-bind (result usage)
        (evaluate-program program
                          (list (cons 'x (make-integer-atom 4))))
      (is (= 5 (cell-zero::integer-term-value/protocol result)))
      (is (plusp (usage-steps usage))))
    (is (signals evaluation-budget-exhausted
          (evaluate-program program
                            (list (cons 'x (make-integer-atom 4)))
                            :limits (make-evaluation-limits :max-steps 1))))))

(deftest model-v1-request-result-and-credential-contract
  (let* ((payload (sexp->term '(task (name "stage-zero"))))
         (request
           (make-model-request
            (list (make-model-text-part "Task: ")
                  (make-model-term-part payload))
            :max-output-bytes 64))
         (same
           (make-model-request
            (list (make-model-text-part "Task: ")
                  (make-model-term-part payload))
            :max-output-bytes 64))
         (usage (make-model-usage :input-tokens 7 :output-tokens 3))
         (result (make-model-result request "done" :usage usage))
         (credential (make-model-credential "autolith/default")))
    (is (model-request-valid-p request))
    (is (string= (model-request-hash request) (model-request-hash same)))
    (is (search "|task|" (render-model-prompt request)))
    (is (model-result-valid-p result request))
    (is (= 7 (model-usage-input-tokens (model-result-usage result))))
    (is (= 3 (model-usage-output-tokens (model-result-usage result))))
    (is (model-credential-valid-p credential))
    (is (string= "autolith/default" (model-credential-ref credential)))
    (is (signals protocol-error
          (make-model-result request (make-string 65 :initial-element #\x))))))

(deftest evaluator-parses-model-text-as-a-bounded-term
  (let ((program
          (sexp->term
           '(program
             (parameters (text))
             (body (call parse-term (var text)))))))
    (multiple-value-bind (parsed usage)
        (evaluate-program program
                          (list (cons 'text (make-string-atom "(|proposal| (|value| 7))"))))
      (is (string= "ok"
                   (cell-zero::symbol-term-value (term-field parsed "status"))))
      (is (term-equal (sexp->term '(proposal (value 7)))
                      (term-field parsed "value")))
      (is (plusp (usage-steps usage))))
    (let ((failed
            (evaluate-program program
                              (list (cons 'text (make-string-atom "("))))))
      (is (string= "error"
                   (cell-zero::symbol-term-value (term-field failed "status")))))))

(defun run-genesis-task-with-model-handler (handler)
  (let* ((store (make-term-store))
         (world (make-genesis-world))
         (subzero (make-subzero store world)))
    (register-capability-handler subzero "model" handler)
    (submit-event subzero
                  (sexp->term '(event (kind task) (task "stage-zero"))))
    (run-until-idle subzero)
    subzero))

(deftest recorded-model-transcript-runs-through-standalone-fixture
  (multiple-value-bind (recording transcript-reader)
      (make-recording-model-handler
       (make-scripted-model-handler nil :answer "STAGE0_OK"))
    (let* ((live (run-genesis-task-with-model-handler recording))
           (transcript (funcall transcript-reader)))
      (is (model-transcript-valid-p transcript))
      (is (= 1 (length (model-transcript-exchanges transcript))))
      (multiple-value-bind (fixture consumed-p)
          (make-model-fixture-handler transcript)
        (let ((replayed (run-genesis-task-with-model-handler fixture)))
          (is (funcall consumed-p))
          (is (string= (subzero-current-root live)
                       (subzero-current-root replayed)))
          (is (string= (subzero-log-root live)
                       (subzero-log-root replayed)))
          (is (every #'term-equal
                     (subzero-outputs live)
                     (subzero-outputs replayed))))))))

(defun run-genesis-evolution-with-tutor-handler (handler)
  (let* ((store (make-term-store))
         (subzero (make-subzero store (make-genesis-world))))
    (register-capability-handler subzero "model" (make-scripted-model-handler))
    (register-capability-handler subzero "tutor" handler)
    (submit-event subzero
                  (sexp->term '(event (kind evolve) (objective "source child"))))
    (run-until-idle subzero)
    subzero))

(deftest stage0-is-an-ordinary-source-bundle
  (let* ((world (make-genesis-world))
         (genome (world-genome world))
         (source (first (source-genome-sources genome)))
         (tampered
           (put-term-field source "text"
                           (make-string-atom "(in-package #:cl-user)")))
         (missing (make-symbol-atom "missing")))
    (is (string= "genome/v1" (genome-abi-name genome)))
    (is (source-genome-valid-p genome))
    (is (source-genome-loads-p genome))
    (is (null (find-package "CELL-ZERO.STAGE0.GENOME")))
    (is (genome-source-valid-p source))
    (is (not (genome-source-valid-p tampered)))
    (is (string= (genome-source-hash source)
                 (cell-zero::genome-source-text-hash
                  (genome-source-text source))))
    (is (string= "entry-point" (atom-value (term-tag (genome-react genome)))))
    (is (term-equal missing (term-field genome "react" missing)))
    (is (term-equal missing (term-field genome "admit" missing)))))

(deftest hosted-tutor-artifact-runs-through-standalone-fixture
  (let ((candidate (make-compatible-candidate)))
    (multiple-value-bind (recording transcript-reader)
        (make-recording-tutor-handler
         (make-scripted-tutor-handler candidate))
      (let* ((live (run-genesis-evolution-with-tutor-handler recording))
             (transcript (funcall transcript-reader))
             (exchange (first (tutor-transcript-exchanges transcript)))
             (response (term-field exchange "response"))
             (artifact (tutor-result-candidate response))
             (missing (make-symbol-atom "missing")))
        (is (tutor-transcript-valid-p transcript))
        (is (= 1 (length (tutor-transcript-exchanges transcript))))
        (is (candidate-artifact-valid-p artifact))
        (is (string= "genome/v1"
                     (genome-abi-name (candidate-artifact-genome artifact))))
        (is (term-equal missing (term-field response "text" missing)))
        (multiple-value-bind (fixture consumed-p)
            (make-tutor-fixture-handler transcript)
          (let ((replayed (run-genesis-evolution-with-tutor-handler fixture)))
            (is (funcall consumed-p))
            (is (string= (subzero-current-root live)
                         (subzero-current-root replayed)))
            (is (string= (subzero-log-root live)
                         (subzero-log-root replayed)))
            (is (string= (subzero-lineage-root live)
                         (subzero-lineage-root replayed)))
            (is (every #'term-equal
                       (subzero-outputs live)
                       (subzero-outputs replayed)))))))))

(deftest tutor-lessons-are-explicit-without-installation
  (let ((subzero
          (run-genesis-evolution-with-tutor-handler
           (make-scripted-tutor-handler nil))))
    (is (null (cell-zero::subzero-lineage subzero)))
    (is (= 1 (length (term-list-elements
                      (term-field (world-state (subzero-current-world subzero))
                                  "lessons")))))
    (is (string= "tutor-update"
                 (atom-value (term-tag (first (subzero-outputs subzero))))))))

(deftest accepted-and-rejected-lineages-replay
  (let* ((demo (run-boot-demo))
         (store (boot-demo-store demo)))
    (is (equal '("accept")
               (lineage-decisions store (boot-demo-accepted-lineage-root demo))))
    (is (equal '("reject")
               (lineage-decisions store (boot-demo-rejected-lineage-root demo))))
    (let ((accepted
            (replay-from-roots store
                               (boot-demo-initial-root demo)
                               (boot-demo-accepted-log-root demo)))
          (rejected
            (replay-from-roots store
                               (boot-demo-initial-root demo)
                               (boot-demo-rejected-log-root demo))))
      (is (string= (boot-demo-accepted-final-root demo)
                   (subzero-current-root accepted)))
      (is (string= (boot-demo-rejected-final-root demo)
                   (subzero-current-root rejected)))
      (is (zerop (subzero-handler-calls accepted)))
      (is (zerop (subzero-handler-calls rejected))))))

(deftest raw-root-replay-survives-store-reopen
  (let ((directory (make-temp-directory)))
    (unwind-protect
         (let* ((demo (run-boot-demo :directory directory))
                (reopened (make-term-store :directory directory))
                (accepted
                  (replay-from-roots reopened
                                     (boot-demo-initial-root demo)
                                     (boot-demo-accepted-log-root demo)))
                (rejected
                  (replay-from-roots reopened
                                     (boot-demo-initial-root demo)
                                     (boot-demo-rejected-log-root demo))))
           (is (string= (boot-demo-accepted-final-root demo)
                        (subzero-current-root accepted)))
           (is (string= (boot-demo-rejected-final-root demo)
                        (subzero-current-root rejected)))
           (is (zerop (subzero-handler-calls accepted)))
           (is (zerop (subzero-handler-calls rejected))))
      (uiop:delete-directory-tree directory :validate t :if-does-not-exist :ignore))))

(deftest candidate-cannot-admit-itself
  (let* ((candidate (make-broken-self-accepting-candidate))
         (admission
           (cell-zero::invoke-source-genome-admit
            (world-genome candidate) candidate (sexp->term '(evidence))))
         (demo (run-boot-demo)))
    (is (string= "accept"
                 (cell-zero::symbol-term-value (term-field admission "decision"))))
    (is (equal '("reject")
               (lineage-decisions (boot-demo-store demo)
                                  (boot-demo-rejected-lineage-root demo))))))

(deftest semantic-claims-defer
  (let* ((store (make-term-store))
         (world (make-genesis-world))
         (candidate (make-compatible-candidate))
         (claims (sexp->term
                  '(claims
                    (automatic ((preserves-behavior regression-suite)))
                    (semantic ((better-writing human-judgment))))))
         (subzero (make-subzero store world)))
    (register-capability-handler subzero "model" (make-scripted-model-handler))
    (register-capability-handler
     subzero "tutor" (make-scripted-tutor-handler candidate :claims claims))
    (submit-event subzero
                  (sexp->term '(event (kind evolve) (objective "write better"))))
    (run-until-idle subzero)
    (is (equal '("defer")
               (lineage-decisions store (subzero-lineage-root subzero))))))

(deftest fabricated-trace-cannot-promote
  (let* ((store (make-term-store))
         (world (make-genesis-world))
         (candidate (make-compatible-candidate))
         (subzero (make-subzero store world))
         (request
           (sexp->term
            `(promote
              (candidate ,candidate)
              (trials ("0000000000000000000000000000000000000000000000000000000000000000"))
              (claims
               (claims
                (automatic ((preserves-behavior regression-suite)))
                (semantic ()))))))
         (effect
           (cell-zero::seal-effect
            subzero
            (cell-zero::make-tagged-term
             "effect"
             (cell-zero::make-field "id" (make-integer-atom 99))
             (cell-zero::make-field "capability" (make-symbol-atom "promote"))
             (cell-zero::make-field "request" request)
             (cell-zero::make-field "budget" (sexp->term '(budget))))))
         (parent-root (subzero-current-root subzero))
         (result (cell-zero::perform-promotion subzero effect)))
    (is (string= "reject"
                 (cell-zero::symbol-term-value (term-field result "decision"))))
    (is (string= parent-root (subzero-current-root subzero)))
    (is (equal '("reject")
               (lineage-decisions store (subzero-lineage-root subzero))))))

(deftest effect-results-bind-exact-requests
  (let* ((effect
           (cell-zero::make-tagged-term
            "effect"
            (cell-zero::make-field "id" (make-integer-atom 1))
            (cell-zero::make-field "capability" (make-symbol-atom "model"))
            (cell-zero::make-field "request" (sexp->term '(answer-task)))
            (cell-zero::make-field "budget" (sexp->term '(budget)))
            (cell-zero::make-field
             "context"
             (sexp->term '(effect-context (world "w") (genome "g"))))))
         (event
           (cell-zero::make-effect-result-event
            effect "ok" (sexp->term '(answer (text "ok")))
            (sexp->term '(resource-usage (effects 1)))))
         (tampered (put-term-field event "request-hash" (make-string-atom "wrong"))))
    (is (cell-zero::verify-effect-result-binding effect event))
    (is (signals protocol-error
          (cell-zero::verify-effect-result-binding effect tampered)))))

(deftest term-accessors-are-defensive-and-text-is-canonical
  (let* ((source-bytes (make-array 3 :element-type '(unsigned-byte 8)
                                   :initial-contents '(1 2 3)))
         (bytes (make-bytes-atom source-bytes))
         (string (make-string-atom "immutable"))
         (hash (term-hash string))
         (node (cell-zero::term-node-octets string))
         (string-value (atom-value string))
         (bytes-value (atom-value bytes)))
    (setf (aref source-bytes 0) 9
          (aref bytes-value 1) 9
          (char string-value 0) #\X
          (char hash 0) (if (char= (char hash 0) #\0) #\1 #\0)
          (aref node 0) 0)
    (is (string= "immutable" (atom-value string)))
    (is (equalp #(1 2 3) (atom-value bytes)))
    (is (not (string= hash (term-hash string))))
    (is (not (equalp node (cell-zero::term-node-octets string)))))
  (dolist (name '("123" "-1" "1/2" "alpha:beta" "λX"))
    (let* ((term (make-symbol-atom name))
           (text (with-output-to-string (stream) (write-term term stream))))
      (is (term-equal term (read-term text)))
      (is (term-equal term (sexp->term (term->sexp term))))))
  (let ((*print-base* 16))
    (let* ((term (make-integer-atom 10))
           (text (with-output-to-string (stream) (write-term term stream))))
      (is (string= "10" text))
      (is (term-equal term (read-term text))))))
  (let ((*read-suppress* t)
        (term (sexp->term '(value 7))))
    (is (term-equal term (read-term "(|value| 7)"))))

(deftest store-hash-strings-do-not-alias-cache-keys
  (let ((directory (make-temp-directory)))
    (unwind-protect
         (let* ((store (make-term-store :directory directory))
                (term (sexp->term '(root (value "stable"))))
                (root (store-put store term))
                (canonical (copy-seq root)))
           (setf (char root 0) (if (char= (char root 0) #\0) #\1 #\0))
           (is (store-exists-p store canonical))
           (let* ((reopened (make-term-store :directory directory))
                  (lookup (copy-seq canonical))
                  (loaded (store-get reopened lookup)))
             (setf (char lookup 0) (if (char= (char lookup 0) #\0) #\1 #\0))
             (is (term-equal term loaded))
             (is (term-equal loaded (store-get reopened canonical)))))
      (uiop:delete-directory-tree directory :validate t :if-does-not-exist :ignore))))

(deftest forged-term-slots-are-rejected-by-storage
  (let* ((canonical (make-string-atom "canonical"))
         (forged
           (make-instance 'cell-zero:atom
                          :kind :string
                          :value "forged"
                          :hash (term-hash canonical)
                          :node-octets (cell-zero::term-node-octets canonical))))
    (is (signals store-error
          (store-put (make-term-store) forged)))))

(deftest duplicate-fields-and-malformed-evaluator-inputs-are-rejected
  (is (signals malformed-term
        (term-field (sexp->term '(record (x 1) (x 2))) "x")))
  (let ((bad-program
          (sexp->term
           '(program
             (parameters (x))
             (body (call integer+ (var x))))))
        (program
          (sexp->term
           '(program
             (parameters (x))
             (body (call integer+ (var x) (quote 1))))))
        (value (make-integer-atom 1)))
    (is (signals evaluation-error (validate-program bad-program)))
    (is (signals evaluation-error
          (evaluate-program program (list (cons 'x value) (cons "x" value)))))
    (is (signals evaluation-error
          (evaluate-program program (list 'x value 'unknown value))))
    (is (signals evaluation-error
          (evaluate-program program (list 'x value 'dangling))))))

(defun exercise-durable-recovery (name reserve-request-p)
  (let ((directory (make-temp-directory)))
    (unwind-protect
         (let* ((store (make-term-store :directory directory))
                (candidate (make-compatible-candidate))
                (subzero (make-subzero store (make-genesis-world) :name name)))
           (submit-event subzero
                         (sexp->term '(event (kind evolve) (objective "recover"))))
           (is (signals protocol-error
                 (submit-event subzero
                               (sexp->term '(event (kind evolve)
                                                   (objective "interleave"))))))
           (when reserve-request-p
             (cell-zero::reserve-next-effect subzero))
           (let* ((reopened-store (make-term-store :directory directory))
                  (reopened (reopen-subzero reopened-store name)))
             (if reserve-request-p
                 (is (cell-zero::subzero-pending-effect reopened))
                 (is (cell-zero::subzero-effect-queue reopened)))
            (register-capability-handler
             reopened "model" (make-scripted-model-handler))
            (register-capability-handler
             reopened "tutor" (make-scripted-tutor-handler candidate))
            (run-until-idle reopened)
             (is (zerop (length (cell-zero::subzero-effect-queue reopened))))
             (is (null (cell-zero::subzero-pending-effect reopened)))
             (is (= 1 (subzero-handler-calls reopened)))
             (let* ((final-root (subzero-current-root reopened))
                    (verified
                      (reopen-subzero (make-term-store :directory directory) name)))
               (is (string= final-root (subzero-current-root verified)))
               (is (zerop (subzero-handler-calls verified))))))
      (uiop:delete-directory-tree directory :validate t :if-does-not-exist :ignore))))

(deftest durable-queued-effects-reopen-and-complete
  (exercise-durable-recovery "queued" nil))

(deftest durable-pending-requests-reopen-and-complete
  (exercise-durable-recovery "pending" t))

(deftest homoiconic-evaluator-is-self-interpreting
  (is (homoiconic-evaluator-self-check))
  (let* ((evaluator (make-homoiconic-evaluator-program))
         (program
           (sexp->term
            '(program
              (parameters (items))
              (body
               (letrec
                ((sum
                  (lambda (rest total)
                   (if (call nonempty? (var rest))
                       (apply (var sum)
                              (call rest (var rest))
                              (call integer+ (var total)
                                    (call first (var rest))))
                       (var total)))))
                (apply (var sum) (var items) (quote 0)))))))
         (items (sexp->term '(1 2 3 4))))
    (multiple-value-bind (result usage)
        (evaluate-homoiconic-program
         evaluator program (list (cons 'items items)))
      (is (= 10 (cell-zero::integer-term-value/protocol result)))
      (is (plusp (usage-steps usage))))))

(defun run-homoiconic-selection-test (parent candidate parent-score candidate-score)
  (let* ((store (make-term-store))
         (cell (make-homoiconic-cell store parent)))
    (register-homoiconic-handler
     cell "model" (make-scripted-homoiconic-model-handler candidate))
    (register-homoiconic-handler
     cell "runner"
     (make-scripted-homoiconic-runner-handler
      (lambda (capsule event)
        (declare (ignore event))
        (values t
                (if (term-equal capsule candidate)
                    candidate-score
                    parent-score)
                (empty-term)))))
    (submit-homoiconic-event
     cell (sexp->term '(event (kind evolve) (objective "improve"))))
    (run-homoiconic-until-idle cell)
    cell))

(deftest homoiconic-capsule-is-closed-and-parent-selected
  (let* ((parent (make-homoiconic-genesis-capsule))
         (candidate
           (make-homoiconic-genesis-capsule
            :task-context "Inspect first, edit narrowly, and run the verifier."))
          (broken (put-term-field parent "evaluator" (empty-term)))
          (wrong-evaluator
            (put-term-field
             parent "evaluator"
             (sexp->term
              '(program (parameters (value)) (body (var value))))))
          (cell (run-homoiconic-selection-test parent candidate 1 2))
          (selection (first (homoiconic-cell-outputs cell))))
    (is (capsule-valid-p parent))
    (is (not (capsule-valid-p broken)))
    (is (not (capsule-valid-p wrong-evaluator)))
    (is (term-equal candidate (homoiconic-cell-current-capsule cell)))
    (is (= 1 (length (homoiconic-cell-lineage cell))))
    (is (string= "promote"
                 (cell-zero::symbol-term-value
                  (term-field selection "decision"))))
    (is (plusp (homoiconic-cell-evaluation-steps cell)))))

(deftest homoiconic-host-rejects-structurally-invalid-successor
  (let* ((parent (make-homoiconic-genesis-capsule))
         (broken (put-term-field parent "evaluator" (empty-term)))
         (cell (run-homoiconic-selection-test parent broken 0 1))
         (current (homoiconic-cell-current-capsule cell))
         (selection (first (homoiconic-cell-outputs cell)))
         (lineage-entry (first (homoiconic-cell-lineage cell))))
    (is (capsule-valid-p current))
    (is (term-equal (capsule-evaluator parent)
                    (capsule-evaluator current)))
    (is (string= "promote"
                 (cell-zero::symbol-term-value
                  (term-field selection "decision"))))
    (is (string= "structurally-rejected"
                 (cell-zero::symbol-term-value
                  (term-field lineage-entry "decision"))))))

(deftest homoiconic-selection-policy-is-hereditary
  (let* ((candidate
           (make-homoiconic-genesis-capsule
            :task-context "Candidate policy"))
         (strict
           (run-homoiconic-selection-test
            (make-homoiconic-genesis-capsule :accept-equal nil)
            candidate 1 1))
         (permissive
           (run-homoiconic-selection-test
            (make-homoiconic-genesis-capsule :accept-equal t)
            candidate 1 1))
         (strict-selection (first (homoiconic-cell-outputs strict)))
         (permissive-selection (first (homoiconic-cell-outputs permissive))))
    (is (string= "retain"
                 (cell-zero::symbol-term-value
                  (term-field strict-selection "decision"))))
    (is (string= "promote"
                 (cell-zero::symbol-term-value
                  (term-field permissive-selection "decision"))))
    (is (not (term-equal candidate
                         (homoiconic-cell-current-capsule strict))))
    (is (term-equal candidate
                    (homoiconic-cell-current-capsule permissive)))))

(deftest malformed-input-is-rejected-before-commit
  (let* ((store (make-term-store))
         (subzero (make-subzero store (make-genesis-world)))
         (before (subzero-log-root subzero)))
    (is (signals protocol-error
          (submit-event subzero (sexp->term '(not-an-event (kind task))))))
    (is (string= before (subzero-log-root subzero)))))

(defun run-tests ()
  (setf *assertions* 0)
  (let ((failures nil))
    (dolist (test (reverse *tests*))
      (handler-case
          (funcall test)
        (error (condition)
          (push (cons test condition) failures))))
    (when failures
      (format *error-output* "~&~D Cell-zero test~:P failed:~%"
              (length failures))
      (dolist (failure (reverse failures))
        (format *error-output* "  ~A: ~A~%" (car failure) (cdr failure)))
      (return-from run-tests nil))
    (format t "~&Cell-zero: ~D tests, ~D assertions passed.~%"
            (length *tests*) *assertions*)
    t))
