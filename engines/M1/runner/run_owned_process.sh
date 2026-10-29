#!/usr/bin/env bash
# CTREND_REVISIT_FILE_PURPOSE: Run one phase in an independently owned process group and clean up orphaned descendants on failure.
set -euo pipefail

if [[ "$#" -lt 5 ]]; then
  echo "usage: $0 OWNER_FILE OWNER_TOKEN CODE_DIR PHASE COMMAND [ARGS...]" >&2
  exit 2
fi

owner_file="$1"
owner_token="$2"
code_dir="$3"
phase="$4"
shift 4

[[ "$owner_token" =~ ^[0-9a-fA-F-]{36}$ ]] || {
  echo "invalid owned-process token" >&2
  exit 2
}
[[ -d "$code_dir" ]] || {
  echo "owned-process code directory is missing: $code_dir" >&2
  exit 2
}
pgid="$(ps -o pgid= -p "$$" | tr -d '[:space:]')"
[[ "$pgid" == "$$" ]] || {
  echo "owned process must be launched by setsid" >&2
  exit 2
}
command_path="$(command -v "$1" 2>/dev/null || true)"
[[ -n "$command_path" ]] || command_path="$1"

mkdir -p -- "$(dirname "$owner_file")"
temporary="${owner_file}.tmp.$$"
{
  printf 'format=ctrend-owned-process-v1\n'
  printf 'state=running\n'
  printf 'owner_token=%s\n' "$owner_token"
  printf 'phase=%s\n' "$phase"
  printf 'pgid=%s\n' "$$"
  printf 'code_dir=%s\n' "$(readlink -f "$code_dir")"
  printf 'command=%s\n' "$(readlink -f "$command_path")"
  printf 'created_at=%s\n' "$(date -Is)"
} > "$temporary"
mv -f -- "$temporary" "$owner_file"

exec "$@"
