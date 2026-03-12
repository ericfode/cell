#!/usr/bin/env python3
"""gastown-eval-loop.py: Execute a cell program via Gas Town.

Usage:
    python gastown-eval-loop.py <program.cell> [--dry-run] [--max-steps N] [--verbose] [--parallel]

This is the GASTOWN column from cell-zero.cell's environment contract:
  - find-ready     = bd ready
  - invoke-substrate = gt sling → polecat (soft cells)
  - eval-expression = python3 (hard cells)
  - spawn-children  = bd create
  - apply-graph-updates = bd create + bd dep add
  - observe-execution = bead metadata recording

Soft cells are dispatched to polecats via gt sling.
Hard cells are evaluated locally (deterministic).
Confluence guarantees: all ready cells can run in parallel.
"""

from __future__ import annotations

import json
import os
import re
import subprocess
import sys
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
from parse import parse_cell_file


BEADS_DIR = os.environ.get("BEADS_DIR", "/home/nixos/wasteland/cell/.beads")
CELL_RIG = "cell"  # target rig for polecat dispatch
POLL_INTERVAL = 5  # seconds between polling for polecat completion
POLL_TIMEOUT = 300  # max seconds to wait for a polecat


# ─── Colors ───────────────────────────────────────────────────
if sys.stdout.isatty():
    BOLD, DIM, GREEN, YELLOW, RED, CYAN, BLUE, RESET = (
        "\033[1m", "\033[2m", "\033[32m", "\033[33m",
        "\033[31m", "\033[36m", "\033[34m", "\033[0m",
    )
else:
    BOLD = DIM = GREEN = YELLOW = RED = CYAN = BLUE = RESET = ""


def log(msg: str):
    print(f"{DIM}[gastown]{RESET} {msg}")


def log_step(step: int, msg: str):
    print(f"{CYAN}[step {step}]{RESET} {msg}")


# ─── Shell helpers ────────────────────────────────────────────

def bd(*args: str) -> str:
    env = os.environ.copy()
    env["BEADS_DIR"] = BEADS_DIR
    result = subprocess.run(
        ["bd"] + list(args), capture_output=True, text=True, env=env,
    )
    if result.returncode != 0 and result.stderr:
        print(f"{DIM}bd error: {result.stderr.strip()}{RESET}", file=sys.stderr)
    return result.stdout.strip()


def gt(*args: str) -> str:
    result = subprocess.run(
        ["gt"] + list(args), capture_output=True, text=True,
    )
    if result.returncode != 0 and result.stderr:
        print(f"{DIM}gt error: {result.stderr.strip()}{RESET}", file=sys.stderr)
    return result.stdout.strip()


def bd_show(bead_id: str) -> dict | None:
    raw = bd("show", bead_id, "--json")
    if not raw:
        return None
    try:
        data = json.loads(raw)
        return data[0] if isinstance(data, list) else data
    except json.JSONDecodeError:
        return None


def bd_ready_all() -> list[dict]:
    raw = bd("ready", "-n", "500", "--json")
    if not raw:
        return []
    try:
        data = json.loads(raw)
        return data if isinstance(data, list) else []
    except json.JSONDecodeError:
        return []


def bd_close(bead_id: str, reason: str):
    bd("close", bead_id, "--reason", reason)


def bd_update_meta(bead_id: str, key: str, value: str):
    bd("update", bead_id, "--set-metadata", f"{key}={value}")


def bd_add_label(bead_id: str, label: str):
    bd("update", bead_id, "--add-label", label)


def get_meta(bead: dict) -> dict:
    return bead.get("metadata", {})


def get_yields(bead: dict) -> dict:
    meta = get_meta(bead)
    yields = {}
    for k, v in meta.items():
        if k.startswith("yield_"):
            field = k[6:]
            try:
                yields[field] = json.loads(v)
            except (json.JSONDecodeError, TypeError):
                yields[field] = v
    return yields


# ─── Cell loading ────────────────────────────────────────────

