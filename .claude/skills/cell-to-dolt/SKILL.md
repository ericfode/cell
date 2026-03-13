---
name: cell-to-dolt
description: Translate Cell language (turnstile syntax) into Dolt SQL queries against the Retort schema. Use when the user provides .cell source or turnstile notation and wants to see the equivalent SQL INSERTs, or when loading cell programs into the Retort database.
argument-hint: <file.cell or inline cell definition>
---

# Cell-to-Dolt: Turnstile Syntax to Retort SQL

Translate Cell language definitions into SQL statements for the Retort Dolt database.

## Your task

Given `$ARGUMENTS` (a .cell file path or inline Cell syntax), parse it and produce the equivalent SQL INSERTs for the Retort schema.

## Cell Turnstile Syntax Reference

Cell uses Unicode operators for a concise declarative language:

### Cell declaration
```
⊢ cell-name
```
Declares a cell. Everything indented below belongs to it.

### Givens (inputs/dependencies)
```
  given source-cell→field        # depends on upstream cell's yield
  given source-cell→field as alias  # with local alias
  given? source-cell→field       # optional dependency
  given param = "default"        # parameter with default
  given source-cell→field where expr  # guarded dependency
```

### Yields (outputs)
```
  yield field-name               # computed output slot
  yield field-name ≡ "value"     # data yield (constant/default value)
  yield field-name ≡ 42          # numeric default
  yield field-name ≡ [1, 2, 3]   # list default
```

### Body types
```
  ⊢= expression                 # hard cell (deterministic, ⊢= expression language)
  ∴ prompt text with «ref»       # soft cell (LLM dispatch, «guillemets» for interpolation)
```
If no body is specified and all yields have defaults (`≡`), it's a **passthrough** (data) cell.

### Oracles (assertions)
```
  ⊨ field = expected_value       # deterministic oracle
  ⊨ field is a string            # structural/semantic oracle
  ⊨ all(i, sorted[i] <= sorted[i+1])  # expression oracle
```

### Recovery
```
  ⟳ 5                           # max retries
  ⟳ bottom                      # on exhaustion: mark as bottom
  ⟳ escalate                    # on exhaustion: escalate
```

### Comments
```
-- This is a comment
```

## Retort Schema (target tables)

### programs
```sql
INSERT INTO programs (id, name, source_file, source_hash, status)
VALUES ('<id>', '<name>', '<file>', '<hash>', 'ready');
```

### cells
```sql
INSERT INTO cells (id, program_id, name, qualified_name, body_type, body, max_retries)
VALUES ('<id>', '<prog_id>', '<name>', '<prog_id>.<name>',
        'soft|hard|passthrough', '<body_text>', 3);
```
- `body_type`: 'hard' if has `⊢=`, 'soft' if has `∴`, 'passthrough' if only default yields

### givens
```sql
INSERT INTO givens (id, cell_id, param_name, source_cell, source_field,
                    is_optional, is_quotation, default_value, has_default, guard_expr)
VALUES ('<id>', '<cell_id>', '<param_name>', '<source_cell>', '<source_field>',
        0|1, 0|1, '<default>', 0|1, '<guard_expr>');
```

### yields
```sql
INSERT INTO yields (cell_id, field_name, default_value)
VALUES ('<cell_id>', '<field_name>', '<default_or_null>');
```
- For `yield X ≡ "val"`: default_value = `"val"`
- For `yield X` (no default): default_value = NULL

### oracles
```sql
INSERT INTO oracles (id, cell_id, oracle_type, assertion, ordinal)
VALUES ('<id>', '<cell_id>', 'deterministic|structural|semantic', '<assertion>', <n>);
```
Oracle type classification:
- **deterministic**: Contains `=`, `!=`, `<`, `>`, `<=`, `>=`, or pure expression ops
- **structural**: Contains "is a string", "is a number", "is a list", "is not empty"
- **semantic**: Everything else (natural language assertions evaluated by LLM)

### recovery_policies
```sql
INSERT INTO recovery_policies (id, cell_id, max_retries, exhaustion_action)
VALUES ('<id>', '<cell_id>', <n>, 'bottom|escalate|partial_accept');
```

## Translation workflow

1. **Read** the Cell source (file or inline)
2. **Parse** each `⊢ cell-name` block
3. **Classify** body type (hard/soft/passthrough)
4. **Generate IDs** (use 16-char hex random IDs)
5. **Emit SQL** in dependency order:
   - Program INSERT first
   - Cells in declaration order
   - Givens, yields, oracles for each cell
   - Recovery policies
6. **Include** the ready_cells view creation
7. **Wrap** in a transaction with DOLT_COMMIT

## Output format

Produce clean SQL that can be piped directly to `dolt sql`:

```sql
-- Generated from: <source>
-- Retort Cell-to-Dolt translation

USE retort;

-- Program
INSERT INTO programs ...

-- Cell: <name>
INSERT INTO cells ...
INSERT INTO givens ...
INSERT INTO yields ...
INSERT INTO oracles ...

-- ... more cells ...

-- Commit
CALL DOLT_ADD('-A');
CALL DOLT_COMMIT('-m', 'load: <program-name>');
```

## OR: Direct loading

If the user wants to load directly (not just see SQL), use the `rt` CLI:

```bash
export RETORT_DSN="root@tcp(127.0.0.1:3308)/"
./rt load <file.cell>
```

## Example

Input:
```
⊢ add
  given a = 3
  given b = 5
  yield sum
  ⊢= a + b
  ⊨ sum = 8
```

Output:
```sql
USE retort;

INSERT INTO programs (id, name, source_file, source_hash, status)
VALUES ('a1b2c3d4e5f6a7b8', 'add-example', NULL, NULL, 'ready');

INSERT INTO cells (id, program_id, name, qualified_name, body_type, body, max_retries)
VALUES ('f1e2d3c4b5a6f7e8', 'a1b2c3d4e5f6a7b8', 'add',
        'a1b2c3d4e5f6a7b8.add', 'hard', 'a + b', 3);

INSERT INTO givens (id, cell_id, param_name, source_cell, source_field,
                    is_optional, is_quotation, default_value, has_default, guard_expr)
VALUES ('0102030405060708', 'f1e2d3c4b5a6f7e8', 'a', NULL, NULL, 0, 0, '3', 1, NULL);

INSERT INTO givens (id, cell_id, param_name, source_cell, source_field,
                    is_optional, is_quotation, default_value, has_default, guard_expr)
VALUES ('0908070605040302', 'f1e2d3c4b5a6f7e8', 'b', NULL, NULL, 0, 0, '5', 1, NULL);

INSERT INTO yields (cell_id, field_name, default_value)
VALUES ('f1e2d3c4b5a6f7e8', 'sum', NULL);

INSERT INTO oracles (id, cell_id, oracle_type, assertion, ordinal)
VALUES ('1a2b3c4d5e6f7a8b', 'f1e2d3c4b5a6f7e8', 'deterministic', 'sum = 8', 0);

CALL DOLT_ADD('-A');
CALL DOLT_COMMIT('-m', 'load: add-example');
```

## Connection details

- **DSN**: `root@tcp(127.0.0.1:3308)/` (env: RETORT_DSN)
- **Database**: retort
- **Port**: 3308 (separate from Beads on 3307)
