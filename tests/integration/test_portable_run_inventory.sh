#!/usr/bin/env bash
# CTREND_REVISIT_FILE_PURPOSE: Test the uniform nine-cell relocation-safe DATA inventory and tamper rejection.
# Inventory a synthetic run, relocate it, revalidate it, then mutate one member.
# This proves hashes bind relative content rather than a host-specific path.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TMP="$(mktemp -d /tmp/cttrend_portable_inventory_XXXXXX)"
cleanup() { rm -rf -- "$TMP"; }
trap cleanup EXIT
RUN_A="$TMP/worker_run"
RUN_B="$TMP/main_run"
RUN_C="$TMP/m2_run"
mkdir -p "$RUN_A/data.staging"
printf 'format=cttrend-published-method-run-complete-v1\n' > "$RUN_A/RUN_COMPLETE"
printf 'alpha\n' > "$RUN_A/data.staging/a.txt"
mkdir "$RUN_A/data.staging/nested"
printf 'beta\n' > "$RUN_A/data.staging/nested/b.txt"
"$ROOT/scripts/write_portable_run_inventories.sh" M0_D0 "$RUN_A" >/dev/null
# Relocation must preserve validity because returned runs change absolute roots.
(cd "$RUN_A/data.staging" && sha256sum -c "$RUN_A/NINE_EXPERIMENT_DATA_INVENTORY.sha256" >/dev/null)
mv "$RUN_A" "$RUN_B"
(cd "$RUN_B/data.staging" && sha256sum -c "$RUN_B/NINE_EXPERIMENT_DATA_INVENTORY.sha256" >/dev/null)
[[ "$(wc -l < "$RUN_B/NINE_EXPERIMENT_DATA_INVENTORY.sha256")" -eq 2 ]]
printf 'tampered\n' >> "$RUN_B/data.staging/nested/b.txt"
# Existing inventories are immutable commitments and cannot be silently rewritten.
if "$ROOT/scripts/write_portable_run_inventories.sh" M0_D0 "$RUN_B" \
    >"$TMP/tamper.out" 2>"$TMP/tamper.err"; then
  echo 'portable inventory accepted a modified DATA member' >&2
  exit 1
fi
grep -F 'existing portable DATA inventory differs' "$TMP/tamper.err" >/dev/null
mkdir -p "$RUN_C/data.staging"
printf 'format=cttrend-lookahead-only-run-complete-v1\n' > "$RUN_C/RUN_COMPLETE"
printf 'gamma\n' > "$RUN_C/data.staging/c.txt"
"$ROOT/scripts/write_portable_run_inventories.sh" M2_D0 "$RUN_C" >/dev/null
(cd "$RUN_C/data.staging" && sha256sum -c "$RUN_C/NINE_EXPERIMENT_DATA_INVENTORY.sha256" >/dev/null)
test ! -e "$RUN_C/2X3_DATA_INVENTORY.sha256"
test ! -e "$RUN_C/3X3_DATA_INVENTORY.sha256"
echo 'PORTABLE_RUN_INVENTORY_TEST_OK files=2 relocation=1 tamper_rejected=1 uniform_nine_schema=1'
