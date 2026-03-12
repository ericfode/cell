#!/usr/bin/env python3
"""eval-one: Minimal Cell execution loop.

Proves Cell is MECHANIZABLE. Classical driver does graph ops,
delegates soft cells to LLM API, evaluates hard cells classically.

Usage:
    source tools/eval-one/.venv/bin/activate
    python tools/eval-one/eval_one.py programs/p1-parallel-confluence.cell

Set ANTHROPIC_API_KEY for live LLM execution.
Without it, runs in dry-run mode (prompts printed, no API calls).
"""

from __future__ import annotations

import json
import os
import re
import sys
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any


# ─── Data Structures ─────────────────────────────────────────────

@dataclass
class Given:
    name: str                        # local parameter name
    source_cell: str | None = None   # upstream cell (None if literal)
    source_field: str | None = None  # field on upstream cell
    default: Any = None              # ≡ value
    has_default: bool = False
    guard_expr: str | None = None    # where clause
    optional: bool = False           # given? vs given

    @property
    def is_dependency(self) -> bool:
        return self.source_cell is not None


@dataclass
class Oracle:
    text: str  # raw assertion text after ⊨


@dataclass
class Cell:
    name: str
    turnstile: str  # "⊢", "⊢=", "⊢⊢"
    givens: list[Given] = field(default_factory=list)
    yield_names: list[str] = field(default_factory=list)
    body: str | None = None
    body_type: str | None = None  # "soft", "hard", "passthrough"
    oracles: list[Oracle] = field(default_factory=list)
    recovery: str | None = None

    # Runtime state
    frozen: bool = False
    yield_values: dict[str, Any] = field(default_factory=dict)
    is_bottom: bool = False

    def resolve_given(self, g: Given, cells: dict[str, Cell]) -> Any:
        """Resolve a given to its concrete value."""
        if g.has_default:
            return g.default
        if g.is_dependency:
            src = cells.get(g.source_cell)
            if src is None:
                return None
            return src.yield_values.get(g.source_field)
        return None

    def is_ready(self, cells: dict[str, Cell]) -> bool:
        """Check if all givens are satisfied and cell can execute."""
        if self.frozen or self.is_bottom:
            return False
        for g in self.givens:
            if g.has_default:
                continue
            if g.is_dependency:
                src = cells.get(g.source_cell)
                if src is None:
                    return False
                if src.is_bottom:
                    if g.optional:
                        continue
                    return False
                if not src.frozen:
                    return False
                if g.source_field not in src.yield_values:
                    return False
                # Check guard clause
                if g.guard_expr:
                    val = src.yield_values[g.source_field]
                    if not self._eval_guard(g.guard_expr, g.name, val):
                        return False
            else:
                # Non-dependency, non-default: shouldn't happen in valid Cell
                return False
        return True

    def _eval_guard(self, expr: str, var_name: str, val: Any) -> bool:
        """Evaluate a guard clause like 'label = "toxic"'."""
        # Simple equality check: name = "value"
        m = re.match(r'(\w+)\s*=\s*"([^"]*)"', expr)
        if m:
            return str(val) == m.group(2)
        m = re.match(r'(\w+)\s*=\s*(\w+)', expr)
        if m:
            return str(val) == m.group(2)
        return True  # Can't evaluate → assume true

    def get_bindings(self, cells: dict[str, Cell]) -> dict[str, Any]:
        """Resolve all givens to concrete values."""
        bindings = {}
        for g in self.givens:
            val = self.resolve_given(g, cells)
            bindings[g.name] = val
            if g.is_dependency:
                # Also store as "cell→field" key for expression evaluation
                bindings[f"{g.source_cell}→{g.source_field}"] = val
        return bindings


# ─── Parser ───────────────────────────────────────────────────────

