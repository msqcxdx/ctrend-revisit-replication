#!/usr/bin/env bash
set -euo pipefail

CODE_DIR="${CODE_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)}"
MATLAB_BIN="${MATLAB_BIN:-$(command -v matlab 2>/dev/null || true)}"
PARALLEL_WORKERS="${PARALLEL_WORKERS:-64}"

# shellcheck source=run_safety.sh
source "$CODE_DIR/run_safety.sh"

[[ -n "$MATLAB_BIN" ]] || {
  echo "MATLAB is not on PATH; set MATLAB_BIN explicitly" >&2
  exit 2
}
if [[ "$MATLAB_BIN" == */* ]]; then
  [[ -x "$MATLAB_BIN" ]] || {
    echo "MATLAB_BIN is not executable: $MATLAB_BIN" >&2
    exit 2
  }
else
  command -v "$MATLAB_BIN" >/dev/null 2>&1 || {
    echo "MATLAB_BIN is not on PATH: $MATLAB_BIN" >&2
    exit 2
  }
  MATLAB_BIN="$(command -v "$MATLAB_BIN")"
fi
[[ "$PARALLEL_WORKERS" =~ ^[1-9][0-9]*$ ]] || {
  echo "PARALLEL_WORKERS must be a positive integer" >&2
  exit 2
}
printf 'MATLAB_BIN=%s\n' "$MATLAB_BIN"

if [[ "${CTREND_PIPELINE_LOCK_HELD:-0}" != 1 ]]; then
  command -v flock >/dev/null 2>&1 || {
    echo "flock is required to serialize corrected-pipeline writers" >&2
    exit 2
  }
  mkdir -p "$CODE_DIR/logs"
  exec 9>"$CODE_DIR/logs/corrected_pipeline.lock"
  if ! flock -n 9; then
    echo "Another corrected-pipeline writer is still active" >&2
    exit 75
  fi
  export CTREND_PIPELINE_LOCK_HELD=1
fi

RESULT_TABLES="$CODE_DIR/Results/Tables"
RESULT_FIGURES="$CODE_DIR/Results/Figures"
for required in \
    "$RESULT_TABLES/univariate_portfolio_sorts.tex" \
    "$RESULT_TABLES/descriptive_statistics_of_asset_pricing_factor_returns.tex" \
    "$RESULT_TABLES/factor_performance_across_research_design_choices_paper_method_specific_available_case.tex" \
    "$RESULT_TABLES/median_method_specific_weekly_observation_counts_underlying_table_6.tex" \
    "$CODE_DIR/b06Table3_UnivariatePortfolioSorts.m" \
    "$CODE_DIR/b10Table6_FactorPerformanceAcrossResearchDesignChoices.m"; do
  [[ -f "$required" ]] || {
    echo "Missing prerequisite: $required" >&2
    exit 1
  }
done

created_runtime_root=0
RUNTIME_TEMP_ROOT="${CTREND_SUPPLEMENTARY_TEMP_ROOT:-}"
if [[ -z "$RUNTIME_TEMP_ROOT" ]]; then
  RUNTIME_TEMP_ROOT="$(mktemp -d /tmp/ctrend_supplementary_XXXXXX)"
  # mktemp created the directory; remove it so preparation can prove
  # ownership by creating the marker before MATLAB writes anything.
  rmdir "$RUNTIME_TEMP_ROOT"
  ctrend_prepare_temp_dir "$RUNTIME_TEMP_ROOT" /tmp supplementary
  created_runtime_root=1
fi

if [[ -z "${MATLAB_PREFDIR:-}" ]]; then
  MATLAB_PREFDIR="$RUNTIME_TEMP_ROOT/matlab_pref"
  export MATLAB_PREFDIR
fi
if [[ -z "${PIPELINE_JOB_STORAGE:-}" ]]; then
  PIPELINE_JOB_STORAGE="$RUNTIME_TEMP_ROOT/parallel_job_storage"
  export PIPELINE_JOB_STORAGE
fi

cleanup_runtime() {
  local rc=$?
  trap - EXIT INT TERM
  if (( created_runtime_root == 1 )); then
    ctrend_safe_remove_temp_dir "$RUNTIME_TEMP_ROOT" /tmp || rc=1
  else
    ctrend_safe_remove_temp_dir "$MATLAB_PREFDIR" "$RUNTIME_TEMP_ROOT" || rc=1
    ctrend_safe_remove_temp_dir "$PIPELINE_JOB_STORAGE" "$RUNTIME_TEMP_ROOT" || rc=1
  fi
  exit "$rc"
}
trap cleanup_runtime EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

ctrend_prepare_temp_dir "$MATLAB_PREFDIR" "$RUNTIME_TEMP_ROOT" matlab_preferences
ctrend_prepare_temp_dir "$PIPELINE_JOB_STORAGE" "$RUNTIME_TEMP_ROOT" parallel_job_storage

export CODE_DIR MATLAB_BIN PARALLEL_WORKERS
export OMP_NUM_THREADS=1
export MKL_NUM_THREADS=1
export OPENBLAS_NUM_THREADS=1
export NUMEXPR_NUM_THREADS=1

echo "Generating Table B.7 from the explicit alternative-factor variant"
CTREND_OUTPUT_VARIANT=alternative_factor \
  "$MATLAB_BIN" -licmode onlinelicensing -nodisplay -nosplash -batch \
  "try, codeDir=getenv('CODE_DIR'); cd(codeDir); addpath('./Utils'); fEnsureParallelPoolExact(str2double(getenv('PARALLEL_WORKERS')),fullfile(getenv('PIPELINE_JOB_STORAGE'),'supp_b7')); run('b06Table3_UnivariatePortfolioSorts.m'); exit(0); catch ME, disp(getReport(ME,'extended','hyperlinks','off')); exit(1); end"

echo "Generating Figure B.1 and Table B.6 from the explicit value-weighted variant"
CTREND_OUTPUT_VARIANT=value_weighted_only \
  "$MATLAB_BIN" -licmode onlinelicensing -nodisplay -nosplash -batch \
  "try, codeDir=getenv('CODE_DIR'); cd(codeDir); addpath('./Utils'); fEnsureParallelPoolExact(str2double(getenv('PARALLEL_WORKERS')),fullfile(getenv('PIPELINE_JOB_STORAGE'),'supp_b1_b6')); run('b10Table6_FactorPerformanceAcrossResearchDesignChoices.m'); fSaveOpenFigures('b10FigureB1_ValueWeightedResearchDesigns'); exit(0); catch ME, disp(getReport(ME,'extended','hyperlinks','off')); exit(1); end"

for output in \
    "$RESULT_TABLES/univariate_portfolio_sorts_alternative_factor_data.tex" \
    "$RESULT_TABLES/factor_performance_across_research_design_choices_value_weighted_only_paper_method_specific_available_case.tex" \
    "$RESULT_TABLES/median_method_specific_weekly_observation_counts_underlying_table_b_6.tex" \
    "$RESULT_TABLES/table6_method_specific_week_counts_value_weighted_only.csv" \
    "$RESULT_TABLES/table6_method_specific_week_counts_value_weighted_only.mat" \
    "$RESULT_TABLES/table_6_panel_b_pairwise_common_week_estimator_comparisons_value_weighted_only.tex" \
    "$RESULT_TABLES/table_6_panel_d_estimator_coverage_and_failure_audit_value_weighted_only.tex" \
    "$RESULT_FIGURES/b10FigureB1_ValueWeightedResearchDesigns_figure01.png" \
    "$RESULT_FIGURES/b10FigureB1_ValueWeightedResearchDesigns_figure02.png" \
    "$RESULT_FIGURES/b10FigureB1_ValueWeightedResearchDesigns_figure03.png" \
    "$RESULT_FIGURES/b10FigureB1_ValueWeightedResearchDesigns_figure04.png"; do
  [[ -s "$output" ]] || {
    echo "Supplementary output missing: $output" >&2
    exit 1
  }
done

echo "Supplementary outputs completed"
