#!/usr/bin/env bash
# CTREND_REVISIT_FILE_PURPOSE: Materialize a P0 cell using the frozen unfilled M0 or current M1/M2 with the common b01 fill disabled.
set -euo pipefail

EXT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ROOT="$(cd "$EXT_ROOT/.." && pwd)"
ID="${1:-}"
OUT="${2:-}"
case "$ID" in
  P0_M0_D0|P0_M0_D1|P0_M0_D2|P0_M1_D0|P0_M1_D1|P0_M1_D2|P0_M2_D0|P0_M2_D1|P0_M2_D2) ;;
  *) echo "usage: $0 P0_M{0,1,2}_D{0,1,2} FRESH_ABSOLUTE_OUTPUT" >&2; exit 2 ;;
esac
[[ "$OUT" == /* && ! -e "$OUT" && ! -L "$OUT" ]] || {
  echo "OUTPUT must be a fresh absolute path: $OUT" >&2
  exit 2
}

IFS=_ read -r P_ID METHOD DATA_ID EXTRA <<< "$ID"
[[ "$P_ID" == P0 && -z "${EXTRA:-}" ]] || exit 2
ENGINE_ID="$METHOD"
[[ "$METHOD" != M0 ]] || ENGINE_ID=P0_M0
BASE="$ROOT/engines/$ENGINE_ID/base"
EXCLUSION_OVERLAY="$ROOT/engines/$ENGINE_ID/overlays/exclusion"
if [[ "$METHOD" == M0 ]]; then
  P0_B01="$BASE/b01ReadData.m"
  [[ "$DATA_ID" == D0 ]] || P0_B01="$EXCLUSION_OVERLAY/b01ReadData.m"
elif [[ "$DATA_ID" == D0 ]]; then
  P0_B01="$EXT_ROOT/overlays/$METHOD/D0/b01ReadData.m"
else
  P0_B01="$EXT_ROOT/overlays/$METHOD/exclusion/b01ReadData.m"
fi
[[ -d "$BASE/Utils" && -f "$BASE/b01ReadData.m" && -f "$P0_B01" ]] || {
  echo "incomplete P0 derivation source for $ID" >&2
  exit 2
}

write_executable_inventory() {
  local source="$1"
  (
    cd "$source"
    {
      find . -maxdepth 1 -type f \( -name '*.m' -o -name '*.sh' \) \
        ! -name 'tmp_*' -printf '%P\n'
      for dir in Utils LatexTables tests; do
        if [[ -d "$dir" ]]; then
          find "$dir" -type f \( -name '*.m' -o -name '*.sh' \) \
            ! -name 'tmp_*' -printf '%p\n'
        fi
      done
    } | LC_ALL=C sort | while IFS= read -r file; do
      sha256sum -- "$file"
    done
  )
}

mkdir -p "$(dirname "$OUT")"
mkdir "$OUT"
cp -a "$BASE/." "$OUT/"

if [[ "$DATA_ID" != D0 ]]; then
  [[ -f "$EXCLUSION_OVERLAY/Utils/fApplyConfiguredGlobalAssetExclusion.m" ]] || {
    echo "incomplete exclusion overlay: $EXCLUSION_OVERLAY" >&2
    exit 2
  }
  cp -- "$EXCLUSION_OVERLAY/Utils/fApplyConfiguredGlobalAssetExclusion.m" \
    "$OUT/Utils/"
  if [[ -f "$EXCLUSION_OVERLAY/Utils/fFileSHA256.m" ]]; then
    cp -- "$EXCLUSION_OVERLAY/Utils/fFileSHA256.m" "$OUT/Utils/"
  fi
fi
cp -- "$P0_B01" "$OUT/b01ReadData.m"
if [[ "$METHOD" == M2 ]]; then
  # P0/M2 retains P0/M0's zero-to-missing volume convention.
  # The shared M2 base and every P1 materialization remain unchanged.
  cp -- "$EXT_ROOT/overlays/M2/b02CalculateIndicators.m" \
    "$OUT/b02CalculateIndicators.m"
fi

find "$OUT" -type l -print -quit | grep -q . && {
  echo "materialized P0 executable source contains a symbolic link" >&2
  exit 2
}
write_executable_inventory "$BASE" > "$OUT.base-executable.sha256"
write_executable_inventory "$OUT" > "$OUT.materialized-executable.sha256"
diff -u "$OUT.base-executable.sha256" \
  "$OUT.materialized-executable.sha256" > "$OUT.p0-overlay.diff" || true
if [[ "$METHOD" == M0 && "$DATA_ID" == D0 ]]; then
  cmp -s "$OUT.base-executable.sha256" "$OUT.materialized-executable.sha256"
else
  grep -F 'b01ReadData.m' "$OUT.p0-overlay.diff" >/dev/null
fi
if [[ "$DATA_ID" != D0 ]]; then
  grep -F 'fApplyConfiguredGlobalAssetExclusion.m' \
    "$OUT.p0-overlay.diff" >/dev/null
fi

EXCLUSION="$ROOT/config/exclusions/$DATA_ID.csv"
EXCLUSION_SHA="$(sha256sum "$EXCLUSION" | awk '{print $1}')"
PARENT_B01="$BASE/b01ReadData.m"
{
  echo 'format=ctrend-2x3x3-p0-materialized-source-v1'
  echo "experiment_id=$ID"
  echo "preprocessing_id=$P_ID"
  echo "unified_missing_preprocessing=0"
  echo "method_id=$METHOD"
  echo "data_id=$DATA_ID"
  echo "base_source=$BASE"
  echo "p1_parent_b01_sha256=$(sha256sum "$PARENT_B01" | awk '{print $1}')"
  echo "p0_b01_sha256=$(sha256sum "$P0_B01" | awk '{print $1}')"
  if [[ "$METHOD" == M2 ]]; then
    echo 'volume_policy=p0_m0_zero_to_missing'
    echo "p0_b02_sha256=$(sha256sum "$OUT/b02CalculateIndicators.m" | awk '{print $1}')"
  fi
  echo "materialized_source=$OUT"
  echo "exclusion_file=$EXCLUSION"
  echo "exclusion_sha256=$EXCLUSION_SHA"
  echo "base_inventory_sha256=$(sha256sum "$OUT.base-executable.sha256" | awk '{print $1}')"
  echo "materialized_inventory_sha256=$(sha256sum "$OUT.materialized-executable.sha256" | awk '{print $1}')"
  echo "materialized_at=$(date -Is)"
} > "$OUT.materialization.env"

printf '%s\n' "$OUT"