def parse_cell_file(text: str) -> list[Cell]:
    """Parse a .cell file into a list of Cell objects."""
    cells: list[Cell] = []
    current: Cell | None = None
    body_lines: list[str] = []
    in_body = False

    for raw_line in text.split("\n"):
        line = raw_line.rstrip()
        stripped = line.lstrip()

        # Skip empty lines and comments
        if not stripped or stripped.startswith("--"):
            if in_body and stripped.startswith("--"):
                continue
            if in_body and not stripped:
                body_lines.append("")
            continue

        # Cell declaration: ⊢ name, ⊢= name, ⊢⊢ name
        m = re.match(r'^(⊢⊢|⊢=|⊢)\s+(\S+)', stripped)
        if m:
            # Save previous body
            if current and in_body and body_lines:
                current.body = "\n".join(body_lines).strip()
            in_body = False
            body_lines = []

            ts = m.group(1)
            name = m.group(2)

            # Check for ⊢= inside a cell body (not a new cell)
            indent = len(line) - len(stripped)
            if indent > 0 and current is not None and ts == "⊢=":
                # This is a hard expression body within a cell
                expr_part = stripped[len("⊢= "):]
                current.body = expr_part
                current.body_type = "hard"
                continue

            current = Cell(name=name, turnstile=ts)
            if ts == "⊢=":
                current.body_type = "hard"
            elif ts == "⊢⊢":
                current.body_type = "spawner"
            cells.append(current)
            continue

        if current is None:
            continue

        # given clause
        gm = re.match(r'^\s+(given\??)\s+(.+)', line)
        if gm:
            if in_body and body_lines:
                current.body = "\n".join(body_lines).strip()
                in_body = False
                body_lines = []

            optional = gm.group(1) == "given?"
            rest = gm.group(2).strip()
            g = _parse_given(rest, optional)
            current.givens.append(g)
            continue

        # yield clause
        ym = re.match(r'^\s+yield\s+(.+)', line)
        if ym:
            if in_body and body_lines:
                current.body = "\n".join(body_lines).strip()
                in_body = False
                body_lines = []

            rest = ym.group(1).strip()
            # Parse yield names (comma-separated, may have [] suffix)
            names = [n.strip().rstrip("[]") for n in rest.split(",")]
            current.yield_names.extend(names)
            continue

        # ∴ body (soft)
        if stripped.startswith("∴"):
            if in_body and body_lines:
                current.body = "\n".join(body_lines).strip()
            body_text = stripped[len("∴"):].strip()
            body_lines = [body_text] if body_text else []
            in_body = True
            current.body_type = "soft"
            continue

        # ⊨? recovery
        if stripped.startswith("⊨?"):
            if in_body and body_lines:
                current.body = "\n".join(body_lines).strip()
                in_body = False
                body_lines = []
            current.recovery = stripped[len("⊨?"):].strip()
            continue

        # ⊨ oracle
        if stripped.startswith("⊨"):
            if in_body and body_lines:
                current.body = "\n".join(body_lines).strip()
                in_body = False
                body_lines = []
            oracle_text = stripped[len("⊨"):].strip()
            current.oracles.append(Oracle(text=oracle_text))
            continue

        # ⊢= expression body (indented within cell)
        if stripped.startswith("⊢="):
            if in_body and body_lines:
                current.body = "\n".join(body_lines).strip()
                in_body = False
                body_lines = []
            expr_part = stripped[len("⊢="):].strip()
            current.body = expr_part
            current.body_type = "hard"
            continue

        # Continuation of ∴ body
        if in_body:
            body_lines.append(stripped)
            continue

    # Save final body
    if current and in_body and body_lines:
        current.body = "\n".join(body_lines).strip()

    # Post-process: cells with no body that yield a given name are passthrough
    for c in cells:
        if c.body is None and c.body_type is None:
            c.body_type = "passthrough"

    return cells


def _parse_given(text: str, optional: bool) -> Given:
    """Parse the rest of a given clause after 'given' keyword."""
    guard = None
    # Check for 'where' guard
    wm = re.search(r'\s+where\s+(.+)$', text)
    if wm:
        guard = wm.group(1).strip()
        text = text[:wm.start()]

    # Check for default value: name ≡ "value" or name ≡ value
    dm = re.match(r'^(\S+)\s*≡\s*(.+)$', text)
    if dm:
        name = dm.group(1)
        val_str = dm.group(2).strip()
        val = _parse_value(val_str)
        # Check if name is a dependency (cell→field ≡ value)
        if "→" in name:
            parts = name.split("→", 1)
            return Given(
                name=parts[1], source_cell=parts[0],
                source_field=parts[1], default=val,
                has_default=True, guard_expr=guard, optional=optional
            )
        return Given(
            name=name, default=val, has_default=True,
            guard_expr=guard, optional=optional
        )

    # Check for dependency: cell→field
    if "→" in text:
        parts = text.split("→", 1)
        cell_name = parts[0].strip()
        field_name = parts[1].strip()
        return Given(
            name=field_name, source_cell=cell_name,
            source_field=field_name, guard_expr=guard, optional=optional
        )

    # Plain given name (no default, no dependency)
    return Given(name=text.strip(), guard_expr=guard, optional=optional)


