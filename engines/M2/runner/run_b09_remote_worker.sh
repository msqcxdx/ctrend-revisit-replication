#!/usr/bin/env bash
# CTREND_REVISIT_FILE_PURPOSE: Execute only the authorized remote b09 range under sealed code, data, and completion contracts.
set -euo pipefail

if [[ "$#" -ne 6 ]]; then
  echo "usage: $0 REMOTE_ROOT RUN_ID WORKERS MATLAB_BIN PACKAGE_SHA DESIGN_SHA" >&2
  exit 2
fi

REMOTE_ROOT="$1"
RUN_ID="$2"
WORKERS="$3"
MATLAB_BIN="$4"
EXPECTED_PACKAGE_SHA256="$5"
EXPECTED_DESIGN_CHOICES_SHA256="$6"
INPUT_DIR="$REMOTE_ROOT/input"
STATE_DIR="$REMOTE_ROOT/state"
RESULTS_DIR="$REMOTE_ROOT/results"
WORK_DIR="$REMOTE_ROOT/work"
PACKAGE="$INPUT_DIR/cttrend_old_v2_pipeline.tar.gz"
DESIGN_FILE="$INPUT_DIR/DesignChoices.mat"
DATA_DIR="$INPUT_DIR/DATA"
RUNNER_DIR="$INPUT_DIR/runner"
CODE_DIR="$WORK_DIR/cttrend_old_v2_pipeline"
JOB_STORAGE_ROOT="$REMOTE_ROOT/job_storage"

[[ "$REMOTE_ROOT" == /* && "$REMOTE_ROOT" =~ ^[A-Za-z0-9_./-]+$ ]] || {
  echo "unsafe remote b09 root" >&2
  exit 2
}
[[ "$RUN_ID" =~ ^[0-9a-fA-F-]{36}$ &&
   "$WORKERS" =~ ^[1-9][0-9]*$ ]] || {
  echo "invalid remote b09 identity or worker count" >&2
  exit 2
}
[[ -x "$MATLAB_BIN" && -f "$PACKAGE" && -f "$DESIGN_FILE" &&
   -d "$DATA_DIR" && -x "$RUNNER_DIR/run_b09_shard.sh" ]] || {
  echo "remote b09 inputs are incomplete" >&2
  exit 2
}
[[ "$(sha256sum "$PACKAGE" | awk '{print $1}')" == \
   "$EXPECTED_PACKAGE_SHA256" &&
   "$(sha256sum "$DESIGN_FILE" | awk '{print $1}')" == \
   "$EXPECTED_DESIGN_CHOICES_SHA256" ]] || {
  echo "remote b09 input hash mismatch" >&2
  exit 2
}
mkdir -p "$STATE_DIR" "$RESULTS_DIR/CTREND" "$RESULTS_DIR/Tables" \
  "$RESULTS_DIR/Figures" "$WORK_DIR" "$JOB_STORAGE_ROOT"
(
  cd "$DATA_DIR"
  sha256sum -c "$INPUT_DIR/data_inputs.sha256"
) > "$STATE_DIR/data_inputs_before_verification.log"
cp -- "$INPUT_DIR/data_inputs.sha256" "$STATE_DIR/data_inputs.sha256"
(
  cd "$RUNNER_DIR"
  sha256sum -c "$INPUT_DIR/remote_runner_inputs.sha256"
) > "$STATE_DIR/remote_runner_before_verification.log"
cp -- "$INPUT_DIR/remote_runner_inputs.sha256" \
  "$STATE_DIR/remote_runner_inputs.sha256"

printf '%s\n' "$$" > "$STATE_DIR/remote_wrapper.pid"
tar -xzf "$PACKAGE" -C "$WORK_DIR"
[[ -d "$CODE_DIR" ]] || {
  echo "remote package root is missing" >&2
  exit 2
}

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
          find "$source_subdir" -type f -name '*.m' \
            ! -name 'tmp_*' -printf '%p\n'
        fi
      done
    } | LC_ALL=C sort | while IFS= read -r relative; do
      digest="$(sha256sum "$relative")"
      printf '%s  %s\n' "${digest%% *}" "$relative"
    done
  )
}

write_runtime_source_inventory "$CODE_DIR" \
  > "$STATE_DIR/package_matlab_sources.sha256"
cmp -s "$INPUT_DIR/canonical_matlab_sources.sha256" \
  "$STATE_DIR/package_matlab_sources.sha256" || {
  echo "remote package source differs from frozen canonical source" >&2
  exit 2
}
cp -- "$DESIGN_FILE" "$CODE_DIR/DesignChoices.mat"
[[ "$(sha256sum "$CODE_DIR/DesignChoices.mat" | awk '{print $1}')" == \
   "$EXPECTED_DESIGN_CHOICES_SHA256" ]] || {
  echo "remote DesignChoices copy failed verification" >&2
  exit 2
}
ln -s "$DATA_DIR" "$CODE_DIR/DATA"
ln -s "$RESULTS_DIR" "$CODE_DIR/Results"
printf '1537 3072\n' > "$STATE_DIR/ranges.txt"

export B09_JOB_STORAGE_ROOT="$JOB_STORAGE_ROOT"
export B09_SHARD_ID="2.1"
export B09_SHARD_STATE_FILE="$STATE_DIR/state.env"
export B09_SHARD_HEARTBEAT_FILE="$STATE_DIR/heartbeat.env"
export B09_SHARD_COMPLETION_FILE="$STATE_DIR/completion.env"
export EXPECTED_DESIGN_CHOICES_SHA256
export EXPECTED_PACKAGE_SHA256
EXPECTED_DATA_INPUTS_SHA256="$(sha256sum \
  "$INPUT_DIR/data_inputs.sha256" | awk '{print $1}')"
export EXPECTED_DATA_INPUTS_SHA256

"$RUNNER_DIR/run_b09_shard.sh" \
  "$CODE_DIR" "$STATE_DIR/ranges.txt" "$RUN_ID" "$WORKERS" \
  "$MATLAB_BIN" "$STATE_DIR/logs"

(
  cd "$DATA_DIR"
  find -L . -maxdepth 1 -type f -printf '%P\0' |
    LC_ALL=C sort -z | xargs -0 -r sha256sum
) > "$STATE_DIR/data_inputs_after.sha256"
cmp -s "$STATE_DIR/data_inputs.sha256" \
  "$STATE_DIR/data_inputs_after.sha256" || {
  echo "remote DATA changed during b09 execution" >&2
  exit 1
}
(
  cd "$RUNNER_DIR"
  sha256sum run_b09_shard.sh run_owned_process.sh \
    run_b09_remote_worker.sh stop_b09_remote_worker.sh
) > "$STATE_DIR/remote_runner_after.sha256"
cmp -s "$STATE_DIR/remote_runner_inputs.sha256" \
  "$STATE_DIR/remote_runner_after.sha256" || {
  echo "remote runner source changed during b09 execution" >&2
  exit 1
}

[[ -f "$STATE_DIR/completion.env" &&
   "$(awk -F= '$1=="complete"{print $2;exit}' \
     "$STATE_DIR/completion.env")" == "1" ]] || {
  echo "remote b09 shard lacks a sealed completion record" >&2
  exit 1
}
