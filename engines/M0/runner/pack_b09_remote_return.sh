#!/usr/bin/env bash
# CTREND_REVISIT_FILE_PURPOSE: Validate and archive completed remote b09 results for lossless return to the owning run.
set -euo pipefail

if [[ "$#" -ne 2 ]]; then
  echo "usage: $0 REMOTE_ROOT OUTPUT_TAR_GZ" >&2
  exit 2
fi
REMOTE_ROOT="$(readlink -f "$1")"
OUTPUT="$(realpath -m "$2")"
STATE_DIR="$REMOTE_ROOT/state"
RESULTS_DIR="$REMOTE_ROOT/results"
[[ -f "$STATE_DIR/completion.env" &&
   "$(awk -F= '$1=="complete"{print $2;exit}' \
     "$STATE_DIR/completion.env")" == "1" &&
   "$(awk -F= '$1=="first_combo"{print $2;exit}' \
     "$STATE_DIR/state.env")" == "1537" &&
   "$(awk -F= '$1=="last_combo"{print $2;exit}' \
     "$STATE_DIR/state.env")" == "3072" ]] || {
  echo "remote shard is not sealed for range 1537:3072" >&2
  exit 2
}
mat_count="$(find "$RESULTS_DIR/CTREND" -maxdepth 1 -type f \
  -name 'CTREND_Combo*.mat' | wc -l)"
digest_count="$(find "$RESULTS_DIR/CTREND" -maxdepth 1 -type f \
  -name 'CTREND_Combo*.mat.sha256' | wc -l)"
[[ "$mat_count" -eq 1536 && "$digest_count" -eq 1536 &&
   -f "$RESULTS_DIR/CTREND/ResearchDesignRunManifest.env" &&
   -f "$RESULTS_DIR/CTREND/ResearchDesignRunManifest.env.sha256" &&
   -f "$STATE_DIR/data_inputs_after.sha256" &&
   -f "$STATE_DIR/remote_runner_after.sha256" ]] || {
  echo "remote shard result count is incomplete" >&2
  exit 1
}
(
  cd "$RESULTS_DIR/CTREND"
  for combo in $(seq 1537 3072); do
    test -s "CTREND_Combo${combo}.mat"
    sha256sum -c "CTREND_Combo${combo}.mat.sha256"
  done
  sha256sum -c ResearchDesignRunManifest.env.sha256
)

TEMP_ROOT="$(mktemp -d /tmp/ctrend_old_v2_remote_return_XXXXXX)"
cleanup() {
  local rc=$?
  trap - EXIT INT TERM
  rm -rf -- "$TEMP_ROOT"
  exit "$rc"
}
trap cleanup EXIT
RETURN_ROOT="$TEMP_ROOT/ctrend_old_v2_b09_remote_return"
mkdir -p "$RETURN_ROOT"
cp -a -- "$STATE_DIR" "$RETURN_ROOT/state"
cp -a -- "$RESULTS_DIR" "$RETURN_ROOT/results"
{
  printf 'format=ctrend-old-v2-b09-remote-return-v1\n'
  printf 'mat_files=%s\n' "$mat_count"
  printf 'digest_files=%s\n' "$digest_count"
  printf 'packed_at=%s\n' "$(date -Is)"
  printf 'remote_root=%s\n' "$REMOTE_ROOT"
} > "$RETURN_ROOT/RETURN.env"
(
  cd "$RETURN_ROOT"
  find . -type f ! -name RETURN_MANIFEST.sha256 -printf '%P\0' |
    LC_ALL=C sort -z | xargs -0 -r sha256sum
) > "$RETURN_ROOT/RETURN_MANIFEST.sha256"
mkdir -p "$(dirname "$OUTPUT")"
temporary_output="${OUTPUT}.tmp.$$"
tar -czf "$temporary_output" -C "$TEMP_ROOT" \
  ctrend_old_v2_b09_remote_return
archive_sha="$(sha256sum "$temporary_output" | awk '{print $1}')"
mv -f -- "$temporary_output" "$OUTPUT"
printf '%s  %s\n' "$archive_sha" "$(basename "$OUTPUT")" \
  > "$OUTPUT.sha256"
printf 'return_package=%s\nsha256=%s\n' "$OUTPUT" "$archive_sha"
