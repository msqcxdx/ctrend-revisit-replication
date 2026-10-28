#!/usr/bin/env bash
# CTREND_REVISIT_FILE_PURPOSE: Run one declared b09 combo range and atomically publish validated MAT files and sidecars.
set -euo pipefail

RUNNER_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [[ "$#" -ne 6 ]]; then
  echo "usage: $0 CODE_DIR RANGE_FILE RUN_ID WORKERS MATLAB_BIN SHARD_LOG_DIR" >&2
  exit 2
fi

CODE_DIR="$1"
RANGE_FILE="$2"
RUN_ID="$3"
WORKERS="$4"
MATLAB_BIN="$5"
SHARD_LOG_DIR="$6"
POOL_START_RETRIES="${POOL_START_RETRIES:-3}"
POOL_RETRY_DELAY_SECONDS="${POOL_RETRY_DELAY_SECONDS:-20}"
POOL_START_TIMEOUT_SECONDS="${POOL_START_TIMEOUT_SECONDS:-2100}"
NO_PROGRESS_TIMEOUT_SECONDS="${NO_PROGRESS_TIMEOUT_SECONDS:-5400}"
HEARTBEAT_INTERVAL_SECONDS="${HEARTBEAT_INTERVAL_SECONDS:-60}"
MATLAB_STOP_GRACE_SECONDS="${MATLAB_STOP_GRACE_SECONDS:-120}"
B09_JOB_STORAGE_ROOT="${B09_JOB_STORAGE_ROOT:-$(dirname "$SHARD_LOG_DIR")/job_storage}"
B09_SHARD_ID="${B09_SHARD_ID:-manual}"
B09_SHARD_STATE_FILE="${B09_SHARD_STATE_FILE:-$SHARD_LOG_DIR/state.env}"
B09_SHARD_HEARTBEAT_FILE="${B09_SHARD_HEARTBEAT_FILE:-$SHARD_LOG_DIR/heartbeat.env}"
B09_SHARD_COMPLETION_FILE="${B09_SHARD_COMPLETION_FILE:-$(dirname "$SHARD_LOG_DIR")/completion.env}"
EXPECTED_DESIGN_CHOICES_SHA256="${EXPECTED_DESIGN_CHOICES_SHA256:-}"
B09_ORCHESTRATOR_PID="${B09_ORCHESTRATOR_PID:-}"
B09_ORCHESTRATOR_START_TICKS="${B09_ORCHESTRATOR_START_TICKS:-}"
SHARD_ROOT="$(dirname "$SHARD_LOG_DIR")"

# shellcheck source=../corrected_code_v2/run_safety.sh
source "$CODE_DIR/run_safety.sh"

[[ -d "$CODE_DIR" ]] || { echo "missing code directory: $CODE_DIR" >&2; exit 2; }
[[ -f "$RANGE_FILE" ]] || { echo "missing range file: $RANGE_FILE" >&2; exit 2; }
[[ -x "$MATLAB_BIN" ]] || { echo "MATLAB is not executable: $MATLAB_BIN" >&2; exit 2; }
[[ "$WORKERS" =~ ^[1-9][0-9]*$ ]] || { echo "invalid worker count: $WORKERS" >&2; exit 2; }
[[ "$B09_SHARD_ID" =~ ^[A-Za-z0-9_.-]+$ ]] || {
  echo "invalid B09_SHARD_ID: $B09_SHARD_ID" >&2
  exit 2
}
[[ "$EXPECTED_DESIGN_CHOICES_SHA256" =~ ^[0-9a-f]{64}$ &&
   "$(sha256sum "$CODE_DIR/DesignChoices.mat" | awk '{print $1}')" == \
     "$EXPECTED_DESIGN_CHOICES_SHA256" ]] || {
  echo "shard DesignChoices.mat differs from the frozen post-b00 hash" >&2
  exit 2
}
if [[ -n "$B09_ORCHESTRATOR_PID" ||
      -n "$B09_ORCHESTRATOR_START_TICKS" ]]; then
  [[ "$B09_ORCHESTRATOR_PID" =~ ^[1-9][0-9]*$ &&
     "$B09_ORCHESTRATOR_START_TICKS" =~ ^[1-9][0-9]*$ ]] || {
    echo "invalid b09 orchestrator lease" >&2
    exit 2
  }
