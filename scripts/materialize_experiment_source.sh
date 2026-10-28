#!/usr/bin/env bash
# CTREND_REVISIT_FILE_PURPOSE: Combine one frozen M engine with one D-axis exclusion overlay without editing either parent.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ID="${1:-}"
OUT="${2:-}"
case "$ID" in
  M0_D0|M0_D1|M0_D2|M1_D0|M1_D1|M1_D2|M2_D0|M2_D1|M2_D2) ;;
  *) echo "usage: $0 M{0,1,2}_D{0,1,2} OUTPUT" >&2; exit 2 ;;
esac
[[ "$OUT" == /* && ! -e "$OUT" && ! -L "$OUT" ]] || {
  echo "OUTPUT must be a fresh absolute path: $OUT" >&2
  exit 2
}

METHOD="${ID%%_*}"
DATA_ID="${ID##*_}"
BASE="$ROOT/engines/$METHOD/base"
OVERLAY="$ROOT/engines/$METHOD/overlays/exclusion"
[[ -d "$BASE/Utils" && -f "$BASE/b01ReadData.m" ]] || {
  echo "incomplete base engine: $BASE" >&2
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
  [[ -f "$OVERLAY/b01ReadData.m" &&
     -f "$OVERLAY/Utils/fApplyConfiguredGlobalAssetExclusion.m" ]] || {
    echo "incomplete exclusion overlay: $OVERLAY" >&2
    exit 2
  }
  cp -- "$OVERLAY/b01ReadData.m" "$OUT/b01ReadData.m"
  cp -- "$OVERLAY/Utils/fApplyConfiguredGlobalAssetExclusion.m" "$OUT/Utils/"
  if [[ -f "$OVERLAY/Utils/fFileSHA256.m" ]]; then
    cp -- "$OVERLAY/Utils/fFileSHA256.m" "$OUT/Utils/"
  fi
fi

find "$OUT" -type l -print -quit | grep -q . && {
  echo "materialized executable source contains a symbolic link" >&2
  exit 2
}
write_executable_inventory "$BASE" > "$OUT.base-executable.sha256"
write_executable_inventory "$OUT" > "$OUT.materialized-executable.sha256"
if [[ "$DATA_ID" == D0 ]]; then
  cmp -s "$OUT.base-executable.sha256" "$OUT.materialized-executable.sha256" || {
    echo "D0 materialization changed executable source" >&2
    exit 2
  }
else
  diff -u "$OUT.base-executable.sha256" \
    "$OUT.materialized-executable.sha256" > "$OUT.overlay.diff" || true
  grep -F 'b01ReadData.m' "$OUT.overlay.diff" >/dev/null
  grep -F 'fApplyConfiguredGlobalAssetExclusion.m' "$OUT.overlay.diff" >/dev/null
fi

EXCLUSION="$ROOT/config/exclusions/$DATA_ID.csv"
EXCLUSION_SHA="$(sha256sum "$EXCLUSION" | awk '{print $1}')"
{
  echo 'format=cttrend-3x3-materialized-source-v1'
  echo "experiment_id=$ID"
  echo "method_id=$METHOD"
  echo "data_id=$DATA_ID"
  echo "base_source=$BASE"
  echo "materialized_source=$OUT"
  echo "exclusion_file=$EXCLUSION"
  echo "exclusion_sha256=$EXCLUSION_SHA"
  echo "base_inventory_sha256=$(sha256sum "$OUT.base-executable.sha256" | awk '{print $1}')"
  echo "materialized_inventory_sha256=$(sha256sum "$OUT.materialized-executable.sha256" | awk '{print $1}')"
  echo "materialized_at=$(date -Is)"
} > "$OUT.materialization.env"

printf '%s\n' "$OUT"
