#!/usr/bin/env bash
# CTREND_REVISIT_FILE_PURPOSE: Launch all local b09 clients with disjoint ranges and isolated MATLAB job storage.
set -euo pipefail

RUNNER_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$RUNNER_DIR/.." && pwd)"
PACKAGE="${OLD_V2_PACKAGE:-$PROJECT_DIR/ctrend_old_pipeline.tar.gz}"
CANONICAL_CODE_DIR="${CANONICAL_CODE_DIR:-$PROJECT_DIR/base}"
OLD_RUNTIME_ROOT_NAME="${OLD_RUNTIME_ROOT_NAME:-ctrend_old_pipeline}"
MATLAB_BIN="${MATLAB_BIN:-$(command -v matlab 2>/dev/null || true)}"
WORKERS_PER_SHARD="${WORKERS_PER_SHARD:-31}"
LOGICAL_SHARD_ID="${LOGICAL_SHARD_ID:-1}"
NUM_SUBSHARDS="${NUM_SUBSHARDS:-4}"
FIRST_COMBO="${FIRST_COMBO:-1}"
LAST_COMBO="${LAST_COMBO:-1536}"
B09_TOPOLOGY_MODE="${B09_TOPOLOGY_MODE:-two_host}"
POOL_START_STAGGER_SECONDS="${POOL_START_STAGGER_SECONDS:-30}"
POOL_START_RETRIES="${POOL_START_RETRIES:-10}"
POOL_RETRY_DELAY_SECONDS="${POOL_RETRY_DELAY_SECONDS:-60}"
POOL_START_TIMEOUT_SECONDS="${POOL_START_TIMEOUT_SECONDS:-2100}"
NO_PROGRESS_TIMEOUT_SECONDS="${NO_PROGRESS_TIMEOUT_SECONDS:-5400}"
HEARTBEAT_INTERVAL_SECONDS="${HEARTBEAT_INTERVAL_SECONDS:-60}"
RUN_STAMP="$(date -u +%Y%m%d_%H%M%S)"
RUN_ROOT="${RUN_ROOT:-$RUNNER_DIR/runs/b09_$RUN_STAMP}"
RESULTS_ROOT="${RESULTS_ROOT:-$RUNNER_DIR/runtime/results/$RUN_STAMP}"
B09_JOB_STORAGE_ROOT="${B09_JOB_STORAGE_ROOT:-$RUNNER_DIR/runtime/job_storage/$RUN_STAMP}"
B09_LATEST_POINTER_DIR="${B09_LATEST_POINTER_DIR:-$RUNNER_DIR}"
EXPECTED_PACKAGE_SHA256="${EXPECTED_PACKAGE_SHA256:-}"
EXPECTED_DESIGN_CHOICES_SHA256="${EXPECTED_DESIGN_CHOICES_SHA256:-}"
EXPECTED_DATA_INPUTS_SHA256="${EXPECTED_DATA_INPUTS_SHA256:-}"
# shellcheck source=b09_topology_lib.sh
source "$RUNNER_DIR/b09_topology_lib.sh"
TOPOLOGY_TEMPLATE="$(ctrend_b09_topology_template \
  "$B09_TOPOLOGY_MODE" "$RUNNER_DIR")"
TOPOLOGY_FILE="$RUN_ROOT/$(basename "$TOPOLOGY_TEMPLATE")"

[[ "$LOGICAL_SHARD_ID" -eq 1 ]] || {
  echo "this launcher is restricted to local logical shard 1" >&2
  exit 2
}
case "$B09_TOPOLOGY_MODE:$NUM_SUBSHARDS:$WORKERS_PER_SHARD:$FIRST_COMBO:$LAST_COMBO" in
  two_host:4:31:1:1536|local_full_8x15:8:15:1:3072) ;;
  *) echo "unsupported audited old-v2 b09 launch profile" >&2; exit 2 ;;
