#!/usr/bin/env bash
# CTREND_REVISIT_FILE_PURPOSE: Dispatch package tests, production experiments, monitoring, and suite acceptance from one stable CLI.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COMMAND="${1:-}"
EXPERIMENTS=()
for p in P0 P1; do
  for m in M0 M2 M1; do
    for d in D0 D1 D2; do EXPERIMENTS+=("${p}_${m}_${d}"); done
  done
done

run_all_experiments() {
  local mode="$1" id registration
  [[ -z "${RUN_ROOT:-}" && -z "${JOB_STORAGE_ROOT:-}" ]] || {
    echo 'all/all-fresh do not accept a shared RUN_ROOT or JOB_STORAGE_ROOT.' >&2
    echo 'Set only RUN_BASE and WORK_BASE; each experiment creates isolated paths.' >&2
    return 2
  }
  for id in "${EXPERIMENTS[@]}"; do
    registration="$ROOT/outputs/experiments/$id/PMD_REGISTRATION.env"
    if [[ -s "$registration" ]]; then
      python3 "$ROOT/scripts/verify_pmd_registrations.py" "$id"
      echo "SKIP_REGISTERED experiment=$id"
      continue
    fi
    "$ROOT/scripts/run_pmd_experiment.sh" "$id" "$mode"
  done
}

case "$COMMAND" in
  preflight) exec "$ROOT/scripts/preflight.sh" ;;
  test) exec "$ROOT/tests/run_tests.sh" ;;
  plan) exec "$ROOT/scripts/plan_runs.sh" ;;
  experiment)
    if [[ "${2:-}" == P* ]]; then
      exec "$ROOT/scripts/run_pmd_experiment.sh" "${2:-}" "${3:-production}"
    fi
    exec "$ROOT/scripts/run_experiment.sh" "${2:-}" "${3:-production}"
    ;;
  launch)
    if [[ "${2:-}" == P* ]]; then exec "$ROOT/scripts/launch_pmd_experiment.sh" "${2:-}"; fi
    exec "$ROOT/scripts/launch_experiment.sh" "${2:-}"
    ;;
  status) exec "$ROOT/scripts/status.sh" ;;
  verify-all) exec python3 "$ROOT/scripts/verify_pmd_registrations.py" ;;
  b19) exec "$ROOT/postprocessing/run_b19_common_week_robustness.sh" "${2:-}" ;;
  b20)
    if [[ "${2:-}" == --from-registrations ]]; then
      [[ $# -eq 3 ]] || { echo 'usage: run_all.sh b20 --from-registrations ABSOLUTE_FRESH_OUTPUT_DIR' >&2; exit 2; }
      exec "${PYTHON_BIN:-python3}" "$ROOT/scripts/report_registered_runs.py" "$3"
    fi
    [[ $# -eq 1 ]] || exit 2
    exec "$ROOT/postprocessing/b20EighteenCellAblation.sh"
    ;;
  assignment) exec "$ROOT/scripts/run_assignment.sh" "${2:-}" "${3:-}" ;;
  all|all-fresh) run_all_experiments "${2:-production}" ;;
  *)
    echo "usage: $0 preflight|test|plan|experiment ID [production]|launch ID|status|verify-all|b19 ABSOLUTE_OUTPUT_DIR|b20 [--from-registrations ABSOLUTE_FRESH_OUTPUT_DIR]|assignment HOST CSV|all [production]|all-fresh [production]" >&2
    exit 2
    ;;
esac
