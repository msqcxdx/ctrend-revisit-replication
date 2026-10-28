#!/usr/bin/env bash
# CTREND_REVISIT_FILE_PURPOSE: Create a deterministic SHA-256 inventory for every release-controlled package file.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUTPUT="$ROOT/PACKAGE_MANIFEST.sha256"
TMP="${OUTPUT}.tmp.$$"
(
  cd "$ROOT"
  find . \
    \( -path './.git' -o -path './.github' -o \
       -path './outputs' -o -path './runtime' -o \
       -name '.venv*' -o -name '__pycache__' -o \
       -name '.pytest_cache' \) -prune -o \
    -type f ! -name 'PACKAGE_MANIFEST.sha256' \
    ! -name 'PACKAGE_MANIFEST.sha256.tmp.*' \
    ! -name '*.pyc' ! -name '*.pyo' \
    ! -path './release/SHA256SUMS' \
    ! -path './release/FILE_MANIFEST.csv' -print0 | \
    LC_ALL=C sort -z | xargs -0 -r sha256sum
) > "$TMP"
test -s "$TMP"
mv -Tf -- "$TMP" "$OUTPUT"
(cd "$ROOT" && sha256sum -c "$OUTPUT" >/dev/null)
echo "PACKAGE_MANIFEST_READY files=$(wc -l < "$OUTPUT") sha256=$(sha256sum "$OUTPUT" | awk '{print $1}')"
