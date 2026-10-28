#!/usr/bin/env bash
# CTREND_REVISIT_FILE_PURPOSE: Execute the real P0-M1 b01 on certified raw inputs and prove that the unchanged production b02 accepts its checkpoint contract.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
EXT_ROOT="$ROOT/p0_extension"
MATLAB_BIN="${MATLAB_BIN:-$(command -v matlab 2>/dev/null || true)}"
[[ -x "$MATLAB_BIN" ]] || {
  echo 'MATLAB_BIN is required for the P0 M1 b01->b02 contract test' >&2
  exit 2
}
MATLAB_BIN="$(readlink -f -- "$MATLAB_BIN")"

TEST_PARENT="${P0_CONTRACT_TEST_PARENT:-${TMPDIR:-/tmp}}"
[[ "$TEST_PARENT" == /* ]] || {
  echo 'P0_CONTRACT_TEST_PARENT must be absolute' >&2
  exit 2
}
mkdir -p "$TEST_PARENT"
TMP="$(mktemp -d "$TEST_PARENT/cttrend_p0_m1_contract_XXXXXX")"
cleanup() { rm -rf -- "$TMP"; }
trap cleanup EXIT

SOURCE="$TMP/source"
DATA="$SOURCE/DATA"
RESULTS="$SOURCE/Results"
RAW="$ROOT/data/raw/common"
PREFIX="$TMP/b02_checkpoint_prefix.m"
LOG="$TMP/matlab.log"
PREF="$TMP/matlab_pref"

"$EXT_ROOT/scripts/materialize_experiment_source.sh" \
  P0_M1_D0 "$SOURCE" >/dev/null
mkdir "$DATA" "$RESULTS" "$PREF"

# Keep the large immutable inputs in place while giving setup/b01 a real,
# isolated DATA directory for their two derived outputs.
while IFS= read -r -d '' file; do
  ln -s -- "$file" "$DATA/$(basename "$file")"
done < <(find "$RAW" -maxdepth 1 -type f -print0)

# Evaluate the exact production b02 prologue through the checkpoint and
# source-fingerprint gates, but stop before the expensive weekly build.
awk '{print} /^% Determine dimensions/{exit}' \
  "$SOURCE/b02CalculateIndicators.m" > "$PREFIX"
printf '%s\n' \
  "fprintf('P0_M1_B01_B02_CHECKPOINT_CONTRACT_OK mask_false=%d\\n',~any(lUnifiedAuxiliaryFilled,'all'));" \
  >> "$PREFIX"

EXPECTED_DESIGN="$ROOT/engines/M1/base/DesignChoices.mat"
CTREND_RAW_ADJUSTMENT_MODE=none \
CTREND_CORE_EXPERIMENT_ID=P0_M1_D0 \
PIPELINE_SCOPE=full \
CTTREND_VERIFY_PACKAGE_ROOT="$ROOT" \
CTTREND_VERIFY_EXPERIMENT_ID=P0_M1_D0 \
CTTREND_VERIFY_DATA_FILE="$DATA/b0DataOLHC.mat" \
CTTREND_VERIFY_DESIGN_CHOICES_FILE="$SOURCE/DesignChoices.mat" \
CTTREND_VERIFY_EXPECTED_DESIGN_CHOICES_FILE="$EXPECTED_DESIGN" \
CTTREND_B02_CONTRACT_PREFIX="$PREFIX" \
MATLAB_PREFDIR="$PREF" \
  "$MATLAB_BIN" -licmode onlinelicensing -nodisplay -nosplash -batch \
  "cd('$SOURCE'); run('setup.m'); run('b01ReadData.m'); addpath('$EXT_ROOT/tests'); verify_experiment_identity; eval(fileread(getenv('CTTREND_B02_CONTRACT_PREFIX'))); exit(0)" \
  > "$LOG" 2>&1 || {
    tail -120 "$LOG" >&2 || true
    exit 1
  }

grep -F 'EXPERIMENT_IDENTITY_TEST_OK experiment=P0_M1_D0' "$LOG" >/dev/null
grep -F 'P0_M1_B01_B02_CHECKPOINT_CONTRACT_OK mask_false=1' "$LOG" >/dev/null
echo 'P0_M1_B01_B02_PRODUCTION_CONTRACT_TEST_OK real_b01=1 production_b02_prologue=1'
