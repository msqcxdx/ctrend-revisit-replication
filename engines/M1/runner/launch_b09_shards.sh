#!/usr/bin/env bash
# CTREND_REVISIT_FILE_PURPOSE: Launch all local b09 clients with disjoint ranges and isolated MATLAB job storage.
set -euo pipefail

RUNNER_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$RUNNER_DIR/.." && pwd)"
PACKAGE="${CORRECTED_PACKAGE:-$PROJECT_DIR/ctrend_m1_pipeline.tar.gz}"
CANONICAL_CODE_DIR="${CANONICAL_CODE_DIR:-$PROJECT_DIR/base}"
MATLAB_BIN="${MATLAB_BIN:-$(command -v matlab 2>/dev/null || true)}"
WORKERS_PER_SHARD="${WORKERS_PER_SHARD:-31}"
NUM_SHARDS="${NUM_SHARDS:-4}"
FIRST_COMBO="${FIRST_COMBO:-2}"
LAST_COMBO="${LAST_COMBO:-3072}"
POOL_START_STAGGER_SECONDS="${POOL_START_STAGGER_SECONDS:-30}"
POOL_START_TIMEOUT_SECONDS="${POOL_START_TIMEOUT_SECONDS:-2100}"
NO_PROGRESS_TIMEOUT_SECONDS="${NO_PROGRESS_TIMEOUT_SECONDS:-5400}"
HEARTBEAT_INTERVAL_SECONDS="${HEARTBEAT_INTERVAL_SECONDS:-60}"
RUN_STAMP="$(date -u +%Y%m%d_%H%M%S)"
RUN_ROOT="${RUN_ROOT:-$RUNNER_DIR/runs/b09_$RUN_STAMP}"
RESULTS_ROOT="${RESULTS_ROOT:-$RUNNER_DIR/runtime/results/$RUN_STAMP}"
B09_JOB_STORAGE_ROOT="${B09_JOB_STORAGE_ROOT:-$RUNNER_DIR/runtime/job_storage/$RUN_STAMP}"
EXPECTED_PACKAGE_SHA256="${EXPECTED_PACKAGE_SHA256:-}"
EXPECTED_DESIGN_CHOICES_SHA256="${EXPECTED_DESIGN_CHOICES_SHA256:-}"
B09_ORCHESTRATOR_PID="${B09_ORCHESTRATOR_PID:-}"
B09_ORCHESTRATOR_START_TICKS="${B09_ORCHESTRATOR_START_TICKS:-}"

# shellcheck source=b09_profile_lib.sh
source "$RUNNER_DIR/b09_profile_lib.sh"

ctrend_b09_validate_profile "$NUM_SHARDS" "$WORKERS_PER_SHARD" \
  "$FIRST_COMBO" "$LAST_COMBO"
[[ "$POOL_START_STAGGER_SECONDS" =~ ^[0-9]+$ ]] || {
  echo "invalid POOL_START_STAGGER_SECONDS" >&2
  exit 2
}
for timeout_name in POOL_START_TIMEOUT_SECONDS NO_PROGRESS_TIMEOUT_SECONDS \
    HEARTBEAT_INTERVAL_SECONDS; do
  timeout_value="${!timeout_name}"
  [[ "$timeout_value" =~ ^[1-9][0-9]*$ ]] || {
    echo "invalid $timeout_name: $timeout_value" >&2
    exit 2
  }