def _parse_value(s: str) -> Any:
    """Parse a literal value from Cell syntax."""
    s = s.strip()
    if s.startswith('"') and s.endswith('"'):
        return s[1:-1]
    if s.startswith("[") and s.endswith("]"):
        # Simple list parsing
        inner = s[1:-1].strip()
        if not inner:
            return []
        items = [_parse_value(x.strip()) for x in inner.split(",")]
        return items
    if s == "true":
        return True
    if s == "false":
        return False
    if s == "⊥":
        return None  # bottom
    try:
        return int(s)
    except ValueError:
        try:
            return float(s)
        except ValueError:
            return s


# ─── Expression Evaluator (⊢= bodies) ───────────────────────────

def eval_hard_expression(expr: str, bindings: dict[str, Any]) -> Any:
    """Evaluate a ⊢= expression with resolved bindings.

    Handles:
    - name ← expression (binding form)
    - String concatenation with +
    - Arithmetic: +, -, *, /
    - Comparison: =, !=, <, >, <=, >=
    - eval(arithmetic) for evaluation context
    - cell→field references (substituted from bindings)
    """
    # Handle binding form: name ← expression
    m = re.match(r'^(\w[\w-]*)\s*←\s*(.+)$', expr, re.DOTALL)
    if m:
        result_name = m.group(1)
        inner_expr = m.group(2).strip()
        return eval_hard_expression(inner_expr, bindings)

    # Substitute cell→field references with their values
    resolved = _substitute_refs(expr, bindings)

    # Try Python eval with safe namespace
    py_expr = _cell_to_python(resolved, bindings)
    try:
        result = eval(py_expr, {"__builtins__": {}}, _safe_namespace(bindings))
        return result
    except Exception as e:
        print(f"  [WARN] Expression eval failed: {py_expr}")
        print(f"         Error: {e}")
        return None


def _substitute_refs(expr: str, bindings: dict[str, Any]) -> str:
    """Replace cell→field references with placeholder variable names."""
    # Replace cell→field with __ref_cell_field
    def ref_replacer(m):
        ref = m.group(0)
        if ref in bindings:
            val = bindings[ref]
            if isinstance(val, str):
                # Use repr() for reliable escaping of all special chars
                return repr(val)
            if isinstance(val, list):
                return repr(val)
            return repr(val)
        return ref
    return re.sub(r'[\w-]+→[\w-]+', ref_replacer, expr)


def _cell_to_python(expr: str, bindings: dict[str, Any]) -> str:
    """Convert Cell expression syntax to Python."""
    result = expr

    # eval(expr) → just evaluate the inner expression
    result = re.sub(r'\beval\(', '(', result)

    # Handle = as equality (but not == or !=, <=, >=)
    # Only replace standalone = not preceded/followed by other operators
    result = re.sub(r'(?<![!<>=])=(?!=)', '==', result)

    # true/false → True/False
    result = re.sub(r'\btrue\b', 'True', result)
    result = re.sub(r'\bfalse\b', 'False', result)

    # Handle \n in string concatenation → actual newlines in strings
    # (already handled by Python string literals)

    return result


def _safe_namespace(bindings: dict[str, Any]) -> dict[str, Any]:
    """Build safe namespace for eval with string/list operations."""
    ns = {}
    # Add plain name bindings (without → characters)
    for k, v in bindings.items():
        safe_k = k.replace("→", "_").replace("-", "_")
        ns[safe_k] = v
    # Add builtins for expression language
    ns["len"] = len
    ns["split"] = lambda s, d: s.split(d) if isinstance(s, str) else []
    ns["join"] = lambda lst, d: d.join(lst) if isinstance(lst, list) else ""
    ns["contains"] = lambda s, sub: sub in s if isinstance(s, str) else False
    ns["length"] = len
    ns["sort"] = sorted
    ns["min"] = min
    ns["max"] = max
    ns["sum"] = sum
    ns["True"] = True
    ns["False"] = False
    return ns


# ─── LLM Interface ───────────────────────────────────────────────

