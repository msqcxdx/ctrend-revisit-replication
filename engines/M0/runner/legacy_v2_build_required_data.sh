#!/usr/bin/env bash
# CTREND_REVISIT_FILE_PURPOSE: Preserve the pre-3x3 v2 required-data archive format for historical recovery only.
set -euo pipefail

RUNNER_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$RUNNER_DIR/.." && pwd)"
SOURCE_DATA="${1:-$PROJECT_DIR/old_code_v2/.raw_input_seed}"
OUTPUT="${2:-$PROJECT_DIR/cttrend_old_v2_required_data.tar.gz}"
TEMP_ROOT="$(mktemp -d /tmp/cttrend_old_v2_required_data_XXXXXX)"
ROOT="$TEMP_ROOT/cttrend_old_v2_required_data"

cleanup() {
  local rc=$?
  trap - EXIT INT TERM
  rm -rf -- "$TEMP_ROOT"
  exit "$rc"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

cRequired=(
  close_cmc.csv open_cmc.csv high_cmc.csv low_cmc.csv
  market_cap_cmc.csv volume_cmc.csv MetaData.mat
  F-F_Research_Data_Factors_daily.CSV LTW_3factor.xlsx UCRY.csv
)
mkdir -p "$ROOT/DATA"
for file in "${cRequired[@]}"; do
  [[ -f "$SOURCE_DATA/$file" && ! -L "$SOURCE_DATA/$file" ]] || {
    echo "missing regular old v2 input: $file" >&2
    exit 2
  }
  cp --reflink=auto -- "$SOURCE_DATA/$file" "$ROOT/DATA/$file"
done
cp -- "$PROJECT_DIR/old_code_v2/INPUT_DATA_REQUIREMENTS.md" "$ROOT/README.md"
(
  cd "$ROOT/DATA"
  find . -maxdepth 1 -type f -printf '%P\0' | LC_ALL=C sort -z |
    xargs -0 -r sha256sum
) > "$ROOT/DATA_MANIFEST.sha256"
mkdir -p "$(dirname "$OUTPUT")"
temporary="${OUTPUT}.tmp.$$"
tar -czf "$temporary" -C "$TEMP_ROOT" cttrend_old_v2_required_data
archive_sha="$(sha256sum "$temporary" | awk '{print $1}')"
mv -f -- "$temporary" "$OUTPUT"
printf '%s  %s\n' "$archive_sha" "$(basename "$OUTPUT")" > "$OUTPUT.sha256"
printf 'required_data=%s\nsha256=%s\n' "$OUTPUT" "$archive_sha"
