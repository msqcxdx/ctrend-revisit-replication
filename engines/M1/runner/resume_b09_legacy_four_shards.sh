#!/usr/bin/env bash
# CTREND_REVISIT_FILE_PURPOSE: Resume only a prevalidated missing M1 b09 range using four isolated local subshards.
set -euo pipefail

if [[ "$#" -ne 2 ]]; then
  echo "usage: $0 RUN_ROOT PLAN_DIR" >&2
  exit 2
fi

RUN_ROOT="$1"
PLAN_DIR="$2"
RUNNER_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
[[ -f "$RUN_ROOT/run.env" ]] || { echo "missing run.env: $RUN_ROOT" >&2; exit 2; }
[[ -d "$PLAN_DIR" ]] || { echo "missing plan directory: $PLAN_DIR" >&2; exit 2; }

while IFS='=' read -r key value; do
  case "$key" in
    results_root|research_run_id|canonical_code_dir|matlab_bin)
      printf -v "$key" '%s' "$value"
      ;;
  esac
done < "$RUN_ROOT/run.env"
: "${results_root:?run.env lacks results_root}"
: "${research_run_id:?run.env lacks research_run_id}"
: "${canonical_code_dir:?run.env lacks canonical_code_dir}"
: "${matlab_bin:?run.env lacks matlab_bin}"
JOB_STORAGE_ROOT="${JOB_STORAGE_ROOT:-$RUN_ROOT/recovery_job_storage/$research_run_id}"
JOB_STORAGE_ALLOWED_ROOT="${JOB_STORAGE_ALLOWED_ROOT:-$(dirname "$JOB_STORAGE_ROOT")}"
RECOVERY_WORKERS="${RECOVERY_WORKERS:-31}"

# shellcheck source=../corrected_code_v2/run_safety.sh
source "$canonical_code_dir/run_safety.sh"

[[ -x "$matlab_bin" ]] || { echo "MATLAB is not executable: $matlab_bin" >&2; exit 2; }
[[ -d "$canonical_code_dir/DATA" ]] || { echo "canonical DATA is missing" >&2; exit 2; }
[[ "$RECOVERY_WORKERS" =~ ^[1-9][0-9]*$ && "$RECOVERY_WORKERS" -le 31 ]] || {
  echo "RECOVERY_WORKERS must be within 1:31" >&2
  exit 2
}
for shard in 1 2 3 4; do
  [[ -f "$PLAN_DIR/shard${shard}_ranges.txt" ]] || {
    echo "missing shard plan: $PLAN_DIR/shard${shard}_ranges.txt" >&2
    exit 2
  }
done
command -v flock >/dev/null 2>&1 || {
  echo "flock is required to serialize corrected-pipeline writers" >&2
  exit 2
}
mkdir -p "$canonical_code_dir/logs"
exec 9>"$canonical_code_dir/logs/corrected_pipeline.lock"
if ! flock -n 9; then
  echo "Another corrected-pipeline writer is still active" >&2
  exit 75
fi
export CTREND_PIPELINE_LOCK_HELD=1

export MATLAB_BIN="$matlab_bin"
export OMP_NUM_THREADS=1
export MKL_NUM_THREADS=1
export OPENBLAS_NUM_THREADS=1
export NUMEXPR_NUM_THREADS=1
export POOL_START_RETRIES="${POOL_START_RETRIES:-3}"
export POOL_RETRY_DELAY_SECONDS="${POOL_RETRY_DELAY_SECONDS:-20}"
export B09_JOB_STORAGE_ROOT="$JOB_STORAGE_ROOT/shards"
cttrend_prepare_temp_dir "$JOB_STORAGE_ROOT" "$JOB_STORAGE_ALLOWED_ROOT" \
  "b09_recovery_$research_run_id"
declare -a pids=()

stop_resume_shards() {
  local pid
  local deadline
  for pid in "${pids[@]}"; do
    [[ "$pid" =~ ^[1-9][0-9]*$ ]] || continue
    kill -TERM "$pid" 2>/dev/null || true
  done
  deadline=$(( $(date +%s) + 180 ))
  for pid in "${pids[@]}"; do
    [[ "$pid" =~ ^[1-9][0-9]*$ ]] || continue
    while kill -0 "$pid" 2>/dev/null && (( $(date +%s) < deadline )); do
      sleep 1
    done
    if kill -0 "$pid" 2>/dev/null; then
      kill -KILL "$pid" 2>/dev/null || true
    fi
    wait "$pid" 2>/dev/null || true
  done
}

