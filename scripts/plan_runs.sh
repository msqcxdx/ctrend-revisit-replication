#!/usr/bin/env bash
# CTREND_REVISIT_FILE_PURPOSE: Display all eighteen public P/M/D experiment identities and local registration states.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
printf 'experiment\tpreprocessing\tmethod\tdata\tstatus\n'
while IFS=, read -r id p m d fill parent active; do
  [[ "$id" != experiment_id ]] || continue
  status=NOT_REGISTERED
  [[ ! -s "$ROOT/outputs/experiments/$id/PMD_REGISTRATION.env" ]] || status=REGISTERED
  printf '%s\t%s\t%s\t%s\t%s\n' "$id" "$p" "$m" "$d" "$status"
done < "$ROOT/config/experiments_pmd.csv"
