#!/usr/bin/env bash
# CTREND_REVISIT_FILE_PURPOSE: Verify shell syntax, relative-path portability, entrypoint contracts, and host-assignment isolation.
# Run syntax/plan modes from a temporary external directory to detect absolute
# paths, ambiguous runner names, misspelled environment variables, and unsafe
# shared run/job roots before MATLAB can start.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
command -v rg >/dev/null 2>&1 || {
  echo 'entrypoint path test requires ripgrep (rg)' >&2
  exit 2
}
TMP="$(mktemp -d /tmp/cttrend_3x3_entrypoint_test_XXXXXX)"
cleanup() { rm -rf -- "$TMP"; }
trap cleanup EXIT

for file in "$ROOT/run_all.sh" "$ROOT/scripts/"*.sh \
    "$ROOT/tests/"*.sh "$ROOT/tests/"*/*.sh "$ROOT/release/"*.sh \
    "$ROOT/postprocessing/"*.sh; do
  [[ ! -f "$file" ]] || bash -n "$file"
done
# Syntax is necessary but insufficient; the blocks below test routing semantics.

# The method directory, rather than a historical development label, identifies
# each internal production runner. Keep this public layout uniform across all
# three methods and reject regressions to the former ambiguous names.
for method in M0 M1 M2; do
  test -x "$ROOT/engines/$method/runner/run_production.sh"
done
test "$(rg -c 'runner/run_production\.sh' \
  "$ROOT/scripts/run_experiment.sh" | awk -F: '{sum += $NF} END {print sum+0}')" -eq 2
if find "$ROOT/engines" -path '*/runner/*' -type f -printf '%P\n' | \
    rg -i '(^|/|[-_.])(old|corrected|current|v[0-9]+|recompute)([-_.]|/|$)' | \
    rg -v '(^|/)legacy_v2_|/test_legacy_v2_|/resume_b09_legacy_'; then
  echo 'method runner path still embeds a historical development label' >&2
  exit 1
fi

# Resolve all entrypoints from a directory unrelated to the package.  This
# catches accidental dependence on the caller's current working directory.
(
  cd "$TMP"
  "$ROOT/run_all.sh" plan > plan.txt
  "$ROOT/scripts/plan_runs.sh" > plan_direct.txt
)
cmp -s "$TMP/plan.txt" "$TMP/plan_direct.txt"
grep -F 'M0_D2' "$TMP/plan.txt" >/dev/null
grep -F 'M1_D2' "$TMP/plan.txt" >/dev/null
grep -F 'M2_D2' "$TMP/plan.txt" >/dev/null

# Batch commands must reject a shared exact run/job directory before any
# preflight or MATLAB process can start.
if RUN_ROOT="$TMP/shared_run" \
    "$ROOT/run_all.sh" all > "$TMP/all_guard.log" 2>&1; then
  echo 'all unexpectedly accepted a shared RUN_ROOT' >&2
  exit 1
fi
grep -F 'RUN_ROOT' "$TMP/all_guard.log" >/dev/null
if JOB_STORAGE_ROOT="$TMP/shared_jobs" \
    "$ROOT/scripts/run_assignment.sh" main \
      "$ROOT/config/host_assignments_3x3_template.csv" \
      > "$TMP/assignment_guard.log" 2>&1; then
  echo 'assignment unexpectedly accepted a shared JOB_STORAGE_ROOT' >&2
  exit 1
fi
grep -F 'JOB_STORAGE_ROOT' "$TMP/assignment_guard.log" >/dev/null
grep -F 'production topology requires at least 128 logical CPUs' \
  "$ROOT/scripts/run_experiment.sh" >/dev/null
grep -F 'runtime_package_sha256' "$ROOT/scripts/run_experiment.sh" >/dev/null
grep -F 'export CTTREND_DATA_TREATMENT_ID="$DATA_ID"' \
  "$ROOT/scripts/run_experiment.sh" >/dev/null
grep -F 'export CTTREND_ASSET_EXCLUSION_FILE="$EXCLUSION"' \
  "$ROOT/scripts/run_experiment.sh" >/dev/null
grep -F 'export CTTREND_ASSET_EXCLUSION_SHA256=' \
  "$ROOT/scripts/run_experiment.sh" >/dev/null
if rg -n 'CTREND_(DATA_TREATMENT_ID|ASSET_EXCLUSION_(FILE|SHA256))' \
    "$ROOT/scripts/run_experiment.sh"; then
  echo 'run_experiment contains a misspelled single-T data/exclusion environment variable' >&2
  exit 1
fi
grep -F "getenv('CTTREND_DATA_TREATMENT_ID')" \
  "$ROOT/engines/M0/overlays/exclusion/Utils/fApplyConfiguredGlobalAssetExclusion.m" \
  >/dev/null
grep -F "getenv('CTTREND_ASSET_EXCLUSION_FILE')" \
  "$ROOT/engines/M0/overlays/exclusion/Utils/fApplyConfiguredGlobalAssetExclusion.m" \
  >/dev/null
grep -F "getenv('CTTREND_ASSET_EXCLUSION_SHA256')" \
  "$ROOT/engines/M0/overlays/exclusion/Utils/fApplyConfiguredGlobalAssetExclusion.m" \
  >/dev/null
grep -F "getenv('CTTREND_DATA_TREATMENT_ID')" \
  "$ROOT/engines/M1/overlays/exclusion/Utils/fApplyConfiguredGlobalAssetExclusion.m" \
  >/dev/null
grep -F "getenv('CTTREND_ASSET_EXCLUSION_FILE')" \
  "$ROOT/engines/M1/overlays/exclusion/Utils/fApplyConfiguredGlobalAssetExclusion.m" \
  >/dev/null
grep -F "getenv('CTTREND_ASSET_EXCLUSION_SHA256')" \
  "$ROOT/engines/M1/overlays/exclusion/Utils/fApplyConfiguredGlobalAssetExclusion.m" \
  >/dev/null
grep -F "getenv('CTTREND_DATA_TREATMENT_ID')" \
  "$ROOT/engines/M2/overlays/exclusion/Utils/fApplyConfiguredGlobalAssetExclusion.m" \
  >/dev/null
grep -F "getenv('CTTREND_ASSET_EXCLUSION_FILE')" \
  "$ROOT/engines/M2/overlays/exclusion/Utils/fApplyConfiguredGlobalAssetExclusion.m" \
  >/dev/null
grep -F "getenv('CTTREND_ASSET_EXCLUSION_SHA256')" \
  "$ROOT/engines/M2/overlays/exclusion/Utils/fApplyConfiguredGlobalAssetExclusion.m" \
  >/dev/null
grep -F 'launch manifest runtime package is not bound to RUN_COMPLETE' \
  "$ROOT/tests/result_checks/verify_completed_run.sh" >/dev/null
grep -F 'register_completed_run.sh' \
  "$ROOT/scripts/verify_all_registrations.sh" >/dev/null

# Every newly produced M0/M1/M2 run belongs to this nine-cell package.  Do
# not leak the frozen parent's former six-cell or method-specific 2x3/3x3
# publication names into new launch, inventory, acceptance, or registration
# artifacts.
for pair in \
  scripts/run_experiment.sh:NINE_EXPERIMENT_LAUNCH_MANIFEST.env \
  scripts/write_portable_run_inventories.sh:NINE_EXPERIMENT_DATA_INVENTORY.sha256 \
  tests/result_checks/verify_completed_run.sh:NINE_EXPERIMENT_ACCEPTANCE.env \
  scripts/register_completed_run.sh:cttrend-nine-experiment-registration-v1 \
  scripts/verify_all_registrations.sh:nine_experiment_acceptance_sha256; do
  file="${pair%%:*}"
  token="${pair#*:}"
  grep -F "$token" "$ROOT/$file" >/dev/null
done
if rg -n '(2X3|3X3|cttrend-(2x3|3x3|six-experiment))' \
    "$ROOT/scripts/run_experiment.sh" \
    "$ROOT/scripts/write_portable_run_inventories.sh" \
    "$ROOT/tests/result_checks/verify_completed_run.sh" \
    "$ROOT/scripts/register_completed_run.sh" \
    "$ROOT/scripts/verify_all_registrations.sh"; then
  echo 'active nine-cell publication code contains a legacy 2x3/3x3 name' >&2
  exit 1
fi

# The full assignment must be a one-to-one partition of all nine cells.
python3 - "$ROOT/config/host_assignments_3x3_template.csv" <<'PY'
import csv, sys
rows = list(csv.DictReader(open(sys.argv[1], encoding="utf-8")))
expected = {
    "M0_D0","M0_D1","M0_D2","M1_D0","M1_D1","M1_D2",
    "M2_D0","M2_D1","M2_D2",
}
ids = [row["experiment_id"] for row in rows]
assert len(ids) == 9 and set(ids) == expected and len(set(ids)) == 9
by_host = {}
for row in rows:
    by_host.setdefault(row["host"], []).append(
        (int(row["sequence"]), row["experiment_id"]))
assert sorted(by_host) == ["main", "worker"]
assert [x[1] for x in sorted(by_host["main"])] == [
    "M1_D0", "M1_D1", "M1_D2", "M2_D0", "M2_D1", "M2_D2"]
assert [x[1] for x in sorted(by_host["worker"])] == ["M0_D0", "M0_D1", "M0_D2"]
PY
echo 'ENTRYPOINT_PATH_TEST_OK external_cwd=1 shell_syntax=1 experiments=9 unified_runner_names=1 uniform_nine_publication_names=1 neutral_runner_paths=1 batch_path_guard=1 assignment_partition=1 host_ownership=M1_M2_main_M0_worker production_cpu_gate=128 exclusion_environment_contract=1 launch_package_binding=1 suite_registration_gate=1 fresh_raw_runs_only=1'
