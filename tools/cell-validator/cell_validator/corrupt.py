"""Corruption engine — generate negative samples from positive Cell snippets.

Six corruption strategies:
  a. Symbol swap: replace ⊢ with random Unicode
  b. Structure break: remove indentation, shuffle lines
  c. Markdown injection: insert # headers, bullet points, code fences
  d. Missing yields: delete yield lines
  e. Broken references: mangle cell→field to cell.field
  f. Random char insertion/deletion
"""

from __future__ import annotations

import random
import re

# Unicode characters to swap Cell symbols with
DECOY_SYMBOLS = ["├", "╔", "║", "▶", "◆", "●", "★", "✓", "✗", "⬤", "▲", "■", "⊕", "⊗"]
CELL_SYMBOLS = ["⊢=", "⊢⊢", "⊢∘", "⊢", "⊨?", "⊨", "⊥?", "⊥", "∴", "≡", "→", "§"]

# Markdown patterns to inject
MARKDOWN_INJECTIONS = [
    "# Section Header",
    "## Subsection",
    "- bullet point item",
    "* another bullet",
    "```python\nprint('hello')\n```",
    "```\ncode block\n```",
    "1. numbered item",
    "> blockquote text",
    "| col1 | col2 |",
    "---",
    "***",
    "[link](http://example.com)",
]


def corrupt_symbol_swap(text: str, rng: random.Random) -> str:
    """Replace Cell-specific symbols with random Unicode decoys."""
    result = text
    # Pick 1-3 symbols to swap
    present = [s for s in CELL_SYMBOLS if s in result]
    if not present:
        return result
    n_swaps = min(rng.randint(1, 3), len(present))
    targets = rng.sample(present, n_swaps)
    for sym in targets:
        decoy = rng.choice(DECOY_SYMBOLS)
        result = result.replace(sym, decoy, 1)
    return result


def corrupt_structure_break(text: str, rng: random.Random) -> str:
    """Break indentation structure or shuffle lines."""
    lines = text.split("\n")
    strategy = rng.choice(["dedent", "shuffle_block", "flatten"])

    if strategy == "dedent":
        # Remove all indentation
        return "\n".join(line.lstrip() for line in lines)
    elif strategy == "shuffle_block":
        # Shuffle a block of consecutive lines
        if len(lines) < 4:
            return text
        start = rng.randint(0, max(0, len(lines) - 4))
        end = min(start + rng.randint(3, 6), len(lines))
        block = lines[start:end]
        rng.shuffle(block)
        return "\n".join(lines[:start] + block + lines[end:])
    else:  # flatten
        # Remove blank lines and reduce to single space indent
        return "\n".join(
            " " + line.strip() if line.strip() else "" for line in lines
        )


def corrupt_markdown_inject(text: str, rng: random.Random) -> str:
    """Insert markdown syntax into Cell code."""
    lines = text.split("\n")
    n_inject = rng.randint(1, 3)
    for _ in range(n_inject):
        pos = rng.randint(0, len(lines))
        injection = rng.choice(MARKDOWN_INJECTIONS)
        lines.insert(pos, injection)
    return "\n".join(lines)


def corrupt_missing_yields(text: str, rng: random.Random) -> str:
    """Delete lines containing 'yield'."""
    lines = text.split("\n")
    yield_lines = [i for i, line in enumerate(lines) if "yield" in line.lower()]
    if not yield_lines:
        return text
    # Remove 1-all yield lines
    n_remove = rng.randint(1, len(yield_lines))
    to_remove = set(rng.sample(yield_lines, n_remove))
    return "\n".join(line for i, line in enumerate(lines) if i not in to_remove)


def corrupt_broken_refs(text: str, rng: random.Random) -> str:
    """Mangle cell→field references to cell.field or cell_field."""
    # Replace → with . or _
    replacements = [".", "_", "->", "::", "/"]
    result = text
    # Find all → occurrences
    arrow_positions = [m.start() for m in re.finditer("→", result)]
    if not arrow_positions:
        return result
    n_replace = rng.randint(1, len(arrow_positions))
    positions = sorted(rng.sample(arrow_positions, n_replace), reverse=True)
    result_list = list(result)
    for pos in positions:
        repl = rng.choice(replacements)
        # → is 3 bytes in UTF-8 but 1 char in Python
        result = result[:pos] + repl + result[pos + 1:]
    return result


def corrupt_random_chars(text: str, rng: random.Random) -> str:
    """Insert or delete random characters."""
    chars = list(text)
    n_ops = rng.randint(2, max(3, len(chars) // 50))
    for _ in range(n_ops):
        if not chars:
            break
        op = rng.choice(["insert", "delete", "replace"])
        pos = rng.randint(0, max(0, len(chars) - 1))
        if op == "insert":
            chars.insert(pos, rng.choice("@$%^&*!~`|\\{}[]<>"))
        elif op == "delete" and chars:
            chars.pop(pos)
        elif op == "replace" and chars:
            chars[pos] = rng.choice("@$%^&*!~`|\\{}[]<>")
    return "".join(chars)


# All corruption strategies
CORRUPTIONS = [
    corrupt_symbol_swap,
    corrupt_structure_break,
    corrupt_markdown_inject,
    corrupt_missing_yields,
    corrupt_broken_refs,
    corrupt_random_chars,
]


def corrupt_snippet(text: str, rng: random.Random) -> str:
    """Apply 1-2 random corruption strategies to a snippet."""
    n_corruptions = rng.randint(1, 2)
    strategies = rng.sample(CORRUPTIONS, n_corruptions)
    result = text
    for strategy in strategies:
        result = strategy(result, rng)
    return result


def generate_negatives(
    positives: list[str],
    *,
    target: int = 2000,
    seed: int = 42,
) -> list[str]:
    """Generate negative samples from positive snippets.

    Each positive generates 1-2 corruptions. Returns up to target negatives.
    """
    rng = random.Random(seed)
    negatives: list[str] = []

    for snippet in positives:
        n = rng.randint(1, 2)
        for _ in range(n):
            neg = corrupt_snippet(snippet, rng)
            if neg != snippet:  # only keep if actually different
                negatives.append(neg)
            if len(negatives) >= target:
                break
        if len(negatives) >= target:
            break

    print(f"Generated {len(negatives)} negative snippets from {len(positives)} positives")
    return negatives[:target]


if __name__ == "__main__":
    # Quick test with sample text
    sample = """\
⊢ solve
  given equation ≡ "2x + 3 = 11"
  yield x, proof[]

  ∴ Solve «equation» for x.

  ⊨ x is a number
"""
    rng = random.Random(42)
    print("Original:")
    print(sample)
    for i, fn in enumerate(CORRUPTIONS):
        print(f"\nCorruption {i} ({fn.__name__}):")
        print(fn(sample, random.Random(42)))
