#!/usr/bin/env bash
# CTREND_REVISIT_FILE_PURPOSE: Validate the M0/M2 8-client by 15-worker b09 topology and full 1-to-3072 coverage.
set -euo pipefail

RUNNER_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TOPOLOGY="$RUNNER_DIR/b09_two_shard_topology.tsv"
LOCAL_TOPOLOGY="$RUNNER_DIR/b09_local_full_8x15_topology.tsv"

# shellcheck source=../b09_topology_lib.sh
source "$RUNNER_DIR/b09_topology_lib.sh"
[[ "$(ctrend_b09_topology_template two_host "$RUNNER_DIR")" == \
   "$TOPOLOGY" ]]
[[ "$(ctrend_b09_topology_template local_full_8x15 "$RUNNER_DIR")" == \
   "$LOCAL_TOPOLOGY" ]]

awk -F '\t' '
  NR == 1 {
    if ($0 != "source_label\tlogical_shard\texecution_site\tfirst_combo\tlast_combo") exit 1
    next
  }
  {
    if ($4 != expected) exit 1
    expected = $5 + 1
    count += $5-$4+1
    rows++
  }
  END {
    if (rows != 5 || count != 3072 || expected != 3073) exit 1
  }
' expected=1 "$TOPOLOGY"

awk -F '\t' 'NR>1 && $2==1 {n++; c += $5-$4+1} END{exit !(n==4 && c==1536)}' "$TOPOLOGY"
awk -F '\t' 'NR>1 && $2==2 {n++; c += $5-$4+1} END{exit !(n==1 && c==1536 && $4==1537 && $5==3072)}' "$TOPOLOGY"

awk -F '\t' '
  NR == 1 {
    if ($0 != "source_label\tlogical_shard\texecution_site\tfirst_combo\tlast_combo") exit 1
    next
  }
  {
    if ($2 != 1 || $3 != "local" || $4 != expected) exit 1
    expected = $5 + 1
    count += $5-$4+1
    if ($5-$4+1 != 384) exit 1
    rows++
  }
  END {
    if (rows != 8 || count != 3072 || expected != 3073) exit 1
  }
' expected=1 "$LOCAL_TOPOLOGY"
[[ "$(ctrend_b09_local_rows "$LOCAL_TOPOLOGY" | wc -l)" -eq 8 ]]
[[ "$(ctrend_b09_remote_rows "$LOCAL_TOPOLOGY" | wc -l)" -eq 0 ]]

if ctrend_b09_topology_template unsupported "$RUNNER_DIR" >/dev/null 2>&1; then
  echo "unsupported topology mode was accepted" >&2
  exit 1
fi

grep -Fq 'local_full_8x15:8:15:1:3072' \
  "$RUNNER_DIR/launch_b09_shards.sh"
grep -Fq 'OLD_V1_B09_FIRST_COMBO' "$RUNNER_DIR/run_b09_shard.sh"
grep -Fq 'OLD_V2_B09_FIRST_COMBO' "$RUNNER_DIR/run_b09_shard.sh"
[[ -f "$RUNNER_DIR/tests/test_b02_parallel_equivalence.m" ]]

"$RUNNER_DIR/tests/test_optional_source_inventory_dirs.sh"

echo OLD_V2_TOPOLOGY_TEST_OK
