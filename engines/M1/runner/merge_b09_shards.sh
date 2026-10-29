#!/usr/bin/env bash
# CTREND_REVISIT_FILE_PURPOSE: Run the M1 MATLAB merge under shell-level source, process, and inventory gates.
set -euo pipefail

RUNNER_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$RUNNER_DIR/.." && pwd)"
RUN_ROOT="${1:-$(<"$RUNNER_DIR/latest_run_path.txt")}" 
MATLAB_BIN="${MATLAB_BIN:-$(command -v matlab 2>/dev/null || true)}"
CANONICAL_CODE_DIR="${CANONICAL_CODE_DIR:-$PROJECT_DIR/base}"

[[ -d "$RUN_ROOT" ]] || { echo "missing run directory: $RUN_ROOT" >&2; exit 2; }
[[ -x "$MATLAB_BIN" ]] || { echo "MATLAB is not executable: $MATLAB_BIN" >&2; exit 2; }
[[ -f "$RUN_ROOT/run.env" ]] || { echo "missing run.env: $RUN_ROOT" >&2; exit 2; }
while IFS='=' read -r key value; do
  case "$key" in
    results_root|research_run_id|b09_job_storage_root|corrected_package|\
expected_package_sha256|expected_design_choices_sha256|num_shards)
      printf -v "$key" '%s' "$value"
      ;;
  esac
done < "$RUN_ROOT/run.env"
: "${results_root:?run.env lacks results_root}"
: "${research_run_id:?run.env lacks research_run_id}"
: "${corrected_package:?run.env lacks corrected_package}"
: "${expected_package_sha256:?run.env lacks expected_package_sha256}"
: "${expected_design_choices_sha256:?run.env lacks expected_design_choices_sha256}"
: "${num_shards:?run.env lacks num_shards}"
[[ "$(sha256sum "$corrected_package" | awk '{print $1}')" == \
   "$expected_package_sha256" ]] || {
  echo "runtime package changed before merge" >&2
  exit 2
}
[[ "$(sha256sum "$CANONICAL_CODE_DIR/DesignChoices.mat" |
      awk '{print $1}')" == "$expected_design_choices_sha256" ]] || {
  echo "DesignChoices.mat changed before merge" >&2
  exit 2
}

# shellcheck source=../base/run_safety.sh
source "$CANONICAL_CODE_DIR/run_safety.sh"

if [[ "${CTREND_PIPELINE_LOCK_HELD:-0}" != 1 ]]; then
  command -v flock >/dev/null 2>&1 || {
    echo "flock is required to serialize corrected-pipeline writers" >&2
    exit 2
  }
  mkdir -p "$CANONICAL_CODE_DIR/logs"
  exec 9>"$CANONICAL_CODE_DIR/logs/corrected_pipeline.lock"
  if ! flock -n 9; then
    echo "Another corrected-pipeline writer is still active" >&2
    exit 75
  fi
  export CTREND_PIPELINE_LOCK_HELD=1
fi

for shard in $(seq 1 "$num_shards"); do
  pid="$(<"$RUN_ROOT/shard$shard/supervisor.pid")"
  if kill -0 "$pid" 2>/dev/null; then
    echo "shard $shard is still running (pid $pid)" >&2
    exit 3
  fi
  completion_file="$RUN_ROOT/shard$shard/completion.env"
  [[ -f "$completion_file" &&
     "$(awk -F= '$1=="complete"{print $2;exit}' \
       "$completion_file")" == "1" &&
     "$(awk -F= '$1=="design_choices_sha256"{print $2;exit}' \
       "$completion_file")" == "$expected_design_choices_sha256" &&
     -f "$RUN_ROOT/shard$shard/runtime_matlab_sources_after.sha256" ]] || {
    echo "shard $shard did not finish successfully" >&2
    exit 3
  }
  cmp -s "$RUN_ROOT/shard$shard/package_matlab_sources.sha256" \
    "$RUN_ROOT/shard$shard/runtime_matlab_sources_after.sha256" || {
    echo "shard $shard executable source changed during execution" >&2
    exit 3
  }
done

export B09_CANONICAL_CODE_DIR="$CANONICAL_CODE_DIR"
export B09_SHARD_RESULTS_ROOT="$results_root"
export B09_RESEARCH_RUN_ID="$research_run_id"
export B09_RUNNER_DIR="$RUNNER_DIR"
export B09_NUM_SHARDS="$num_shards"
MERGE_TEMP_ROOT="${B09_MERGE_TEMP_ROOT:-${b09_job_storage_root:-/tmp/ctrend_b09_merge}/merge_$$}"
MERGE_TEMP_ALLOWED_ROOT="${B09_MERGE_TEMP_ALLOWED_ROOT:-$(dirname "$MERGE_TEMP_ROOT")}"
ctrend_prepare_temp_dir "$MERGE_TEMP_ROOT" "$MERGE_TEMP_ALLOWED_ROOT" \
  b09_merge
export MATLAB_PREFDIR="$MERGE_TEMP_ROOT/matlab_pref"

cleanup_merge_temp() {
  local rc=$?
  trap - EXIT INT TERM
  ctrend_safe_remove_temp_dir "$MERGE_TEMP_ROOT" \
    "$MERGE_TEMP_ALLOWED_ROOT" || rc=1
  exit "$rc"
}
trap cleanup_merge_temp EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
mkdir -p "$MATLAB_PREFDIR"

"$MATLAB_BIN" -licmode onlinelicensing -nodisplay -nosplash \
  -batch "addpath(getenv('B09_RUNNER_DIR')); merge_b09_shards" \
  > "$RUN_ROOT/merge.log" 2>&1

echo "merged_at=$(date -Is)" >> "$RUN_ROOT/run.env"
echo "merge_log=$RUN_ROOT/merge.log"
