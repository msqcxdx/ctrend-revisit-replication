#!/usr/bin/env bash
# CTREND_REVISIT_FILE_PURPOSE: Run the public checkout's mandatory offline source and saved-result tests.
# The controlled project's acquisition and private-annotation tests are not
# claimed here: their source/materials are outside this rights-screened export.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
command -v rg >/dev/null 2>&1 || {
  echo 'PUBLIC_TEST_ERROR ripgrep (rg) is required' >&2
  exit 2
}

while IFS= read -r path; do bash -n "$path"; done < <(
  find "$ROOT" -type f -name '*.sh' \
    ! -path "$ROOT/runtime/*" ! -path "$ROOT/outputs/*" | LC_ALL=C sort
)

if [[ -d "$ROOT/data/raw/common" ]]; then
  python3 "$ROOT/scripts/public_quickcheck.py" --installed-inputs
else
  python3 "$ROOT/scripts/public_quickcheck.py"
fi
python3 "$ROOT/tests/data_checks/test_design_registry.py"
test -s "$ROOT/engines/M1/base/DesignChoices.mat"
"$ROOT/tests/integration/test_materialization.sh"
"$ROOT/tests/integration/test_engine_guards.sh"
"$ROOT/tests/integration/test_m1_inventory_contract.sh"
python3 "$ROOT/tests/integration/test_p0_m2_volume_policy.py"
python3 "$ROOT/tests/integration/test_m2_consumer_matrix.py"
python3 "$ROOT/tests/public_test_bundle.py"
"$ROOT/tests/integration/test_cpu_capacity_detection.sh"
"$ROOT/p0_extension/tests/test_preprocessing_derivation.sh"
python3 "$ROOT/tests/public_test_tables.py"
echo 'PUBLIC_OFFLINE_TESTS_OK scope=source_contracts_author_workbook_saved_aggregates_no_matlab'
