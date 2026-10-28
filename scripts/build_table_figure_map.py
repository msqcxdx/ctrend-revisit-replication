#!/usr/bin/env python3
"""Create the public paper-item map from the frozen coverage list and source code labels."""

import csv
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
INPUT = ROOT / "results/comparisons/source_tables/PAPER_ITEM_COVERAGE.csv"
OUTPUT = ROOT / "TABLE_FIGURE_MAP.csv"

CODE = {
    "Table 1": "b03Table1_ResearchSample.m",
    "Table 2": "b04Table2_TechnicalIndicatorStrategyReturns.m",
    "Table 3": "b06Table3_UnivariatePortfolioSorts.m",
    "Table 4": "b07Table4_CrossSectionalRegressions.m",
    "Table 5": "b08Table5_PerformanceInSubperiodsAndDifferentMarketStates.m",
    "Table 6": "b10Table6_FactorPerformanceAcrossResearchDesignChoices.m",
    "Table 7": "b12Table7_FrontierExpansionTest.m",
    "Table 8": "b13Table8_TheCTRENDFactorPerformanceInBigAndLiquidCryptos.m",
    "Table 9": "b14Table9_CTRENDPortfoliosAndTransactionCosts.m",
    "Table B.1": "Utils/characteristics.m;Utils/technical_indicators.m",
    "Table B.2": "b06Table3_UnivariatePortfolioSorts.m",
    "Table B.3": "b15TableB3_BivariatePortfolioSorts.m",
    "Table B.4": "b16TableB4_CTRENDPerformanceDependingOnCryptocurrencyType.m",
    "Table B.5": "b04Table2_TechnicalIndicatorStrategyReturns.m",
    "Table B.6": "b10Table6_FactorPerformanceAcrossResearchDesignChoices.m",
    "Table B.7": "b06Table3_UnivariatePortfolioSorts.m",
    "Table B.8": "b04Table2_TechnicalIndicatorStrategyReturns.m",
    "Table B.9": "b11Figure3_AnomalyAlphas.m",
    "Table B.10": "b17TableB10_ExtendedPortfolioHoldingPeriod.m",
    "Figure 1": "b06Table3_UnivariatePortfolioSorts.m",
    "Figure 2": "b10Table6_FactorPerformanceAcrossResearchDesignChoices.m",
    "Figure 3": "b11Figure3_AnomalyAlphas.m",
    "Figure B.1": "b10Table6_FactorPerformanceAcrossResearchDesignChoices.m",
    "Figure B.2": "b06Table3_UnivariatePortfolioSorts.m",
    "Figure C.3": "b18FigureC3_C4_AverageVariableImportance.m",
    "Figure C.4": "b18FigureC3_C4_AverageVariableImportance.m",
}
SCOPE = {
    "Table 1": "screened research sample and market-cap distribution",
    "Table 2": "technical-indicator univariate return sorts",
    "Table 3": "CTREND and comparator-factor univariate sorts",
    "Table 4": "cross-sectional return regressions",
    "Table 5": "factor performance by subperiod and market state",
    "Table 6": "research-design Sharpe distribution; own versus common support must be distinguished",
    "Table 7": "factor model frontier and tangency diagnostics",
    "Table 8": "CTREND performance in large and liquid assets",
    "Table 9": "portfolio turnover and modeled transaction-cost returns",
    "Table B.1": "characteristic definitions only; no numerical table cells exported",
    "Table B.2": "factor-return descriptive statistics",
    "Table B.3": "bivariate portfolio sorts",
    "Table B.4": "CTREND by cryptocurrency type",
    "Table B.5": "insignificant-anomaly strategy returns",
    "Table B.6": "value-weighted research-design comparison",
    "Table B.7": "univariate sorts under alternative factor data",
    "Table B.8": "anomaly portfolio returns for pricing tests",
    "Table B.9": "anomaly alpha under the TREND model",
    "Table B.10": "extended holding-period CTREND portfolios",
    "Figure 1": "factor mean and Sharpe displays",
    "Figure 2": "Sharpe distribution across research designs",
    "Figure 3": "anomaly alpha display",
    "Figure B.1": "value-weighted Sharpe distribution",
    "Figure B.2": "cumulative factor returns; zero-increment gap disclosure is a display rule",
    "Figure C.3": "average indicator importance",
    "Figure C.4": "indicator-selection frequency through time",
}


def main() -> None:
    with INPUT.open(newline="", encoding="utf-8") as handle:
        coverage = list(csv.DictReader(handle))
    if {row["paper_item"] for row in coverage} != set(CODE) or set(SCOPE) != set(CODE) or len(coverage) != len(CODE):
        raise SystemExit("paper coverage and code map disagree")
    with OUTPUT.open("w", newline="", encoding="utf-8") as handle:
        writer = csv.writer(handle)
        writer.writerow(("paper_item", "paper_location", "code_in_engines", "public_evidence", "controlled_output", "estimand_scope", "required_inputs", "public_status"))
        for row in coverage:
            item = row["paper_item"]
            figure = item.startswith("Figure")
            definition_only = item == "Table B.1"
            evidence = ("results/comparisons/source_tables/EIGHTEEN_EXPERIMENT_FIGURE_INVENTORY.csv" if figure else
                        "reference/dataverse_files.zip" if definition_only else
                        "results/comparisons/source_tables/EIGHTEEN_EXPERIMENT_ALL_TABLE_CELLS.csv")
            writer.writerow((
                item,
                row["paper_location"],
                "engines/{M0,M1,M2}/base/" + CODE[item],
                evidence,
                "18 accepted run roots: Figures/ or Tables/ (not public here)" if figure else "18 accepted run roots: Tables/ (not public here)",
                SCOPE[item],
                "licensed CMC OHLCV/cap panel and relevant auxiliary factors; MATLAB R2023b" if not definition_only else "author-deposited source and Appendix A definitions",
                "inventory only" if figure else "definition only" if definition_only else "aggregate cells available",
            ))
    print(f"TABLE_FIGURE_MAP_OK items={len(coverage)}")


if __name__ == "__main__":
    main()
