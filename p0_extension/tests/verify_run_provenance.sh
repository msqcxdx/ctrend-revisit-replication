#!/usr/bin/env bash
# CTREND_REVISIT_FILE_PURPOSE: Check immutable method, data, runtime, topology, and causal-gate fields in RUN_COMPLETE.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
ID="${1:-}"
RUN_ROOT="${2:-}"
case "$ID" in
  P0_M0_D0|P0_M0_D1|P0_M0_D2|P0_M1_D0|P0_M1_D1|P0_M1_D2|P0_M2_D0|P0_M2_D1|P0_M2_D2)
    IFS=_ read -r PREPROCESSING_ID METHOD DATA_ID <<< "$ID"
    ;;
  *) exit 2 ;;
esac
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
RUN_ID="$(value research_run_id "$MARKER")"
[[ "$RUN_ID" =~ ^[0-9a-fA-F-]{36}$ ]] || exit 1

FORMAT="$(value format "$MARKER")"

# A run may be internally immutable yet still have been produced by a
# different source release.  Materialize this package's frozen M/D engine and
# require the launch-time source inventory to match it exactly.  The E1 reuse
# route is handled separately above because its historical control shell/tests
# differ while its scientific MATLAB code is checked before reuse.
EXPECTED_PARENT="$(mktemp -d "${TMPDIR:-/tmp}/cttrend_expected_engine_XXXXXX")"
cleanup_expected() { rm -rf -- "$EXPECTED_PARENT"; }
trap cleanup_expected EXIT
EXPECTED_SOURCE="$EXPECTED_PARENT/source"
"$ROOT/p0_extension/scripts/materialize_experiment_source.sh" "$ID" \
  "$EXPECTED_SOURCE" >/dev/null
EXPECTED_INVENTORY="$EXPECTED_SOURCE.materialized-executable.sha256"
if [[ "$METHOD" == M0 || "$METHOD" == M2 ]]; then
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
PROVENANCE_COMPATIBILITY_MARKER="$RUN_ROOT/P0_EXPERIMENT_PROVENANCE_COMPATIBILITY.env"
if ! cmp -s "$EXPECTED_INVENTORY" "$OBSERVED_SOURCE_INVENTORY"; then
  echo "run executable source differs from frozen P0 package engine for $ID" >&2
  diff -u "$EXPECTED_INVENTORY" "$OBSERVED_SOURCE_INVENTORY" >&2 || true
  exit 1
fi

STARTED="$RUN_ROOT/RUN_STARTED.env"
[[ -s "$STARTED" ]] || { echo 'RUN_STARTED.env is missing' >&2; exit 1; }
require_value "$STARTED" research_run_id "$RUN_ID"

if [[ "$METHOD" == M0 || "$METHOD" == M2 ]]; then
  if [[ "$METHOD" == M0 ]]; then
    EXPECTED_COMPLETE_FORMAT=cttrend-published-method-run-complete-v1
    EXPECTED_STARTED_FORMAT=cttrend-published-method-run-started-v1
    EXPECTED_VARIANT=v1
    EXPECTED_RUNTIME_ROOT=cttrend_old_pipeline
  else
    EXPECTED_COMPLETE_FORMAT=cttrend-lookahead-only-run-complete-v1
    EXPECTED_STARTED_FORMAT=cttrend-lookahead-only-run-started-v1
    EXPECTED_VARIANT=m2
    EXPECTED_RUNTIME_ROOT=cttrend_lookahead_only_pipeline
  fi
  require_value "$MARKER" format "$EXPECTED_COMPLETE_FORMAT"
  require_value "$MARKER" complete 1
  require_value "$MARKER" old_pipeline_variant "$EXPECTED_VARIANT"
  require_value "$MARKER" b02_execution_topology parallel_asset_chunks
  require_value "$MARKER" b02_serial_parallel_equivalence_test pass
  if [[ "$METHOD" == M2 ]]; then
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
  [[ -s "$B09" && -s "$B09.sha256" ]] || exit 1
  (cd "$(dirname "$B09")" && sha256sum -c "$(basename "$B09").sha256" >/dev/null)
  require_value "$B09" format cttrend-old-v2-complete-b09-manifest-v1
  require_value "$B09" research_run_id "$RUN_ID"
  require_value "$B09" combo_files 3072
  require_value "$B09" digest_files 3072
  require_value "$B09" execution_topology local_full_8x15
  require_value "$B09" physical_sources 8
  require_value "$B09" package_sha256 "$(value package_sha256 "$MARKER")"
  require_value "$B09" data_inputs_sha256 "$(value data_inputs_sha256 "$MARKER")"
  require_value "$B09" design_choices_sha256 "$(value design_choices_sha256 "$MARKER")"
else
  require_value "$MARKER" format cttrend-run-complete-v1
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
  (cd "$RUN_ROOT/runtime/cttrend_corrected_pipeline" && \
    sha256sum -c "$RUN_ROOT/runtime_code_inventory_at_publish.sha256" >/dev/null)
  DATA="$RUN_ROOT/data"; RESULTS="$RUN_ROOT/results"
  [[ -d "$DATA" && -d "$RESULTS" ]] || exit 1
  (cd "$DATA" && sha256sum -c "$RUN_ROOT/raw_inputs.sha256" >/dev/null)
fi

if [[ -n "$PROVENANCE_COMPATIBILITY_EVIDENCE" ]]; then
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
