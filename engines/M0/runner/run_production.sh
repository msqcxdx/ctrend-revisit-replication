#!/usr/bin/env bash
# CTREND_REVISIT_FILE_PURPOSE: Execute the full M0/M2 production pipeline with phase isolation, 8x15 b09, and fail-closed publication.
set -euo pipefail

SOURCE_RUNNER_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RUNNER_DIR="$SOURCE_RUNNER_DIR"
PROJECT_DIR="$(cd "$SOURCE_RUNNER_DIR/.." && pwd)"
OLD_PIPELINE_VARIANT="${OLD_PIPELINE_VARIANT:-v1}"
case "$OLD_PIPELINE_VARIANT" in
  v1)
    DEFAULT_SOURCE_DIR="$PROJECT_DIR/base"
    OLD_RUNTIME_ROOT_NAME=ctrend_old_pipeline
    RUN_NAME_PREFIX=old_v1
    ;;
  v2)
    DEFAULT_SOURCE_DIR="$PROJECT_DIR/old_code_v2"
    OLD_RUNTIME_ROOT_NAME=ctrend_old_v2_pipeline
    RUN_NAME_PREFIX=old_v2
    ;;
  *)
    echo "OLD_PIPELINE_VARIANT must be v1 or v2" >&2
    exit 2
    ;;
esac
SOURCE_DIR="${SOURCE_DIR:-$DEFAULT_SOURCE_DIR}"
if [[ "$OLD_PIPELINE_VARIANT" == v1 ]]; then
  DEFAULT_PACKAGE="$PROJECT_DIR/ctrend_old_pipeline.tar.gz"
else
  DEFAULT_PACKAGE="$PROJECT_DIR/ctrend_old_v2_pipeline.tar.gz"
fi
PACKAGE="${1:-$DEFAULT_PACKAGE}"
MATLAB_BIN="${MATLAB_BIN:-$(command -v matlab 2>/dev/null || true)}"
RUN_BASE="${RUN_BASE:-$PROJECT_DIR/runtime/runs}"
RUN_STAMP="${RUN_STAMP:-$(date -u +%Y%m%d_%H%M%S_%N)}"
RESEARCH_RUN_ID="${RESEARCH_RUN_ID:-$(</proc/sys/kernel/random/uuid)}"
RUN_ROOT="${RUN_ROOT:-$RUN_BASE/${RUN_NAME_PREFIX}_${RUN_STAMP}}"
JOB_STORAGE_ROOT="${JOB_STORAGE_ROOT:-$PROJECT_DIR/runtime/job_storage/$RESEARCH_RUN_ID}"
HANDOFF_DIR="${OLD_V2_HANDOFF_DIR:-$PROJECT_DIR/remote_handoff_old_v2}"
OLD_V2_B09_EXECUTION_TOPOLOGY="${OLD_V2_B09_EXECUTION_TOPOLOGY:-two_host}"
B09_COMPLETION_PUBLICATION_TIMEOUT_SECONDS="${B09_COMPLETION_PUBLICATION_TIMEOUT_SECONDS:-300}"
# Preserve single-threaded MATLAB/BLAS children without letting GNU nproc
# reinterpret OMP_NUM_THREADS=1 as a one-CPU host.  Unlike nproc --all this
# probe continues to respect affinity, cpuset, and cgroup restrictions.
HOST_NPROC="$(env -u OMP_NUM_THREADS -u OMP_THREAD_LIMIT nproc)"
if (( HOST_NPROC > 1 )); then
  DEFAULT_OLD_B02_WORKERS=$((HOST_NPROC - 1))
else
  DEFAULT_OLD_B02_WORKERS=1
fi
OLD_B02_PARALLEL_WORKERS="${OLD_B02_PARALLEL_WORKERS:-${PARALLEL_WORKERS:-$DEFAULT_OLD_B02_WORKERS}}"
LOG_ROOT="$RUN_ROOT/logs"
DATA_DIR="$RUN_ROOT/data.staging"
RESULTS_DIR="$RUN_ROOT/results.staging"
RUNTIME_PARENT="$RUN_ROOT/runtime"
CODE_DIR="$RUNTIME_PARENT/$OLD_RUNTIME_ROOT_NAME"
SEALED_RUNNER_DIR="$RUNTIME_PARENT/b09_parallel_runner_old_v2"
RUNTIME_PACKAGE="$RUN_ROOT/runtime_package.tar.gz"
SHARD_RUN_ROOT="$RUN_ROOT/b09_shards"
SHARD_RESULTS_ROOT="$RUN_ROOT/b09_shard_results"
LOCK_FILE="$SOURCE_DIR/logs/${RUN_NAME_PREFIX}_pipeline.lock"
REMOTE_PAYLOAD="$HANDOFF_DIR/ctrend_old_v2_b09_remote_payload_${RESEARCH_RUN_ID}.tar.gz"
CURRENT_PHASE_PID=""
CURRENT_PHASE_PGID=""
RUN_FINISHED=0

