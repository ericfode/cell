# genome/v1

`genome/v1` is the Stage 0 hereditary format. A genome is an ordinary Common Lisp source bundle plus fixed entry points and canonical data. Subzero treats controller source as opaque text, verifies its manifest, and invokes it through a mechanical loader.

## Bundle

```lisp
(genome
  (abi genome/v1)
  (language common-lisp)
  (sources
    ((source
       (path "stage0.lisp")
       (sha256 "<SHA-256 of the UTF-8 source text>")
       (text "..."))))
  (entry-points
    (entry-points
      (react
        (entry-point
          (package "CELL-ZERO.STAGE0.GENOME")
          (function "REACT")))
      (admit
        (entry-point
          (package "CELL-ZERO.STAGE0.GENOME")
          (function "ADMIT")))))
  (data <canonical term>))
```

Source paths are relative `.lisp` paths without empty, `.` or `..` components. Paths are unique within a bundle. Each `sha256` binds the exact UTF-8 source string.

`react` has the ordinary Common Lisp signature:

```lisp
(react state event data world) => reaction-term
```

`admit` has the signature:

```lisp
(admit candidate evidence data) => admission-term
```

The returned reaction and admission terms are validated by Subzero. Effects, request hashes, trial evidence, lineage entries, and state roots remain canonical content-addressed terms.

## Mechanical loader

For each load or invocation, Subzero:

1. validates the bundle and source hashes;
2. materializes the sources in a fresh temporary directory;
3. starts a disposable Common Lisp process;
4. compiles and loads the files in manifest order;
5. resolves the declared package and function names;
6. exchanges canonical invocation and result files;
7. removes the temporary build directory.

The candidate package is never loaded into the parent Lisp image. `CELL_ZERO_LISP` may select the runner executable; it defaults to `sbcl`.

A load check compiles all sources and resolves both entry points without calling either function. Parent trials require this check before executing probes.

## World and promotion

A running world remains:

```lisp
(world
  (genome <genome/v1 bundle>)
  (state <canonical term>))
```

A candidate must use the same supported genome ABI as its parent. The parent creates the trial envelope, grants only intersected capabilities, verifies replay, constructs evidence, runs its own `admit` entry point, and installs the candidate only after `accept`.

The legacy `cell-zero/1` interpreted-program world remains supported. The homoiconic Cell-zero/2 capsule API remains a separate optional experiment.
