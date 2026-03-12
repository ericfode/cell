#!/usr/bin/env python3
"""cell-to-beads.py: Load a .cell program into beads.

Usage:
    python cell-to-beads.py <program.cell> [--prefix PREFIX] [--dry-run]

Creates one bead per cell with dependencies matching the cell graph.
Outputs a JSON mapping of cell-name → bead-id.
"""

from __future__ import annotations

import json
import os
import subprocess
import sys
from pathlib import Path

# Import the existing parser
sys.path.insert(0, str(Path(__file__).parent))
from parse import parse_cell_file


def run_bd(args: list[str], input_text: str | None = None) -> str:
    """Run a bd command and return stdout."""
    env = os.environ.copy()
    if "BEADS_DIR" not in env:
        env["BEADS_DIR"] = "/home/nixos/wasteland/cell/.beads"
    result = subprocess.run(
        ["bd"] + args,
        capture_output=True, text=True, env=env,
        input=input_text,
    )
    if result.returncode != 0:
        print(f"bd error: {result.stderr}", file=sys.stderr)
    return result.stdout.strip()


def cell_to_bead(cell: dict, prefix: str, dry_run: bool) -> str | None:
    """Create a bead for a cell. Returns the bead ID."""
    name = cell["name"]
    turnstile = cell["turnstile"]

    # Build description from body
    body_type = cell.get("body_type", "unknown")
    if body_type == "soft" and cell.get("body"):
        description = f"∴ {cell['body']}"
    elif body_type == "hard" and cell.get("body"):
        description = f"⊢= {cell['body']}"
    else:
        description = f"Cell: {turnstile} {name}"

    # Add oracle info to description
    if cell.get("oracles"):
        description += "\n\nOracles:"
        for o in cell["oracles"]:
            description += f"\n  ⊨ {o['text']}"

    # Add yield info
    if cell.get("yield_names"):
        description += f"\n\nYields: {', '.join(cell['yield_names'])}"

    # Build metadata
    metadata = {
        "cell_name": name,
        "turnstile": turnstile,
        "body_type": body_type,
        "yield_names": json.dumps(cell["yield_names"]),
        "givens": json.dumps(cell["givens"]),
    }
    if body_type == "hard" and cell.get("body"):
        metadata["expr"] = cell["body"]
    if cell.get("oracles"):
        metadata["oracles"] = json.dumps([o["text"] for o in cell["oracles"]])
    if cell.get("recovery"):
        metadata["recovery"] = cell["recovery"]

    # Store default values
    for g in cell["givens"]:
        if g.get("has_default"):
            metadata[f"default_{g['name']}"] = json.dumps(g["default"])
        if g.get("guard_expr"):
            metadata[f"guard_{g['name']}"] = g["guard_expr"]

    # Labels
    labels = ["cell", body_type]
    if turnstile == "⊢⊢":
        labels.append("spawner")
    elif turnstile == "⊢∘":
        labels.append("evolution")

    if dry_run:
        print(f"  [dry-run] would create: {turnstile} {name} ({body_type})", file=sys.stderr)
        return f"dry-{name}"

    # Create the bead
    label_args = []
    for l in labels:
        label_args.extend(["-l", l])

    result = run_bd([
        "create",
        f"{prefix}{name}",
        "-d", description,
        "-t", "task",
        "--metadata", json.dumps(metadata),
        "--json",
    ] + label_args)

    # Parse JSON to get the bead ID
    try:
        data = json.loads(result)
        bead_id = data.get("id", "")
    except json.JSONDecodeError:
        bead_id = ""

    if not bead_id:
        print(f"ERROR: failed to create bead for {name}", file=sys.stderr)
        return None

    return bead_id.strip()


def main():
    if len(sys.argv) < 2:
        print("Usage: cell-to-beads.py <program.cell> [--prefix PREFIX] [--dry-run]",
              file=sys.stderr)
        sys.exit(1)

    program_path = Path(sys.argv[1])
    prefix = "cell: "
    dry_run = "--dry-run" in sys.argv

    for i, arg in enumerate(sys.argv):
        if arg == "--prefix" and i + 1 < len(sys.argv):
            prefix = sys.argv[i + 1]

    # Parse the program
    text = program_path.read_text()
    cells = parse_cell_file(text)
    print(f"Parsed {len(cells)} cells from {program_path}", file=sys.stderr)

    # Create beads
    mapping = {}  # cell-name → bead-id
    for cell in cells:
        bead_id = cell_to_bead(cell, prefix, dry_run)
        if bead_id:
            mapping[cell["name"]] = bead_id
            print(f"  {cell['turnstile']} {cell['name']} → {bead_id}", file=sys.stderr)

    # Add dependencies
    for cell in cells:
        cell_id = mapping.get(cell["name"])
        if not cell_id:
            continue
        for g in cell["givens"]:
            src = g.get("source_cell")
            if src and src in mapping:
                dep_id = mapping[src]
                if not dry_run:
                    run_bd(["dep", "add", cell_id, dep_id])
                print(f"  dep: {cell['name']} depends on {src}", file=sys.stderr)

    # Output mapping
    print(json.dumps(mapping, indent=2))


if __name__ == "__main__":
    main()
