#!/usr/bin/env bash
# CTREND_REVISIT_FILE_PURPOSE: Verify optional source directories are inventoried when present and safely ignored when absent.
set -euo pipefail

RUNNER_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RELEASE_ROOT="$(cd "$RUNNER_DIR/../replication_release_src" 2>/dev/null && pwd || true)"
T="$(mktemp -d /tmp/cttrend_old_optional_inventory_XXXXXX)"
trap 'rm -rf "$T"' EXIT

mkdir -p "$T/source/Utils" "$T/source/LatexTables"
printf 'root\n' > "$T/source/root.m"
printf 'utils\n' > "$T/source/Utils/u.m"
printf 'latex\n' > "$T/source/LatexTables/l.m"
[[ ! -e "$T/source/tests" ]]

(
  cd "$T/source"
  printf '%s\n' LatexTables/l.m Utils/u.m root.m | while IFS= read -r file; do
    sha256sum "$file"
  done
) > "$T/expected.sha256"

check_inventory_function() {
  local script="$1"
  local function_name="$2"
  local extracted="$T/$(basename "$script").${function_name}.sh"
  local actual="$extracted.actual"

  sed -n "/^${function_name}()/,/^}/p" "$script" > "$extracted"
  grep -Fq "${function_name}()" "$extracted"
  # shellcheck disable=SC1090
  source "$extracted"
  "$function_name" "$T/source" > "$actual"
  cmp -s "$T/expected.sha256" "$actual" || {
    diff -u "$T/expected.sha256" "$actual" >&2 || true
    echo "optional-directory inventory mismatch: $script" >&2
    exit 1
  }
}

for script in \
    "$RUNNER_DIR/run_production.sh" \
    "$RUNNER_DIR/launch_b09_shards.sh" \
    "$RUNNER_DIR/run_b09_shard.sh" \
    "$RUNNER_DIR/build_b09_remote_payload.sh" \
    "$RUNNER_DIR/run_b09_remote_worker.sh"; do
  if [[ "$script" == *run_production.sh ]]; then
    check_inventory_function "$script" write_source_inventory
  else
    check_inventory_function "$script" write_runtime_source_inventory
  fi
  ! grep -Eq '\[\[ -d "\$[^\"]+" \]\] && find' "$script"
  ! grep -Eq 'find Utils LatexTables tests' "$script"
done

if [[ -n "$RELEASE_ROOT" && -f "$RELEASE_ROOT/scripts/run_portable_engine.sh" ]]; then
  check_inventory_function "$RELEASE_ROOT/scripts/run_portable_engine.sh" \
    write_source_inventory
  ! grep -Eq '\[\[ -d "\$[^\"]+" \]\] && find' \
    "$RELEASE_ROOT/scripts/run_portable_engine.sh"
fi

echo OLD_OPTIONAL_SOURCE_INVENTORY_TEST_OK