class LLMClient:
    """Wrapper for Anthropic API calls."""

    def __init__(self, spec_text: str, dry_run: bool = False):
        self.spec_text = spec_text
        self.dry_run = dry_run
        self.call_count = 0
        if not dry_run:
            self.client = __import__("anthropic").Anthropic()

    def eval_soft_cell(self, cell: Cell, bindings: dict[str, Any]) -> dict[str, Any]:
        """Evaluate a soft cell by sending to LLM. Returns yield values."""
        self.call_count += 1

        # Interpolate «» references in the body
        body = self._interpolate(cell.body, bindings)

        prompt = self._build_eval_prompt(cell, bindings, body)

        if self.dry_run:
            print(f"\n  [DRY-RUN] LLM prompt for '{cell.name}':")
            print(f"  {body[:200]}...")
            return {name: f"<dry-run-{cell.name}-{name}>" for name in cell.yield_names}

        response = self.client.messages.create(
            model="claude-haiku-4-5-20251001",
            max_tokens=1024,
            system=self._system_prompt(),
            messages=[{"role": "user", "content": prompt}],
        )

        return self._parse_yields(response.content[0].text, cell.yield_names)

    def check_oracle(self, oracle: Oracle, cell_name: str,
                     outputs: dict[str, Any], bindings: dict[str, Any]) -> tuple[bool, str]:
        """Check a semantic oracle assertion. Returns (pass, reasoning)."""
        self.call_count += 1

        # Check if oracle is deterministic (exact value check)
        det_result = self._check_deterministic_oracle(oracle.text, outputs, bindings)
        if det_result is not None:
            self.call_count -= 1  # Didn't actually call LLM
            return det_result

        if self.dry_run:
            print(f"  [DRY-RUN] Oracle check: {oracle.text}")
            return (True, "dry-run: assumed pass")

        prompt = self._build_oracle_prompt(oracle, cell_name, outputs, bindings)

        response = self.client.messages.create(
            model="claude-haiku-4-5-20251001",
            max_tokens=256,
            messages=[{"role": "user", "content": prompt}],
        )

        text = response.content[0].text.strip()
        passed = text.upper().startswith("PASS")
        return (passed, text)

    def _check_deterministic_oracle(self, oracle_text: str,
                                     outputs: dict[str, Any],
                                     bindings: dict[str, Any]) -> tuple[bool, str] | None:
        """Try to check oracle deterministically. Returns None if semantic."""
        # Pattern: "field = value"
        m = re.match(r'^(\w[\w-]*)\s*=\s*(.+)$', oracle_text)
        if m:
            field = m.group(1)
            expected = _parse_value(m.group(2).strip())
            actual = outputs.get(field)
            if actual is not None and expected is not None:
                passed = actual == expected
                reason = f"deterministic: {actual!r} {'==' if passed else '!='} {expected!r}"
                return (passed, reason)

        # Pattern: field contains "literal" (only with quoted literal)
        m = re.match(r'^(\w[\w-]*)\s+contains\s+"([^"]+)"$', oracle_text)
        if m:
            field = m.group(1)
            substr = m.group(2)
            actual = outputs.get(field)
            if actual is not None and isinstance(actual, str):
                passed = substr in actual
                return (passed, f"deterministic: contains check")

        return None  # Can't check deterministically

    def _interpolate(self, text: str, bindings: dict[str, Any]) -> str:
        """Replace «name» and «cell→field» with actual values."""
        if text is None:
            return ""
        def replacer(m):
            ref = m.group(1)
            if ref in bindings:
                val = bindings[ref]
                return str(val) if val is not None else "⊥"
            # Try plain name
            for k, v in bindings.items():
                if k.endswith(f"→{ref}") or k == ref:
                    return str(v) if v is not None else "⊥"
            return f"«{ref}»"  # Leave unresolved
        return re.sub(r'«([^»]+)»', replacer, text)

    def _system_prompt(self) -> str:
        return (
            "You are a Cell program executor. You evaluate cells by following "
            "their ∴ (therefore) instructions precisely. Respond ONLY with a "
            "JSON object mapping yield field names to their values. No markdown, "
            "no explanation, no code fences — just the JSON object."
        )

    def _build_eval_prompt(self, cell: Cell, bindings: dict[str, Any], body: str) -> str:
        parts = [f"Evaluate this Cell:\n\nCell: {cell.name}"]
        parts.append("\nInputs:")
        for g in cell.givens:
            val = bindings.get(g.name) or bindings.get(f"{g.source_cell}→{g.source_field}")
            parts.append(f"  {g.name} = {json.dumps(val)}")
        parts.append(f"\nTask:\n{body}")
        parts.append(f"\nProduce values for: {', '.join(cell.yield_names)}")
        field_hints = ", ".join(f'"{n}": ...' for n in cell.yield_names)
        parts.append(f"\nRespond with JSON: {{{field_hints}}}")
        return "\n".join(parts)

    def _build_oracle_prompt(self, oracle: Oracle, cell_name: str,
                              outputs: dict[str, Any],
                              bindings: dict[str, Any]) -> str:
        parts = [f"Check this oracle assertion on cell '{cell_name}':\n"]
        parts.append("Outputs:")
        for k, v in outputs.items():
            parts.append(f"  {k} = {json.dumps(v)}")
        if bindings:
            parts.append("\nInputs (context):")
            for k, v in bindings.items():
                if "→" not in k:
                    parts.append(f"  {k} = {json.dumps(v)}")
        parts.append(f"\nAssertion: {oracle.text}")
        parts.append("\nDoes the output satisfy this assertion?")
        parts.append("Respond with exactly PASS or FAIL on the first line, then a brief explanation.")
        return "\n".join(parts)

    def _parse_yields(self, response: str, yield_names: list[str]) -> dict[str, Any]:
        """Parse LLM response into yield values."""
        # Strip any markdown code fences
        text = response.strip()
        text = re.sub(r'^```\w*\n?', '', text)
        text = re.sub(r'\n?```$', '', text)
        text = text.strip()

        try:
            data = json.loads(text)
            if isinstance(data, dict):
                return {k: data[k] for k in yield_names if k in data}
        except json.JSONDecodeError:
            pass

        # Fallback: if single yield, use entire response
        if len(yield_names) == 1:
            return {yield_names[0]: text}

        print(f"  [WARN] Could not parse LLM response as JSON: {text[:100]}...")
        return {name: text for name in yield_names}


