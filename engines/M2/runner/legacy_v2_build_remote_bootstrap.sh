#!/usr/bin/env bash
# CTREND_REVISIT_FILE_PURPOSE: Preserve the pre-3x3 v2 remote-bootstrap format for historical recovery only.
set -euo pipefail

RUNNER_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$RUNNER_DIR/.." && pwd)"
HANDOFF_DIR="$PROJECT_DIR/remote_handoff_old_v2"
OUTPUT="${1:-$PROJECT_DIR/cttrend_old_v2_remote_agent_bootstrap_20260801.tar.gz}"
TEMP_ROOT="$(mktemp -d /tmp/cttrend_old_v2_bootstrap_XXXXXX)"
ROOT="$TEMP_ROOT/cttrend_old_v2_remote_agent_bootstrap_20260801"

cleanup() {
  local rc=$?
  trap - EXIT INT TERM
  rm -rf -- "$TEMP_ROOT"
  exit "$rc"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

cRequired=(
  cttrend_old_v2_pipeline.tar.gz
  cttrend_old_v2_pipeline.tar.gz.sha256
  cttrend_old_v2_required_data.tar.gz
  cttrend_old_v2_required_data.tar.gz.sha256
  cttrend_old_v2_runner.tar.gz
  cttrend_old_v2_runner.tar.gz.sha256
)
mkdir -p "$ROOT"
for file in "${cRequired[@]}"; do
  [[ -f "$PROJECT_DIR/$file" ]]
  cp -- "$PROJECT_DIR/$file" "$ROOT/"
done
cp -- "$HANDOFF_DIR/REMOTE_AGENT_PROMPT.md" \
  "$HANDOFF_DIR/RSYNC_COMMAND.txt" \
  "$HANDOFF_DIR/README_BOOTSTRAP.md" "$ROOT/"
(
  cd "$ROOT"
  find . -type f ! -name BOOTSTRAP_FILES.sha256 -printf '%P\0' |
    LC_ALL=C sort -z | xargs -0 -r sha256sum
) > "$ROOT/BOOTSTRAP_FILES.sha256"
temporary="${OUTPUT}.tmp.$$"
tar -czf "$temporary" -C "$TEMP_ROOT" \
  cttrend_old_v2_remote_agent_bootstrap_20260801
archive_sha="$(sha256sum "$temporary" | awk '{print $1}')"
mv -f -- "$temporary" "$OUTPUT"
printf '%s  %s\n' "$archive_sha" "$(basename "$OUTPUT")" > "$OUTPUT.sha256"
printf 'bootstrap=%s\nsha256=%s\n' "$OUTPUT" "$archive_sha"
