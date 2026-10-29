#!/usr/bin/env bash
# CTREND_REVISIT_FILE_PURPOSE: Independently verify a completed run and bind its immutable identity to the declared experiment cell.
set -euo pipefail

EXT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ROOT="$(cd "$EXT_ROOT/.." && pwd)"
ID="${1:-}"
RUN_ROOT="${2:-}"
case "$ID" in
  P0_M0_D0|P0_M0_D1|P0_M0_D2|P0_M1_D0|P0_M1_D1|P0_M1_D2|P0_M2_D0|P0_M2_D1|P0_M2_D2) ;;
  *) echo "invalid experiment ID: $ID" >&2; exit 2 ;;
esac
[[ -d "$RUN_ROOT" && -f "$RUN_ROOT/RUN_COMPLETE" ]] || {
  echo "completed run root is invalid: $RUN_ROOT" >&2; exit 2;
}
RUN_ROOT="$(readlink -f -- "$RUN_ROOT")"

# Registration is the public acceptance gate, not a pointer-writing shortcut.
# It verifies the full paper-output registry and the saved M/D identity before
# consuming the result inventory below.
"$EXT_ROOT/tests/verify_completed_run.sh" "$ID" "$RUN_ROOT"
ACCEPTANCE="$RUN_ROOT/P0_EXPERIMENT_ACCEPTANCE.env"
ACCEPTANCE_HASH_FIELD=p0_experiment_acceptance_sha256
REGISTRATION_FORMAT=ctrend-p0-experiment-registration-v1
PROVENANCE_COMPATIBILITY="$RUN_ROOT/P0_EXPERIMENT_PROVENANCE_COMPATIBILITY.env"
[[ -s "$ACCEPTANCE" ]] || exit 1

if [[ -d "$RUN_ROOT/results" ]]; then
  RESULTS="$RUN_ROOT/results"
elif [[ -d "$RUN_ROOT/results.staging" ]]; then
  RESULTS="$RUN_ROOT/results.staging"
elif [[ -d "$RUN_ROOT/runtime/code/Results" ]]; then
  RESULTS="$RUN_ROOT/runtime/code/Results"
else
  echo "cannot locate results tree" >&2; exit 2
fi

MAT_COUNT="$(find "$RESULTS/CTREND" -maxdepth 1 -type f \
  -name 'CTREND_Combo*.mat' | wc -l)"
SHA_COUNT="$(find "$RESULTS/CTREND" -maxdepth 1 -type f \
  -name 'CTREND_Combo*.mat.sha256' | wc -l)"
[[ "$MAT_COUNT" -eq 3072 && "$SHA_COUNT" -eq 3072 ]] || {
  echo "b09 result count is incomplete: mat=$MAT_COUNT sidecar=$SHA_COUNT" >&2
  exit 1
}
while IFS= read -r sidecar; do
  (cd "$(dirname "$sidecar")" && sha256sum -c "$(basename "$sidecar")" >/dev/null)
done < <(find "$RESULTS/CTREND" -maxdepth 1 -type f \
  -name 'CTREND_Combo*.mat.sha256' | LC_ALL=C sort)

INVENTORY=""
for candidate in "$RUN_ROOT/results.sha256" \
    "$RUN_ROOT/results_inventory.sha256"; do
  if [[ -s "$candidate" ]]; then INVENTORY="$candidate"; break; fi
done
if [[ -n "$INVENTORY" ]]; then
  (cd "$RESULTS" && sha256sum -c "$INVENTORY" >/dev/null)
  INVENTORY_SHA="$(sha256sum "$INVENTORY" | awk '{print $1}')"
elif [[ -s "$RUN_ROOT/Results.full.manifest.tsv" ]]; then
  source "$ROOT/scripts/core_provenance_lib.sh"
  core_verify_manifest_members "$RESULTS" "$RUN_ROOT/Results.full.manifest.tsv"
  INVENTORY="$RUN_ROOT/Results.full.manifest.tsv"
  INVENTORY_SHA="$(sha256sum "$INVENTORY" | awk '{print $1}')"
else
  echo "no accepted results inventory exists" >&2
  exit 1
fi

RUN_ID="$(awk -F= '$1=="research_run_id"{print $2;exit}' \
  "$RUN_ROOT/RUN_COMPLETE")"