esac
[[ "$POOL_START_STAGGER_SECONDS" =~ ^[0-9]+$ ]] || {
  echo "invalid POOL_START_STAGGER_SECONDS" >&2
  exit 2
}
[[ "$POOL_START_RETRIES" =~ ^[1-9][0-9]*$ &&
   "$POOL_RETRY_DELAY_SECONDS" =~ ^[0-9]+$ ]] || {
  echo "invalid pool retry contract" >&2
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
[[ -f "$TOPOLOGY_TEMPLATE" ]] || {
  echo "missing frozen b09 topology template" >&2
  exit 2
}
[[ -f "$PACKAGE" ]] || { echo "missing old v2 package: $PACKAGE" >&2; exit 2; }
[[ "$EXPECTED_PACKAGE_SHA256" =~ ^[0-9a-f]{64}$ &&
   "$(sha256sum "$PACKAGE" | awk '{print $1}')" == \
     "$EXPECTED_PACKAGE_SHA256" ]] || {
  echo "old v2 package does not match the frozen run hash" >&2
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
data_inventory_temporary="$(mktemp /tmp/ctrend_old_v2_local_data.XXXXXX)"
trap 'rm -f -- "$data_inventory_temporary"' RETURN
(
  cd "$CANONICAL_CODE_DIR/DATA"
  find -L . -maxdepth 1 -type f -printf '%P\0' |
    LC_ALL=C sort -z | xargs -0 -r sha256sum
) > "$data_inventory_temporary"
[[ "$EXPECTED_DATA_INPUTS_SHA256" =~ ^[0-9a-f]{64}$ &&
   "$(sha256sum "$data_inventory_temporary" | awk '{print $1}')" == \
     "$EXPECTED_DATA_INPUTS_SHA256" ]] || {
  echo "old v2 DATA inventory differs from the frozen post-b02 hash" >&2
  exit 2
}
[[ "$OLD_RUNTIME_ROOT_NAME" =~ ^[A-Za-z0-9_.-]+$ ]] || {
  echo "invalid old runtime root name: $OLD_RUNTIME_ROOT_NAME" >&2
  exit 2
}
rm -f -- "$data_inventory_temporary"
trap - RETURN
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
cp -- "$TOPOLOGY_TEMPLATE" "$TOPOLOGY_FILE"
ctrend_b09_validate_topology "$TOPOLOGY_FILE" "$TOPOLOGY_TEMPLATE"
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
      for source_subdir in Utils LatexTables tests; do
        if [[ -d "$source_subdir" ]]; then
          find "$source_subdir" -type f \
            -name '*.m' ! -name 'tmp_*' -printf '%p\n'
        fi
      done
    } | LC_ALL=C sort | while IFS= read -r relative; do
      digest="$(sha256sum "$relative")"
      printf '%s  %s\n' "${digest%% *}" "$relative"
    done
  )
}

write_runtime_source_inventory "$CANONICAL_CODE_DIR" \
  > "$RUN_ROOT/canonical_matlab_sources.sha256"

for subshard in $(seq 1 "$NUM_SUBSHARDS"); do
  source_label="shard1/subshard$subshard"
  shard_dir="$RUN_ROOT/$source_label"
  result_dir="$RESULTS_ROOT/$source_label"
  mkdir -p "$shard_dir/extract" "$shard_dir/logs" "$result_dir/CTREND" \
    "$result_dir/Tables" "$result_dir/Figures"
  [[ "$(sha256sum "$PACKAGE" | awk '{print $1}')" == \
     "$EXPECTED_PACKAGE_SHA256" ]] || {
    echo "old v2 package changed before $source_label extraction" >&2
    exit 2
  }
  tar -xzf "$PACKAGE" -C "$shard_dir/extract"
  code_dir="$shard_dir/extract/$OLD_RUNTIME_ROOT_NAME"
  [[ -d "$code_dir" ]] || {
    echo "package root missing in $source_label" >&2
    exit 2
  }
  write_runtime_source_inventory "$code_dir" \
    > "$shard_dir/package_matlab_sources.sha256"
  if ! cmp -s "$RUN_ROOT/canonical_matlab_sources.sha256" \
      "$shard_dir/package_matlab_sources.sha256"; then
    diff -u "$RUN_ROOT/canonical_matlab_sources.sha256" \
      "$shard_dir/package_matlab_sources.sha256" >&2 || true
    echo "runtime package source differs from canonical old v2 source" >&2
    exit 2
  fi
  design_temporary="$code_dir/DesignChoices.mat.runner_tmp.$$"
  cp -- "$CANONICAL_CODE_DIR/DesignChoices.mat" "$design_temporary"
  mv -f -- "$design_temporary" "$code_dir/DesignChoices.mat"
  [[ "$(sha256sum "$code_dir/DesignChoices.mat" | awk '{print $1}')" == \
     "$EXPECTED_DESIGN_CHOICES_SHA256" ]] || {
    echo "$source_label DesignChoices copy failed hash verification" >&2
    exit 2
  }
  ln -s "$CANONICAL_CODE_DIR/DATA" "$code_dir/DATA"
  ln -s "$result_dir" "$code_dir/Results"
  : > "$shard_dir/ranges.txt"
