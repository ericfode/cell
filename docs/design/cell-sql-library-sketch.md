# Cell as a SQL Library on Dolt (Retort)

**Date**: 2026-03-13
**Status**: Sketch
**Premise**: The intermediate language for Cell is not a new language — it's a SQL
schema + views on Dolt. A `.cell` file compiles to SQL. Execution is queries.
The Cell execution database is called **Retort** — a distillation vessel where
soft cells go in and crystallized outputs come out. Retort is separate from Beads
(the issue tracker / coordination substrate). Reifying cells into beads is one
execution path, but not the only one — the computation lives in Retort.

---

## The Insight

Beads already stores work as rows in Dolt. Cell programs already transform to beads.
The "intermediate representation" is just **structured SQL operations against tables
that model computation graphs**. No new language needed. The schema IS the language.

Cell's execution semantics map directly to SQL:

| Cell concept | SQL operation |
|-------------|---------------|
| Declare a cell | `INSERT INTO cells` |
| Declare a dependency | `INSERT INTO givens` |
| Declare a yield | `INSERT INTO yields` |
| Find ready cells | `SELECT FROM ready_cells` (view, already exists as recursive CTE) |
| Evaluate hard cell | `SELECT eval_expr(...)` |
| Freeze output | `UPDATE yields SET value = ..., frozen = 1` |
| Spawn new cell | `INSERT INTO cells` (same as declare — spawning IS declaring) |
| Quotation `§` | `SELECT * FROM cells WHERE name = ?` |
| Bottom `⊥` | `UPDATE yields SET value = NULL, frozen = 1, is_bottom = 1` |
| Oracle check | `INSERT INTO oracles` + evaluate |
| Guard check | `SELECT eval_guard(cell_id)` |

---

## Schema Extension

This extends the existing beads schema. Cell-specific tables overlay on the
existing `issues` + `dependencies` infrastructure. Two approaches:

### Option A: Separate cell tables (cleaner, but parallel to beads)

```sql
-- A cell program is a named graph
CREATE TABLE IF NOT EXISTS programs (
    id VARCHAR(255) PRIMARY KEY,
    name VARCHAR(255) NOT NULL,
    created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP
);

-- Each cell in the program
CREATE TABLE IF NOT EXISTS cells (
    id VARCHAR(255) PRIMARY KEY,
    program_id VARCHAR(255) NOT NULL,
    name VARCHAR(255) NOT NULL,
    body_type ENUM('soft', 'hard', 'spawner', 'evolution') NOT NULL,
    body TEXT NOT NULL,                -- ∴ prompt text or ⊢= expression
    status ENUM('pending', 'ready', 'computing', 'frozen', 'bottom') DEFAULT 'pending',
    UNIQUE KEY (program_id, name),
    FOREIGN KEY (program_id) REFERENCES programs(id)
);

-- Given declarations (input dependencies)
CREATE TABLE IF NOT EXISTS givens (
    cell_id VARCHAR(255) NOT NULL,
    source_cell VARCHAR(255) NOT NULL,  -- which cell provides the value
    source_field VARCHAR(255) NOT NULL, -- which yield field
    is_optional TINYINT(1) DEFAULT 0,   -- given? (tolerates ⊥)
    guard_expr TEXT DEFAULT '',          -- where clause expression
    FOREIGN KEY (cell_id) REFERENCES cells(id)
);

-- Yield declarations (output slots)
CREATE TABLE IF NOT EXISTS yields (
    cell_id VARCHAR(255) NOT NULL,
    field VARCHAR(255) NOT NULL,
    value TEXT,                          -- NULL until frozen
    frozen TINYINT(1) DEFAULT 0,
    is_bottom TINYINT(1) DEFAULT 0,     -- ⊥
    default_value TEXT,                  -- ≡ default
    PRIMARY KEY (cell_id, field),
    FOREIGN KEY (cell_id) REFERENCES cells(id)
);

-- Oracle assertions
CREATE TABLE IF NOT EXISTS oracles (
    id VARCHAR(255) PRIMARY KEY,
    cell_id VARCHAR(255) NOT NULL,
    assertion TEXT NOT NULL,             -- the ⊨ text
    oracle_type ENUM('deterministic', 'structural', 'semantic') DEFAULT 'semantic',
    status ENUM('pending', 'passed', 'failed') DEFAULT 'pending',
    FOREIGN KEY (cell_id) REFERENCES cells(id)
);

-- Recovery policies
CREATE TABLE IF NOT EXISTS recovery (
    cell_id VARCHAR(255) NOT NULL,
    max_retries INT DEFAULT 3,
    on_exhaustion ENUM('escalate', 'bottom', 'partial_accept') DEFAULT 'escalate',
    partial_predicate TEXT DEFAULT '',   -- for partial_accept
    current_attempt INT DEFAULT 0,
    FOREIGN KEY (cell_id) REFERENCES cells(id)
);
```