[[ "$RUN_ID" =~ ^[0-9a-fA-F-]{36}$ ]] || {
  echo "RUN_COMPLETE lacks a valid research_run_id" >&2; exit 1;
}
PROVENANCE_COMPATIBILITY_MODE=exact
PROVENANCE_COMPATIBILITY_SHA=''
if [[ -e "$PROVENANCE_COMPATIBILITY" ]]; then
  [[ -s "$PROVENANCE_COMPATIBILITY" ]] || {
    echo 'provenance compatibility evidence is empty' >&2
    exit 1
  }
  PROVENANCE_COMPATIBILITY_FORMAT="$(awk -F= '$1=="format"{print $2;exit}' \
    "$PROVENANCE_COMPATIBILITY")"
  PROVENANCE_COMPATIBILITY_MODE="$(awk -F= '$1=="mode"{print $2;exit}' \
    "$PROVENANCE_COMPATIBILITY")"
  case "$PROVENANCE_COMPATIBILITY_FORMAT:$PROVENANCE_COMPATIBILITY_MODE" in
    ctrend-m1-legacy-inventory-compatibility-v1:tests_subdirectory_shell_omission_v1) ;;
    ctrend-m1-dynamic-figure-b2-recovery-compatibility-v1:dynamic_figure_b2_validator_recovery_v1) ;;
    *) echo 'unrecognized provenance compatibility mode' >&2; exit 1 ;;
  esac
  [[ "$(awk -F= '$1=="experiment_id"{print $2;exit}' \
       "$PROVENANCE_COMPATIBILITY")" == "$ID" && \
     "$(awk -F= '$1=="research_run_id"{print $2;exit}' \
       "$PROVENANCE_COMPATIBILITY")" == "$RUN_ID" && \
     "$(awk -F= '$1=="run_complete_sha256"{print $2;exit}' \
       "$PROVENANCE_COMPATIBILITY")" == \
       "$(sha256sum "$RUN_ROOT/RUN_COMPLETE" | awk '{print $1}')" ]] || {
    echo 'provenance compatibility evidence does not bind this run' >&2
    exit 1
  }
  PROVENANCE_COMPATIBILITY_SHA="$(sha256sum "$PROVENANCE_COMPATIBILITY" | awk '{print $1}')"
fi
DEST="$ROOT/outputs/experiments/$ID"
mkdir -p "$DEST"
REG="$DEST/registration.env"
[[ ! -e "$REG" ]] || {
  reg_value() {
    awk -F= -v key="$1" '$1==key{print substr($0,index($0,"=")+1);exit}' "$2"
  }
  OLD_ROOT="$(reg_value run_root "$REG")"
  [[ "$OLD_ROOT" == "$RUN_ROOT" ]] || {
    echo "experiment already registered to another run: $OLD_ROOT" >&2; exit 2;
  }
  EXISTING_PROVENANCE_MODE="$(reg_value provenance_compatibility_mode "$REG")"
  [[ -n "$EXISTING_PROVENANCE_MODE" ]] || EXISTING_PROVENANCE_MODE=exact
  EXISTING_PROVENANCE_SHA="$(reg_value provenance_compatibility_evidence_sha256 "$REG")"
  [[ "$(reg_value format "$REG")" == "$REGISTRATION_FORMAT" && \
     "$(reg_value experiment_id "$REG")" == "$ID" && \
     "$(reg_value research_run_id "$REG")" == "$RUN_ID" && \
     "$(reg_value results_root "$REG")" == "$RESULTS" && \
     "$(reg_value combo_count "$REG")" == "$MAT_COUNT" && \
     "$(reg_value combo_sidecar_count "$REG")" == "$SHA_COUNT" && \
     "$(reg_value results_inventory_sha256 "$REG")" == "$INVENTORY_SHA" && \
     "$(reg_value run_complete_sha256 "$REG")" == \
       "$(sha256sum "$RUN_ROOT/RUN_COMPLETE" | awk '{print $1}')" && \
     "$(reg_value "$ACCEPTANCE_HASH_FIELD" "$REG")" == \
       "$(sha256sum "$ACCEPTANCE" | awk '{print $1}')" && \
     "$EXISTING_PROVENANCE_MODE" == "$PROVENANCE_COMPATIBILITY_MODE" && \
     "$EXISTING_PROVENANCE_SHA" == "$PROVENANCE_COMPATIBILITY_SHA" ]] || {
    echo "existing registration is stale or no longer binds current files: $REG" >&2
    exit 1
  }
  echo "REGISTRATION_ALREADY_VALID experiment=$ID run_root=$RUN_ROOT"
  exit 0
}
TMP="${REG}.tmp.$$"
{
  echo "format=$REGISTRATION_FORMAT"
  echo "experiment_id=$ID"
  echo "research_run_id=$RUN_ID"
  echo "run_root=$RUN_ROOT"
  echo "results_root=$RESULTS"
  echo "combo_count=$MAT_COUNT"
  echo "combo_sidecar_count=$SHA_COUNT"
  echo "results_inventory=$INVENTORY"
  echo "results_inventory_sha256=$INVENTORY_SHA"
  echo "run_complete_sha256=$(sha256sum "$RUN_ROOT/RUN_COMPLETE" | awk '{print $1}')"
  echo "$ACCEPTANCE_HASH_FIELD=$(sha256sum "$ACCEPTANCE" | awk '{print $1}')"
  echo "provenance_compatibility_mode=$PROVENANCE_COMPATIBILITY_MODE"
  echo "provenance_compatibility_evidence_sha256=$PROVENANCE_COMPATIBILITY_SHA"
  echo "registered_at=$(date -Is)"
} > "$TMP"
mv -Tf -- "$TMP" "$REG"
echo "RUN_REGISTERED experiment=$ID run_root=$RUN_ROOT registration=$REG"
