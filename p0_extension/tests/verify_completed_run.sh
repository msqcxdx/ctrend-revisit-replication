#!/usr/bin/env bash
# CTREND_REVISIT_FILE_PURPOSE: Verify one completed run across provenance, DATA, Results, 3072 designs, outputs, and experiment identity.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
EXT_ROOT="$ROOT/p0_extension"
ID="${1:-}"
RUN_ROOT="${2:-}"
case "$ID" in
  P0_M0_D0|P0_M0_D1|P0_M0_D2|P0_M1_D0|P0_M1_D1|P0_M1_D2|P0_M2_D0|P0_M2_D1|P0_M2_D2)
    IFS=_ read -r PREPROCESSING_ID METHOD DATA_ID <<< "$ID"
    EXPECTED_LAUNCH_FORMAT=cttrend-pmd-launch-v1
    ;;
  *) exit 2 ;;
esac
[[ "$RUN_ROOT" == /* && -d "$RUN_ROOT" && -f "$RUN_ROOT/RUN_COMPLETE" ]] || {
  echo "invalid completed run root: $RUN_ROOT" >&2; exit 2;
}
RUN_ROOT="$(readlink -f -- "$RUN_ROOT")"
value() { awk -F= -v key="$1" '$1==key{print substr($0,index($0,"=")+1);exit}' "$2"; }
"$EXT_ROOT/tests/verify_run_provenance.sh" "$ID" "$RUN_ROOT"

if [[ -d "$RUN_ROOT/results" ]]; then
  RESULTS="$RUN_ROOT/results"
elif [[ -d "$RUN_ROOT/results.staging" ]]; then
  RESULTS="$RUN_ROOT/results.staging"
elif [[ -d "$RUN_ROOT/runtime/code/Results" ]]; then
  RESULTS="$RUN_ROOT/runtime/code/Results"
else
  echo "completed run has no results tree" >&2; exit 2
fi
if [[ -d "$RUN_ROOT/data" ]]; then
  DATA="$RUN_ROOT/data"
elif [[ -d "$RUN_ROOT/data.staging" ]]; then
  DATA="$RUN_ROOT/data.staging"
elif [[ -d "$RUN_ROOT/runtime/code/DATA" ]]; then
  DATA="$RUN_ROOT/runtime/code/DATA"
else
  echo "completed run has no DATA tree" >&2; exit 2
fi
RESULTS_RESOLVED="$(readlink -f -- "$RESULTS")"
DATA_RESOLVED="$(readlink -f -- "$DATA")"
case "$RESULTS_RESOLVED/" in "$RUN_ROOT"/*) ;; *)
  echo "Results resolves outside the transferable run root: $RESULTS_RESOLVED" >&2; exit 1;;
esac
case "$DATA_RESOLVED/" in "$RUN_ROOT"/*) ;; *)
  echo "DATA resolves outside the transferable run root: $DATA_RESOLVED" >&2; exit 1;;
esac
PORTABLE_DATA_INVENTORY="$RUN_ROOT/P0_EXPERIMENT_DATA_INVENTORY.sha256"
[[ -s "$PORTABLE_DATA_INVENTORY" ]] || {
  echo 'portable DATA inventory is missing' >&2; exit 1;
}
(cd "$DATA_RESOLVED" && sha256sum -c "$PORTABLE_DATA_INVENTORY" >/dev/null)
PORTABLE_DATA_INVENTORY_SHA="$(sha256sum "$PORTABLE_DATA_INVENTORY" | awk '{print $1}')"

FORMAT="$(value format "$RUN_ROOT/RUN_COMPLETE")"
MANIFEST="$RUN_ROOT/P0_EXPERIMENT_LAUNCH_MANIFEST.env"
  [[ -s "$MANIFEST" && "$(value format "$MANIFEST")" == "$EXPECTED_LAUNCH_FORMAT" && \
     "$(value experiment_id "$MANIFEST")" == "$ID" && \
     "$(value method_id "$MANIFEST")" == "$METHOD" && \
     "$(value data_id "$MANIFEST")" == "$DATA_ID" && \
     "$(value raw_adjustment_mode "$MANIFEST")" == none && \
     "$(value b09_topology "$MANIFEST")" == 8x15 ]] || {
    echo "run launch manifest does not match $ID" >&2; exit 1;
  }
  if [[ "$ID" == P0_* ]]; then
    [[ "$(value preprocessing_id "$MANIFEST")" == P0 && \
       "$(value unified_missing_preprocessing "$MANIFEST")" == 0 ]] || {
      echo "P0 launch manifest does not declare the preprocessing arm" >&2
      exit 1
    }
  fi
  EXPECTED_EXCLUSION="$ROOT/config/exclusions/$DATA_ID.csv"
  [[ "$(value exclusion_sha256 "$MANIFEST")" == \
     "$(sha256sum "$EXPECTED_EXCLUSION" | awk '{print $1}')" ]] || {
    echo "run exclusion digest does not match the frozen $ID configuration" >&2
    exit 1
  }
  if [[ "$METHOD" == M0 || "$METHOD" == M2 ]]; then
    RUN_PACKAGE_SHA="$(value package_sha256 "$RUN_ROOT/RUN_COMPLETE")"
  else
    RUN_PACKAGE_SHA="$(value runtime_package_sha256 "$RUN_ROOT/RUN_COMPLETE")"
  fi
  [[ "$RUN_PACKAGE_SHA" =~ ^[0-9a-f]{64}$ && \
     "$(value runtime_package_sha256 "$MANIFEST")" == "$RUN_PACKAGE_SHA" ]] || {
    echo 'launch manifest runtime package is not bound to RUN_COMPLETE' >&2
    exit 1
  }
IDENTITY_DECLARATION="$MANIFEST"
IDENTITY_DECLARATION_SHA="$(sha256sum "$IDENTITY_DECLARATION" | awk '{print $1}')"
RESULTS_RELATIVE="${RESULTS#"$RUN_ROOT"/}"
DATA_RELATIVE="${DATA#"$RUN_ROOT"/}"
IDENTITY_DECLARATION_RELATIVE="${IDENTITY_DECLARATION#"$RUN_ROOT"/}"
[[ "$RESULTS_RELATIVE" != "$RESULTS" && "$DATA_RELATIVE" != "$DATA" && \
   "$IDENTITY_DECLARATION_RELATIVE" != "$IDENTITY_DECLARATION" ]] || {
  echo 'accepted result/data/identity files must be located inside the run root' >&2
  exit 1
}

MAT_COUNT="$(find "$RESULTS/CTREND" -maxdepth 1 -type f -name 'CTREND_Combo*.mat' | wc -l)"
SHA_COUNT="$(find "$RESULTS/CTREND" -maxdepth 1 -type f -name 'CTREND_Combo*.mat.sha256' | wc -l)"
[[ "$MAT_COUNT" -eq 3072 && "$SHA_COUNT" -eq 3072 ]] || {
  echo "incomplete b09 grid: mat=$MAT_COUNT sidecar=$SHA_COUNT" >&2; exit 1;
}
[[ -s "$DATA/b0DataOLHC.mat" ]] || {
  echo "missing b01 checkpoint: $DATA/b0DataOLHC.mat" >&2; exit 1;
}
DATA_CHECKPOINT_SHA="$(sha256sum "$DATA/b0DataOLHC.mat" | awk '{print $1}')"
RUN_COMPLETE_SHA="$(sha256sum "$RUN_ROOT/RUN_COMPLETE" | awk '{print $1}')"
RESEARCH_RUN_ID="$(value research_run_id "$RUN_ROOT/RUN_COMPLETE")"
[[ "$RESEARCH_RUN_ID" =~ ^[0-9a-fA-F-]{36}$ ]] || {
  echo 'RUN_COMPLETE lacks a valid research_run_id' >&2; exit 1;
}
PROVENANCE_COMPATIBILITY="$RUN_ROOT/P0_EXPERIMENT_PROVENANCE_COMPATIBILITY.env"
PROVENANCE_COMPATIBILITY_MODE=exact
PROVENANCE_COMPATIBILITY_SHA=''
if [[ -e "$PROVENANCE_COMPATIBILITY" ]]; then
  [[ -s "$PROVENANCE_COMPATIBILITY" ]] || {
    echo 'provenance compatibility evidence is empty' >&2; exit 1;
  }
  PROVENANCE_COMPATIBILITY_FORMAT="$(value format "$PROVENANCE_COMPATIBILITY")"
  PROVENANCE_COMPATIBILITY_MODE="$(value mode "$PROVENANCE_COMPATIBILITY")"
  case "$PROVENANCE_COMPATIBILITY_FORMAT:$PROVENANCE_COMPATIBILITY_MODE" in
    cttrend-m1-legacy-inventory-compatibility-v1:tests_subdirectory_shell_omission_v1) ;;
    cttrend-m1-dynamic-figure-b2-recovery-compatibility-v1:dynamic_figure_b2_validator_recovery_v1) ;;
    *) echo 'unrecognized provenance compatibility mode' >&2; exit 1 ;;
  esac
  [[ "$(value experiment_id "$PROVENANCE_COMPATIBILITY")" == "$ID" && \
     "$(value research_run_id "$PROVENANCE_COMPATIBILITY")" == \
       "$RESEARCH_RUN_ID" && \
     "$(value run_complete_sha256 "$PROVENANCE_COMPATIBILITY")" == \
       "$RUN_COMPLETE_SHA" ]] || {
    echo 'provenance compatibility evidence does not bind this run' >&2
    exit 1
  }
  PROVENANCE_COMPATIBILITY_SHA="$(sha256sum "$PROVENANCE_COMPATIBILITY" | awk '{print $1}')"
fi

OUTPUT_LOG="$(python3 "$EXT_ROOT/tests/verify_output_registry.py" \
  "$ROOT" "$ID" "$RESULTS")"

MATLAB_BIN="${MATLAB_BIN:-$(command -v matlab 2>/dev/null || true)}"
[[ -x "$MATLAB_BIN" ]] || {
  echo "MATLAB_BIN is required for final experiment-identity acceptance" >&2
  exit 2
}
PREF="$(mktemp -d "${TMPDIR:-/tmp}/cttrend_identity_pref_XXXXXX")"
cleanup() { rm -rf -- "$PREF"; }
trap cleanup EXIT
IDENTITY_LOG="$RUN_ROOT/P0_EXPERIMENT_IDENTITY_CHECK.log"
DESIGN_FILE=''
EXPECTED_DESIGN_FILE=''
if [[ "$METHOD" == M1 ]]; then
  EXPECTED_DESIGN_FILE="$ROOT/engines/M1/base/DesignChoices.mat"
  for candidate in "$RUN_ROOT/DesignChoices.mat" \
      "$RUN_ROOT/runtime/code/DesignChoices.mat" \
      "$RUN_ROOT/runtime/cttrend_corrected_pipeline/DesignChoices.mat"; do
    if [[ -f "$candidate" ]]; then DESIGN_FILE="$candidate"; break; fi
  done
  [[ -n "$DESIGN_FILE" && -f "$EXPECTED_DESIGN_FILE" ]] || {
    echo 'cannot locate M1 DesignChoices identity files' >&2
    exit 1
  }
fi
CTTREND_VERIFY_PACKAGE_ROOT="$ROOT" \
CTTREND_VERIFY_EXPERIMENT_ID="$ID" \
CTTREND_VERIFY_DATA_FILE="$DATA/b0DataOLHC.mat" \
CTTREND_VERIFY_DESIGN_CHOICES_FILE="$DESIGN_FILE" \
CTTREND_VERIFY_EXPECTED_DESIGN_CHOICES_FILE="$EXPECTED_DESIGN_FILE" \
MATLAB_PREFDIR="$PREF" \
  "$MATLAB_BIN" -licmode onlinelicensing -nodisplay -nosplash -batch \
  "addpath(fullfile(getenv('CTTREND_VERIFY_PACKAGE_ROOT'),'p0_extension','tests')); verify_experiment_identity; exit(0)" \
  > "$IDENTITY_LOG" 2>&1 || {
    tail -80 "$IDENTITY_LOG" >&2 || true
    exit 1
  }
grep -F "EXPERIMENT_IDENTITY_TEST_OK experiment=$ID" "$IDENTITY_LOG" >/dev/null

ACCEPTANCE="$RUN_ROOT/P0_EXPERIMENT_ACCEPTANCE.env"
ACCEPTANCE_FORMAT=cttrend-p0-experiment-acceptance-v1
if [[ ! -e "$ACCEPTANCE" ]]; then
  TMP="${ACCEPTANCE}.tmp.$$"
  {
    echo "format=$ACCEPTANCE_FORMAT"
    echo "experiment_id=$ID"
    echo "research_run_id=$RESEARCH_RUN_ID"
    echo "results_relative_path=$RESULTS_RELATIVE"
    echo "data_relative_path=$DATA_RELATIVE"
    echo "combo_files=$MAT_COUNT"
    echo "combo_sidecars=$SHA_COUNT"
    echo "identity_declaration_relative_path=$IDENTITY_DECLARATION_RELATIVE"
    echo "identity_declaration_sha256=$IDENTITY_DECLARATION_SHA"
    echo "b01_checkpoint_sha256=$DATA_CHECKPOINT_SHA"
    echo "data_inventory_sha256=$PORTABLE_DATA_INVENTORY_SHA"
    echo "run_complete_sha256=$RUN_COMPLETE_SHA"
    echo "provenance_compatibility_mode=$PROVENANCE_COMPATIBILITY_MODE"
    echo "provenance_compatibility_evidence_sha256=$PROVENANCE_COMPATIBILITY_SHA"
    echo "output_registry_status=PASS"
    echo "experiment_identity_status=PASS"
    echo "raw_adjustment_mode=none"
    echo "accepted_at_utc=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  } > "$TMP"
  mv -Tf -- "$TMP" "$ACCEPTANCE"
else
  EXISTING_PROVENANCE_MODE="$(value provenance_compatibility_mode "$ACCEPTANCE")"
  EXISTING_PROVENANCE_SHA="$(value provenance_compatibility_evidence_sha256 "$ACCEPTANCE")"
  if [[ -z "$EXISTING_PROVENANCE_MODE" && -z "$EXISTING_PROVENANCE_SHA" && \
        "$PROVENANCE_COMPATIBILITY_MODE" != exact ]]; then
    # Historical worker acceptance predates the explicit compatibility fields.
    # Keep that signed marker byte-for-byte intact; the independently generated
    # compatibility marker and the registration bind the missing scope evidence.
    EXISTING_PROVENANCE_MODE="$PROVENANCE_COMPATIBILITY_MODE"
    EXISTING_PROVENANCE_SHA="$PROVENANCE_COMPATIBILITY_SHA"
  else
    [[ -n "$EXISTING_PROVENANCE_MODE" ]] || EXISTING_PROVENANCE_MODE=exact
  fi
  [[ "$(value format "$ACCEPTANCE")" == "$ACCEPTANCE_FORMAT" && \
     "$(value experiment_id "$ACCEPTANCE")" == "$ID" && \
     "$(value research_run_id "$ACCEPTANCE")" == "$RESEARCH_RUN_ID" && \
     "$(value results_relative_path "$ACCEPTANCE")" == \
       "$RESULTS_RELATIVE" && \
     "$(value data_relative_path "$ACCEPTANCE")" == "$DATA_RELATIVE" && \
     "$(value identity_declaration_relative_path "$ACCEPTANCE")" == \
       "$IDENTITY_DECLARATION_RELATIVE" && \
     "$(value combo_files "$ACCEPTANCE")" == "$MAT_COUNT" && \
     "$(value combo_sidecars "$ACCEPTANCE")" == "$SHA_COUNT" && \
     "$(value identity_declaration_sha256 "$ACCEPTANCE")" == \
       "$IDENTITY_DECLARATION_SHA" && \
     "$(value b01_checkpoint_sha256 "$ACCEPTANCE")" == \
       "$DATA_CHECKPOINT_SHA" && \
     "$(value data_inventory_sha256 "$ACCEPTANCE")" == \
       "$PORTABLE_DATA_INVENTORY_SHA" && \
     "$(value run_complete_sha256 "$ACCEPTANCE")" == \
       "$RUN_COMPLETE_SHA" && \
     "$EXISTING_PROVENANCE_MODE" == "$PROVENANCE_COMPATIBILITY_MODE" && \
     "$EXISTING_PROVENANCE_SHA" == "$PROVENANCE_COMPATIBILITY_SHA" && \
     "$(value output_registry_status "$ACCEPTANCE")" == PASS && \
     "$(value experiment_identity_status "$ACCEPTANCE")" == PASS && \
     "$(value raw_adjustment_mode "$ACCEPTANCE")" == none ]] || {
    echo "existing acceptance is stale or no longer binds current files: $ACCEPTANCE" >&2
    exit 1
  }
fi
printf 'COMPLETED_RUN_ACCEPTED experiment=%s combos=%s output_registry=%s acceptance=%s\n' \
  "$ID" "$MAT_COUNT" "$OUTPUT_LOG" "$ACCEPTANCE"
