#!/usr/bin/env bash
# CTREND_REVISIT_FILE_PURPOSE: Install the shared, checksum-verified research data bundle without mixing snapshots.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SOURCE="${1:-}"
[[ $# -ge 1 && $# -le 2 && -d "$SOURCE" ]] || { echo "usage: $0 CMC_EXPORT_DIRECTORY AUX_DATA_DIRECTORY (or: $0 LEGACY_COMPLETE_BUNDLE)" >&2; exit 2; }
ARGS=(install --source "$SOURCE" --root "$ROOT")
if [[ $# -eq 2 ]]; then
  ARGS+=(--aux-data-dir "$2")
fi
exec "${PYTHON_BIN:-python3}" "$ROOT/scripts/data_bundle.py" "${ARGS[@]}"