def load_program(program_path: str) -> tuple[list[dict], dict]:
    """Parse .cell file and create beads. Returns (cells, mapping)."""
    text = Path(program_path).read_text()
    cells = parse_cell_file(text)

    log(f"{BOLD}Loading:{RESET} {program_path}")
    for c in cells:
        gs = len(c["givens"])
        ys = len(c["yield_names"])
        os_ = len(c["oracles"])
        print(f"  {c['turnstile']} {c['name']}: {gs} givens, {ys} yields, {os_} oracles, body={c['body_type']}")

    # Create beads
    mapping = {}
    for cell in cells:
        name = cell["name"]
        body_type = cell.get("body_type", "unknown")

        # Build description — for soft cells, include full execution context
        if body_type == "soft" and cell.get("body"):
            desc = f"∴ {cell['body']}"
        elif body_type == "hard" and cell.get("body"):
            desc = f"⊢= {cell['body']}"
        else:
            desc = f"Cell: {cell['turnstile']} {name}"

        if cell.get("oracles"):
            desc += "\n\nOracles:"
            for o in cell["oracles"]:
                desc += f"\n  ⊨ {o['text']}"

        if cell.get("yield_names"):
            desc += f"\n\nYields: {', '.join(cell['yield_names'])}"

        # Metadata
        metadata = {
            "cell_name": name,
            "turnstile": cell["turnstile"],
            "body_type": body_type,
            "yield_names": json.dumps(cell["yield_names"]),
            "givens": json.dumps(cell["givens"]),
        }
        if body_type == "hard" and cell.get("body"):
            metadata["expr"] = cell["body"]
        if cell.get("oracles"):
            metadata["oracles"] = json.dumps([o["text"] for o in cell["oracles"]])

        for g in cell["givens"]:
            if g.get("has_default"):
                metadata[f"default_{g['name']}"] = json.dumps(g["default"])
            if g.get("guard_expr"):
                metadata[f"guard_{g['name']}"] = g["guard_expr"]

        labels = ["cell", body_type]

        # Create bead
        label_args = []
        for l in labels:
            label_args.extend(["-l", l])

        result = bd(
            "create", f"cell: {name}",
            "-d", desc, "-t", "task",
            "--metadata", json.dumps(metadata),
            "--json", *label_args,
        )
        try:
            data = json.loads(result)
            bead_id = data.get("id", "")
        except json.JSONDecodeError:
            bead_id = ""

        if bead_id:
            mapping[name] = bead_id

    # Add dependencies
    for cell in cells:
        cell_id = mapping.get(cell["name"])
        if not cell_id:
            continue
        for g in cell["givens"]:
            src = g.get("source_cell")
            if src and src in mapping:
                bd("dep", "add", cell_id, mapping[src])

    log(f"{GREEN}Created{RESET} {len(mapping)} beads")
    return cells, mapping


# ─── Evaluation ──────────────────────────────────────────────

def resolve_bindings(cell_meta: dict, mapping: dict) -> dict:
    """Resolve givens to concrete values from upstream bead yields."""
    givens = json.loads(cell_meta.get("givens", "[]"))
    bindings = {}

    for g in givens:
        name = g.get("name", "")
        if g.get("has_default"):
            bindings[name] = g["default"]

        src = g.get("source_cell")
        if src and src in mapping:
            src_bead = bd_show(mapping[src])
            if src_bead:
                src_yields = get_yields(src_bead)
                field = g.get("source_field", name)
                if field in src_yields:
                    bindings[name] = src_yields[field]
                    bindings[f"{src}\u2192{field}"] = src_yields[field]

        default_key = f"default_{name}"
        if default_key in cell_meta and name not in bindings:
            try:
                bindings[name] = json.loads(cell_meta[default_key])
            except (json.JSONDecodeError, TypeError):
                bindings[name] = cell_meta[default_key]

    return bindings


def eval_hard(expr: str, bindings: dict, yield_names: list[str]) -> dict:
    """Evaluate a ⊢= expression deterministically."""
    m = re.match(r'^(\w[\w-]*)\s*←\s*(.+)$', expr, re.DOTALL)
    if m:
        expr = m.group(2).strip()

    resolved = expr
    refs = sorted(
        [(ref, val) for ref, val in bindings.items() if "\u2192" in ref],
        key=lambda x: len(x[0]), reverse=True,
    )
    for ref, val in refs:
        resolved = resolved.replace(ref, repr(val))

    py_expr = resolved
    py_expr = re.sub(r'\beval\(', '(', py_expr)
    py_expr = re.sub(r'(?<![!<>=])=(?!=)', '==', py_expr)
    py_expr = re.sub(r'\btrue\b', 'True', py_expr)
    py_expr = re.sub(r'\bfalse\b', 'False', py_expr)

    ns = {}
    for k, v in bindings.items():
        safe_k = k.replace("\u2192", "_").replace("-", "_")
        ns[safe_k] = v
    ns.update({"len": len, "split": lambda s, d: s.split(d),
               "join": lambda lst, d: d.join(lst), "min": min, "max": max,
               "sum": sum, "sorted": sorted, "True": True, "False": False,
               "length": len})

    try:
        result = eval(py_expr, {"__builtins__": {}}, ns)
    except Exception as e:
        print(f"WARN: eval failed: {py_expr} — {e}", file=sys.stderr)
        result = None

    if len(yield_names) == 1:
        return {yield_names[0]: result}
    return {yield_names[0]: result} if not isinstance(result, dict) else result