# shellcheck source=b09_completion_protocol.sh
source "$RUNNER_DIR/b09_completion_protocol.sh"

case "$OLD_V2_B09_EXECUTION_TOPOLOGY" in
  two_host)
    B09_TOPOLOGY_MODE=two_host
    B09_TOPOLOGY_TEMPLATE_NAME=b09_two_shard_topology.tsv
    B09_NUM_LOCAL_SUBSHARDS=4
    B09_LOCAL_WORKERS_PER_SUBSHARD=31
    B09_LOCAL_FIRST_COMBO=1
    B09_LOCAL_LAST_COMBO=1536
    B09_LOGICAL_SHARDS=2
    B09_NUM_REMOTE_SUBSHARDS=1
    ;;
  local_full_8x15)
    B09_TOPOLOGY_MODE=local_full_8x15
    B09_TOPOLOGY_TEMPLATE_NAME=b09_local_full_8x15_topology.tsv
    B09_NUM_LOCAL_SUBSHARDS=8
    B09_LOCAL_WORKERS_PER_SUBSHARD=15
    B09_LOCAL_FIRST_COMBO=1
    B09_LOCAL_LAST_COMBO=3072
    B09_LOGICAL_SHARDS=1
    B09_NUM_REMOTE_SUBSHARDS=0
    ;;
  *)
    echo "OLD_V2_B09_EXECUTION_TOPOLOGY must be two_host or local_full_8x15" >&2
    exit 2
    ;;
esac

[[ "$OLD_B02_PARALLEL_WORKERS" =~ ^[1-9][0-9]*$ ]] &&
  (( OLD_B02_PARALLEL_WORKERS <= HOST_NPROC )) || {
  echo "OLD_B02_PARALLEL_WORKERS must be an integer in 1..nproc" >&2
  exit 2
}
[[ "$B09_COMPLETION_PUBLICATION_TIMEOUT_SECONDS" =~ ^[1-9][0-9]*$ ]] || {
  echo "B09_COMPLETION_PUBLICATION_TIMEOUT_SECONDS must be a positive integer" >&2
  exit 2
}

[[ "$RESEARCH_RUN_ID" =~ ^[0-9a-fA-F-]{36}$ ]] || {
  echo "invalid research run ID" >&2
  exit 2
}
[[ -x "$MATLAB_BIN" && -d "$SOURCE_DIR/.raw_input_seed" &&
   -f "$PACKAGE" && -f "$PACKAGE.sha256" ]] || {
  echo "old v2 package, raw seed, or MATLAB is missing" >&2
  exit 2
}
[[ ! -e "$RUN_ROOT" && ! -e "$JOB_STORAGE_ROOT" ]] || {
  echo "old v2 run root or job-storage root already exists" >&2
  exit 2
}
if [[ "$OLD_V2_B09_EXECUTION_TOPOLOGY" == "two_host" ]]; then
  [[ ! -e "$REMOTE_PAYLOAD" && ! -e "$REMOTE_PAYLOAD.sha256" ]] || {
    echo "run-specific remote payload already exists" >&2
    exit 2
  }
fi

mkdir -p "$SOURCE_DIR/logs" "$HANDOFF_DIR"
exec 9>"$LOCK_FILE"
flock -n 9 || {
  echo "another old v2 production run holds $LOCK_FILE" >&2
  exit 2
}

mkdir -p "$RUN_ROOT" "$LOG_ROOT" "$DATA_DIR" "$RESULTS_DIR/CTREND" \
  "$RESULTS_DIR/Tables" "$RESULTS_DIR/Figures" "$RUNTIME_PARENT" \
  "$JOB_STORAGE_ROOT"

log_event() {
  printf '%s\t%s\n' "$(date -Is)" "$*" | tee -a "$LOG_ROOT/orchestrator_events.tsv"
}

stop_group() {
  local pgid="$1"
  [[ "$pgid" =~ ^[1-9][0-9]*$ ]] || return 0
  ps -eo pgid= | awk -v p="$pgid" '$1==p{found=1} END{exit !found}' || return 0
  kill -TERM -- "-$pgid" 2>/dev/null || true
  for _ in $(seq 1 120); do
    ps -eo pgid= | awk -v p="$pgid" '$1==p{found=1} END{exit !found}' || return 0
    sleep 1
  done
  kill -KILL -- "-$pgid" 2>/dev/null || true
}

