#!/usr/bin/env bash
set -euo pipefail

code_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

require_text() {
  local pattern="$1"
  local file="$2"
  if ! rg -q -- "$pattern" "$code_dir/$file"; then
    printf 'Missing required v2 guard: %s in %s\n' "$pattern" "$file" >&2
    exit 1
  fi
}

reject_text() {
  local pattern="$1"
  shift
  if rg -q -- "$pattern" "$@"; then
    printf 'Forbidden v2 pattern found: %s\n' "$pattern" >&2
    exit 1
  fi
}

require_text "vYoutLabel = vYoutRaw" \
  "Utils/fPrepareWalkforwardOutcomes.m"
require_text "vYoutPnl = vYoutEvaluationRaw" \
  "Utils/fPrepareWalkforwardOutcomes.m"
require_text "own_cross_section_for_each_historical_week" \
  "Utils/fPrepareWalkforwardOutcomes.m"
require_text "never an OOS or future week" \
  "Utils/fPrepareWalkforwardOutcomes.m"
require_text "independent formation-" \
  "Utils/fPrepareWalkforwardOutcomes.m"

require_text "fApplyV2RawDataCorrections" "b01ReadData.m"
require_text "economic close/P&L are never masked and no missing value is filled" \
  "Utils/fApplyV2RawDataCorrections.m"
require_text "different CMCIDs are not" \
  "Utils/fApplyV2RawDataCorrections.m"
require_text "2603,.*9040" "tests/test_v2_raw_data_corrections.m"
require_text 'sRawMode == "none"' "tests/run_corrected_unit_tests.m"
require_text "V2_NO_ADJUSTMENT_MODE_TEST_OK" \
  "tests/test_v2_no_adjustment_mode.m"
require_text "uses_future_observations.*False" \
  "audit/build_causal_point_correction_manifest.py"
require_text "magnitude triggers investigation only" \
  "audit/classify_all_extreme_events.py"
reject_text "confirmed_external_corrupt_price_cells.csv" \
  "$code_dir/b01ReadData.m" "$code_dir/Utils/fApplyV2RawDataCorrections.m"
reject_text "v2_external_corrupt_price_cells.csv" \
  "$code_dir/b01ReadData.m" \
  "$code_dir/Utils/fApplyV2RawDataCorrections.m" \
  "$code_dir/Utils/fPipelineCodeFingerprint.m"
reject_text "bitcny_isolated_vendor_price_error" \
  "$code_dir/Utils/fApplyV2RawDataCorrections.m"

line_correction="$(rg -n "fApplyV2RawDataCorrections" \
  "$code_dir/b01ReadData.m" | tail -1 | cut -d: -f1)"
line_pnl_snapshot="$(rg -n '^mClosePnlRaw = mClose;' \
  "$code_dir/b01ReadData.m" | cut -d: -f1)"
line_initial_return="$(rg -n '^mReturns = ' \
  "$code_dir/b01ReadData.m" | head -1 | cut -d: -f1)"
if (( line_correction >= line_pnl_snapshot || \
      line_correction >= line_initial_return )); then
  printf 'Raw unit correction does not precede P&L/return construction\n' >&2
  exit 1
fi

require_text "fBuildHistoricalWeeklyOutlierAudit" "b05CreateCTREND.m"
require_text "fBuildHistoricalWeeklyOutlierAudit" "b09RunResearchDesigns.m"
reject_text "fBuildRollingOutlierAudit\\(" \
  "$code_dir/b05CreateCTREND.m" "$code_dir/b09RunResearchDesigns.m"

require_text "yticks\\(vAverageYTicks\\)" \
  "b06Table3_UnivariatePortfolioSorts.m"
require_text "yticks\\(vSharpeYTicks\\)" \
  "b06Table3_UnivariatePortfolioSorts.m"
