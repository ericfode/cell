;;;; lab/protocol.lisp

(in-package #:cell-zero-lab)

(defstruct (laboratory (:constructor %make-laboratory))
  (hidden (make-hash-table :test #'equal))
  directory
  current-root
  champion-root
  (attestations nil))

(defun laboratory-ref-path (laboratory relative)
  (and (laboratory-directory laboratory)
       (merge-pathnames relative (laboratory-directory laboratory))))

(defun read-laboratory-ref (pathname)
  (when (and pathname (probe-file pathname))
    (string-trim '(#\Space #\Tab #\Newline #\Return)
                 (uiop:read-file-string pathname))))

(defun write-laboratory-ref (laboratory relative root)
  (let ((pathname (laboratory-ref-path laboratory relative)))
    (when pathname
      (ensure-directories-exist pathname)
      (let ((temporary
              (make-pathname :name (format nil ".~A-~D.tmp"
                                           (pathname-name pathname)
                                           (get-internal-real-time))
                             :type (pathname-type pathname)
                             :defaults pathname)))
        (with-open-file (stream temporary :direction :output
                               :if-exists :supersede :if-does-not-exist :create)
          (write-line root stream))
        (uiop:rename-file-overwriting-target temporary pathname))))
  root)

(defun make-laboratory (&key directory current-root champion-root)
  (let* ((directory (and directory (uiop:ensure-directory-pathname directory)))
         (laboratory
           (%make-laboratory
            :directory directory
            :current-root (or current-root
                              (read-laboratory-ref
                               (and directory (merge-pathnames "refs/organism/current" directory))))
            :champion-root (or champion-root
                               (read-laboratory-ref
                                (and directory (merge-pathnames "refs/lab/champion" directory)))))))
    (when current-root (write-laboratory-ref laboratory "refs/organism/current" current-root))
    (when champion-root (write-laboratory-ref laboratory "refs/lab/champion" champion-root))
    laboratory))

(defun laboratory-set-current (laboratory root)
  (setf (laboratory-current-root laboratory) root)
  (write-laboratory-ref laboratory "refs/organism/current" root))

(defun laboratory-set-champion (laboratory root)
  (setf (laboratory-champion-root laboratory) root)
  (write-laboratory-ref laboratory "refs/lab/champion" root))

(defun laboratory-seal (laboratory descriptor hidden-object)
  "Seal HIDDEN-OBJECT behind the canonical root of public DESCRIPTOR."
  (let ((root (term-hash descriptor)))
    (setf (gethash root (laboratory-hidden laboratory)) hidden-object)
    root))

(defun laboratory-hidden-object (laboratory root)
  (multiple-value-bind (object present) (gethash root (laboratory-hidden laboratory))
    (unless present (error "Unknown sealed laboratory root ~A" root))
    object))

(defun make-challenge-term (&key id objective public-examples public-checks
                              capabilities budgets hidden-generator hidden-seeds
                              promotion-gates)
  (sexp->term
   `(challenge
     (id ,id)
     (objective ,objective)
     (public-examples ,(term->sexp public-examples))
     (public-checks ,(term->sexp public-checks))
     (capabilities ,capabilities)
     (budgets ,budgets)
     (hidden-generator ,hidden-generator)
     (hidden-seeds ,hidden-seeds)
     (promotion-gates ,promotion-gates))))

(defun make-gate-attestation (&key candidate-root lineage-root hidden-seed-root
                                invalid-promotions replay-match lineage-intact
                                inherited-regressions-pass challenge-threshold-pass
                                resource-budget-pass cost latency detail)
  (sexp->term
   `(attestation
     (candidate ,candidate-root)
     (lineage ,lineage-root)
     (hidden-seed ,hidden-seed-root)
     (invalid-promotions ,invalid-promotions)
     (replay-match ,replay-match)
     (lineage-intact ,lineage-intact)
     (inherited-regressions-pass ,inherited-regressions-pass)
     (challenge-threshold-pass ,challenge-threshold-pass)
     (resource-budget-pass ,resource-budget-pass)
     (cost ,cost)
     (latency ,latency)
     (detail ,(term->sexp detail)))))

(defun attestation-boolean (attestation field)
  (cell-zero::term-truth-p (cell-zero::required-field attestation field)))

(defun attestation-passes-p (attestation)
  "Apply hard gates lexicographically. Cost and latency are never correctness gates."
  (and (zerop (cell-zero::integer-term-value/protocol
               (cell-zero::required-field attestation "invalid-promotions")))
       (attestation-boolean attestation "replay-match")
       (attestation-boolean attestation "lineage-intact")
       (attestation-boolean attestation "inherited-regressions-pass")
       (attestation-boolean attestation "challenge-threshold-pass")
       (attestation-boolean attestation "resource-budget-pass")))

(defun record-lineage-attestation (laboratory attestation)
  (push attestation (laboratory-attestations laboratory))
  (when (attestation-passes-p attestation)
    (laboratory-set-champion
     laboratory
     (cell-zero::string-term-value
      (cell-zero::required-field attestation "candidate"))))
  attestation)

(defun stage-passes-p (laboratory &key (required-lineages 3))
  (let ((lineages (make-hash-table :test #'equal))
        (seeds (make-hash-table :test #'equal)))
    (dolist (attestation (laboratory-attestations laboratory))
      (when (attestation-passes-p attestation)
        (setf (gethash (cell-zero::string-term-value
                        (cell-zero::required-field attestation "lineage")) lineages) t
              (gethash (cell-zero::string-term-value
                        (cell-zero::required-field attestation "hidden-seed")) seeds) t)))
    (and (>= (hash-table-count lineages) required-lineages)
         (>= (hash-table-count seeds) required-lineages))))
