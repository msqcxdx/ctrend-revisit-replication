#!/usr/bin/env python3
# CTREND_REVISIT_FILE_PURPOSE: Trace every M2 causal return, support, screen, sort, and reporting definition to its direct consumers.
"""Trace M2 return/support definitions to every direct b03--b18 consumer."""

# Static wiring contract: scan the actual M2 scripts and require each declared
# statistical-return and economic-payoff consumer to read the intended layer.
# This catches a partial causal fix in which one downstream table silently
# continues to use an M0 field.  It does not assert any empirical coefficient.

from __future__ import annotations

import re
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
M0 = ROOT / "engines" / "M0" / "base"
M2 = ROOT / "engines" / "M2" / "base"

M2_STATISTICAL_LAYER_CONSUMERS = {
    "b04Table2_TechnicalIndicatorStrategyReturns.m",
    "b05CreateCTREND.m",
    "b06Table3_UnivariatePortfolioSorts.m",
    "b09RunResearchDesigns.m",
    "b13Table8_TheCTRENDFactorPerformanceInBigAndLiquidCryptos.m",
    "b14Table9_CTRENDPortfoliosAndTransactionCosts.m",
    "b15TableB3_BivariatePortfolioSorts.m",
    "b16TableB4_CTRENDPerformanceDependingOnCryptocurrencyType.m",
    "b17TableB10_ExtendedPortfolioHoldingPeriod.m",
    "b18FigureC3_C4_AverageVariableImportance.m",
}
ECONOMIC_PAYOFF_CONSUMERS = {
    "b04Table2_TechnicalIndicatorStrategyReturns.m",
    "b05CreateCTREND.m",
    "b06Table3_UnivariatePortfolioSorts.m",
    "b09RunResearchDesigns.m",
    "b13Table8_TheCTRENDFactorPerformanceInBigAndLiquidCryptos.m",
    "b14Table9_CTRENDPortfoliosAndTransactionCosts.m",
    "b15TableB3_BivariatePortfolioSorts.m",
    "b16TableB4_CTRENDPerformanceDependingOnCryptocurrencyType.m",
    "b17TableB10_ExtendedPortfolioHoldingPeriod.m",
}
M2_ACTIVE_RETURN_CONSUMERS = (
    M2_STATISTICAL_LAYER_CONSUMERS | ECONOMIC_PAYOFF_CONSUMERS
)
M0_STATISTICAL_CONSUMERS = {
    "b03Table1_ResearchSample.m",
    "b07Table4_CrossSectionalRegressions.m",
    "b08Table5_PerformanceInSubperiodsAndDifferentMarketStates.m",
}


def text(path: Path) -> str:
    return path.read_text(encoding="utf-8", errors="replace")


def direct_return_consumers() -> tuple[set[str], set[str], set[str]]:
    # Classify direct field reads before comparing them with the audited sets.
    model_label: set[str] = set()
    economic: set[str] = set()
    statistical: set[str] = set()
    for path in M2.glob("b*.m"):
        body = text(path)
        if "rData.mReturnsM2Raw" in body:
            model_label.add(path.name)
        if "rData.mPnlReturnsM2" in body:
            economic.add(path.name)
        if re.search(r"rData\.mReturns(?!M2Raw)", body):
            statistical.add(path.name)
    # b02 defines both layers; it is their producer rather than a downstream
    # table/model consumer.
    model_label.discard("b02CalculateIndicators.m")
    economic.discard("b02CalculateIndicators.m")
    statistical.discard("b02CalculateIndicators.m")
    return model_label, economic, statistical


