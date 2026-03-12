#!/usr/bin/env python3
"""dispatch.py: Evaluate a cell (soft or hard) and return outputs.

Usage:
    python dispatch.py <state-dir> <cell-name> [--dry-run] [--simulate <file>]

Outputs JSON object mapping yield names to values.
- Soft cells (∴): calls Anthropic API (or dry-run/simulate)
- Hard cells (⊢=): evaluates deterministically
- Passthrough cells: passes given values through
"""

from __future__ import annotations

import json
import os
import re
import sys
from pathlib import Path


def load_cells(state_dir: Path) -> dict[str, dict]:
    """Load all cell JSON files from state directory."""
    meta = json.loads((state_dir / "_meta.json").read_text())
    cells = {}
    for name in meta["cell_order"]:
        cells[name] = json.loads((state_dir / f"{name}.json").read_text())
    return cells


def resolve_bindings(cell: dict, cells: dict[str, dict]) -> dict[str, any]:
    """Resolve all givens to concrete values."""
    bindings = {}
    for g in cell["givens"]:
        if g.get("has_default"):
            bindings[g["name"]] = g["default"]
            if g.get("source_cell"):
                bindings[f"{g['source_cell']}→{g['source_field']}"] = g["default"]
        elif g.get("source_cell"):
            src = cells.get(g["source_cell"])
            if src and g["source_field"] in src["yield_values"]:
                val = src["yield_values"][g["source_field"]]
                bindings[g["name"]] = val
                bindings[f"{g['source_cell']}→{g['source_field']}"] = val
            elif g.get("optional") and src and src["is_bottom"]:
                bindings[g["name"]] = None  # ⊥
                bindings[f"{g['source_cell']}→{g['source_field']}"] = None
    return bindings


def interpolate(text: str, bindings: dict[str, any]) -> str:
    """Replace «name» and «cell→field» with actual values."""
    if not text:
        return ""
    def replacer(m):
        ref = m.group(1)
        if ref in bindings:
            val = bindings[ref]
            return str(val) if val is not None else "⊥"
        for k, v in bindings.items():
            if k.endswith(f"→{ref}") or k == ref:
                return str(v) if v is not None else "⊥"
        return f"«{ref}»"
    return re.sub(r'«([^»]+)»', replacer, text)


# ─── If/then/else converter ──────────────────────────────────────

def _convert_if_then_else(expr: str) -> str:
    """Convert Cell if/then/else to Python ternary, handling nesting."""
    # Find the first 'if' keyword (word boundary)
    m = re.search(r'\bif\b', expr)
    if not m:
        return expr

    start = m.start()
    rest = expr[m.end():]

    # Find matching 'then' (not nested)
    then_pos = _find_keyword(rest, 'then')
    if then_pos is None:
        return expr

    cond = rest[:then_pos].strip()
    after_then = rest[then_pos + 4:].strip()

    # Find matching 'else' — skip nested if/then/else
    else_pos = _find_top_else(after_then)
    if else_pos is None:
        return expr

    then_branch = after_then[:else_pos].strip()
    else_branch = after_then[else_pos + 4:].strip()

    # Recursively convert branches
    then_py = _convert_if_then_else(then_branch)
    else_py = _convert_if_then_else(else_branch)

    converted = f"(({then_py}) if ({cond}) else ({else_py}))"
    return expr[:start] + converted


def _find_keyword(text: str, kw: str) -> int | None:
    """Find keyword at word boundary, not inside strings."""
    pat = re.compile(r'\b' + kw + r'\b')
    m = pat.search(text)
    return m.start() if m else None


def _find_top_else(text: str) -> int | None:
    """Find the 'else' that matches the current if, skipping nested if/then/else."""
    depth = 0
    i = 0
    while i < len(text):
        # Check for 'if' keyword (increases nesting)
        if text[i:].startswith('if') and (i == 0 or not text[i-1].isalnum()) and (i + 2 >= len(text) or not text[i+2].isalnum()):
            depth += 1
            i += 2
            continue
        # Check for 'else' keyword
        if text[i:].startswith('else') and (i == 0 or not text[i-1].isalnum()) and (i + 4 >= len(text) or not text[i+4].isalnum()):
            if depth == 0:
                return i
            depth -= 1
            i += 4
            continue
        # Skip strings
        if text[i] == '"':
            i += 1
            while i < len(text) and text[i] != '"':
                i += 1
            i += 1
            continue
        i += 1
    return None


# ─── Hard expression evaluator ───────────────────────────────────