fi
[[ "$POOL_START_RETRIES" =~ ^[1-9][0-9]*$ ]] || {
  echo "invalid POOL_START_RETRIES: $POOL_START_RETRIES" >&2
  exit 2
}
[[ "$POOL_RETRY_DELAY_SECONDS" =~ ^[0-9]+$ ]] || {
  echo "invalid POOL_RETRY_DELAY_SECONDS: $POOL_RETRY_DELAY_SECONDS" >&2
  exit 2
}
for timeout_name in POOL_START_TIMEOUT_SECONDS NO_PROGRESS_TIMEOUT_SECONDS \
    HEARTBEAT_INTERVAL_SECONDS MATLAB_STOP_GRACE_SECONDS; do
  timeout_value="${!timeout_name}"
  [[ "$timeout_value" =~ ^[1-9][0-9]*$ ]] || {
    echo "invalid $timeout_name: $timeout_value" >&2
    exit 2
  }
done

mkdir -p "$SHARD_LOG_DIR"
rm -f -- "$B09_SHARD_COMPLETION_FILE"
export OMP_NUM_THREADS=1
export MKL_NUM_THREADS=1
export OPENBLAS_NUM_THREADS=1
export NUMEXPR_NUM_THREADS=1

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

[[ -f "$SHARD_ROOT/package_matlab_sources.sha256" ]] || {
  echo "shard start source inventory is missing" >&2
  exit 2
}
write_runtime_source_inventory "$CODE_DIR" \
  > "$SHARD_ROOT/runtime_matlab_sources_at_start.sha256"
cmp -s "$SHARD_ROOT/package_matlab_sources.sha256" \
  "$SHARD_ROOT/runtime_matlab_sources_at_start.sha256" || {
  echo "shard executable source changed before MATLAB start" >&2
  exit 2
}

iNumRanges=0
iFirstCombo=0
iLastCombo=0
while read -r combo_start combo_end extra; do
  [[ -n "${combo_start:-}" ]] || continue
  [[ -z "${extra:-}" ]] || {
    echo "range rows must contain exactly START END: $combo_start $combo_end $extra" >&2
    exit 2
  }
  [[ "$combo_start" =~ ^[1-9][0-9]*$ && "$combo_end" =~ ^[1-9][0-9]*$ ]] || {
    echo "invalid combo range: $combo_start $combo_end" >&2
    exit 2
  }
  (( combo_start <= combo_end && combo_end <= 3072 )) || {
    echo "combo range out of bounds: $combo_start $combo_end" >&2
    exit 2
  }
  iNumRanges=$((iNumRanges + 1))
  if (( iNumRanges == 1 )); then
    iFirstCombo="$combo_start"
  fi
  iLastCombo="$combo_end"
done < "$RANGE_FILE"
if (( iNumRanges == 0 )); then
  now_epoch="$(date +%s)"
  state_temporary="${B09_SHARD_STATE_FILE}.tmp.$$"
  heartbeat_temporary="${B09_SHARD_HEARTBEAT_FILE}.tmp.$$"
  mkdir -p "$(dirname "$B09_SHARD_STATE_FILE")" \
    "$(dirname "$B09_SHARD_HEARTBEAT_FILE")"
  completion_temporary="${B09_SHARD_COMPLETION_FILE}.tmp.$$"
  {
    echo "format=cttrend-shard-complete-v1"
    echo "complete=1"
    echo "shard_id=$B09_SHARD_ID"
    echo "supervisor_pid=$$"
    echo "combo_files=0"
    echo "research_run_id=$RUN_ID"
    echo "source_inventory_sha256=$(sha256sum \
      "$SHARD_ROOT/runtime_matlab_sources_at_start.sha256" | awk '{print $1}')"
    echo "design_choices_sha256=$EXPECTED_DESIGN_CHOICES_SHA256"
    echo "completed_at=$(date -Is)"
  } > "$completion_temporary"
  mv -f -- "$completion_temporary" "$B09_SHARD_COMPLETION_FILE"
  {
    echo "state=COMPLETE"
    echo "reason=no_ranges_assigned"
    echo "updated_at=$(date -Is)"
    echo "updated_epoch=$now_epoch"
    echo "supervisor_pid=$$"
    echo "matlab_pid="
    echo "attempt=0"
    echo "workers=$WORKERS"
    echo "shard_id=$B09_SHARD_ID"
    echo "range_file=$RANGE_FILE"
    echo "num_ranges=0"
    echo "first_combo=0"
    echo "last_combo=0"
  } > "$state_temporary"
  mv -f -- "$state_temporary" "$B09_SHARD_STATE_FILE"
  {
    echo "state=COMPLETE"
    echo "updated_at=$(date -Is)"
    echo "updated_epoch=$now_epoch"
    echo "supervisor_pid=$$"
    echo "matlab_pid="
    echo "attempt=0"
    echo "pool_active=0"
    echo "combo_files=0"
    echo "latest_output_epoch=0"
    echo "matlab_log_bytes=0"
    echo "last_progress_epoch=$now_epoch"
    echo "seconds_since_progress=0"
  } > "$heartbeat_temporary"
  mv -f -- "$heartbeat_temporary" "$B09_SHARD_HEARTBEAT_FILE"
  echo "shard_complete=1 ranges=0 attempts=0 at $(date -Is)"
  exit 0
