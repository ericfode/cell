#!/usr/bin/env python3
"""trace.py: Render a cell-zero state directory back into a .cell trace file.

Usage:
    python trace.py <state-dir> [--source <original.cell>]

The trace IS the executed program — document-is-state.
Frozen yields get ≡ value. Bottomed cells get ⊥. Oracles get ✓/✗.

Without --source, reconstructs from parsed state (loses comments/formatting).
With --source, annotates the original source file in-place.
"""

from __future__ import annotations

import json
import re
import sys
from pathlib import Path


def load_state(state_dir: Path) -> tuple[list[str], dict[str, dict]]:
    """Load cell order and cell data from state directory."""
    meta = json.loads((state_dir / "_meta.json").read_text())
    cells = {}
    for name in meta["cell_order"]:
        cells[name] = json.loads((state_dir / f"{name}.json").read_text())
    return meta["cell_order"], cells


def format_value(val) -> str:
    """Format a Python value as Cell literal."""
    if val is None:
        return "⊥"
    if isinstance(val, bool):
        return "true" if val else "false"
    if isinstance(val, str):
        return f'"{val}"'
    if isinstance(val, list):
        inner = ", ".join(format_value(v) for v in val)
        return f"[{inner}]"
    return str(val)


def cell_status(cell: dict) -> str:
    """Return status string for a cell."""
    if cell["frozen"]:
        return "FROZEN"
    if cell["is_bottom"]:
        return "⊥"
    return "PENDING"


def render_from_source(source_path: Path, cell_order: list[str],
                       cells: dict[str, dict]) -> str:
    """Annotate original source file with execution results."""
    lines = source_path.read_text().split("\n")
    out = []
    current_cell = None
    # Track which yields we've annotated
    annotated_yields = set()

    # Count summary
    frozen = sum(1 for c in cells.values() if c["frozen"])
    bottom = sum(1 for c in cells.values() if c["is_bottom"])
    total = len(cells)

    # Header
    out.append(f"-- TRACE: {frozen} frozen, {bottom} ⊥, {total} total")
    out.append("")

    for line in lines:
        stripped = line.lstrip()

        # Cell declaration — add status annotation
        m = re.match(r'^(⊢⊢|⊢∘|⊢=|⊢)\s+(\S+)', stripped)
        if m and len(line) - len(stripped) == 0:
            name = m.group(2)
            if name in cells:
                current_cell = cells[name]
                status = cell_status(current_cell)
                if status == "⊥":
                    out.append(f"{line}  -- ⊥")
                elif status == "FROZEN":
                    out.append(f"{line}  -- ✓ frozen")
                else:
                    out.append(f"{line}  -- pending")
                continue

        # yield line — annotate with frozen values
        ym = re.match(r'^(\s+yield\s+)(.+)', line)
        if ym and current_cell:
            prefix = ym.group(1)
            yield_text = ym.group(2).strip()
            ynames = [n.strip().rstrip("[]") for n in yield_text.split(",")]

            if current_cell["frozen"] and current_cell.get("yield_values"):
                parts = []
                for yn in ynames:
                    val = current_cell["yield_values"].get(yn)
                    parts.append(f"{yn} ≡ {format_value(val)}")
                out.append(f"{prefix}{', '.join(parts)}")
            elif current_cell["is_bottom"]:
                parts = [f"{yn} ≡ ⊥" for yn in ynames]
                out.append(f"{prefix}{', '.join(parts)}")
            else:
                out.append(line)
            continue

        # Oracle line — annotate with pass/fail
        if stripped.startswith("⊨") and not stripped.startswith("⊨?") and current_cell:
            oracle_text = stripped[len("⊨"):].strip()
            if current_cell["frozen"]:
                out.append(f"{line}  -- ✓")
            elif current_cell["is_bottom"]:
                out.append(f"{line}  -- ✗ (cell ⊥)")
            else:
                out.append(line)
            continue

        # Guard annotation
        gm = re.match(r'^(\s+given\s+\S+→\S+\s+where\s+.+)', line)
        if gm and current_cell and current_cell["is_bottom"]:
            out.append(f"{line}  -- guard ✗")
            continue

        out.append(line)

    return "\n".join(out)


