#!/usr/bin/env bash
# CTREND_REVISIT_FILE_PURPOSE: Run one full P0 M1/M2 experiment with the frozen P1 engine and only unified missing-data preprocessing disabled.
set -euo pipefail

EXT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ROOT="$(cd "$EXT_ROOT/.." && pwd)"
ID="${1:-}"
MODE="${2:-production}"
case "$ID" in
  P0_M0_D0|P0_M0_D1|P0_M0_D2|P0_M1_D0|P0_M1_D1|P0_M1_D2|P0_M2_D0|P0_M2_D1|P0_M2_D2) ;;
  *) echo "invalid P0 experiment ID: $ID" >&2; exit 2 ;;
esac
[[ "$MODE" == production ]] || {
  echo "only the audited production topology is supported" >&2
  exit 2
}
IFS=_ read -r PREPROCESSING_ID METHOD DATA_ID <<< "$ID"
LEGACY_ID="${METHOD}_${DATA_ID}"

HOST_NPROC="$(env -u OMP_NUM_THREADS -u OMP_THREAD_LIMIT nproc)"
(( HOST_NPROC >= 128 )) || {
  echo "production topology requires at least 128 logical CPUs; found $HOST_NPROC" >&2
  exit 2
}
REGISTRATION="$ROOT/outputs/experiments/$ID/registration.env"
[[ ! -s "$REGISTRATION" ]] || {
  echo "experiment is already registered; refusing an accidental rerun: $ID" >&2
  exit 2
}

MATLAB_BIN="${MATLAB_BIN:-$(command -v matlab 2>/dev/null || true)}"
[[ -x "$MATLAB_BIN" ]] || {
  echo "MATLAB_BIN must identify MATLAB R2023b Update 11" >&2
  exit 2
}
MATLAB_BIN="$(readlink -f -- "$MATLAB_BIN")"
P0_REQUIRE_MATLAB_INTEGRATION=1 MATLAB_BIN="$MATLAB_BIN" \
  "$EXT_ROOT/scripts/preflight.sh"