done
[[ "$FIRST_COMBO" =~ ^[1-9][0-9]*$ && "$LAST_COMBO" =~ ^[1-9][0-9]*$ ]] || { echo "invalid combo bounds" >&2; exit 2; }
(( FIRST_COMBO <= LAST_COMBO && LAST_COMBO <= 3072 )) || { echo "combo bounds out of range" >&2; exit 2; }
(( LAST_COMBO - FIRST_COMBO + 1 >= NUM_SHARDS )) || {
  echo "the persistent shard profile has too few combos" >&2
  exit 2
}
[[ -f "$PACKAGE" ]] || { echo "missing corrected package: $PACKAGE" >&2; exit 2; }
[[ "$EXPECTED_PACKAGE_SHA256" =~ ^[0-9a-f]{64}$ &&
   "$(sha256sum "$PACKAGE" | awk '{print $1}')" == \
     "$EXPECTED_PACKAGE_SHA256" ]] || {
  echo "corrected package does not match the frozen run hash" >&2
  exit 2
}
[[ -x "$MATLAB_BIN" ]] || { echo "MATLAB is not executable: $MATLAB_BIN" >&2; exit 2; }
[[ -d "$CANONICAL_CODE_DIR/DATA" ]] || { echo "missing canonical DATA directory" >&2; exit 2; }
[[ -f "$CANONICAL_CODE_DIR/DesignChoices.mat" ]] || {
  echo "missing canonical DesignChoices.mat" >&2
  exit 2
}
[[ "$EXPECTED_DESIGN_CHOICES_SHA256" =~ ^[0-9a-f]{64}$ &&
   "$(sha256sum "$CANONICAL_CODE_DIR/DesignChoices.mat" |
      awk '{print $1}')" == "$EXPECTED_DESIGN_CHOICES_SHA256" ]] || {
  echo "DesignChoices.mat does not match the post-b00 frozen hash" >&2
  exit 2
}
[[ "$B09_ORCHESTRATOR_PID" =~ ^[1-9][0-9]*$ &&
   "$B09_ORCHESTRATOR_START_TICKS" =~ ^[1-9][0-9]*$ &&
   -r "/proc/$B09_ORCHESTRATOR_PID/stat" &&
   "$(awk '{print $22}' "/proc/$B09_ORCHESTRATOR_PID/stat")" == \
     "$B09_ORCHESTRATOR_START_TICKS" ]] || {
  echo "b09 production launch requires a live orchestrator lease" >&2
  exit 2
}
[[ ! -e "$RUN_ROOT" ]] || { echo "run directory already exists: $RUN_ROOT" >&2; exit 2; }
[[ ! -e "$RESULTS_ROOT" ]] || { echo "result directory already exists: $RESULTS_ROOT" >&2; exit 2; }

if (( FIRST_COMBO > 1 )) && [[ -z "${RESEARCH_RUN_ID:-}" ]]; then
  echo "RESEARCH_RUN_ID is required when reusing earlier canonical combos" >&2
  exit 2
fi

declare -a launched_pids=()
launch_complete=0
cleanup_partial_launch() {
  local rc=$?
  local pid
  local deadline
  trap - EXIT INT TERM
  if (( launch_complete == 0 )); then
    for pid in "${launched_pids[@]}"; do
      [[ "$pid" =~ ^[1-9][0-9]*$ ]] || continue
      kill -TERM -- "-$pid" 2>/dev/null || kill -TERM "$pid" 2>/dev/null || true
    done
    deadline=$(( $(date +%s) + 120 ))
    for pid in "${launched_pids[@]}"; do
      [[ "$pid" =~ ^[1-9][0-9]*$ ]] || continue
      while kill -0 "$pid" 2>/dev/null && (( $(date +%s) < deadline )); do
        sleep 1
      done
      if kill -0 "$pid" 2>/dev/null; then
        kill -KILL -- "-$pid" 2>/dev/null || kill -KILL "$pid" 2>/dev/null || true
      fi
      wait "$pid" 2>/dev/null || true
    done
  fi
  exit "$rc"
}
trap cleanup_partial_launch EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

mkdir -p "$RUN_ROOT" "$RESULTS_ROOT"
RUN_ID="${RESEARCH_RUN_ID:-$(</proc/sys/kernel/random/uuid)}"
[[ "$RUN_ID" =~ ^[0-9a-fA-F-]{36}$ ]] || { echo "could not create research run ID: $RUN_ID" >&2; exit 2; }

write_runtime_source_inventory() {
  local source_dir="$1"
  (
    cd "$source_dir"
    {
      find . -maxdepth 1 -type f \
        \( -name '*.m' -o -name '*.sh' \) \
        ! -name 'tmp_*' -printf '%P\n'
      find Utils LatexTables tests -type f \
        \( -name '*.m' -o -name '*.sh' \) \
        ! -name 'tmp_*' -printf '%p\n'
    } | LC_ALL=C sort | while IFS= read -r relative; do
      digest="$(sha256sum "$relative")"
      printf '%s  %s\n' "${digest%% *}" "$relative"
    done
  )
}

