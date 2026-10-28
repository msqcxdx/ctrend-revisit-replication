#!/usr/bin/env bash
# CTREND_REVISIT_FILE_PURPOSE: Recalculate the author's factor moments and redraw rights-cleared saved aggregates in a fresh directory.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
[[ $# -le 1 ]] || { echo 'usage: reproduce_tables.sh [FRESH_OUTPUT_DIR]' >&2; exit 2; }
OUTPUT="${1:-$ROOT/outputs/public_tables}"
exec "${PYTHON_BIN:-python3}" "$ROOT/scripts/reproduce_public_tables.py" "$OUTPUT"
