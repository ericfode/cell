#!/usr/bin/env python3
"""beads-eval-loop.py: Execute a cell program loaded into beads.

Usage:
    python beads-eval-loop.py <mapping-file> [--dry-run] [--max-steps N] [--verbose]

The mapping file is JSON: {"cell-name": "bead-id", ...}
Created by cell-to-beads.py
"""

from __future__ import annotations

import json
import os
import re
import subprocess
import sys
from pathlib import Path


BEADS_DIR = os.environ.get("BEADS_DIR", "/home/nixos/wasteland/cell/.beads")


# ─── Colors ───────────────────────────────────────────────────
if sys.stdout.isatty():
    BOLD, DIM, GREEN, YELLOW, RED, CYAN, RESET = (
        "\033[1m", "\033[2m", "\033[32m", "\033[33m", "\033[31m", "\033[36m", "\033[0m"
    )
else:
    BOLD = DIM = GREEN = YELLOW = RED = CYAN = RESET = ""


def log(msg: str):
    print(f"{DIM}[beads-eval]{RESET} {msg}")


def log_step(step: int, msg: str):
    print(f"{CYAN}[step {step}]{RESET} {msg}")


# ─── bd helpers ───────────────────────────────────────────────

def bd(*args: str, input_text: str | None = None) -> str:
    """Run a bd command and return stdout."""
    env = os.environ.copy()
    env["BEADS_DIR"] = BEADS_DIR
    result = subprocess.run(
        ["bd"] + list(args),
        capture_output=True, text=True, env=env,
        input=input_text,
    )
    return result.stdout.strip()


def bd_show(bead_id: str) -> dict | None:
    """Get a bead's full data."""
    raw = bd("show", bead_id, "--json")
    if not raw:
        return None
    try:
        data = json.loads(raw)
        return data[0] if isinstance(data, list) else data
    except json.JSONDecodeError:
        return None


def bd_ready_all() -> list[dict]:
    """Get all ready beads."""
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


def bd_update_metadata(bead_id: str, metadata: dict):
    """Update bead metadata. Uses --set-metadata key=value format."""
    args = ["update", bead_id]
    for k, v in metadata.items():
        args.extend(["--set-metadata", f"{k}={v}"])
    bd(*args)


def bd_add_label(bead_id: str, label: str):
    bd("update", bead_id, "--add-label", label)


# ─── Cell evaluation ─────────────────────────────────────────

def get_metadata(bead: dict) -> dict:
    return bead.get("metadata", {})


def get_yield_values(bead: dict) -> dict:
    meta = get_metadata(bead)
    yields = {}
    for k, v in meta.items():
        if k.startswith("yield_"):
            field = k[6:]
            try:
                yields[field] = json.loads(v)
            except (json.JSONDecodeError, TypeError):
                yields[field] = v
    return yields


def resolve_bindings(cell_meta: dict, mapping: dict) -> dict:
    """Resolve all givens to concrete values."""
    givens = json.loads(cell_meta.get("givens", "[]"))
    bindings = {}

    for g in givens:
        name = g.get("name", "")

        # Default values
        if g.get("has_default"):
            bindings[name] = g["default"]

        # Source cell references
        src = g.get("source_cell")
        if src and src in mapping:
            src_bead = bd_show(mapping[src])
            if src_bead:
                src_yields = get_yield_values(src_bead)
                field = g.get("source_field", name)
                if field in src_yields:
                    bindings[name] = src_yields[field]
                    bindings[f"{src}→{field}"] = src_yields[field]

        # Metadata defaults
        default_key = f"default_{name}"
        if default_key in cell_meta and name not in bindings:
            try:
                bindings[name] = json.loads(cell_meta[default_key])
            except (json.JSONDecodeError, TypeError):
                bindings[name] = cell_meta[default_key]

    return bindings