fi

runtime_dir="$SHARD_LOG_DIR/runtime"
driver_file="$runtime_dir/cttrend_b09_persistent_driver.m"
session_log="$SHARD_LOG_DIR/pipeline.log"
mkdir -p "$runtime_dir"

# The runtime-only driver keeps its loop variables in a function workspace.
# b09RunResearchDesigns begins with `clear`, but that clears only MATLAB's
# base workspace; the driver therefore survives and reuses the same pool for
# every recovery range.  No repository .m source is generated or modified.
printf '%s\n' \
  'function cttrend_b09_persistent_driver()' \
  'rangeFile = getenv("B09_RANGE_FILE");' \
  'logDir = getenv("PIPELINE_LOG_DIR");' \
  'fid = fopen(rangeFile,"r");' \
  'assert(fid >= 0,"Could not open persistent shard range file");' \
  'cleanupFile = onCleanup(@() fclose(fid));' \
  'values = textscan(fid,"%f%f");' \
  'ranges = [values{1},values{2}];' \
  'clear cleanupFile' \
  'assert(~isempty(ranges) && all(isfinite(ranges),"all"),"Invalid persistent shard ranges");' \
  'for idx = 1:size(ranges,1)' \
  '    first = ranges(idx,1);' \
  '    last = ranges(idx,2);' \
  '    setenv("PIPELINE_COMBO_START",sprintf("%d",first));' \
  '    setenv("PIPELINE_COMBO_END",sprintf("%d",last));' \
  '    setenv("PIPELINE_STATUS_FILE",fullfile(logDir,sprintf("status_%04d_%04d.tsv",first,last)));' \
  '    fprintf(2,"persistent_range_start=%04d_%04d index=%d/%d at=%s\n",first,last,idx,size(ranges,1),char(datetime("now","Format","yyyyMMdd_HHmmss")));' \
  '    run_full_pipeline_corrected();' \
  '    fprintf(2,"persistent_range_complete=%04d_%04d index=%d/%d at=%s\n",first,last,idx,size(ranges,1),char(datetime("now","Format","yyyyMMdd_HHmmss")));' \
  'end' \
  'fprintf(2,"persistent_shard_complete=1 ranges=%d at=%s\n",size(ranges,1),char(datetime("now","Format","yyyyMMdd_HHmmss")));' \
  'end' > "$driver_file"

matlab_pid=""
matlab_pgid=""
matlab_owner_file=""
attempt=0
current_job_storage=""
current_state="INITIALIZING"

orchestrator_lease_is_live() {
  local observed_start_ticks
  [[ -n "$B09_ORCHESTRATOR_PID" ]] || return 0
  [[ -r "/proc/$B09_ORCHESTRATOR_PID/stat" ]] || return 1
  observed_start_ticks="$(awk '{print $22}' \
    "/proc/$B09_ORCHESTRATOR_PID/stat" 2>/dev/null || true)"
  [[ "$observed_start_ticks" == "$B09_ORCHESTRATOR_START_TICKS" ]]
}

