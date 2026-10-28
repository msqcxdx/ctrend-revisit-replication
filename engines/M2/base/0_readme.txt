Execute the following files to replicate the results in "A Trend Factor for the Cross-Section of Cryptocurrency Returns" by Fieberg, Liedtke, Poddig, Walker, Zaremba (JFQA)

For one automated run of every empirical table and figure in the paper and
online appendix, use:

    OLD_PIPELINE_FULL=1 PARALLEL_WORKERS=12 ./run_full_pipeline_old.sh

After b18, the runner calls run_supplementary_outputs.sh to generate Figure
B.1/Table B.6 and Table B.7 from the paper's existing switches without
overwriting the main Figure 2/Table 6 and Table 3/Table B.2 files.

The original CTREND factor data is available in ./Results/CTREND/CTREND.xlsx

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

1) b01GenerateArtificalData.m generates an artificial dataset (only useful for technical check)

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

10) b09RunResearchDesigns estimates the CTREND characteristic for all Research designs

11) b10Table6_FactorPerformanceAcrossResearchDesignChoices creates
	- Figure 2: 	Distribution of Sharpe Ratios under Alternative Research Designs
	- Table 6: 	Factor Performance across Research Design Choices

	and when Setting lUseEqualWeighting to false:
	- Figure B.1:   Distribution of Sharpe Ratios Under Alternative Research Designs (Value-Weighted Portfolios Only)
	- Table B.6: 	Factor Performance Depending on Research Design Choices without Equal-Weighting

12) b11Figure3_AnomalyAlphas creates
	- Figure 3: 	Anomaly Alphas
	- Table B.9: 	TREND Model Alphas

13) b12Table7_FrontierExpansionTest creates
	- Table 7: 	Frontier Expansion Test

14) b13Table8_TheCTRENDFactorPerformanceInBigAndLiquidCryptos creates
	- Table 8:	The CTREND Factor Performance in Big and Liquid Cryptocurrencies

15) b14Table9_CTRENDPortfoliosAndTransactionCosts creates 
	- Table 9: 	CTREND Portfolios and Transaction Costs

16) b15TableB3_BivariatePortfolioSorts creates
	- Table B.3: 	Bivariate Portfolio Sorts

17) b16TableB4_CTRENDPerformanceDependingOnCryptocurrencyType creates
	- Table B.4: 	CTREND Performance Depending on Cryptocurrency Type

18) b17TableB10_ExtendedPortfolioHoldingPeriod creates
	- Table B.10: 	Extended Portfolio Holding Periods

19) b18FigureC3_C4_AverageVariableImportance creates
	- Figure C.3: 	Average Variable Importance
	- Figure C.4:   Indicator Selection Over Time
