#!/usr/bin/env bash
# CTREND_REVISIT_FILE_PURPOSE: Smoke-test b09 range partitioning, payload identity, sidecars, merge behavior, and failure handling.
set -euo pipefail

RUNNER_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
grep -F 'Unexpected error during communication with services required to run MATLAB' \
  "$RUNNER_DIR/run_b09_shard.sh" >/dev/null
grep -F 'error 5006' "$RUNNER_DIR/run_b09_shard.sh" >/dev/null
grep -F 'pool_start_retries=$POOL_START_RETRIES' \
  "$RUNNER_DIR/launch_b09_shards.sh" >/dev/null
grep -F 'pool_retry_delay_seconds=$POOL_RETRY_DELAY_SECONDS' \
  "$RUNNER_DIR/launch_b09_shards.sh" >/dev/null
MATLAB_BIN="${MATLAB_BIN:-$(command -v matlab 2>/dev/null || true)}"
ROOT="$(mktemp -d /tmp/ctrend_old_v2_b09_smoke_XXXXXX)"
CODE_DIR="$ROOT/code"
SHARD_ROOT="$ROOT/shard"
LOG_DIR="$SHARD_ROOT/logs"
RESULTS_DIR="$ROOT/results"
JOB_ROOT="$ROOT/job_storage"
RANGE_FILE="$SHARD_ROOT/ranges.txt"

cleanup() {
  local rc=$?
  trap - EXIT INT TERM
  if [[ "${KEEP_SMOKE_ROOT:-0}" == 1 && "$rc" -ne 0 ]]; then
    printf 'OLD_V2_B09_SMOKE_ROOT=%s\n' "$ROOT" >&2
  else
    rm -rf -- "$ROOT"
  fi
  exit "$rc"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

[[ -x "$MATLAB_BIN" ]]
mkdir -p "$CODE_DIR/Utils" "$CODE_DIR/LatexTables" "$CODE_DIR/tests" \
  "$RESULTS_DIR/CTREND" "$RESULTS_DIR/Tables" "$RESULTS_DIR/Figures" \
  "$LOG_DIR" "$JOB_ROOT"
cp -- "$RUNNER_DIR/../base/run_safety.sh" "$CODE_DIR/"
cp -- "$RUNNER_DIR/tests/fixtures/b09RunResearchDesigns.m" "$CODE_DIR/"
ln -s "$RESULTS_DIR" "$CODE_DIR/Results"
printf 'old-v2-smoke-design\n' > "$CODE_DIR/DesignChoices.mat"
printf '1 1\n' > "$RANGE_FILE"

(
  cd "$CODE_DIR"
  {
    find . -maxdepth 1 -type f \
      \( -name '*.m' -o -name '*.sh' \) ! -name 'tmp_*' -printf '%P\n'
    find Utils LatexTables tests -type f -name '*.m' \
      ! -name 'tmp_*' -printf '%p\n'
  } | LC_ALL=C sort | while IFS= read -r relative; do
    digest="$(sha256sum "$relative")"
    printf '%s  %s\n' "${digest%% *}" "$relative"
  done
) > "$SHARD_ROOT/package_matlab_sources.sha256"

design_sha="$(sha256sum "$CODE_DIR/DesignChoices.mat" | awk '{print $1}')"
identity_sha="$(printf 'old-v2-smoke\n' | sha256sum | awk '{print $1}')"
run_id="$(</proc/sys/kernel/random/uuid)"

HEARTBEAT_INTERVAL_SECONDS=1 \
POOL_START_TIMEOUT_SECONDS=600 NO_PROGRESS_TIMEOUT_SECONDS=600 \
MATLAB_STOP_GRACE_SECONDS=30 MATLAB_GROUP_EXIT_GRACE_SECONDS=30 \
B09_JOB_STORAGE_ROOT="$JOB_ROOT" \
B09_SHARD_ID=smoke \
B09_SHARD_STATE_FILE="$SHARD_ROOT/state.env" \
B09_SHARD_HEARTBEAT_FILE="$SHARD_ROOT/heartbeat.env" \
B09_SHARD_COMPLETION_FILE="$SHARD_ROOT/completion.env" \
EXPECTED_DESIGN_CHOICES_SHA256="$design_sha" \
EXPECTED_PACKAGE_SHA256="$identity_sha" \
EXPECTED_DATA_INPUTS_SHA256="$identity_sha" \
  "$RUNNER_DIR/run_b09_shard.sh" \
  "$CODE_DIR" "$RANGE_FILE" "$run_id" 2 "$MATLAB_BIN" "$LOG_DIR"

[[ "$(awk -F= '$1=="state"{print $2;exit}' "$SHARD_ROOT/state.env")" == COMPLETE ]]
[[ "$(awk -F= '$1=="complete"{print $2;exit}' "$SHARD_ROOT/completion.env")" == 1 ]]
[[ -s "$RESULTS_DIR/CTREND/CTREND_Combo1.mat" ]]
(
  cd "$RESULTS_DIR/CTREND"
  sha256sum -c CTREND_Combo1.mat.sha256 >/dev/null
  sha256sum -c ResearchDesignRunManifest.env.sha256 >/dev/null
)
grep -Fq 'parallel_workers_active=2' "$LOG_DIR/matlab_attempt_1.log"
printf 'OLD_V2_B09_RUNNER_SMOKE_TEST_OK\n'
