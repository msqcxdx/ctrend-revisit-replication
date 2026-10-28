#!/usr/bin/env bash
set -euo pipefail

CODE_DIR="${CODE_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)}"
MATLAB_BIN="${MATLAB_BIN:-$(command -v matlab 2>/dev/null || true)}"
PARALLEL_WORKERS="${PARALLEL_WORKERS:-12}"
OLD_PIPELINE_FULL="${OLD_PIPELINE_FULL:-0}"
RUN_ID="$(date +%Y%m%d_%H%M%S)"
LOG_DIR="$CODE_DIR/logs/old_pipeline_$RUN_ID"
LOG_FILE="$LOG_DIR/pipeline.log"
STATUS_FILE="$LOG_DIR/status.tsv"
PID_FILE="$CODE_DIR/logs/old_pipeline_latest.pid"

mkdir -p "$LOG_DIR" "$CODE_DIR/Results/CTREND" \
  "$CODE_DIR/Results/Figures" "$CODE_DIR/Results/Tables"
cd "$CODE_DIR"
echo "$$" > "$PID_FILE"

export MATLAB_PREFDIR="${MATLAB_PREFDIR:-$CODE_DIR/logs/matlab_pref_pipeline}"
export OLD_PIPELINE_FULL
export OLD_PIPELINE_JOB_STORAGE="${OLD_PIPELINE_JOB_STORAGE:-/tmp/dsctrend_old_parallel_$RUN_ID}"
export OMP_NUM_THREADS=1
export MKL_NUM_THREADS=1
export OPENBLAS_NUM_THREADS=1
export NUMEXPR_NUM_THREADS=1
mkdir -p "$MATLAB_PREFDIR" "$OLD_PIPELINE_JOB_STORAGE"

{
  echo "run_id=$RUN_ID"
  echo "code_dir=$CODE_DIR"
  echo "matlab=$MATLAB_BIN"
  echo "parallel_workers=$PARALLEL_WORKERS"
  if [[ "${OLD_PIPELINE_FULL,,}" == "1" || "${OLD_PIPELINE_FULL,,}" == "true" || "${OLD_PIPELINE_FULL,,}" == "yes" || "${OLD_PIPELINE_FULL,,}" == "on" ]]; then
    echo "pipeline_mode=old-full"
  else
    echo "pipeline_mode=old-baseline-only"
  fi
  echo "parallel_job_storage=$OLD_PIPELINE_JOB_STORAGE"
  echo "started_at=$(date -Is)"
} >> "$LOG_FILE"
printf "step\tstatus\tstarted_at\tended_at\trc\n" > "$STATUS_FILE"

run_matlab_step() {
  local step="$1"
  local started ended rc pool_setup job_storage
  started="$(date -Is)"
  printf "%s\tSTART\t%s\t\t\n" "$step" "$started" >> "$STATUS_FILE"
  echo "===== START $step $started =====" >> "$LOG_FILE"
  pool_setup=""
  if [[ "$step" == "b02CalculateIndicators" || \
        "$step" == "b05CreateCTREND" || \
        "$step" == "b09RunResearchDesigns" ]]; then
    job_storage="$OLD_PIPELINE_JOB_STORAGE/$step"
    mkdir -p "$job_storage"
    pool_setup="c=parcluster('local'); c.JobStorageLocation='$job_storage'; c.NumWorkers=$PARALLEL_WORKERS; saveProfile(c); parpool(c,$PARALLEL_WORKERS);"
  fi
  if "$MATLAB_BIN" -licmode onlinelicensing -nodisplay -nosplash -batch \
      "try, cd('$CODE_DIR'); $pool_setup run('$step.m'); fSaveOpenFigures('$step'); exit(0); catch ME, disp(getReport(ME,'extended','hyperlinks','off')); exit(1); end" \
      >> "$LOG_FILE" 2>&1; then
    rc=0
  else
    rc=$?
  fi
  ended="$(date -Is)"
  printf "%s\tEND\t%s\t%s\t%s\n" "$step" "$started" "$ended" "$rc" >> "$STATUS_FILE"
  echo "===== END $step rc=$rc $ended =====" >> "$LOG_FILE"
  return "$rc"
}

if [[ "${OLD_PIPELINE_FULL,,}" == "1" || "${OLD_PIPELINE_FULL,,}" == "true" || "${OLD_PIPELINE_FULL,,}" == "yes" || "${OLD_PIPELINE_FULL,,}" == "on" ]]; then
  STEPS=(
    setup
    b00GenerateDesignChoices
    b01ReadData
    b02CalculateIndicators
    b03Table1_ResearchSample
    b04Table2_TechnicalIndicatorStrategyReturns
    b05CreateCTREND
    b06Table3_UnivariatePortfolioSorts
    b07Table4_CrossSectionalRegressions
    b08Table5_PerformanceInSubperiodsAndDifferentMarketStates
    b09RunResearchDesigns
    b10Table6_FactorPerformanceAcrossResearchDesignChoices
    b11Figure3_AnomalyAlphas
    b12Table7_FrontierExpansionTest
    b13Table8_TheCTRENDFactorPerformanceInBigAndLiquidCryptos
    b14Table9_CTRENDPortfoliosAndTransactionCosts
    b15TableB3_BivariatePortfolioSorts
    b16TableB4_CTRENDPerformanceDependingOnCryptocurrencyType
    b17TableB10_ExtendedPortfolioHoldingPeriod
    b18FigureC3_C4_AverageVariableImportance
  )
else
  STEPS=(
    setup
    b00GenerateDesignChoices
    b00SelectBaselineOnlyForOldRun
    b01ReadData
    b02CalculateIndicators
    b03Table1_ResearchSample
    b04Table2_TechnicalIndicatorStrategyReturns
    b05CreateCTREND
    b06Table3_UnivariatePortfolioSorts
    b07Table4_CrossSectionalRegressions
    b08Table5_PerformanceInSubperiodsAndDifferentMarketStates
    b11Figure3_AnomalyAlphas
    b12Table7_FrontierExpansionTest
    b13Table8_TheCTRENDFactorPerformanceInBigAndLiquidCryptos
    b14Table9_CTRENDPortfoliosAndTransactionCosts
    b15TableB3_BivariatePortfolioSorts
    b16TableB4_CTRENDPerformanceDependingOnCryptocurrencyType
    b17TableB10_ExtendedPortfolioHoldingPeriod
    b18FigureC3_C4_AverageVariableImportance
  )
fi

for step in "${STEPS[@]}"; do
  run_matlab_step "$step"
done

if [[ "${OLD_PIPELINE_FULL,,}" == "1" || "${OLD_PIPELINE_FULL,,}" == "true" || "${OLD_PIPELINE_FULL,,}" == "yes" || "${OLD_PIPELINE_FULL,,}" == "on" ]]; then
  started="$(date -Is)"
  printf "supplementary_B1_B6_B7\tSTART\t%s\t\t\n" "$started" >> "$STATUS_FILE"
  echo "===== START supplementary_B1_B6_B7 $started =====" >> "$LOG_FILE"
  if "$CODE_DIR/run_supplementary_outputs.sh" >> "$LOG_FILE" 2>&1; then
    rc=0
  else
    rc=$?
  fi
  ended="$(date -Is)"
  printf "supplementary_B1_B6_B7\tEND\t%s\t%s\t%s\n" "$started" "$ended" "$rc" >> "$STATUS_FILE"
  echo "===== END supplementary_B1_B6_B7 rc=$rc $ended =====" >> "$LOG_FILE"
  [[ "$rc" -eq 0 ]]
fi

echo "completed_at=$(date -Is)" >> "$LOG_FILE"
