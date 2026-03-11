"""Scan .cell files and window them into training snippets.

Walks the cell repo, collects all .cell files, and slices them into
overlapping windows of 20-50 lines with stride 10.
"""

from __future__ import annotations

import random
from pathlib import Path

DEFAULT_WINDOW_MIN = 20
DEFAULT_WINDOW_MAX = 50
DEFAULT_STRIDE = 10
TARGET_SNIPPETS = 2000


def find_cell_files(root: Path) -> list[Path]:
    """Find all .cell files under root, sorted for reproducibility."""
    return sorted(root.rglob("*.cell"))


def window_file(
    text: str,
    *,
    window_min: int = DEFAULT_WINDOW_MIN,
    window_max: int = DEFAULT_WINDOW_MAX,
    stride: int = DEFAULT_STRIDE,
    rng: random.Random | None = None,
) -> list[str]:
    """Slice a file into overlapping line-based windows.

    Returns list of snippet strings.
    """
    if rng is None:
        rng = random.Random(42)

    lines = text.split("\n")
    if len(lines) < window_min:
        return [text] if text.strip() else []

    snippets = []
    i = 0
    while i + window_min <= len(lines):
        win_size = rng.randint(window_min, min(window_max, len(lines) - i))
        snippet = "\n".join(lines[i : i + win_size])
        if snippet.strip():
            snippets.append(snippet)
        i += stride

    return snippets


def collect_snippets(
    root: Path,
    *,
    target: int = TARGET_SNIPPETS,
    seed: int = 42,
) -> list[str]:
    """Collect positive training snippets from all .cell files."""
    rng = random.Random(seed)
    files = find_cell_files(root)
    print(f"Found {len(files)} .cell files")

    all_snippets: list[str] = []
    for f in files:
        text = f.read_text(errors="replace")
        snippets = window_file(text, rng=rng)
        all_snippets.extend(snippets)

    print(f"Collected {len(all_snippets)} raw snippets")

    # Subsample if too many, or note if fewer than target
    if len(all_snippets) > target:
        rng.shuffle(all_snippets)
        all_snippets = all_snippets[:target]
        print(f"Subsampled to {target} snippets")
    elif len(all_snippets) < target:
        print(f"Note: only {len(all_snippets)} snippets (target was {target})")

    return all_snippets


if __name__ == "__main__":
    import sys

    root = Path(sys.argv[1]) if len(sys.argv) > 1 else Path(".")
    snippets = collect_snippets(root)
    print(f"\nFinal: {len(snippets)} positive snippets")
    if snippets:
        print(f"\nSample snippet (first 5 lines):")
        for line in snippets[0].split("\n")[:5]:
            print(f"  {line}")