class SimulatedLLMClient(LLMClient):
    """LLM client that uses pre-recorded responses for validation."""

    def __init__(self, responses: dict[str, dict[str, Any]], spec_text: str = ""):
        super().__init__(spec_text=spec_text, dry_run=True)
        self.responses = responses  # cell_name -> {field: value}

    def eval_soft_cell(self, cell: Cell, bindings: dict[str, Any]) -> dict[str, Any]:
        self.call_count += 1
        if cell.name in self.responses:
            outputs = self.responses[cell.name]
            return {k: outputs[k] for k in cell.yield_names if k in outputs}
        print(f"  [SIM] No response for '{cell.name}' — using placeholder")
        return {n: f"<sim-{cell.name}-{n}>" for n in cell.yield_names}

    def check_oracle(self, oracle: Oracle, cell_name: str,
                     outputs: dict[str, Any], bindings: dict[str, Any]) -> tuple[bool, str]:
        self.call_count += 1
        # Try deterministic check first
        det = self._check_deterministic_oracle(oracle.text, outputs, bindings)
        if det is not None:
            self.call_count -= 1
            return det
        # For semantic oracles in simulation, assume pass
        return (True, "simulated: assumed pass")


# ─── Eval-One Loop ────────────────────────────────────────────────

def render_cell_state(cell: Cell, cells: dict[str, Cell]) -> str:
    """Render a single cell as pure Cell text showing current state."""
    lines = []

    # Turnstile + name
    frozen_mark = ""
    if cell.is_bottom:
        frozen_mark = "  -- ⊥"
    lines.append(f"{cell.turnstile} {cell.name}{frozen_mark}")

    # Givens (with resolved values if available)
    for g in cell.givens:
        prefix = "given?" if g.optional else "given"
        if g.is_dependency:
            ref = f"{g.source_cell}→{g.source_field}"
            if cell.frozen or cell.is_bottom:
                # Show resolved value
                src = cells.get(g.source_cell)
                if src and g.source_field in src.yield_values:
                    val = src.yield_values[g.source_field]
                    val_str = _format_value(val)
                    guard = f" where {g.guard_expr}" if g.guard_expr else ""
                    lines.append(f"  {prefix} {ref} ≡ {val_str}{guard}")
                else:
                    lines.append(f"  {prefix} {ref}")
            else:
                guard = f" where {g.guard_expr}" if g.guard_expr else ""
                lines.append(f"  {prefix} {ref}{guard}")
        elif g.has_default:
            val_str = _format_value(g.default)
            lines.append(f"  {prefix} {g.name} ≡ {val_str}")
        else:
            lines.append(f"  {prefix} {g.name}")

    # Yields (with values if frozen)
    yield_parts = []
    for yname in cell.yield_names:
        if yname in cell.yield_values:
            val_str = _format_value(cell.yield_values[yname])
            yield_parts.append(f"{yname} ≡ {val_str}")
        else:
            yield_parts.append(yname)
    if yield_parts:
        lines.append(f"  yield {', '.join(yield_parts)}")

    # Body
    if cell.body_type == "soft" and cell.body:
        lines.append("")
        lines.append(f"  ∴ {cell.body}")
    elif cell.body_type == "hard" and cell.body:
        lines.append("")
        lines.append(f"  ⊢= {cell.body}")

    # Oracles (with results if frozen)
    if cell.oracles:
        lines.append("")
        for o in cell.oracles:
            if hasattr(o, "result"):
                mark = "✓" if o.result else "✗"
                lines.append(f"  ⊨ {o.text} → {mark}")
            else:
                lines.append(f"  ⊨ {o.text}")

    return "\n".join(lines)


