#!/usr/bin/env bash
# CTREND_REVISIT_FILE_PURPOSE: Dispatch isolated P0 derivation tests, materialization, production execution, monitoring, and registration.
set -euo pipefail

EXT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COMMAND="${1:-}"
case "$COMMAND" in
  preflight|test) exec "$EXT_ROOT/scripts/preflight.sh" ;;
  materialize)
    exec "$EXT_ROOT/scripts/materialize_experiment_source.sh" \
      "${2:-}" "${3:-}"
    ;;
  experiment)
    exec "$EXT_ROOT/scripts/run_experiment.sh" \
      "${2:-}" "${3:-production}"
    ;;
  launch) exec "$EXT_ROOT/scripts/launch_experiment.sh" "${2:-}" ;;
  status) exec "$EXT_ROOT/scripts/status.sh" ;;
  register)
    exec "$EXT_ROOT/scripts/register_completed_run.sh" "${2:-}" "${3:-}"
    ;;
  *)
    echo "usage: $0 preflight|test|materialize ID ABSOLUTE_OUTPUT|experiment ID [production]|launch ID|status|register ID ABSOLUTE_RUN_ROOT" >&2
    exit 2
    ;;
esac