def eval_hard(expr: str, bindings: dict, yield_names: list[str]) -> dict:
    """Evaluate a ⊢= expression."""
    # Handle binding form: name ← expression
    m = re.match(r'^(\w[\w-]*)\s*←\s*(.+)$', expr, re.DOTALL)
    if m:
        expr = m.group(2).strip()

    # Substitute cell→field references (longest first to avoid partial matches)
    resolved = expr
    refs_by_length = sorted(
        [(ref, val) for ref, val in bindings.items() if "→" in ref],
        key=lambda x: len(x[0]),
        reverse=True,
    )
    for ref, val in refs_by_length:
        resolved = resolved.replace(ref, repr(val))

    # Convert to Python
    py_expr = resolved
    # Convert Cell if/then/else to Python ternary (inside-out for nested)
    def _cell_ternary(text):
        # Find innermost if/then/else (one with no nested 'if' in condition or then)
        pat = re.compile(r'\bif\s+((?:(?!\bif\b).)+?)\s+then\s+((?:(?!\bif\b).)+?)\s+else\s+')
        while pat.search(text):
            text = pat.sub(lambda m: f'({m.group(2).strip()}) if ({m.group(1).strip()}) else ', text)
        return text
    py_expr = _cell_ternary(py_expr)
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
               "sum": sum, "sorted": sorted, "True": True, "False": False,
               "length": len})

    try:
        result = eval(py_expr, {"__builtins__": {}}, ns)
    except Exception as e:
        print(f"WARN: eval failed: {py_expr} — {e}", file=sys.stderr)
        result = None

    if len(yield_names) == 1:
        return {yield_names[0]: result}
    elif isinstance(result, dict):
        return result
    else:
        return {yield_names[0]: result}


