#!/usr/bin/env bash
# CTREND_REVISIT_FILE_PURPOSE: Prove that a completed M1 recovery differs from the current engine only by the superseded Figure B.2 validator and its static guard.
# Normalize exactly two declared test paths, authenticate their prior bytes and
# recovery controller, then require every other inventory entry to match.
set -euo pipefail

EXPECTED="${1:-}"
OBSERVED="${2:-}"
RUN_ROOT="${3:-}"
FIGURE_TEST='tests/test_figure_b2_results.m'
STATIC_GUARD='tests/test_v2_static_guards.sh'
OLD_FIGURE_SHA='5c8f49f29a6f710745c54122d43033adc1d908aa560e80fc6762c0295105b5d0'
OLD_STATIC_GUARD_SHA='98e15b5aa2ae19b85f6cb2271203e50c7d973f02effc873eefe07e9745294fc1'
RECOVERY_CONTROLLER_SHA='85f1f1a695eea317ea82b90729ac4b5f4b2b565e242186f6110b83cbbf5d6774'

[[ -s "$EXPECTED" && -s "$OBSERVED" && "$RUN_ROOT" == /* && \
   -d "$RUN_ROOT" && -f "$RUN_ROOT/RUN_COMPLETE" ]] || exit 2
RUN_ROOT="$(readlink -f -- "$RUN_ROOT")"

inventory_sha() {
  local inventory="$1" relative="$2"
  awk -v relative="$relative" '$2==relative{print $1;exit}' "$inventory"
}
inventory_count() {
  local inventory="$1" relative="$2"
  awk -v relative="$relative" '$2==relative{n++} END{print n+0}' "$inventory"
}
value() {
  local file="$1" key="$2"
  awk -F= -v key="$key" \
    '$1==key{print substr($0,index($0,"=")+1);exit}' "$file"
}

for relative in "$FIGURE_TEST" "$STATIC_GUARD"; do
  # Each exceptional path must occur exactly once in both inventories.
  [[ "$(inventory_count "$EXPECTED" "$relative")" -eq 1 && \
     "$(inventory_count "$OBSERVED" "$relative")" -eq 1 ]] || exit 1
done

EXPECTED_FIGURE_SHA="$(inventory_sha "$EXPECTED" "$FIGURE_TEST")"
# Expected inventory uses current validators; the run inventory contains sealed old ones.
EXPECTED_STATIC_GUARD_SHA="$(inventory_sha "$EXPECTED" "$STATIC_GUARD")"
OBSERVED_FIGURE_SHA="$(inventory_sha "$OBSERVED" "$FIGURE_TEST")"
OBSERVED_STATIC_GUARD_SHA="$(inventory_sha "$OBSERVED" "$STATIC_GUARD")"
[[ "$EXPECTED_FIGURE_SHA" =~ ^[0-9a-f]{64}$ && \
   "$EXPECTED_STATIC_GUARD_SHA" =~ ^[0-9a-f]{64}$ && \
   "$OBSERVED_FIGURE_SHA" == "$OLD_FIGURE_SHA" && \
   "$OBSERVED_STATIC_GUARD_SHA" == "$OLD_STATIC_GUARD_SHA" ]] || exit 1

# Normalize only the two declared validator paths.  Exact equality after this
# substitution proves that no scientific MATLAB file, runner, or other test
# differs between the immutable run and the current frozen engine.
TEMP="$(mktemp -d "${TMPDIR:-/tmp}/ctrend_m1_figure_b2_compat_XXXXXX")"
cleanup() { rm -rf -- "$TEMP"; }
trap cleanup EXIT
awk -v figure="$FIGURE_TEST" -v figure_sha="$EXPECTED_FIGURE_SHA" \
    -v guard="$STATIC_GUARD" -v guard_sha="$EXPECTED_STATIC_GUARD_SHA" \
    '{
       if ($2==figure) $1=figure_sha;
       if ($2==guard) $1=guard_sha;
       printf "%s  %s\n",$1,$2;
     }' "$OBSERVED" > "$TEMP/normalized.sha256"
cmp -s "$EXPECTED" "$TEMP/normalized.sha256" || exit 1

# All publish-time inventories must describe the same sealed runtime tree.
for inventory in runtime_code_inventory.sha256 \
    source_code_inventory_at_publish.sha256 \
    runtime_code_inventory_at_publish.sha256; do
  [[ -s "$RUN_ROOT/$inventory" ]] || exit 1
  cmp -s "$OBSERVED" "$RUN_ROOT/$inventory" || exit 1
done

# Authenticate both exceptional files in the extracted runtime and original archive.
for pair in "$FIGURE_TEST:$OLD_FIGURE_SHA" \
    "$STATIC_GUARD:$OLD_STATIC_GUARD_SHA"; do
  relative="${pair%%:*}"
  expected_old_sha="${pair##*:}"
  runtime_file="$RUN_ROOT/runtime/ctrend_corrected_pipeline/$relative"
  [[ -f "$runtime_file" && ! -L "$runtime_file" && \
     "$(sha256sum "$runtime_file" | awk '{print $1}')" == \
       "$expected_old_sha" ]] || exit 1
done

ARCHIVE="$RUN_ROOT/runtime_package.tar.gz"
[[ -f "$ARCHIVE" && ! -L "$ARCHIVE" ]] || exit 1
for pair in "$FIGURE_TEST:$OLD_FIGURE_SHA" \
    "$STATIC_GUARD:$OLD_STATIC_GUARD_SHA"; do
  relative="${pair%%:*}"
  expected_old_sha="${pair##*:}"
  mapfile -t members < <(tar -tzf "$ARCHIVE" | awk -v suffix="/$relative" \
    'length($0)>=length(suffix) && substr($0,length($0)-length(suffix)+1)==suffix')
  [[ "${#members[@]}" -eq 1 ]] || exit 1
  archive_sha="$(tar -xOzf "$ARCHIVE" -- "${members[0]}" | \
    sha256sum | awk '{print $1}')"
  [[ "$archive_sha" == "$expected_old_sha" ]] || exit 1
done

MARKER="$RUN_ROOT/RUN_COMPLETE"
STARTED="$RUN_ROOT/RUN_STARTED.env"
[[ -s "$STARTED" ]] || exit 1
RUN_ID="$(value "$MARKER" research_run_id)"
[[ "$RUN_ID" =~ ^[0-9a-fA-F-]{36}$ && \
   "$(value "$STARTED" research_run_id)" == "$RUN_ID" && \
   "$(value "$MARKER" source_inventory_sha256)" == \
     "$(sha256sum "$OBSERVED" | awk '{print $1}')" && \
   "$(value "$MARKER" runtime_inventory_sha256)" == \
     "$(sha256sum "$RUN_ROOT/runtime_code_inventory.sha256" | awk '{print $1}')" && \
   "$(value "$MARKER" runtime_package_sha256)" == \
     "$(sha256sum "$ARCHIVE" | awk '{print $1}')" ]] || exit 1

RECOVERY_DIR="$RUN_ROOT/logs/post_b09_dynamic_figure_b2_recovery"
# Evidence must prove no b00–b09 rerun and a successful dynamic validator.
RECOVERY="$RECOVERY_DIR/recovery.env"
RESULT_LOG="$RUN_ROOT/logs/result_invariants/pipeline.log"
RESULT_SEAL="$RUN_ROOT/logs/result_invariants/phase.complete.env"
[[ -s "$RECOVERY" && -s "$RESULT_LOG" && -s "$RESULT_SEAL" ]] || exit 1
[[ "$(value "$RECOVERY" format)" == \
     ctrend-m1-dynamic-figure-b2-post-b09-recovery-v1 && \
   "$(value "$RECOVERY" research_run_id)" == "$RUN_ID" && \
   "$(value "$RECOVERY" rerun_b00_b09)" == 0 && \
   "$(value "$RECOVERY" verified_b09_payloads)" == 3072 && \
   "$(value "$RECOVERY" old_validator_sha256)" == "$OLD_FIGURE_SHA" && \
   "$(value "$RECOVERY" fixed_validator_sha256)" == "$EXPECTED_FIGURE_SHA" && \
   "$(value "$RECOVERY" original_orchestrator_sha256)" == \
     "$(value "$STARTED" orchestrator_sha256)" && \
   "$(value "$RECOVERY" recovery_controller_sha256)" == \
     "$RECOVERY_CONTROLLER_SHA" && \
   "$(value "$RESULT_SEAL" rc)" == 0 && \
   "$(value "$RESULT_SEAL" group_empty)" == 1 ]] || exit 1

rg -q '^B05_B09_BASELINE_RESULT_TEST_OK setting=517 method=C_ENET_SCS$' \
  "$RESULT_LOG" || exit 1
rg -q '^FIGURE_B2_RESULT_TEST_OK .*dynamic_rebuild=1 zero_gap_disclosed=1$' \
  "$RESULT_LOG" || exit 1

# Preserve exactly one superseded failure whose message matches this known issue.
mapfile -t OLD_LOGS < <(find "$RECOVERY_DIR" -mindepth 2 -maxdepth 2 \
  -type f -path '*/result_invariants_superseded_failure_*/pipeline.log' | \
  LC_ALL=C sort)
mapfile -t OLD_SEALS < <(find "$RECOVERY_DIR" -mindepth 2 -maxdepth 2 \
  -type f -path '*/result_invariants_superseded_failure_*/phase.complete.env' | \
  LC_ALL=C sort)
[[ "${#OLD_LOGS[@]}" -eq 1 && "${#OLD_SEALS[@]}" -eq 1 && \
   "$(value "${OLD_SEALS[0]}" rc)" == 1 && \
   "$(value "${OLD_SEALS[0]}" group_empty)" == 1 ]] || exit 1
rg -q 'Figure B\.2 does not disclose the expected zero-increment gap segments' \
  "${OLD_LOGS[0]}" || exit 1

# Emit normalized compatibility evidence for the caller to seal into the run root.
printf '%s\n' \
  'format=ctrend-m1-dynamic-figure-b2-recovery-compatibility-v1' \
  'mode=dynamic_figure_b2_validator_recovery_v1' \
  "changed_relative_paths=$FIGURE_TEST,$STATIC_GUARD" \
  "old_figure_validator_sha256=$OBSERVED_FIGURE_SHA" \
  "current_figure_validator_sha256=$EXPECTED_FIGURE_SHA" \
  "old_static_guard_sha256=$OBSERVED_STATIC_GUARD_SHA" \
  "current_static_guard_sha256=$EXPECTED_STATIC_GUARD_SHA" \
  "expected_inventory_sha256=$(sha256sum "$EXPECTED" | awk '{print $1}')" \
  "observed_inventory_sha256=$(sha256sum "$OBSERVED" | awk '{print $1}')" \
  "runtime_package_sha256=$(sha256sum "$ARCHIVE" | awk '{print $1}')" \
  "recovery_evidence_sha256=$(sha256sum "$RECOVERY" | awk '{print $1}')" \
  "dynamic_result_log_sha256=$(sha256sum "$RESULT_LOG" | awk '{print $1}')" \
  "dynamic_result_seal_sha256=$(sha256sum "$RESULT_SEAL" | awk '{print $1}')"