write_runtime_source_inventory "$CANONICAL_CODE_DIR" \
  > "$RUN_ROOT/canonical_matlab_sources.sha256"

for shard in $(seq 1 "$NUM_SHARDS"); do
  shard_dir="$RUN_ROOT/shard$shard"
  mkdir -p "$shard_dir/extract" "$shard_dir/logs" "$RESULTS_ROOT/shard$shard/CTREND" \
    "$RESULTS_ROOT/shard$shard/Tables" "$RESULTS_ROOT/shard$shard/Figures"
  [[ "$(sha256sum "$PACKAGE" | awk '{print $1}')" == \
     "$EXPECTED_PACKAGE_SHA256" ]] || {
    echo "corrected package changed before shard $shard extraction" >&2
    exit 2
  }
  tar -xzf "$PACKAGE" -C "$shard_dir/extract"
  code_dir="$shard_dir/extract/ctrend_corrected_pipeline"
  [[ -d "$code_dir" ]] || { echo "package root missing in shard $shard" >&2; exit 2; }
  write_runtime_source_inventory "$code_dir" \
    > "$shard_dir/package_matlab_sources.sha256"
  if ! cmp -s "$RUN_ROOT/canonical_matlab_sources.sha256" \
      "$shard_dir/package_matlab_sources.sha256"; then
    diff -u "$RUN_ROOT/canonical_matlab_sources.sha256" \
      "$shard_dir/package_matlab_sources.sha256" >&2 || true
    echo "runtime package source differs from canonical corrected source" >&2
    exit 2
  fi
  design_temporary="$code_dir/DesignChoices.mat.runner_tmp.$$"
  cp -- "$CANONICAL_CODE_DIR/DesignChoices.mat" "$design_temporary"
  mv -f -- "$design_temporary" "$code_dir/DesignChoices.mat"
  [[ "$(sha256sum "$code_dir/DesignChoices.mat" | awk '{print $1}')" == \
     "$EXPECTED_DESIGN_CHOICES_SHA256" ]] || {
    echo "shard $shard DesignChoices copy failed hash verification" >&2
    exit 2
  }
  ln -s "$CANONICAL_CODE_DIR/DATA" "$code_dir/DATA"
  ln -s "$RESULTS_ROOT/shard$shard" "$code_dir/Results"
  : > "$shard_dir/ranges.txt"
done
[[ "$(sha256sum "$PACKAGE" | awk '{print $1}')" == \
   "$EXPECTED_PACKAGE_SHA256" ]] || {
  echo "corrected package changed during shard extraction" >&2
  exit 2
}

# Give each shard one nearly equal contiguous range.  run_b09_shard keeps one
# MATLAB client and one process pool alive for every range in its file; a
# single range here avoids all routine client/pool restarts.  Recovery plans
# may still contain several disjoint ranges and use the same persistent
# runner.
ctrend_b09_write_contiguous_ranges "$NUM_SHARDS" "$FIRST_COMBO" \
  "$LAST_COMBO" "$RUN_ROOT" || {
  echo "internal contiguous shard allocation error" >&2
  exit 2
}