### Option B: Use existing beads tables with cell metadata (unified)

Every cell IS a bead. Cell-specific data lives in the `metadata` JSON column.

```sql
-- A cell is an issue with label 'cell'
INSERT INTO issues (id, title, description, status, metadata)
VALUES (
    'ce-sort',
    'sort',
    'Sort «items» in ascending order.',
    'open',
    JSON_OBJECT(
        'cell_program', 'sort-proof',
        'body_type', 'soft',
        'yield_names', JSON_ARRAY('sorted'),
        'yield_sorted', NULL,
        'yield_sorted_frozen', false
    )
);
INSERT INTO labels (issue_id, label) VALUES ('ce-sort', 'cell');
INSERT INTO labels (issue_id, label) VALUES ('ce-sort', 'soft');

-- Dependencies are beads dependencies
INSERT INTO dependencies (issue_id, depends_on_id, type, created_by, metadata)
VALUES (
    'ce-sort',
    'ce-data',
    'blocks',
    'cell-loader',
    JSON_OBJECT('source_field', 'items', 'is_optional', false, 'guard_expr', '')
);
```

~~**Option B is the recommendation.**~~ **Superseded**: Retort gets its own Dolt
database, separate from Beads. Reifying cells into beads is one execution path
(e.g., when dispatching soft cells to polecats), but the core computation lives
in Retort's own tables. Beads is for coordination; Retort is for computation.

**Option A (separate tables in a dedicated Retort database) is the recommendation.**

---

## The Ready View (already works)

The existing `ready_issues` recursive CTE computes cell readiness:

```sql
-- Find ready cells in program 'sort-proof'
SELECT i.id, i.title, i.description,
       JSON_EXTRACT(i.metadata, '$.body_type') as body_type,
       JSON_EXTRACT(i.metadata, '$.yield_names') as yield_names
FROM ready_issues i
JOIN labels l ON l.issue_id = i.id
WHERE l.label = 'cell'
  AND JSON_EXTRACT(i.metadata, '$.cell_program') = 'sort-proof';
```

No new readiness logic needed. `bd ready --label=cell` already does this.

---

## cell-to-sql: The Compiler

A `.cell` file compiles to a `.sql` file. The SQL file is the IR.

**Input** (`sort-proof.cell`):
```
⊢ data
  yield items ≡ [4, 1, 7, 3, 9, 2]

⊢ sort
  given data→items
  yield sorted
  ∴ Sort «items» in ascending order.
  ⊨ sorted is a permutation of «data→items»
  ⊨ sorted is in ascending order
```

