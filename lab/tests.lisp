;;;; lab/tests.lisp

(defpackage #:cell-zero-lab-tests
  (:use #:cl #:cell-zero-lab)
  (:import-from #:cell-zero #:sexp->term #:term-hash #:term->sexp #:make-string-atom))

(in-package #:cell-zero-lab-tests)

(defun check (condition control &rest arguments)
  (unless condition (error (apply #'format nil control arguments)))
  t)

(defun attestation (lineage seed &key (invalid 0) (threshold t))
  (make-gate-attestation
   :candidate-root (format nil "candidate-~A" lineage)
   :lineage-root lineage
   :hidden-seed-root seed
   :invalid-promotions invalid
   :replay-match t :lineage-intact t :inherited-regressions-pass t
   :challenge-threshold-pass threshold :resource-budget-pass t
   :cost 1 :latency 1 :detail (sexp->term '(detail))))

(defun run-tests ()
  (let* ((lab (make-laboratory))
         (descriptor (sexp->term '(sealed-generator (challenge c0) (version 1))))
         (root (laboratory-seal lab descriptor #'identity)))
    (check (string= root (term-hash descriptor)) "sealed root mismatch")
    (check (functionp (laboratory-hidden-object lab root)) "hidden object unavailable")
    (check (attestation-passes-p (attestation "a" "s1")) "valid gates rejected")
    (check (not (attestation-passes-p (attestation "bad" "s2" :invalid 1)))
           "invalid promotion passed")
    (record-lineage-attestation lab (attestation "a" "s1"))
    (record-lineage-attestation lab (attestation "b" "s2"))
    (check (not (stage-passes-p lab)) "stage passed before three lineages")
    (record-lineage-attestation lab (attestation "c" "s3"))
    (check (stage-passes-p lab) "stage did not pass three lineages")
    (check (cell-zero-lab::c0-counts-passed-p
            (run-c0-distribution :seed 77 :cases 25))
           "small C0 distribution failed"))
  (format t "Cell-zero lab: protocol and C0 smoke checks passed.~%")
  t)