{
  echo "run_root=$RUN_ROOT"
  echo "results_root=$RESULTS_ROOT"
  echo "research_run_id=$RUN_ID"
  echo "corrected_package=$PACKAGE"
  echo "package_sha256=$(sha256sum "$PACKAGE" | awk '{print $1}')"
  echo "expected_package_sha256=$EXPECTED_PACKAGE_SHA256"
  echo "canonical_code_dir=$CANONICAL_CODE_DIR"
  echo "canonical_code_dir_resolved=$(readlink -f "$CANONICAL_CODE_DIR")"
  echo "canonical_data_dir_resolved=$(readlink -f "$CANONICAL_CODE_DIR/DATA")"
  echo "design_choices_sha256=$(sha256sum "$CANONICAL_CODE_DIR/DesignChoices.mat" | awk '{print $1}')"
  echo "expected_design_choices_sha256=$EXPECTED_DESIGN_CHOICES_SHA256"
  echo "results_root_resolved=$(readlink -f "$RESULTS_ROOT")"
  echo "matlab_bin=$MATLAB_BIN"
  echo "host=$(hostname)"
  echo "kernel=$(uname -srvmo)"
  echo "launch_runner_sha256=$(sha256sum "$RUNNER_DIR/launch_b09_shards.sh" | awk '{print $1}')"
  echo "shard_runner_sha256=$(sha256sum "$RUNNER_DIR/run_b09_shard.sh" | awk '{print $1}')"
  echo "orchestrator_sha256=$(sha256sum "$RUNNER_DIR/run_production.sh" | awk '{print $1}')"
  echo "num_shards=$NUM_SHARDS"
  echo "workers_per_shard=$WORKERS_PER_SHARD"
  echo "total_workers=$((NUM_SHARDS * WORKERS_PER_SHARD))"
  echo "worker_processes_plus_clients=$((NUM_SHARDS * (WORKERS_PER_SHARD + 1)))"
  echo "allocation=contiguous_persistent"
  echo "b09_job_storage_root=$B09_JOB_STORAGE_ROOT"
  echo "pool_start_stagger_seconds=$POOL_START_STAGGER_SECONDS"
  echo "pool_start_timeout_seconds=$POOL_START_TIMEOUT_SECONDS"
  echo "no_progress_timeout_seconds=$NO_PROGRESS_TIMEOUT_SECONDS"
  echo "heartbeat_interval_seconds=$HEARTBEAT_INTERVAL_SECONDS"
  echo "orchestrator_pid=$B09_ORCHESTRATOR_PID"
  echo "orchestrator_start_ticks=$B09_ORCHESTRATOR_START_TICKS"
  echo "first_combo=$FIRST_COMBO"
  echo "last_combo=$LAST_COMBO"
  echo "launched_at=$(date -Is)"
} > "$RUN_ROOT/run.env"

export B09_JOB_STORAGE_ROOT
export POOL_START_TIMEOUT_SECONDS
export NO_PROGRESS_TIMEOUT_SECONDS
export HEARTBEAT_INTERVAL_SECONDS

for shard in $(seq 1 "$NUM_SHARDS"); do
  shard_dir="$RUN_ROOT/shard$shard"
  code_dir="$shard_dir/extract/ctrend_corrected_pipeline"
  nohup setsid env \
    B09_SHARD_ID="$shard" \
    B09_SHARD_STATE_FILE="$shard_dir/state.env" \
    B09_SHARD_HEARTBEAT_FILE="$shard_dir/heartbeat.env" \
    B09_SHARD_COMPLETION_FILE="$shard_dir/completion.env" \
    B09_ORCHESTRATOR_PID="$B09_ORCHESTRATOR_PID" \
    B09_ORCHESTRATOR_START_TICKS="$B09_ORCHESTRATOR_START_TICKS" \
    EXPECTED_DESIGN_CHOICES_SHA256="$EXPECTED_DESIGN_CHOICES_SHA256" \
    "$RUNNER_DIR/run_b09_shard.sh" \
    "$code_dir" "$shard_dir/ranges.txt" "$RUN_ID" \
    "$WORKERS_PER_SHARD" "$MATLAB_BIN" "$shard_dir/logs" \
    > "$shard_dir/supervisor.log" 2>&1 < /dev/null &
  pid=$!
  launched_pids[$shard]="$pid"
  printf '%s\n' "$pid" > "$shard_dir/supervisor.pid"
  printf '%s\n' "$(date +%s)" > "$shard_dir/supervisor.started_epoch"
  printf 'shard=%d pid=%d ranges=%s\n' "$shard" "$pid" \
    "$(tr '\n' ';' < "$shard_dir/ranges.txt")"
  if (( shard < NUM_SHARDS && POOL_START_STAGGER_SECONDS > 0 )); then
    sleep "$POOL_START_STAGGER_SECONDS"
  fi
done

printf '%s\n' "$RUN_ROOT" > "$RUNNER_DIR/latest_run_path.txt"
printf '%s\n' "$RUN_ID" > "$RUNNER_DIR/latest_research_run_id.txt"
echo "run_root=$RUN_ROOT"
echo "results_root=$RESULTS_ROOT"
echo "research_run_id=$RUN_ID"
echo "pool_workers=$((NUM_SHARDS * WORKERS_PER_SHARD))"
echo "worker_processes_plus_clients=$((NUM_SHARDS * (WORKERS_PER_SHARD + 1)))"
launch_complete=1
trap - EXIT INT TERM
