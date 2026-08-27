;;;; lab/package.lisp

(defpackage #:cell-zero-lab
  (:use #:cl)
  (:import-from #:cell-zero
                #:sexp->term #:term->sexp #:term-hash #:term-equal #:term-list
                #:make-string-atom #:make-integer-atom #:make-symbol-atom
                #:make-term-store #:make-genesis-world #:make-subzero
                #:register-capability-handler #:make-scripted-model-handler
                #:submit-event #:run-until-idle #:replay-from-roots
                #:subzero-current-root #:subzero-initial-root #:subzero-log-root
                #:subzero-outputs #:subzero-handler-calls)
  (:export #:make-laboratory #:laboratory-current-root #:laboratory-champion-root
           #:laboratory-set-current #:laboratory-seal #:laboratory-hidden-object
           #:make-challenge-term #:make-gate-attestation #:attestation-passes-p
           #:record-lineage-attestation #:stage-passes-p
           #:run-c0-distribution #:write-c0-report))

(in-package #:cell-zero-lab)
