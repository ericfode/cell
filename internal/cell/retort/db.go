package retort

import (
	"context"
	"crypto/rand"
	"database/sql"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"strings"
	"time"

	_ "github.com/go-sql-driver/mysql"
)

const (
	DefaultDSN      = "root:@tcp(127.0.0.1:3307)/"
	DefaultDatabase = "retort"
)

// DB wraps a Dolt database connection for Retort operations.
type DB struct {
	conn     *sql.DB
	database string
}

// OpenDB connects to the Dolt server and ensures the retort database and schema exist.
func OpenDB(ctx context.Context, dsn, database string) (*DB, error) {
	if dsn == "" {
		dsn = DefaultDSN
	}
	if database == "" {
		database = DefaultDatabase
	}

	db, err := sql.Open("mysql", dsn)
	if err != nil {
		return nil, fmt.Errorf("retort: connect: %w", err)
	}
	db.SetMaxOpenConns(5)
	db.SetConnMaxLifetime(5 * time.Minute)

	rdb := &DB{conn: db, database: database}

	if err := rdb.ensureDatabase(ctx); err != nil {
		db.Close()
		return nil, err
	}

	return rdb, nil
}

// InitSchema creates all Retort tables and views.
func (d *DB) InitSchema(ctx context.Context) error {
	for _, ddl := range DDL {
		if _, err := d.conn.ExecContext(ctx, ddl); err != nil {
			return fmt.Errorf("retort: schema: %w\nSQL: %s", err, ddl)
		}
	}

	if _, err := d.conn.ExecContext(ctx, ReadyCellsView); err != nil {
		return fmt.Errorf("retort: ready_cells view: %w", err)
	}

	// Try to set up dolt_ignore for trace table (may fail if table doesn't exist yet)
	d.conn.ExecContext(ctx, DoltIgnoreTrace)

	// Initial schema commit
	return d.DoltCommit(ctx, "retort: init schema v"+fmt.Sprintf("%d", SchemaVersion))
}

func (d *DB) ensureDatabase(ctx context.Context) error {
	_, err := d.conn.ExecContext(ctx, "CREATE DATABASE IF NOT EXISTS `"+d.database+"`")
	if err != nil {
		return fmt.Errorf("retort: create database: %w", err)
	}
	_, err = d.conn.ExecContext(ctx, "USE `"+d.database+"`")
	if err != nil {
		return fmt.Errorf("retort: use database: %w", err)
	}
	return nil
}

// Close closes the database connection.
func (d *DB) Close() error {
	return d.conn.Close()
}

// QueryRow exposes a single-row query for ad-hoc SQL.
func (d *DB) QueryRow(ctx context.Context, query string, args ...interface{}) *sql.Row {
	return d.conn.QueryRowContext(ctx, query, args...)
}

// DoltCommit creates a Dolt commit with the given message.
func (d *DB) DoltCommit(ctx context.Context, message string) error {
	if _, err := d.conn.ExecContext(ctx, "CALL DOLT_ADD('-A')"); err != nil {
		return fmt.Errorf("retort: dolt add: %w", err)
	}
	if _, err := d.conn.ExecContext(ctx, "CALL DOLT_COMMIT('-m', ?, '--allow-empty')", message); err != nil {
		return fmt.Errorf("retort: dolt commit: %w", err)
	}
	return nil
}

// --- Program operations ---

// InsertProgram creates a new program record.
func (d *DB) InsertProgram(ctx context.Context, prog *RetortProgram) (string, error) {
	id := newID()
	_, err := d.conn.ExecContext(ctx,
		`INSERT INTO programs (id, name, source_file, source_hash, status)
		 VALUES (?, ?, ?, ?, 'ready')`,
		id, prog.Name, prog.SourceFile, prog.SourceHash)
	if err != nil {
		return "", fmt.Errorf("retort: insert program: %w", err)
	}
	return id, nil
}

