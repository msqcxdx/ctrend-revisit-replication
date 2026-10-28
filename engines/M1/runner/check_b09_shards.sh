#!/usr/bin/env bash
# CTREND_REVISIT_FILE_PURPOSE: Audit every M1 b09 shard state, range, result count, and sidecar before merge.
set -euo pipefail

RUNNER_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RUN_ROOT="${1:-$(<"$RUNNER_DIR/latest_run_path.txt")}" 
[[ -d "$RUN_ROOT" ]] || { echo "missing run directory: $RUN_ROOT" >&2; exit 2; }

search_progress() {
  local pattern="$1"
  shift
  if command -v rg >/dev/null 2>&1; then
    rg "$pattern" "$@"
  else
    grep -ERH "$pattern" "$@"
  fi
}

total_shard_files=0
NUM_SHARDS="$(awk -F= '$1=="num_shards" {print $2;exit}' \
  "$RUN_ROOT/run.env")"
[[ "$NUM_SHARDS" =~ ^[1-9][0-9]*$ ]] || {
  echo "run.env has invalid num_shards" >&2
  exit 2
}
for shard in $(seq 1 "$NUM_SHARDS"); do
  shard_dir="$RUN_ROOT/shard$shard"
  pid="$(<"$shard_dir/supervisor.pid")"
  recorded_state="$(awk -F= '$1 == "state" { print $2; exit }' \
    "$shard_dir/state.env" 2>/dev/null || true)"
  heartbeat_epoch="$(awk -F= '$1 == "updated_epoch" { print $2; exit }' \
    "$shard_dir/heartbeat.env" 2>/dev/null || true)"
  heartbeat_age="unknown"
  if [[ "$heartbeat_epoch" =~ ^[0-9]+$ ]]; then
    heartbeat_age="$(( $(date +%s) - heartbeat_epoch ))"
  fi
  if kill -0 "$pid" 2>/dev/null; then
    state="${recorded_state:-running}"
  elif [[ "$recorded_state" == "COMPLETE" ]]; then
    state=complete
  else
    state="${recorded_state:-stopped_or_failed}"
  fi
  combo_files="$(find -L "$shard_dir/extract/cttrend_corrected_pipeline/Results/CTREND" \
    -maxdepth 1 -type f -name 'CTREND_Combo*.mat' | wc -l)"
  total_shard_files="$((total_shard_files + combo_files))"
  last_progress="$(search_progress 'Estimate combo|persistent_range_|research_design_run_complete|shard_complete|Error using|error:' \
    "$shard_dir"/logs/matlab_attempt_*.log \
    "$shard_dir/supervisor.log" 2>/dev/null | tail -1 || true)"
  printf 'shard=%d pid=%s state=%s heartbeat_age_seconds=%s combo_files=%s\n' \
    "$shard" "$pid" "$state" "$heartbeat_age" "$combo_files"
  [[ -z "$last_progress" ]] || printf '  %s\n' "$last_progress"
done

# The orchestrator computes canonical combo 1 before launching these
# disjoint shard ranges (2:3072).
total_with_canonical="$((total_shard_files + 1))"
percent="$(awk -v done="$total_with_canonical" \
  'BEGIN { printf "%.2f", 100 * done / 3072 }')"
printf 'total_completed=%d/3072 percent=%s%% shard_files=%d canonical_files=1\n' \
  "$total_with_canonical" "$percent" "$total_shard_files"
