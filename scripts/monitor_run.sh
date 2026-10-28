#!/usr/bin/env bash
# CTREND_REVISIT_FILE_PURPOSE: Report the marker, phase, process, and b09 file counts of one run root without modifying it.
set -euo pipefail
RUN_ROOT="${1:-}"
[[ -d "$RUN_ROOT" ]] || { echo "usage: $0 RUN_ROOT" >&2; exit 2; }
echo "timestamp=$(date -Is)"
echo "run_root=$(readlink -f "$RUN_ROOT")"
for marker in RUN_STARTED.env RUN_COMPLETE RUN_FAILED.env FULL_FAILED.env; do
  [[ ! -f "$RUN_ROOT/$marker" ]] || {
    echo "marker=$marker"
    sed -n '1,80p' "$RUN_ROOT/$marker"
  }
done
RESULTS="$RUN_ROOT/results.staging"
[[ -d "$RESULTS" ]] || RESULTS="$RUN_ROOT/results"
[[ -d "$RESULTS" ]] || RESULTS="$RUN_ROOT/runtime/code/Results"
if [[ -d "$RESULTS/CTREND" ]]; then
  echo "combo_mat=$(find "$RESULTS/CTREND" -maxdepth 1 -type f -name 'CTREND_Combo*.mat' | wc -l)"
  echo "combo_sha=$(find "$RESULTS/CTREND" -maxdepth 1 -type f -name 'CTREND_Combo*.mat.sha256' | wc -l)"
fi
if [[ -d "$RUN_ROOT/b09_shards" ]]; then
  find "$RUN_ROOT/b09_shards" -type f \
    \( -name heartbeat.env -o -name completion.env -o -name state.env \) \
    -printf '%p\n' | LC_ALL=C sort | while IFS= read -r file; do
      echo "--- $file"
      sed -n '1,50p' "$file"
    done
fi
ps -eo pid,pgid,etimes,pcpu,pmem,stat,cmd | \
  awk -v root="$RUN_ROOT" 'index($0,root)>0 || $7 ~ /MATLAB|MATLABWorker/ {print}' || true
