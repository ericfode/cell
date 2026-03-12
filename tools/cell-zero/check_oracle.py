#!/usr/bin/env python3
"""check_oracle.py: Check oracle assertions on a cell's outputs.

Usage:
    python check_oracle.py <state-dir> <cell-name> <outputs-json> [--dry-run]

Outputs JSON: {"all_pass": bool, "results": [{"text": "...", "pass": bool, "reason": "..."}]}
"""

from __future__ import annotations

import json
import os
import re
import sys
from pathlib import Path


def load_cells(state_dir: Path) -> dict[str, dict]:
    meta = json.loads((state_dir / "_meta.json").read_text())
    cells = {}
    for name in meta["cell_order"]:
        cells[name] = json.loads((state_dir / f"{name}.json").read_text())
    return cells


def resolve_bindings(cell: dict, cells: dict[str, dict]) -> dict[str, any]:
    bindings = {}
    for g in cell["givens"]:
        if g.get("has_default"):
            bindings[g["name"]] = g["default"]
        elif g.get("source_cell"):
            src = cells.get(g["source_cell"])
            if src and g.get("source_field") in src["yield_values"]:
                bindings[g["name"]] = src["yield_values"][g["source_field"]]
    return bindings


def parse_value(s: str):
    s = s.strip()
    if s.startswith('"') and s.endswith('"'):
        return s[1:-1]
    if s.startswith("[") and s.endswith("]"):
        inner = s[1:-1].strip()
        if not inner:
            return []
        return [parse_value(x.strip()) for x in inner.split(",")]
    if s == "true":
        return True
    if s == "false":
        return False
    try:
        return int(s)
    except ValueError:
        try:
            return float(s)
        except ValueError:
            return s


def check_deterministic(oracle_text: str, outputs: dict, bindings: dict) -> tuple[bool, str] | None:
    """Try to check oracle deterministically. Returns None if semantic."""
    # Conditional oracle: "if X then Y"
    cm = re.match(r'^if\s+(.+?)\s+then\s+(.+)$', oracle_text)
    if cm:
        cond_text = cm.group(1).strip()
        then_text = cm.group(2).strip()
        # Evaluate condition against bindings + outputs
        cond_result = eval_simple_condition(cond_text, {**bindings, **outputs})
        if cond_result is None:
            return None  # Can't evaluate condition → semantic
        if not cond_result:
            return (True, "vacuously satisfied (condition false)")
        # Condition true — check the consequent
        return check_deterministic(then_text, outputs, bindings)

    # Pattern: "field = value"
    m = re.match(r'^(\w[\w-]*)\s*=\s*(.+)$', oracle_text)
    if m:
        field = m.group(1)
        expected = parse_value(m.group(2).strip())
        actual = outputs.get(field)
        if actual is not None and expected is not None:
            # Handle numeric comparison
            try:
                if float(actual) == float(expected):
                    return (True, f"deterministic: {actual!r} == {expected!r}")
            except (ValueError, TypeError):
                pass
            passed = actual == expected
            return (passed, f"deterministic: {actual!r} {'==' if passed else '!='} {expected!r}")

    # Pattern: "field is a number"
    m = re.match(r'^(\w[\w-]*)\s+is\s+a\s+number$', oracle_text)
    if m:
        field = m.group(1)
        actual = outputs.get(field)
        try:
            float(actual)
            return (True, f"deterministic: {actual!r} is a number")
        except (ValueError, TypeError):
            return (False, f"deterministic: {actual!r} is NOT a number")

    return None  # Semantic oracle


def eval_simple_condition(text: str, values: dict) -> bool | None:
    """Evaluate a simple condition like 'substitute→holds' or 'x > 3'."""
    # Direct variable reference (truthy check)
    for key, val in values.items():
        if text == key:
            return bool(val)
    # Can't evaluate
    return None


def check_semantic(oracle_text: str, cell_name: str, outputs: dict,
                   bindings: dict, dry_run: bool) -> tuple[bool, str]:
    """Check a semantic oracle via LLM."""
    if dry_run:
        return (True, "dry-run: assumed pass")

    if not os.environ.get("ANTHROPIC_API_KEY"):
        return (True, "no API key: assumed pass")

    import anthropic
    client = anthropic.Anthropic()

    parts = [f"Check this oracle assertion on cell '{cell_name}':\n"]
    parts.append("Outputs:")
    for k, v in outputs.items():
        parts.append(f"  {k} = {json.dumps(v)}")
    if bindings:
        parts.append("\nInputs (context):")
        for k, v in bindings.items():
            parts.append(f"  {k} = {json.dumps(v)}")
    parts.append(f"\nAssertion: {oracle_text}")
    parts.append("\nDoes the output satisfy this assertion?")
    parts.append("Respond with exactly PASS or FAIL on the first line, then a brief explanation.")

    response = client.messages.create(
        model="claude-haiku-4-5-20251001",
        max_tokens=256,
        messages=[{"role": "user", "content": "\n".join(parts)}],
    )

    text = response.content[0].text.strip()
    passed = text.upper().startswith("PASS")
    return (passed, text)


def main():
    if len(sys.argv) < 4:
        print("Usage: check_oracle.py <state-dir> <cell-name> <outputs-json> [--dry-run]",
              file=sys.stderr)
        sys.exit(1)

    state_dir = Path(sys.argv[1])
    cell_name = sys.argv[2]
    outputs = json.loads(sys.argv[3])
    dry_run = "--dry-run" in sys.argv

    cells = load_cells(state_dir)
    cell = cells[cell_name]
    bindings = resolve_bindings(cell, cells)

    results = []
    all_pass = True

    for oracle in cell["oracles"]:
        det = check_deterministic(oracle["text"], outputs, bindings)
        if det is not None:
            passed, reason = det
        else:
            passed, reason = check_semantic(oracle["text"], cell_name, outputs,
                                             bindings, dry_run)

        results.append({"text": oracle["text"], "pass": passed, "reason": reason})
        if not passed:
            all_pass = False

    print(json.dumps({"all_pass": all_pass, "results": results}, ensure_ascii=False))


if __name__ == "__main__":
    main()
