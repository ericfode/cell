package retort

import (
	"fmt"
	"strings"
)

// EmitSQL generates SQL INSERT statements for a RetortProgram.
// This is the "compile to SQL" path — can be used without a live DB.
func EmitSQL(prog *RetortProgram) string {
	var sb strings.Builder

	progID := "prog_" + sanitizeName(prog.Name)

	sb.WriteString(fmt.Sprintf(
		"INSERT INTO programs (id, name, source_file, source_hash, status) VALUES (%s, %s, %s, %s, 'ready');\n",
		sqlStr(progID), sqlStr(prog.Name), sqlStr(prog.SourceFile), sqlStr(prog.SourceHash)))

	for i, cell := range prog.Cells {
		cellID := fmt.Sprintf("cell_%s_%d", sanitizeName(cell.Name), i)
		qualName := progID + "." + cell.Name

		sb.WriteString(fmt.Sprintf(
			"INSERT INTO cells (id, program_id, name, qualified_name, body_type, body, max_retries) VALUES (%s, %s, %s, %s, %s, %s, %d);\n",
			sqlStr(cellID), sqlStr(progID), sqlStr(cell.Name), sqlStr(qualName),
			sqlStr(string(cell.BodyType)), sqlStr(cell.Body), maxRetries(&cell)))

		for j, g := range cell.Givens {
			givenID := fmt.Sprintf("given_%s_%d", sanitizeName(cell.Name), j)
			defVal := "NULL"
			if g.HasDefault && g.Default != nil {
				defVal = sqlStr(*g.Default)
			}
			srcCell := sqlNullStr(g.SourceCell)
			srcField := sqlNullStr(g.SourceField)
			guardExpr := sqlNullStr(g.GuardExpr)

			sb.WriteString(fmt.Sprintf(
				"INSERT INTO givens (id, cell_id, param_name, source_cell, source_field, is_optional, is_quotation, default_value, has_default, guard_expr) VALUES (%s, %s, %s, %s, %s, %d, %d, %s, %d, %s);\n",
				sqlStr(givenID), sqlStr(cellID), sqlStr(g.Name),
				srcCell, srcField,
				boolToInt(g.IsOptional), boolToInt(g.IsQuotation),
				defVal, boolToInt(g.HasDefault), guardExpr))
		}

		for _, y := range cell.Yields {
			defVal := "NULL"
			if y.DefaultValue != nil {
				defVal = sqlStr(*y.DefaultValue)
			}
			sb.WriteString(fmt.Sprintf(
				"INSERT INTO yields (cell_id, field_name, default_value) VALUES (%s, %s, %s);\n",
				sqlStr(cellID), sqlStr(y.Name), defVal))
		}

		for k, o := range cell.Oracles {
			oracleID := fmt.Sprintf("oracle_%s_%d", sanitizeName(cell.Name), k)
			oType := classifyOracle(o.Assertion)
			sb.WriteString(fmt.Sprintf(
				"INSERT INTO oracles (id, cell_id, oracle_type, assertion, ordinal) VALUES (%s, %s, %s, %s, %d);\n",
				sqlStr(oracleID), sqlStr(cellID), sqlStr(oType), sqlStr(o.Assertion), o.Ordinal))
		}

		if cell.Recovery != nil {
			recoveryID := fmt.Sprintf("recovery_%s", sanitizeName(cell.Name))
			sb.WriteString(fmt.Sprintf(
				"INSERT INTO recovery_policies (id, cell_id, max_retries, exhaustion_action, recovery_directive) VALUES (%s, %s, %d, %s, %s);\n",
				sqlStr(recoveryID), sqlStr(cellID),
				cell.Recovery.MaxRetries, sqlStr(cell.Recovery.ExhaustionAction),
				sqlStr(cell.Recovery.RecoveryDirective)))
		}
	}

	return sb.String()
}

func sqlStr(s string) string {
	escaped := strings.ReplaceAll(s, "'", "''")
	escaped = strings.ReplaceAll(escaped, "\\", "\\\\")
	return "'" + escaped + "'"
}

func sqlNullStr(s string) string {
	if s == "" {
		return "NULL"
	}
	return sqlStr(s)
}

func sanitizeName(name string) string {
	var sb strings.Builder
	for _, r := range name {
		if (r >= 'a' && r <= 'z') || (r >= 'A' && r <= 'Z') || (r >= '0' && r <= '9') || r == '_' {
			sb.WriteRune(r)
		} else {
			sb.WriteByte('_')
		}
	}
	return sb.String()
}
