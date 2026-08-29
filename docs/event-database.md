# Lisp-native temporal event database

Cell Zero includes an immutable temporal event database built directly on the canonical term store. It adds no external database process or file format.

## Storage model

Each transaction is a canonical `event-db-transaction` term containing:

- a monotonic sequence
- the previous transaction root
- an optional idempotency source
- immutable EAV datoms with transaction and operation fields

A datom is `(entity attribute value transaction operation)`. Operations are `assert` and `retract`. Transaction roots form a SHA-256 hash chain. A named database stores a small canonical manifest under `refs/event-db/NAME.ref`; reopening validates the manifest, sequence, transaction roots, predecessor links, and datoms.

```lisp
(let* ((store (cell-zero:make-term-store :directory #P"/var/lib/cell-zero/"))
       (db (cell-zero:make-event-database store :name "requests")))
  (cell-zero:event-db-transact
   db
   '(("call/1" :model/status :pending)
     ("call/1" :model/prompt "Write the patch."))))
```

Named databases persist after every transaction. Reopen them against a fresh store instance:

```lisp
(let* ((store (cell-zero:make-term-store :directory #P"/var/lib/cell-zero/"))
       (db (cell-zero:reopen-event-database store "requests")))
  (cell-zero:event-db-transaction-count db))
```

The optional transaction `:source` makes projections idempotent. Reusing a source returns its existing transaction without appending duplicate facts.

## Queries and history

`event-db-query` accepts Datalog-style EAV clauses. Symbols beginning with `?` are join variables and `_` is a wildcard.

```lisp
(cell-zero:event-db-query
 db
 '((?call :db/type :model-call)
   (?call :model/request-hash ?request-hash)
   (?call :model/prompt ?prompt)
   (?call :model/status ?status))
 :find '(?call ?request-hash ?prompt ?status))
```

Atomic term values are returned as ordinary Lisp strings, integers, byte vectors, or canonical symbol names. Structured values remain immutable terms. Pass `:raw t` to retain atom terms too.

The default query view applies retractions and returns current facts. Historical views can use a transaction sequence, transaction root, or transaction term:

```lisp
(let ((old-db (cell-zero:event-db-as-of db transaction-root)))
  (cell-zero:event-db-query old-db '((?call :model/status ?status))
                            :find '(?call ?status)))
```

Pass `:history t` and use five-position clauses to inspect transaction and operation values:

```lisp
(cell-zero:event-db-query
 db
 '((?entity :model/status ?status ?tx ?operation))
 :find '(?entity ?status ?tx ?operation)
 :history t)
```

## Live queries and tails

Query subscriptions run after each committed transaction:

```lisp
(cell-zero:event-db-subscribe
 db
 '((?call :db/type :model-call)
   (?call :model/status ?status))
 (lambda (rows transaction database)
   (declare (ignore database))
   (format t "~&tx ~A: ~S~%"
           (and transaction
                (cell-zero:event-db-transaction-sequence transaction))
           rows))
 :find '(?call ?status))
```

`event-db-tail` first delivers transactions at or after `:from`, then delivers new transactions. Both APIs return a subscription accepted by `event-db-unsubscribe`.

## Subzero projection

Attach a database when constructing Subzero:

```lisp
(let* ((store (cell-zero:make-term-store :directory #P"/var/lib/cell-zero/"))
       (db (cell-zero:make-event-database store :name "requests"))
       (cell (cell-zero:make-subzero
              store (cell-zero:make-genesis-world)
              :name "organism"
              :event-database db)))
  cell)
```

Every authoritative Subzero log entry then produces one idempotent projection transaction. Projection includes:

- Subzero run, entry sequence, predecessor, type, payload root, and payload
- effect IDs, capabilities, context worlds, request roots, results, statuses, and resource usage
- `model/v1` request hashes, exact `render-model-prompt` text, result text, finish reason, and failures
- nested trial runs linked through `:trial/run`, `:run/parent`, and `:trial/event-log`

A model request can be inspected directly:

```lisp
(cell-zero:event-db-query
 db
 '((?call :db/type :model-call)
   (?call :model/request-hash ?hash)
   (?call :model/prompt ?prompt)
   (?call :model/status ?status)
   (?call :model/result-text ?result))
 :find '(?hash ?prompt ?status ?result))
```

Existing logs can be imported without replaying providers:

```lisp
(cell-zero:event-db-project-log-root db subzero-log-root)
```

`reopen-subzero` accepts `:event-database`; it validates deterministic replay, attaches the database, and idempotently projects the stored log before live execution resumes.

## Replay authority and telemetry

Subzero's hash-chained event log remains the replay authority. The event database is a derived query projection and never replaces replay verification.

Provider token counts are stored on a separate `:provider-telemetry` entity linked by `:model/provider-telemetry`. Those entities carry `:projection/only true` and `:telemetry/source provider-response`. Prompt, request, response, and status facts point back to authoritative canonical Subzero payloads.
