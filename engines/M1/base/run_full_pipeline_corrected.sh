#!/usr/bin/env bash
set -euo pipefail

CODE_DIR="${CODE_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)}"
if [[ -z "${MATLAB_BIN:-}" ]]; then
  if command -v matlab >/dev/null 2>&1; then
    MATLAB_BIN="$(command -v matlab)"
  else
    echo "MATLAB is not on PATH; set MATLAB_BIN explicitly" >&2
    exit 2
  fi
fi
if [[ "$MATLAB_BIN" == */* ]]; then
  [[ -x "$MATLAB_BIN" ]] || { echo "MATLAB_BIN is not executable: $MATLAB_BIN" >&2; exit 2; }
else
  command -v "$MATLAB_BIN" >/dev/null 2>&1 || { echo "MATLAB_BIN is not on PATH: $MATLAB_BIN" >&2; exit 2; }
  MATLAB_BIN="$(command -v "$MATLAB_BIN")"
fi
export MATLAB_BIN
PARALLEL_WORKERS="${PARALLEL_WORKERS:-$(env -u OMP_NUM_THREADS -u OMP_THREAD_LIMIT nproc)}"
[[ "$PARALLEL_WORKERS" =~ ^[1-9][0-9]*$ ]] || {
  echo "PARALLEL_WORKERS must be a positive integer" >&2
  exit 2
}
PIPELINE_SCOPE="${PIPELINE_SCOPE:-full}"
case "${PIPELINE_SCOPE,,}" in
  full|baseline|table6) ;;
  *) echo "PIPELINE_SCOPE must be full, baseline, or table6" >&2; exit 2 ;;
esac
command -v flock >/dev/null 2>&1 || {
  echo "flock is required to serialize corrected-pipeline writers" >&2
  exit 2
}
mkdir -p "$CODE_DIR/logs"
PIPELINE_LOCK_FILE="$CODE_DIR/logs/corrected_pipeline.lock"
exec 9>"$PIPELINE_LOCK_FILE"
if ! flock -n 9; then
  echo "Another corrected-pipeline writer holds $PIPELINE_LOCK_FILE" >&2
  exit 75
fi
export CTREND_PIPELINE_LOCK_HELD=1

RUN_ID="$(date -u +%Y%m%d_%H%M%S_%N)_$$"
LOG_DIR="$CODE_DIR/logs/corrected_pipeline_$RUN_ID"
LOG_FILE="$LOG_DIR/pipeline.log"
STATUS_FILE="$LOG_DIR/status.tsv"
PID_FILE="$CODE_DIR/logs/corrected_pipeline_latest.pid"
RUNTIME_TEMP_ROOT="${PIPELINE_RUNTIME_TEMP_ROOT:-${TMPDIR:-/tmp}/ctrend_pipeline_runtime_$RUN_ID}"
RUNTIME_TEMP_ALLOWED_ROOT="${PIPELINE_RUNTIME_TEMP_ALLOWED_ROOT:-$(dirname "$RUNTIME_TEMP_ROOT")}"
PIPELINE_JOB_STORAGE="$RUNTIME_TEMP_ROOT/parallel_job_storage"
export PIPELINE_JOB_STORAGE

# shellcheck source=run_safety.sh
source "$CODE_DIR/run_safety.sh"

mkdir -p "$LOG_DIR" "$CODE_DIR/Results/CTREND" \
  "$CODE_DIR/Results/Figures" "$CODE_DIR/Results/Tables"
cd "$CODE_DIR"
echo "$$" > "$PID_FILE"
cleanup_pid() {
  local rc=$?
  if [[ -f "$PID_FILE" ]] && [[ "$(<"$PID_FILE")" == "$$" ]]; then
    rm -f "$PID_FILE"
  fi
  ctrend_safe_remove_temp_dir "$RUNTIME_TEMP_ROOT" \
    "$RUNTIME_TEMP_ALLOWED_ROOT" || rc=1
  exit "$rc"
}
trap cleanup_pid EXIT

export PIPELINE_LOG_DIR="$LOG_DIR"
export PIPELINE_LOG_FILE="$LOG_FILE"
export PIPELINE_STATUS_FILE="$STATUS_FILE"
export PIPELINE_STDOUT_REDIRECTED=1
export PIPELINE_SCOPE
export PARALLEL_WORKERS
export MATLAB_PREFDIR="$RUNTIME_TEMP_ROOT/matlab_pref"
export OMP_NUM_THREADS=1
export MKL_NUM_THREADS=1
export OPENBLAS_NUM_THREADS=1
export NUMEXPR_NUM_THREADS=1

ctrend_prepare_temp_dir "$RUNTIME_TEMP_ROOT" \
  "$RUNTIME_TEMP_ALLOWED_ROOT" "corrected_pipeline_$RUN_ID"
ctrend_prepare_temp_dir "$MATLAB_PREFDIR" \
  "$RUNTIME_TEMP_ROOT" matlab_preferences
ctrend_prepare_temp_dir "$PIPELINE_JOB_STORAGE" \
  "$RUNTIME_TEMP_ROOT" parallel_job_storage

{
  echo "run_id=$RUN_ID"
  echo "code_dir=$CODE_DIR"
  echo "matlab=$MATLAB_BIN"
  echo "parallel_workers=$PARALLEL_WORKERS"
  echo "pipeline_scope=${PIPELINE_SCOPE,,}"
  echo "matlab_prefdir=$MATLAB_PREFDIR"
  echo "parallel_job_storage=$PIPELINE_JOB_STORAGE"
  echo "pipeline_start_step=${PIPELINE_START_STEP:-}"
  echo "pipeline_end_step=${PIPELINE_END_STEP:-}"
  echo "pipeline_combo_start=${PIPELINE_COMBO_START:-}"
  echo "pipeline_combo_end=${PIPELINE_COMBO_END:-}"
  echo "pipeline_research_run_id=${PIPELINE_RESEARCH_RUN_ID:-}"
  echo "pipeline_run_id=$RUN_ID"
  echo "results_dir=$(readlink -f "$CODE_DIR/Results")"
  echo "started_at=$(date -Is)"
} >> "$LOG_FILE"

export PIPELINE_RUN_ID="$RUN_ID"
export CTREND_OUTPUT_VARIANT=main
"$MATLAB_BIN" -licmode onlinelicensing -nodisplay -nosplash \
  -batch "run_full_pipeline_corrected" >> "$LOG_FILE" 2>&1

# Supplementary B1/B6/B7 consume the completed Table 6 outputs.  A partial
# full-scope run ending before b10 must not read stale results left by an
# earlier run.  The status row is the authoritative record that this exact
# MATLAB invocation completed b10 successfully.
ran_b10=0
supplementary_completed=0
if [[ -f "$STATUS_FILE" ]] && awk -F '\t' \
    '$1 == "b10Table6_FactorPerformanceAcrossResearchDesignChoices" &&
     $2 == "END" && $5 == "0" { found = 1 }
     END { exit(found ? 0 : 1) }' "$STATUS_FILE"; then
  ran_b10=1
fi

if [[ "${PIPELINE_SCOPE,,}" == "full" && "$ran_b10" -eq 1 ]]; then
  started="$(date -Is)"
  printf "supplementary_B1_B6_B7\tSTART\t%s\t\t\n" "$started" >> "$STATUS_FILE"
  echo "===== START supplementary_B1_B6_B7 $started =====" >> "$LOG_FILE"
  if CTREND_SUPPLEMENTARY_TEMP_ROOT="$RUNTIME_TEMP_ROOT" \
      "$CODE_DIR/run_supplementary_outputs.sh" >> "$LOG_FILE" 2>&1; then
    rc=0
  else
    rc=$?
  fi
  ended="$(date -Is)"
  printf "supplementary_B1_B6_B7\tEND\t%s\t%s\t%s\n" "$started" "$ended" "$rc" >> "$STATUS_FILE"
  echo "===== END supplementary_B1_B6_B7 rc=$rc $ended =====" >> "$LOG_FILE"
  [[ "$rc" -eq 0 ]]
  supplementary_completed=1
fi

completion_name=RUN_INVOCATION_COMPLETE
if [[ "${PIPELINE_SCOPE,,}" == "full" &&
      -z "${PIPELINE_START_STEP:-}" &&
      -z "${PIPELINE_END_STEP:-}" &&
      "$supplementary_completed" -eq 1 ]] &&
    awk -F '\t' \
      '$1 == "b18FigureC3_C4_AverageVariableImportance" &&
       $2 == "END" && $5 == "0" { found = 1 }
       END { exit(found ? 0 : 1) }' "$STATUS_FILE"; then
  completion_name=RUN_COMPLETE
fi
{
  echo "format=ctrend-direct-invocation-complete-v1"
  echo "run_id=$RUN_ID"
  echo "pipeline_scope=${PIPELINE_SCOPE,,}"
  echo "parallel_workers=$PARALLEL_WORKERS"
  echo "results_dir=$(readlink -f "$CODE_DIR/Results")"
  echo "status_sha256=$(sha256sum "$STATUS_FILE" | awk '{print $1}')"
  echo "completed_at=$(date -Is)"
} > "$LOG_DIR/$completion_name"
