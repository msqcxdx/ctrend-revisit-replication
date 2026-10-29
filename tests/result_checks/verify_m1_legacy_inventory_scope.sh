#!/usr/bin/env bash
# CTREND_REVISIT_FILE_PURPOSE: Validate the intentional M1 expected-versus-observed inventory scope difference.
# Compatibility is limited to one shell guard that existed physically but was
# omitted by an older glob. Any second difference fails closed.
set -euo pipefail

EXPECTED="${1:-}"
OBSERVED="${2:-}"
RUN_ROOT="${3:-}"
RELATIVE='tests/test_v2_static_guards.sh'

[[ -s "$EXPECTED" && -s "$OBSERVED" && "$RUN_ROOT" == /* && \
   -d "$RUN_ROOT" && -f "$RUN_ROOT/RUN_COMPLETE" ]] || exit 2
RUN_ROOT="$(readlink -f -- "$RUN_ROOT")"

EXPECTED_COUNT="$(awk -v relative="$RELATIVE" '$2==relative{n++} END{print n+0}' \
  "$EXPECTED")"
OBSERVED_COUNT="$(awk -v relative="$RELATIVE" '$2==relative{n++} END{print n+0}' \
  "$OBSERVED")"
[[ "$EXPECTED_COUNT" -eq 1 && "$OBSERVED_COUNT" -eq 0 ]] || exit 1

EXPECTED_SHA="$(awk -v relative="$RELATIVE" '$2==relative{print $1;exit}' \
  "$EXPECTED")"
[[ "$EXPECTED_SHA" =~ ^[0-9a-f]{64}$ ]] || exit 1

TEMP="$(mktemp -d "${TMPDIR:-/tmp}/ctrend_m1_inventory_compat_XXXXXX")"
# Restore only the single omitted row before comparing sorted inventories.
cleanup() { rm -rf -- "$TEMP"; }
trap cleanup EXIT
{
  cat "$OBSERVED"
  printf '%s  %s\n' "$EXPECTED_SHA" "$RELATIVE"
} | awk '{print $2 "\t" $0}' | LC_ALL=C sort -k1,1 | cut -f2- \
  > "$TEMP/normalized.sha256"
cmp -s "$EXPECTED" "$TEMP/normalized.sha256" || exit 1

for inventory in runtime_code_inventory.sha256 \
    source_code_inventory_at_publish.sha256 \
    runtime_code_inventory_at_publish.sha256; do
  [[ -s "$RUN_ROOT/$inventory" ]] || exit 1
  cmp -s "$OBSERVED" "$RUN_ROOT/$inventory" || exit 1
done

RUNTIME_FILE="$RUN_ROOT/runtime/ctrend_corrected_pipeline/$RELATIVE"
[[ -f "$RUNTIME_FILE" && ! -L "$RUNTIME_FILE" ]] || exit 1
[[ "$(sha256sum "$RUNTIME_FILE" | awk '{print $1}')" == "$EXPECTED_SHA" ]] || exit 1

ARCHIVE="$RUN_ROOT/runtime_package.tar.gz"
[[ -f "$ARCHIVE" && ! -L "$ARCHIVE" ]] || exit 1
mapfile -t MEMBERS < <(tar -tzf "$ARCHIVE" | \
  awk -v relative="/$RELATIVE" \
    'length($0)>=length(relative) && substr($0,length($0)-length(relative)+1)==relative')
[[ "${#MEMBERS[@]}" -eq 1 ]] || exit 1
ARCHIVE_SHA="$(tar -xOzf "$ARCHIVE" -- "${MEMBERS[0]}" | sha256sum | awk '{print $1}')"
[[ "$ARCHIVE_SHA" == "$EXPECTED_SHA" ]] || exit 1

value() {
  awk -F= -v key="$1" '$1==key{print substr($0,index($0,"=")+1);exit}' \
    "$RUN_ROOT/RUN_COMPLETE"
}
[[ "$(value source_inventory_sha256)" == \
   "$(sha256sum "$OBSERVED" | awk '{print $1}')" ]] || exit 1
[[ "$(value runtime_inventory_sha256)" == \
   "$(sha256sum "$RUN_ROOT/runtime_code_inventory.sha256" | awk '{print $1}')" ]] || exit 1
[[ "$(value runtime_package_sha256)" == \
   "$(sha256sum "$ARCHIVE" | awk '{print $1}')" ]] || exit 1

printf '%s\n' \
  'format=ctrend-m1-legacy-inventory-compatibility-v1' \
  'mode=tests_subdirectory_shell_omission_v1' \
  "omitted_relative_path=$RELATIVE" \
  "omitted_sha256=$EXPECTED_SHA" \
  "expected_inventory_sha256=$(sha256sum "$EXPECTED" | awk '{print $1}')" \
  "observed_inventory_sha256=$(sha256sum "$OBSERVED" | awk '{print $1}')" \
  "runtime_package_sha256=$(sha256sum "$ARCHIVE" | awk '{print $1}')"
