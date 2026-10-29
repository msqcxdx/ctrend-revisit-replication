#!/usr/bin/env bash
# CTREND_REVISIT_FILE_PURPOSE: Materialize all nine cells and verify D overlays, source identities, and exclusion placement.
# D0 must equal its method base byte-for-byte; D1/D2 may add only the configured
# exclusion helper and b01 call site recorded by the materialization diff.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TMP="$(mktemp -d /tmp/ctrend_3x3_materialization_test_XXXXXX)"
cleanup() { rm -rf -- "$TMP"; }
trap cleanup EXIT

for id in M0_D0 M0_D1 M0_D2 M1_D0 M1_D1 M1_D2 M2_D0 M2_D1 M2_D2; do
  # Exercise the public materializer for every cell rather than inferring overlays.
  out="$TMP/$id/source"
  "$ROOT/scripts/materialize_experiment_source.sh" "$id" "$out" >/dev/null
  test -f "$out/b01ReadData.m"
  test -s "$TMP/$id/source.materialization.env"
  data_id="${id##*_}"
  if [[ "$data_id" == D0 ]]; then
    test ! -e "$out/Utils/fApplyConfiguredGlobalAssetExclusion.m"
    cmp -s "$TMP/$id/source.base-executable.sha256" \
      "$TMP/$id/source.materialized-executable.sha256"
  else
    test -f "$out/Utils/fApplyConfiguredGlobalAssetExclusion.m"
    grep -F 'fApplyConfiguredGlobalAssetExclusion' "$out/b01ReadData.m" >/dev/null
    grep -F 'b01ReadData.m' "$TMP/$id/source.overlay.diff" >/dev/null
  fi
done
cmp -s "$ROOT/engines/M1/base/b01ReadData.m" "$TMP/M1_D0/source/b01ReadData.m"
cmp -s "$ROOT/engines/M0/base/b01ReadData.m" "$TMP/M0_D0/source/b01ReadData.m"
cmp -s "$ROOT/engines/M2/base/b01ReadData.m" "$TMP/M2_D0/source/b01ReadData.m"
echo 'MATERIALIZATION_TEST_OK sources=9 d0_exact=3 overlays=6'
