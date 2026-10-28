#!/usr/bin/env bash
# CTREND_REVISIT_FILE_PURPOSE: Stop only the process group owned by a declared remote b09 worker and preserve its state.
set -euo pipefail

if [[ "$#" -ne 1 ]]; then
  echo "usage: $0 REMOTE_ROOT" >&2
  exit 2
fi
REMOTE_ROOT="$1"
PID_FILE="$REMOTE_ROOT/state/remote_wrapper.pid"
[[ "$REMOTE_ROOT" == /* && "$REMOTE_ROOT" =~ ^[A-Za-z0-9_./-]+$ &&
   -f "$PID_FILE" ]] || exit 0
pid="$(<"$PID_FILE")"
[[ "$pid" =~ ^[1-9][0-9]*$ ]] || exit 0
kill -TERM -- "-$pid" 2>/dev/null || kill -TERM "$pid" 2>/dev/null || true
