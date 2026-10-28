#!/usr/bin/env bash
# CTREND_REVISIT_FILE_PURPOSE: Wait for and validate an explicitly expected remote b09 return without changing its range or contents.
set -euo pipefail

if [[ "$#" -ne 4 ]]; then
  echo "usage: $0 SHARD_RUN_ROOT RESULTS_ROOT HANDOFF_DIR RUN_ID" >&2
  exit 2
fi

SHARD_RUN_ROOT="$1"
RESULTS_ROOT="$2"
HANDOFF_DIR="$3"
RUN_ID="$4"
STATE_DIR="$SHARD_RUN_ROOT/shard2/subshard1"
RESULT_DIR="$RESULTS_ROOT/shard2/subshard1"
RETURN_ARCHIVE="$HANDOFF_DIR/cttrend_old_v2_b09_remote_return_${RUN_ID}.tar.gz"
RETURN_SIDECAR="$RETURN_ARCHIVE.sha256"
POLL_SECONDS="${B09_MANUAL_RETURN_POLL_SECONDS:-60}"

[[ "$RUN_ID" =~ ^[0-9a-fA-F-]{36}$ &&
   "$POLL_SECONDS" =~ ^[1-9][0-9]*$ ]] || {
  echo "invalid manual remote-return configuration" >&2
  exit 2
}
mkdir -p "$STATE_DIR" "$RESULT_DIR" "$HANDOFF_DIR"
printf '%s\n' "$$" > "$STATE_DIR/supervisor.pid"
printf '%s\n' "$(date +%s)" > "$STATE_DIR/supervisor.started_epoch"

write_wait_state() {
  local temporary="$STATE_DIR/state.env.tmp.$$"
  {
    printf 'state=WAITING_FOR_REMOTE_RETURN\n'
    printf 'updated_at=%s\n' "$(date -Is)"
    printf 'updated_epoch=%s\n' "$(date +%s)"
    printf 'supervisor_pid=%s\n' "$$"
    printf 'first_combo=1537\n'
    printf 'last_combo=3072\n'
    printf 'expected_return_archive=%s\n' "$RETURN_ARCHIVE"
  } > "$temporary"
  mv -f -- "$temporary" "$STATE_DIR/state.env"
}

write_transport_heartbeat() {
  local temporary="$STATE_DIR/transport_heartbeat.env.tmp.$$"
  {
    printf 'state=WAITING_FOR_REMOTE_RETURN\n'
    printf 'updated_at=%s\n' "$(date -Is)"
    printf 'updated_epoch=%s\n' "$(date +%s)"
    printf 'supervisor_pid=%s\n' "$$"
  } > "$temporary"
  mv -f -- "$temporary" "$STATE_DIR/transport_heartbeat.env"
}

write_wait_state
while [[ ! -f "$RETURN_ARCHIVE" || ! -f "$RETURN_SIDECAR" ]]; do
  write_transport_heartbeat
  sleep "$POLL_SECONDS"
done
write_transport_heartbeat

(
  cd "$HANDOFF_DIR"
  sha256sum -c "$(basename "$RETURN_SIDECAR")"
)
extract_root="$(mktemp -d "$SHARD_RUN_ROOT/shard2/.return_extract_XXXXXX")"
cleanup() {
  local rc=$?
  trap - EXIT INT TERM
  rm -rf -- "$extract_root"
  exit "$rc"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
tar -xzf "$RETURN_ARCHIVE" -C "$extract_root"
returned="$extract_root/cttrend_old_v2_b09_remote_return"
[[ -d "$returned/state" && -d "$returned/results" &&
   -f "$returned/RETURN.env" &&
   -f "$returned/RETURN_MANIFEST.sha256" ]] || {
  echo "remote return archive schema is incomplete" >&2
  exit 1
}
(
  cd "$returned"
  sha256sum -c RETURN_MANIFEST.sha256
)
[[ "$(awk -F= '$1=="mat_files"{print $2;exit}' \
     "$returned/RETURN.env")" == "1536" &&
   "$(awk -F= '$1=="digest_files"{print $2;exit}' \
     "$returned/RETURN.env")" == "1536" &&
   "$(awk -F= '$1=="complete"{print $2;exit}' \
     "$returned/state/completion.env")" == "1" &&
   "$(awk -F= '$1=="first_combo"{print $2;exit}' \
     "$returned/state/state.env")" == "1537" &&
   "$(awk -F= '$1=="last_combo"{print $2;exit}' \
     "$returned/state/state.env")" == "3072" ]] || {
  echo "remote return archive does not certify the assigned range" >&2
  exit 1
}

cp -a -- "$returned/state/." "$STATE_DIR/"
cp -a -- "$returned/results/." "$RESULT_DIR/"
printf '%s\n' "$$" > "$STATE_DIR/supervisor.pid"
mat_count="$(find "$RESULT_DIR/CTREND" -maxdepth 1 -type f \
  -name 'CTREND_Combo*.mat' | wc -l)"
digest_count="$(find "$RESULT_DIR/CTREND" -maxdepth 1 -type f \
  -name 'CTREND_Combo*.mat.sha256' | wc -l)"
[[ "$mat_count" -eq 1536 && "$digest_count" -eq 1536 &&
   -f "$RESULT_DIR/CTREND/ResearchDesignRunManifest.env" &&
   -f "$RESULT_DIR/CTREND/ResearchDesignRunManifest.env.sha256" ]] || {
  echo "imported remote result count is incomplete" >&2
  exit 1
}
(
  cd "$RESULT_DIR/CTREND"
  for combo in $(seq 1537 3072); do
    test -s "CTREND_Combo${combo}.mat"
    sha256sum -c "CTREND_Combo${combo}.mat.sha256" >/dev/null
  done
  sha256sum -c ResearchDesignRunManifest.env.sha256 >/dev/null
)
{
  printf 'remote_return_complete=1\n'
  printf 'return_mode=manual_verified_archive\n'
  printf 'return_archive=%s\n' "$RETURN_ARCHIVE"
  printf 'return_archive_sha256=%s\n' \
    "$(sha256sum "$RETURN_ARCHIVE" | awk '{print $1}')"
  printf 'returned_at=%s\n' "$(date -Is)"
} > "$STATE_DIR/return.env"
