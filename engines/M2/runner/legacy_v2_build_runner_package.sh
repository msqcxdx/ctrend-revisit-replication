#!/usr/bin/env bash
# CTREND_REVISIT_FILE_PURPOSE: Preserve the pre-3x3 v2 runner archive format for historical recovery only.
set -euo pipefail

RUNNER_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$RUNNER_DIR/.." && pwd)"
OUTPUT="${1:-$PROJECT_DIR/ctrend_old_v2_runner.tar.gz}"
TEMP_ROOT="$(mktemp -d /tmp/ctrend_old_v2_runner_package_XXXXXX)"
ROOT="$TEMP_ROOT/b09_parallel_runner_old_v2"

cleanup() {
  local rc=$?
  trap - EXIT INT TERM
  rm -rf -- "$TEMP_ROOT"
  exit "$rc"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

mkdir -p "$ROOT"
while IFS= read -r -d '' file; do
  relative="${file#"$RUNNER_DIR/"}"
  mkdir -p "$ROOT/$(dirname "$relative")"
  cp -a -- "$file" "$ROOT/$relative"
done < <(find "$RUNNER_DIR" -type f \
  \( -name '*.sh' -o -name '*.tsv' -o -name '*.m' \) \
  -print0 | LC_ALL=C sort -z)
find "$ROOT" -type l -print -quit | grep -q . && {
  echo "runner package contains a symbolic link" >&2
  exit 2
}
(
  cd "$ROOT"
  find . -type f ! -name RUNNER_FILES.sha256 -printf '%P\0' |
    LC_ALL=C sort -z | xargs -0 -r sha256sum
) > "$ROOT/RUNNER_FILES.sha256"
temporary="${OUTPUT}.tmp.$$"
tar -czf "$temporary" -C "$TEMP_ROOT" b09_parallel_runner_old_v2
archive_sha="$(sha256sum "$temporary" | awk '{print $1}')"
mv -f -- "$temporary" "$OUTPUT"
printf '%s  %s\n' "$archive_sha" "$(basename "$OUTPUT")" > "$OUTPUT.sha256"
printf 'runner=%s\nsha256=%s\n' "$OUTPUT" "$archive_sha"
