#!/usr/bin/env bash
# CTREND_REVISIT_FILE_PURPOSE: run pmd experiment; publication orchestration, validation or saved-result analysis, not a model-definition edit.
# Dispatch one P/M/D cell to its frozen scientific implementation and bind its
# public identity to the inner engine registration. No array is transformed here.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ID="${1:-}"
MODE="${2:-production}"
[[ "$ID" =~ ^P[01]_M[012]_D[012]$ && "$MODE" == production ]] || {
  echo 'usage: run_pmd_experiment.sh P{0,1}_M{0,1,2}_D{0,1,2} production' >&2
  exit 2
}
IFS=_ read -r PREPROCESSING METHOD DATA_ID <<< "$ID"
if [[ "$PREPROCESSING" == P0 ]]; then
  DRIVER="$ROOT/p0_extension/scripts/run_experiment.sh"
  INNER_ID="$ID"
else
  DRIVER="$ROOT/scripts/run_experiment.sh"
  INNER_ID="${METHOD}_${DATA_ID}"
fi
if [[ "${CTREND_PLAN_ONLY:-0}" == 1 ]]; then
  printf 'experiment_id=%s preprocessing=%s inner_id=%s driver=%s\n' \
    "$ID" "$PREPROCESSING" "$INNER_ID" "${DRIVER#"$ROOT"/}"
  exit 0
fi
WORK_BASE="${WORK_BASE:-$ROOT/runtime}"
RUN_BASE="${RUN_BASE:-$ROOT/outputs/experiments/$ID/runs}"
[[ "$WORK_BASE" == /* && "$RUN_BASE" == /* ]] || exit 2
mkdir -p "$WORK_BASE/locks"
# Both P branches share this outer lock. Existing inner locks remain intact.
exec 9>"$WORK_BASE/locks/pmd_production.lock"
flock -n 9 || { echo 'another P/M/D production task owns this host lock' >&2; exit 2; }
PUBLIC="$ROOT/outputs/experiments/$ID/PMD_REGISTRATION.env"
[[ ! -e "$PUBLIC" ]] || { echo "already registered: $ID" >&2; exit 2; }
export WORK_BASE RUN_BASE
"$DRIVER" "$INNER_ID" "$MODE"
INNER="$ROOT/outputs/experiments/$INNER_ID/registration.env"
[[ -s "$INNER" ]] || { echo 'inner acceptance did not publish registration' >&2; exit 1; }
mkdir -p "$(dirname "$PUBLIC")"
TMP="${PUBLIC}.tmp.$$"
{
  echo 'format=ctrend-pmd-wrapper-registration-v1'
  echo "experiment_id=$ID"
  echo "preprocessing_id=$PREPROCESSING"
  echo "inner_experiment_id=$INNER_ID"
  echo "inner_registration_relative=outputs/experiments/$INNER_ID/registration.env"
  echo "inner_registration_sha256=$(sha256sum "$INNER" | awk '{print $1}')"
} > "$TMP"
mv -T "$TMP" "$PUBLIC"
echo "PMD_EXPERIMENT_ACCEPTED experiment=$ID registration=$PUBLIC"