def interpolate(text: str, bindings: dict) -> str:
    """Replace «name» and «cell→field» with values."""
    def replacer(m):
        ref = m.group(1)
        if ref in bindings:
            val = bindings[ref]
            return str(val) if val is not None else "⊥"
        for k, v in bindings.items():
            if k.endswith(f"\u2192{ref}") or k == ref:
                return str(v) if v is not None else "⊥"
        return f"«{ref}»"
    return re.sub(r'«([^»]+)»', replacer, text)


def sling_soft_cell(bead_id: str, cell_name: str, body: str,
                    bindings: dict, yield_names: list[str],
                    dry_run: bool = False) -> str | None:
    """Dispatch a soft cell to a polecat via gt sling.

    Updates the bead description with interpolated body + execution instructions,
    then slings to the cell rig. Returns the polecat name or None.
    """
    resolved_body = interpolate(body, bindings)

    # Build execution instructions for the polecat
    instructions = f"""## Cell Execution Task

Execute this cell and store the results.

### Cell: {cell_name}

### Inputs:
"""
    for k, v in bindings.items():
        if "\u2192" not in k:
            instructions += f"  {k} = {json.dumps(v)}\n"

    instructions += f"""
### Task:
{resolved_body}

### Required Outputs:
Produce values for: {', '.join(yield_names)}

### How to Store Results:
For each yield value, run:
```bash
export BEADS_DIR={BEADS_DIR}
bd update {bead_id} --set-metadata "yield_<name>=<value>"
```

For example:
"""
    for n in yield_names:
        instructions += f'```bash\nbd update {bead_id} --set-metadata "yield_{n}=<your result>"\n```\n'

    instructions += f"""
### When Done:
After storing all yield values, close the bead:
```bash
bd close {bead_id} --reason "frozen: cell execution complete"
```

**IMPORTANT**: Store yields BEFORE closing. The eval loop reads yields from metadata.
"""

    # Update bead description with full instructions
    bd("update", bead_id, "-d", instructions)

    if dry_run:
        log(f"  {DIM}[dry-run] would sling {bead_id} to {CELL_RIG}{RESET}")
        # Simulate: store dry-run values and close
        for n in yield_names:
            bd_update_meta(bead_id, f"yield_{n}", json.dumps(f"<slung-{n}>"))
        bd_close(bead_id, f"dry-run: simulated polecat execution")
        return "dry-run"

    # SLING IT
    log(f"  {BLUE}sling{RESET} {cell_name} [{bead_id}] → {CELL_RIG}")
    sling_output = gt(
        "sling", bead_id, CELL_RIG,
        "-m", f"Execute cell '{cell_name}': {resolved_body[:200]}",
        "--no-convoy",
    )

    if sling_output:
        # Extract polecat name from output
        for line in sling_output.split("\n"):
            if "polecat" in line.lower():
                log(f"  {DIM}{line.strip()}{RESET}")

    return "slung"


def wait_for_bead_closed(bead_id: str, cell_name: str,
                         timeout: int = POLL_TIMEOUT) -> bool:
    """Poll until a bead is closed (frozen/bottom). Returns True if closed."""
    start = time.time()
    while time.time() - start < timeout:
        bead = bd_show(bead_id)
        if bead and bead.get("status") == "closed":
            return True
        time.sleep(POLL_INTERVAL)
        elapsed = int(time.time() - start)
        if elapsed % 15 == 0:
            log(f"  {DIM}waiting for {cell_name} [{bead_id}]... ({elapsed}s){RESET}")
    return False


