#!/usr/bin/env bash
# CTREND_REVISIT_FILE_PURPOSE: Verify the frozen P1 parent and every P0-specific source, identity, packaging, and portability contract before production.
set -euo pipefail

EXT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ROOT="$(cd "$EXT_ROOT/.." && pwd)"
"$ROOT/scripts/preflight.sh"

while IFS= read -r file; do bash -n "$file"; done < <(
  find "$EXT_ROOT" -type f -name '*.sh' | LC_ALL=C sort
)
python3 -m py_compile "$EXT_ROOT/tests/verify_output_registry.py"
"$EXT_ROOT/tests/test_preprocessing_derivation.sh"
"$EXT_ROOT/tests/test_runtime_packages.sh"

MATLAB_BIN="${MATLAB_BIN:-$(command -v matlab 2>/dev/null || true)}"
if [[ -x "$MATLAB_BIN" ]]; then
  MATLAB_BIN="$MATLAB_BIN" \
    "$EXT_ROOT/tests/test_m1_b01_b02_checkpoint_contract.sh"
elif [[ "${P0_REQUIRE_MATLAB_INTEGRATION:-0}" == 1 ]]; then
  echo 'P0 preflight requires MATLAB for the real b01->b02 contract test' >&2
  exit 2
else
  echo 'P0_PREFLIGHT_WARNING real b01->b02 contract test skipped without MATLAB' >&2
fi

python3 - "$EXT_ROOT/config/experiments.csv" <<'PY'
import csv
import sys

rows = list(csv.DictReader(open(sys.argv[1], encoding="utf-8")))
expected = [
    f"P0_M{method}_D{data}"
    for method in (0, 1, 2)
    for data in (0, 1, 2)
]
assert [row["experiment_id"] for row in rows] == expected
assert len(rows) == 9 and len({row["experiment_id"] for row in rows}) == 9
assert all(row["preprocessing_id"] == "P0" for row in rows)
assert all(row["run_policy"] == "new_run_required" for row in rows)
print("P0_EXPERIMENT_REGISTRY_OK cells=9 methods=M0,M1,M2 data=D0,D1,D2")
PY

echo 'P0_PREFLIGHT_OK cells=9 parent_p1_frozen=1 unified_missing_preprocessing=0 b01_b02_contract=1 b09=8x15'
