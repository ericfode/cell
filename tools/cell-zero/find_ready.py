#!/usr/bin/env python3
"""find_ready.py: Find cells that are ready to execute.

Usage:
    python find_ready.py <state-dir>

Outputs JSON array of ready cell names to stdout.
A cell is ready when: all givens bound, all guards true, not frozen, not bottom.
"""

from __future__ import annotations

import json
import re
import sys
from pathlib import Path


def load_cells(state_dir: Path) -> dict[str, dict]:
    """Load all cell JSON files from state directory."""
    meta = json.loads((state_dir / "_meta.json").read_text())
    cells = {}
    for name in meta["cell_order"]:
        cell_path = state_dir / f"{name}.json"
        cells[name] = json.loads(cell_path.read_text())
    return cells


def eval_guard(expr: str, var_name: str, val) -> bool:
    """Evaluate a guard clause like 'label = "toxic"'."""
    m = re.match(r'(\w[\w-]*)\s*=\s*"([^"]*)"', expr)
    if m:
        return str(val) == m.group(2)
    m = re.match(r'(\w[\w-]*)\s*=\s*(\w+)', expr)
    if m:
        expected = m.group(2)
        # Normalize Python bools to Cell bools for comparison
        actual = str(val).lower() if isinstance(val, bool) else str(val)
        return actual == expected
    m = re.match(r'(\w[\w-]*)\s*!=\s*"([^"]*)"', expr)
    if m:
        return str(val) != m.group(2)
    return True


def classify_cell(cell: dict, cells: dict[str, dict]) -> str:
    """Classify a cell's readiness: 'ready', 'blocked', 'skipped', 'done'.

    'skipped' means all givens are bound but a guard clause is false.
    Per the spec, skipped cells' yields become ⊥.
    """
    if cell["frozen"] or cell["is_bottom"]:
        return "done"

    all_bound = True
    guard_failed = False

    for g in cell["givens"]:
        if g.get("has_default"):
            continue

        src_cell = g.get("source_cell")
        if src_cell:
            src = cells.get(src_cell)
            if src is None:
                all_bound = False
                continue
            if src["is_bottom"]:
                if g.get("optional"):
                    continue
                # Non-optional dep on ⊥ → permanently blocked (should be skipped)
                return "skipped"
            if not src["frozen"]:
                all_bound = False
                continue
            src_field = g.get("source_field")
            if src_field not in src["yield_values"]:
                all_bound = False
                continue
            # Check guard
            if g.get("guard_expr"):
                val = src["yield_values"][src_field]
                if not eval_guard(g["guard_expr"], g["name"], val):
                    guard_failed = True
        else:
            # Non-dependency, non-default — can't be satisfied
            all_bound = False

    if not all_bound:
        return "blocked"
    if guard_failed:
        return "skipped"
    return "ready"


def main():
    if len(sys.argv) < 2:
        print("Usage: find_ready.py <state-dir>", file=sys.stderr)
        sys.exit(1)

    state_dir = Path(sys.argv[1])
    cells = load_cells(state_dir)

    ready = []
    blocked = []
    skipped = []

    for name, cell in cells.items():
        status = classify_cell(cell, cells)
        if status == "ready":
            ready.append(name)
        elif status == "blocked":
            blocked.append(name)
        elif status == "skipped":
            skipped.append(name)

    print(json.dumps({"ready": ready, "blocked": blocked, "skipped": skipped}))


if __name__ == "__main__":
    main()