def check_guards(cell_meta: dict, mapping: dict) -> bool:
    """Check guard expressions. Returns False if any guard fails."""
    givens = json.loads(cell_meta.get("givens", "[]"))
    for g in givens:
        if not g.get("guard_expr"):
            continue
        src = g.get("source_cell")
        if not src or src not in mapping:
            continue
        src_bead = bd_show(mapping[src])
        if not src_bead:
            continue
        src_yields = get_yields(src_bead)
        field = g.get("source_field", g.get("name", ""))
        val = src_yields.get(field)

        gexpr = g["guard_expr"]
        m = re.match(r'(\w[\w-]*)\s*=\s*"([^"]*)"', gexpr)
        if m and str(val) != m.group(2):
            return False
        m = re.match(r'(\w[\w-]*)\s*=\s*(\w+)', gexpr)
        if m and str(val) != m.group(2):
            return False
    return True


def check_oracles(oracle_texts: list[str], outputs: dict) -> tuple[bool, list[dict]]:
    """Check oracle assertions deterministically."""
    results = []
    all_pass = True

    def parse_value(s):
        s = s.strip()
        if s.startswith('"') and s.endswith('"'): return s[1:-1]
        if s == "true": return True
        if s == "false": return False
        try: return int(s)
        except ValueError:
            try: return float(s)
            except ValueError: return s

    for oracle_text in oracle_texts:
        cm = re.match(r'^if\s+(.+?)\s+then\s+(.+)$', oracle_text)
        if cm:
            results.append({"text": oracle_text, "pass": True, "reason": "conditional: assumed pass"})
            continue

        m = re.match(r'^(\w[\w-]*)\s*=\s*(.+)$', oracle_text)
        if m:
            field, expected = m.group(1), parse_value(m.group(2).strip())
            actual = outputs.get(field)
            if actual is not None and expected is not None:
                try:
                    passed = float(actual) == float(expected)
                except (ValueError, TypeError):
                    passed = actual == expected
                results.append({"text": oracle_text, "pass": passed,
                              "reason": f"{actual!r} vs {expected!r}"})
                if not passed:
                    all_pass = False
                continue

        results.append({"text": oracle_text, "pass": True, "reason": "semantic: assumed pass"})

    return all_pass, results


# ─── Main eval loop ──────────────────────────────────────────