**Output** (`sort-proof.sql`):
```sql
-- Cell program: sort-proof
-- Generated from sort-proof.cell

-- Cell: data (hard, pre-bound)
INSERT INTO issues (id, title, description, status, metadata)
VALUES (
    'ce-sp-data',
    'data',
    '',
    'open',
    '{"cell_program":"sort-proof","body_type":"hard","yield_names":["items"]}'
);
INSERT INTO labels (issue_id, label) VALUES ('ce-sp-data', 'cell');
INSERT INTO labels (issue_id, label) VALUES ('ce-sp-data', 'hard');

-- Yield: data.items (pre-bound default)
-- Since items has a default value, freeze it immediately
UPDATE issues SET
    metadata = JSON_SET(metadata,
        '$.yield_items', '[4, 1, 7, 3, 9, 2]',
        '$.yield_items_frozen', true),
    status = 'closed'
WHERE id = 'ce-sp-data';

-- Cell: sort (soft)
INSERT INTO issues (id, title, description, status, metadata)
VALUES (
    'ce-sp-sort',
    'sort',
    'Sort «items» in ascending order.',
    'open',
    '{"cell_program":"sort-proof","body_type":"soft","yield_names":["sorted"]}'
);
INSERT INTO labels (issue_id, label) VALUES ('ce-sp-sort', 'cell');
INSERT INTO labels (issue_id, label) VALUES ('ce-sp-sort', 'soft');

-- Dependency: sort depends on data (field: items)
INSERT INTO dependencies (issue_id, depends_on_id, type, created_by, metadata)
VALUES (
    'ce-sp-sort',
    'ce-sp-data',
    'blocks',
    'cell-to-sql',
    '{"source_field":"items","is_optional":false}'
);

-- Oracles for sort
INSERT INTO issues (id, title, description, status, metadata)
VALUES (
    'ce-sp-sort-o1',
    'oracle: sort / permutation check',
    'sorted is a permutation of «data→items»',
    'open',
    '{"oracle_for":"ce-sp-sort","oracle_type":"structural"}'
);
INSERT INTO labels (issue_id, label) VALUES ('ce-sp-sort-o1', 'oracle');
INSERT INTO dependencies (issue_id, depends_on_id, type, created_by)
VALUES ('ce-sp-sort-o1', 'ce-sp-sort', 'parent-child', 'cell-to-sql');

INSERT INTO issues (id, title, description, status, metadata)
VALUES (
    'ce-sp-sort-o2',
    'oracle: sort / order check',
    'sorted is in ascending order',
    'open',
    '{"oracle_for":"ce-sp-sort","oracle_type":"structural"}'
);
INSERT INTO labels (issue_id, label) VALUES ('ce-sp-sort-o2', 'oracle');
INSERT INTO dependencies (issue_id, depends_on_id, type, created_by)
VALUES ('ce-sp-sort-o2', 'ce-sp-sort', 'parent-child', 'cell-to-sql');
```

**Key property:** The `.sql` file is deterministic, unambiguous, and directly
executable on Dolt via `dolt sql < sort-proof.sql`. No new parser needed for the IR.

---

## Execution: beads-eval-loop as SQL

The eval loop becomes a tight cycle of SQL queries:

```sql
-- Step 1: Find next ready cell
SELECT i.id, i.title, i.description,
       JSON_EXTRACT(i.metadata, '$.body_type') as body_type
FROM ready_issues i
JOIN labels l ON l.issue_id = i.id
WHERE l.label = 'cell'
  AND JSON_EXTRACT(i.metadata, '$.cell_program') = ?
LIMIT 1;

-- Step 2: Resolve inputs (read upstream frozen yields)
SELECT dep.depends_on_id as source_id,
       JSON_EXTRACT(dep.metadata, '$.source_field') as field,
       JSON_EXTRACT(src.metadata, CONCAT('$.yield_', JSON_EXTRACT(dep.metadata, '$.source_field'))) as value
FROM dependencies dep
JOIN issues src ON src.id = dep.depends_on_id
WHERE dep.issue_id = ?
  AND dep.type = 'blocks';

-- Step 3: After evaluation, freeze yields
UPDATE issues SET
    metadata = JSON_SET(metadata,
        '$.yield_sorted', ?,
        '$.yield_sorted_frozen', true),
    status = 'closed',
    closed_at = NOW()
WHERE id = ?;

-- Step 4: Check oracles (find child oracle beads)
SELECT id, description
FROM issues
WHERE JSON_EXTRACT(metadata, '$.oracle_for') = ?;
```

---

## Metacircularity: Programs as Queries

