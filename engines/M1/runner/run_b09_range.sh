#!/usr/bin/env bash
# CTREND_REVISIT_FILE_PURPOSE: Dispatch one audited M1 b09 range with a declared worker profile and isolated storage.
set -euo pipefail

if [[ "$#" -lt 4 || "$#" -gt 5 ]]; then
  echo "usage: $0 RUN_ROOT SHARD START END [WORKERS]" >&2
  exit 2
fi

RUN_ROOT="$1"
SHARD="$2"
START="$3"
END="$4"
WORKERS="${5:-31}"
RUNNER_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

[[ -f "$RUN_ROOT/run.env" ]] || { echo "missing run.env: $RUN_ROOT" >&2; exit 2; }
[[ "$SHARD" =~ ^[1-4]$ ]] || { echo "SHARD must be 1-4" >&2; exit 2; }
[[ "$START" =~ ^[1-9][0-9]*$ && "$END" =~ ^[1-9][0-9]*$ ]] || { echo "invalid range" >&2; exit 2; }
(( START >= 2 && START <= END && END <= 3072 )) || { echo "range must be within 2:3072" >&2; exit 2; }
[[ "$WORKERS" =~ ^[1-9][0-9]*$ ]] || { echo "invalid worker count" >&2; exit 2; }
(( WORKERS <= 31 )) || { echo "manual shard workers must not exceed 31" >&2; exit 2; }

while IFS='=' read -r key value; do
  case "$key" in
    research_run_id|matlab_bin)
      printf -v "$key" '%s' "$value"
      ;;
  esac
done < "$RUN_ROOT/run.env"
: "${research_run_id:?run.env lacks research_run_id}"
: "${matlab_bin:?run.env lacks matlab_bin}"
shard_dir="$RUN_ROOT/shard$SHARD"
code_dir="$shard_dir/extract/ctrend_corrected_pipeline"
[[ -d "$code_dir" ]] || { echo "missing staged code: $code_dir" >&2; exit 2; }

if [[ -f "$shard_dir/supervisor.pid" ]]; then
  old_pid="$(<"$shard_dir/supervisor.pid")"
  if kill -0 "$old_pid" 2>/dev/null; then
    echo "shard $SHARD is already running (pid $old_pid)" >&2
    exit 3
  fi
fi

stamp="$(date -u +%Y%m%d_%H%M%S)"
range_file="$shard_dir/manual_range_${START}_${END}_$stamp.txt"
log_dir="$shard_dir/manual_logs_${START}_${END}_$stamp"
printf '%d %d\n' "$START" "$END" > "$range_file"
mkdir -p "$log_dir"

nohup setsid env \
  B09_SHARD_ID="manual${SHARD}" \
  B09_SHARD_STATE_FILE="$shard_dir/state.env" \
  B09_SHARD_HEARTBEAT_FILE="$shard_dir/heartbeat.env" \
  "$RUNNER_DIR/run_b09_shard.sh" \
  "$code_dir" "$range_file" "$research_run_id" "$WORKERS" \
  "$matlab_bin" "$log_dir" > "$log_dir/supervisor.log" 2>&1 < /dev/null &
pid=$!
printf '%s\n' "$pid" > "$shard_dir/supervisor.pid"
printf 'shard=%s range=%s:%s workers=%s pid=%s log_dir=%s\n' \
  "$SHARD" "$START" "$END" "$WORKERS" "$pid" "$log_dir"
