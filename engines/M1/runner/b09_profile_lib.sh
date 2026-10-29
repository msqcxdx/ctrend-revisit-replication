#!/usr/bin/env bash
# CTREND_REVISIT_FILE_PURPOSE: Define the audited local b09 client ranges, worker counts, and profile-validation helpers.

ctrend_b09_validate_profile() {
  local shards="$1" workers="$2" first="$3" last="$4"
  case "$shards:$workers:$first:$last" in
    4:31:2:3072|8:15:2:3072) return 0 ;;
    *) echo "unsupported audited b09 launch profile" >&2; return 2 ;;
  esac
}

ctrend_b09_write_contiguous_ranges() {
  local shards="$1" first="$2" last="$3" run_root="$4"
  local total base remainder start shard count finish
  [[ "$shards" =~ ^[1-9][0-9]*$ && "$first" =~ ^[1-9][0-9]*$ &&
     "$last" =~ ^[1-9][0-9]*$ && "$first" -le "$last" ]] || return 2
  total=$((last - first + 1))
  (( total >= shards )) || return 2
  base=$((total / shards))
  remainder=$((total % shards))
  start="$first"
  for shard in $(seq 1 "$shards"); do
    count="$base"
    (( shard <= remainder )) && count=$((count + 1))
    finish=$((start + count - 1))
    printf '%d %d\n' "$start" "$finish" > "$run_root/shard$shard/ranges.txt"
    start=$((finish + 1))
  done
  (( start == last + 1 ))
}
