#!/usr/bin/env bash
# Wrapper script for running cell-validator Python code on NixOS.
#
# NixOS needs LD_LIBRARY_PATH set for pip-installed binary wheels,
# and tinygrad needs PYTHON=1 since clang isn't in the default devshell.
#
# Usage: ./run.sh <script.py> [args...]
#        ./run.sh -c 'from tinygrad import Tensor; print(Tensor([1,2,3]).numpy())'

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VENV="$SCRIPT_DIR/.venv"

if [ ! -d "$VENV" ]; then
  echo "Error: venv not found. Run: cd $SCRIPT_DIR && uv venv .venv && uv pip install -e ." >&2
  exit 1
fi

# NixOS: binary wheels need these shared libraries
GCC_LIB=$(dirname "$(find /nix/store -maxdepth 3 -name 'libstdc++.so.6' -path '*gcc-*-lib*' 2>/dev/null | head -1)")
ZLIB=$(dirname "$(find /nix/store -maxdepth 3 -name 'libz.so.1' -path '*zlib-*' 2>/dev/null | head -1)")

export LD_LIBRARY_PATH="${GCC_LIB:+$GCC_LIB:}${ZLIB:+$ZLIB:}${LD_LIBRARY_PATH:-}"

# tinygrad: use Python backend (no clang in NixOS devshell)
export PYTHON="${PYTHON:-1}"

exec "$VENV/bin/python" "$@"
