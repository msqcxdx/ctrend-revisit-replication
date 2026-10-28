#!/usr/bin/env bash
# CTREND_REVISIT_FILE_PURPOSE: Validate every supported M1 b09 profile, range partition, and worker-budget invariant.
set -euo pipefail

RUNNER_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=../b09_profile_lib.sh
source "$RUNNER_DIR/b09_profile_lib.sh"

temporary="$(mktemp -d /tmp/cttrend_b09_profile_test_XXXXXX)"
trap 'rm -rf -- "$temporary"' EXIT

for profile in '4 31' '8 15'; do
  read -r shards workers <<< "$profile"
  cttrend_b09_validate_profile "$shards" "$workers" 2 3072
  root="$temporary/${shards}x${workers}"
  for shard in $(seq 1 "$shards"); do mkdir -p "$root/shard$shard"; done
  cttrend_b09_write_contiguous_ranges "$shards" 2 3072 "$root"
  for shard in $(seq 1 "$shards"); do
    read -r first last < "$root/shard$shard/ranges.txt"
    seq "$first" "$last"
  done > "$root/assigned.txt"
  seq 2 3072 > "$root/expected.txt"
  cmp -s "$root/assigned.txt" "$root/expected.txt"
  [[ "$(wc -l < "$root/assigned.txt")" -eq 3071 ]]
done

if cttrend_b09_validate_profile 8 31 2 3072 2>/dev/null; then
  echo "invalid oversubscribed profile was accepted" >&2
  exit 1
fi

printf 'B09_AUDITED_PROFILES_TEST_OK\n'
