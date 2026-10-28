#!/usr/bin/env bash
# CTREND_REVISIT_FILE_PURPOSE: Reproduce all eighteen empirical pipelines and fresh-run reports using the installed sealed inputs.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec "${PYTHON_BIN:-python3}" "$ROOT/scripts/reproduce_everything.py" "$@"