write_state() {
  local state="$1"
  local reason="$2"
  local now_epoch
  local temporary
  now_epoch="$(date +%s)"
  temporary="${B09_SHARD_STATE_FILE}.tmp.$$"
  mkdir -p "$(dirname "$B09_SHARD_STATE_FILE")"
  {
    printf 'state=%s\n' "$state"
    printf 'reason=%s\n' "$reason"
    printf 'updated_at=%s\n' "$(date -Is)"
    printf 'updated_epoch=%s\n' "$now_epoch"
    printf 'supervisor_pid=%s\n' "$$"
    printf 'matlab_pid=%s\n' "${matlab_pid:-}"
    printf 'matlab_pgid=%s\n' "${matlab_pgid:-}"
    printf 'matlab_owner_file=%s\n' "${matlab_owner_file:-}"
    printf 'attempt=%s\n' "$attempt"
    printf 'workers=%s\n' "$WORKERS"
    printf 'shard_id=%s\n' "$B09_SHARD_ID"
    printf 'range_file=%s\n' "$RANGE_FILE"
    printf 'num_ranges=%s\n' "$iNumRanges"
    printf 'first_combo=%s\n' "$iFirstCombo"
    printf 'last_combo=%s\n' "$iLastCombo"
  } > "$temporary"
  mv -f -- "$temporary" "$B09_SHARD_STATE_FILE"
  current_state="$state"
}

progress_signature() {
  local results_dir="$CODE_DIR/Results/CTREND"
  local combo_count
  local latest_epoch
  if [[ ! -d "$results_dir" ]]; then
    printf '0:0\n'
    return 0
  fi
  combo_count="$(find -L "$results_dir" -maxdepth 1 -type f \
    -name 'CTREND_Combo*.mat' -printf '.\n' 2>/dev/null | awk 'END { print NR }')"
  latest_epoch="$(find -L "$results_dir" -maxdepth 1 -type f \
    \( -name 'CTREND_Combo*.mat' -o -name 'ResearchDesignRunManifest.mat' \) \
    -printf '%T@\n' 2>/dev/null | awk '
      BEGIN { latest = 0 }
      $1 > latest { latest = $1 }
      END { printf "%.9f", latest }
    ')"
  printf '%s:%s\n' "$combo_count" "${latest_epoch:-0}"
}

write_heartbeat() {
  local pool_state="$1"
  local signature="$2"
  local last_progress_epoch="$3"
  local log_bytes="${4:-0}"
  local now_epoch
  local combo_count="${signature%%:*}"
  local latest_output_epoch="${signature#*:}"
  local temporary="${B09_SHARD_HEARTBEAT_FILE}.tmp.$$"
  now_epoch="$(date +%s)"
  mkdir -p "$(dirname "$B09_SHARD_HEARTBEAT_FILE")"
  {
    printf 'state=%s\n' "$current_state"
    printf 'updated_at=%s\n' "$(date -Is)"
    printf 'updated_epoch=%s\n' "$now_epoch"
    printf 'supervisor_pid=%s\n' "$$"
    printf 'matlab_pid=%s\n' "${matlab_pid:-}"
    printf 'attempt=%s\n' "$attempt"
    printf 'pool_active=%s\n' "$pool_state"
    printf 'combo_files=%s\n' "$combo_count"
    printf 'latest_output_epoch=%s\n' "$latest_output_epoch"
    printf 'matlab_log_bytes=%s\n' "$log_bytes"
    printf 'last_progress_epoch=%s\n' "$last_progress_epoch"
    printf 'seconds_since_progress=%s\n' "$((now_epoch - last_progress_epoch))"
  } > "$temporary"
  mv -f -- "$temporary" "$B09_SHARD_HEARTBEAT_FILE"
}

stop_matlab() {
  local deadline
  if [[ -z "${matlab_pgid:-}" && -n "${matlab_owner_file:-}" &&
        -f "$matlab_owner_file" ]]; then
    matlab_pgid="$(awk -F= '$1=="pgid"{print $2;exit}' \
      "$matlab_owner_file")"
  fi
  [[ "$matlab_pgid" =~ ^[1-9][0-9]*$ ]] || return 0
  process_group_exists "$matlab_pgid" || return 0
  kill -TERM -- "-$matlab_pgid" 2>/dev/null || true
  deadline=$(( $(date +%s) + MATLAB_STOP_GRACE_SECONDS ))
  while process_group_exists "$matlab_pgid" &&
      (( $(date +%s) < deadline )); do
    sleep 1
  done
  if process_group_exists "$matlab_pgid"; then
    kill -KILL -- "-$matlab_pgid" 2>/dev/null || true
  fi
}