require_text "yline\\(0" "b06Table3_UnivariatePortfolioSorts.m"
require_text "vDisplayIncrement\\(~isfinite\\(vDisplayIncrement\\)\\) = 0" \
  "Utils/fCumulativeFactorReturnDisplayZeroGaps.m"
require_text "fCumulativeFactorReturnDisplayZeroGaps" \
  "b06Table3_UnivariatePortfolioSorts.m"
require_text "gaps = 0" "b06Table3_UnivariatePortfolioSorts.m"
require_text "dynamic_rebuild=1" "tests/test_figure_b2_results.m"
require_text "mExpected\(iExpectedFirst:end,:\) = cumsum" \
  "tests/test_figure_b2_results.m"
reject_text "accepted real-data scientific support has 36|>= 36" \
  "$code_dir/tests/test_figure_b2_results.m"
reject_text "vSingletonEpisode" \
  "$code_dir/b06Table3_UnivariatePortfolioSorts.m"
require_text "cCharNamesSortedTex = fAddSlash\\(cCharNamesSorted,false\\)" \
  "b18FigureC3_C4_AverageVariableImportance.m"
reject_text "fAddSlash\\(fAddSlash\\(cCharNamesSorted" \
  "$code_dir/b18FigureC3_C4_AverageVariableImportance.m"

require_text "55296" \
  "b10Table6_FactorPerformanceAcrossResearchDesignChoices.m"
require_text "fTable6CommonWeekStats" \
  "b10Table6_FactorPerformanceAcrossResearchDesignChoices.m"
require_text "fTable6BalancedCellGate" \
  "b10Table6_FactorPerformanceAcrossResearchDesignChoices.m"
require_text "table6_strict_common_week_comparison" \
  "b10Table6_FactorPerformanceAcrossResearchDesignChoices.m"
require_text "PairCommonN" \
  "b10Table6_FactorPerformanceAcrossResearchDesignChoices.m"
require_text "Jaccard" \
  "b10Table6_FactorPerformanceAcrossResearchDesignChoices.m"
require_text "lAllMethodBalancedCell" \
  "b10Table6_FactorPerformanceAcrossResearchDesignChoices.m"
require_text "AllMethodBalancedDesignCells" \
  "b10Table6_FactorPerformanceAcrossResearchDesignChoices.m"
require_text "vAllMethodCommonOverlap" \
  "b10Table6_FactorPerformanceAcrossResearchDesignChoices.m"
require_text "PairCommonScheduledCoverage" \
  "b10Table6_FactorPerformanceAcrossResearchDesignChoices.m"
require_text "StatusExpectedNoAdmissibleLambda" \
  "b10Table6_FactorPerformanceAcrossResearchDesignChoices.m"
require_text "Pairwise Common-Week Estimator Comparisons ' ..." \
  "b10Table6_FactorPerformanceAcrossResearchDesignChoices.m"
require_text "Estimator Coverage and Failure Audit ' ..." \
  "b10Table6_FactorPerformanceAcrossResearchDesignChoices.m"
require_text "factor_performance_across_research_design_choices_paper_method_specific_available_case.tex" \
  "run_supplementary_outputs.sh"
require_text "factor_performance_across_research_design_choices_value_weighted_only_paper_method_specific_available_case.tex" \
  "run_supplementary_outputs.sh"
require_text "table_6_panel_b_pairwise_common_week_estimator_comparisons_value_weighted_only.tex" \
  "run_supplementary_outputs.sh"
require_text "table_6_panel_d_estimator_coverage_and_failure_audit_value_weighted_only.tex" \
  "run_supplementary_outputs.sh"

require_text "1,000.215" "EVENT_RETURN_AUDIT.md"
require_text "bitcointalk.org/index.php\\?topic=5242368.0" \
  "EVENT_RETURN_AUDIT.md"
require_text "medium.com/furucombo/announcing-combo-token-launch" \
  "EVENT_RETURN_AUDIT.md"

printf 'V2_STATIC_GUARDS_OK\n'
