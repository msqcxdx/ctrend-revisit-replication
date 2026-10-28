#!/usr/bin/env bash
# CTREND_REVISIT_FILE_PURPOSE: Enforce the M2 causal delta, the declared P0/P1 input contract, and no-cash economic settlement.
set -euo pipefail

SOURCE="${1:-}"
[[ -d "$SOURCE/Utils" ]] || {
  echo "usage: $0 /absolute/m2/source" >&2
  exit 2
}
PREPROCESSING_ID="${CTREND_PREPROCESSING_ID:-P1}"
case "$PREPROCESSING_ID" in
  P0|P1) ;;
  *)
    echo 'CTREND_PREPROCESSING_ID must be P0 or P1' >&2
    exit 2
    ;;
esac

for file in \
  fCreatePanelExAnteM2.m fCleanWeeklyLabelsM2.m \
  fDemeanWeeklyM2.m fFilterM2EstimationSupport.m \
  fApplyUnifiedMissingDataPreprocessing.m \
  fBuildAndFreezeMechanicalExitCalendar.m \
  fBuildWeeklyEndpointPnl.m fBuildWeeklyReinvestmentLedger.m \
  fApplySameLegReinvestment.m fLoadEconomicReinvestmentLedger.m \
  fAttachEconomicLedgerOptions.m; do
  [[ -s "$SOURCE/Utils/$file" ]] || {
    echo "missing M2 contract helper: $file" >&2
    exit 1
  }
done

# The direct weekly look-ahead is removed: LAST may search only the already
# isolated current-week block.
grep -Fq 'mDataDailyTemp(:,idx)' "$SOURCE/Utils/fResampleLiuEtAl.m"
if grep -Fq "mDataTemp(find(~isnan(mDataTemp(:,idx)),1,'last'),idx)" \
    "$SOURCE/Utils/fResampleLiuEtAl.m"; then
  echo 'M2 resampler still searches the whole calendar year' >&2
  exit 1
fi

# P1 applies the common input layer before weekly construction. P0 is the
# registered ablation that removes exactly that call and diagnostic while
# retaining the frozen mechanical-exit calendar and the pre-P1 volume rule.
if [[ "$PREPROCESSING_ID" == P1 ]]; then
  grep -Fq 'fApplyUnifiedMissingDataPreprocessing' "$SOURCE/b01ReadData.m"
  grep -Fq 'rUnifiedMissingPreprocessing' "$SOURCE/b01ReadData.m"
else
  if rg -n 'fApplyUnifiedMissingDataPreprocessing|rUnifiedMissingPreprocessing' \
      "$SOURCE/b01ReadData.m" >/dev/null; then
    echo 'P0 M2 source still invokes or records unified preprocessing' >&2
    exit 1
  fi
  grep -Eq 'lReplaceVol[[:space:]]*=[[:space:]]*mVolume == 0 & isnan\(mReturns\)' \
    "$SOURCE/b01ReadData.m"
  grep -Eq 'mVolume\(lReplaceVol\)[[:space:]]*=[[:space:]]*NaN' \
    "$SOURCE/b01ReadData.m"
fi
grep -Fq 'fBuildAndFreezeMechanicalExitCalendar' "$SOURCE/b01ReadData.m"
grep -Fq 'mVolume(lVolumeFilled) = 0' \
  "$SOURCE/Utils/fApplyUnifiedMissingDataPreprocessing.m"
grep -Fq 'lFillsAfterLastOriginalClose = false' \
  "$SOURCE/Utils/fApplyUnifiedMissingDataPreprocessing.m"

# M2 keeps a historical statistical-label layer for its estimator while the
# economic layer uses prepared endpoint quotes and the authenticated event
# ledger.  The two layers must never be silently interchanged.
grep -Fq 'mReturnsM2Raw' "$SOURCE/b02CalculateIndicators.m"
grep -Fq 'mPnlReturnsM2' "$SOURCE/b02CalculateIndicators.m"
grep -Fq 'mPnlRetLeadM2' "$SOURCE/b02CalculateIndicators.m"
grep -Fq 'rEconomicReinvestmentLedgerReference' \
  "$SOURCE/b02CalculateIndicators.m"
grep -Fq 'fCleanWeeklyLabelsM2' "$SOURCE/b05CreateCTREND.m"
grep -Fq 'fCreatePanelExAnteM2' "$SOURCE/b05CreateCTREND.m"
grep -Fq 'vYEstimation' "$SOURCE/b09RunResearchDesigns.m"
grep -Fq 'mME_L1' "$SOURCE/b09RunResearchDesigns.m"

# Table 4 is a retrospective statistical-label regression and deliberately
# retains the M0 estimand.
grep -Fq 'mReturns        = rData.mReturns;' \
  "$SOURCE/b07Table4_CrossSectionalRegressions.m"
grep -Fq 'mReturnsLead    = rData.mRetLead;' \
  "$SOURCE/b07Table4_CrossSectionalRegressions.m"
if grep -Fq 'mReturnsM2Raw' "$SOURCE/b07Table4_CrossSectionalRegressions.m"; then
  echo 'M2 Table 4 no longer preserves the M0 statistical-label estimand' >&2
  exit 1
