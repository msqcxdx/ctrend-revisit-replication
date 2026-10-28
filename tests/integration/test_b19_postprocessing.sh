#!/usr/bin/env bash
# CTREND_REVISIT_FILE_PURPOSE: Verify that numbered b19 is path-free, registration-bound, complete, and separate from all method engines.
# Bind b19 to all nine registrations, seven declared outputs, and the
# intersection-only missing-return rule; keep it outside scientific engines.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
RUNNER="$ROOT/postprocessing/run_b19_common_week_robustness.sh"

bash -n "$RUNNER"
# Verify the public route and the provenance/output commitments it delegates to.
grep -F 'b19)' "$ROOT/run_all.sh" >/dev/null
grep -F 'scripts/register_completed_run.sh' "$RUNNER" >/dev/null
grep -F 'B19_OUTPUTS.sha256' "$RUNNER" >/dev/null
grep -F 'missing_return_rule=intersection_only_no_imputation' "$RUNNER" >/dev/null
for id in M0_D0 M0_D1 M0_D2 M2_D0 M2_D1 M2_D2 M1_D0 M1_D1 M1_D2; do
  grep -F "$id" "$RUNNER" >/dev/null
done
site_path_pattern='/ho''me/|/Us''ers/|[A-Za-z]:\\Us''ers\\|/da''ta[0-9]+/|/m''nt/|61\.162''\.193\.19'
if rg -n "$site_path_pattern" \
    "$ROOT/postprocessing" "$ROOT/config/postprocessing_registry.csv"; then
  echo 'b19 contains a site-specific path or host' >&2
  exit 1
fi
python3 - "$ROOT/config/postprocessing_registry.csv" <<'PY'
import csv, sys
rows = list(csv.DictReader(open(sys.argv[1], encoding="utf-8")))
assert len(rows) == 7
assert {row["producer_step"] for row in rows} == {"b19"}
assert len({row["required_output"] for row in rows}) == 7
PY
for method in M0 M1 M2; do
  # Scientific engines must not contain cross-method post-processing artifacts.
  if find "$ROOT/engines/$method" -type f -iname '*b19*' -print -quit | grep -q .; then
    echo "b19 leaked into the $method scientific engine" >&2
    exit 1
  fi
done
echo 'B19_POSTPROCESSING_CONTRACT_OK inputs=9 outputs=7 engine_separation=1 no_imputation=1'
