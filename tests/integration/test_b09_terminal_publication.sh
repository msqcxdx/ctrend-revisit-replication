#!/usr/bin/env bash
# CTREND_REVISIT_FILE_PURPOSE: Prove that b09 completion is atomically published, identity-bound, and never inferred from advisory state or command-line text.
# The fixture fabricates shard state in a disposable directory and exercises
# each method's real terminal-state helper. Only a hash-bound completion marker
# may authorize publication; heartbeat text and process arguments are advisory.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TMP="$(mktemp -d /tmp/ctrend_b09_terminal_publication_XXXXXX)"
DECOY_PID=""
cleanup() {
  local rc=$?
  trap - EXIT INT TERM
  if [[ "$DECOY_PID" =~ ^[1-9][0-9]*$ ]]; then
    kill "$DECOY_PID" 2>/dev/null || true
    wait "$DECOY_PID" 2>/dev/null || true
  fi
  rm -rf -- "$TMP"
  exit "$rc"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

RUN_ID=11111111-2222-4333-8444-555555555555

exercise_protocol() {
  # Run the same state-machine attacks against one method-specific helper.
  local helper="$1" label="$2" shard
  local observed
  shard="$TMP/$label"
  mkdir -p "$shard"
  # shellcheck source=/dev/null
  source "$helper"

  printf 'state=COMPLETE\nupdated_epoch=100\n' > "$shard/state.env"
  observed="$(ctrend_b09_observed_terminal_state "$shard" "$RUN_ID" 30 110)"
  [[ "$observed" == FINALIZING ]]
  observed="$(ctrend_b09_observed_terminal_state "$shard" "$RUN_ID" 30 130)"
  [[ "$observed" == FAILED_MISSING_COMPLETION_RECORD ]]

  printf 'state=RUNNING\nupdated_epoch=120\n' > "$shard/state.env"
  {
    printf 'format=ctrend-shard-complete-v1\n'
    printf 'complete=1\n'
    printf 'research_run_id=%s\n' "$RUN_ID"
  } > "$shard/completion.env"
  observed="$(ctrend_b09_observed_terminal_state "$shard" "$RUN_ID" 30 121)"
  [[ "$observed" == COMPLETE ]]

  sed -i 's/11111111-2222-4333-8444-555555555555/aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee/' \
    "$shard/completion.env"
  observed="$(ctrend_b09_observed_terminal_state "$shard" "$RUN_ID" 30 121)"
  [[ "$observed" == FAILED_INVALID_COMPLETION_RECORD ]]

  rm -- "$shard/completion.env"
  printf 'state=FAILED\nupdated_epoch=121\n' > "$shard/state.env"
  observed="$(ctrend_b09_observed_terminal_state "$shard" "$RUN_ID" 30 121)"
  [[ "$observed" == FAILED ]]
}

exercise_protocol "$ROOT/engines/M0/runner/b09_completion_protocol.sh" m0
exercise_protocol "$ROOT/engines/M2/runner/b09_completion_protocol.sh" m2
cmp -s "$ROOT/engines/M0/runner/b09_completion_protocol.sh" \
  "$ROOT/engines/M2/runner/b09_completion_protocol.sh"

python3 - "$ROOT" <<'PY'
from pathlib import Path
import sys

root = Path(sys.argv[1])
for method in ("M0", "M1", "M2"):
    path = root / "engines" / method / "runner" / "run_b09_shard.sh"
    text = path.read_text(encoding="utf-8")
    zero = text.split("if (( iNumRanges == 0 )); then", 1)[1].split(
        "runtime_dir=", 1
    )[0]
    normal = text.split("if (( rc == 0 )); then", 1)[1]
    atomic_move = 'mv -f -- "$completion_temporary" "$B09_SHARD_COMPLETION_FILE"'
    assert zero.index(atomic_move) < zero.index('echo "state=COMPLETE"'), method
    assert (
        normal.index('write_state "FINALIZING"')
        < normal.index(atomic_move)
        < normal.index('write_state "COMPLETE"')
    ), method
    assert 'echo "research_run_id=$RUN_ID"' in zero, method
    assert 'echo "research_run_id=$RUN_ID"' in normal, method

for method in ("M0", "M2"):
    production = (
        root / "engines" / method / "runner" / "run_production.sh"
    ).read_text(encoding="utf-8")
    assert 'source "$RUNNER_DIR/b09_completion_protocol.sh"' in production
    assert "ctrend_b09_observed_terminal_state" in production
    assert '[[ "$state" == COMPLETE ]] && complete=' in production
    assert '[[ "$state" == FAILED* ]] && failed=' in production
    assert '[[ "$state" == FAILED ]] && failed=' not in production
PY

# A shell command that merely mentions an R2023b path must not be mistaken for
# MATLAB.  Process identity is constrained by comm/executable class before its
# arguments are searched, preventing the parent-command false positive that
# motivated this regression test.
# shellcheck source=../../scripts/core_provenance_lib.sh
source "$ROOT/scripts/core_provenance_lib.sh"
DECOY="$TMP/R2023b/bin/matlab"
mkdir -p "$(dirname "$DECOY")"
bash -c 'sleep 30' "$DECOY" &
DECOY_PID=$!
sleep 0.1
if core_runtime_processes_referencing_path "$DECOY" "$$" | \
    awk -v pid="$DECOY_PID" '$1 == pid { found=1 } END { exit !found }'; then
  echo 'plain command-line text was misclassified as a MATLAB runtime' >&2
  exit 1
fi

echo 'B09_TERMINAL_PUBLICATION_TEST_OK methods=3 atomic_commit=1 identity_bound=1 bounded_finalizing=1 process_decoy_rejected=1'
