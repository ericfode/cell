"""Small character-level transformer classifier for Cell validation.

Architecture:
  - Character embedding (vocab_size × 128) + learned positional embedding (512 × 128)
  - 4 transformer encoder layers, 4 attention heads, 128 dim, 256 FFN
  - Global average pooling → linear → sigmoid (binary classification)
  - ~500K parameters

Additional output: per-token attention entropy as a regularity signal.
"""

from __future__ import annotations

import math
from pathlib import Path

import numpy as np
from tinygrad import Tensor, dtypes
import tinygrad.nn as nn


class MultiHeadAttention:
    """Multi-head self-attention with attention weight tracking."""

    def __init__(self, dim: int, n_heads: int):
        assert dim % n_heads == 0
        self.n_heads = n_heads
        self.head_dim = dim // n_heads
        self.qkv = nn.Linear(dim, 3 * dim)
        self.out = nn.Linear(dim, dim)

    def __call__(self, x: Tensor, mask: Tensor | None = None) -> tuple[Tensor, Tensor]:
        """Forward pass. Returns (output, attention_weights)."""
        B, T, C = x.shape
        qkv = self.qkv(x).reshape(B, T, 3, self.n_heads, self.head_dim)
        qkv = qkv.permute(2, 0, 3, 1, 4)  # (3, B, H, T, D)
        q, k, v = qkv[0], qkv[1], qkv[2]

        scale = math.sqrt(self.head_dim)
        attn = (q @ k.transpose(-2, -1)) / scale  # (B, H, T, T)

        if mask is not None:
            # mask: (B, 1, 1, T) — True where padded
            attn = attn + mask * (-1e9)

        attn_weights = attn.softmax(-1)  # (B, H, T, T)
        out = (attn_weights @ v).transpose(1, 2).reshape(B, T, C)
        return self.out(out), attn_weights


class FeedForward:
    """Position-wise feed-forward with GELU activation."""

    def __init__(self, dim: int, ffn_dim: int):
        self.up = nn.Linear(dim, ffn_dim)
        self.down = nn.Linear(ffn_dim, dim)

    def __call__(self, x: Tensor) -> Tensor:
        return self.down(self.up(x).gelu())


class TransformerBlock:
    """Pre-norm transformer encoder block."""

    def __init__(self, dim: int, n_heads: int, ffn_dim: int):
        self.ln1 = nn.LayerNorm(dim)
        self.attn = MultiHeadAttention(dim, n_heads)
        self.ln2 = nn.LayerNorm(dim)
        self.ffn = FeedForward(dim, ffn_dim)

    def __call__(self, x: Tensor, mask: Tensor | None = None) -> tuple[Tensor, Tensor]:
        attn_out, attn_weights = self.attn(self.ln1(x), mask)
        x = x + attn_out
        x = x + self.ffn(self.ln2(x))
        return x, attn_weights


class CellTransformer:
    """Character-level transformer classifier for Cell validation.

    Args:
        vocab_size: Number of tokens in vocabulary.
        dim: Embedding/hidden dimension (default 128).
        n_layers: Number of transformer layers (default 4).
        n_heads: Number of attention heads (default 4).
        ffn_dim: Feed-forward intermediate dimension (default 256).
        max_len: Maximum sequence length (default 512).
    """

    def __init__(
        self,
        vocab_size: int,
        dim: int = 128,
        n_layers: int = 4,
        n_heads: int = 4,
        ffn_dim: int = 256,
        max_len: int = 512,
    ):
        self.vocab_size = vocab_size
        self.dim = dim
        self.max_len = max_len

        self.tok_embed = nn.Embedding(vocab_size, dim)
        self.pos_embed = nn.Embedding(max_len, dim)
        self.layers = [TransformerBlock(dim, n_heads, ffn_dim) for _ in range(n_layers)]
        self.ln_final = nn.LayerNorm(dim)
        self.classifier = nn.Linear(dim, 1)

    def __call__(
        self, x: Tensor, pad_mask: Tensor | None = None
    ) -> tuple[Tensor, list[Tensor]]:
        """Forward pass.

        Args:
            x: Token IDs, shape (B, T), dtype int.
            pad_mask: Boolean mask, shape (B, T), True where padded.

        Returns:
            logits: Shape (B,) — raw logits (apply sigmoid for probability).
            attn_weights: List of (B, H, T, T) attention weight tensors per layer.
        """
        B, T = x.shape

        # Embeddings
        positions = Tensor.arange(T).reshape(1, T).expand(B, T)
        h = self.tok_embed(x) + self.pos_embed(positions)

        # Attention mask: (B, 1, 1, T) for broadcasting over heads and query positions
        attn_mask = None
        if pad_mask is not None:
            attn_mask = pad_mask.reshape(B, 1, 1, T).float()

        # Transformer layers
        all_attn: list[Tensor] = []
        for layer in self.layers:
            h, attn_w = layer(h, attn_mask)
            all_attn.append(attn_w)

        h = self.ln_final(h)

        # Global average pooling (exclude padding)
        if pad_mask is not None:
            # Zero out padded positions before averaging
            token_mask = (1.0 - pad_mask.float()).reshape(B, T, 1)
            h = h * token_mask
            lengths = token_mask.sum(1)  # (B, 1)
            pooled = h.sum(1) / lengths.maximum(Tensor(1.0))
        else:
            pooled = h.mean(1)  # (B, dim)

        logits = self.classifier(pooled).reshape(B)
        return logits, all_attn


def attention_entropy(attn_weights: list[Tensor], pad_mask: Tensor | None = None) -> Tensor:
    """Compute per-token attention entropy averaged across layers and heads.

    Higher entropy = more uniform attention = more regular structure.
    Lower entropy = sharper attention = potentially irregular/broken structure.

    Args:
        attn_weights: List of (B, H, T, T) attention weight tensors.
        pad_mask: (B, T) boolean mask, True where padded.

    Returns:
        entropy: (B,) mean attention entropy per sample.
    """
    # Stack all layers: (L, B, H, T, T)
    stacked = Tensor.stack(*attn_weights)
    # Mean over layers and heads: (B, T, T)
    mean_attn = stacked.mean(0).mean(1)

    # Entropy: -sum(p * log(p)) per query position
    eps = 1e-8
    log_attn = (mean_attn + eps).log()
    ent = -(mean_attn * log_attn).sum(-1)  # (B, T)

    if pad_mask is not None:
        # Zero out padding positions
        token_mask = 1.0 - pad_mask.float()
        ent = ent * token_mask
        lengths = token_mask.sum(-1).maximum(Tensor(1.0))
        return ent.sum(-1) / lengths  # (B,)

    return ent.mean(-1)  # (B,)


def count_parameters(model: CellTransformer) -> int:
    """Count total trainable parameters."""
    from tinygrad.nn.state import get_state_dict
    total = 0
    for v in get_state_dict(model).values():
        total += math.prod(v.shape)
    return total


def save_model(model: CellTransformer, path: Path) -> None:
    """Save model state dict as numpy .npz file."""
    from tinygrad.nn.state import get_state_dict
    state = {k: v.numpy() for k, v in get_state_dict(model).items()}
    np.savez(str(path), **state)


def load_model(model: CellTransformer, path: Path) -> None:
    """Load model state dict from numpy .npz file."""
    from tinygrad.nn.state import get_state_dict, load_state_dict
    loaded = np.load(str(path))
    state = get_state_dict(model)
    for k in state:
        if k in loaded:
            state[k].assign(Tensor(loaded[k]))
    Tensor.realize(*state.values())
