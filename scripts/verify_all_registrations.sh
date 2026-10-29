#!/usr/bin/env bash
# CTREND_REVISIT_FILE_PURPOSE: Revalidate all nine registered runs and write the suite-level acceptance marker only on complete success.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT="$ROOT/outputs/comparisons/NINE_EXPERIMENT_ACCEPTANCE.csv"
MARKER="$ROOT/outputs/comparisons/NINE_EXPERIMENT_RUN_COMPLETE.env"
TMP="${OUT}.tmp.$$"
printf 'experiment_id,research_run_id,run_root,combo_count,registration_sha256,acceptance_sha256\n' > "$TMP"
for id in M0_D0 M0_D1 M0_D2 M1_D0 M1_D1 M1_D2 M2_D0 M2_D1 M2_D2; do
  reg="$ROOT/outputs/experiments/$id/registration.env"
  [[ -s "$reg" ]] || { echo "missing registration: $id" >&2; rm -f "$TMP"; exit 1; }
  value() { awk -F= -v key="$1" '$1==key{print substr($0,index($0,"=")+1);exit}' "$2"; }
  run="$(value run_root "$reg")"
  expected_registration_format=ctrend-nine-experiment-registration-v1
  acceptance="$run/NINE_EXPERIMENT_ACCEPTANCE.env"
  acceptance_field=nine_experiment_acceptance_sha256
  [[ "$(value format "$reg")" == "$expected_registration_format" && \
     "$(value experiment_id "$reg")" == "$id" ]] || {
    echo "registration identity mismatch: $id" >&2; rm -f "$TMP"; exit 1;
  }
  [[ -d "$run" ]] || { echo "registered run root is absent: $run" >&2; rm -f "$TMP"; exit 1; }
  # This is intentionally the registration gate, not only the lighter result
  # check: for an existing registration it revalidates every stored run/result/
  # inventory/acceptance hash and refuses stale metadata without rewriting it.
  "$ROOT/scripts/register_completed_run.sh" "$id" "$run"
  [[ "$(value "$acceptance_field" "$reg")" == \
     "$(sha256sum "$acceptance" | awk '{print $1}')" ]] || {
    echo "registration acceptance hash mismatch: $id" >&2; rm -f "$TMP"; exit 1;
  }
  printf '%s,%s,%s,%s,%s,%s\n' "$id" "$(value research_run_id "$reg")" \
    "$run" "$(value combo_count "$reg")" "$(sha256sum "$reg" | awk '{print $1}')" \
    "$(sha256sum "$acceptance" | awk '{print $1}')" >> "$TMP"
done
mv -Tf -- "$TMP" "$OUT"
{
  echo 'format=ctrend-nine-experiment-suite-complete-v1'
  echo 'clean_nine_experiment_run_complete=true'
  echo 'experiments=9'
  echo "acceptance_csv_sha256=$(sha256sum "$OUT" | awk '{print $1}')"
  echo "completed_at_utc=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
} > "${MARKER}.tmp.$$"
mv -Tf -- "${MARKER}.tmp.$$" "$MARKER"
echo "NINE_EXPERIMENT_SUITE_ACCEPTED manifest=$OUT marker=$MARKER"
