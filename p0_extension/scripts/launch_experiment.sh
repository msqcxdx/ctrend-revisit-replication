#!/usr/bin/env bash
# CTREND_REVISIT_FILE_PURPOSE: Launch exactly one complete P0 experiment in a detached process group and record its log and PID.
set -euo pipefail

EXT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ROOT="$(cd "$EXT_ROOT/.." && pwd)"
ID="${1:-}"
case "$ID" in
  P0_M0_D0|P0_M0_D1|P0_M0_D2|P0_M1_D0|P0_M1_D1|P0_M1_D2|P0_M2_D0|P0_M2_D1|P0_M2_D2) ;;
  *) echo "invalid P0 experiment ID: $ID" >&2; exit 2 ;;
esac
mkdir -p "$ROOT/outputs/logs"
STAMP="$(date -u +%Y%m%d_%H%M%S)"
LOG="$ROOT/outputs/logs/${ID}_launch_$STAMP.log"
nohup setsid "$EXT_ROOT/scripts/run_experiment.sh" "$ID" production \
  > "$LOG" 2>&1 < /dev/null &
PID=$!
printf '%s\n' "$PID" > "$LOG.pid"
echo "LAUNCHED experiment=$ID pid=$PID log=$LOG"
