#!/usr/bin/env bash
# CTREND_REVISIT_FILE_PURPOSE: List experiment registrations and active CTREND or MATLAB production processes.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
while IFS=, read -r id rest; do
  [[ "$id" != experiment_id ]] || continue
  reg="$ROOT/outputs/experiments/$id/PMD_REGISTRATION.env"
  if [[ -s "$reg" ]]; then
    inner="$(awk -F= '$1=="inner_registration_relative"{print $2;exit}' "$reg")"
    printf '%s\tREGISTERED\t%s\n' "$id" \
      "$(awk -F= '$1=="run_root"{print $2;exit}' "$ROOT/$inner")"
  else
    printf '%s\tNOT_REGISTERED\n' "$id"
  fi
done < "$ROOT/config/experiments_pmd.csv"
printf '%s\n' 'ACTIVE_PROCESSES'
ps -eo pid,pgid,etimes,pcpu,pmem,cmd | \
  awk '$6 ~ /^(MATLAB|MATLABWorker|matlab)$/ || \
       $0 ~ /run_production\.sh|run_experiment\.sh/ {print}' || true