cleanup_resume() {
  local rc=$?
  trap - EXIT INT TERM
  stop_resume_shards
  cttrend_safe_remove_temp_dir "$JOB_STORAGE_ROOT" \
    "$JOB_STORAGE_ALLOWED_ROOT" || rc=1
  exit "$rc"
}
trap cleanup_resume EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

log_event() {
  printf '%s\t%s\n' "$(date -Is)" "$*" | tee -a "$PLAN_DIR/resume_events.tsv"
}

# The recovery plan must cover exactly the combinations that are not
# committed by a matching shard manifest and valid MAT, or by a valid
# canonical MAT left by an interrupted merge.
export B09_CANONICAL_CODE_DIR="$canonical_code_dir"
export B09_SHARD_RESULTS_ROOT="$results_root"
export B09_RESEARCH_RUN_ID="$research_run_id"
export B09_RESUME_PRESENT_FILE="$PLAN_DIR/present_before.txt"
export B09_RUNNER_DIR="$RUNNER_DIR"
export MATLAB_PREFDIR="$JOB_STORAGE_ROOT/resume_validation_matlab_pref"
mkdir -p "$MATLAB_PREFDIR"
"$matlab_bin" -licmode onlinelicensing -nodisplay -nosplash \
  -batch "addpath(getenv('B09_RUNNER_DIR')); validate_b09_resume_state" \
  > "$PLAN_DIR/resume_validation.log" 2>&1

seq 1 3072 | comm -23 - "$PLAN_DIR/present_before.txt" \
  > "$PLAN_DIR/missing_before.txt"

: > "$PLAN_DIR/planned_combos.txt"
for shard in 1 2 3 4; do
  while read -r first last; do
    [[ "$first" =~ ^[1-9][0-9]*$ && "$last" =~ ^[1-9][0-9]*$ ]] || {
      echo "invalid range in shard $shard plan" >&2
      exit 2
    }
    (( first >= 2 && first <= last && last <= 3072 )) || {
      echo "out-of-bounds range in shard $shard plan: $first $last" >&2
      exit 2
    }
    seq "$first" "$last" >> "$PLAN_DIR/planned_combos.txt"
  done < "$PLAN_DIR/shard${shard}_ranges.txt"
done
sort -n "$PLAN_DIR/planned_combos.txt" -o "$PLAN_DIR/planned_combos.txt"
if [[ -n "$(uniq -d "$PLAN_DIR/planned_combos.txt")" ]]; then
  echo "recovery plan contains duplicate combos" >&2
  exit 2
fi
cmp -s "$PLAN_DIR/missing_before.txt" "$PLAN_DIR/planned_combos.txt" || {
  echo "recovery plan does not exactly match the currently missing combos" >&2
  exit 2
}

log_event "START phase=b09_resume missing=$(wc -l < "$PLAN_DIR/missing_before.txt") workers=4x$RECOVERY_WORKERS persistent=1"
for shard in 1 2 3 4; do
  shard_dir="$RUN_ROOT/shard$shard"
  code_dir="$shard_dir/extract/cttrend_corrected_pipeline"
  log_dir="$PLAN_DIR/shard$shard"
  mkdir -p "$log_dir"
  B09_SHARD_ID="resume$shard" \
  B09_SHARD_STATE_FILE="$shard_dir/state.env" \
  B09_SHARD_HEARTBEAT_FILE="$shard_dir/heartbeat.env" \
  "$RUNNER_DIR/run_b09_shard.sh" \
    "$code_dir" "$PLAN_DIR/shard${shard}_ranges.txt" \
    "$research_run_id" "$RECOVERY_WORKERS" "$matlab_bin" "$log_dir" \
    > "$log_dir/supervisor.log" 2>&1 &
  pids[$shard]=$!
  printf '%s\n' "${pids[$shard]}" > "$shard_dir/supervisor.pid"
  log_event "LAUNCH phase=b09_resume shard=$shard pid=${pids[$shard]} ranges=$(tr '\n' ';' < "$PLAN_DIR/shard${shard}_ranges.txt")"
done

