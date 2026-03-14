package retort

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"os"
	"strings"
)

// DispatchResult is the output of dispatching a single cell.
type DispatchResult struct {
	Outputs map[string]interface{}
	Err     error
}

// Dispatch evaluates a cell and returns its outputs.
func Dispatch(ctx context.Context, cell *CellRow, yields []YieldRow, bindings map[string]interface{}) DispatchResult {
	yieldNames := make([]string, len(yields))
	for i, y := range yields {
		yieldNames[i] = y.FieldName
	}

	switch cell.BodyType {
	case "hard":
		return dispatchHard(cell, yieldNames, bindings)
	case "soft":
		return dispatchSoft(ctx, cell, yieldNames, bindings)
	case "passthrough":
		return dispatchPassthrough(yieldNames, bindings)
	default:
		return DispatchResult{Err: fmt.Errorf("unsupported body type: %s", cell.BodyType)}
	}
}

func dispatchHard(cell *CellRow, yieldNames []string, bindings map[string]interface{}) DispatchResult {
	body := cell.Body

	// Handle multi-expression bodies (newline-separated ⊢= lines)
	lines := strings.Split(body, "\n")
	if len(lines) > 1 {
		outputs := make(map[string]interface{})
		localBindings := make(map[string]interface{})
		for k, v := range bindings {
			localBindings[k] = v
		}

		for _, line := range lines {
			line = strings.TrimSpace(line)
			if line == "" {
				continue
			}

			// Check for binding form: name ← expression
			if idx := strings.Index(line, "←"); idx > 0 {
				name := strings.TrimSpace(line[:idx])
				expr := strings.TrimSpace(line[idx+len("←"):])
				val, err := EvalExpr(expr, localBindings)
				if err != nil {
					return DispatchResult{Err: fmt.Errorf("hard eval %s: %w", name, err)}
				}
				localBindings[name] = val
				outputs[name] = val
			} else {
				val, err := EvalExpr(line, localBindings)
				if err != nil {
					return DispatchResult{Err: fmt.Errorf("hard eval: %w", err)}
				}
				if len(outputs) < len(yieldNames) {
					outputs[yieldNames[len(outputs)]] = val
				}
			}
		}
		return DispatchResult{Outputs: outputs}
	}

	// Single expression
	result, err := EvalExpr(body, bindings)
	if err != nil {
		return DispatchResult{Err: fmt.Errorf("hard eval: %w", err)}
	}

	outputs := make(map[string]interface{})
	if len(yieldNames) == 1 {
		outputs[yieldNames[0]] = result
	} else if m, ok := result.(map[string]interface{}); ok {
		outputs = m
	} else {
		outputs[yieldNames[0]] = result
	}
	return DispatchResult{Outputs: outputs}
}

func dispatchSoft(ctx context.Context, cell *CellRow, yieldNames []string, bindings map[string]interface{}) DispatchResult {
	body := Interpolate(cell.Body, bindings)

	apiKey := os.Getenv("ANTHROPIC_API_KEY")
	if apiKey == "" {
		// Fallback to dry-run if no API key
		outputs := make(map[string]interface{})
		for _, name := range yieldNames {
			outputs[name] = fmt.Sprintf("<no-api-key-%s-%s>", cell.Name, name)
		}
		return DispatchResult{Outputs: outputs}
	}

	outputs, err := callAnthropic(ctx, apiKey, cell.Name, body, bindings, yieldNames)
	if err != nil {
		return DispatchResult{Err: err}
	}
	return DispatchResult{Outputs: outputs}
}

func dispatchPassthrough(yieldNames []string, bindings map[string]interface{}) DispatchResult {
	outputs := make(map[string]interface{})
	for _, name := range yieldNames {
		if val, ok := bindings[name]; ok {
			outputs[name] = val
		}
	}
	return DispatchResult{Outputs: outputs}
}

// DispatchWithYieldDefaults handles data cells that have yield defaults.
// It populates outputs from yield default values.
func DispatchWithYieldDefaults(yields []YieldRow) DispatchResult {
	outputs := make(map[string]interface{})
	for _, y := range yields {
		if y.DefaultValue != "" {
			outputs[y.FieldName] = parseYieldDefault(y.DefaultValue)
		}
	}
	return DispatchResult{Outputs: outputs}
}