def render_program_state(cells: dict[str, Cell], step: int,
                         evaluated: str | None = None,
                         ready_set: list[str] | None = None) -> str:
    """Render the complete program as pure Cell showing current state."""
    lines = []
    lines.append(f"-- frame {step}")
    if evaluated:
        lines.append(f"-- evaluated: {evaluated}")
    if ready_set:
        lines.append(f"-- ready: {{ {', '.join(ready_set)} }}")

    frozen_names = [n for n, c in cells.items() if c.frozen]
    blocked_names = [n for n, c in cells.items() if not c.frozen and not c.is_bottom]
    if frozen_names:
        lines.append(f"-- frozen: {{ {', '.join(frozen_names)} }}")
    if blocked_names:
        lines.append(f"-- blocked: {{ {', '.join(blocked_names)} }}")

    lines.append("")
    for name in cells:
        lines.append(render_cell_state(cells[name], cells))
        lines.append("")

    return "\n".join(lines)


def _format_value(val: Any) -> str:
    """Format a value for Cell output."""
    if val is None:
        return "⊥"
    if isinstance(val, bool):
        return "true" if val else "false"
    if isinstance(val, str):
        return f'"{val}"'
    if isinstance(val, list):
        items = ", ".join(_format_value(v) for v in val)
        return f"[{items}]"
    return str(val)


def eval_one_loop(cells_list: list[Cell], llm: LLMClient) -> list[str]:
    """Run eval-one loop to quiescence. Returns list of frame texts (pure Cell)."""
    cells = {c.name: c for c in cells_list}
    frames: list[str] = []
    step = 0
    max_steps = 50  # Safety limit

    # Record initial state (h0)
    ready = [n for n, c in cells.items() if c.is_ready(cells)]
    frames.append(render_program_state(cells, step, ready_set=ready))

    print(f"\n{'='*60}")
    print(f"EVAL-ONE LOOP — {len(cells)} cells")
    print(f"{'='*60}")
    print(f"\nFrame h{step}: initial state")
    print(f"  Ready set: {{ {', '.join(ready)} }}")

    while step < max_steps:
        # Find ready cells
        ready = [n for n, c in cells.items() if c.is_ready(cells)]
        if not ready:
            print(f"\n  No ready cells — QUIESCE")
            break

        # Pick one cell (first in ready set)
        picked = ready[0]
        cell = cells[picked]
        step += 1

        print(f"\nFrame h{step}: evaluate '{picked}' ({cell.turnstile}, {cell.body_type})")
        print(f"  Ready set was: {{ {', '.join(ready)} }}")

        # Resolve bindings
        bindings = cell.get_bindings(cells)
        for k, v in bindings.items():
            if "→" not in k:
                print(f"  Input: {k} = {_format_value(v)}")

        # Evaluate
        outputs = {}
        if cell.body_type == "passthrough":
            # Pass-through: yield values come from givens with same name
            for yname in cell.yield_names:
                if yname in bindings:
                    outputs[yname] = bindings[yname]
            print(f"  Passthrough: {outputs}")

        elif cell.body_type == "hard":
            # Deterministic evaluation
            result = eval_hard_expression(cell.body, bindings)
            if len(cell.yield_names) == 1:
                outputs[cell.yield_names[0]] = result
            elif isinstance(result, dict):
                outputs = result
            else:
                outputs[cell.yield_names[0]] = result
            print(f"  Hard eval: {_format_value(result)}")

        elif cell.body_type == "soft":
            # LLM evaluation
            outputs = llm.eval_soft_cell(cell, bindings)
            for k, v in outputs.items():
                preview = str(v)[:80]
                print(f"  Soft eval → {k} = {preview}...")

        elif cell.body_type == "spawner":
            print(f"  [SKIP] Spawner cells not yet implemented")
            continue

        # Check oracles
        all_pass = True
        for oracle in cell.oracles:
            passed, reason = llm.check_oracle(oracle, cell.name, outputs, bindings)
            oracle.result = passed
            mark = "✓" if passed else "✗"
            print(f"  Oracle: ⊨ {oracle.text} → {mark} ({reason[:60]})")
            if not passed:
                all_pass = False

        # Freeze or bottom
        if all_pass:
            cell.frozen = True
            cell.yield_values = outputs
            print(f"  → FREEZE")
        else:
            # No retry in minimal version → bottom
            cell.is_bottom = True
            print(f"  → ⊥ (oracle failed, no retry)")

        # Record frame
        new_ready = [n for n, c in cells.items() if c.is_ready(cells)]
        frames.append(render_program_state(cells, step, evaluated=picked, ready_set=new_ready))

    # Summary
    frozen_count = sum(1 for c in cells.values() if c.frozen)
    bottom_count = sum(1 for c in cells.values() if c.is_bottom)
    print(f"\n{'='*60}")
    print(f"QUIESCENCE after {step} steps")
    print(f"  Frozen: {frozen_count}/{len(cells)}")
    print(f"  Bottom: {bottom_count}/{len(cells)}")
    print(f"  LLM calls: {llm.call_count}")
    print(f"{'='*60}")

    return frames