def main():
    if len(sys.argv) < 2:
        print("Usage: gastown-eval-loop.py <program.cell> [--dry-run] [--parallel] [--max-steps N] [--verbose]",
              file=sys.stderr)
        sys.exit(1)

    program_path = sys.argv[1]
    dry_run = "--dry-run" in sys.argv
    parallel = "--parallel" in sys.argv
    verbose = "--verbose" in sys.argv or "-v" in sys.argv
    max_steps = 100
    for i, arg in enumerate(sys.argv):
        if arg == "--max-steps" and i + 1 < len(sys.argv):
            max_steps = int(sys.argv[i + 1])

    # ── Phase 1: Load program into beads ──
    cells, mapping = load_program(program_path)
    reverse_map = {v: k for k, v in mapping.items()}
    bead_ids = set(mapping.values())

    # ── Phase 2: Eval loop ──
    log(f"{BOLD}Entering Gas Town eval-loop{RESET} (max {max_steps} steps, parallel={'yes' if parallel else 'no'})")

    step = 0
    while step < max_steps:
        # ── find-ready ──
        all_ready = bd_ready_all()
        ready_cells = [r for r in all_ready
                       if r.get("id") in bead_ids and "cell" in r.get("labels", [])]

        # ── skip guard-failed cells ──
        if not ready_cells:
            skipped_any = False
            for name, bid in mapping.items():
                bead = bd_show(bid)
                if not bead or bead.get("status") == "closed":
                    continue
                meta = get_meta(bead)
                givens = json.loads(meta.get("givens", "[]"))
                all_deps_met = True
                for g in givens:
                    src = g.get("source_cell")
                    if src and src in mapping:
                        src_bead = bd_show(mapping[src])
                        if not src_bead or src_bead.get("status") != "closed":
                            all_deps_met = False
                            break

                if all_deps_met and not check_guards(meta, mapping):
                    yield_names = json.loads(meta.get("yield_names", "[]"))
                    for n in yield_names:
                        bd_update_meta(bid, f"yield_{n}", "null")
                    bd_close(bid, "guard clause false → ⊥")
                    bd_add_label(bid, "bottom")
                    log_step(step, f"{DIM}skip{RESET} {name} (guard false → ⊥)")
                    skipped_any = True

            if skipped_any:
                continue

            # Check if done
            all_closed = all(
                (bd_show(bid) or {}).get("status") == "closed"
                for bid in mapping.values()
            )
            if all_closed:
                log(f"{GREEN}{BOLD}QUIESCENT{RESET} after {step} steps — all beads closed")
            else:
                pending = [n for n, bid in mapping.items()
                          if (bd_show(bid) or {}).get("status") != "closed"]
                log(f"{YELLOW}Blocked{RESET}: pending=[{', '.join(pending)}] but none ready")
            break

        # ── dispatch (parallel or sequential) ──
        if parallel:
            # CONFLUENCE: sling ALL ready cells at once
            slung = []
            local_evals = []

            for r in ready_cells:
                bid = r["id"]
                name = reverse_map.get(bid, bid)
                bead = bd_show(bid)
                if not bead:
                    continue
                meta = get_meta(bead)

                if not check_guards(meta, mapping):
                    yield_names = json.loads(meta.get("yield_names", "[]"))
                    for n in yield_names:
                        bd_update_meta(bid, f"yield_{n}", "null")
                    bd_close(bid, "guard clause false → ⊥")
                    bd_add_label(bid, "bottom")
                    log_step(step, f"{DIM}skip{RESET} {name} (guard → ⊥)")
                    continue

                body_type = meta.get("body_type", "")
                yield_names = json.loads(meta.get("yield_names", "[]"))
                bindings = resolve_bindings(meta, mapping)

                if body_type == "hard":
                    # Evaluate locally (fast, deterministic)
                    outputs = eval_hard(meta.get("expr", ""), bindings, yield_names)
                    for k, v in outputs.items():
                        bd_update_meta(bid, f"yield_{k}", json.dumps(v))
                    oracle_texts = json.loads(meta.get("oracles", "[]"))
                    all_pass, results = check_oracles(oracle_texts, outputs) if oracle_texts else (True, [])
                    if all_pass:
                        yields_str = ", ".join(f"{k}={v!r}" for k, v in outputs.items())
                        bd_close(bid, f"frozen: {yields_str}")
                        log_step(step, f"{GREEN}freeze{RESET} {name} → {yields_str}")
                    else:
                        bd_close(bid, "bottom: oracle failure")
                        bd_add_label(bid, "bottom")
                        log_step(step, f"{RED}bottom{RESET} {name}")
                    local_evals.append(name)

                elif body_type == "soft":
                    # Sling to polecat
                    body = bead.get("description", "")
                    if body.startswith("∴ ") or body.startswith("∴\n"):
                        body = body[2:]
                    sling_soft_cell(bid, name, body, bindings, yield_names, dry_run)
                    slung.append((bid, name))

            # Wait for all slung cells to complete
            if slung and not dry_run:
                log(f"  {BLUE}Waiting{RESET} for {len(slung)} polecat(s)...")
                for bid, name in slung:
                    if wait_for_bead_closed(bid, name):
                        bead = bd_show(bid)
                        yields = get_yields(bead) if bead else {}
                        yields_str = ", ".join(f"{k}={v!r}" for k, v in yields.items())
                        log_step(step, f"{GREEN}freeze{RESET} {name} → {yields_str} {BLUE}(polecat){RESET}")
                    else:
                        log_step(step, f"{RED}timeout{RESET} {name} (polecat didn't complete)")

            step += 1

        else:
            # SEQUENTIAL: one cell at a time
            target = ready_cells[0]
            bid = target["id"]
            name = reverse_map.get(bid, bid)

            if verbose:
                ready_names = [reverse_map.get(r["id"], r["id"]) for r in ready_cells]
                log_step(step, f"ready=[{', '.join(ready_names)}] picking={name}")

            bead = bd_show(bid)
            if not bead:
                step += 1
                continue

            meta = get_meta(bead)

            if not check_guards(meta, mapping):
                yield_names = json.loads(meta.get("yield_names", "[]"))
                for n in yield_names:
                    bd_update_meta(bid, f"yield_{n}", "null")
                bd_close(bid, "guard clause false → ⊥")
                bd_add_label(bid, "bottom")
                log_step(step, f"{DIM}skip{RESET} {name} (guard → ⊥)")
                continue

            body_type = meta.get("body_type", "")
            yield_names = json.loads(meta.get("yield_names", "[]"))
            bindings = resolve_bindings(meta, mapping)

            if body_type == "hard":
                outputs = eval_hard(meta.get("expr", ""), bindings, yield_names)
                for k, v in outputs.items():
                    bd_update_meta(bid, f"yield_{k}", json.dumps(v))

                oracle_texts = json.loads(meta.get("oracles", "[]"))
                all_pass = True
                if oracle_texts:
                    all_pass, results = check_oracles(oracle_texts, outputs)
                    if verbose:
                        log(f"  oracles: {json.dumps({'all_pass': all_pass, 'results': results})}")

                if all_pass:
                    yields_str = ", ".join(f"{k}={v!r}" for k, v in outputs.items())
                    bd_close(bid, f"frozen: {yields_str}")
                    log_step(step, f"{GREEN}freeze{RESET} {name} → {yields_str}")
                else:
                    retries = int(meta.get("retries", "0"))
                    if retries < 3:
                        bd_update_meta(bid, "retries", str(retries + 1))
                        log_step(step, f"{YELLOW}retry{RESET} {name} (attempt {retries + 1})")
                        continue
                    bd_close(bid, "bottom: oracle exhaustion")
                    bd_add_label(bid, "bottom")
                    log_step(step, f"{RED}bottom{RESET} {name}")

            elif body_type == "soft":
                body = bead.get("description", "")
                if body.startswith("∴ ") or body.startswith("∴\n"):
                    body = body[2:]

                polecat = sling_soft_cell(bid, name, body, bindings, yield_names, dry_run)

                if not dry_run:
                    # Wait for polecat to finish
                    if wait_for_bead_closed(bid, name):
                        bead = bd_show(bid)
                        yields = get_yields(bead) if bead else {}
                        yields_str = ", ".join(f"{k}={v!r}" for k, v in yields.items())
                        log_step(step, f"{GREEN}freeze{RESET} {name} → {yields_str} {BLUE}(polecat){RESET}")
                    else:
                        log_step(step, f"{RED}timeout{RESET} {name}")
                else:
                    bead = bd_show(bid)
                    yields = get_yields(bead) if bead else {}
                    yields_str = ", ".join(f"{k}={v!r}" for k, v in yields.items())
                    log_step(step, f"{GREEN}freeze{RESET} {name} → {yields_str} {DIM}(dry-run sling){RESET}")

            elif body_type == "passthrough":
                outputs = {n: bindings.get(n) for n in yield_names}
                for k, v in outputs.items():
                    bd_update_meta(bid, f"yield_{k}", json.dumps(v))
                yields_str = ", ".join(f"{k}={v!r}" for k, v in outputs.items())
                bd_close(bid, f"frozen: {yields_str}")
                log_step(step, f"{GREEN}freeze{RESET} {name} → {yields_str}")

            step += 1

    if step >= max_steps:
        log(f"{RED}{BOLD}HALTED{RESET}: max steps ({max_steps}) reached")

    # ── Phase 3: Final report ──
    print()
    log(f"{BOLD}Final state:{RESET}")
    print()

    frozen = bottom = pending_count = 0
    for name, bid in mapping.items():
        bead = bd_show(bid)
        if not bead:
            print(f"  ? {name} [{bid}]: ERROR")
            continue
        status = bead.get("status", "?")
        labels = bead.get("labels", [])
        yields = get_yields(bead)
        ts = get_meta(bead).get("turnstile", "⊢")
        is_bottom = "bottom" in labels

        if status == "closed" and not is_bottom:
            icon, frozen = "✓", frozen + 1
        elif is_bottom:
            icon, bottom = "⊥", bottom + 1
        else:
            icon, pending_count = "◌", pending_count + 1

        yield_str = " → " + ", ".join(f"{k}={v!r}" for k, v in yields.items()) if yields else ""
        print(f"  {icon} {ts} {name} [{bid}]: {status}{yield_str}")

    total = len(mapping)
    print()
    log(f"{BOLD}Summary:{RESET} {frozen} frozen, {bottom} bottom, {pending_count} pending (of {total} cells)")

    if pending_count == 0 and bottom == 0:
        log(f"{GREEN}{BOLD}ALL CELLS FROZEN — program complete{RESET}")

    # ── Cleanup info ──
    print()
    bead_list = " ".join(mapping.values())
    log(f"{DIM}To clean up: bd delete {bead_list} --force{RESET}")


if __name__ == "__main__":
    main()
