;;;; scripts/render-c0-challenge.lisp
(require :asdf)
(asdf:load-asd (truename "cell-zero.asd"))
(asdf:load-asd (truename "cell-zero-lab.asd"))
(asdf:load-system "cell-zero-lab")
(let* ((lab (cell-zero-lab:make-laboratory))
       (generator-descriptor
         (cell-zero:sexp->term
          '(sealed-generator (challenge c0) (version 1)
            (distribution generated-event-histories))))
       (seed-descriptor
         (cell-zero:sexp->term
          '(sealed-seeds (challenge c0) (lineages 3) (cases-per-lineage 10000))))
       (generator-root (cell-zero-lab:laboratory-seal lab generator-descriptor
                                                       #'cell-zero-lab:run-c0-distribution))
       (seed-root (cell-zero-lab:laboratory-seal lab seed-descriptor :laboratory-private))
       (challenge
         (cell-zero-lab:make-challenge-term
          :id 'c0
          :objective "Process event histories identically live and by replay without unrecorded replay effects."
          :public-examples (cell-zero:sexp->term '(examples (normal) (interrupted) (malformed)))
          :public-checks (cell-zero:sexp->term
                          '(checks replay-root outputs handler-calls committed-log))
          :capabilities '(model store)
          :budgets '((histories 10000) (lineages 3) (max-events 24))
          :hidden-generator generator-root
          :hidden-seeds seed-root
          :promotion-gates '(replay-match lineage-intact inherited-regressions-pass
                             challenge-threshold-pass resource-budget-pass))))
  (with-open-file (stream "evidence/ecology/c0-challenge.sexp"
                          :direction :output :if-exists :supersede
                          :if-does-not-exist :create)
    (cell-zero:write-term challenge stream)
    (terpri stream))
  (format t "generator=~A~%seeds=~A~%challenge=~A~%"
          generator-root seed-root (cell-zero:term-hash challenge)))
