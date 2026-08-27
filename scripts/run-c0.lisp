;;;; scripts/run-c0.lisp
(require :asdf)
(asdf:load-asd (truename "cell-zero.asd"))
(asdf:load-asd (truename "cell-zero-lab.asd"))
(asdf:load-system "cell-zero-lab")
(destructuring-bind (seed-text cases-text output &optional lineage-root) (uiop:command-line-arguments)
  (let* ((seed (parse-integer seed-text))
         (cases (parse-integer cases-text))
         (counts (cell-zero-lab:run-c0-distribution :seed seed :cases cases)))
    (with-open-file (stream output :direction :output :if-exists :supersede
                                   :if-does-not-exist :create)
      (cell-zero-lab:write-c0-report counts stream :seed seed
                                     :lineage-root (or lineage-root "lineage-unlabeled")))
    (cell-zero-lab:write-c0-report counts *standard-output* :seed seed
                                   :lineage-root (or lineage-root "lineage-unlabeled"))))