# ─── Main ─────────────────────────────────────────────────────────

def main():
    if len(sys.argv) < 2:
        print("Usage: eval_one.py <program.cell> [--spec path] [--dry-run] [--simulate file] [--output-dir dir]")
        sys.exit(1)

    program_path = Path(sys.argv[1])
    spec_path = None
    dry_run = "--dry-run" in sys.argv
    simulate_path = None
    output_dir = None

    for i, arg in enumerate(sys.argv[2:], 2):
        if arg == "--spec" and i + 1 < len(sys.argv):
            spec_path = Path(sys.argv[i + 1])
        if arg == "--output-dir" and i + 1 < len(sys.argv):
            output_dir = Path(sys.argv[i + 1])
        if arg == "--simulate" and i + 1 < len(sys.argv):
            simulate_path = Path(sys.argv[i + 1])

    if not program_path.exists():
        print(f"Error: {program_path} not found")
        sys.exit(1)

    # Load spec
    spec_text = ""
    if spec_path and spec_path.exists():
        spec_text = spec_path.read_text()

    # Parse program
    program_text = program_path.read_text()
    cells = parse_cell_file(program_text)

    print(f"Parsed {len(cells)} cells from {program_path.name}:")
    for c in cells:
        gs = len(c.givens)
        ys = len(c.yield_names)
        os_ = len(c.oracles)
        print(f"  {c.turnstile} {c.name}: {gs} givens, {ys} yields, {os_} oracles, body={c.body_type}")

    # Create LLM client
    if simulate_path:
        responses = json.loads(simulate_path.read_text())
        llm = SimulatedLLMClient(responses=responses, spec_text=spec_text)
        print(f"\nUsing simulated responses from {simulate_path}")
    elif dry_run or not os.environ.get("ANTHROPIC_API_KEY"):
        if not dry_run:
            print("No ANTHROPIC_API_KEY set — running in dry-run mode")
        llm = LLMClient(spec_text=spec_text, dry_run=True)
    else:
        llm = LLMClient(spec_text=spec_text, dry_run=False)

    # Run eval-one loop
    frames = eval_one_loop(cells, llm)

    # Write frames to files
    if output_dir:
        output_dir = Path(output_dir)
        output_dir.mkdir(parents=True, exist_ok=True)
    else:
        output_dir = program_path.parent / f"{program_path.stem}-frames"
        output_dir.mkdir(parents=True, exist_ok=True)

    for i, frame in enumerate(frames):
        frame_path = output_dir / f"h{i}.cell"
        frame_path.write_text(frame + "\n")
        print(f"Wrote {frame_path}")

    print(f"\nDone. {len(frames)} frames written to {output_dir}/")


if __name__ == "__main__":
    main()
