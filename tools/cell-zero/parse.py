#!/usr/bin/env python3
"""parse.py: Parse a .cell file into JSON cell files in a state directory.

Usage:
    python parse.py <program.cell> <state-dir>

Creates one JSON file per cell in <state-dir>/, plus _meta.json.
"""

from __future__ import annotations

import json
import os
import re
import sys
from pathlib import Path


def parse_given(text: str, optional: bool) -> dict:
    """Parse the rest of a given clause after 'given' keyword."""
    guard = None
    wm = re.search(r'\s+where\s+(.+)$', text)
    if wm:
        guard = wm.group(1).strip()
        text = text[:wm.start()]

    dm = re.match(r'^(\S+)\s*≡\s*(.+)$', text)
    if dm:
        name = dm.group(1)
        val = parse_value(dm.group(2).strip())
        if "→" in name:
            parts = name.split("→", 1)
            return {
                "name": parts[1], "source_cell": parts[0],
                "source_field": parts[1], "default": val,
                "has_default": True, "guard_expr": guard, "optional": optional,
            }
        return {
            "name": name, "default": val, "has_default": True,
            "guard_expr": guard, "optional": optional,
        }

    if "→" in text:
        parts = text.split("→", 1)
        field_part = parts[1].strip()
        # Handle "as alias" syntax: given cell→field as alias
        alias = None
        am = re.match(r'^(\S+)\s+as\s+(\S+)$', field_part)
        if am:
            field_part = am.group(1)
            alias = am.group(2)
        return {
            "name": alias or field_part, "source_cell": parts[0].strip(),
            "source_field": field_part, "has_default": False,
            "guard_expr": guard, "optional": optional,
        }

    name = text.strip()
    # §cell-name references (quotation) are metadata — always available
    is_quotation = name.startswith("§")
    return {"name": name, "has_default": is_quotation, "guard_expr": guard, "optional": optional,
            **({"default": name} if is_quotation else {})}


def parse_value(s: str):
    """Parse a literal value from Cell syntax."""
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
    if s == "⊥":
        return None
    try:
        return int(s)
    except ValueError:
        try:
            return float(s)
        except ValueError:
            return s


def parse_cell_file(text: str) -> list[dict]:
    """Parse a .cell file into a list of cell dicts."""
    cells = []
    current = None
    body_lines = []
    in_body = False

    for raw_line in text.split("\n"):
        line = raw_line.rstrip()
        stripped = line.lstrip()

        if not stripped or stripped.startswith("--"):
            if in_body and not stripped:
                body_lines.append("")
            continue

        # Cell declaration
        m = re.match(r'^(⊢⊢|⊢∘|⊢=|⊢)\s+(\S+)', stripped)
        if m:
            if current and in_body and body_lines:
                current["body"] = "\n".join(body_lines).strip()
            in_body = False
            body_lines = []

            ts = m.group(1)
            name = m.group(2)
            indent = len(line) - len(stripped)

            # ⊢= inside a cell body (not a new cell)
            if indent > 0 and current is not None and ts == "⊢=":
                expr_part = stripped[len("⊢= "):]
                current["body"] = expr_part
                current["body_type"] = "hard"
                continue

            current = {
                "name": name,
                "turnstile": ts,
                "givens": [],
                "yield_names": [],
                "body": None,
                "body_type": {"⊢=": "hard", "⊢⊢": "spawner", "⊢∘": "evolution"}.get(ts),
                "oracles": [],
                "recovery": None,
                "frozen": False,
                "yield_values": {},
                "is_bottom": False,
                "retries": 0,
                "max_retries": 3,
            }
            cells.append(current)
            continue

        if current is None:
            continue

        # given clause
        gm = re.match(r'^\s+(given\??)\s+(.+)', line)
        if gm:
            if in_body and body_lines:
                current["body"] = "\n".join(body_lines).strip()
                in_body = False
                body_lines = []
            optional = gm.group(1) == "given?"
            current["givens"].append(parse_given(gm.group(2).strip(), optional))
            continue

        # yield clause
        ym = re.match(r'^\s+yield\s+(.+)', line)
        if ym:
            if in_body and body_lines:
                current["body"] = "\n".join(body_lines).strip()
                in_body = False
                body_lines = []
            names = [n.strip().rstrip("[]") for n in ym.group(1).strip().split(",")]
            current["yield_names"].extend(names)
            continue

        # ∴ body
        if stripped.startswith("∴"):
            if in_body and body_lines:
                current["body"] = "\n".join(body_lines).strip()
            body_text = stripped[len("∴"):].strip()
            body_lines = [body_text] if body_text else []
            in_body = True
            current["body_type"] = "soft"
            continue

        # ⊨? recovery
        if stripped.startswith("⊨?"):
            if in_body and body_lines:
                current["body"] = "\n".join(body_lines).strip()
                in_body = False
                body_lines = []
            current["recovery"] = stripped[len("⊨?"):].strip()
            continue

        # ⊨ oracle
        if stripped.startswith("⊨"):
            if in_body and body_lines:
                current["body"] = "\n".join(body_lines).strip()
                in_body = False
                body_lines = []
            current["oracles"].append({"text": stripped[len("⊨"):].strip()})
            continue

        # ⊢= expression body (indented)
        if stripped.startswith("⊢="):
            if in_body and body_lines:
                current["body"] = "\n".join(body_lines).strip()
                in_body = False
                body_lines = []
            current["body"] = stripped[len("⊢="):].strip()
            current["body_type"] = "hard"
            continue

        # Continuation of ∴ body
        if in_body:
            body_lines.append(stripped)
            continue

    if current and in_body and body_lines:
        current["body"] = "\n".join(body_lines).strip()

    # Post-process: cells with no body are passthrough
    for c in cells:
        if c["body"] is None and c["body_type"] is None:
            c["body_type"] = "passthrough"

    return cells


def main():
    if len(sys.argv) < 3:
        print("Usage: parse.py <program.cell> <state-dir>", file=sys.stderr)
        sys.exit(1)

    program_path = Path(sys.argv[1])
    state_dir = Path(sys.argv[2])
    state_dir.mkdir(parents=True, exist_ok=True)

    text = program_path.read_text()
    cells = parse_cell_file(text)

    # Write cell order for deterministic iteration
    cell_order = []
    for cell in cells:
        name = cell["name"]
        cell_path = state_dir / f"{name}.json"
        cell_path.write_text(json.dumps(cell, indent=2, ensure_ascii=False))
        cell_order.append(name)

    # Write metadata
    meta = {
        "program": str(program_path),
        "cell_order": cell_order,
        "step": 0,
    }
    (state_dir / "_meta.json").write_text(json.dumps(meta, indent=2))

    # Report
    for cell in cells:
        gs = len(cell["givens"])
        ys = len(cell["yield_names"])
        os_ = len(cell["oracles"])
        print(f"  {cell['turnstile']} {cell['name']}: {gs} givens, {ys} yields, {os_} oracles, body={cell['body_type']}")

    print(json.dumps(cell_order))


if __name__ == "__main__":
    main()
