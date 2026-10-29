#!/usr/bin/env bash
# CTREND_REVISIT_FILE_PURPOSE: Build and inspect all six P0 runtime archives without starting MATLAB or modifying the frozen parent.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
EXT_ROOT="$ROOT/p0_extension"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/ctrend_p0_packages_XXXXXX")"
cleanup() { rm -rf -- "$TMP"; }
trap cleanup EXIT

count=0
for method in M0 M1 M2; do
  for data_id in D0 D1 D2; do
    id="P0_${method}_${data_id}"
    legacy_id="${method}_${data_id}"
    source="$TMP/sources/$id/source"
    archive="$TMP/packages/$id.tar.gz"
    "$EXT_ROOT/scripts/materialize_experiment_source.sh" \
      "$id" "$source" >/dev/null
    BOOTSTRAP_RESULTS_ROOT="$TMP/bootstrap/$id" \
      "$ROOT/scripts/initialize_materialized_source.sh" \
        "$legacy_id" "$source" >/dev/null
    "$ROOT/scripts/build_runtime_package.sh" \
      "$legacy_id" "$source" "$archive" >/dev/null
    (cd "$(dirname "$archive")" && \
      sha256sum -c "$(basename "$archive").sha256" >/dev/null)

    if [[ "$method" == M1 ]]; then
      package_name=ctrend_corrected_pipeline
    elif [[ "$method" == M2 ]]; then
      package_name=ctrend_lookahead_only_pipeline
    else
      package_name=ctrend_old_pipeline
    fi
    extract="$TMP/extracted/$id"
    mkdir -p "$extract"
    tar -xzf "$archive" -C "$extract"
    runtime="$extract/$package_name"
    test -d "$runtime/Utils"
    test -f "$runtime/b01ReadData.m"
    cmp -s "$source/b01ReadData.m" "$runtime/b01ReadData.m"
    test ! -e "$runtime/DATA"
    test ! -e "$runtime/Results"
    test ! -e "$runtime/.raw_input_seed"
    ((count += 1))
  done
done

echo "P0_RUNTIME_PACKAGE_TEST_OK archives=$count initialized_sources=$count p0_b01_bound=1"
