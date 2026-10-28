#!/usr/bin/env bash
# CTREND_REVISIT_FILE_PURPOSE: Run the complete data, publication, derivation, annotation, topology, and optional MATLAB test suite.
# Authoritative local/CI order: fast offline Python/shell contracts run first;
# MATLAB unit tests run when MATLAB_BIN (or matlab on PATH) is available.
# Every invoked command is mandatory and set -e prevents a false suite PASS.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
command -v rg >/dev/null 2>&1 || {
  echo 'PACKAGE_TEST_ERROR: ripgrep (rg) is required; refusing false-pass guards' >&2
  exit 2
}
# Data/acquisition, package structure, prose, routing, and derivation gates.
python3 "$ROOT/tests/data_checks/test_design_registry.py"
"${PYTHON_BIN:-python3}" "$ROOT/tests/run_acquisition_tests.py"
"${PYTHON_BIN:-python3}" "$ROOT/tests/integration/test_reproduce_everything.py"
python3 "$ROOT/tests/data_checks/test_jfqa_structure.py"
python3 "$ROOT/tests/integration/test_publication_readiness.py"
python3 "$ROOT/tests/integration/test_research_editorial_contract.py"
"$ROOT/tests/integration/test_materialization.sh"
"$ROOT/tests/integration/test_entrypoint_paths.sh"
"$ROOT/tests/integration/test_b19_postprocessing.sh"
"$ROOT/tests/integration/test_portable_run_inventory.sh"
"$ROOT/tests/integration/test_engine_guards.sh"
"$ROOT/tests/integration/test_b09_terminal_publication.sh"
"$ROOT/tests/integration/test_m2_derivation_scope.sh"
"$ROOT/tests/integration/test_m1_inventory_contract.sh"
python3 "$ROOT/tests/integration/test_method_boundary_contract.py"
python3 "$ROOT/tests/integration/test_annotated_source_equivalence.py"
python3 "$ROOT/tests/integration/test_annotation_opcode_coverage.py"
python3 "$ROOT/tests/integration/test_annotation_readability.py"
python3 "$ROOT/tests/integration/test_pmd_public_contract.py"
python3 "$ROOT/tests/integration/test_p0_m2_volume_policy.py"
python3 "$ROOT/tests/integration/test_m2_consumer_matrix.py"
"$ROOT/tests/integration/test_runtime_packages.sh"
# Numerical helper tests are mandatory whenever a compatible MATLAB is available.
if [[ -n "${MATLAB_BIN:-}" || -n "$(command -v matlab 2>/dev/null || true)" ]]; then
  "$ROOT/scripts/run_matlab_unit_tests.sh"
else
  echo 'MATLAB_TESTS_SKIPPED reason=MATLAB_BIN_not_available'
fi
echo "PACKAGE_TEST_SUITE_OK raw_inputs_verified=1"
