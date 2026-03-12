"""Training script for the Cell transformer validator.

Usage: ./run.sh -m cell_validator.train [data-dir] [--epochs N] [--batch-size N]

Loads dataset from the data pipeline, trains the transformer classifier,
logs metrics per epoch, and saves the best model checkpoint.
"""

from __future__ import annotations

import argparse
import json
import math
import time
from pathlib import Path

import numpy as np
from tinygrad import Tensor, dtypes
from tinygrad.nn.optim import AdamW
from tinygrad.nn.state import get_state_dict

from .dataset import load_dataset
from .model import CellTransformer, attention_entropy, count_parameters, save_model, load_model
from .tokenizer import Vocab


def binary_cross_entropy(logits: Tensor, targets: Tensor) -> Tensor:
    """Binary cross-entropy loss from raw logits (numerically stable)."""
    # BCE with logits: max(logits, 0) - logits * targets + log(1 + exp(-|logits|))
    relu_logits = logits.relu()
    abs_logits = logits.abs()
    return (relu_logits - logits * targets + (1 + (-abs_logits).exp()).log()).mean()


def compute_accuracy(logits: Tensor, targets: Tensor) -> float:
    """Compute binary classification accuracy."""
    preds = (logits.sigmoid() > 0.5).float()
    return (preds == targets.float()).mean().item()


def make_batches(
    X: np.ndarray, y: np.ndarray, batch_size: int, rng: np.random.Generator
) -> list[tuple[np.ndarray, np.ndarray]]:
    """Shuffle and batch the data."""
    n = len(X)
    perm = rng.permutation(n)
    X, y = X[perm], y[perm]
    batches = []
    for i in range(0, n, batch_size):
        batches.append((X[i : i + batch_size], y[i : i + batch_size]))
    return batches


def train(
    data_dir: Path,
    output_dir: Path | None = None,
    epochs: int = 50,
    batch_size: int = 32,
    lr: float = 3e-4,
    seed: int = 42,
) -> dict:
    """Train the Cell transformer validator.

    Returns dict with final metrics.
    """
    if output_dir is None:
        output_dir = data_dir

    rng = np.random.default_rng(seed)

    # Load data
    print("Loading dataset...")
    data = load_dataset(data_dir)
    train_X, train_y = data["train_X"], data["train_y"]
    val_X, val_y = data["val_X"], data["val_y"]
    print(f"  Train: {train_X.shape[0]} samples")
    print(f"  Val: {val_X.shape[0]} samples")
    print(f"  Sequence length: {train_X.shape[1]}")

    # Load vocab
    vocab_path = data_dir / "vocab.json"
    vocab = Vocab()
    vocab.load(vocab_path)
    vocab_size = len(vocab)
    pad_id = vocab.token_to_id["<PAD>"]
    print(f"  Vocab size: {vocab_size}")

    # Build model
    max_len = train_X.shape[1]
    model = CellTransformer(vocab_size=vocab_size, max_len=max_len)
    n_params = count_parameters(model)
    print(f"\nModel: {n_params:,} parameters")

    # Optimizer
    params = list(get_state_dict(model).values())
    opt = AdamW(params, lr=lr)

    # Training loop
    best_val_loss = float("inf")
    best_epoch = -1
    history: list[dict] = []

    print(f"\nTraining for {epochs} epochs (batch_size={batch_size}, lr={lr})")
    print("-" * 70)

    for epoch in range(epochs):
        t0 = time.time()

        # Train
        Tensor.training = True
        train_batches = make_batches(train_X, train_y, batch_size, rng)
        train_loss_sum = 0.0
        train_correct = 0
        train_total = 0

        for bx, by in train_batches:
            x = Tensor(bx, dtype=dtypes.int)
            targets = Tensor(by, dtype=dtypes.float)
            pad_mask = (x == pad_id)

            logits, _ = model(x, pad_mask)
            loss = binary_cross_entropy(logits, targets)

            loss.backward()
            opt.step()
            opt.zero_grad()

            bs = len(bx)
            train_loss_sum += loss.item() * bs
            preds = (logits.sigmoid() > 0.5).numpy()
            train_correct += (preds == by).sum()
            train_total += bs

        train_loss = train_loss_sum / train_total
        train_acc = train_correct / train_total

        # Validate
        Tensor.training = False
        val_batches = make_batches(val_X, val_y, batch_size, rng)
        val_loss_sum = 0.0
        val_correct = 0
        val_total = 0

        Tensor.no_grad = True
        for bx, by in val_batches:
            x = Tensor(bx, dtype=dtypes.int)
            targets = Tensor(by, dtype=dtypes.float)
            pad_mask = (x == pad_id)

            logits, _ = model(x, pad_mask)
            loss = binary_cross_entropy(logits, targets)

            bs = len(bx)
            val_loss_sum += loss.item() * bs
            preds = (logits.sigmoid() > 0.5).numpy()
            val_correct += (preds == by).sum()
            val_total += bs
        Tensor.no_grad = False

        val_loss = val_loss_sum / val_total
        val_acc = val_correct / val_total
        elapsed = time.time() - t0

        epoch_metrics = {
            "epoch": epoch + 1,
            "train_loss": round(train_loss, 4),
            "train_acc": round(train_acc, 4),
            "val_loss": round(val_loss, 4),
            "val_acc": round(val_acc, 4),
            "time_s": round(elapsed, 1),
        }
        history.append(epoch_metrics)

        marker = ""
        if val_loss < best_val_loss:
            best_val_loss = val_loss
            best_epoch = epoch + 1
            marker = " *"
            # Save best checkpoint
            save_model(model, output_dir / "model.npz")

        print(
            f"Epoch {epoch+1:3d}/{epochs} | "
            f"loss: {train_loss:.4f} acc: {train_acc:.4f} | "
            f"val_loss: {val_loss:.4f} val_acc: {val_acc:.4f} | "
            f"{elapsed:.1f}s{marker}"
        )

    print("-" * 70)
    print(f"Best val_loss: {best_val_loss:.4f} at epoch {best_epoch}")
    print(f"Model saved: {output_dir / 'model.npz'}")

    # Save training history
    history_path = output_dir / "training_history.json"
    with open(history_path, "w") as f:
        json.dump(history, f, indent=2)
    print(f"History saved: {history_path}")

    # Compute evaluation metrics on val set with best model
    print("\n" + "=" * 70)
    print("Evaluation on validation set (best checkpoint)")
    print("=" * 70)

    load_model(model, output_dir / "model.npz")

    eval_metrics = evaluate(model, val_X, val_y, pad_id, batch_size)

    # Save eval metrics
    eval_path = output_dir / "eval_metrics.json"
    with open(eval_path, "w") as f:
        json.dump(eval_metrics, f, indent=2)
    print(f"\nMetrics saved: {eval_path}")

    return eval_metrics