def render_from_state(cell_order: list[str], cells: dict[str, dict]) -> str:
    """Reconstruct a .cell trace purely from parsed state."""
    out = []
    frozen = sum(1 for c in cells.values() if c["frozen"])
    bottom = sum(1 for c in cells.values() if c["is_bottom"])
    total = len(cells)
    out.append(f"-- TRACE: {frozen} frozen, {bottom} ⊥, {total} total")
    out.append("")

    for name in cell_order:
        cell = cells[name]
        status = cell_status(cell)

        # Cell declaration
        ts = cell["turnstile"]
        status_comment = {"FROZEN": "-- ✓ frozen", "⊥": "-- ⊥",
                          "PENDING": "-- pending"}[status]
        out.append(f"{ts} {name}  {status_comment}")

        # Givens
        for g in cell["givens"]:
            given_str = "  given"
            if g.get("optional"):
                given_str = "  given?"

            if g.get("source_cell"):
                ref = f"{g['source_cell']}→{g['source_field']}"
                if g.get("name") != g.get("source_field"):
                    ref += f" as {g['name']}"
                given_str += f" {ref}"
            elif g.get("has_default") and not g["name"].startswith("§"):
                given_str += f" {g['name']} ≡ {format_value(g['default'])}"
            else:
                given_str += f" {g['name']}"

            if g.get("guard_expr"):
                src_cell = cells.get(g.get("source_cell", ""))
                if cell["is_bottom"] and src_cell and src_cell["frozen"]:
                    given_str += f" where {g['guard_expr']}  -- guard ✗"
                elif cell["frozen"]:
                    given_str += f" where {g['guard_expr']}  -- guard ✓"
                else:
                    given_str += f" where {g['guard_expr']}"

            out.append(given_str)

        # Yields — annotated with values
        if cell["yield_names"]:
            if cell["frozen"] and cell.get("yield_values"):
                parts = []
                for yn in cell["yield_names"]:
                    val = cell["yield_values"].get(yn)
                    parts.append(f"{yn} ≡ {format_value(val)}")
                out.append(f"  yield {', '.join(parts)}")
            elif cell["is_bottom"]:
                parts = [f"{yn} ≡ ⊥" for yn in cell["yield_names"]]
                out.append(f"  yield {', '.join(parts)}")
            else:
                out.append(f"  yield {', '.join(cell['yield_names'])}")

        # Body
        if cell["body"]:
            out.append("")
            if cell["body_type"] == "soft":
                for i, bline in enumerate(cell["body"].split("\n")):
                    if i == 0:
                        out.append(f"  ∴ {bline}")
                    else:
                        out.append(f"    {bline}")
            elif cell["body_type"] == "hard":
                for bline in cell["body"].split("\n"):
                    out.append(f"  ⊢= {bline}")

        # Oracles
        if cell["oracles"]:
            out.append("")
            for oracle in cell["oracles"]:
                if cell["frozen"]:
                    out.append(f"  ⊨ {oracle['text']}  -- ✓")
                elif cell["is_bottom"]:
                    out.append(f"  ⊨ {oracle['text']}  -- ✗ (cell ⊥)")
                else:
                    out.append(f"  ⊨ {oracle['text']}")

        # Recovery
        if cell.get("recovery"):
            out.append(f"  ⊨? {cell['recovery']}")

        out.append("")

    return "\n".join(out)


def main():
    if len(sys.argv) < 2:
        print("Usage: trace.py <state-dir> [--source <original.cell>]",
              file=sys.stderr)
        sys.exit(1)

    state_dir = Path(sys.argv[1])
    source_path = None

    for i, arg in enumerate(sys.argv):
        if arg == "--source" and i + 1 < len(sys.argv):
            source_path = Path(sys.argv[i + 1])

    cell_order, cells = load_state(state_dir)

    if source_path:
        print(render_from_source(source_path, cell_order, cells))
    else:
        print(render_from_state(cell_order, cells))


if __name__ == "__main__":
    main()