done
[[ "$(sha256sum "$PACKAGE" | awk '{print $1}')" == \
   "$EXPECTED_PACKAGE_SHA256" ]] || {
  echo "old v2 package changed during shard extraction" >&2
  exit 2
}

# Give each local subshard one equal contiguous range. run_b09_shard keeps
# one MATLAB client and one process pool alive for its complete range.
iNumCombos=$((LAST_COMBO - FIRST_COMBO + 1))
iBasePerShard=$((iNumCombos / NUM_SUBSHARDS))
iRemainder=$((iNumCombos % NUM_SUBSHARDS))
combo_start="$FIRST_COMBO"
for subshard in $(seq 1 "$NUM_SUBSHARDS"); do
  iShardCombos="$iBasePerShard"
  if (( subshard <= iRemainder )); then
    iShardCombos=$((iShardCombos + 1))
  fi
  combo_end=$((combo_start + iShardCombos - 1))
  printf '%d %d\n' "$combo_start" "$combo_end" \
    > "$RUN_ROOT/shard1/subshard$subshard/ranges.txt"
  combo_start=$((combo_end + 1))
done
(( combo_start == LAST_COMBO + 1 )) || {
  echo "internal contiguous shard allocation error" >&2
  exit 2
}

{
  echo "run_root=$RUN_ROOT"
  echo "results_root=$RESULTS_ROOT"
  echo "topology_file=$TOPOLOGY_FILE"
  echo "topology_template_name=$(basename "$TOPOLOGY_TEMPLATE")"
  echo "topology_mode=$B09_TOPOLOGY_MODE"
  echo "topology_sha256=$(sha256sum "$TOPOLOGY_FILE" | awk '{print $1}')"
  echo "research_run_id=$RUN_ID"
  echo "old_v2_package=$PACKAGE"
  echo "package_sha256=$(sha256sum "$PACKAGE" | awk '{print $1}')"
  echo "expected_package_sha256=$EXPECTED_PACKAGE_SHA256"
  echo "canonical_code_dir=$CANONICAL_CODE_DIR"
  echo "old_runtime_root_name=$OLD_RUNTIME_ROOT_NAME"
  echo "canonical_code_dir_resolved=$(readlink -f "$CANONICAL_CODE_DIR")"
  echo "canonical_data_dir_resolved=$(readlink -f "$CANONICAL_CODE_DIR/DATA")"
  echo "design_choices_sha256=$(sha256sum "$CANONICAL_CODE_DIR/DesignChoices.mat" | awk '{print $1}')"
  echo "expected_design_choices_sha256=$EXPECTED_DESIGN_CHOICES_SHA256"
  echo "expected_data_inputs_sha256=$EXPECTED_DATA_INPUTS_SHA256"
  echo "results_root_resolved=$(readlink -f "$RESULTS_ROOT")"
  echo "matlab_bin=$MATLAB_BIN"
  echo "host=$(hostname)"
  echo "kernel=$(uname -srvmo)"
  echo "launch_runner_sha256=$(sha256sum "$RUNNER_DIR/launch_b09_shards.sh" | awk '{print $1}')"
  echo "shard_runner_sha256=$(sha256sum "$RUNNER_DIR/run_b09_shard.sh" | awk '{print $1}')"
  echo "orchestrator_sha256=$(sha256sum "$RUNNER_DIR/run_production.sh" | awk '{print $1}')"
  if [[ "$B09_TOPOLOGY_MODE" == "two_host" ]]; then
    echo "logical_shards=2"
    echo "allocation=two_logical_shards_local_four_subshards"
  else
    echo "logical_shards=1"
    echo "allocation=single_host_full_eight_subshards"
  fi
  echo "launched_logical_shard=$LOGICAL_SHARD_ID"
  echo "num_local_subshards=$NUM_SUBSHARDS"
  echo "workers_per_shard=$WORKERS_PER_SHARD"
  echo "total_local_workers=$((NUM_SUBSHARDS * WORKERS_PER_SHARD))"
  echo "local_worker_processes_plus_clients=$((NUM_SUBSHARDS * (WORKERS_PER_SHARD + 1)))"
  echo "b09_job_storage_root=$B09_JOB_STORAGE_ROOT"
  echo "pool_start_stagger_seconds=$POOL_START_STAGGER_SECONDS"
  echo "pool_start_retries=$POOL_START_RETRIES"
  echo "pool_retry_delay_seconds=$POOL_RETRY_DELAY_SECONDS"
  echo "pool_start_timeout_seconds=$POOL_START_TIMEOUT_SECONDS"
  echo "no_progress_timeout_seconds=$NO_PROGRESS_TIMEOUT_SECONDS"
  echo "heartbeat_interval_seconds=$HEARTBEAT_INTERVAL_SECONDS"
  echo "first_combo=$FIRST_COMBO"
  echo "last_combo=$LAST_COMBO"
  echo "launched_at=$(date -Is)"
} > "$RUN_ROOT/run.env"