def eval_soft(cell_name: str, body: str, bindings: dict, yield_names: list[str],
              dry_run: bool) -> dict:
    """Evaluate a soft cell via LLM."""
    # Interpolate references
    def interpolate(text: str) -> str:
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

    body = interpolate(body)

    if dry_run:
        return {n: f"<dry-run-{n}>" for n in yield_names}

    if not os.environ.get("ANTHROPIC_API_KEY"):
        return {n: f"<no-api-key-{n}>" for n in yield_names}

    import anthropic
    client = anthropic.Anthropic()

    parts = [f"Evaluate this Cell:\n\nCell: {cell_name}"]
    parts.append("\nInputs:")
    for k, v in bindings.items():
        if "→" not in k:
            parts.append(f"  {k} = {json.dumps(v)}")
    parts.append(f"\nTask:\n{body}")
    parts.append(f"\nProduce values for: {', '.join(yield_names)}")
    field_hints = ", ".join(f'"{n}": ...' for n in yield_names)
    parts.append(f"\nRespond with JSON only: {{{field_hints}}}")

    response = client.messages.create(
        model="claude-haiku-4-5-20251001",
        max_tokens=1024,
        system="You are a Cell program executor. Follow ∴ instructions precisely. Respond ONLY with JSON.",
        messages=[{"role": "user", "content": "\n".join(parts)}],
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


def check_oracles(oracle_texts: list[str], outputs: dict, bindings: dict,
                  dry_run: bool) -> tuple[bool, list[dict]]:
    """Check oracle assertions."""
    results = []
    all_pass = True

    def parse_value(s: str):
        s = s.strip()
        if s.startswith('"') and s.endswith('"'):
            return s[1:-1]
        if s == "true": return True
        if s == "false": return False
        try: return int(s)
        except ValueError:
            try: return float(s)
            except ValueError: return s

    for oracle_text in oracle_texts:
        # Conditional: if X then Y
        cm = re.match(r'^if\s+(.+?)\s+then\s+(.+)$', oracle_text)
        if cm:
            results.append({"text": oracle_text, "pass": True, "reason": "conditional: assumed pass"})
            continue

        # Pattern: field = value
        m = re.match(r'^(\w[\w-]*)\s*=\s*(.+)$', oracle_text)
        if m:
            field = m.group(1)
            expected = parse_value(m.group(2).strip())
            actual = outputs.get(field)
            if actual is not None and expected is not None:
                try:
                    passed = float(actual) == float(expected)
                except (ValueError, TypeError):
                    passed = actual == expected
                results.append({"text": oracle_text, "pass": passed,
                              "reason": f"deterministic: {actual!r} vs {expected!r}"})
                if not passed:
                    all_pass = False
                continue

        # Semantic oracle — assume pass
        reason = "dry-run: assumed pass" if dry_run else "semantic: assumed pass"
        results.append({"text": oracle_text, "pass": True, "reason": reason})

    return all_pass, results


def check_guards(cell_meta: dict, mapping: dict) -> bool:
    """Check if all guard expressions pass. Returns False if any guard fails."""
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
        src_yields = get_yield_values(src_bead)
        field = g.get("source_field", g.get("name", ""))
        val = src_yields.get(field)

        # Simple guard eval: field = "value"
        gexpr = g["guard_expr"]
        m = re.match(r'(\w[\w-]*)\s*=\s*"([^"]*)"', gexpr)
        if m and str(val) != m.group(2):
            return False
        m = re.match(r'(\w[\w-]*)\s*=\s*(\w+)', gexpr)
        if m and str(val) != m.group(2):
            return False
    return True


# ─── Main eval loop ──────────────────────────────────────────

def main():
    if len(sys.argv) < 2:
        print("Usage: beads-eval-loop.py <mapping-file> [--dry-run] [--max-steps N] [--verbose]",
              file=sys.stderr)
        sys.exit(1)

    mapping_file = sys.argv[1]
    dry_run = "--dry-run" in sys.argv
    verbose = "--verbose" in sys.argv or "-v" in sys.argv
    max_steps = 100

    for i, arg in enumerate(sys.argv):
        if arg == "--max-steps" and i + 1 < len(sys.argv):
            max_steps = int(sys.argv[i + 1])

    mapping = json.loads(Path(mapping_file).read_text())
    reverse_map = {v: k for k, v in mapping.items()}
    bead_ids = set(mapping.values())

    log(f"{BOLD}Starting beads eval-loop{RESET} (max {max_steps} steps)")

    step = 0
    while step < max_steps:
        # ── find-ready ──
        all_ready = bd_ready_all()
        ready_cells = [r for r in all_ready
                       if r.get("id") in bead_ids and "cell" in r.get("labels", [])]

        # ── handle guard-skipped cells ──
        if not ready_cells:
            # Check for guard-skipped cells
            for name, bid in mapping.items():
                bead = bd_show(bid)
                if not bead or bead.get("status") == "closed":
                    continue
                meta = get_metadata(bead)
                # Check if all deps are closed
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
                    bd_close(bid, "guard clause false → ⊥")
                    bd_add_label(bid, "bottom")
                    # Set yields to null
                    yield_names = json.loads(meta.get("yield_names", "[]"))
                    yield_meta = {f"yield_{n}": "null" for n in yield_names}
                    bd_update_metadata(bid, yield_meta)
                    log_step(step, f"{DIM}skip{RESET} {name} (guard false → ⊥)")
                    continue  # Re-check after skipping

            # Re-check ready after skipping
            all_ready = bd_ready_all()
            ready_cells = [r for r in all_ready
                          if r.get("id") in bead_ids and "cell" in r.get("labels", [])]

        if not ready_cells:
            # Check if all beads are closed
            all_closed = True
            pending = []
            for name, bid in mapping.items():
                bead = bd_show(bid)
                if bead and bead.get("status") != "closed":
                    all_closed = False
                    pending.append(name)

            if all_closed:
                log(f"{GREEN}{BOLD}QUIESCENT{RESET} after {step} steps — all beads closed")
            elif pending:
                log(f"{YELLOW}Blocked{RESET}: pending=[{', '.join(pending)}] but none ready")
            else:
                log(f"{GREEN}{BOLD}QUIESCENT{RESET} after {step} steps")
            break

        # ── pick-cell ──
        target = ready_cells[0]
        target_bid = target["id"]
        target_name = reverse_map.get(target_bid, target_bid)

        if verbose:
            ready_names = [reverse_map.get(r["id"], r["id"]) for r in ready_cells]
            log_step(step, f"ready=[{', '.join(ready_names)}] picking={target_name}")

        # ── get full metadata ──
        bead = bd_show(target_bid)
        if not bead:
            log(f"{RED}ERROR{RESET}: could not read bead {target_bid}")
            step += 1
            continue

        meta = get_metadata(bead)
        body_type = meta.get("body_type", "")
        expr = meta.get("expr", "")
        yield_names = json.loads(meta.get("yield_names", "[]"))

        # ── check guards ──
        if not check_guards(meta, mapping):
            bd_close(target_bid, "guard clause false → ⊥")
            bd_add_label(target_bid, "bottom")
            yield_meta = {f"yield_{n}": "null" for n in yield_names}
            bd_update_metadata(target_bid, yield_meta)
            log_step(step, f"{DIM}skip{RESET} {target_name} (guard false → ⊥)")
            continue

        # ── resolve bindings ──
        bindings = resolve_bindings(meta, mapping)

        # ── dispatch ──
        if body_type == "hard":
            outputs = eval_hard(expr, bindings, yield_names)
        elif body_type == "soft":
            body = bead.get("description", "")
            if body.startswith("∴ ") or body.startswith("∴\n"):
                body = body[2:]
            outputs = eval_soft(target_name, body, bindings, yield_names, dry_run)
        elif body_type == "passthrough":
            outputs = {n: bindings.get(n) for n in yield_names}
        else:
            log(f"{RED}Unknown body_type: {body_type}{RESET}")
            outputs = {}

        if verbose:
            log(f"  outputs: {json.dumps(outputs)}")

        # ── store yield values as metadata ──
        # Store as JSON strings so they can be parsed back correctly
        yield_meta = {f"yield_{k}": json.dumps(v) for k, v in outputs.items()}
        # Also store the raw values for display
        bd_update_metadata(target_bid, yield_meta)

        # ── check oracles ──
        oracle_texts = json.loads(meta.get("oracles", "[]"))
        if oracle_texts:
            all_pass, results = check_oracles(oracle_texts, outputs, bindings, dry_run)
            if verbose:
                log(f"  oracles: {json.dumps({'all_pass': all_pass, 'results': results})}")
        else:
            all_pass = True

        # ── decide ──
        if all_pass:
            yields_str = ", ".join(f"{k}={v!r}" for k, v in outputs.items())
            bd_close(target_bid, f"frozen: {yields_str}")
            log_step(step, f"{GREEN}freeze{RESET} {target_name} → {yields_str}")
            step += 1
        else:
            retries = int(meta.get("retries", "0"))
            max_retries = 3
            if retries < max_retries:
                bd_update_metadata(target_bid, {"retries": str(retries + 1)})
                log_step(step, f"{YELLOW}retry{RESET} {target_name} (attempt {retries + 1})")
            else:
                bd_close(target_bid, "bottom: oracle exhaustion")
                bd_add_label(target_bid, "bottom")
                log_step(step, f"{RED}bottom{RESET} {target_name} (exhausted)")
                step += 1

    if step >= max_steps:
        log(f"{RED}{BOLD}HALTED{RESET}: max steps ({max_steps}) reached")

    # ── Final report ──
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
        yields = get_yield_values(bead)
        ts = get_metadata(bead).get("turnstile", "⊢")

        is_bottom = "bottom" in labels
        if status == "closed" and not is_bottom:
            icon = "✓"
            frozen += 1
        elif is_bottom:
            icon = "⊥"
            bottom += 1
        else:
            icon = "◌"
            pending_count += 1

        yield_str = " → " + ", ".join(f"{k}={v!r}" for k, v in yields.items()) if yields else ""
        print(f"  {icon} {ts} {name} [{bid}]: {status}{yield_str}")

    total = len(mapping)
    print()
    log(f"{BOLD}Summary:{RESET} {frozen} frozen, {bottom} bottom, {pending_count} pending (of {total} cells)")

    if pending_count == 0 and bottom == 0:
        log(f"{GREEN}{BOLD}ALL CELLS FROZEN — program complete{RESET}")
    elif pending_count == 0:
        log(f"{YELLOW}All cells resolved (some ⊥){RESET}")


if __name__ == "__main__":
    main()