STAMP="$(date -u +%Y%m%d_%H%M%S_%N)"
WORK_BASE="${WORK_BASE:-$ROOT/runtime}"
[[ "$WORK_BASE" == /* ]] || { echo "WORK_BASE must be absolute" >&2; exit 2; }
SOURCE="$WORK_BASE/materialized_sources/${ID}_$STAMP/source"
PACKAGE="$WORK_BASE/runtime_packages/${ID}_$STAMP.tar.gz"
RUN_BASE="${RUN_BASE:-$ROOT/outputs/experiments/$ID/runs}"
RUN_ROOT="${RUN_ROOT:-$RUN_BASE/${ID}_production_$STAMP}"
JOB_STORAGE_ROOT="${JOB_STORAGE_ROOT:-$WORK_BASE/job_storage/$ID/$STAMP}"
PARALLEL_WORKERS="${PARALLEL_WORKERS:-$((HOST_NPROC - 1))}"
[[ "$RUN_BASE" == /* && "$RUN_ROOT" == /* && \
   "$JOB_STORAGE_ROOT" == /* ]] || {
  echo "RUN_BASE, RUN_ROOT and JOB_STORAGE_ROOT must be absolute" >&2
  exit 2
}
[[ "$PARALLEL_WORKERS" =~ ^[1-9][0-9]*$ && \
   "$PARALLEL_WORKERS" -le "$HOST_NPROC" ]] || {
  echo "PARALLEL_WORKERS must be an integer in 1..nproc" >&2
  exit 2
}
[[ ! -e "$RUN_ROOT" && ! -L "$RUN_ROOT" && \
   ! -e "$JOB_STORAGE_ROOT" && ! -L "$JOB_STORAGE_ROOT" ]] || {
  echo "run root or job storage already exists" >&2
  exit 2
}
mkdir -p "$(dirname "$SOURCE")" "$(dirname "$PACKAGE")" "$RUN_BASE" \
  "$(dirname "$JOB_STORAGE_ROOT")" "$ROOT/outputs/logs" "$WORK_BASE/locks"

exec 8>"$WORK_BASE/locks/2x3x3_production.lock"
flock -n 8 || {
  echo "another 2x3x3 production run holds the package host lock" >&2
  exit 2
}

"$EXT_ROOT/scripts/materialize_experiment_source.sh" "$ID" "$SOURCE"
BOOTSTRAP_RESULTS_ROOT="$WORK_BASE/bootstrap_results/$ID/$STAMP" \
  "$ROOT/scripts/initialize_materialized_source.sh" "$LEGACY_ID" "$SOURCE"
"$ROOT/scripts/build_runtime_package.sh" "$LEGACY_ID" "$SOURCE" "$PACKAGE"

EXCLUSION="$ROOT/config/exclusions/$DATA_ID.csv"
export CTTREND_DATA_TREATMENT_ID="$DATA_ID"
export CTTREND_ASSET_EXCLUSION_FILE="$EXCLUSION"
export CTTREND_ASSET_EXCLUSION_SHA256
CTTREND_ASSET_EXCLUSION_SHA256="$(sha256sum "$EXCLUSION" | awk '{print $1}')"
export CTREND_RAW_ADJUSTMENT_MODE=none
export CTREND_CORE_EXPERIMENT_ID="$ID"
export CTREND_PREPROCESSING_ID="$PREPROCESSING_ID"
export CODE_DIR="$SOURCE"
export SOURCE_DIR="$SOURCE"
export MATLAB_BIN RUN_BASE RUN_ROOT JOB_STORAGE_ROOT PARALLEL_WORKERS
export OMP_NUM_THREADS=1 MKL_NUM_THREADS=1 OPENBLAS_NUM_THREADS=1
export NUMEXPR_NUM_THREADS=1

LAUNCH_MANIFEST="$SOURCE/../LAUNCH_MANIFEST.env"
{
  echo 'format=cttrend-pmd-launch-v1'
  echo "experiment_id=$ID"
  echo "preprocessing_id=$PREPROCESSING_ID"
  echo 'unified_missing_preprocessing=0'
  echo "method_id=$METHOD"
  echo "data_id=$DATA_ID"
  echo 'raw_adjustment_mode=none'
  echo "exclusion_file=$EXCLUSION"
  echo "exclusion_sha256=$CTTREND_ASSET_EXCLUSION_SHA256"
  echo "materialized_source=$SOURCE"
  echo "materialization_manifest_sha256=$(sha256sum "$SOURCE.materialization.env" | awk '{print $1}')"
  echo "runtime_package=$PACKAGE"
  echo "runtime_package_sha256=$(sha256sum "$PACKAGE" | awk '{print $1}')"
  echo "run_root=$RUN_ROOT"
  echo "parallel_workers=$PARALLEL_WORKERS"
  echo 'b09_topology=8x15'
  echo "started_at=$(date -Is)"
} > "$LAUNCH_MANIFEST"

if [[ "$METHOD" == M0 || "$METHOD" == M2 ]]; then
  export OLD_PIPELINE_VARIANT=m2
  [[ "$METHOD" != M0 ]] || export OLD_PIPELINE_VARIANT=v1
  export OLD_B02_PARALLEL_WORKERS="$PARALLEL_WORKERS"
  export OLD_V2_B09_EXECUTION_TOPOLOGY=local_full_8x15
  export OLD_V2_HANDOFF_DIR="$WORK_BASE/handoffs/$ID/$STAMP"
  "$ROOT/engines/$METHOD/runner/run_production.sh" "$PACKAGE"
else
  export JOB_STORAGE_ALLOWED_ROOT="$(dirname "$JOB_STORAGE_ROOT")"
  export B09_NUM_SHARDS=8
  export B09_WORKERS_PER_SHARD=15
  "$ROOT/engines/M1/runner/run_production.sh" "$PACKAGE"
fi

cp -- "$LAUNCH_MANIFEST" "$RUN_ROOT/P0_EXPERIMENT_LAUNCH_MANIFEST.env"
"$EXT_ROOT/scripts/write_portable_run_inventories.sh" "$ID" "$RUN_ROOT"
"$EXT_ROOT/scripts/register_completed_run.sh" "$ID" "$RUN_ROOT"
echo "EXPERIMENT_COMPLETE experiment=$ID run_root=$RUN_ROOT"