// GetProgramByName returns a program by name.
func (d *DB) GetProgramByName(ctx context.Context, name string) (string, error) {
	var id string
	err := d.conn.QueryRowContext(ctx,
		`SELECT id FROM programs WHERE name = ? ORDER BY created_at DESC LIMIT 1`, name).Scan(&id)
	if err == sql.ErrNoRows {
		return "", fmt.Errorf("retort: program not found: %s", name)
	}
	return id, err
}

// UpdateProgramStatus sets the program status.
func (d *DB) UpdateProgramStatus(ctx context.Context, programID, status string) error {
	_, err := d.conn.ExecContext(ctx,
		`UPDATE programs SET status = ? WHERE id = ?`, status, programID)
	return err
}

// --- Cell operations ---

// InsertCell creates a new cell record.
func (d *DB) InsertCell(ctx context.Context, programID string, cell *RetortCell) (string, error) {
	id := newID()
	qualifiedName := programID + "." + cell.Name
	_, err := d.conn.ExecContext(ctx,
		`INSERT INTO cells (id, program_id, name, qualified_name, body_type, body, max_retries)
		 VALUES (?, ?, ?, ?, ?, ?, ?)`,
		id, programID, cell.Name, qualifiedName, string(cell.BodyType), cell.Body, maxRetries(cell))
	if err != nil {
		return "", fmt.Errorf("retort: insert cell %s: %w", cell.Name, err)
	}
	return id, nil
}

// InsertGiven creates a given record for a cell.
func (d *DB) InsertGiven(ctx context.Context, cellID string, g *RetortGiven) error {
	id := newID()
	var defVal *string
	if g.HasDefault && g.Default != nil {
		defVal = g.Default
	}
	var srcCell, srcField *string
	if g.SourceCell != "" {
		srcCell = &g.SourceCell
	}
	if g.SourceField != "" {
		srcField = &g.SourceField
	}
	var guardExpr *string
	if g.GuardExpr != "" {
		guardExpr = &g.GuardExpr
	}

	_, err := d.conn.ExecContext(ctx,
		`INSERT INTO givens (id, cell_id, param_name, source_cell, source_field,
		 is_optional, is_quotation, default_value, has_default, guard_expr)
		 VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`,
		id, cellID, g.Name, srcCell, srcField,
		boolToInt(g.IsOptional), boolToInt(g.IsQuotation),
		defVal, boolToInt(g.HasDefault), guardExpr)
	return err
}

// InsertYield creates a yield record for a cell.
func (d *DB) InsertYield(ctx context.Context, cellID string, y *RetortYield) error {
	_, err := d.conn.ExecContext(ctx,
		`INSERT INTO yields (cell_id, field_name, default_value)
		 VALUES (?, ?, ?)`,
		cellID, y.Name, y.DefaultValue)
	return err
}

// InsertOracle creates an oracle record for a cell.
func (d *DB) InsertOracle(ctx context.Context, cellID string, o *RetortOracle, oracleType string) error {
	id := newID()
	_, err := d.conn.ExecContext(ctx,
		`INSERT INTO oracles (id, cell_id, oracle_type, assertion, ordinal)
		 VALUES (?, ?, ?, ?, ?)`,
		id, cellID, oracleType, o.Assertion, o.Ordinal)
	return err
}

// InsertRecoveryPolicy creates a recovery policy for a cell.
func (d *DB) InsertRecoveryPolicy(ctx context.Context, cellID string, r *RetortRecovery) error {
	id := newID()
	_, err := d.conn.ExecContext(ctx,
		`INSERT INTO recovery_policies (id, cell_id, max_retries, exhaustion_action, recovery_directive)
		 VALUES (?, ?, ?, ?, ?)`,
		id, cellID, r.MaxRetries, r.ExhaustionAction, r.RecoveryDirective)
	return err
}

// --- Query operations ---

