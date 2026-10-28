#!/usr/bin/env bash
# CTREND_REVISIT_FILE_PURPOSE: Run code, data, MATLAB, topology, and provenance gates before any production run is admitted.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

fail() { echo "PREFLIGHT_ERROR: $*" >&2; exit 2; }
SKIP_MATLAB=0
data_preflight() {
  "${PYTHON_BIN:-python3}" "$ROOT/scripts/data_bundle.py" preflight --root "$ROOT"
}
if [[ "${1:-}" == "--data-only" ]]; then
  data_preflight
  exit 0
fi
if [[ "${1:-}" == "--no-matlab" ]]; then
  # Explicitly skip MATLAB here. The release builder separately verifies its
  # staged bytes and source-tree MATLAB test; this flag alone proves neither.
  SKIP_MATLAB=1
  shift
fi
[[ $# -eq 0 ]] || fail 'usage: preflight.sh [--data-only|--no-matlab]'
LOG_ROOT="${PREFLIGHT_LOG_ROOT:-$ROOT/outputs/logs/preflight}"
mkdir -p "$LOG_ROOT"
"${PYTHON_BIN:-python3}" "$ROOT/tests/run_acquisition_tests.py" \
  2>&1 | tee "$LOG_ROOT/acquisition_regression.log"
"${PYTHON_BIN:-python3}" "$ROOT/tests/integration/test_reproduce_everything.py" \
  2>&1 | tee "$LOG_ROOT/reproduce_everything.log"
for command_name in bash awk env find flock python3 readlink realpath rg rsync setsid \
    sha256sum sort tar unzip zip; do
  command -v "$command_name" >/dev/null 2>&1 || fail "missing command: $command_name"
done

while IFS= read -r file; do bash -n "$file"; done < <(
  find "$ROOT" -type f -name '*.sh' \
    ! -path "$ROOT/runtime/*" ! -path "$ROOT/outputs/*" | LC_ALL=C sort
)
python3 "$ROOT/tests/data_checks/test_design_registry.py" \
  | tee "$LOG_ROOT/design_registry.log"
python3 "$ROOT/tests/data_checks/test_jfqa_structure.py" \
  | tee "$LOG_ROOT/jfqa_structure.log"
python3 "$ROOT/tests/integration/test_publication_readiness.py" \
  | tee "$LOG_ROOT/publication_readiness.log"
python3 "$ROOT/tests/integration/test_research_editorial_contract.py" \
  | tee "$LOG_ROOT/research_editorial_contract.log"
"$ROOT/tests/integration/test_materialization.sh" \
  | tee "$LOG_ROOT/materialization.log"
"$ROOT/tests/integration/test_entrypoint_paths.sh" \
  | tee "$LOG_ROOT/entrypoint_paths.log"
"$ROOT/tests/integration/test_cpu_capacity_detection.sh" \
  | tee "$LOG_ROOT/cpu_capacity_detection.log"
"$ROOT/tests/integration/test_portable_run_inventory.sh" \
  | tee "$LOG_ROOT/portable_run_inventory.log"
"$ROOT/tests/integration/test_engine_guards.sh" \
  | tee "$LOG_ROOT/engine_guards.log"
"$ROOT/tests/integration/test_m2_derivation_scope.sh" \
  | tee "$LOG_ROOT/m2_derivation_scope.log"
"$ROOT/tests/integration/test_m1_inventory_contract.sh" \
  | tee "$LOG_ROOT/m1_inventory_contract.log"
python3 "$ROOT/tests/integration/test_method_boundary_contract.py" \
  | tee "$LOG_ROOT/method_boundary_contract.log"
python3 "$ROOT/tests/integration/test_annotated_source_equivalence.py" \
  | tee "$LOG_ROOT/annotated_source_equivalence.log"
python3 "$ROOT/tests/integration/test_annotation_opcode_coverage.py" \
  | tee "$LOG_ROOT/annotation_opcode_coverage.log"
python3 "$ROOT/tests/integration/test_annotation_readability.py" \
  | tee "$LOG_ROOT/annotation_readability.log"
python3 "$ROOT/tests/integration/test_pmd_public_contract.py"
python3 "$ROOT/tests/integration/test_m2_consumer_matrix.py" \
  | tee "$LOG_ROOT/m2_consumer_matrix.log"

for method in M0 M1 M2; do
  test -f "$ROOT/engines/$method/base/b01ReadData.m"
  test -f "$ROOT/engines/$method/base/b09RunResearchDesigns.m"
  test -f "$ROOT/engines/$method/overlays/exclusion/b01ReadData.m"
  test -f "$ROOT/engines/$method/overlays/exclusion/Utils/fApplyConfiguredGlobalAssetExclusion.m"
done
grep -F 'CTREND_RAW_ADJUSTMENT_MODE=none' "$ROOT/scripts/run_experiment.sh" >/dev/null
if rg -n '/home/|/Users/|[A-Za-z]:\\Users\\|/data[0-9]+/|/mnt/|/srv/' \
    "$ROOT" --glob '*.sh' --glob '*.m' --glob '*.py' --glob '*.md' \
    --glob '*.txt' --glob '*.csv' --glob '*.json' --glob '*.cff' \
    --glob '*.bat' --glob '!**/runtime/**' --glob '!**/outputs/**' \
    --glob '!**/AUDIT_RUNS.json' | \
    grep -v -E '/scripts/preflight.sh:|/release/make_release.sh:'; then
  fail 'public package text contains a development-host path or address'
fi

data_preflight
# Runtime package initialization intentionally requires the installed vendor
# inputs. Keep it in production preflight, after the explicit raw-input gate;
# the clean-clone code test reports this one test as skipped until installation.
"$ROOT/tests/integration/test_runtime_packages.sh" \
  | tee "$LOG_ROOT/runtime_packages.log"

for required_file in README.md RUNBOOK.md STUDY_OVERVIEW.md REPRODUCTION_GUIDE_CN.md reproduce_everything.sh \
    ORIGINAL_DATAVERSE_CODE_COMPARISON.md CITATION.cff LICENSE NOTICE \
    run_all.m run_all.bat \
    config/project_config.m config/output_registry.csv \
    environment/environment_check.m docs/METHOD_BOUNDARIES.md \
    docs/AUDIT_AND_ANNOTATIONS.md \
    scripts/write_portable_run_inventories.sh \
    tests/result_checks/verify_run_provenance.sh \
    release/make_release.sh; do
  [[ -s "$ROOT/$required_file" ]] || fail "JFQA package member is missing: $required_file"
done

if [[ -s "$ROOT/PACKAGE_MANIFEST.sha256" ]]; then
  (cd "$ROOT" && sha256sum -c PACKAGE_MANIFEST.sha256 >/dev/null) \
    > "$LOG_ROOT/package_manifest.log" || fail 'PACKAGE_MANIFEST.sha256 mismatch'
fi

MATLAB_BIN="${MATLAB_BIN:-$(command -v matlab 2>/dev/null || true)}"
if [[ "$SKIP_MATLAB" -eq 1 ]]; then
  echo 'PREFLIGHT_MATLAB_SKIPPED reason=explicit_no_matlab_flag'
elif [[ -n "$MATLAB_BIN" ]]; then
  [[ -x "$MATLAB_BIN" ]] || fail "MATLAB_BIN is not executable: $MATLAB_BIN"
  MATLAB_TEST_PREF_ROOT="$LOG_ROOT" MATLAB_BIN="$MATLAB_BIN" \
    "$ROOT/scripts/run_matlab_unit_tests.sh" \
    > "$LOG_ROOT/matlab_environment_and_unit.log" 2>&1 || {
      tail -100 "$LOG_ROOT/matlab_environment_and_unit.log" >&2 || true
      fail 'MATLAB environment/global-exclusion checks failed'
    }
else
  echo 'PREFLIGHT_WARNING MATLAB unavailable: only static/package checks ran' >&2
fi
echo 'PREFLIGHT_OK experiments=18 raw_adjustment_mode=none b09=8x15 d2_assets=28'
