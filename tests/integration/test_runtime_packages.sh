#!/usr/bin/env bash
# CTREND_REVISIT_FILE_PURPOSE: Round-trip all nine materialized sources through their immutable runtime archives.
# Materialize, initialize, archive, hash-check, and clean-extract each M×D cell.
# This tests package identity only and does not produce research results.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TMP="$(mktemp -d /tmp/cttrend_3x3_package_test_XXXXXX)"
cleanup() { rm -rf -- "$TMP"; }
trap cleanup EXIT

for id in M0_D0 M0_D1 M0_D2 M1_D0 M1_D1 M1_D2 M2_D0 M2_D1 M2_D2; do
  # Cell-specific temporary roots detect accidental cross-cell reuse.
  src="$TMP/$id/source"
  pkg="$TMP/$id/runtime.tar.gz"
  "$ROOT/scripts/materialize_experiment_source.sh" "$id" "$src" >/dev/null
  BOOTSTRAP_RESULTS_ROOT="$TMP/$id/bootstrap" \
    "$ROOT/scripts/initialize_materialized_source.sh" "$id" "$src" >/dev/null
  case "$id" in
    M0_*|M2_*)
      test -d "$src/.raw_input_seed"
      test "$(find "$src/.raw_input_seed" -maxdepth 1 -type f | wc -l)" -eq 10
      ;;
    M1_*)
      test -L "$src/DATA" && test -L "$src/Results"
      test "$(readlink -f "$src/DATA")" = "$(readlink -f "$ROOT/data/raw/common")"
      ;;
  esac
  "$ROOT/scripts/build_runtime_package.sh" "$id" "$src" "$pkg" >/dev/null
  (cd "$(dirname "$pkg")" && sha256sum -c "$(basename "$pkg").sha256" >/dev/null)
  case "$id" in
    M0_*) expected=cttrend_old_pipeline ;;
    M1_*) expected=cttrend_corrected_pipeline ;;
    M2_*) expected=cttrend_lookahead_only_pipeline ;;
  esac
  test "$(tar -tzf "$pkg" | sed -n '1s#/$##p')" = "$expected"
  test -z "$(tar -tzf "$pkg" | grep -E '/(DATA|Results|logs|\.canonical|\.raw_input_seed)(/|$)' || true)"
  if [[ "$id" == M0_* || "$id" == M2_* ]]; then
    mkdir "$TMP/$id/extracted"
    tar -xzf "$pkg" -C "$TMP/$id/extracted"
    (
      cd "$TMP/$id/extracted/$expected"
      test -s PACKAGE_FILES.sha256
      ! grep -F '  PACKAGE_FILES.sha256' PACKAGE_FILES.sha256
      sha256sum -c PACKAGE_FILES.sha256 >/dev/null
    )
  fi
done
echo 'RUNTIME_PACKAGE_TEST_OK archives=9 initialized_sources=9 sidecars=9 portable_layout=1'
