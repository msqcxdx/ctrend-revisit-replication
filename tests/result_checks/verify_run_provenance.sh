#!/usr/bin/env bash
# CTREND_REVISIT_FILE_PURPOSE: Check immutable method, data, runtime, topology, and causal-gate fields in RUN_COMPLETE.
# Authenticate launch/completion identities, executable source, DATA/Results
# inventories, topology, MATLAB version, and method-specific causal gates.
# Compatibility is admitted only through separately sealed M1 validators.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
ID="${1:-}"
RUN_ROOT="${2:-}"
case "$ID" in M0_D0|M0_D1|M0_D2|M1_D0|M1_D1|M1_D2|M2_D0|M2_D1|M2_D2) ;; *) exit 2;; esac
[[ "$RUN_ROOT" == /* && -d "$RUN_ROOT" && -f "$RUN_ROOT/RUN_COMPLETE" ]] || exit 2
RUN_ROOT="$(readlink -f -- "$RUN_ROOT")"
MARKER="$RUN_ROOT/RUN_COMPLETE"
value() { awk -F= -v key="$1" '$1==key{print substr($0,index($0,"=")+1);exit}' "$2"; }
require_value() {
  local file="$1" key="$2" expected="$3" observed
  observed="$(value "$key" "$file")"
  [[ "$observed" == "$expected" ]] || {
    echo "provenance mismatch file=$file key=$key expected=$expected observed=$observed" >&2
    exit 1
  }
}
require_hash_field() {
  local field="$1" file="$2" expected observed
  [[ -f "$file" ]] || { echo "missing provenance member: $file" >&2; exit 1; }
  expected="$(value "$field" "$MARKER")"
  observed="$(sha256sum "$file" | awk '{print $1}')"
  [[ "$expected" =~ ^[0-9a-f]{64}$ && "$observed" == "$expected" ]] || {
    echo "provenance hash mismatch field=$field file=$file" >&2
    exit 1
  }
}

[[ ! -e "$RUN_ROOT/RUN_FAILED.env" && ! -e "$RUN_ROOT/RUN_PUBLICATION_FAILED.env" ]] || {
  echo 'completed run retains an active failure marker' >&2; exit 1;
}
# Active failure markers invalidate completion even if RUN_COMPLETE also exists.
RUN_ID="$(value research_run_id "$MARKER")"
[[ "$RUN_ID" =~ ^[0-9a-fA-F-]{36}$ ]] || exit 1

FORMAT="$(value format "$MARKER")"
# E1 is a portable reuse of an independently sealed M1_D0 full run.
if [[ "$FORMAT" == ctrend-e1-full-complete-v1 ]]; then
  require_value "$MARKER" experiment_id E1_raw_cmc_retain_3787
  require_value "$MARKER" combo_count 3072
  require_value "$MARKER" combo_sidecar_count 3072
  require_value "$MARKER" b09_shards 8
  require_value "$MARKER" b09_workers_per_shard 15
  [[ ! -e "$RUN_ROOT/FULL_FAILED.env" ]] || exit 1
  REUSE="$RUN_ROOT/2X3_E1_REUSE_PROVENANCE.env"
  CORE_SNAPSHOT="$RUN_ROOT/2X3_E1_PARENT_CORE_COMPLETE"
  RAW_SNAPSHOT="$RUN_ROOT/2X3_E1_RAW_SOURCE.manifest.tsv"
  SCIENTIFIC_SNAPSHOT="$RUN_ROOT/2X3_E1_SCIENTIFIC_SOURCE.sha256"
  [[ -s "$REUSE" && -s "$CORE_SNAPSHOT" && -s "$RAW_SNAPSHOT" && \
     -s "$SCIENTIFIC_SNAPSHOT" ]] || {
    echo 'portable E1 reuse provenance is incomplete' >&2; exit 1;
  }
  require_value "$REUSE" format ctrend-e1-reuse-provenance-v1
  require_value "$REUSE" target_experiment_id M1_D0
  require_value "$REUSE" source_experiment_id E1_raw_cmc_retain_3787
  require_value "$REUSE" research_run_id "$RUN_ID"
  require_value "$REUSE" data_build_id "$(value data_build_id "$MARKER")"
  for item in \
    parent_core_complete_sha256:"$CORE_SNAPSHOT" \
    raw_source_manifest_sha256:"$RAW_SNAPSHOT" \
    scientific_source_inventory_sha256:"$SCIENTIFIC_SNAPSHOT"; do
    field="${item%%:*}"; file="${item#*:}"
    [[ "$(value "$field" "$REUSE")" == \
       "$(sha256sum "$file" | awk '{print $1}')" ]] || exit 1
  done
  require_value "$CORE_SNAPSHOT" format ctrend-core-complete-v2
  require_value "$CORE_SNAPSHOT" experiment_id E1_raw_cmc_retain_3787
  require_value "$CORE_SNAPSHOT" engine corrected_v2
  require_value "$CORE_SNAPSHOT" raw_adjustment_mode none
  require_value "$CORE_SNAPSHOT" exclude_asset_id ''
  require_value "$CORE_SNAPSHOT" research_run_id "$RUN_ID"
  require_value "$CORE_SNAPSHOT" data_build_id "$(value data_build_id "$MARKER")"
  EXPECTED_E1_FINGERPRINT=e6b7e83bec5c976594652c8d8412edaed3b4035ccfd71d7ab8f1a2642d8a1deb
  require_value "$REUSE" code_fingerprint "$EXPECTED_E1_FINGERPRINT"
  require_value "$CORE_SNAPSHOT" code_fingerprint "$EXPECTED_E1_FINGERPRINT"
  [[ "$(value raw_manifest_sha256 "$CORE_SNAPSHOT")" == \
     "$(sha256sum "$RAW_SNAPSHOT" | awk '{print $1}')" ]] || exit 1
  source "$ROOT/scripts/core_provenance_lib.sh"
  core_verify_manifest_members "$ROOT/data/raw/common" "$RAW_SNAPSHOT" || {
    echo 'current package raw inputs differ from the sealed E1 source' >&2
    exit 1
  }
  [[ "$(value package_raw_inventory_sha256 "$REUSE")" == \
     "$(sha256sum "$ROOT/data/RAW_INPUTS.sha256" | awk '{print $1}')" ]] || exit 1

  EXPECTED_PARENT="$(mktemp -d "${TMPDIR:-/tmp}/ctrend_expected_e1_XXXXXX")"
  cleanup_e1_expected() { rm -rf -- "$EXPECTED_PARENT"; }
  trap cleanup_e1_expected EXIT
  EXPECTED_SOURCE="$EXPECTED_PARENT/source"
  "$ROOT/scripts/materialize_experiment_source.sh" M1_D0 "$EXPECTED_SOURCE" \
    >/dev/null
  (
    cd "$EXPECTED_SOURCE"
    find . -type f -name '*.m' ! -path './tests/*' ! -path './audit/*' \
      -printf '%P\0' | LC_ALL=C sort -z | xargs -0 -r sha256sum
  ) > "$EXPECTED_PARENT/scientific.sha256"
  cmp -s "$EXPECTED_PARENT/scientific.sha256" "$SCIENTIFIC_SNAPSHOT" || {
    echo 'current M1_D0 scientific source differs from sealed E1 reuse source' >&2
    exit 1
  }

  RESULTS="$RUN_ROOT/runtime/code/Results"
  [[ -d "$RESULTS" && -s "$RUN_ROOT/Results.full.manifest.tsv" ]] || exit 1
  [[ "$(value results_manifest_sha256 "$MARKER")" == \
     "$(sha256sum "$RUN_ROOT/Results.full.manifest.tsv" | awk '{print $1}')" ]] || exit 1
  core_verify_manifest_members "$RESULTS" "$RUN_ROOT/Results.full.manifest.tsv"
  echo "RUN_PROVENANCE_OK experiment=$ID format=$FORMAT external_reuse=1 research_run_id=$RUN_ID"
  exit 0
fi

# A run may be internally immutable yet still have been produced by a
# different source release.  Materialize this package's frozen M/D engine and
# require the launch-time source inventory to match it exactly.  The E1 reuse
# route is handled separately above because its historical control shell/tests
# differ while its scientific MATLAB code is checked before reuse.
EXPECTED_PARENT="$(mktemp -d "${TMPDIR:-/tmp}/ctrend_expected_engine_XXXXXX")"
cleanup_expected() { rm -rf -- "$EXPECTED_PARENT"; }
trap cleanup_expected EXIT
EXPECTED_SOURCE="$EXPECTED_PARENT/source"
"$ROOT/scripts/materialize_experiment_source.sh" "$ID" "$EXPECTED_SOURCE" \
  >/dev/null
EXPECTED_INVENTORY="$EXPECTED_SOURCE.materialized-executable.sha256"
if [[ "$ID" == M0_* || "$ID" == M2_* ]]; then
  # M0 and M2 share the old-style runner but expose distinct formats/variants.
  OBSERVED_SOURCE_INVENTORY="$RUN_ROOT/source_code_after.sha256"
else
  OBSERVED_SOURCE_INVENTORY="$RUN_ROOT/source_code_inventory.sha256"
fi
[[ -s "$OBSERVED_SOURCE_INVENTORY" ]] || {
  echo "run source inventory is missing: $OBSERVED_SOURCE_INVENTORY" >&2
  exit 1
}
PROVENANCE_COMPATIBILITY_EVIDENCE=''
PROVENANCE_COMPATIBILITY_VALIDATOR=''
PROVENANCE_COMPATIBILITY_FORMAT=''
PROVENANCE_COMPATIBILITY_MODE=''
PROVENANCE_COMPATIBILITY_MARKER="$RUN_ROOT/NINE_EXPERIMENT_PROVENANCE_COMPATIBILITY.env"
if ! cmp -s "$EXPECTED_INVENTORY" "$OBSERVED_SOURCE_INVENTORY"; then
  # Two explicitly sealed M1 compatibility routes exist: the first public
  # inventory omitted one physically present shell guard, and the 2026-08-29
  # post-b09 recovery replaced only a sample-specific Figure B.2 validator and
  # its static guard.  Each route independently proves its exact file scope,
  # archived bytes, recovery evidence, and RUN_COMPLETE bindings.  Every other
  # difference remains fail-closed.
  if [[ "$ID" == M1_* ]]; then
    PROVENANCE_COMPATIBILITY_EVIDENCE="$EXPECTED_PARENT/source_inventory_compatibility.env"
    if "$ROOT/tests/result_checks/verify_m1_legacy_inventory_scope.sh" \
        "$EXPECTED_INVENTORY" "$OBSERVED_SOURCE_INVENTORY" "$RUN_ROOT" \
        > "$PROVENANCE_COMPATIBILITY_EVIDENCE"; then
      PROVENANCE_COMPATIBILITY_VALIDATOR="$ROOT/tests/result_checks/verify_m1_legacy_inventory_scope.sh"
      PROVENANCE_COMPATIBILITY_FORMAT=ctrend-m1-legacy-inventory-compatibility-v1
      PROVENANCE_COMPATIBILITY_MODE=tests_subdirectory_shell_omission_v1
    elif "$ROOT/tests/result_checks/verify_m1_dynamic_figure_b2_recovery_scope.sh" \
        "$EXPECTED_INVENTORY" "$OBSERVED_SOURCE_INVENTORY" "$RUN_ROOT" \
        > "$PROVENANCE_COMPATIBILITY_EVIDENCE"; then
      PROVENANCE_COMPATIBILITY_VALIDATOR="$ROOT/tests/result_checks/verify_m1_dynamic_figure_b2_recovery_scope.sh"
      PROVENANCE_COMPATIBILITY_FORMAT=ctrend-m1-dynamic-figure-b2-recovery-compatibility-v1
      PROVENANCE_COMPATIBILITY_MODE=dynamic_figure_b2_validator_recovery_v1
    else
      echo "run executable source differs from frozen package engine for $ID" >&2
      diff -u "$EXPECTED_INVENTORY" "$OBSERVED_SOURCE_INVENTORY" >&2 || true
      exit 1
    fi
  else
    echo "run executable source differs from frozen package engine for $ID" >&2
    diff -u "$EXPECTED_INVENTORY" "$OBSERVED_SOURCE_INVENTORY" >&2 || true
    exit 1
  fi
fi

STARTED="$RUN_ROOT/RUN_STARTED.env"
# Fresh M0/M2 and M1 runners expose different markers and are checked separately.
[[ -s "$STARTED" ]] || { echo 'RUN_STARTED.env is missing' >&2; exit 1; }
require_value "$STARTED" research_run_id "$RUN_ID"

if [[ "$ID" == M0_* || "$ID" == M2_* ]]; then
  if [[ "$ID" == M0_* ]]; then
    EXPECTED_COMPLETE_FORMAT=ctrend-published-method-run-complete-v1
    EXPECTED_STARTED_FORMAT=ctrend-published-method-run-started-v1
    EXPECTED_VARIANT=v1
    EXPECTED_RUNTIME_ROOT=ctrend_old_pipeline
  else
    EXPECTED_COMPLETE_FORMAT=ctrend-lookahead-only-run-complete-v1
    EXPECTED_STARTED_FORMAT=ctrend-lookahead-only-run-started-v1
    EXPECTED_VARIANT=m2
    EXPECTED_RUNTIME_ROOT=ctrend_lookahead_only_pipeline
  fi
  require_value "$MARKER" format "$EXPECTED_COMPLETE_FORMAT"
  require_value "$MARKER" complete 1
  require_value "$MARKER" old_pipeline_variant "$EXPECTED_VARIANT"
  require_value "$MARKER" b02_execution_topology parallel_asset_chunks
  require_value "$MARKER" b02_serial_parallel_equivalence_test pass
  if [[ "$ID" == M2_* ]]; then
    require_value "$MARKER" m2_causal_contract_test pass
  fi
  require_value "$MARKER" b09_combo_files 3072
  require_value "$MARKER" b09_execution_topology local_full_8x15
  require_value "$MARKER" b09_shards 8
  require_value "$MARKER" b09_workers_per_shard 15
  require_value "$STARTED" format "$EXPECTED_STARTED_FORMAT"
  require_value "$STARTED" old_pipeline_variant "$EXPECTED_VARIANT"
  require_value "$STARTED" b09_execution_topology local_full_8x15

  require_hash_field package_sha256 "$RUN_ROOT/runtime_package.tar.gz"
  require_hash_field results_inventory_sha256 "$RUN_ROOT/results_inventory.sha256"
  require_hash_field data_inputs_sha256 "$RUN_ROOT/data_after_b02.sha256"
  require_hash_field design_choices_sha256 \
    "$RUN_ROOT/runtime/$EXPECTED_RUNTIME_ROOT/DesignChoices.mat"

  # Before/after inventories prove code, raw inputs, and b02 DATA stayed immutable.
  for pair in \
    source_code_before.sha256:source_code_after.sha256 \
    runtime_code_before.sha256:runtime_code_after.sha256 \
    runner_source_before.sha256:runner_source_after.sha256 \
    runner_sealed_before.sha256:runner_sealed_after.sha256 \
    raw_source_before.sha256:raw_source_after.sha256 \
    data_after_b02.sha256:data_after_run.sha256; do
    before="${pair%%:*}"; after="${pair##*:}"
    cmp -s "$RUN_ROOT/$before" "$RUN_ROOT/$after" || {
      echo "$ID before/after provenance differs: $before $after" >&2; exit 1;
    }
  done
  cmp -s "$RUN_ROOT/raw_source_before.sha256" \
    "$RUN_ROOT/raw_snapshot_before.sha256" || {
    echo "$ID raw source and run-local snapshot differ" >&2; exit 1;
  }
  (cd "$RUN_ROOT/runtime/$EXPECTED_RUNTIME_ROOT" && \
    sha256sum -c "$RUN_ROOT/runtime_code_after.sha256" >/dev/null)
  (cd "$RUN_ROOT/runtime/b09_parallel_runner_old_v2" && \
    sha256sum -c "$RUN_ROOT/runner_sealed_after.sha256" >/dev/null)
  DATA="$RUN_ROOT/data.staging"
  [[ -d "$DATA" ]] || DATA="$RUN_ROOT/data"
  (cd "$DATA" && sha256sum -c "$RUN_ROOT/raw_snapshot_before.sha256" >/dev/null)

  RESULTS="$RUN_ROOT/results.staging"
  [[ -d "$RESULTS" ]] || RESULTS="$RUN_ROOT/results"
  B09="$RESULTS/CTREND/ResearchDesignRunManifest.env"
  # Bind the merged grid to this run, package, DATA, and DesignChoices.
  [[ -s "$B09" && -s "$B09.sha256" ]] || exit 1
  (cd "$(dirname "$B09")" && sha256sum -c "$(basename "$B09").sha256" >/dev/null)
  require_value "$B09" format ctrend-old-v2-complete-b09-manifest-v1
  require_value "$B09" research_run_id "$RUN_ID"
  require_value "$B09" combo_files 3072
  require_value "$B09" digest_files 3072
  require_value "$B09" execution_topology local_full_8x15
  require_value "$B09" physical_sources 8
  require_value "$B09" package_sha256 "$(value package_sha256 "$MARKER")"
  require_value "$B09" data_inputs_sha256 "$(value data_inputs_sha256 "$MARKER")"
  require_value "$B09" design_choices_sha256 "$(value design_choices_sha256 "$MARKER")"
else
  # M1 records every phase, 8×15 topology, and atomic publication commitments.
  require_value "$MARKER" format ctrend-run-complete-v1
  for key in unit_tests_rc core_phase_rc baseline_downstream_rc \
      canonical_combo1_rc b09_shards_rc b09_merge_rc b10_rc supplementary_rc; do
    require_value "$MARKER" "$key" 0
  done
  require_value "$MARKER" b09_combo_count 3072
  require_value "$MARKER" b09_shards 8
  require_value "$MARKER" b09_workers_per_shard 15
  require_value "$MARKER" b09_total_workers 120
  require_value "$MARKER" b09_processes_plus_clients 128
  require_value "$MARKER" matlab_release 2023b
  require_value "$MARKER" publication_protocol complete-marker-then-atomic-bundle-swap-v1
  [[ "$(value matlab_version "$MARKER")" == *'R2023b'*'Update 11'* ]] || exit 1

  require_hash_field runtime_package_sha256 "$RUN_ROOT/runtime_package.tar.gz"
  require_hash_field runner_source_inventory_sha256 "$RUN_ROOT/runner_source_inventory.sha256"
  require_hash_field runner_snapshot_inventory_sha256 "$RUN_ROOT/runner_snapshot_inventory.sha256"
  require_hash_field source_inventory_sha256 "$RUN_ROOT/source_code_inventory.sha256"
  require_hash_field runtime_inventory_sha256 "$RUN_ROOT/runtime_code_inventory.sha256"
  require_hash_field raw_input_inventory_sha256 "$RUN_ROOT/raw_inputs.sha256"
  require_hash_field raw_input_sources_sha256 "$RUN_ROOT/raw_input_sources.tsv"
  require_hash_field raw_source_publish_inventory_sha256 \
    "$RUN_ROOT/raw_input_sources_at_publish.sha256"
  require_hash_field data_before_inventory_sha256 "$RUN_ROOT/data_before.sha256"
  require_hash_field data_after_inventory_sha256 "$RUN_ROOT/data_after.sha256"
  require_hash_field results_inventory_sha256 "$RUN_ROOT/results.sha256"
  require_hash_field status_inventory_sha256 "$RUN_ROOT/status_inventory.sha256"
  require_hash_field matlab_environment_sha256 "$RUN_ROOT/MATLAB_ENVIRONMENT.txt"
  require_hash_field design_choices_sha256 "$RUN_ROOT/DesignChoices.mat"
  require_value "$MARKER" result_file_count "$(wc -l < "$RUN_ROOT/results.sha256")"

  (cd "$RUN_ROOT" && sha256sum -c status_inventory.sha256 >/dev/null)
  (cd "$RUN_ROOT/runtime/ctrend_corrected_pipeline" && \
    sha256sum -c "$RUN_ROOT/runtime_code_inventory_at_publish.sha256" >/dev/null)
  DATA="$RUN_ROOT/data"; RESULTS="$RUN_ROOT/results"
  [[ -d "$DATA" && -d "$RESULTS" ]] || exit 1
  (cd "$DATA" && sha256sum -c "$RUN_ROOT/raw_inputs.sha256" >/dev/null)
fi

if [[ -n "$PROVENANCE_COMPATIBILITY_EVIDENCE" ]]; then
  # Bind the successful exceptional proof atomically to this RUN_COMPLETE.
  COMPATIBILITY_VALIDATOR="$PROVENANCE_COMPATIBILITY_VALIDATOR"
  COMPATIBILITY_VALIDATOR_SHA="$(sha256sum "$COMPATIBILITY_VALIDATOR" | awk '{print $1}')"
  RUN_COMPLETE_SHA="$(sha256sum "$MARKER" | awk '{print $1}')"
  if [[ ! -e "$PROVENANCE_COMPATIBILITY_MARKER" ]]; then
    COMPATIBILITY_TMP="${PROVENANCE_COMPATIBILITY_MARKER}.tmp.$$"
    {
      cat "$PROVENANCE_COMPATIBILITY_EVIDENCE"
      echo "experiment_id=$ID"
      echo "research_run_id=$RUN_ID"
      echo "run_complete_sha256=$RUN_COMPLETE_SHA"
      echo "compatibility_validator_sha256=$COMPATIBILITY_VALIDATOR_SHA"
      echo "accepted_at_utc=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    } > "$COMPATIBILITY_TMP"
    mv -Tf -- "$COMPATIBILITY_TMP" "$PROVENANCE_COMPATIBILITY_MARKER"
  else
    require_value "$PROVENANCE_COMPATIBILITY_MARKER" format \
      "$PROVENANCE_COMPATIBILITY_FORMAT"
    require_value "$PROVENANCE_COMPATIBILITY_MARKER" mode \
      "$PROVENANCE_COMPATIBILITY_MODE"
    require_value "$PROVENANCE_COMPATIBILITY_MARKER" experiment_id "$ID"
    require_value "$PROVENANCE_COMPATIBILITY_MARKER" research_run_id "$RUN_ID"
    require_value "$PROVENANCE_COMPATIBILITY_MARKER" run_complete_sha256 \
      "$RUN_COMPLETE_SHA"
    require_value "$PROVENANCE_COMPATIBILITY_MARKER" compatibility_validator_sha256 \
      "$COMPATIBILITY_VALIDATOR_SHA"
    while IFS='=' read -r key expected; do
      [[ -n "$key" ]] || continue
      require_value "$PROVENANCE_COMPATIBILITY_MARKER" "$key" "$expected"
    done < "$PROVENANCE_COMPATIBILITY_EVIDENCE"
  fi
  echo "RUN_PROVENANCE_OK experiment=$ID format=$FORMAT research_run_id=$RUN_ID compatibility=$PROVENANCE_COMPATIBILITY_MODE"
else
  [[ ! -e "$PROVENANCE_COMPATIBILITY_MARKER" ]] || {
    echo 'stale provenance compatibility marker exists for an exact-inventory run' >&2
    exit 1
  }
  echo "RUN_PROVENANCE_OK experiment=$ID format=$FORMAT research_run_id=$RUN_ID compatibility=exact"
fi
