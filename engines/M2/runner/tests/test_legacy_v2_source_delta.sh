#!/usr/bin/env bash
# CTREND_REVISIT_FILE_PURPOSE: Validate the explicitly selected legacy-v2 compatibility source against Dataverse.
set -euo pipefail

if [[ "$#" -ne 2 ]]; then
  echo "usage: $0 OLD_ARCHIVE OLD_V2_SOURCE" >&2
  exit 2
fi
OLD_ARCHIVE="$1"
OLD_V2_SOURCE="$2"
TEMP_ROOT="$(mktemp -d /tmp/ctrend_old_v2_delta_XXXXXX)"
trap 'rm -rf -- "$TEMP_ROOT"' EXIT
tar -xzf "$OLD_ARCHIVE" -C "$TEMP_ROOT"
OLD_SOURCE="$TEMP_ROOT/ctrend_old_pipeline"

for file in "$OLD_SOURCE"/*.m "$OLD_SOURCE"/*.sh; do
  name="$(basename "$file")"
  case "$name" in
    b01ReadData.m|b09RunResearchDesigns.m) continue ;;
  esac
  cmp -s "$file" "$OLD_V2_SOURCE/$name" || {
    echo "unexpected top-level old-code change: $name" >&2
    exit 1
  }
done
diff -qr "$OLD_SOURCE/Utils" "$OLD_V2_SOURCE/Utils"
diff -qr "$OLD_SOURCE/LatexTables" "$OLD_V2_SOURCE/LatexTables"

grep -Fq 'iOldV2ExcludedAssetID = 3787' "$OLD_V2_SOURCE/b01ReadData.m"
grep -Fq 'OLD_V2_B09_FIRST_COMBO' "$OLD_V2_SOURCE/b09RunResearchDesigns.m"
grep -Fq 'OLD_V2_B09_LAST_COMBO' "$OLD_V2_SOURCE/b09RunResearchDesigns.m"
echo OLD_V2_SOURCE_DELTA_TEST_OK