**Quotation (`§`)** is a SELECT:
```sql
-- §sort = read sort's full definition as data
SELECT i.title as name,
       i.description as body,
       JSON_EXTRACT(i.metadata, '$.body_type') as body_type,
       JSON_EXTRACT(i.metadata, '$.yield_names') as yields
FROM issues i
WHERE i.id = 'ce-sp-sort';
```

**Spawning (`⊢⊢`)** is an INSERT:
```sql
-- A spawner cell's output IS new INSERT statements
-- The LLM evaluating the spawner produces SQL that creates new cells
INSERT INTO issues (id, title, description, status, metadata)
VALUES ('ce-sp-task-0', 'task-0', 'Do subtask 0', 'open',
        '{"cell_program":"sort-proof","body_type":"soft","yield_names":["result"],"spawned_by":"ce-sp-spawn"}');
```

**A Cell program that generates another Cell program** is a query that produces
INSERT statements. The homoiconicity is: **programs are rows, and rows are programs.**

---

## What This Gives Us

1. **Deterministic parsing**: SQL is the most battle-tested parseable language on earth
2. **LLM fluency**: LLMs write SQL at ~8/10; they write INSERT statements trivially
3. **Immutability via Dolt commits**: Each eval-one step = one Dolt commit
4. **Content addressing**: Dolt's content-addressed storage = Cell's hash transitions
5. **Readiness via recursive CTE**: Same pattern as beads, in Retort's own schema
6. **Audit trail**: Dolt diff between commits = execution trace
7. **Distribution**: Multiple agents can query `ready_cells` concurrently
8. **Separation of concerns**: Retort = computation; Beads = coordination/dispatch

## Retort ↔ Beads Bridge

Retort and Beads are separate databases. The bridge between them:

- **Dispatch**: When Retort's eval-loop encounters a soft cell, it CAN create a
  bead in the Beads DB to dispatch work to a polecat. But it can also dispatch
  directly (e.g., inline LLM call). Beads dispatch is one option, not the only one.
- **Results**: When a bead closes, the bridge writes the result back to Retort
  (freezes the yield in the Retort DB).
- **Observation**: Beads can observe Retort state (e.g., "what cells are frozen?")
  without owning it.

## What We Still Need

1. **A surface syntax parser** — something that compiles `.cell` → `.sql`.
   This can be simple because the target (SQL INSERTs) is trivial to generate.
   The hard part was always "what does the program MEAN?" — now the Retort schema
   answers that definitively.

2. **Guard expression evaluator** — evaluate `where` clauses against frozen yields.
   Could be a simple expression evaluator in Go, or even a SQL expression
   (Dolt supports computed columns).

3. **Hard cell evaluator** — evaluate `⊢=` expressions. Same expression language
   as guards. Could be a stored procedure or a Go function.

4. **Soft cell dispatcher** — compose prompts from cell description + resolved
   inputs, send to LLM. Can dispatch inline or via beads bridge to polecats.

5. **Oracle checker** — evaluate oracle assertions against frozen yields.
   Deterministic oracles: expression evaluator. Semantic oracles: LLM dispatch.

6. **Retort CLI** — `rt` or similar, analogous to `bd` but for the Retort DB.
   `rt load program.cell`, `rt ready`, `rt eval-one`, `rt status`, `rt yields`.

---

## The Compiler Stack

```
.cell file (human/LLM authoring syntax — turnstile, markdown, or whatever wins)
    │
    ▼
cell-to-sql (surface parser — only job is to emit valid SQL)
    │
    ▼
.sql file (deterministic IR — INSERT/UPDATE statements)
    │
    ▼
dolt sql < program.sql (load into Dolt)
    │
    ▼
beads-eval-loop (SELECT ready → dispatch → UPDATE yields → COMMIT)
    │
    ▼
Dolt commits (immutable execution trace, content-addressed)
```

The surface syntax debate becomes a FRONTEND concern. The IR is settled: it's SQL
against the Retort schema. Multiple frontends can target it. The pretend test
applies to the surface syntax; the deterministic transformation guarantee applies
to the IR.

Sugar goes on top. Retort is the substance underneath.
