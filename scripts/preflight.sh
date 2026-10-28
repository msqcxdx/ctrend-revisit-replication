#!/usr/bin/env bash
# CTREND_REVISIT_FILE_PURPOSE: Gate a public-checkout production run on real inputs, required helpers, static contracts and MATLAB tests.
# This is the rights-screened public counterpart of the controlled preflight.
# It does not pretend that omitted acquisition tests or private annotations ran.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

if [[ "${1:-}" == --code-only && $# -eq 1 ]]; then
  "$ROOT/tests/run_tests.sh"
  echo 'PUBLIC_CODE_PREFLIGHT_OK scope=offline_no_vendor_data_no_matlab'
  exit 0
fi
[[ $# -eq 0 ]] || { echo 'usage: preflight.sh [--code-only]' >&2; exit 2; }

for name in bash awk find flock python3 readlink realpath rg rsync setsid \
    sha256sum sort tar unzip zip; do
  command -v "$name" >/dev/null 2>&1 || {
    echo "PUBLIC_PREFLIGHT_ERROR missing command: $name" >&2
    exit 2
  }
done

"$ROOT/tests/run_tests.sh"
"${PYTHON_BIN:-python3}" "$ROOT/scripts/data_bundle.py" preflight --root "$ROOT"

# These third-party helpers are intentionally not redistributed. A locally
# supplied copy is required in each engine's Utils directory; the frozen
# package inventory verifies the precise research version of each copy.
for method in M0 M1 M2 P0_M0; do
  base="$ROOT/engines/$method/base"
  for helper in regstats2.m parfor_wait.m; do
    [[ -s "$base/Utils/$helper" && ! -L "$base/Utils/$helper" ]] || {
      echo "PUBLIC_PREFLIGHT_ERROR missing separately supplied $base/Utils/$helper" >&2
      exit 2
    }
    expected="$(awk -v path="Utils/$helper" '$2==path {print $1}' \
      "$ROOT/engines/P0_M0/base/PACKAGE_FILES.sha256")"
    [[ -n "$expected" && "$(sha256sum "$base/Utils/$helper" | awk '{print $1}')" == "$expected" ]] || {
      echo "PUBLIC_PREFLIGHT_ERROR helper version differs from accepted study: $base/Utils/$helper" >&2
      exit 2
    }
  done
  if [[ -f "$base/PACKAGE_FILES.sha256" ]]; then
    (cd "$base" && sha256sum -c PACKAGE_FILES.sha256 >/dev/null) || {
      echo "PUBLIC_PREFLIGHT_ERROR engine source/helper inventory mismatch: $method" >&2
      exit 2
    }
  fi
done

MATLAB_BIN="${MATLAB_BIN:-$(command -v matlab 2>/dev/null || true)}"
[[ -n "$MATLAB_BIN" && -x "$MATLAB_BIN" ]] || {
  echo 'PUBLIC_PREFLIGHT_ERROR set MATLAB_BIN to MATLAB R2023b Update 11' >&2
  exit 2
}
MATLAB_BIN="$MATLAB_BIN" "$ROOT/scripts/run_matlab_unit_tests.sh"
echo 'PUBLIC_PRODUCTION_PREFLIGHT_OK data=verified helpers=verified matlab_tests=passed experiments=18'