export B09_JOB_STORAGE_ROOT
export POOL_START_RETRIES
export POOL_RETRY_DELAY_SECONDS
export POOL_START_TIMEOUT_SECONDS
export NO_PROGRESS_TIMEOUT_SECONDS
export HEARTBEAT_INTERVAL_SECONDS

for subshard in $(seq 1 "$NUM_SUBSHARDS"); do
  source_label="shard1/subshard$subshard"
  shard_dir="$RUN_ROOT/$source_label"
  code_dir="$shard_dir/extract/$OLD_RUNTIME_ROOT_NAME"
  nohup setsid env \
    B09_SHARD_ID="1.$subshard" \
    B09_SHARD_STATE_FILE="$shard_dir/state.env" \
    B09_SHARD_HEARTBEAT_FILE="$shard_dir/heartbeat.env" \
    B09_SHARD_COMPLETION_FILE="$shard_dir/completion.env" \
    EXPECTED_DESIGN_CHOICES_SHA256="$EXPECTED_DESIGN_CHOICES_SHA256" \
    EXPECTED_PACKAGE_SHA256="$EXPECTED_PACKAGE_SHA256" \
    EXPECTED_DATA_INPUTS_SHA256="$EXPECTED_DATA_INPUTS_SHA256" \
    "$RUNNER_DIR/run_b09_shard.sh" \
    "$code_dir" "$shard_dir/ranges.txt" "$RUN_ID" \
    "$WORKERS_PER_SHARD" "$MATLAB_BIN" "$shard_dir/logs" \
    > "$shard_dir/supervisor.log" 2>&1 < /dev/null &
  pid=$!
  launched_pids+=("$pid")
  printf '%s\n' "$pid" > "$shard_dir/supervisor.pid"
  printf '%s\n' "$(date +%s)" > "$shard_dir/supervisor.started_epoch"
  printf 'logical_shard=1 subshard=%d pid=%d ranges=%s\n' "$subshard" "$pid" \
    "$(tr '\n' ';' < "$shard_dir/ranges.txt")"
  if (( subshard < NUM_SUBSHARDS && POOL_START_STAGGER_SECONDS > 0 )); then
    sleep "$POOL_START_STAGGER_SECONDS"
  fi
done

mkdir -p "$B09_LATEST_POINTER_DIR"
printf '%s\n' "$RUN_ROOT" > "$B09_LATEST_POINTER_DIR/latest_run_path.txt"
printf '%s\n' "$RUN_ID" > "$B09_LATEST_POINTER_DIR/latest_research_run_id.txt"
echo "run_root=$RUN_ROOT"
echo "results_root=$RESULTS_ROOT"
echo "research_run_id=$RUN_ID"
echo "logical_shard=1"
echo "local_subshards=$NUM_SUBSHARDS"
echo "pool_workers=$((NUM_SUBSHARDS * WORKERS_PER_SHARD))"
echo "worker_processes_plus_clients=$((NUM_SUBSHARDS * (WORKERS_PER_SHARD + 1)))"
launch_complete=1
trap - EXIT INT TERM
