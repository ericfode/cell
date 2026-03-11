"""Dataset builder — combine positive and negative samples into training arrays.

Tokenizes, pads/truncates to fixed length, splits train/val, saves as numpy.
"""

from __future__ import annotations

from pathlib import Path

import numpy as np

from .tokenizer import Vocab, tokenize

MAX_SEQ_LEN = 512
TRAIN_RATIO = 0.8


def build_dataset(
    positives: list[str],
    negatives: list[str],
    vocab: Vocab,
    *,
    max_len: int = MAX_SEQ_LEN,
    train_ratio: float = TRAIN_RATIO,
    seed: int = 42,
) -> dict[str, np.ndarray]:
    """Build tokenized dataset from positive and negative snippets.

    Returns dict with keys: train_X, train_y, val_X, val_y
    """
    rng = np.random.default_rng(seed)

    # Tokenize and encode all samples
    samples: list[tuple[list[int], int]] = []

    for text in positives:
        tokens = tokenize(text)
        ids = vocab.encode(tokens)
        samples.append((ids, 1))

    for text in negatives:
        tokens = tokenize(text)
        ids = vocab.encode(tokens)
        samples.append((ids, 0))

    print(f"Total samples: {len(samples)} (pos={len(positives)}, neg={len(negatives)})")

    # Pad/truncate to fixed length
    pad_id = vocab.token_to_id["<PAD>"]
    X = np.full((len(samples), max_len), pad_id, dtype=np.int32)
    y = np.zeros(len(samples), dtype=np.int32)

    for i, (ids, label) in enumerate(samples):
        length = min(len(ids), max_len)
        X[i, :length] = ids[:length]
        y[i] = label

    # Shuffle
    perm = rng.permutation(len(samples))
    X = X[perm]
    y = y[perm]

    # Split
    split = int(len(samples) * train_ratio)
    result = {
        "train_X": X[:split],
        "train_y": y[:split],
        "val_X": X[split:],
        "val_y": y[split:],
    }

    print(f"Train: {result['train_X'].shape[0]} samples")
    print(f"Val: {result['val_X'].shape[0]} samples")
    print(f"Sequence length: {max_len}")
    print(f"Vocab size: {len(vocab)}")

    return result


def save_dataset(data: dict[str, np.ndarray], output_dir: Path) -> None:
    """Save dataset arrays to numpy files."""
    output_dir.mkdir(parents=True, exist_ok=True)
    for name, arr in data.items():
        path = output_dir / f"{name}.npy"
        np.save(path, arr)
        print(f"Saved {path} ({arr.shape})")


def load_dataset(output_dir: Path) -> dict[str, np.ndarray]:
    """Load dataset arrays from numpy files."""
    data = {}
    for name in ["train_X", "train_y", "val_X", "val_y"]:
        path = output_dir / f"{name}.npy"
        data[name] = np.load(path)
    return data


if __name__ == "__main__":
    import sys

    from .collect import collect_snippets
    from .corrupt import generate_negatives

    root = Path(sys.argv[1]) if len(sys.argv) > 1 else Path("../..")
    output_dir = Path(sys.argv[2]) if len(sys.argv) > 2 else Path("data")

    print("=== Collecting positive snippets ===")
    positives = collect_snippets(root)

    print("\n=== Generating negative snippets ===")
    negatives = generate_negatives(positives)

    print("\n=== Building vocabulary ===")
    vocab = Vocab()
    all_tokens = [tokenize(s) for s in positives + negatives]
    vocab.build(all_tokens)

    vocab_path = output_dir / "vocab.json"
    output_dir.mkdir(parents=True, exist_ok=True)
    vocab.save(vocab_path)
    print(f"Vocab size: {len(vocab)}, saved to {vocab_path}")

    print("\n=== Building dataset ===")
    data = build_dataset(positives, negatives, vocab)
    save_dataset(data, output_dir)

    print("\n=== Done ===")
