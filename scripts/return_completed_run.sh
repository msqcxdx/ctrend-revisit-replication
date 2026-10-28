#!/usr/bin/env bash
# CTREND_REVISIT_FILE_PURPOSE: Transfer an already verified complete run root while preserving its portable inventories.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ID="${1:-}"
RUN_ROOT="${2:-}"
DESTINATION="${3:-}"
SSH_PORT="${SSH_PORT:-22}"
case "$ID" in M0_D0|M0_D1|M0_D2|M1_D0|M1_D1|M1_D2|M2_D0|M2_D1|M2_D2) ;; *) exit 2;; esac
[[ "$RUN_ROOT" == /* && -d "$RUN_ROOT" && -n "$DESTINATION" ]] || {
  echo "usage: $0 EXPERIMENT_ID /absolute/run/root user@host:/absolute/parent/" >&2
  exit 2
}
"$ROOT/tests/result_checks/verify_completed_run.sh" "$ID" "$RUN_ROOT"
rsync -avP --partial --append-verify -e "ssh -p $SSH_PORT" \
  "$RUN_ROOT/" "$DESTINATION/$(basename "$RUN_ROOT")/"
echo "RUN_RETURNED experiment=$ID source=$RUN_ROOT destination=$DESTINATION/$(basename "$RUN_ROOT")/"