resume_rc=0
for shard in 1 2 3 4; do
  if wait "${pids[$shard]}"; then
    rc=0
  else
    rc=$?
    resume_rc=1
  fi
  pids[$shard]=""
  log_event "END phase=b09_resume shard=$shard rc=$rc"
done
(( resume_rc == 0 )) || {
  echo "At least one recovery shard failed; completed recovery outputs remain reusable" >&2
  exit 1
}

for shard in 1 2 3 4; do
  printf 'shard_complete=1 recovery_plan=%s at %s\n' \
    "$PLAN_DIR" "$(date -Is)" >> "$RUN_ROOT/shard$shard/supervisor.log"
done

log_event "START phase=b09_merge"
MATLAB_BIN="$matlab_bin" CANONICAL_CODE_DIR="$canonical_code_dir" \
  "$RUNNER_DIR/merge_b09_shards.sh" "$RUN_ROOT" \
  > "$PLAN_DIR/b09_merge_supervisor.log" 2>&1
log_event "END phase=b09_merge rc=0"

log_event "START phase=b10 workers=64"
b10_dir="$PLAN_DIR/b10"
mkdir -p "$b10_dir" "$JOB_STORAGE_ROOT/b10/matlab_pref" \
  "$JOB_STORAGE_ROOT/b10/parallel_job_storage"
(
  export PIPELINE_SCOPE=table6
  export PIPELINE_START_STEP=b10Table6_FactorPerformanceAcrossResearchDesignChoices
  export PIPELINE_END_STEP=b10Table6_FactorPerformanceAcrossResearchDesignChoices
  export PARALLEL_WORKERS=64
  export PIPELINE_LOG_DIR="$b10_dir"
  export PIPELINE_LOG_FILE="$b10_dir/pipeline.log"
  export PIPELINE_STATUS_FILE="$b10_dir/status.tsv"
    export PIPELINE_STDOUT_REDIRECTED=1
    export MATLAB_PREFDIR="$JOB_STORAGE_ROOT/b10/matlab_pref"
    export PIPELINE_JOB_STORAGE="$JOB_STORAGE_ROOT/b10/parallel_job_storage"
    export PIPELINE_CODE_DIR="$canonical_code_dir"
    "$matlab_bin" -licmode onlinelicensing -nodisplay -nosplash \
    -batch "cd(getenv('PIPELINE_CODE_DIR')); run_full_pipeline_corrected" \
    >> "$b10_dir/pipeline.log" 2>&1
)
log_event "END phase=b10 rc=0"

log_event "START phase=supplementary workers=64"
supp_dir="$PLAN_DIR/supplementary"
mkdir -p "$supp_dir"
(
  export PARALLEL_WORKERS=64
  export CTREND_SUPPLEMENTARY_TEMP_ROOT="$JOB_STORAGE_ROOT/supplementary"
  export MATLAB_PREFDIR="$JOB_STORAGE_ROOT/supplementary/matlab_pref"
  export PIPELINE_JOB_STORAGE="$JOB_STORAGE_ROOT/supplementary/parallel_job_storage"
  export MATLAB_BIN="$matlab_bin"
  export CODE_DIR="$canonical_code_dir"
  "$canonical_code_dir/run_supplementary_outputs.sh" \
    > "$supp_dir/pipeline.log" 2>&1
)
log_event "END phase=supplementary rc=0"

for output in \
  "$canonical_code_dir/Results/Tables/factor_performance_across_research_design_choices.tex" \
  "$canonical_code_dir/Results/Tables/median_method_specific_weekly_observation_counts_underlying_table_6.tex" \
  "$canonical_code_dir/Results/Tables/table6_method_specific_week_counts.csv" \
  "$canonical_code_dir/Results/Tables/table6_method_specific_week_counts.mat" \
  "$canonical_code_dir/Results/Tables/factor_performance_across_research_design_choices_value_weighted_only.tex" \
  "$canonical_code_dir/Results/Tables/median_method_specific_weekly_observation_counts_underlying_table_b_6.tex"; do
  [[ -s "$output" ]] || { echo "required final output is missing: $output" >&2; exit 1; }
done

touch "$RUN_ROOT/../RECOMPUTE_COMPLETE" "$PLAN_DIR/RECOVERY_COMPLETE"
log_event "COMPLETE run_id=$research_run_id"
