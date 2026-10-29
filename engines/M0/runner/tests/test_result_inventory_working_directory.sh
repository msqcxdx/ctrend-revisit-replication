#!/usr/bin/env bash
# CTREND_REVISIT_FILE_PURPOSE: Prevent final result inventories from recording paths relative to the wrong working directory.
set -euo pipefail

RUNNER="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/run_production.sh}"
[[ -f "$RUNNER" ]]

# The production command emits paths relative to RESULTS_DIR.  It must also
# execute sha256sum from RESULTS_DIR; otherwise a run launched from any other
# directory fails only after every numerical phase has completed.
inventory_block="$(sed -n '/^[[:space:]]*(/,/) > "\$RUN_ROOT\/results_inventory.sha256"/p' "$RUNNER" | tail -6)"
grep -Fq 'cd "$RESULTS_DIR"' <<< "$inventory_block"
grep -Fq "find . -type f -printf '%P\\0'" <<< "$inventory_block"
grep -Fq 'results_inventory_sha256=$(sha256sum "$RUN_ROOT/results_inventory.sha256"' \
  "$RUNNER"

tmp="$(mktemp -d /tmp/ctrend_old_result_inventory_XXXXXX)"
trap 'rm -rf -- "$tmp"' EXIT
mkdir -p "$tmp/results/CTREND" "$tmp/unrelated"
printf 'alpha\n' > "$tmp/results/CTREND/a.mat"
printf 'beta\n' > "$tmp/results/summary.txt"
(
  cd "$tmp/unrelated"
  (
    cd "$tmp/results"
    find . -type f -printf '%P\0' | LC_ALL=C sort -z |
      xargs -0 -r sha256sum
  ) > "$tmp/results.sha256"
)
[[ "$(wc -l < "$tmp/results.sha256")" -eq 2 ]]
(
  cd "$tmp/results"
  sha256sum -c "$tmp/results.sha256" >/dev/null
)

printf 'OLD_RESULT_INVENTORY_WORKING_DIRECTORY_TEST_OK runner=%s\n' "$RUNNER"
