#!/usr/bin/env bash
# CTREND_REVISIT_FILE_PURPOSE: Prove P0/P1 differ only at b01 and the declared M2 b02 volume block, without invoking common filling in P0.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
EXT_ROOT="$ROOT/p0_extension"
M2_STATIC_GUARD="$ROOT/engines/M2/runner/tests/test_m2_static_guards.sh"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/ctrend_p0_derivation_XXXXXX")"
cleanup() { rm -rf -- "$TMP"; }
trap cleanup EXIT

for method in M1 M2; do
  for data_id in D0 D1 D2; do
    id="P0_${method}_${data_id}"
    out="$TMP/$id/source"
    "$EXT_ROOT/scripts/materialize_experiment_source.sh" "$id" "$out" >/dev/null
    p1_out="$TMP/P1_${method}_${data_id}/source"
    "$ROOT/scripts/materialize_experiment_source.sh" \
      "${method}_${data_id}" "$p1_out" >/dev/null
    [[ "$(awk -F= '$1=="experiment_id"{print $2;exit}' \
      "$out.materialization.env")" == "$id" ]]
    [[ "$(awk -F= '$1=="unified_missing_preprocessing"{print $2;exit}' \
      "$out.materialization.env")" == 0 ]]

    ! rg -n 'fApplyUnifiedMissingDataPreprocessing|rUnifiedMissingPreprocessing' \
      "$out/b01ReadData.m" >/dev/null
    rg -n 'lReplaceVol[[:space:]]*=[[:space:]]*mVolume == 0 & isnan\(mReturns\)' \
      "$out/b01ReadData.m" >/dev/null
    rg -n 'mVolume\(lReplaceVol\)[[:space:]]*=[[:space:]]*NaN' \
      "$out/b01ReadData.m" >/dev/null
    rg -n 'fBuildAndFreezeMechanicalExitCalendar' "$out/b01ReadData.m" >/dev/null
    if [[ "$method" == M1 ]]; then
      # M1 b02 requires an explicit audit mask. In P0 it must be an
      # all-false sentinel, never the output of unified preprocessing.
      rg -n 'lUnifiedAuxiliaryFilled[[:space:]]*=[[:space:]]*false\(size\(mClose\)\)' \
        "$out/b01ReadData.m" >/dev/null
      rg -n "'lUnifiedAuxiliaryFilled'" "$out/b01ReadData.m" >/dev/null
    else
      ! rg -n 'lUnifiedAuxiliaryFilled' "$out/b01ReadData.m" >/dev/null
      # Exercise the same guard called by the production M2 runner under the
      # P0 contract. This prevents a P1-only assertion from passing package
      # preflight and then killing a fresh P0 production run.
      CTREND_PREPROCESSING_ID=P0 \
        "$M2_STATIC_GUARD" "$out" >/dev/null
    fi

    # The same-M/D delta is b01 plus the declared M2 b02 volume block. This
    # direct comparison prevents a D overlay or downstream M file from being
    # silently changed while still satisfying a base-relative allowlist.
    same_cell_changed="$(diff -u \
      "$p1_out.materialized-executable.sha256" \
      "$out.materialized-executable.sha256" | \
      awk '/^[+-][0-9a-f]/{print $2}' | sort -u || true)"
    expected_changed=b01ReadData.m
    [[ "$method" != M2 ]] || expected_changed=$'b01ReadData.m\nb02CalculateIndicators.m'
    [[ "$same_cell_changed" == "$expected_changed" ]]

    # The full executable inventory adds only those files plus the existing
    # D1/D2 global-exclusion helper inherited from the P1 parent overlay.
    changed="$(awk '/^[+-][0-9a-f]/{print $2}' "$out.p0-overlay.diff" | sort -u)"
    if [[ "$data_id" == D0 ]]; then
      [[ "$changed" == "$expected_changed" ]]
    else
      [[ "$changed" == $'Utils/fApplyConfiguredGlobalAssetExclusion.m\n'"$expected_changed" || \
         "$changed" == $'Utils/fApplyConfiguredGlobalAssetExclusion.m\nUtils/fFileSHA256.m\n'"$expected_changed" ]]
    fi
  done
done

# D1 and D2 share executable source by design; only their external frozen
# exclusion registry differs at launch.
for method in M1 M2; do
  cmp -s "$TMP/P0_${method}_D1/source.materialized-executable.sha256" \
    "$TMP/P0_${method}_D2/source.materialized-executable.sha256"
done

python3 "$ROOT/tests/integration/test_p0_m2_volume_policy.py"
echo 'P0_PREPROCESSING_DERIVATION_TEST_OK cells=6 parent=P1 same_md_scope=b01_and_M2_volume_block'
