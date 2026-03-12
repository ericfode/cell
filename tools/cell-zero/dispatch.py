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

    ns = {}
    for k, v in bindings.items():
        safe_k = k.replace("→", "_").replace("-", "_")
        ns[safe_k] = v
    ns.update({"len": len, "split": lambda s, d: s.split(d),
               "join": lambda lst, d: d.join(lst), "min": min, "max": max,
               "sum": sum, "sorted": sorted, "True": True, "False": False})

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