// FindReadyCells returns cells that are ready to evaluate.
func (d *DB) FindReadyCells(ctx context.Context, programID string) ([]CellRow, error) {
	rows, err := d.conn.QueryContext(ctx,
		`SELECT c.id, c.program_id, c.name, c.body_type, c.body, c.state,
		        c.retry_count, c.max_retries
		 FROM ready_cells c
		 WHERE c.program_id = ?
		 ORDER BY c.name`, programID)
	if err != nil {
		return nil, fmt.Errorf("retort: find ready: %w", err)
	}
	defer rows.Close()
	return scanCellRows(rows)
}

// GetCell returns a single cell by ID.
func (d *DB) GetCell(ctx context.Context, cellID string) (*CellRow, error) {
	rows, err := d.conn.QueryContext(ctx,
		`SELECT id, program_id, name, body_type, body, state, retry_count, max_retries
		 FROM cells WHERE id = ?`, cellID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	cells, err := scanCellRows(rows)
	if err != nil {
		return nil, err
	}
	if len(cells) == 0 {
		return nil, fmt.Errorf("retort: cell not found: %s", cellID)
	}
	return &cells[0], nil
}

// GetCellByName returns a cell by program ID and name.
func (d *DB) GetCellByName(ctx context.Context, programID, name string) (*CellRow, error) {
	rows, err := d.conn.QueryContext(ctx,
		`SELECT id, program_id, name, body_type, body, state, retry_count, max_retries
		 FROM cells WHERE program_id = ? AND name = ?`, programID, name)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	cells, err := scanCellRows(rows)
	if err != nil {
		return nil, err
	}
	if len(cells) == 0 {
		return nil, fmt.Errorf("retort: cell %s not found in program %s", name, programID)
	}
	return &cells[0], nil
}

// GetGivens returns all givens for a cell.
func (d *DB) GetGivens(ctx context.Context, cellID string) ([]GivenRow, error) {
	rows, err := d.conn.QueryContext(ctx,
		`SELECT id, cell_id, param_name, source_cell, source_field,
		        is_optional, is_quotation, default_value, has_default, guard_expr, resolved
		 FROM givens WHERE cell_id = ?`, cellID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var givens []GivenRow
	for rows.Next() {
		var g GivenRow
		var srcCell, srcField, defVal, guardExpr sql.NullString
		err := rows.Scan(&g.ID, &g.CellID, &g.ParamName, &srcCell, &srcField,
			&g.IsOptional, &g.IsQuotation, &defVal, &g.HasDefault, &guardExpr, &g.Resolved)
		if err != nil {
			return nil, err
		}
		g.SourceCell = srcCell.String
		g.SourceField = srcField.String
		g.DefaultValue = defVal.String
		g.GuardExpr = guardExpr.String
		givens = append(givens, g)
	}
	return givens, rows.Err()
}

// GetYields returns all yields for a cell.
func (d *DB) GetYields(ctx context.Context, cellID string) ([]YieldRow, error) {
	rows, err := d.conn.QueryContext(ctx,
		`SELECT cell_id, field_name, value_text, value_json, is_frozen, is_bottom,
		        tentative_value, default_value
		 FROM yields WHERE cell_id = ?`, cellID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var yields []YieldRow
	for rows.Next() {
		var y YieldRow
		var valText, valJSON, tentative, defVal sql.NullString
		err := rows.Scan(&y.CellID, &y.FieldName, &valText, &valJSON,
			&y.IsFrozen, &y.IsBottom, &tentative, &defVal)
		if err != nil {
			return nil, err
		}
		y.ValueText = valText.String
		y.ValueJSON = valJSON.String
		y.TentativeValue = tentative.String
		y.DefaultValue = defVal.String
		yields = append(yields, y)
	}
	return yields, rows.Err()
}

// GetOracles returns all oracles for a cell.
func (d *DB) GetOracles(ctx context.Context, cellID string) ([]OracleRow, error) {
	rows, err := d.conn.QueryContext(ctx,
		`SELECT id, cell_id, oracle_type, assertion, condition_expr, ordinal
		 FROM oracles WHERE cell_id = ? ORDER BY ordinal`, cellID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var oracles []OracleRow
	for rows.Next() {
		var o OracleRow
		var condExpr sql.NullString
		err := rows.Scan(&o.ID, &o.CellID, &o.OracleType, &o.Assertion, &condExpr, &o.Ordinal)
		if err != nil {
			return nil, err
		}
		o.ConditionExpr = condExpr.String
		oracles = append(oracles, o)
	}
	return oracles, rows.Err()
}

// GetAllCells returns all cells for a program.
func (d *DB) GetAllCells(ctx context.Context, programID string) ([]CellRow, error) {
	rows, err := d.conn.QueryContext(ctx,
		`SELECT id, program_id, name, body_type, body, state, retry_count, max_retries
		 FROM cells WHERE program_id = ? ORDER BY name`, programID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	return scanCellRows(rows)
}

// GetAllYields returns all yields for a program.
func (d *DB) GetAllYields(ctx context.Context, programID string) ([]YieldRow, error) {
	rows, err := d.conn.QueryContext(ctx,
		`SELECT y.cell_id, y.field_name, y.value_text, y.value_json,
		        y.is_frozen, y.is_bottom, y.tentative_value, y.default_value
		 FROM yields y
		 JOIN cells c ON c.id = y.cell_id
		 WHERE c.program_id = ?
		 ORDER BY c.name, y.field_name`, programID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var yields []YieldRow
	for rows.Next() {
		var y YieldRow
		var valText, valJSON, tentative, defVal sql.NullString
		err := rows.Scan(&y.CellID, &y.FieldName, &valText, &valJSON,
			&y.IsFrozen, &y.IsBottom, &tentative, &defVal)
		if err != nil {
			return nil, err
		}
		y.ValueText = valText.String
		y.ValueJSON = valJSON.String
		y.TentativeValue = tentative.String
		y.DefaultValue = defVal.String
		yields = append(yields, y)
	}
	return yields, rows.Err()
}

// --- State mutation ---

// SetCellState updates a cell's state.
func (d *DB) SetCellState(ctx context.Context, cellID, state string) error {
	_, err := d.conn.ExecContext(ctx,
		`UPDATE cells SET state = ? WHERE id = ?`, state, cellID)
	return err
}

// SetTentativeValue sets the tentative value on a yield.
func (d *DB) SetTentativeValue(ctx context.Context, cellID, fieldName, value string) error {
	_, err := d.conn.ExecContext(ctx,
		`UPDATE yields SET tentative_value = ? WHERE cell_id = ? AND field_name = ?`,
		value, cellID, fieldName)
	return err
}

// FreezeYield freezes a yield with its final value.
func (d *DB) FreezeYield(ctx context.Context, cellID, fieldName string, value interface{}) error {
	valText := fmt.Sprintf("%v", value)
	valJSON, _ := json.Marshal(value)
	_, err := d.conn.ExecContext(ctx,
		`UPDATE yields SET value_text = ?, value_json = ?, is_frozen = 1, frozen_at = NOW()
		 WHERE cell_id = ? AND field_name = ?`,
		valText, string(valJSON), cellID, fieldName)
	return err
}

// SetYieldBottom marks a yield as bottom.
func (d *DB) SetYieldBottom(ctx context.Context, cellID, fieldName string) error {
	_, err := d.conn.ExecContext(ctx,
		`UPDATE yields SET is_bottom = 1, is_frozen = 1, frozen_at = NOW()
		 WHERE cell_id = ? AND field_name = ?`,
		cellID, fieldName)
	return err
}

// MarkGivenResolved marks a given as resolved.
func (d *DB) MarkGivenResolved(ctx context.Context, givenID string) error {
	_, err := d.conn.ExecContext(ctx,
		`UPDATE givens SET resolved = 1 WHERE id = ?`, givenID)
	return err
}

// IncrementRetry bumps the retry count on a cell.
func (d *DB) IncrementRetry(ctx context.Context, cellID string) error {
	_, err := d.conn.ExecContext(ctx,
		`UPDATE cells SET retry_count = retry_count + 1 WHERE id = ?`, cellID)
	return err
}

// --- Trace ---

// InsertTrace records an execution trace entry.
func (d *DB) InsertTrace(ctx context.Context, programID string, step int, cellID, action, detail string, durationMs int) error {
	_, err := d.conn.ExecContext(ctx,
		`INSERT INTO trace (step, program_id, cell_id, action, duration_ms, detail)
		 VALUES (?, ?, ?, ?, ?, ?)`,
		step, programID, cellID, action, durationMs, detail)
	return err
}

// GetTrace returns execution trace entries for a program.
func (d *DB) GetTrace(ctx context.Context, programID string) ([]TraceRow, error) {
	rows, err := d.conn.QueryContext(ctx,
		`SELECT step, program_id, cell_id, action, duration_ms, detail, created_at
		 FROM trace WHERE program_id = ? ORDER BY step`, programID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var traces []TraceRow
	for rows.Next() {
		var t TraceRow
		var detail sql.NullString
		var durationMs sql.NullInt64
		var createdAt sql.NullString
		err := rows.Scan(&t.Step, &t.ProgramID, &t.CellID, &t.Action, &durationMs, &detail, &createdAt)
		if err != nil {
			return nil, err
		}
		t.Detail = detail.String
		if durationMs.Valid {
			t.DurationMs = int(durationMs.Int64)
		}
		if createdAt.Valid {
			t.CreatedAt, _ = time.Parse("2006-01-02 15:04:05", createdAt.String)
		}
		traces = append(traces, t)
	}
	return traces, rows.Err()
}

// --- Row types ---

// CellRow is a database row from the cells table.
type CellRow struct {
	ID         string
	ProgramID  string
	Name       string
	BodyType   string
	Body       string
	State      string
	RetryCount int
	MaxRetries int
}

// GivenRow is a database row from the givens table.
type GivenRow struct {
	ID           string
	CellID       string
	ParamName    string
	SourceCell   string
	SourceField  string
	IsOptional   bool
	IsQuotation  bool
	DefaultValue string
	HasDefault   bool
	GuardExpr    string
	Resolved     bool
}

// YieldRow is a database row from the yields table.
type YieldRow struct {
	CellID         string
	FieldName      string
	ValueText      string
	ValueJSON      string
	IsFrozen       bool
	IsBottom       bool
	TentativeValue string
	DefaultValue   string
}

// OracleRow is a database row from the oracles table.
type OracleRow struct {
	ID            string
	CellID        string
	OracleType    string
	Assertion     string
	ConditionExpr string
	Ordinal       int
}

// TraceRow is a database row from the trace table.
type TraceRow struct {
	Step       int
	ProgramID  string
	CellID     string
	Action     string
	DurationMs int
	Detail     string
	CreatedAt  time.Time
}

// --- Helpers ---

func scanCellRows(rows *sql.Rows) ([]CellRow, error) {
	var cells []CellRow
	for rows.Next() {
		var c CellRow
		var body sql.NullString
		err := rows.Scan(&c.ID, &c.ProgramID, &c.Name, &c.BodyType, &body,
			&c.State, &c.RetryCount, &c.MaxRetries)
		if err != nil {
			return nil, err
		}
		c.Body = body.String
		cells = append(cells, c)
	}
	return cells, rows.Err()
}

func newID() string {
	b := make([]byte, 8)
	rand.Read(b)
	return hex.EncodeToString(b)
}

func boolToInt(b bool) int {
	if b {
		return 1
	}
	return 0
}

func maxRetries(cell *RetortCell) int {
	if cell.Recovery != nil {
		return cell.Recovery.MaxRetries
	}
	return 3
}

// GetFrozenYieldValue reads the frozen value of a specific yield.
func (d *DB) GetFrozenYieldValue(ctx context.Context, programID, cellName, fieldName string) (interface{}, bool, error) {
	var valJSON sql.NullString
	var isBottom bool
	err := d.conn.QueryRowContext(ctx,
		`SELECT y.value_json, y.is_bottom
		 FROM yields y
		 JOIN cells c ON c.id = y.cell_id
		 WHERE c.program_id = ? AND c.name = ? AND y.field_name = ?`,
		programID, cellName, fieldName).Scan(&valJSON, &isBottom)
	if err == sql.ErrNoRows {
		return nil, false, nil
	}
	if err != nil {
		return nil, false, err
	}
	if isBottom {
		return nil, true, nil
	}
	if !valJSON.Valid || valJSON.String == "" {
		return nil, false, nil
	}
	var val interface{}
	if err := json.Unmarshal([]byte(valJSON.String), &val); err != nil {
		return valJSON.String, false, nil
	}
	return val, false, nil
}

// ResolveGivens resolves all givens for a cell by reading upstream frozen yields.
// Returns the bindings map and whether all required givens are satisfied.
func (d *DB) ResolveGivens(ctx context.Context, programID, cellID string) (map[string]interface{}, bool, error) {
	givens, err := d.GetGivens(ctx, cellID)
	if err != nil {
		return nil, false, err
	}

	bindings := make(map[string]interface{})
	allResolved := true

	for _, g := range givens {
		// Defaults
		if g.HasDefault && g.DefaultValue != "" {
			bindings[g.ParamName] = parseStoredValue(g.DefaultValue)
		}

		// Source cell references
		if g.SourceCell != "" {
			val, isBottom, err := d.GetFrozenYieldValue(ctx, programID, g.SourceCell, g.SourceField)
			if err != nil {
				return nil, false, err
			}
			if isBottom {
				if !g.IsOptional {
					bindings[g.ParamName] = nil
					bindings[g.SourceCell+"→"+g.SourceField] = nil
				} else {
					bindings[g.ParamName] = nil
				}
			} else if val != nil {
				bindings[g.ParamName] = val
				bindings[g.SourceCell+"→"+g.SourceField] = val
				d.MarkGivenResolved(ctx, g.ID)
			} else if !g.IsOptional && !g.HasDefault {
				allResolved = false
			}
		}

		// Quotation
		if g.IsQuotation {
			// For §cell-name, the value is the cell definition as data
			// For v0, just pass the reference name
			bindings[g.ParamName] = g.ParamName
		}
	}

	return bindings, allResolved, nil
}

// CheckGuards evaluates guard expressions on a cell's givens.
// Returns true if all guards pass, false if any guard fails.
func (d *DB) CheckGuards(ctx context.Context, programID, cellID string, bindings map[string]interface{}) (bool, error) {
	givens, err := d.GetGivens(ctx, cellID)
	if err != nil {
		return false, err
	}

	for _, g := range givens {
		if g.GuardExpr == "" {
			continue
		}
		// Evaluate the guard expression
		result, err := EvalExpr(g.GuardExpr, bindings)
		if err != nil {
			// Guard eval failure → guard fails
			return false, nil
		}
		if !toBool(result) {
			return false, nil
		}
	}
	return true, nil
}

func parseStoredValue(s string) interface{} {
	s = strings.TrimSpace(s)

	// Try JSON first
	var v interface{}
	if err := json.Unmarshal([]byte(s), &v); err == nil {
		return v
	}

	// String literals
	if strings.HasPrefix(s, "\"") && strings.HasSuffix(s, "\"") {
		return s[1 : len(s)-1]
	}

	// Booleans
	if s == "true" {
		return true
	}
	if s == "false" {
		return false
	}

	// Bottom
	if s == "⊥" || s == "null" {
		return nil
	}

	// Numbers
	if f, err := fmt.Sscanf(s, "%g", &v); f == 1 && err == nil {
		return v
	}

	return s
}
