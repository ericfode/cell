package retort

// SchemaVersion is the current schema version for Retort.
const SchemaVersion = 1

// DDL contains the CREATE TABLE statements for the Retort schema.
// These are executed against a Dolt database.
var DDL = []string{
	`CREATE TABLE IF NOT EXISTS programs (
		id VARCHAR(64) PRIMARY KEY,
		name VARCHAR(255) NOT NULL,
		source_file TEXT,
		source_hash VARCHAR(64),
		status ENUM('loading', 'ready', 'running', 'quiescent', 'error') NOT NULL DEFAULT 'loading',
		created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
		updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
	)`,

	`CREATE TABLE IF NOT EXISTS cells (
		id VARCHAR(64) PRIMARY KEY,
		program_id VARCHAR(64) NOT NULL,
		name VARCHAR(255) NOT NULL,
		qualified_name VARCHAR(512) NOT NULL,
		body_type ENUM('soft', 'hard', 'script', 'passthrough', 'spawner', 'evolution') NOT NULL,
		body TEXT,
		state ENUM('declared', 'computing', 'tentative', 'frozen', 'bottom', 'skipped') NOT NULL DEFAULT 'declared',
		retry_count INT NOT NULL DEFAULT 0,
		max_retries INT NOT NULL DEFAULT 3,
		spawned_by VARCHAR(64),
		spawn_order INT,
		iteration INT,
		metadata JSON,
		UNIQUE KEY uq_qualified_name (qualified_name),
		KEY idx_program_id (program_id),
		KEY idx_state (state),
		CONSTRAINT fk_cells_program FOREIGN KEY (program_id) REFERENCES programs(id)
	)`,

	`CREATE TABLE IF NOT EXISTS givens (
		id VARCHAR(64) PRIMARY KEY,
		cell_id VARCHAR(64) NOT NULL,
		param_name VARCHAR(255) NOT NULL,
		source_cell VARCHAR(255),
		source_field VARCHAR(255),
		source_pattern VARCHAR(255),
		is_optional TINYINT(1) NOT NULL DEFAULT 0,
		is_quotation TINYINT(1) NOT NULL DEFAULT 0,
		default_value TEXT,
		has_default TINYINT(1) NOT NULL DEFAULT 0,
		guard_expr TEXT,
		resolved TINYINT(1) NOT NULL DEFAULT 0,
		resolved_value_id VARCHAR(64),
		KEY idx_cell_id (cell_id),
		CONSTRAINT fk_givens_cell FOREIGN KEY (cell_id) REFERENCES cells(id)
	)`,

	`CREATE TABLE IF NOT EXISTS yields (
		cell_id VARCHAR(64) NOT NULL,
		field_name VARCHAR(255) NOT NULL,
		value_text TEXT,
		value_json JSON,
		is_frozen TINYINT(1) NOT NULL DEFAULT 0,
		is_bottom TINYINT(1) NOT NULL DEFAULT 0,
		tentative_value TEXT,
		default_value TEXT,
		value_hash VARCHAR(64),
		frozen_at TIMESTAMP NULL,
		PRIMARY KEY (cell_id, field_name),
		CONSTRAINT fk_yields_cell FOREIGN KEY (cell_id) REFERENCES cells(id)
	)`,

	`CREATE TABLE IF NOT EXISTS oracles (
		id VARCHAR(64) PRIMARY KEY,
		cell_id VARCHAR(64) NOT NULL,
		oracle_type ENUM('deterministic', 'structural', 'semantic', 'conditional') NOT NULL DEFAULT 'semantic',
		assertion TEXT NOT NULL,
		condition_expr TEXT,
		ordinal INT NOT NULL DEFAULT 0,
		KEY idx_cell_id (cell_id),
		CONSTRAINT fk_oracles_cell FOREIGN KEY (cell_id) REFERENCES cells(id)
	)`,

	`CREATE TABLE IF NOT EXISTS recovery_policies (
		id VARCHAR(64) PRIMARY KEY,
		cell_id VARCHAR(64),
		program_id VARCHAR(64),
		max_retries INT NOT NULL DEFAULT 3,
		exhaustion_action ENUM('bottom', 'escalate', 'partial_accept') NOT NULL DEFAULT 'bottom',
		exhaustion_predicate TEXT,
		recovery_directive TEXT,
		KEY idx_cell_id (cell_id),
		KEY idx_program_id (program_id)
	)`,

	`CREATE TABLE IF NOT EXISTS evolution_loops (
		id VARCHAR(64) PRIMARY KEY,
		target_cell_id VARCHAR(64) NOT NULL,
		until_expr TEXT,
		max_iterations INT NOT NULL DEFAULT 100,
		current_iteration INT NOT NULL DEFAULT 0,
		status ENUM('pending', 'running', 'converged', 'exhausted') NOT NULL DEFAULT 'pending',
		KEY idx_target_cell (target_cell_id)
	)`,

	`CREATE TABLE IF NOT EXISTS trace (
		step INT NOT NULL,
		program_id VARCHAR(64) NOT NULL,
		cell_id VARCHAR(64),
		action VARCHAR(64) NOT NULL,
		duration_ms INT,
		detail TEXT,
		created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
		KEY idx_program_step (program_id, step)
	)`,

	`CREATE TABLE IF NOT EXISTS bead_bridge (
		cell_id VARCHAR(64) NOT NULL,
		bead_id VARCHAR(64) NOT NULL,
		bridge_type ENUM('dispatch', 'result', 'oracle') NOT NULL,
		created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
		updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
		PRIMARY KEY (cell_id, bead_id)
	)`,

	`CREATE TABLE IF NOT EXISTS config (
		key_name VARCHAR(255) PRIMARY KEY,
		value_text TEXT
	)`,

	`CREATE TABLE IF NOT EXISTS metadata (
		key_name VARCHAR(255) PRIMARY KEY,
		value_text TEXT
	)`,
}

// ReadyCellsView is the SQL for finding cells ready to evaluate.
// Non-recursive: Cell's blocking is through data flow, not transitive parent chains.
// A cell is ready when:
// 1. It's declared
// 2. All required source-cell givens have their upstream yields frozen
// 3. No required upstream yields are bottom
// NOTE: Uses NOT IN instead of correlated NOT EXISTS due to Dolt view bug.
const ReadyCellsView = `
CREATE OR REPLACE VIEW ready_cells AS
SELECT c.* FROM cells c
WHERE c.state = 'declared'
  AND c.id NOT IN (
    SELECT g.cell_id FROM givens g
    WHERE g.is_optional = 0
      AND g.source_cell IS NOT NULL
      AND NOT EXISTS (
        SELECT 1 FROM cells src
        JOIN yields y ON y.cell_id = src.id AND y.field_name = g.source_field
        WHERE src.program_id = (SELECT program_id FROM cells WHERE id = g.cell_id)
          AND src.name = g.source_cell
          AND y.is_frozen = 1
      )
  )
  AND c.id NOT IN (
    SELECT g.cell_id FROM givens g
    JOIN cells src ON src.name = g.source_cell
      AND src.program_id = (SELECT program_id FROM cells WHERE id = g.cell_id)
    JOIN yields y ON y.cell_id = src.id AND y.field_name = g.source_field
    WHERE g.is_optional = 0
      AND g.source_cell IS NOT NULL
      AND y.is_bottom = 1
  )
`

// DoltIgnoreTrace tells Dolt to ignore the trace table (high-volume, not versioned).
const DoltIgnoreTrace = `INSERT IGNORE INTO dolt_ignore VALUES ('trace', 1)`
