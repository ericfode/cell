"""Character-level tokenizer with Cell-aware token merges.

Special tokens get their own IDs. All other characters are individual tokens.
Whitespace is tracked as INDENT/DEDENT/NEWLINE. Comments (--) are single tokens.
"""

from __future__ import annotations

import json
import re
from pathlib import Path

# Special multi-char tokens that get their own IDs (order matters: longest first)
SPECIAL_TOKENS = [
    "⊢=", "⊢⊢", "⊢∘", "⊢",
    "⊨?", "⊨",
    "⊥?", "⊥",
    "∴", "≡", "→", "§",
    "«", "»",
    "##/", "##", "#/",
]

# Structural tokens
PAD = "<PAD>"
UNK = "<UNK>"
INDENT = "<INDENT>"
DEDENT = "<DEDENT>"
NEWLINE = "<NEWLINE>"
COMMENT = "<COMMENT>"

CONTROL_TOKENS = [PAD, UNK, INDENT, DEDENT, NEWLINE, COMMENT]


def tokenize(text: str) -> list[str]:
    """Tokenize Cell source text into a list of string tokens."""
    tokens: list[str] = []
    lines = text.split("\n")
    indent_stack = [0]

    for line_idx, line in enumerate(lines):
        if line_idx > 0:
            tokens.append(NEWLINE)

        # Measure leading spaces for indent tracking
        stripped = line.lstrip(" ")
        n_spaces = len(line) - len(stripped)

        # Emit INDENT/DEDENT
        if stripped:  # skip blank lines for indent tracking
            if n_spaces > indent_stack[-1]:
                indent_stack.append(n_spaces)
                tokens.append(INDENT)
            else:
                while indent_stack[-1] > n_spaces and len(indent_stack) > 1:
                    indent_stack.pop()
                    tokens.append(DEDENT)

        # Check for comment
        comment_match = re.search(r"--", stripped)
        if comment_match is not None:
            before = stripped[: comment_match.start()]
            _tokenize_fragment(before, tokens)
            tokens.append(COMMENT)
            continue

        _tokenize_fragment(stripped, tokens)

    # Close remaining indents
    while len(indent_stack) > 1:
        indent_stack.pop()
        tokens.append(DEDENT)

    return tokens


def _tokenize_fragment(text: str, tokens: list[str]) -> None:
    """Tokenize a text fragment (no newlines, no comments) into tokens."""
    i = 0
    while i < len(text):
        matched = False
        for special in SPECIAL_TOKENS:
            if text[i:].startswith(special):
                tokens.append(special)
                i += len(special)
                matched = True
                break
        if not matched:
            tokens.append(text[i])
            i += 1


class Vocab:
    """Token vocabulary with encode/decode."""

    def __init__(self) -> None:
        self.token_to_id: dict[str, int] = {}
        self.id_to_token: dict[int, str] = {}

    def build(self, corpus_tokens: list[list[str]]) -> None:
        """Build vocabulary from a list of tokenized documents."""
        # Reserve control and special tokens first
        for tok in CONTROL_TOKENS + SPECIAL_TOKENS:
            self._add(tok)

        # Add all tokens from corpus
        for doc_tokens in corpus_tokens:
            for tok in doc_tokens:
                self._add(tok)

    def _add(self, token: str) -> int:
        if token not in self.token_to_id:
            idx = len(self.token_to_id)
            self.token_to_id[token] = idx
            self.id_to_token[idx] = token
        return self.token_to_id[token]

    def encode(self, tokens: list[str]) -> list[int]:
        unk_id = self.token_to_id[UNK]
        return [self.token_to_id.get(t, unk_id) for t in tokens]

    def decode(self, ids: list[int]) -> list[str]:
        return [self.id_to_token.get(i, UNK) for i in ids]

    def save(self, path: Path) -> None:
        with open(path, "w") as f:
            json.dump(self.token_to_id, f, ensure_ascii=False, indent=2)

    def load(self, path: Path) -> None:
        with open(path) as f:
            self.token_to_id = json.load(f)
        self.id_to_token = {v: k for k, v in self.token_to_id.items()}

    def __len__(self) -> int:
        return len(self.token_to_id)


if __name__ == "__main__":
    import sys

    if len(sys.argv) < 2:
        print("Usage: tokenizer.py <file.cell>")
        sys.exit(1)

    text = Path(sys.argv[1]).read_text()
    tokens = tokenize(text)
    print(f"Tokens ({len(tokens)}):")
    for t in tokens:
        print(f"  {t!r}")
