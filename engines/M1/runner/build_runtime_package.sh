#!/usr/bin/env bash
# CTREND_REVISIT_FILE_PURPOSE: Build the immutable M1 runtime archive and bind it to source and runner inventories.
set -euo pipefail

RUNNER_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$RUNNER_DIR/.." && pwd)"
CODE_DIR="${CODE_DIR:-$PROJECT_DIR/base}"
OUTPUT="${1:-$PROJECT_DIR/cttrend_m1_pipeline.tar.gz}"
TEMP_ROOT="$(mktemp -d /tmp/cttrend_package_XXXXXX)"
rmdir "$TEMP_ROOT"

# shellcheck source=../base/run_safety.sh
source "$CODE_DIR/run_safety.sh"
cttrend_prepare_temp_dir "$TEMP_ROOT" /tmp package_build

cleanup_package_temp() {
  local rc=$?
  trap - EXIT INT TERM
  cttrend_safe_remove_temp_dir "$TEMP_ROOT" /tmp || rc=1
  exit "$rc"
}
trap cleanup_package_temp EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

PACKAGE_ROOT="$TEMP_ROOT/cttrend_corrected_pipeline"
mkdir -p "$PACKAGE_ROOT"

# Explicitly exclude DATA, Results, logs, MATLAB preferences, and prior
# packages.  Only executable source, tests, documentation, and the seed
# DesignChoices file enter the runtime archive.
while IFS= read -r -d '' source_file; do
  cp -- "$source_file" "$PACKAGE_ROOT/"
done < <(
  find "$CODE_DIR" -maxdepth 1 -type f \
    \( -name '*.m' -o -name '*.sh' -o -name '*.md' -o -name '*.txt' \
    \) -print0
)
[[ -f "$CODE_DIR/DesignChoices.mat" ]] || {
  echo "DesignChoices.mat is missing from the M1 source" >&2
  exit 2
}
# DesignChoices may be a stable symlink through the canonical-bundle
# pointer.  Dereference it so every runtime package contains an immutable
# seed file rather than a workspace-specific link.
cp -L -- "$CODE_DIR/DesignChoices.mat" "$PACKAGE_ROOT/DesignChoices.mat"
cp -a -- "$CODE_DIR/Utils" "$PACKAGE_ROOT/Utils"
cp -a -- "$CODE_DIR/LatexTables" "$PACKAGE_ROOT/LatexTables"
if [[ -d "$CODE_DIR/tests" ]]; then
  cp -a -- "$CODE_DIR/tests" "$PACKAGE_ROOT/tests"
fi

temporary_archive="$TEMP_ROOT/cttrend_corrected_pipeline.tar.gz"
tar -czf "$temporary_archive" -C "$TEMP_ROOT" cttrend_corrected_pipeline
mkdir -p -- "$(dirname "$OUTPUT")"
output_temporary="${OUTPUT}.tmp.$$"
cp -- "$temporary_archive" "$output_temporary"
archive_sha="$(sha256sum "$output_temporary" | awk '{print $1}')"
mv -f -- "$output_temporary" "$OUTPUT"
checksum_temporary="${OUTPUT}.sha256.tmp.$$"
printf '%s  %s\n' "$archive_sha" "$(basename "$OUTPUT")" \
  > "$checksum_temporary"
mv -f -- "$checksum_temporary" "${OUTPUT}.sha256"
printf 'package=%s\nsha256=%s\n' "$(readlink -f "$OUTPUT")" "$archive_sha"
