;;;; lab/c0-event-eater.lisp

(in-package #:cell-zero-lab)

(defstruct c0-counts
  (cases 0) (replay-root-mismatches 0) (unrecorded-effects-on-replay 0)
  (lost-committed-events 0) (silent-malformed-event-skips 0)
  (errors 0) (error-details nil))

(defun c0-next (state)
  (mod (+ (* state 6364136223846793005) 1442695040888963407)
       18446744073709551616))

(defun c0-output-root (outputs)
  (term-hash (apply #'term-list outputs)))

(defun c0-react-program ()
  (sexp->term
   '(program
     (parameters (state event data world))
     (body
      (call list
            (quote reaction)
            (call list (quote state)
                  (call append-field (var state) (quote history) (var event)))
            (call list (quote outputs) (call list (var event)))
            (call list (quote effects) (quote nil)))))))

(defun c0-world ()
  (cell-zero::make-world
   (c0-react-program)
   (cell-zero::make-genesis-admit-program)
   (sexp->term '(data (capabilities ()) (generation 0)))))

(defun c0-compare-replay (counts subject store)
  (let ((replayed (replay-from-roots store
                                    (subzero-initial-root subject)
                                    (subzero-log-root subject))))
    (unless (and (string= (subzero-current-root subject)
                          (subzero-current-root replayed))
                 (string= (c0-output-root (subzero-outputs subject))
                          (c0-output-root (subzero-outputs replayed))))
      (incf (c0-counts-replay-root-mismatches counts)))
    (unless (zerop (subzero-handler-calls replayed))
      (incf (c0-counts-unrecorded-effects-on-replay counts)))))

(defun c0-malformed-case (counts)
  (let* ((store (make-term-store))
         (subject (make-subzero store (c0-world)))
         (before (subzero-log-root subject))
         (signaled nil))
    (handler-case
        (submit-event subject (sexp->term '(not-an-event (kind task))))
      (cell-zero:protocol-error () (setf signaled t)))
    (unless signaled (incf (c0-counts-silent-malformed-event-skips counts)))
    (unless (string= before (subzero-log-root subject))
      (incf (c0-counts-lost-committed-events counts)))))

(defun c0-generated-event (state index)
  (let ((kind (case (mod state 5)
                (0 'effect-result)
                (1 'timeout)
                (2 'model-result)
                (3 'restart)
                (t 'input))))
    (sexp->term
     `(event (kind ,kind) (sequence ,index) (payload ,(mod state 1000000))))))

(defun c0-cheap-history-case (counts state)
  (let* ((store (make-term-store))
         (subject (make-subzero store (c0-world)))
         (length (1+ (mod state 12)))
         (last-event nil))
    (dotimes (index length)
      (setf state (c0-next state)
            last-event (c0-generated-event state index))
      (submit-event subject last-event)
      ;; Duplicated effect-result/input events are committed explicitly.
      (when (zerop (mod state 17))
        (submit-event subject last-event))
      ;; Restart/replay at generated event boundaries without handler access.
      (when (zerop (mod state 7))
        (c0-compare-replay counts subject store)))
    (c0-compare-replay counts subject store)))

(defun c0-pending-effect-case (counts)
  (let* ((store (make-term-store))
         (subject (make-subzero store (make-genesis-world)))
         (candidate (cell-zero:make-compatible-candidate)))
    (register-capability-handler subject "model"
                                 (make-scripted-model-handler candidate))
    (submit-event subject
                  (sexp->term '(event (kind task) (instruction "probe"))))
    (cell-zero::reserve-next-effect subject)
    (let ((partial (replay-from-roots store
                                      (subzero-initial-root subject)
                                      (subzero-log-root subject)
                                      :allow-unresolved t)))
      (unless (zerop (subzero-handler-calls partial))
        (incf (c0-counts-unrecorded-effects-on-replay counts))))
    (cell-zero::complete-pending-effect subject)
    (run-until-idle subject)
    (c0-compare-replay counts subject store)))

(defun run-c0-distribution (&key (seed 1) (cases 10000))
  "Run a generated C0 distribution. Hidden cases are selected only from SEED."
  (let ((counts (make-c0-counts))
        (state seed))
    (dotimes (index cases counts)
      (incf (c0-counts-cases counts))
      (setf state (c0-next state))
      (handler-case
          (cond
            ((zerop (mod state 16)) (c0-malformed-case counts))
            ((zerop (mod state 257)) (c0-pending-effect-case counts))
            (t (c0-cheap-history-case counts state)))
        (error (condition)
          (incf (c0-counts-errors counts))
          (when (< (length (c0-counts-error-details counts)) 10)
            (push (princ-to-string condition)
                  (c0-counts-error-details counts))))))))

(defun c0-counts-passed-p (counts)
  (and (zerop (c0-counts-replay-root-mismatches counts))
       (zerop (c0-counts-unrecorded-effects-on-replay counts))
       (zerop (c0-counts-lost-committed-events counts))
       (zerop (c0-counts-silent-malformed-event-skips counts))
       (zerop (c0-counts-errors counts))))

(defun write-c0-report (counts stream &key seed lineage-root)
  (write `((challenge c0)
           (hidden-seed ,(term-hash (sexp->term `(hidden-seed (challenge c0) (value ,seed)))))
           (lineage ,lineage-root)
           (cases ,(c0-counts-cases counts))
           (replay-root-mismatches ,(c0-counts-replay-root-mismatches counts))
           (unrecorded-effects-on-replay ,(c0-counts-unrecorded-effects-on-replay counts))
           (lost-committed-events ,(c0-counts-lost-committed-events counts))
           (silent-malformed-event-skips ,(c0-counts-silent-malformed-event-skips counts))
           (errors ,(c0-counts-errors counts))
           (error-details ,(nreverse (copy-list (c0-counts-error-details counts))))
           (passed ,(c0-counts-passed-p counts)))
         :stream stream :pretty t)
  (terpri stream))