process_group_exists() {
  local expected_pgid="$1"
  ps -eo pgid= | awk -v expected="$expected_pgid" \
    '$1 == expected { found=1; exit } END { exit !found }'
}

on_signal() {
  local signal_name="$1"
  local signal_rc="$2"
  trap - INT TERM
  write_state "STOPPING" "signal_$signal_name"
  stop_matlab
  exit "$signal_rc"
}

cleanup() {
  local rc=$?
  trap - EXIT INT TERM
  stop_matlab
  if [[ -n "$current_job_storage" ]]; then
    cttrend_safe_remove_temp_dir "$current_job_storage" \
      "$B09_JOB_STORAGE_ROOT" || rc=1
  fi
  if (( rc != 0 )) && [[ "$current_state" != "FAILED" && "$current_state" != "STOPPING" ]]; then
    write_state "FAILED" "supervisor_exit_$rc"
  fi
  exit "$rc"
}

trap cleanup EXIT
trap 'on_signal INT 130' INT
trap 'on_signal TERM 143' TERM

export PIPELINE_SCOPE=table6
export PIPELINE_START_STEP=b09RunResearchDesigns
export PIPELINE_END_STEP=b09RunResearchDesigns
export PIPELINE_RESEARCH_RUN_ID="$RUN_ID"
export PARALLEL_WORKERS="$WORKERS"
export PIPELINE_LOG_DIR="$SHARD_LOG_DIR"
export PIPELINE_LOG_FILE="$session_log"
export PIPELINE_STDOUT_REDIRECTED=1
export PIPELINE_CODE_DIR="$CODE_DIR"
export B09_RANGE_FILE="$RANGE_FILE"
export B09_DRIVER_DIR="$runtime_dir"

{
  echo "persistent_shard=1"
  echo "shard_id=$B09_SHARD_ID"
  echo "num_ranges=$iNumRanges"
  echo "first_combo=$iFirstCombo"
  echo "last_combo=$iLastCombo"
  echo "workers=$WORKERS"
  echo "research_run_id=$RUN_ID"
  echo "code_dir=$CODE_DIR"
  echo "pool_start_timeout_seconds=$POOL_START_TIMEOUT_SECONDS"
  echo "no_progress_timeout_seconds=$NO_PROGRESS_TIMEOUT_SECONDS"
  echo "started_at=$(date -Is)"
} >> "$session_log"