cleanup() {
  local rc=$?
  trap - EXIT INT TERM
  if (( rc != 0 && RUN_FINISHED == 0 )); then
    stop_group "$CURRENT_PHASE_PGID"
    if [[ -d "$SHARD_RUN_ROOT" ]]; then
      while IFS= read -r pid; do
        [[ "$pid" =~ ^[1-9][0-9]*$ ]] && stop_group "$pid"
      done < <(find "$SHARD_RUN_ROOT" -type f \
        \( -name supervisor.pid -o -name remote_wrapper.pid \) \
        -exec sed -n '1p' {} \; 2>/dev/null)
      while IFS= read -r owner; do
        pgid="$(awk -F= '$1=="pgid"{print $2;exit}' "$owner" 2>/dev/null || true)"
        stop_group "$pgid"
      done < <(find "$SHARD_RUN_ROOT" -type f -name '*.owner.env' 2>/dev/null)
    fi
    {
      echo "format=ctrend-old-v2-run-failed-v1"
      echo "research_run_id=$RESEARCH_RUN_ID"
      echo "failed_at=$(date -Is)"
      echo "exit_code=$rc"
    } > "$RUN_ROOT/RUN_FAILED.env"
  fi
  exit "$rc"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

write_file_inventory() {
  local root="$1"
  (
    cd "$root"
    find -L . -maxdepth 1 -type f -printf '%P\0' |
      LC_ALL=C sort -z | xargs -0 -r sha256sum
  )
}

write_source_inventory() {
  local root="$1"
  (
    cd "$root"
    {
      find . -maxdepth 1 -type f \( -name '*.m' -o -name '*.sh' \) -printf '%P\n'
      for source_subdir in Utils LatexTables tests; do
        if [[ -d "$source_subdir" ]]; then
          find "$source_subdir" -type f \
            \( -name '*.m' -o -name '*.sh' \) -printf '%p\n'
        fi
      done
    } | LC_ALL=C sort | while IFS= read -r file; do sha256sum "$file"; done
  )
}

write_runner_inventory() {
  local root="$1"
  (
    cd "$root"
    find . -type f \
      \( -name '*.sh' -o -name '*.tsv' -o -name '*.m' \) \
      -printf '%P\n' | LC_ALL=C sort | while IFS= read -r file; do
        sha256sum "$file"
      done
  )
}

write_runner_inventory "$SOURCE_RUNNER_DIR" \
  > "$RUN_ROOT/runner_source_before.sha256"
cp -a -- "$SOURCE_RUNNER_DIR" "$SEALED_RUNNER_DIR"
find "$SEALED_RUNNER_DIR" -type l -print -quit | grep -q . && {
  echo "sealed old v2 runner contains a symbolic link" >&2
  exit 2
}
write_runner_inventory "$SEALED_RUNNER_DIR" \
  > "$RUN_ROOT/runner_sealed_before.sha256"
cmp -s "$RUN_ROOT/runner_source_before.sha256" \
  "$RUN_ROOT/runner_sealed_before.sha256" || {
  echo "sealed old v2 runner differs from its source" >&2
  exit 2
}
RUNNER_DIR="$SEALED_RUNNER_DIR"

expected_package_sha="$(awk '{print $1;exit}' "$PACKAGE.sha256")"
actual_package_sha="$(sha256sum "$PACKAGE" | awk '{print $1}')"
[[ "$expected_package_sha" =~ ^[0-9a-f]{64}$ &&
   "$actual_package_sha" == "$expected_package_sha" ]] || {
  echo "old v2 package sidecar mismatch" >&2
  exit 2
}
cp -- "$PACKAGE" "$RUNTIME_PACKAGE"
[[ "$(sha256sum "$RUNTIME_PACKAGE" | awk '{print $1}')" == \
   "$expected_package_sha" ]]
tar -xzf "$RUNTIME_PACKAGE" -C "$RUNTIME_PARENT"
[[ -d "$CODE_DIR" && -f "$CODE_DIR/PACKAGE_FILES.sha256" ]]
(
  cd "$CODE_DIR"
  sha256sum -c PACKAGE_FILES.sha256
) > "$LOG_ROOT/package_file_verification.log"

cp -a -- "$SOURCE_DIR/.raw_input_seed/." "$DATA_DIR/"
find "$DATA_DIR" -maxdepth 1 -type l -print -quit | grep -q . && {
  echo "run-local raw input snapshot contains a symbolic link" >&2
  exit 2
}
write_file_inventory "$SOURCE_DIR/.raw_input_seed" > "$RUN_ROOT/raw_source_before.sha256"
write_file_inventory "$DATA_DIR" > "$RUN_ROOT/raw_snapshot_before.sha256"
cmp -s "$RUN_ROOT/raw_source_before.sha256" "$RUN_ROOT/raw_snapshot_before.sha256" || {
  echo "run-local raw snapshot differs from old v2 source seed" >&2
  exit 2
}

ln -s "$DATA_DIR" "$CODE_DIR/DATA"
ln -s "$RESULTS_DIR" "$CODE_DIR/Results"
write_source_inventory "$SOURCE_DIR" > "$RUN_ROOT/source_code_before.sha256"
write_source_inventory "$CODE_DIR" > "$RUN_ROOT/runtime_code_before.sha256"
cmp -s "$RUN_ROOT/source_code_before.sha256" "$RUN_ROOT/runtime_code_before.sha256" || {
  echo "runtime source differs from old v2 source" >&2
  exit 2
}

{
  echo "format=ctrend-published-method-run-started-v1"
  echo "old_pipeline_variant=$OLD_PIPELINE_VARIANT"
  echo "research_run_id=$RESEARCH_RUN_ID"
  echo "run_stamp=$RUN_STAMP"
  echo "run_root=$RUN_ROOT"
  echo "source_code_dir=$SOURCE_DIR"
  echo "runtime_code_dir=$CODE_DIR"
  echo "runtime_package=$RUNTIME_PACKAGE"
  echo "runtime_package_sha256=$expected_package_sha"
  echo "runner_inventory_sha256=$(sha256sum "$RUN_ROOT/runner_sealed_before.sha256" | awk '{print $1}')"
  echo "raw_input_inventory_sha256=$(sha256sum "$RUN_ROOT/raw_snapshot_before.sha256" | awk '{print $1}')"
  echo "matlab_bin=$MATLAB_BIN"
  echo "host=$(hostname)"
  echo "nproc=$HOST_NPROC"
  echo "b02_execution_topology=parallel_asset_chunks"
  echo "b02_parallel_workers=$OLD_B02_PARALLEL_WORKERS"
  echo "b09_execution_topology=$OLD_V2_B09_EXECUTION_TOPOLOGY"
  echo "b09_topology_template=$B09_TOPOLOGY_TEMPLATE_NAME"
  echo "b09_logical_shards=$B09_LOGICAL_SHARDS"
  echo "b09_local_subshards=$B09_NUM_LOCAL_SUBSHARDS"
  echo "b09_workers_per_subshard=$B09_LOCAL_WORKERS_PER_SUBSHARD"
  echo "b09_completion_publication_timeout_seconds=$B09_COMPLETION_PUBLICATION_TIMEOUT_SECONDS"
  echo "local_first_combo=$B09_LOCAL_FIRST_COMBO"
  echo "local_last_combo=$B09_LOCAL_LAST_COMBO"
  if [[ "$OLD_V2_B09_EXECUTION_TOPOLOGY" == "two_host" ]]; then
    echo "remote_first_combo=1537"
    echo "remote_last_combo=3072"
  else
    echo "remote_first_combo=0"
    echo "remote_last_combo=0"
  fi
  echo "started_at=$(date -Is)"
} > "$RUN_ROOT/RUN_STARTED.env"

run_shell_phase() {
  local phase="$1"
  shift
  local phase_dir="$LOG_ROOT/$phase"
  local owner="$phase_dir/phase.owner.env"
  local token
  token="$(</proc/sys/kernel/random/uuid)"
  mkdir -p "$phase_dir"
  log_event "START phase=$phase"
  setsid "$RUNNER_DIR/run_owned_process.sh" "$owner" "$token" \
    "$CODE_DIR" "$phase" "$@" > "$phase_dir/pipeline.log" 2>&1 &
  CURRENT_PHASE_PID=$!
  CURRENT_PHASE_PGID=$CURRENT_PHASE_PID
  printf '%s\n' "$CURRENT_PHASE_PID" > "$phase_dir/phase.pid"
  set +e
  wait "$CURRENT_PHASE_PID"
  rc=$?
  set -e
  CURRENT_PHASE_PID=""
  CURRENT_PHASE_PGID=""
  {
    echo "complete=$((rc==0 ? 1 : 0))"
    echo "exit_code=$rc"
    echo "completed_at=$(date -Is)"
  } > "$phase_dir/phase.complete.env"
  (( rc == 0 )) || return "$rc"
  log_event "END phase=$phase rc=0"
}

run_matlab_step() {
  local step="$1"
  local workers="${2:-0}"
  local phase_dir="$LOG_ROOT/$step"
  local pref="$JOB_STORAGE_ROOT/$step/matlab_pref"
  local job="$JOB_STORAGE_ROOT/$step/parallel_job_storage"
  local expression pool_setup=""
  mkdir -p "$pref" "$job"
  if (( workers > 0 )); then
    pool_setup="c=parcluster('local'); c.JobStorageLocation='$job'; c.NumWorkers=$workers; saveProfile(c); parpool(c,$workers);"
  fi
  expression="try, cd('$CODE_DIR'); $pool_setup run('$step.m'); fSaveOpenFigures('$step'); exit(0); catch ME, disp(getReport(ME,'extended','hyperlinks','off')); exit(1); end"
  run_shell_phase "$step" env \
    MATLAB_PREFDIR="$pref" \
    OMP_NUM_THREADS=1 MKL_NUM_THREADS=1 OPENBLAS_NUM_THREADS=1 NUMEXPR_NUM_THREADS=1 \
    "$MATLAB_BIN" -licmode onlinelicensing -nodisplay -nosplash \
    -batch "$expression"
}

log_event "START phase=unit_tests"
"$RUNNER_DIR/tests/test_topology.sh" > "$LOG_ROOT/unit_tests.log" 2>&1
if [[ "$OLD_PIPELINE_VARIANT" == "v2" ]]; then
  "$RUNNER_DIR/tests/test_legacy_v2_source_delta.sh" \
    "$PROJECT_DIR/ctrend_old_pipeline.tar.gz" "$SOURCE_DIR" \
    >> "$LOG_ROOT/unit_tests.log" 2>&1
else
  grep -Fq "OLD_V1_B09_FIRST_COMBO" \
    "$SOURCE_DIR/b09RunResearchDesigns.m"
  grep -Fq "OLD_V1_B09_LAST_COMBO" \
    "$SOURCE_DIR/b09RunResearchDesigns.m"
  echo OLD_V1_RANGE_ADAPTER_TEST_OK >> "$LOG_ROOT/unit_tests.log"
fi
log_event "END phase=unit_tests rc=0"

# Prove at every production launch that the corrected-style asset-chunk
# adapter is bitwise identical to the published serial formulas before it is
# allowed to consume raw data.
B02_TEST_WORKERS=4
(( HOST_NPROC < B02_TEST_WORKERS )) && B02_TEST_WORKERS="$HOST_NPROC"
B02_TEST_PREF="$JOB_STORAGE_ROOT/unit_test_old_b02_parallel/matlab_pref"
B02_TEST_JOB="$JOB_STORAGE_ROOT/unit_test_old_b02_parallel/job_storage"
mkdir -p "$B02_TEST_PREF" "$B02_TEST_JOB"
log_event "START phase=unit_test_old_b02_parallel workers=$B02_TEST_WORKERS"
run_shell_phase unit_test_old_b02_parallel env \
  MATLAB_PREFDIR="$B02_TEST_PREF" \
  OMP_NUM_THREADS=1 MKL_NUM_THREADS=1 OPENBLAS_NUM_THREADS=1 \
  NUMEXPR_NUM_THREADS=1 \
  PIPELINE_CODE_DIR="$CODE_DIR" \
  RUNNER_TEST_DIR="$RUNNER_DIR/tests" \
  B02_TEST_JOB_STORAGE="$B02_TEST_JOB" \
  B02_TEST_WORKERS="$B02_TEST_WORKERS" \
  "$MATLAB_BIN" -licmode onlinelicensing -nodisplay -nosplash -batch \
  "try, cd(getenv('PIPELINE_CODE_DIR')); addpath('./Utils'); addpath(getenv('RUNNER_TEST_DIR')); c=parcluster('local'); c.JobStorageLocation=getenv('B02_TEST_JOB_STORAGE'); c.NumWorkers=str2double(getenv('B02_TEST_WORKERS')); parpool(c,c.NumWorkers); test_b02_parallel_equivalence(getenv('PIPELINE_CODE_DIR')); exit(0); catch ME, disp(getReport(ME,'extended','hyperlinks','off')); exit(1); end"
log_event "END phase=unit_test_old_b02_parallel rc=0"

for step in setup b00GenerateDesignChoices b01ReadData; do
  run_matlab_step "$step" 0
done
log_event "START phase=b02CalculateIndicators workers=$OLD_B02_PARALLEL_WORKERS topology=parallel_asset_chunks"
run_matlab_step b02CalculateIndicators "$OLD_B02_PARALLEL_WORKERS"
log_event "END phase=b02CalculateIndicators rc=0"

design_sha="$(sha256sum "$CODE_DIR/DesignChoices.mat" | awk '{print $1}')"
printf '%s  DesignChoices.mat\n' "$design_sha" \
  > "$RUN_ROOT/design_choices_after_b00.sha256"
write_file_inventory "$DATA_DIR" > "$RUN_ROOT/data_after_b02.sha256"
data_inputs_sha="$(sha256sum "$RUN_ROOT/data_after_b02.sha256" | awk '{print $1}')"

if [[ "$OLD_V2_B09_EXECUTION_TOPOLOGY" == "two_host" ]]; then
  log_event "START phase=remote_payload_build"
  "$RUNNER_DIR/build_b09_remote_payload.sh" "$RUN_ROOT" "$REMOTE_PAYLOAD" \
    > "$LOG_ROOT/remote_payload_build.log" 2>&1
  log_event "END phase=remote_payload_build rc=0 payload=$REMOTE_PAYLOAD"
fi

for step in b03Table1_ResearchSample b04Table2_TechnicalIndicatorStrategyReturns; do
  run_matlab_step "$step" 0
done
run_matlab_step b05CreateCTREND 64
for step in b06Table3_UnivariatePortfolioSorts \
  b07Table4_CrossSectionalRegressions \
  b08Table5_PerformanceInSubperiodsAndDifferentMarketStates \
  b11Figure3_AnomalyAlphas b12Table7_FrontierExpansionTest \
  b13Table8_TheCTRENDFactorPerformanceInBigAndLiquidCryptos \
  b14Table9_CTRENDPortfoliosAndTransactionCosts \
  b15TableB3_BivariatePortfolioSorts \
  b16TableB4_CTRENDPerformanceDependingOnCryptocurrencyType \
  b17TableB10_ExtendedPortfolioHoldingPeriod \
  b18FigureC3_C4_AverageVariableImportance; do
  run_matlab_step "$step" 0
done

[[ "$(sha256sum "$CODE_DIR/DesignChoices.mat" | awk '{print $1}')" == "$design_sha" ]]
write_file_inventory "$DATA_DIR" > "$RUN_ROOT/data_before_b09.sha256"
cmp -s "$RUN_ROOT/data_after_b02.sha256" "$RUN_ROOT/data_before_b09.sha256" || {
  echo "old v2 DATA changed after b02" >&2
  exit 1
}

log_event "START phase=b09_local_shards topology=$OLD_V2_B09_EXECUTION_TOPOLOGY range=${B09_LOCAL_FIRST_COMBO}:${B09_LOCAL_LAST_COMBO} subshards=$B09_NUM_LOCAL_SUBSHARDS workers=${B09_NUM_LOCAL_SUBSHARDS}x${B09_LOCAL_WORKERS_PER_SUBSHARD}"
OLD_V2_PACKAGE="$RUNTIME_PACKAGE" \
CANONICAL_CODE_DIR="$CODE_DIR" \
MATLAB_BIN="$MATLAB_BIN" \
WORKERS_PER_SHARD="$B09_LOCAL_WORKERS_PER_SUBSHARD" LOGICAL_SHARD_ID=1 \
NUM_SUBSHARDS="$B09_NUM_LOCAL_SUBSHARDS" \
FIRST_COMBO="$B09_LOCAL_FIRST_COMBO" LAST_COMBO="$B09_LOCAL_LAST_COMBO" \
B09_TOPOLOGY_MODE="$B09_TOPOLOGY_MODE" \
RUN_ROOT="$SHARD_RUN_ROOT" RESULTS_ROOT="$SHARD_RESULTS_ROOT" \
B09_JOB_STORAGE_ROOT="$JOB_STORAGE_ROOT/b09_shards" \
B09_LATEST_POINTER_DIR="$RUN_ROOT/b09_status" \
RESEARCH_RUN_ID="$RESEARCH_RUN_ID" \
EXPECTED_PACKAGE_SHA256="$expected_package_sha" \
EXPECTED_DESIGN_CHOICES_SHA256="$design_sha" \
EXPECTED_DATA_INPUTS_SHA256="$data_inputs_sha" \
OLD_RUNTIME_ROOT_NAME="$OLD_RUNTIME_ROOT_NAME" \
  "$RUNNER_DIR/launch_b09_shards.sh" \
  > "$LOG_ROOT/b09_launch.log" 2>&1

topology_file="$SHARD_RUN_ROOT/$B09_TOPOLOGY_TEMPLATE_NAME"
# shellcheck source=b09_topology_lib.sh
source "$RUNNER_DIR/b09_topology_lib.sh"
ctrend_b09_validate_topology \
  "$topology_file" "$RUNNER_DIR/$B09_TOPOLOGY_TEMPLATE_NAME"

remote_waiter_pid=""
if [[ "$OLD_V2_B09_EXECUTION_TOPOLOGY" == "two_host" ]]; then
  mkdir -p "$SHARD_RUN_ROOT/shard2/subshard1"
  setsid "$RUNNER_DIR/wait_b09_remote_return.sh" \
    "$SHARD_RUN_ROOT" "$SHARD_RESULTS_ROOT" "$HANDOFF_DIR" \
    "$RESEARCH_RUN_ID" > "$SHARD_RUN_ROOT/shard2/subshard1/launcher_bootstrap.log" 2>&1 &
  remote_waiter_pid=$!
  printf '%s\n' "$remote_waiter_pid" > "$SHARD_RUN_ROOT/shard2/subshard1/supervisor.pid"
fi

while true; do
  complete=0
  failed=0
  progress=""
  for subshard in $(seq 1 "$B09_NUM_LOCAL_SUBSHARDS"); do
    shard_dir="$SHARD_RUN_ROOT/shard1/subshard${subshard}"
    heartbeat_file="$shard_dir/heartbeat.env"
    state="$(ctrend_b09_observed_terminal_state "$shard_dir" \
      "$RESEARCH_RUN_ID" "$B09_COMPLETION_PUBLICATION_TIMEOUT_SECONDS" \
      "$(date +%s)")"
    count="$(awk -F= '$1=="combo_files"{print $2;exit}' "$heartbeat_file" 2>/dev/null || echo 0)"
    [[ "$state" == COMPLETE ]] && complete=$((complete+1))
    [[ "$state" == FAILED* ]] && failed=$((failed+1))
    progress+=" shard1.subshard${subshard}=${state}:${count}"
  done
  log_event "PROGRESS phase=b09 complete_local=$complete failed_local=$failed$progress"
  (( failed == 0 )) || { echo "old v2 local b09 shard failed" >&2; exit 1; }
  if [[ "$OLD_V2_B09_EXECUTION_TOPOLOGY" == "two_host" ]]; then
    remote_state="$(awk -F= '$1=="state"{print $2;exit}' \
      "$SHARD_RUN_ROOT/shard2/subshard1/state.env" 2>/dev/null || echo WAITING_FOR_REMOTE_RETURN)"
    remote_result_dir="$SHARD_RESULTS_ROOT/shard2/subshard1/CTREND"
    remote_count=0
    if [[ -d "$remote_result_dir" ]]; then
      remote_count="$(find "$remote_result_dir" -maxdepth 1 -type f \
        -name 'CTREND_Combo*.mat' | wc -l)"
    fi
    log_event "PROGRESS phase=b09 remote=shard2.subshard1:${remote_state}:${remote_count}"
    if ! kill -0 "$remote_waiter_pid" 2>/dev/null && [[ "$remote_state" != COMPLETE ]]; then
      echo "old v2 remote return waiter exited before a verified return" >&2
      exit 1
    fi
    if (( complete == B09_NUM_LOCAL_SUBSHARDS )) && \
        [[ "$remote_state" == COMPLETE &&
           -f "$SHARD_RUN_ROOT/shard2/subshard1/return.env" ]]; then
      break
    fi
  elif (( complete == B09_NUM_LOCAL_SUBSHARDS )); then
    break
  fi
  sleep 60
done

mkdir -p "$RUN_ROOT/b09_manifests"
validate_and_import_shard() {
  local label="$1" first="$2" last="$3"
  local source="$SHARD_RESULTS_ROOT/$label/CTREND"
  local manifest="$source/ResearchDesignRunManifest.env"
  local completion="$SHARD_RUN_ROOT/$label/completion.env"
  local expected_count=$((last-first+1))
  [[ -f "$completion" &&
     "$(ctrend_b09_record_value "$completion" complete)" == 1 &&
     "$(ctrend_b09_record_value "$completion" research_run_id)" == \
       "$RESEARCH_RUN_ID" &&
     -f "$manifest" && -f "$manifest.sha256" ]]
  (
    cd "$source"
    sha256sum -c ResearchDesignRunManifest.env.sha256 >/dev/null
  )
  [[ "$(awk -F= '$1=="research_run_id"{print $2;exit}' "$manifest")" == "$RESEARCH_RUN_ID" &&
     "$(awk -F= '$1=="first_combo"{print $2;exit}' "$manifest")" == "$first" &&
     "$(awk -F= '$1=="last_combo"{print $2;exit}' "$manifest")" == "$last" &&
     "$(awk -F= '$1=="combo_files"{print $2;exit}' "$manifest")" == "$expected_count" &&
     "$(awk -F= '$1=="package_sha256"{print $2;exit}' "$manifest")" == "$expected_package_sha" &&
     "$(awk -F= '$1=="data_inputs_sha256"{print $2;exit}' "$manifest")" == "$data_inputs_sha" &&
     "$(awk -F= '$1=="design_choices_sha256"{print $2;exit}' "$manifest")" == "$design_sha" ]]
  cp -- "$manifest" "$RUN_ROOT/b09_manifests/${label//\//_}.env"
  for combo in $(seq "$first" "$last"); do
    file="CTREND_Combo${combo}.mat"
    [[ ! -e "$RESULTS_DIR/CTREND/$file" ]]
    (
      cd "$source"
      sha256sum -c "$file.sha256" >/dev/null
    )
    cp -- "$source/$file" "$RESULTS_DIR/CTREND/$file"
    cp -- "$source/$file.sha256" "$RESULTS_DIR/CTREND/$file.sha256"
  done
}

while IFS=$'\t' read -r source_label logical_shard execution_site \
    first_combo last_combo; do
  validate_and_import_shard "$source_label" "$first_combo" "$last_combo"
done < <(ctrend_b09_source_rows "$topology_file")

combo_count="$(find "$RESULTS_DIR/CTREND" -maxdepth 1 -type f \
  -name 'CTREND_Combo*.mat' | wc -l)"
digest_count="$(find "$RESULTS_DIR/CTREND" -maxdepth 1 -type f \
  -name 'CTREND_Combo*.mat.sha256' | wc -l)"
[[ "$combo_count" -eq 3072 && "$digest_count" -eq 3072 ]]
{
  echo "format=ctrend-old-v2-complete-b09-manifest-v1"
  echo "research_run_id=$RESEARCH_RUN_ID"
  echo "combo_files=$combo_count"
  echo "digest_files=$digest_count"
  echo "package_sha256=$expected_package_sha"
  echo "data_inputs_sha256=$data_inputs_sha"
  echo "design_choices_sha256=$design_sha"
  echo "execution_topology=$OLD_V2_B09_EXECUTION_TOPOLOGY"
  echo "topology_sha256=$(sha256sum "$topology_file" | awk '{print $1}')"
  echo "physical_sources=$(ctrend_b09_source_rows "$topology_file" | wc -l)"
  echo "merged_at=$(date -Is)"
} > "$RESULTS_DIR/CTREND/ResearchDesignRunManifest.env"
(
  cd "$RESULTS_DIR/CTREND"
  sha256sum ResearchDesignRunManifest.env > ResearchDesignRunManifest.env.sha256
)
log_event "END phase=b09 rc=0 combos=3072"

run_matlab_step b10Table6_FactorPerformanceAcrossResearchDesignChoices 0
run_shell_phase supplementary env CODE_DIR="$CODE_DIR" MATLAB_BIN="$MATLAB_BIN" \
  "$CODE_DIR/run_supplementary_outputs.sh"

write_source_inventory "$SOURCE_DIR" > "$RUN_ROOT/source_code_after.sha256"
write_source_inventory "$CODE_DIR" > "$RUN_ROOT/runtime_code_after.sha256"
write_runner_inventory "$SOURCE_RUNNER_DIR" \
  > "$RUN_ROOT/runner_source_after.sha256"
write_runner_inventory "$SEALED_RUNNER_DIR" \
  > "$RUN_ROOT/runner_sealed_after.sha256"
write_file_inventory "$SOURCE_DIR/.raw_input_seed" > "$RUN_ROOT/raw_source_after.sha256"
write_file_inventory "$DATA_DIR" > "$RUN_ROOT/data_after_run.sha256"
cmp -s "$RUN_ROOT/source_code_before.sha256" "$RUN_ROOT/source_code_after.sha256"
cmp -s "$RUN_ROOT/runtime_code_before.sha256" "$RUN_ROOT/runtime_code_after.sha256"
cmp -s "$RUN_ROOT/runner_source_before.sha256" "$RUN_ROOT/runner_source_after.sha256"
cmp -s "$RUN_ROOT/runner_sealed_before.sha256" "$RUN_ROOT/runner_sealed_after.sha256"
cmp -s "$RUN_ROOT/raw_source_before.sha256" "$RUN_ROOT/raw_source_after.sha256"
cmp -s "$RUN_ROOT/data_after_b02.sha256" "$RUN_ROOT/data_after_run.sha256"
[[ "$(sha256sum "$PACKAGE" | awk '{print $1}')" == "$expected_package_sha" ]]
(
  cd "$RESULTS_DIR"
  find . -type f -printf '%P\0' | LC_ALL=C sort -z |
    xargs -0 -r sha256sum
) > "$RUN_ROOT/results_inventory.sha256"

{
  echo "format=ctrend-published-method-run-complete-v1"
  echo "complete=1"
  echo "old_pipeline_variant=$OLD_PIPELINE_VARIANT"
  echo "research_run_id=$RESEARCH_RUN_ID"
  echo "run_root=$RUN_ROOT"
  echo "package_sha256=$expected_package_sha"
  echo "data_inputs_sha256=$data_inputs_sha"
  echo "design_choices_sha256=$design_sha"
  echo "results_inventory_sha256=$(sha256sum "$RUN_ROOT/results_inventory.sha256" | awk '{print $1}')"
  echo "b02_execution_topology=parallel_asset_chunks"
  echo "b02_parallel_workers=$OLD_B02_PARALLEL_WORKERS"
  echo "b02_serial_parallel_equivalence_test=pass"
  echo "b09_combo_files=3072"
  echo "b09_execution_topology=$OLD_V2_B09_EXECUTION_TOPOLOGY"
  echo "b09_shards=$B09_NUM_LOCAL_SUBSHARDS"
  echo "b09_workers_per_shard=$B09_LOCAL_WORKERS_PER_SUBSHARD"
  echo "b09_completion_publication_timeout_seconds=$B09_COMPLETION_PUBLICATION_TIMEOUT_SECONDS"
  echo "completed_at=$(date -Is)"
} > "$RUN_ROOT/RUN_COMPLETE"
log_event "RUN_COMPLETE run_id=$RESEARCH_RUN_ID run_root=$RUN_ROOT"
RUN_FINISHED=1
trap - EXIT INT TERM
