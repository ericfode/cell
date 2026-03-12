#!/usr/bin/env python3
"""decide.py: Freeze, retry, or bottom a cell based on oracle results.

Usage:
    python decide.py <state-dir> <cell-name> <outputs-json> <oracle-result-json>

Updates the cell's JSON file in the state directory.
Outputs the action taken: "freeze", "retry", or "bottom"
"""

from __future__ import annotations

import json
import sys
from pathlib import Path


def main():
    if len(sys.argv) < 5:
        print("Usage: decide.py <state-dir> <cell-name> <outputs-json> <oracle-result-json>",
              file=sys.stderr)
        sys.exit(1)

    state_dir = Path(sys.argv[1])
    cell_name = sys.argv[2]
    outputs = json.loads(sys.argv[3])
    oracle_result = json.loads(sys.argv[4])

    cell_path = state_dir / f"{cell_name}.json"
    cell = json.loads(cell_path.read_text())

    all_pass = oracle_result["all_pass"]

    if all_pass:
        # FREEZE: bind outputs and mark frozen
        cell["frozen"] = True
        cell["yield_values"] = outputs
        action = "freeze"
    elif cell["retries"] < cell["max_retries"]:
        # RETRY: increment retry counter (caller re-dispatches)
        cell["retries"] += 1
        action = "retry"
    else:
        # BOTTOM: exhausted retries
        cell["is_bottom"] = True
        cell["yield_values"] = {n: None for n in cell["yield_names"]}
        action = "bottom"

    cell_path.write_text(json.dumps(cell, indent=2, ensure_ascii=False))

    # Also update meta step counter
    meta_path = state_dir / "_meta.json"
    meta = json.loads(meta_path.read_text())
    meta["step"] = meta.get("step", 0) + 1
    meta_path.write_text(json.dumps(meta, indent=2))

    print(action)


if __name__ == "__main__":
    main()