def evaluate(
    model: CellTransformer,
    X: np.ndarray,
    y: np.ndarray,
    pad_id: int,
    batch_size: int = 32,
) -> dict:
    """Evaluate model and compute detailed metrics."""
    all_preds = []
    all_probs = []
    all_entropy = []

    Tensor.training = False
    Tensor.no_grad = True
    for i in range(0, len(X), batch_size):
        bx = X[i : i + batch_size]
        x = Tensor(bx, dtype=dtypes.int)
        pad_mask = (x == pad_id)

        logits, attn_weights = model(x, pad_mask)
        probs = logits.sigmoid().numpy()
        preds = (probs > 0.5).astype(int)
        ent = attention_entropy(attn_weights, pad_mask).numpy()

        all_preds.extend(preds.tolist())
        all_probs.extend(probs.tolist())
        all_entropy.extend(ent.tolist())
    Tensor.no_grad = False
    Tensor.training = True

    all_preds = np.array(all_preds)
    all_probs = np.array(all_probs)
    all_entropy = np.array(all_entropy)

    # Confusion matrix
    tp = int(((all_preds == 1) & (y == 1)).sum())
    fp = int(((all_preds == 1) & (y == 0)).sum())
    tn = int(((all_preds == 0) & (y == 0)).sum())
    fn = int(((all_preds == 0) & (y == 1)).sum())

    accuracy = (tp + tn) / max(1, tp + fp + tn + fn)
    precision = tp / max(1, tp + fp)
    recall = tp / max(1, tp + fn)
    f1 = 2 * precision * recall / max(1e-8, precision + recall)

    # Regularity score: average confidence on valid (positive) samples
    valid_mask = y == 1
    regularity_score = float(all_probs[valid_mask].mean()) if valid_mask.any() else 0.0

    # Entropy stats
    valid_entropy = float(all_entropy[valid_mask].mean()) if valid_mask.any() else 0.0
    invalid_entropy = float(all_entropy[~valid_mask].mean()) if (~valid_mask).any() else 0.0

    metrics = {
        "accuracy": round(accuracy, 4),
        "precision": round(precision, 4),
        "recall": round(recall, 4),
        "f1": round(f1, 4),
        "regularity_score": round(regularity_score, 4),
        "confusion_matrix": {"tp": tp, "fp": fp, "tn": tn, "fn": fn},
        "valid_entropy_mean": round(valid_entropy, 4),
        "invalid_entropy_mean": round(invalid_entropy, 4),
    }

    print(f"Accuracy:  {accuracy:.4f}")
    print(f"Precision: {precision:.4f}")
    print(f"Recall:    {recall:.4f}")
    print(f"F1:        {f1:.4f}")
    print(f"Regularity score (avg confidence on valid): {regularity_score:.4f}")
    print(f"\nConfusion Matrix:")
    print(f"  TP={tp}  FP={fp}")
    print(f"  FN={fn}  TN={tn}")
    print(f"\nAttention entropy:")
    print(f"  Valid samples:   {valid_entropy:.4f}")
    print(f"  Invalid samples: {invalid_entropy:.4f}")

    if accuracy < 0.85:
        print(
            "\n⚠ Accuracy below 85% — the language may be too irregular "
            "for structural learning. This is a useful finding."
        )

    return metrics


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Train Cell transformer validator")
    parser.add_argument("data_dir", nargs="?", default="data", help="Dataset directory")
    parser.add_argument("--output-dir", default=None, help="Output directory (default: data_dir)")
    parser.add_argument("--epochs", type=int, default=50)
    parser.add_argument("--batch-size", type=int, default=32)
    parser.add_argument("--lr", type=float, default=3e-4)
    parser.add_argument("--seed", type=int, default=42)
    args = parser.parse_args()

    train(
        data_dir=Path(args.data_dir),
        output_dir=Path(args.output_dir) if args.output_dir else None,
        epochs=args.epochs,
        batch_size=args.batch_size,
        lr=args.lr,
        seed=args.seed,
    )
