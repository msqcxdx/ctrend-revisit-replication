#!/usr/bin/env bash
# CTREND_REVISIT_FILE_PURPOSE: Create relocation-safe DATA and Results inventories for a completed run root.
set -euo pipefail

ID="${1:-}"
RUN_ROOT="${2:-}"
case "$ID" in M0_D0|M0_D1|M0_D2|M1_D0|M1_D1|M1_D2|M2_D0|M2_D1|M2_D2) ;; *) exit 2;; esac
[[ "$RUN_ROOT" == /* && -d "$RUN_ROOT" && -f "$RUN_ROOT/RUN_COMPLETE" ]] || {
  echo "usage: $0 EXPERIMENT_ID /absolute/completed/run/root" >&2
  exit 2
}
RUN_ROOT="$(readlink -f -- "$RUN_ROOT")"

if [[ -d "$RUN_ROOT/data" ]]; then
  DATA="$RUN_ROOT/data"
elif [[ -d "$RUN_ROOT/data.staging" ]]; then
  DATA="$RUN_ROOT/data.staging"
elif [[ -d "$RUN_ROOT/runtime/code/DATA" ]]; then
  DATA="$RUN_ROOT/runtime/code/DATA"
else
  echo "completed run has no DATA tree" >&2
  exit 2
fi
DATA_RESOLVED="$(readlink -f -- "$DATA")"
case "$DATA_RESOLVED/" in "$RUN_ROOT"/*) ;; *)
  echo "DATA resolves outside the transferable run root: $DATA_RESOLVED" >&2
  exit 1
esac
[[ -z "$(find "$DATA_RESOLVED" -type l -print -quit)" ]] || {
  echo "portable DATA inventory refuses symbolic links" >&2
  exit 1
}
SPECIAL="$(find "$DATA_RESOLVED" ! -type d ! -type f -print -quit)"
[[ -z "$SPECIAL" ]] || {
  echo "portable DATA inventory found unsupported object: $SPECIAL" >&2
  exit 1
}

OUTPUT="$RUN_ROOT/NINE_EXPERIMENT_DATA_INVENTORY.sha256"
TMP="${OUTPUT}.tmp.$$.$RANDOM"
(
  cd "$DATA_RESOLVED"
  find . -type f -printf '%P\0' | LC_ALL=C sort -z | xargs -0 -r sha256sum
) > "$TMP"
[[ -s "$TMP" ]] || { rm -f -- "$TMP"; echo 'empty DATA inventory' >&2; exit 1; }
if [[ -e "$OUTPUT" ]]; then
  cmp -s "$OUTPUT" "$TMP" || {
    rm -f -- "$TMP"
    echo "existing portable DATA inventory differs: $OUTPUT" >&2
    exit 1
  }
  rm -f -- "$TMP"
else
  mv -Tf -- "$TMP" "$OUTPUT"
fi
(cd "$DATA_RESOLVED" && sha256sum -c "$OUTPUT" >/dev/null)
printf 'PORTABLE_RUN_INVENTORY_OK experiment=%s data_relative=%s files=%s sha256=%s\n' \
  "$ID" "${DATA_RESOLVED#"$RUN_ROOT"/}" "$(wc -l < "$OUTPUT")" \
  "$(sha256sum "$OUTPUT" | awk '{print $1}')"
