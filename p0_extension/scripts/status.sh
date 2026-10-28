#!/usr/bin/env bash
# CTREND_REVISIT_FILE_PURPOSE: Report P0 registrations and active MATLAB or CTREND production processes without mutating a run.
set -euo pipefail

EXT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ROOT="$(cd "$EXT_ROOT/.." && pwd)"
for id in P0_M1_D0 P0_M1_D1 P0_M1_D2 P0_M2_D0 P0_M2_D1 P0_M2_D2; do
  reg="$ROOT/outputs/experiments/$id/registration.env"
  if [[ -s "$reg" ]]; then
    printf '%s\tREGISTERED\t%s\n' "$id" \
      "$(awk -F= '$1=="run_root"{print $2;exit}' "$reg")"
  else
    printf '%s\tNOT_REGISTERED\n' "$id"
  fi
done
printf '%s\n' 'ACTIVE_PROCESSES'
ps -eo pid,pgid,etimes,pcpu,pmem,cmd | \
  awk '$6 ~ /^(MATLAB|MATLABWorker|matlab)$/ || \
       $0 ~ /run_production\.sh|p0_extension\/scripts\/run_experiment\.sh/ {print}' || true