def main() -> int:
    # Exact set equality is deliberate: a newly added consumer must be reviewed.
    model_label, economic, statistical = direct_return_consumers()
    assert model_label == M2_STATISTICAL_LAYER_CONSUMERS, (
        "M2 statistical-layer consumer drift "
        f"missing={sorted(M2_STATISTICAL_LAYER_CONSUMERS-model_label)} "
        f"extra={sorted(model_label-M2_STATISTICAL_LAYER_CONSUMERS)}"
    )
    assert economic == ECONOMIC_PAYOFF_CONSUMERS, (
        "M2 economic-payoff consumer drift "
        f"missing={sorted(ECONOMIC_PAYOFF_CONSUMERS-economic)} "
        f"extra={sorted(economic-ECONOMIC_PAYOFF_CONSUMERS)}"
    )
    assert statistical == M0_STATISTICAL_CONSUMERS, (
        f"M2 statistical-label consumer drift "
        f"missing={sorted(M0_STATISTICAL_CONSUMERS-statistical)} "
        f"extra={sorted(statistical-M0_STATISTICAL_CONSUMERS)}"
    )

    b02 = text(M2 / "b02CalculateIndicators.m")
    raw_snapshot = b02.index("rData.mReturnsM2Raw = mReturns")
    outlier_switch = b02.index("switch upper(sOutlierTreatment)")
    assert raw_snapshot < outlier_switch
    assert "rData.mRetLeadM2Raw = lagmatrix(mReturns,-1)" in b02
    assert "rData.mReturnsM2Raw = rData.mReturnsM2Raw-1" in b02
    assert "rData.mRetLeadM2Raw = rData.mRetLeadM2Raw-1" in b02

    for filename in M2_ACTIVE_RETURN_CONSUMERS:
        body = text(M2 / filename)
        assert "mME_L1" in body and "mPrices_L1" in body, filename
        assert re.search(r"mME_L1\s*<\s*dMinMCAP", body), filename
        assert re.search(r"mPrices_L1\s*<\s*dMinPrc", body), filename

    for filename in M2_STATISTICAL_LAYER_CONSUMERS:
        body = text(M2 / filename)
        assert re.search(r"mReturns\s*=\s*rData\.mReturnsM2Raw;", body), filename
        assert re.search(r"mReturnsLead\s*=\s*rData\.mRetLeadM2Raw;", body), filename

    for filename in ECONOMIC_PAYOFF_CONSUMERS:
        body = text(M2 / filename)
        assert "rData.mPnlReturnsM2" in body, filename
        assert "rData.mPnlRetLeadM2" in body, filename
        if filename == "b09RunResearchDesigns.m":
            assert "fLoadEconomicReinvestmentLedger" in body, filename
        else:
            assert "fAttachEconomicLedgerOptions" in body, filename
    figure_c = text(M2 / "b18FigureC3_C4_AverageVariableImportance.m")
    assert "mPnlReturnsM2" not in figure_c

    # Descriptive Table 1 is unchanged. Table 4 keeps the M0 statistical
    # estimand but uses formation screens. Table 5 keeps M0 state inputs and
    # changes only the future-payoff-conditioned sample boundary.
    assert (M2 / "b03Table1_ResearchSample.m").read_bytes() == (
        M0 / "b03Table1_ResearchSample.m"
    ).read_bytes()
    b07 = text(M2 / "b07Table4_CrossSectionalRegressions.m")
    assert "mReturns        = rData.mReturns;" in b07
    assert "mReturnsM2Raw" not in b07
    assert "mME_L1" in b07 and "mPrices_L1" in b07
    b08 = text(M2 / "b08Table5_PerformanceInSubperiodsAndDifferentMarketStates.m")
    assert "find(any(~isnan(rCTREND.mYhat),1),1,'first')" in b08
    assert "find(all(~isnan(mPortRet),2),1,'first')" not in b08

    # b05 and b09 rank/screen before creating an ex-ante panel, clean labels
    # before predictor support, and never let Y define the prediction rows.
    for filename in ("b05CreateCTREND.m", "b09RunResearchDesigns.m"):
        body = text(M2 / filename)
        rank_at = body.index("fCrossSectTransChars")
        clean_at = body.index("fCleanWeeklyLabelsM2")
        panel_at = body.index("fCreatePanelExAnteM2")
        assert rank_at < clean_at < panel_at, filename
        assert "vYEstimation" in body
        assert "mTrainingRaw(~lAvail)" not in body
    b09 = text(M2 / "b09RunResearchDesigns.m")
    assert "iFirstFormationForecast" in b09
    b10 = text(M2 / "b10Table6_FactorPerformanceAcrossResearchDesignChoices.m")
    assert "iIdxFirst = iFirstFormationForecast;" in b10
    assert "find(any(~isnan(mTrend_5),2),1,'first')" not in b10

    panel = text(M2 / "Utils" / "fCreatePanelExAnteM2.m")
    assert "lRemove = any(isnan(mX),2);" in panel
    assert "isnan(vY)" not in panel
    assert "isfinite" not in panel

    for filename in (
        "fWalkforwardCENET.m", "fWalkforwardCSENET.m",
        "fWalkforwardFamaMacBethPanel.m", "fWalkforwardPanelRegression.m",
    ):
        body = text(M2 / "Utils" / filename)
        assert "vYEstimation" in body, filename
        assert "fFilterM2EstimationSupport" in body, filename
        assert body.index("lIsDataOut") < body.index(
            "fFilterM2EstimationSupport"
        ), filename

    for filename in (
        "fSingleSortFast.m", "fSingleSortMulti.m",
        "fDepDoubleSort.m", "fIndepDoubleSort.m",
    ):
        body = text(M2 / "Utils" / filename)
        # The accepted target-availability/reweighting rule is inherited
        # directly from M0. It is not itself an M2 look-ahead correction.
        assert re.search(r"lAvail\s*=.*~isnan\(mRet\)", body), filename
        availability_at = body.index("lAvail")
        breakpoint_at = min(
            index for token in ("quantile(", "mQuantiles")
            if (index := body.find(token)) >= 0
        )
        assert availability_at < breakpoint_at, filename
    single = text(M2 / "Utils" / "fSingleSortMulti.m")
    assert re.search(
        r"mRetDriftL1\s*=\s*\[zeros\(iNumAssets,1\),\s*"
        r"mRet\(:,1:end-1\)\]", single
    )
    assert "mWtsTempL1 .* (1 + mRet)" not in single

    # b11/b12 are downstream factor consumers and need no asset-level causal
    # change; byte equality prevents an unnecessary M1 definition leaking in.
    for filename in (
        "b11Figure3_AnomalyAlphas.m",
        "b12Table7_FrontierExpansionTest.m",
    ):
        assert (M2 / filename).read_bytes() == (M0 / filename).read_bytes()

    all_m2 = "\n".join(
        text(path) for path in M2.rglob("*.m") if path.is_file()
    )
    for forbidden in (
        "fRankPredictorsOwnSupport", "fImportanceCS_ENetPredictorSupport",
        "fWeeklyEndpointPnl", "fMeanForecastsFixedSet",
    ):
        assert forbidden not in all_m2, f"M2 imported M1 definition: {forbidden}"
    assert "mLiquidatedToCash" not in all_m2
    ledger = text(M2 / "Utils" / "fApplySameLegReinvestment.m")
    assert "lEndCashAlwaysZero = true" in ledger
    assert "lCrossLegTransfer = false" in ledger
    preprocessing = text(
        M2 / "Utils" / "fApplyUnifiedMissingDataPreprocessing.m"
    )
    assert "mVolume(lVolumeFilled) = 0" in preprocessing
    assert "lFillsAfterLastOriginalClose = false" in preprocessing

    print(
        "M2_CONSUMER_MATRIX_OK "
        f"model_label_consumers={len(model_label)} "
        f"economic_payoff_consumers={len(economic)} "
        f"statistical_consumers={len(statistical)} "
        "formation_screens=1 ex_ante_panel=1 historical_label_slices=1 "
        "announced_target_reallocation=1 endpoint_same_leg_reinvestment=1 "
        "no_cash=1 unified_missing_preprocessing=1 "
        "forbidden_m1_imports=0"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