func parseYieldDefault(s string) interface{} {
	s = strings.TrimSpace(s)
	// Try as a list: [1, 2, 3]
	if strings.HasPrefix(s, "[") && strings.HasSuffix(s, "]") {
		inner := strings.TrimSpace(s[1 : len(s)-1])
		if inner == "" {
			return []interface{}{}
		}
		parts := strings.Split(inner, ",")
		result := make([]interface{}, len(parts))
		for i, p := range parts {
			result[i] = parseLiteralValueForDefault(strings.TrimSpace(p))
		}
		return result
	}
	return parseLiteralValueForDefault(s)
}

func parseLiteralValueForDefault(s string) interface{} {
	s = strings.TrimSpace(s)
	if s == "true" {
		return true
	}
	if s == "false" {
		return false
	}
	if s == "⊥" || s == "null" {
		return nil
	}
	if len(s) >= 2 && s[0] == '"' && s[len(s)-1] == '"' {
		return s[1 : len(s)-1]
	}
	var f float64
	if n, err := fmt.Sscanf(s, "%g", &f); n == 1 && err == nil {
		return f
	}
	return s
}

func callAnthropic(ctx context.Context, apiKey, cellName, body string, bindings map[string]interface{}, yieldNames []string) (map[string]interface{}, error) {
	// Build prompt
	var prompt strings.Builder
	prompt.WriteString(fmt.Sprintf("Evaluate this Cell:\n\nCell: %s\n", cellName))
	prompt.WriteString("\nInputs:\n")
	for k, v := range bindings {
		if !strings.Contains(k, "→") {
			vJSON, _ := json.Marshal(v)
			prompt.WriteString(fmt.Sprintf("  %s = %s\n", k, string(vJSON)))
		}
	}
	prompt.WriteString(fmt.Sprintf("\nTask:\n%s\n", body))
	prompt.WriteString(fmt.Sprintf("\nProduce values for: %s\n", strings.Join(yieldNames, ", ")))
	fieldHints := make([]string, len(yieldNames))
	for i, n := range yieldNames {
		fieldHints[i] = fmt.Sprintf(`"%s": ...`, n)
	}
	prompt.WriteString(fmt.Sprintf("\nRespond with JSON only: {%s}\n", strings.Join(fieldHints, ", ")))

	// Build API request
	reqBody := map[string]interface{}{
		"model":      "claude-haiku-4-5-20251001",
		"max_tokens": 1024,
		"system":     "You are a Cell program executor. Follow ∴ instructions precisely. Respond ONLY with JSON.",
		"messages": []map[string]interface{}{
			{"role": "user", "content": prompt.String()},
		},
	}

	reqJSON, err := json.Marshal(reqBody)
	if err != nil {
		return nil, fmt.Errorf("marshal request: %w", err)
	}

	req, err := http.NewRequestWithContext(ctx, "POST", "https://api.anthropic.com/v1/messages", bytes.NewReader(reqJSON))
	if err != nil {
		return nil, err
	}
	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("x-api-key", apiKey)
	req.Header.Set("anthropic-version", "2023-06-01")

	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		return nil, fmt.Errorf("anthropic API: %w", err)
	}
	defer resp.Body.Close()

	respBody, err := io.ReadAll(resp.Body)
	if err != nil {
		return nil, fmt.Errorf("read response: %w", err)
	}

	if resp.StatusCode != 200 {
		return nil, fmt.Errorf("anthropic API %d: %s", resp.StatusCode, string(respBody))
	}

	// Parse response
	var apiResp struct {
		Content []struct {
			Text string `json:"text"`
		} `json:"content"`
	}
	if err := json.Unmarshal(respBody, &apiResp); err != nil {
		return nil, fmt.Errorf("parse response: %w", err)
	}

	if len(apiResp.Content) == 0 {
		return nil, fmt.Errorf("empty response from API")
	}

	text := strings.TrimSpace(apiResp.Content[0].Text)
	// Strip markdown code fences
	text = strings.TrimPrefix(text, "```json")
	text = strings.TrimPrefix(text, "```")
	text = strings.TrimSuffix(text, "```")
	text = strings.TrimSpace(text)

	// Parse JSON output
	var data map[string]interface{}
	if err := json.Unmarshal([]byte(text), &data); err != nil {
		// If single yield, use the raw text
		if len(yieldNames) == 1 {
			return map[string]interface{}{yieldNames[0]: text}, nil
		}
		return nil, fmt.Errorf("parse LLM output: %w", err)
	}

	outputs := make(map[string]interface{})
	for _, name := range yieldNames {
		if val, ok := data[name]; ok {
			outputs[name] = val
		}
	}
	return outputs, nil
}
