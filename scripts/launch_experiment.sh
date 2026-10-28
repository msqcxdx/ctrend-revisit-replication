#!/usr/bin/env bash
# CTREND_REVISIT_FILE_PURPOSE: Start one complete production experiment in a detached process group and record its launch log.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ID="${1:-}"
case "$ID" in M0_D0|M0_D1|M0_D2|M1_D0|M1_D1|M1_D2|M2_D0|M2_D1|M2_D2) ;; *) exit 2;; esac
mkdir -p "$ROOT/outputs/logs"
STAMP="$(date -u +%Y%m%d_%H%M%S)"
LOG="$ROOT/outputs/logs/${ID}_launch_$STAMP.log"
nohup setsid "$ROOT/scripts/run_experiment.sh" "$ID" production \
  > "$LOG" 2>&1 < /dev/null &
PID=$!
printf '%s\n' "$PID" > "$LOG.pid"
echo "LAUNCHED experiment=$ID pid=$PID log=$LOG"
