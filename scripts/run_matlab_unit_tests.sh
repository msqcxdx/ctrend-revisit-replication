#!/usr/bin/env bash
# CTREND_REVISIT_FILE_PURPOSE: Execute deterministic MATLAB scientific and engineering gates in isolated job-storage directories.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MATLAB_BIN="${MATLAB_BIN:-$(command -v matlab 2>/dev/null || true)}"
[[ -x "$MATLAB_BIN" ]] || {
  echo 'set MATLAB_BIN to an executable MATLAB R2023b binary' >&2; exit 2;
}
PREF_PARENT="${MATLAB_TEST_PREF_ROOT:-${TMPDIR:-/tmp}}"
mkdir -p "$PREF_PARENT"
PREF="$(mktemp -d "$PREF_PARENT/ctrend_3x3_matlab_pref_XXXXXX")"
cleanup() { rm -rf -- "$PREF"; }
trap cleanup EXIT
MATLAB_PREFDIR="$PREF" "$MATLAB_BIN" -licmode onlinelicensing \
  -nodisplay -nosplash -batch \
  "addpath(fullfile('$ROOT','environment')); environment_check; addpath(fullfile('$ROOT','tests','unit')); test_p0_m2_volume_policy('$ROOT'); test_global_exclusion('$ROOT'); test_unified_missing_and_exit_calendar('$ROOT'); test_same_leg_reinvestment('$ROOT'); setenv('CTREND_RAW_ADJUSTMENT_MODE','none'); setenv('CTREND_CORE_EXPERIMENT_ID','M1_D0_package_preflight'); setenv('CTREND_EVENT_REGISTRY_FILE',''); addpath(fullfile('$ROOT','engines','M1','base','tests')); cd(fullfile('$ROOT','engines','M1','base')); run_corrected_unit_tests; exit(0)"

# The M0 acceleration is an adapter around the published serial formulas.
# Prove 59 saved fields bit-for-bit equal with a real local pool before any
# production run may use the 127-worker b02 profile.
OLD_B02_JOB="$PREF/old_b02_job_storage"
mkdir -p "$OLD_B02_JOB"
MATLAB_PREFDIR="$PREF" "$MATLAB_BIN" -licmode onlinelicensing \
  -nodisplay -nosplash -batch \
  "code=fullfile('$ROOT','engines','M0','base'); tests=fullfile('$ROOT','engines','M0','runner','tests'); addpath(fullfile(code,'Utils')); addpath(tests); c=parcluster('local'); c.JobStorageLocation='$OLD_B02_JOB'; c.NumWorkers=4; p=parpool(c,4); test_b02_parallel_equivalence(code); delete(p); exit(0)"

# Exercise the sealed M0 shard wrapper, two pool workers, combo output,
# per-file sidecar, research-design manifest, heartbeat and completion state.
MATLAB_BIN="$MATLAB_BIN" \
  "$ROOT/engines/M0/runner/tests/test_b09_runner_smoke.sh"

# M2 has a separate deterministic gate because its b02 intentionally adds an
# untransformed causal return layer and therefore cannot be bitwise-equal to M0.
M2_PREF="$PREF/m2"
mkdir -p "$M2_PREF"
MATLAB_PREFDIR="$M2_PREF" "$MATLAB_BIN" -licmode onlinelicensing \
  -nodisplay -nosplash -batch \
  "code=fullfile('$ROOT','engines','M2','base'); tests=fullfile('$ROOT','engines','M2','runner','tests'); analysisTests=fullfile('$ROOT','analysis','tests'); addpath(fullfile(code,'Utils')); addpath(tests); addpath(analysisTests); cd(code); test_m2_causal_contract; test_compare_nine_methods_common_weeks; exit(0)"
MATLAB_BIN="$MATLAB_BIN" "$ROOT/p0_extension/tests/test_m1_b01_b02_checkpoint_contract.sh"
echo 'MATLAB_PACKAGE_TESTS_OK corrected=28 m1_b02_diagnostic_contract=1 unified_missing_exit=1 same_leg_reinvestment=1 m0_b02_fields=59 m0_b09_smoke=1 m2_causal_contract=1 common_week_test=1 p0_real_b01_b02=1'
