#!/bin/bash
# eval-one: Run the Cell eval-one loop
#
# Usage:
#   ./run.sh <program.cell> [options]
#   ./run.sh --test              # Run validation tests with simulated data
#
# Options:
#   --spec <path>     Cell spec for LLM context
#   --dry-run         No LLM calls, placeholder outputs
#   --simulate <file> Use pre-recorded JSON responses
#   --output-dir <d>  Where to write frame .cell files
#
# For live execution, set ANTHROPIC_API_KEY in your environment.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
VENV="$SCRIPT_DIR/.venv"

if [ ! -d "$VENV" ]; then
    echo "Creating virtual environment..."
    uv venv "$VENV"
    source "$VENV/bin/activate"
    uv pip install anthropic
else
    source "$VENV/bin/activate"
fi

if [ "$1" = "--test" ]; then
    echo "=== Validation Test Suite ==="
    echo ""

    echo "--- Test 1: p1-parallel-confluence (simulated) ---"
    python "$SCRIPT_DIR/eval_one.py" \
        "$REPO_ROOT/evolution/round-15/programs/p1-parallel-confluence.cell" \
        --simulate "$SCRIPT_DIR/sim-p1-confluence.json" \
        --output-dir /tmp/eval-one-test-p1
    echo ""

    echo "--- Test 2: mixed-hard-soft correct answer (simulated) ---"
    python "$SCRIPT_DIR/eval_one.py" \
        "$REPO_ROOT/docs/examples/mixed-hard-soft.cell" \
        --simulate "$SCRIPT_DIR/sim-mixed-hard-soft.json" \
        --output-dir /tmp/eval-one-test-mhs
    echo ""

    echo "--- Test 3: mixed-hard-soft wrong answer → ⊥ (simulated) ---"
    python "$SCRIPT_DIR/eval_one.py" \
        "$REPO_ROOT/docs/examples/mixed-hard-soft.cell" \
        --simulate "$SCRIPT_DIR/sim-mixed-wrong.json" \
        --output-dir /tmp/eval-one-test-wrong
    echo ""

    echo "=== All tests complete ==="
    exit 0
fi

python "$SCRIPT_DIR/eval_one.py" "$@"
