CORRECTED PIPELINE NOTICE

This directory implements one corrected replication convention. It is not the
unchanged published pipeline. Existing MAT, table, and figure outputs are
invalid and must not be used to infer source-code correctness.

The default run covers every empirical output in the paper and online
appendix, including the complete Table 6 grid. Run it with:

    ./run_full_pipeline_corrected.sh

The canonical runner exposes only three execution scopes:

    PIPELINE_SCOPE=full      # default: b00-b18 plus supplementary outputs
    PIPELINE_SCOPE=baseline  # baseline outputs without the Table 6 grid
    PIPELINE_SCOPE=table6    # Table 6 grid from certified weekly inputs

Set PARALLEL_WORKERS to cap the process pool explicitly. If omitted, the shell
runner requests the CPUs visible through nproc. PIPELINE_START_STEP and
PIPELINE_END_STEP may resume a scope only when source and data fingerprints
still match. Existing result files are never used as prediction caches.

After b18, the runner calls run_supplementary_outputs.sh to generate Figure
B.1/Table B.6 and Table B.7 from the paper's existing switches without
overwriting the main outputs. b02 constructs market-wide inputs before the
baseline asset filter. The raw CMC export must therefore retain stablecoins,
low-cap assets, and assets with internal history gaps; missing asset-date cells
stay NaN. The exact screening_summary.json contract is documented in
INPUT_DATA_REQUIREMENTS.md. Run setup.m, b00GenerateDesignChoices.m,
b01ReadData.m, and b02CalculateIndicators.m before downstream scripts.
The raw market return uses every asset-day with a finite current return and
positive finite lagged market cap, and re-normalizes those lagged-cap weights.
It does not impute a gap return as zero or inherit any strategy/CTREND mask.

The paper's same-date cross-sectional cleaning cannot be applied to the
current OOS target. b02 therefore keeps raw returns. In v2, each already-
realized historical training/validation week is cleaned on its own
formation-eligible cross-section. The target OOS statistical label is raw,
and economic OOS P&L always uses the genuine raw endpoint return; historical
label preprocessing never deletes or caps payoffs.
CTREND_Base.mat saves these as separate mRetLabelOOS and mRetPnlOOS matrices.
Table 4 remains a statistical-label regression and uses the raw strict OOS
label minus the risk-free rate; it does not substitute endpoint P&L.
Portfolio sorts, factor returns, turnover, costs, and holding-period results
use raw endpoint P&L. Validation variants reserve exactly the latest 12
in-sample weeks; because those weeks are already realized before the target,
each is cleaned using its own cross-section. If a selected holding's return is
missing, the portfolio leg is NaN: no zero replacement and no post-return
reweighting.

Every Table 6 predictive regression uses the paper's market-cap WLS objective.
The vUseValueWts switch changes only EW versus VW factor-portfolio accounting.
For every combination and method, b09 records scheduled, independently
eligible, finite, failed, and unexpected-failure weeks. Completion requires
at least 50% coverage of eligible prediction/tertile/quintile factor weeks and
zero unexpected failures; one successful week can never certify a method,
while structurally unidentified/undefined early weeks can remain NaN.
The paper Table 6 remains explicitly labelled method-specific
available-case. A parallel strict output recomputes all six baseline
estimators on all-method and pairwise common weeks within exactly the same
balanced design cells, without imputing failed weeks.
Unexpected lasso/toolbox/license/input errors are rethrown rather than silently
converted to all-NaN output. The top-level runner exports one validated
MATLAB_BIN to its supplementary child processes.
Figure 3 plots each anomaly's mean return on the exact finite sample used by
that model's alpha regression, and Table B.10 uses raw weekly returns throughout
each fixed-member holding block.

Execute the following files to reproduce the published analyses under these
corrected constraints for "A Trend Factor for the Cross-Section of Cryptocurrency Returns" by Fieberg, Liedtke, Poddig, Walker, Zaremba (JFQA).

Any separately supplied published CTREND factor data is a comparison benchmark
only. It is not corrected input, a cache, or evidence that the corrected
implementation is valid.

Please run setup.m to ensure that you have all available code and data
	- F-F_Research_Data_Factors_daily.CSV (Kenneth French's website)
	- LTW_3factor.xlsx (https://www.yukunliu.com/research/)
	- UCRY.csv (https://sites.google.com/view/cryptocurrency-indices/the-indices/crypto-uncertainty)
	- regstats2.m (https://de.mathworks.com/matlabcentral/fileexchange/26169-regstats2)
	- parfor_wait.m (https://de.mathworks.com/matlabcentral/fileexchange/71083-waitbar-for-parfor)

This code package also uses some functions written by others, however, in a modified Version. These functions
are provided in this package:
	- latexTable.m by Eli Duenisch (https://de.mathworks.com/matlabcentral/fileexchange/44274-latextable)
	- fGRS.m by Sven Thies (https://de.mathworks.com/matlabcentral/fileexchange/45898-grs-test-statistic)

To replicate the paper, please execute scripts in order.

1) b01GenerateArtificialData.m generates an artificial dataset (only useful for technical check)

2) b01ReadData.m reads the CoinmarketCap data and does some error elimination (not relevant for artificial dataset)

3) b02CalculateIndicators.m calculates all cryptocurrency characteristics and technical indicators required

4) b03Table1_ResearchSample.m creates
	- Table 1:		Research Sample

5) b04Table2_TechnicalIndicatorStrategyReturns.m creates
	- Table 2:	Technical Indicator Strategy Returns
	- Table B.5: 	Insignificant Anomaly Strategy Returns
	- Table B.8:    Anomaly Strategy Returns

6) b05CreateCTREND.m creates the CTREND factor

7) b06Table3_UnivariatePortfolioSorts.m creates
	- Table 3:	Univariate Portfolio Sorts
	- Figure 1:	Comparison of Cryptocurrency Factors
	- Figure B.2: 	Comparison of Cumulative Factor Returns
	- Table B.2:  	Descriptive Statistics of Asset Pricing Factor Returns
	- Table B.7:  	Univariate Portfolio Sorts - Alternative Factor Data (when setting lUseLTW to false)

8) b07Table4_CrossSectionalRegressions creates
	- Table 4: 	Cross-Sectional Regressions

9) b08Table5_PerformanceInSubperiodsAndDifferentMarketStates creates
	- Table 5: 	Performance in Subperiods and Different Market States

10) b09 and b10 create the paper's alternative Table 6 designs in full mode

11) b11Figure3_AnomalyAlphas creates
	- Figure 3: 	Anomaly Alphas
	- Table B.9: 	TREND Model Alphas

12) b12Table7_FrontierExpansionTest creates
	- Table 7: 	Frontier Expansion Test

13) b13Table8_TheCTRENDFactorPerformanceInBigAndLiquidCryptos creates
	- Table 8:	The CTREND Factor Performance in Big and Liquid Cryptocurrencies

14) b14Table9_CTRENDPortfoliosAndTransactionCosts creates 
	- Table 9: 	CTREND Portfolios and Transaction Costs

15) b15TableB3_BivariatePortfolioSorts creates
	- Table B.3: 	Bivariate Portfolio Sorts

16) b16TableB4_CTRENDPerformanceDependingOnCryptocurrencyType creates
	- Table B.4: 	CTREND Performance Depending on Cryptocurrency Type

17) b17TableB10_ExtendedPortfolioHoldingPeriod creates
	- Table B.10: 	Extended Portfolio Holding Periods

18) b18FigureC3_C4_AverageVariableImportance creates
	- Figure C.3: 	Average Variable Importance
	- Figure C.4:   Indicator Selection Over Time
