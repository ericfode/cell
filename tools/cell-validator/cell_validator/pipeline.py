"""End-to-end pipeline: collect → tokenize → corrupt → dataset.

Usage: ./run.sh -m cell_validator.pipeline <cell-repo-root> [output-dir]
"""

from __future__ import annotations

import sys
from pathlib import Path

from .collect import collect_snippets
from .corrupt import generate_negatives
from .dataset import build_dataset, save_dataset
from .tokenizer import Vocab, tokenize


def main(cell_root: Path, output_dir: Path) -> None:
    output_dir.mkdir(parents=True, exist_ok=True)

    print("=" * 60)
    print("Cell Validator — Training Data Pipeline")
    print("=" * 60)

    print("\n[1/5] Collecting positive snippets...")
    positives = collect_snippets(cell_root)

    print(f"\n[2/5] Generating negative snippets...")
    negatives = generate_negatives(positives)

    print(f"\n[3/5] Tokenizing and building vocabulary...")
    all_tokens = [tokenize(s) for s in positives + negatives]
    vocab = Vocab()
    vocab.build(all_tokens)

    vocab_path = output_dir / "vocab.json"
    vocab.save(vocab_path)
    print(f"  Vocab size: {len(vocab)}")
    print(f"  Saved to: {vocab_path}")

    print(f"\n[4/5] Building dataset...")
    data = build_dataset(positives, negatives, vocab)

    print(f"\n[5/5] Saving dataset...")
    save_dataset(data, output_dir)

    print(f"\n{'=' * 60}")
    print("Pipeline complete!")
    print(f"  Positive samples: {len(positives)}")
    print(f"  Negative samples: {len(negatives)}")
    print(f"  Vocab size: {len(vocab)}")
    print(f"  Train: {data['train_X'].shape}")
    print(f"  Val: {data['val_X'].shape}")
    print(f"  Output: {output_dir}")
    print(f"{'=' * 60}")


if __name__ == "__main__":
    cell_root = Path(sys.argv[1]) if len(sys.argv) > 1 else Path("../..")
    output_dir = Path(sys.argv[2]) if len(sys.argv) > 2 else Path("data")
    main(cell_root, output_dir)
