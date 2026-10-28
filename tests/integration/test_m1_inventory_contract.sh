#!/usr/bin/env bash
# CTREND_REVISIT_FILE_PURPOSE: Prevent M1 source inventories from silently omitting required shell tests or executable files.
# Cover the current complete inventory and two narrowly sealed compatibility
# validators. Any extra omission or changed physical/archived guard must fail.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
HELPER="$ROOT/tests/result_checks/verify_m1_legacy_inventory_scope.sh"
FIGURE_RECOVERY_HELPER="$ROOT/tests/result_checks/verify_m1_dynamic_figure_b2_recovery_scope.sh"
RUNNERS=(
  "$ROOT/engines/M1/runner/run_production.sh"
  "$ROOT/engines/M1/runner/launch_b09_shards.sh"
  "$ROOT/engines/M1/runner/run_b09_shard.sh"
)

# Prove both compatibility validators are wired into acceptance and registration.
[[ -x "$FIGURE_RECOVERY_HELPER" ]]
grep -F 'dynamic_figure_b2_validator_recovery_v1' \
  "$FIGURE_RECOVERY_HELPER" >/dev/null
grep -F 'verify_m1_dynamic_figure_b2_recovery_scope.sh' \
  "$ROOT/tests/result_checks/verify_run_provenance.sh" >/dev/null
grep -F 'cttrend-m1-dynamic-figure-b2-recovery-compatibility-v1' \
  "$ROOT/tests/result_checks/verify_completed_run.sh" >/dev/null
grep -F 'cttrend-m1-dynamic-figure-b2-recovery-compatibility-v1' \
  "$ROOT/scripts/register_completed_run.sh" >/dev/null

for runner in "${RUNNERS[@]}"; do
  # All executable MATLAB and shell tests must enter before/after inventories.
  grep -F "find Utils LatexTables tests -type f" "$runner" >/dev/null
  grep -F "\( -name '*.m' -o -name '*.sh' \)" "$runner" >/dev/null
  if grep -F "find Utils LatexTables tests -type f -name '*.m'" \
      "$runner" >/dev/null; then
    echo "legacy M1 inventory scope remains in $runner" >&2
    exit 1
  fi
done

TEMP="$(mktemp -d "${TMPDIR:-/tmp}/cttrend_m1_inventory_test_XXXXXX")"
# Build a minimal immutable run fixture for adversarial compatibility checks.
cleanup() { rm -rf -- "$TEMP"; }
trap cleanup EXIT
RUN="$TEMP/run"
RUNTIME="$RUN/runtime/cttrend_corrected_pipeline"
RELATIVE=tests/test_v2_static_guards.sh
mkdir -p "$RUNTIME/tests"
printf '%s\n' '#!/usr/bin/env bash' 'echo guard' > "$RUNTIME/$RELATIVE"
GUARD_SHA="$(sha256sum "$RUNTIME/$RELATIVE" | awk '{print $1}')"

printf '%064d  a.m\n' 0 > "$TEMP/observed.sha256"
{
  cat "$TEMP/observed.sha256"
  printf '%s  %s\n' "$GUARD_SHA" "$RELATIVE"
} | awk '{print $2 "\t" $0}' | LC_ALL=C sort -k1,1 | cut -f2- \
  > "$TEMP/expected.sha256"
for inventory in source_code_inventory.sha256 runtime_code_inventory.sha256 \
    source_code_inventory_at_publish.sha256 \
    runtime_code_inventory_at_publish.sha256; do
  cp "$TEMP/observed.sha256" "$RUN/$inventory"
done
tar -C "$RUN/runtime" -czf "$RUN/runtime_package.tar.gz" \
  cttrend_corrected_pipeline
{
  echo 'format=cttrend-run-complete-v1'
  echo "source_inventory_sha256=$(sha256sum "$TEMP/observed.sha256" | awk '{print $1}')"
  echo "runtime_inventory_sha256=$(sha256sum "$RUN/runtime_code_inventory.sha256" | awk '{print $1}')"
  echo "runtime_package_sha256=$(sha256sum "$RUN/runtime_package.tar.gz" | awk '{print $1}')"
} > "$RUN/RUN_COMPLETE"

# Positive case: exactly the historical one-file omission is admissible.
"$HELPER" "$TEMP/expected.sha256" "$TEMP/observed.sha256" "$RUN" \
  > "$TEMP/evidence.env"
grep -F 'format=cttrend-m1-legacy-inventory-compatibility-v1' \
  "$TEMP/evidence.env" >/dev/null
grep -F 'mode=tests_subdirectory_shell_omission_v1' \
  "$TEMP/evidence.env" >/dev/null

# Negative cases: an extra path, changed physical guard, or changed archive fails.
cp "$TEMP/expected.sha256" "$TEMP/extra_difference.sha256"
printf '%064d  z.m\n' 1 >> "$TEMP/extra_difference.sha256"
if "$HELPER" "$TEMP/extra_difference.sha256" \
    "$TEMP/observed.sha256" "$RUN" >/dev/null 2>&1; then
  echo 'compatibility helper accepted an additional inventory difference' >&2
  exit 1
fi

printf '%s\n' 'mutated guard' > "$RUNTIME/$RELATIVE"
if "$HELPER" "$TEMP/expected.sha256" "$TEMP/observed.sha256" "$RUN" \
    >/dev/null 2>&1; then
  echo 'compatibility helper accepted a mutated physical guard' >&2
  exit 1
fi
printf '%s\n' '#!/usr/bin/env bash' 'echo guard' > "$RUNTIME/$RELATIVE"

printf '%s\n' 'mutated archive guard' > "$RUNTIME/$RELATIVE"
tar -C "$RUN/runtime" -czf "$RUN/runtime_package.tar.gz" \
  cttrend_corrected_pipeline
printf '%s\n' '#!/usr/bin/env bash' 'echo guard' > "$RUNTIME/$RELATIVE"
sed -i "s/^runtime_package_sha256=.*/runtime_package_sha256=$(sha256sum "$RUN/runtime_package.tar.gz" | awk '{print $1}')/" \
  "$RUN/RUN_COMPLETE"
if "$HELPER" "$TEMP/expected.sha256" "$TEMP/observed.sha256" "$RUN" \
    >/dev/null 2>&1; then
  echo 'compatibility helper accepted a mutated archived guard' >&2
  exit 1
fi

echo 'M1_INVENTORY_CONTRACT_TEST_OK'