def eval_hard(expr: str, bindings: dict[str, any]) -> any:
    """Evaluate a ⊢= expression."""
    # Handle binding form: name ← expression
    m = re.match(r'^(\w[\w-]*)\s*←\s*(.+)$', expr, re.DOTALL)
    if m:
        return eval_hard(m.group(2).strip(), bindings)

    # Substitute cell→field references
    resolved = expr
    for ref, val in bindings.items():
        if "→" in ref:
            resolved = resolved.replace(ref, repr(val))

    # Convert to Python
    py_expr = resolved
    py_expr = re.sub(r'\beval\(', '(', py_expr)
    py_expr = re.sub(r'(?<![!<>=])=(?!=)', '==', py_expr)
    py_expr = re.sub(r'\btrue\b', 'True', py_expr)
    py_expr = re.sub(r'\bfalse\b', 'False', py_expr)

    # Convert Cell if/then/else to Python ternary (recursive)
    py_expr = _convert_if_then_else(py_expr)

    # Replace hyphenated binding names with underscored Python identifiers
    for k in bindings:
        if "-" in k and "→" not in k:
            safe = k.replace("-", "_")
            py_expr = re.sub(r'\b' + re.escape(k) + r'\b', safe, py_expr)

    ns = {}
    for k, v in bindings.items():
        safe_k = k.replace("→", "_").replace("-", "_")
        ns[safe_k] = v
    ns.update({"len": len, "length": len, "split": lambda s, d: s.split(d),
               "join": lambda lst, d: d.join(lst), "min": min, "max": max,
               "sum": sum, "sorted": sorted, "True": True, "False": False,
               "abs": abs, "upper": lambda s: s.upper(), "lower": lambda s: s.lower(),
               "str": str, "int": int, "float": float,
               "reversed": lambda x: list(reversed(x)),
               "filter": lambda lst, fn: [x for x in lst if fn(x)],
               "map": lambda lst, fn: [fn(x) for x in lst],
               "contains": lambda s, sub: sub in s,
               "starts_with": lambda s, p: s.startswith(p),
               "ends_with": lambda s, p: s.endswith(p),
               "trim": lambda s: s.strip(),
               "concat": lambda a, b: a + b,
               "flatten": lambda lst: [x for sub in lst for x in sub],
               "zip": lambda a, b: list(zip(a, b)),
               "any": any, "all": all, "count": lambda lst, fn: sum(1 for x in lst if fn(x)),
               "range": range, "list": list,
               "None": None,
               })

    try:
        return eval(py_expr, {"__builtins__": {}}, ns)
    except Exception as e:
        print(f"WARN: eval failed: {py_expr} — {e}", file=sys.stderr)
        return None


# ─── Soft cell evaluator (Anthropic API) ─────────────────────────

def eval_soft(cell: dict, bindings: dict[str, any], dry_run: bool = False,
              simulate: dict | None = None) -> dict[str, any]:
    """Evaluate a soft cell via LLM."""
    body = interpolate(cell["body"], bindings)
    yield_names = cell["yield_names"]

    # Simulation mode
    if simulate and cell["name"] in simulate:
        return {k: simulate[cell["name"]][k] for k in yield_names
                if k in simulate[cell["name"]]}

    # Dry-run mode
    if dry_run:
        return {n: f"<dry-run-{cell['name']}-{n}>" for n in yield_names}

    # Live API call
    import anthropic
    client = anthropic.Anthropic()

    prompt_parts = [f"Evaluate this Cell:\n\nCell: {cell['name']}"]
    prompt_parts.append("\nInputs:")
    for g in cell["givens"]:
        key = g["name"]
        val = bindings.get(key)
        prompt_parts.append(f"  {key} = {json.dumps(val)}")
    prompt_parts.append(f"\nTask:\n{body}")
    prompt_parts.append(f"\nProduce values for: {', '.join(yield_names)}")
    field_hints = ", ".join(f'"{n}": ...' for n in yield_names)
    prompt_parts.append(f"\nRespond with JSON only: {{{field_hints}}}")

    response = client.messages.create(
        model="claude-haiku-4-5-20251001",
        max_tokens=1024,
        system="You are a Cell program executor. Evaluate cells by following "
               "their ∴ instructions precisely. Respond ONLY with a JSON object "
               "mapping yield field names to values. No markdown, no explanation.",
        messages=[{"role": "user", "content": "\n".join(prompt_parts)}],
    )

    text = response.content[0].text.strip()
    text = re.sub(r'^```\w*\n?', '', text)
    text = re.sub(r'\n?```$', '', text)
    text = text.strip()

    try:
        data = json.loads(text)
        if isinstance(data, dict):
            return {k: data[k] for k in yield_names if k in data}
    except json.JSONDecodeError:
        pass

    if len(yield_names) == 1:
        return {yield_names[0]: text}
    return {n: text for n in yield_names}


def main():
    if len(sys.argv) < 3:
        print("Usage: dispatch.py <state-dir> <cell-name> [--dry-run] [--simulate file]",
              file=sys.stderr)
        sys.exit(1)

    state_dir = Path(sys.argv[1])
    cell_name = sys.argv[2]
    dry_run = "--dry-run" in sys.argv
    simulate = None

    for i, arg in enumerate(sys.argv):
        if arg == "--simulate" and i + 1 < len(sys.argv):
            simulate = json.loads(Path(sys.argv[i + 1]).read_text())

    cells = load_cells(state_dir)
    cell = cells[cell_name]
    bindings = resolve_bindings(cell, cells)

    if cell["body_type"] == "hard":
        result = eval_hard(cell["body"], bindings)
        if len(cell["yield_names"]) == 1:
            outputs = {cell["yield_names"][0]: result}
        elif isinstance(result, dict):
            outputs = result
        else:
            outputs = {cell["yield_names"][0]: result}

    elif cell["body_type"] == "soft":
        if not dry_run and not os.environ.get("ANTHROPIC_API_KEY"):
            dry_run = True
            print("WARN: no ANTHROPIC_API_KEY, using dry-run", file=sys.stderr)
        outputs = eval_soft(cell, bindings, dry_run=dry_run, simulate=simulate)

    elif cell["body_type"] == "passthrough":
        outputs = {}
        for yname in cell["yield_names"]:
            if yname in bindings:
                outputs[yname] = bindings[yname]

    else:
        print(f"ERROR: unsupported body_type: {cell['body_type']}", file=sys.stderr)
        sys.exit(1)

    print(json.dumps(outputs, ensure_ascii=False))


if __name__ == "__main__":
    main()
