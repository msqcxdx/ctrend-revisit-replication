#!/usr/bin/env bash
# CTREND_REVISIT_FILE_PURPOSE: Preserve the pre-3x3 v2 runtime archive format for historical recovery only.
set -euo pipefail

if [[ "$#" -gt 2 ]]; then
  echo "usage: $0 [SOURCE_DIR] [OUTPUT_TAR_GZ]" >&2
  exit 2
fi

RUNNER_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$RUNNER_DIR/.." && pwd)"
SOURCE_DIR="${1:-$PROJECT_DIR/old_code_v2}"
OUTPUT="${2:-$PROJECT_DIR/cttrend_old_v2_pipeline.tar.gz}"
TEMP_ROOT="$(mktemp -d /tmp/cttrend_old_v2_package_XXXXXX)"
PACKAGE_ROOT="$TEMP_ROOT/cttrend_old_v2_pipeline"

cleanup() {
  local rc=$?
  trap - EXIT INT TERM
  rm -rf -- "$TEMP_ROOT"
  exit "$rc"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

[[ -d "$SOURCE_DIR/Utils" && -d "$SOURCE_DIR/LatexTables" &&
   -d "$SOURCE_DIR/tests" && -f "$SOURCE_DIR/b01ReadData.m" &&
   -f "$SOURCE_DIR/b09RunResearchDesigns.m" &&
   -f "$SOURCE_DIR/run_safety.sh" ]] || {
  echo "old v2 source tree is incomplete" >&2
  exit 2
}

mkdir -p "$PACKAGE_ROOT"
while IFS= read -r -d '' file; do
  cp -a -- "$file" "$PACKAGE_ROOT/"
done < <(find "$SOURCE_DIR" -maxdepth 1 -type f \
  \( -name '*.m' -o -name '*.sh' -o -name '*.md' -o -name '*.txt' \) \
  -print0 | LC_ALL=C sort -z)
cp -a -- "$SOURCE_DIR/Utils" "$SOURCE_DIR/LatexTables" \
  "$SOURCE_DIR/tests" "$PACKAGE_ROOT/"

[[ ! -e "$PACKAGE_ROOT/DATA" && ! -e "$PACKAGE_ROOT/Results" &&
   ! -e "$PACKAGE_ROOT/.raw_input_seed" && ! -e "$PACKAGE_ROOT/logs" ]] || {
  echo "runtime package contains forbidden mutable directories" >&2
  exit 2
}
find "$PACKAGE_ROOT" -type l -print -quit | grep -q . && {
  echo "runtime package contains a symbolic link" >&2
  exit 2
}

(
  cd "$PACKAGE_ROOT"
  find . -type f -printf '%P\0' | LC_ALL=C sort -z |
    xargs -0 -r sha256sum
) > "$TEMP_ROOT/package_files.sha256"
cp -- "$TEMP_ROOT/package_files.sha256" "$PACKAGE_ROOT/PACKAGE_FILES.sha256"

mkdir -p "$(dirname "$OUTPUT")"
temporary_output="${OUTPUT}.tmp.$$"
tar -czf "$temporary_output" -C "$TEMP_ROOT" cttrend_old_v2_pipeline
archive_sha="$(sha256sum "$temporary_output" | awk '{print $1}')"
mv -f -- "$temporary_output" "$OUTPUT"
printf '%s  %s\n' "$archive_sha" "$(basename "$OUTPUT")" \
  > "$OUTPUT.sha256"
printf 'package=%s\nsha256=%s\n' "$OUTPUT" "$archive_sha"
