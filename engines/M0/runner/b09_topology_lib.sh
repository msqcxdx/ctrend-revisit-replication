#!/usr/bin/env bash
# CTREND_REVISIT_FILE_PURPOSE: Define and validate the complete disjoint b09 shard topology and global combo coverage.

# Sourced helper for the frozen old-v2 b09 execution topologies.
# The research grid is identical under both contracts; only its physical
# scheduling differs.

B09_LOCAL_LOGICAL_SHARD=1
B09_REMOTE_LOGICAL_SHARD=2
B09_LOCAL_SUBSHARDS=4
B09_REMOTE_SUBSHARDS=1
B09_LOCAL_FIRST_COMBO=1
B09_LOCAL_LAST_COMBO=1536
B09_REMOTE_FIRST_COMBO=1537
B09_REMOTE_LAST_COMBO=3072
B09_TOTAL_COMBOS=3072

cttrend_b09_validate_topology() {
  local topology_file="$1"
  local expected_file="$2"
  [[ -f "$topology_file" && -f "$expected_file" ]] || {
    echo "b09 topology file is missing" >&2
    return 2
  }
  cmp -s "$topology_file" "$expected_file" || {
    echo "b09 topology differs from the selected frozen contract" >&2
    return 2
  }
}

cttrend_b09_topology_template() {
  local mode="$1"
  local runner_dir="$2"
  case "$mode" in
    two_host) printf '%s\n' "$runner_dir/b09_two_shard_topology.tsv" ;;
    local_full_8x15) printf '%s\n' "$runner_dir/b09_local_full_8x15_topology.tsv" ;;
    *) echo "invalid old-v2 b09 topology mode: $mode" >&2; return 2 ;;
  esac
}

cttrend_b09_source_rows() {
  local topology_file="$1"
  tail -n +2 "$topology_file"
}

cttrend_b09_local_rows() {
  local topology_file="$1"
  awk -F '\t' 'NR > 1 && $2 == 1 && $3 == "local" { print }' \
    "$topology_file"
}

cttrend_b09_remote_rows() {
  local topology_file="$1"
  awk -F '\t' 'NR > 1 && $2 == 2 && $3 == "remote" { print }' \
    "$topology_file"
}
