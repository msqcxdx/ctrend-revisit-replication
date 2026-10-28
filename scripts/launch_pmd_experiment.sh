#!/usr/bin/env bash
# CTREND_REVISIT_FILE_PURPOSE: launch pmd experiment; publication orchestration, validation or saved-result analysis, not a model-definition edit.
# Launch one explicitly selected P/M/D experiment with a unique log and PGID.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ID="${1:-}"
[[ "$ID" =~ ^P[01]_M[012]_D[012]$ ]] || exit 2
mkdir -p "$ROOT/outputs/logs"
STAMP="$(date -u +%Y%m%d_%H%M%S_%N)"
LOG="$ROOT/outputs/logs/${ID}_${STAMP}.log"
nohup setsid "$ROOT/scripts/run_pmd_experiment.sh" "$ID" production \
  > "$LOG" 2>&1 < /dev/null &
PID=$!
printf '%s\n' "$PID" > "${LOG%.log}.pid"
printf 'experiment=%s pid=%s log=%s\n' "$ID" "$PID" "$LOG"