attempt=1
while true; do
  current_job_storage="$B09_JOB_STORAGE_ROOT/${RUN_ID}_shard${B09_SHARD_ID}_pid$$_attempt${attempt}"
  export MATLAB_PREFDIR="$current_job_storage/matlab_pref"
  export PIPELINE_JOB_STORAGE="$current_job_storage"
  attempt_log="$SHARD_LOG_DIR/matlab_attempt_$attempt.log"
  if [[ -e "$current_job_storage" || -L "$current_job_storage" ]]; then
    cttrend_safe_remove_temp_dir "$current_job_storage" \
      "$B09_JOB_STORAGE_ROOT"
  fi
  cttrend_prepare_temp_dir "$current_job_storage" \
    "$B09_JOB_STORAGE_ROOT" "b09_shard_${B09_SHARD_ID}_attempt_$attempt"
  mkdir -p "$MATLAB_PREFDIR"
  ln -sfn "$(basename "$attempt_log")" "$SHARD_LOG_DIR/latest_matlab_attempt.log"
  printf 'matlab_attempt=%d/%d started_at=%s job_storage=%s\n' \
    "$attempt" "$POOL_START_RETRIES" "$(date -Is)" "$current_job_storage" \
    >> "$session_log"
  write_state "STARTING" "matlab_attempt_$attempt"

  matlab_owner_file="$SHARD_LOG_DIR/matlab_attempt_${attempt}.owner.env"
  matlab_owner_token="$(</proc/sys/kernel/random/uuid)"
  rm -f -- "$matlab_owner_file"
  setsid "$RUNNER_DIR/run_owned_process.sh" \
    "$matlab_owner_file" "$matlab_owner_token" "$CODE_DIR" \
    "b09_shard_${B09_SHARD_ID}_attempt_${attempt}" \
    "$MATLAB_BIN" -licmode onlinelicensing -nodisplay -nosplash \
    -batch "addpath(getenv('B09_DRIVER_DIR')); cd(getenv('PIPELINE_CODE_DIR')); cttrend_b09_persistent_driver" \
    > "$attempt_log" 2>&1 &
  matlab_pid=$!
  matlab_pgid=$matlab_pid
  write_state "STARTING" "waiting_for_pool"

  pool_active=0
  timeout_reason=""
  attempt_started_epoch="$(date +%s)"
  last_progress_epoch="$attempt_started_epoch"
  last_signature="$(progress_signature)"
  last_log_bytes="$(stat -c %s "$attempt_log" 2>/dev/null || printf '0')"
  write_heartbeat "$pool_active" "$last_signature" "$last_progress_epoch" \
    "$last_log_bytes"

  while kill -0 "$matlab_pid" 2>/dev/null; do
    now_epoch="$(date +%s)"
    if ! orchestrator_lease_is_live; then
      timeout_reason="orchestrator_lost"
      write_state "FAILED" "$timeout_reason"
      stop_matlab
      break
    fi
    if (( pool_active == 0 )) && grep -Fq \
        "parallel_workers_active=$WORKERS" "$attempt_log" 2>/dev/null; then
      pool_active=1
      last_progress_epoch="$now_epoch"
      write_state "RUNNING" "pool_active"
    fi

    current_signature="$(progress_signature)"
    current_log_bytes="$(stat -c %s "$attempt_log" 2>/dev/null || printf '0')"
    if [[ "$current_signature" != "$last_signature" ]]; then
      last_signature="$current_signature"
      last_progress_epoch="$now_epoch"
    fi
    last_log_bytes="$current_log_bytes"
    write_heartbeat "$pool_active" "$last_signature" "$last_progress_epoch" \
      "$last_log_bytes"

    if (( pool_active == 0 && now_epoch - attempt_started_epoch > POOL_START_TIMEOUT_SECONDS )); then
      timeout_reason="pool_start_timeout"
      write_state "FAILED" "$timeout_reason"
      stop_matlab
      break
    fi
    if (( pool_active == 1 && now_epoch - last_progress_epoch > NO_PROGRESS_TIMEOUT_SECONDS )); then
      timeout_reason="no_progress_timeout"
      write_state "FAILED" "$timeout_reason"
      stop_matlab
      break
    fi
    sleep "$HEARTBEAT_INTERVAL_SECONDS"
  done

  if [[ -n "$timeout_reason" ]]; then
    rc=124
  else
    set +e
    wait "$matlab_pid"
    rc=$?
    set -e
  fi
  # MATLAB can return rc=0 before the Processes pool has completely drained.
  # Give a successful client the same bounded natural-exit grace used by the
  # top-level phase runner.  Only a group that survives that grace is an
  # orphan condition; an immediately observed, normally shutting-down worker
  # must not turn fully written shard output into a false rc=125 failure.
  if (( rc == 0 )) && process_group_exists "$matlab_pgid"; then
    if ! cttrend_wait_for_process_group_exit \
        "$matlab_pgid" "$MATLAB_STOP_GRACE_SECONDS"; then
      timeout_reason="${timeout_reason:-residual_matlab_process_group}"
      stop_matlab
      rc=125
    fi
  elif process_group_exists "$matlab_pgid"; then
    timeout_reason="${timeout_reason:-residual_matlab_process_group}"
    stop_matlab
    rc=125
  fi
  matlab_pid=""
  matlab_pgid=""
  cttrend_safe_remove_temp_dir "$current_job_storage" \
    "$B09_JOB_STORAGE_ROOT"
  current_job_storage=""
  printf 'matlab_attempt=%d ended_at=%s rc=%d pool_active=%d timeout_reason=%s\n' \
    "$attempt" "$(date -Is)" "$rc" "$pool_active" "$timeout_reason" \
    >> "$session_log"

  if (( rc == 0 )); then
    [[ "$(sha256sum "$CODE_DIR/DesignChoices.mat" | awk '{print $1}')" == \
       "$EXPECTED_DESIGN_CHOICES_SHA256" ]] || {
      write_state "FAILED" "design_choices_changed"
      exit 1
    }
    write_runtime_source_inventory "$CODE_DIR" \
      > "$SHARD_ROOT/runtime_matlab_sources_after.sha256"
    cmp -s "$SHARD_ROOT/package_matlab_sources.sha256" \
      "$SHARD_ROOT/runtime_matlab_sources_after.sha256" || {
      write_state "FAILED" "runtime_source_changed"
      echo "shard executable source changed during MATLAB execution" >&2
      exit 1
    }
    # FINALIZING is advisory.  Only the atomic completion record below is a
    # commit point; COMPLETE is published after that record exists.
    write_state "FINALIZING" "publishing_completion_record"
    write_heartbeat 1 "$(progress_signature)" "$(date +%s)" \
      "$(stat -c %s "$attempt_log" 2>/dev/null || printf '0')"
    completion_temporary="${B09_SHARD_COMPLETION_FILE}.tmp.$$"
    {
      echo "format=cttrend-shard-complete-v1"
      echo "complete=1"
      echo "shard_id=$B09_SHARD_ID"
      echo "supervisor_pid=$$"
      echo "attempts=$attempt"
      echo "combo_files=$(progress_signature | cut -d: -f1)"
      echo "research_run_id=$RUN_ID"
      echo "source_inventory_sha256=$(sha256sum \
        "$SHARD_ROOT/runtime_matlab_sources_after.sha256" | awk '{print $1}')"
      echo "design_choices_sha256=$EXPECTED_DESIGN_CHOICES_SHA256"
      echo "completed_at=$(date -Is)"
    } > "$completion_temporary"
    mv -f -- "$completion_temporary" "$B09_SHARD_COMPLETION_FILE"
    write_state "COMPLETE" "completion_record_published"
    write_heartbeat 1 "$(progress_signature)" "$(date +%s)" \
      "$(stat -c %s "$attempt_log" 2>/dev/null || printf '0')"
    echo "shard_complete=1 ranges=$iNumRanges attempts=$attempt at $(date -Is)"
    exit 0
  fi

  if [[ "$timeout_reason" == "orchestrator_lost" ]]; then
    printf 'shard_failed=1 attempt=%d rc=%d reason=%s at=%s\n' \
      "$attempt" "$rc" "$timeout_reason" "$(date -Is)" >&2
    exit "$rc"
  fi

  retryable_startup=0
  if (( pool_active == 0 )) && {
      [[ "$timeout_reason" == "pool_start_timeout" ]] || grep -Eq \
        'Parallel pool failed to start|Failed to initialize (the )?interactive session|A timeout occurred setting up the parallel pool communication|Could not start requested parallel pool|Unable to load ApplicationService for command.*client-v1|Unable to communicate with required MathWorks services' \
        "$attempt_log";
    }; then
    retryable_startup=1
  fi

  if (( retryable_startup == 0 )); then
    write_state "FAILED" "matlab_nonretryable_rc_$rc"
    printf 'shard_failed=1 attempt=%d rc=%d nonretryable=1 at=%s\n' \
      "$attempt" "$rc" "$(date -Is)" >&2
    exit "$rc"
  fi
  if (( attempt >= POOL_START_RETRIES )); then
    write_state "FAILED" "pool_start_attempts_exhausted"
    printf 'shard_failed=1 attempts_exhausted=%d rc=%d at=%s\n' \
      "$attempt" "$rc" "$(date -Is)" >&2
    exit "$rc"
  fi

  printf 'retryable_matlab_pool_start_failure attempt=%d rc=%d retry_in_seconds=%d at=%s\n' \
    "$attempt" "$rc" "$POOL_RETRY_DELAY_SECONDS" "$(date -Is)" \
    | tee -a "$session_log"
  sleep "$POOL_RETRY_DELAY_SECONDS"
  attempt=$((attempt + 1))
done