fi

# Reporting boundaries come from formation forecasts, never realized payoff
# completeness.
grep -Fq "find(any(~isnan(rCTREND.mYhat),1),1,'first')" \
  "$SOURCE/b08Table5_PerformanceInSubperiodsAndDifferentMarketStates.m"
if grep -Fq "find(all(~isnan(mPortRet),2),1,'first')" \
    "$SOURCE/b08Table5_PerformanceInSubperiodsAndDifferentMarketStates.m"; then
  echo 'M2 Table 5 still conditions its start on future payoff' >&2
  exit 1
fi
grep -Fq 'iFirstFormationForecast = find(any(mAnyFormationForecast,2)' \
  "$SOURCE/b09RunResearchDesigns.m"
grep -Fq 'iIdxFirst = iFirstFormationForecast;' \
  "$SOURCE/b10Table6_FactorPerformanceAcrossResearchDesignChoices.m"

# Weekly label cutoffs precede predictor-support construction and never use
# the later all-predictor availability intersection.
for file in b05CreateCTREND.m b09RunResearchDesigns.m; do
  grep -Fq 'fCleanWeeklyLabelsM2' "$SOURCE/$file"
  if grep -Fq 'mTrainingRaw(~lAvail)' "$SOURCE/$file"; then
    echo "M2 outlier cutoff still depends on predictor availability: $file" >&2
    exit 1
  fi
done

# M2 does not import M1's predictor-own estimator/importance definitions.
if rg -n 'fRankPredictorsOwnSupport|fImportanceCS_ENetPredictorSupport|fMeanForecastsFixedSet' \
    "$SOURCE" --glob '*.m'; then
  echo 'M2 imported a forbidden M1-only estimator definition' >&2
  exit 1
fi

# M2 retains M0's declared target-availability-before-breakpoint convention,
# but every actually formed economic leg is valued through the event ledger.
for file in fSingleSortFast.m fSingleSortMulti.m fDepDoubleSort.m \
    fIndepDoubleSort.m; do
  grep -Fq 'lAvail' "$SOURCE/Utils/$file"
  grep -Fq 'fApplySameLegReinvestment' "$SOURCE/Utils/$file"
done

# All direct economic-return consumers must authenticate/attach the ledger.
for file in \
  b04Table2_TechnicalIndicatorStrategyReturns.m \
  b05CreateCTREND.m \
  b06Table3_UnivariatePortfolioSorts.m \
  b13Table8_TheCTRENDFactorPerformanceInBigAndLiquidCryptos.m \
  b14Table9_CTRENDPortfoliosAndTransactionCosts.m \
  b15TableB3_BivariatePortfolioSorts.m \
  b16TableB4_CTRENDPerformanceDependingOnCryptocurrencyType.m \
  b17TableB10_ExtendedPortfolioHoldingPeriod.m; do
  grep -Fq 'mPnlReturnsM2' "$SOURCE/$file"
  grep -Fq 'fAttachEconomicLedgerOptions' "$SOURCE/$file"
done
grep -Fq 'mPnlReturnsM2' "$SOURCE/b09RunResearchDesigns.m"
grep -Fq 'fLoadEconomicReinvestmentLedger' "$SOURCE/b09RunResearchDesigns.m"

# Cash after a terminal event is not an admissible mode.  Initial formation
# from cash may still appear in comments/accounting, so reject the obsolete
# executable field rather than the word itself.
if rg -n 'mLiquidatedToCash|vEndCashWeight|lProceedsRemainCash\s*=\s*true' \
    "$SOURCE" --glob '*.m'; then
  echo 'M2 contains an obsolete post-terminal cash accounting path' >&2
  exit 1
fi
grep -Fq 'lAllowsCashAfterExit = false' \
  "$SOURCE/Utils/fBuildWeeklyReinvestmentLedger.m"
grep -Fq 'lEndCashAlwaysZero = true' \
  "$SOURCE/Utils/fApplySameLegReinvestment.m"
grep -Fq 'lCrossLegTransfer = false' \
  "$SOURCE/Utils/fApplySameLegReinvestment.m"

# GKX drift into target t can use only the preceding holding state.
grep -Fq 'mRetDriftL1 = [zeros(iNumAssets,1), mRet(:,1:end-1)]' \
  "$SOURCE/Utils/fSingleSortMulti.m"
if grep -Fq 'mWtsTempL1 .* (1 + mRet)' \
    "$SOURCE/Utils/fSingleSortMulti.m"; then
  echo 'M2 GKX turnover still uses the current target payoff' >&2
  exit 1
fi

if [[ "$PREPROCESSING_ID" == P1 ]]; then
  INPUT_MARKER='shared_input_fill=1'
else
  INPUT_MARKER='shared_input_fill=0 p0_legacy_missing_contract=1'
fi
echo "M2_STATIC_GUARDS_OK preprocessing=$PREPROCESSING_ID causal_support=1 $INPUT_MARKER frozen_exit=1 same_leg_reinvestment=1 no_cash=1 table4_m0_label=1 reporting_formation_boundary=1 causal_turnover_timing=1"
