#!/usr/bin/env bash
# CTREND_REVISIT_FILE_PURPOSE: Materialize and archive the immutable method/data source package used by one experiment.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ID="${1:-}"
SOURCE="${2:-}"
OUTPUT="${3:-}"
case "$ID" in
  M0_D0|M0_D1|M0_D2) METHOD=M0; PACKAGE_NAME=cttrend_old_pipeline ;;
  M1_D0|M1_D1|M1_D2) METHOD=M1; PACKAGE_NAME=cttrend_corrected_pipeline ;;
  M2_D0|M2_D1|M2_D2) METHOD=M2; PACKAGE_NAME=cttrend_lookahead_only_pipeline ;;
  *) echo "usage: $0 EXPERIMENT_ID MATERIALIZED_SOURCE OUTPUT.tar.gz" >&2; exit 2 ;;
esac
[[ -d "$SOURCE" && "$OUTPUT" == /* ]] || exit 2
SOURCE="$(readlink -f -- "$SOURCE")"
TEMP="$(mktemp -d /tmp/cttrend_2x3_package_XXXXXX)"
cleanup() { local rc=$?; trap - EXIT; rm -rf -- "$TEMP"; exit "$rc"; }
trap cleanup EXIT INT TERM
DEST="$TEMP/$PACKAGE_NAME"
mkdir "$DEST"

while IFS= read -r -d '' file; do cp -- "$file" "$DEST/"; done < <(
  find "$SOURCE" -maxdepth 1 -type f \
    \( -name '*.m' -o -name '*.sh' -o -name '*.md' -o -name '*.txt' \) \
    ! -name 'tmp_*' ! -name 'PACKAGE_FILES.sha256' -print0 | LC_ALL=C sort -z
)
for dir in Utils LatexTables tests; do
  [[ ! -d "$SOURCE/$dir" ]] || cp -a -- "$SOURCE/$dir" "$DEST/"
done
if [[ "$METHOD" == M1 ]]; then
  [[ -f "$SOURCE/DesignChoices.mat" ]] || {
    echo "M1 source lacks DesignChoices.mat" >&2; exit 2;
  }
  cp -- "$SOURCE/DesignChoices.mat" "$DEST/"
fi
[[ ! -e "$DEST/DATA" && ! -e "$DEST/Results" && ! -e "$DEST/logs" &&
   ! -e "$DEST/.raw_input_seed" && ! -e "$DEST/.canonical" ]] || exit 2
find "$DEST" -type l -print -quit | grep -q . && {
  echo "runtime package contains a symbolic link" >&2; exit 2;
}
if [[ "$METHOD" == M0 || "$METHOD" == M2 ]]; then
  (
    cd "$DEST"
    find . -type f ! -name 'PACKAGE_FILES.sha256' -printf '%P\0' | \
      LC_ALL=C sort -z | xargs -0 -r sha256sum
  ) > "$TEMP/PACKAGE_FILES.sha256"
  cp -- "$TEMP/PACKAGE_FILES.sha256" "$DEST/PACKAGE_FILES.sha256"
fi

mkdir -p "$(dirname "$OUTPUT")"
TMP_OUTPUT="${OUTPUT}.tmp.$$"
tar -czf "$TMP_OUTPUT" -C "$TEMP" "$PACKAGE_NAME"
SHA="$(sha256sum "$TMP_OUTPUT" | awk '{print $1}')"
mv -f -- "$TMP_OUTPUT" "$OUTPUT"
printf '%s  %s\n' "$SHA" "$(basename "$OUTPUT")" > "$OUTPUT.sha256"
echo "RUNTIME_PACKAGE_READY experiment=$ID path=$OUTPUT sha256=$SHA"
