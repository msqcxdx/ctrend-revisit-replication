#!/usr/bin/env bash
# CTREND_REVISIT_FILE_PURPOSE: Resolve nine accepted registrations and run b19 common-week robustness from saved outputs only.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUTPUT_DIR="${1:-}"
MATLAB_BIN="${MATLAB_BIN:-$(command -v matlab 2>/dev/null || true)}"
IDS=(M0_D0 M0_D1 M0_D2 M2_D0 M2_D1 M2_D2 M1_D0 M1_D1 M1_D2)

[[ "$OUTPUT_DIR" == /* && ! -e "$OUTPUT_DIR" && ! -L "$OUTPUT_DIR" ]] || {
  echo 'usage: MATLAB_BIN=/absolute/R2023b/bin/matlab run_b19_common_week_robustness.sh /fresh/absolute/output' >&2
  exit 2
}
[[ -x "$MATLAB_BIN" ]] || {
  echo 'MATLAB_BIN must name an executable MATLAB R2023b binary' >&2
  exit 2
}

mkdir -p "$(dirname "$OUTPUT_DIR")"
mkdir "$OUTPUT_DIR"
PREF="$(mktemp -d "${TMPDIR:-/tmp}/ctrend_b19_pref_XXXXXX")"
COMPLETE=0
cleanup() {
  local rc=$?
  trap - EXIT INT TERM
  rm -rf -- "$PREF"
  if [[ "$COMPLETE" -ne 1 ]]; then
    {
      echo 'format=ctrend-b19-common-week-failure-v1'
      echo "exit_code=$rc"
      echo "failed_at_utc=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    } > "$OUTPUT_DIR/B19_FAILED.env"
  fi
  exit "$rc"
}
trap cleanup EXIT INT TERM

value() {
  local key="$1" file="$2"
  awk -F= -v key="$key" '$1==key{print substr($0,index($0,"=")+1);exit}' "$file"
}

BINDINGS_TMP="$OUTPUT_DIR/b19_input_bindings.csv.tmp.$$"
printf 'experiment_id,research_run_id,registration_sha256,ctrend_base_sha256\n' > "$BINDINGS_TMP"
for id in "${IDS[@]}"; do
  registration="$ROOT/outputs/experiments/$id/registration.env"
  [[ -s "$registration" ]] || {
    echo "b19 requires a completed registration for $id" >&2
    exit 1
  }
  run_root="$(value run_root "$registration")"
  [[ -d "$run_root" && -f "$run_root/RUN_COMPLETE" ]] || {
    echo "registered run root is unavailable for $id" >&2
    exit 1
  }
  # Existing registrations are revalidated in place. A stale hash fails;
  # this command never substitutes another run or recomputes an experiment.
  "$ROOT/scripts/register_completed_run.sh" "$id" "$run_root" >/dev/null
  results_root="$(value results_root "$registration")"
  baseline="$results_root/CTREND/CTREND_Base.mat"
  [[ -s "$baseline" ]] || {
    echo "registered baseline is missing for $id" >&2
    exit 1
  }
  variable="CTREND_COMMON_WEEK_$id"
  printf -v "$variable" '%s' "$baseline"
  export "$variable"
  printf '%s,%s,%s,%s\n' "$id" \
    "$(value research_run_id "$registration")" \
    "$(sha256sum "$registration" | awk '{print $1}')" \
    "$(sha256sum "$baseline" | awk '{print $1}')" >> "$BINDINGS_TMP"
done
mv -Tf -- "$BINDINGS_TMP" "$OUTPUT_DIR/b19_input_bindings.csv"

export CTREND_COMMON_WEEK_OUTPUT_DIR="$OUTPUT_DIR"
MATLAB_PREFDIR="$PREF" "$MATLAB_BIN" -licmode onlinelicensing \
  -nodisplay -nosplash -batch \
  "addpath(fullfile('$ROOT','postprocessing')); b19CommonWeekRobustness; exit(0)"

for required in \
  nine_method_weekly_returns.csv \
  nine_method_own_support_summary.csv \
  nine_method_all_common_summary.csv \
  nine_method_by_data_axis_common_summary.csv \
  nine_method_by_method_common_summary.csv \
  nine_method_pairwise_common_week_summary.csv \
  nine_method_common_week_audit.mat; do
  [[ -s "$OUTPUT_DIR/$required" ]] || {
    echo "b19 required output is missing: $required" >&2
    exit 1
  }
done

(
  cd "$OUTPUT_DIR"
  find . -maxdepth 1 -type f \
    ! -name 'B19_OUTPUTS.sha256' ! -name 'B19_COMPLETE.env' \
    ! -name 'B19_FAILED.env' -printf '%P\0' | \
    LC_ALL=C sort -z | xargs -0 -r sha256sum
) > "$OUTPUT_DIR/B19_OUTPUTS.sha256"
(cd "$OUTPUT_DIR" && sha256sum -c B19_OUTPUTS.sha256 >/dev/null)
COMMON_N="$(awk -F, 'NR==2{print $3;exit}' \
  "$OUTPUT_DIR/nine_method_all_common_summary.csv")"
{
  echo 'format=ctrend-b19-common-week-complete-v1'
  echo 'methods=9'
  echo "all_nine_common_n=$COMMON_N"
  echo "input_bindings_sha256=$(sha256sum "$OUTPUT_DIR/b19_input_bindings.csv" | awk '{print $1}')"
  echo "outputs_inventory_sha256=$(sha256sum "$OUTPUT_DIR/B19_OUTPUTS.sha256" | awk '{print $1}')"
  echo 'missing_return_rule=intersection_only_no_imputation'
  echo "completed_at_utc=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
} > "$OUTPUT_DIR/B19_COMPLETE.env"
rm -f "$OUTPUT_DIR/B19_FAILED.env"
COMPLETE=1
echo "B19_COMMON_WEEK_ROBUSTNESS_OK output=$OUTPUT_DIR common_n=$COMMON_N"
