#!/usr/bin/env python3
# CTREND_REVISIT_FILE_PURPOSE: Generate the nine comment-only review mirrors, their diff index, and integrity inventories.
"""Build nine comment-only review mirrors with an explicit evidence chain.

The executable body of every annotated text file is copied byte-for-byte from
the corresponding materialized experiment source. M0 is compared with the
Dataverse source. M1 and M2 both use the transparent two-step chain
Dataverse-to-M0-to-method, so inherited M0 adapters and the explicitly shared
new-v2 input amendment cannot be mistaken for an M1/M2-only correction. The
canonical engines are never edited.
"""

from __future__ import annotations

import csv
import difflib
import hashlib
import os
from pathlib import Path
import shutil
import stat
import sys
import tempfile
import textwrap


TEXT_SUFFIXES = {".m", ".sh", ".py", ".bat"}
HEADER_BEGIN = "CTREND_REVISIT_ANNOTATION_HEADER_V4_BEGIN"
HEADER_END = "CTREND_REVISIT_ANNOTATION_HEADER_V4_END"
MAX_HEADER_WIDTH = 100
EXPERIMENTS = [f"M{m}_D{d}" for m in range(3) for d in range(3)]


M0_REASONS = {
    "LatexTables/fCreateLatexTable.m": (
        "reporting-engineering",
        "Adds deterministic, headless table-file publication while preserving the table cells supplied by the caller.",
        "No scientific-number change; only output routing and filename sanitation.",
    ),
    "Utils/fComputeOldFeaturesParallel.m": (
        "bit-exact-parallel-engineering",
        "Schedules asset-separable published characteristic formulas in column chunks and merges fields in their original order.",
        "Required to pass the 59-field serial/parallel bit-exact equivalence gate.",
    ),
    "Utils/fApplyUnifiedMissingDataPreprocessing.m": (
        "shared-missing-data-preprocessing",
        "Applies the new-v2 rule common to M0/M1/M2: missing/invalid OHLC uses the strictly prior valid close, while non-finite or negative volume/turnover becomes zero.",
        "This is an explicit common input amendment, not a method-axis contrast; leading and post-terminal prices remain missing.",
    ),
    "Utils/fBuildAndFreezeMechanicalExitCalendar.m": (
        "shared-exit-calendar-provenance",
        "Freezes each asset's last positive close before any model or portfolio stage and records right-censored sample-end assets.",
        "M0 publishes this provenance artifact but retains the Dataverse downstream portfolio logic; M1/M2 consume it for terminal settlement.",
    ),
    "Utils/fFileSHA256.m": (
        "streaming-content-identity-helper",
        "The Dataverse archive does not content-bind preprocessing and frozen mechanical-exit artifacts. This bounded-memory helper computes their exact SHA-256 identities for later provenance checks.",
        "It emits a digest of existing file bytes for audit/release gates and never transforms a scientific input, feature, payoff, or result.",
    ),
    "Utils/parfor_wait.m": (
        "missing-runtime-dependency",
        "Vendors the progress helper referenced by the published b09 loop and permits a non-GUI mode on headless servers.",
        "No estimator or numeric formula is changed.",
    ),
    "Utils/regstats2.m": (
        "missing-runtime-dependency",
        "Vendors the regression/HAC helper called by the published Table 7 code but absent from the Dataverse archive.",
        "Makes the published call executable without redefining its requested regression outputs.",
    ),
    "b00SelectBaselineOnlyForOldRun.m": (
        "supplementary-run-engineering",
        "Selects the published baseline row only for explicitly requested supplementary runs and leaves the full 3,072-design manifest intact for production b09.",
        "Execution selection only; no formula change.",
    ),
    "b01ReadData.m": (
        "shared-input-preprocessing-and-portability",
        "Corrects the Utils path case, applies the declared common OHLC/volume missing-data rule immediately after raw alignment, and freezes the mechanical-exit calendar before any downstream model is run.",
        "The path repair is engineering; the missing-data rule is a deliberately shared new-v2 input amendment applied identically to all three methods.",
    ),
    "b02CalculateIndicators.m": (
        "shared-volume-rule-and-parallel-engineering",
        "Runs the empirical input, preserves zero-filled volume/turnover from the shared preprocessing layer, and parallelizes only asset-independent feature/resampling work.",
        "The common volume rule is explicit; all remaining M0 feature formulas are the Dataverse formulas and the parallel path is equivalence-gated.",
    ),
    "b03Table1_ResearchSample.m": (
        "reporting-engineering",
        "Publishes the already-computed Table 1 cell array to a deterministic LaTeX file.",
        "No Table 1 statistic is recomputed or changed.",
    ),
    "b09RunResearchDesigns.m": (
        "bit-exact-sharding-engineering",
        "Allows disjoint contiguous subsets of the unchanged 1--3,072 design loop and disables the desktop waitbar for headless execution.",
        "Each global setting retains its original fields, estimator, filename, and numeric payload.",
    ),
    "b10Table6_FactorPerformanceAcrossResearchDesignChoices.m": (
        "necessary-runability-repair",
        "Repairs the CPOLS spelling and sizes arrays after the published VW filter so the intended Table 6 code can execute.",
        "Uses the published design rows and formulas; fixes indexing/name failures only.",
    ),
    "b12Table7_FrontierExpansionTest.m": (
        "necessary-runability-repair",
        "Constructs the factor table that the Dataverse file references before defining it.",
        "Uses the same LTW and CTREND series and the same published test; no methodological correction is imported.",
    ),
    "fSaveOpenFigures.m": (
        "headless-publication-engineering",
        "Saves all open MATLAB figures deterministically in a noninteractive run.",
        "Presentation/persistence only; plotted numeric arrays are unchanged.",
    ),
    "run_full_pipeline_old.sh": (
        "pipeline-orchestration-engineering",
        "Provides a fail-closed one-command ordering of the published scripts, tests, and supplementary variants.",
        "Does not alter the scientific operations inside any MATLAB stage.",
    ),
    "run_safety.sh": (
        "process-safety-engineering",
        "Adds PGID, PID, heartbeat, log, and orphan-worker controls for unattended execution.",
        "Process ownership only; no scientific-number change.",
    ),
    "run_supplementary_outputs.sh": (
        "supplementary-publication-engineering",
        "Runs explicit supplementary variants without editing production source or overwriting headline outputs.",
        "Only exposes existing published switches.",
    ),
}


M2_REASONS = {
    "Utils/fApplySameLegReinvestment.m": (
        "shared-economic-terminal-reinvestment",
        "Settles a frozen terminal event at its last tradable close and immediately reallocates the released wealth only among surviving members of the same portfolio leg.",
        "EW recipients share equally; VW recipients use event-day market capitalizations; cash and cross-leg transfers are forbidden.",
    ),
    "Utils/fAttachEconomicLedgerOptions.m": (
        "shared-economic-terminal-reinvestment",
        "Attaches the authenticated weekly terminal-event ledger and exact calendar row mapping to an M2 portfolio call.",
        "Prevents a consumer from silently reverting to the obsolete missing-payoff or cash convention.",
    ),
    "Utils/fBreakevenTCFromCosts.m": (
        "shared-economic-transaction-cost-support",
        "Computes breakeven transaction costs from an explicitly supplied full-L1 cost base that includes event-day sale and same-leg reinvestment trades.",
        "Changes only the economic cost accounting required by the declared no-cash settlement rule.",
    ),
    "Utils/fBuildWeeklyReinvestmentLedger.m": (
        "shared-economic-terminal-reinvestment",
        "Maps the pre-model frozen mechanical-exit calendar into weekly entry, terminal-sale, and event-day market-cap records.",
        "Provides deterministic inputs for same-leg reinvestment without consulting model forecasts or realized return magnitudes.",
    ),
    "Utils/fLoadEconomicReinvestmentLedger.m": (
        "shared-economic-terminal-reinvestment",
        "Loads and hash-validates the separately saved economic ledger against weekly asset IDs and dates.",
        "Fails closed on mixed DATA builds and guarantees that every M2 economic consumer uses the same frozen exits.",
    ),
    "Utils/fCleanWeeklyLabelsM2.m": (
        "look-ahead-outlier-fix",
        "Cleans each already-realized historical week on its own formation-screened return cross-section, before predictor support is applied.",
        "Prevents future weeks, OOS targets, and volume/predictor availability from defining the cutoff; raw payoff remains untouched.",
    ),
    "Utils/fCreatePanelExAnteM2.m": (
        "look-ahead-support-fix",
        "Builds the M0 joint-predictor panel from formation-time X and weights without requiring the future dependent variable.",
        "Removes outcome-availability conditioning while retaining M0's all-predictor intersection.",
    ),
    "Utils/fDemeanWeeklyM2.m": (
        "look-ahead-label-separation",
        "Demeans a supplied weekly label layer without changing missing cells or the separate payoff layer.",
        "Supports causal historical estimation labels and raw OOS evaluation rows.",
    ),
    "Utils/fFilterM2EstimationSupport.m": (
        "look-ahead-estimation-support",
        "Drops undefined labels only after historical train/validation calendar slices have been fixed.",
        "Never removes OOS prediction or portfolio rows based on their future payoff.",
    ),
    "Utils/fResampleLiuEtAl.m": (
        "deterministic-future-data-fix",
        "Restricts a missing weekly LAST fallback to the current seven-day block instead of searching the rest of the calendar year.",
        "Eliminates direct future observation access and retains M0's within-week last-valid convention.",
    ),
    "Utils/fBuildWeeklyEndpointPnl.m": (
        "shared-economic-endpoint-and-terminal-settlement",
        "Builds ordinary weekly endpoint payoffs and a separate authenticated terminal-event ledger from scheduled entry prices and the frozen last tradable close.",
        "Interior quote gaps do not erase an observable endpoint ratio; terminal proceeds are reinvested by the portfolio consumer and never retained as cash.",
    ),
    "Utils/fSingleSortFast.m": (
        "look-ahead-portfolio-and-settlement-fix",
        "Forms the sort without conditioning ranks on payoff magnitude, applies the frozen terminal ledger after membership is fixed, and immediately reallocates terminal proceeds within the same leg.",
        "Retains the M0 sort definition while removing future-year quote fallback and post-exit cash.",
    ),
    "Utils/fSingleSortMulti.m": (
        "look-ahead-portfolio-and-settlement-fix",
        "Forms M0-style portfolios on declared support, applies frozen terminal sales with immediate same-leg EW/VW reinvestment, and drifts GKX turnover with the preceding rather than current target payoff.",
        "The direct future-price fallback, post-exit cash state, and turnover look-ahead index are removed while noncausal M0 design choices remain.",
    ),
    "Utils/fDepDoubleSort.m": (
        "look-ahead-bivariate-and-settlement-fix",
        "Forms dependent-sort cells without payoff-magnitude conditioning and applies frozen terminal exits with immediate reinvestment inside each cell.",
        "No M1-specific bivariate design is imported and no wealth crosses cells.",
    ),
    "Utils/fIndepDoubleSort.m": (
        "look-ahead-bivariate-and-settlement-fix",
        "Forms independent-sort cells without payoff-magnitude conditioning and applies frozen terminal exits with immediate reinvestment inside each cell.",
        "The dormant Dataverse empty-mMV branch remains; no M1-specific design and no cross-cell transfer is imported.",
    ),
    "Utils/fWalkforwardCENET.m": (
        "look-ahead-walkforward-fix",
        "Separates historical cleaned estimation labels from raw OOS panel rows and filters labels only inside fixed historical slices.",
        "Retains M0 C-ENet models, validation fraction, and combination rules.",
    ),
    "Utils/fWalkforwardCSENET.m": (
        "look-ahead-walkforward-fix",
        "Separates historical cleaned estimation labels from raw OOS panel rows and preserves every formation-time prediction row.",
        "Retains M0 CS-C-ENet joint support and selection/averaging definitions.",
    ),
    "Utils/fWalkforwardFamaMacBethPanel.m": (
        "look-ahead-walkforward-fix",
        "Uses cleaned labels only within the already-fixed historical estimation dates and predicts the full ex-ante OOS panel.",
        "No new sample-size threshold or M1 estimator change is added.",
    ),
    "Utils/fWalkforwardPanelRegression.m": (
        "look-ahead-walkforward-fix",
        "Uses cleaned labels only within the already-fixed historical estimation dates and predicts the full ex-ante OOS panel.",
        "Pooled-OLS formulas and M0 settings are retained.",
    ),
    "b02CalculateIndicators.m": (
        "look-ahead-return-layer-and-economic-ledger",
        "Preserves an untransformed M0-synchronized label layer and separately builds endpoint payoffs plus the frozen terminal-event reinvestment ledger before the contemporaneous outlier path.",
        "Retains M0 data/feature definitions while preventing later-calendar quote fallback and authenticating the no-cash economic layer.",
    ),
    "b04Table2_TechnicalIndicatorStrategyReturns.m": (
        "look-ahead-formation-and-payoff-fix",
        "Uses formation-time screens and the authenticated endpoint/reinvestment ledger for technical-indicator portfolios.",
        "All indicator formulas and strategy signs remain M0; terminal wealth stays invested in the same leg.",
    ),
    "b05CreateCTREND.m": (
        "look-ahead-cttrend-fix",
        "Separates own-week historical label cleaning from raw OOS payoff, removes future Y from panel/rank support, and applies screens at formation.",
        "Retains M0 predictors, all-predictor joint support, models, hyperparameters, and selected-forecast combination rules.",
    ),
    "b06Table3_UnivariatePortfolioSorts.m": (
        "look-ahead-formation-and-payoff-fix",
        "Uses formation screens and the authenticated endpoint/reinvestment ledger in the unchanged M0 Table 3 sort definitions.",
        "Does not import M1's Table-3 characteristic redefinitions; it imports only the shared economic settlement contract.",
    ),
    "b07Table4_CrossSectionalRegressions.m": (
        "look-ahead-formation-screen-fix",
        "Retains M0's statistical-label regression and changes only the market-cap/price eligibility screen from payoff-period values to lagged formation information.",
        "The regression outcome remains rData.mReturns; M2 does not import either the raw portfolio-payoff layer or M1 endpoint P&L.",
    ),
    "b08Table5_PerformanceInSubperiodsAndDifferentMarketStates.m": (
        "look-ahead-state-boundary-fix",
        "Defines the first Table 5 OOS state week from the formation-time CTREND forecast instead of requiring the future portfolio payoff vector to be complete.",
        "Only the future-conditioned boundary is removed; M0's Table 5 portfolios, state variables, and reported statistics are retained.",
    ),
    "b09RunResearchDesigns.m": (
        "look-ahead-research-design-fix",
        "Applies the same M2 causal label/panel/formation rules to every unchanged M0 research-design row.",
        "The complete 3,072-row manifest and M0 estimator menu remain unchanged; a compact formation-start marker supports causal downstream comparison and sharding is execution-only.",
    ),
    "b10Table6_FactorPerformanceAcrossResearchDesignChoices.m": (
        "look-ahead-comparison-boundary-fix",
        "Matches the LTW comparison sample to the first formation-time forecast marker saved by b09 rather than the first realized CTREND payoff.",
        "M0 Sharpe, research-design, and available-case reporting formulas are otherwise retained.",
    ),
    "b13Table8_TheCTRENDFactorPerformanceInBigAndLiquidCryptos.m": (
        "look-ahead-universe-fix",
        "Builds largest/liquid membership from formation characteristics and removes announcement-equivalent untradable targets before the sort.",
        "Retains the Dataverse Table 8 universe definitions.",
    ),
    "b14Table9_CTRENDPortfoliosAndTransactionCosts.m": (
        "look-ahead-portfolio-and-settlement-fix",
        "Encodes Top-100 membership in formation signals/weights, consumes the frozen endpoint/reinvestment ledger, and includes terminal sale/reinvestment trades in M0-style turnover.",
        "M0 reporting conventions remain unless directly implicated; the obsolete post-terminal cash state is not retained.",
    ),
    "b15TableB3_BivariatePortfolioSorts.m": (
        "look-ahead-bivariate-fix",
        "Applies formation-time support before bivariate breakpoints and the frozen terminal ledger after cell membership is fixed.",
        "Preserves the published independent/dependent-sort design while reinvesting terminal proceeds only within the same cell.",
    ),
    "b16TableB4_CTRENDPerformanceDependingOnCryptocurrencyType.m": (
        "look-ahead-universe-fix",
        "Encodes the named crypto-type universe in formation signals/weights instead of deleting future-return cells.",
        "Type definitions and M0 table calculations remain unchanged.",
    ),
    "b17TableB10_ExtendedPortfolioHoldingPeriod.m": (
        "look-ahead-holding-and-settlement-fix",
        "Uses formation screens and frozen terminal exits with immediate same-leg reinvestment for the published repeated-signal holding-period implementation.",
        "Does not import M1's fixed-cohort buy-and-hold rewrite and never retains post-exit cash.",
    ),
    "b18FigureC3_C4_AverageVariableImportance.m": (
        "look-ahead-figure-c-support-fix",
        "Removes future Y availability from the M0 joint-predictor importance panel.",
        "Retains M0 importance/selected-set definitions rather than M1 predictor-own-support importance.",
    ),
}


M1_REASONS = {
    "LatexTables/fAddSlash.m": ("latex-publication-fix", "Escapes every unescaped underscore in a label rather than only the first occurrence.", "Presentation-only correction; supplied numeric cells are unchanged."),
    "LatexTables/fAddStatistics.m": ("latex-publication-fix", "Corrects the invalid LaTeX command textBF to textbf.", "Presentation-only correction; statistical values and significance decisions are unchanged."),
    "Utils/characteristics.m": ("scientific-characteristic-fix", "Aligns characteristic definitions, units, paired support, and rolling calculations with the paper and audited economic/statistical meanings.", "Characteristic matrices use the declared units, time windows, and paired finite support; this file does not rewrite raw endpoint P&L or the separate technical-indicator layer."),
    "Utils/technical_indicators.m": ("scientific-indicator-fix", "Corrects audited technical-indicator definitions and missing-data restart behavior while retaining confirmed EMA/volatility conventions.", "The 28 predictor matrices follow their audited formulas and restart only when their own lookback support is available; predictor construction does not overwrite raw endpoint payoff."),
    "Utils/fResampleLiuEtAl.m": ("causal-weekly-resampling", "Uses only the scheduled weekly boundary/current block and prevents a missing endpoint from reading a later calendar observation.", "Removes deterministic future-data contamination."),
    "Utils/fCrossSectTransChars.m": ("predictor-own-support-ranking", "Ranks each predictor on its own finite formation-time eligible cross-section before any future-outcome mask.", "Implements the paper's predictor-specific rank definition."),
    "Utils/fDepDoubleSort.m": ("causal-portfolio-accounting", "Removes announcement-equivalent untradable targets before dependent-sort breakpoints and reweights the surviving cells.", "Corrects target tradability and economic payoff accounting without using payoff magnitude."),
    "Utils/fIndepDoubleSort.m": ("causal-portfolio-accounting", "Removes announcement-equivalent untradable targets before independent-sort breakpoints, reweights survivors, and fixes the empty-weight dimension branch.", "Corrects runability plus target-tradability accounting."),
    "Utils/fSingleSortFast.m": ("causal-portfolio-accounting", "Makes b05/b09 hedge portfolios use identical target-tradability screens, breakpoints, and survivor weights.", "Corrects baseline-estimator equality while never using payoff magnitude for membership."),
    "Utils/fSingleSortMulti.m": ("economic-portfolio-accounting", "Implements formation-time membership, frozen terminal sales, immediate same-leg EW/VW reinvestment, full-L1/half-L1 reporting distinctions, and gap episodes without a post-exit cash state.", "Corrects portfolio P&L, turnover, transaction costs, and missing-data accounting."),
    "Utils/fWalkforwardCSENET.m": ("paper-equation-and-oos-fix", "Implements causal historical outlier fitting, predictor-specific supports, validation selection, fixed selected sets, and fail-closed OOS forecast combination.", "Aligns Eqs. (7), (10), and (11) with strict OOS execution."),
    "Utils/fWalkforwardCENET.m": ("paper-equation-and-oos-fix", "Applies the corrected causal label/support and validation logic to C-ENet without using future outcomes.", "C-ENet tuning and estimation use only fixed historical train/validation rows, while OOS membership and raw payoff remain outside cutoff fitting; the declared C-ENet model menu is retained."),
    "Utils/fWalkforwardFamaMacBethPanel.m": ("oos-regression-fix", "Uses fixed calendar windows, model-specific finite support, and causal historical labels for Fama--MacBeth forecasts.", "Removes outcome-conditioned panels and numerical rank failures."),
    "Utils/fWalkforwardPanelRegression.m": ("oos-regression-fix", "Uses fixed calendar windows, model-specific finite support, and causal historical labels for pooled regressions.", "Removes outcome-conditioned panels and numerical rank failures."),
    "Utils/fMeanVarianceSpanningSoebhag.m": ("table7-calendar-fix", "Uses exactly the prior 52 calendar positions with local listwise deletion and no older-week backfill.", "Implements the audited strict-OOS Table 7 rule."),
    "Utils/fImportanceCS_ENet.m": ("figure-c-estimator-fix", "Aligns importance timing, selected variables, and cross-sectional support with the corrected CTREND estimator.", "Prevents Figure C from using a different estimator/support."),
    "Utils/fAnalyzeReturns.m": ("return-statistics-fix", "Removes an unavailable bootstrap branch, uses common finite calendar observations, and computes conventional and calendar-preserving Newey-West regression statistics explicitly.", "Makes the reported return/alpha statistics reproducible without compressing missing calendar weeks."),
    "Utils/fEnsureAllObs.m": ("finite-support-fix", "Treats nonfinite numeric cells as unavailable when aligning multiple arrays.", "Prevents Inf values from entering corrected estimators; no finite observation is changed."),
    "Utils/fEstCombinedLasso.m": ("dimension-runability-fix", "Uses the number of panel rows rather than MATLAB length(mID), which can return the number of columns for short panels.", "Corrects a dimension assertion only; the model formula is unchanged."),
    "Utils/fEstEvalTangPort.m": ("table7-positive-tangency-direction", "Our M1 rewrite accidentally normalized by a potentially negative sum of zero-cost factor exposures, whereas the author helper checked the positive expected-return direction. The corrected M1 helper scales the covariance-inverse mean direction by a positive volatility multiplier.", "Removes our sign-reversal error from Table 7; unidentified covariance still fails closed. This is not attributed to the original CTREND source."),
    "Utils/fEstFamaMacBethPanel.m": ("fama-macbeth-calendar-and-identification-fix", "Preserves the complete weekly calendar for Newey-West lags, filters locally, uses scale-invariant full-rank solves, and returns undefined estimates when a cross-section is not identified.", "Corrects compressed-time HAC, weighted R-squared, degrees of freedom, and singular-regression behavior."),
    "Utils/fEstPanelRegression.m": ("panel-regression-identification-fix", "Uses local finite support, valid nonnegative weights, a scale-invariant full-rank solve, and correct coefficient degrees of freedom.", "Prevents unit-dependent rank decisions, pseudoinverse estimates, and invalid standard errors."),
    "Utils/fEstRegPanelRegression.m": ("regularized-regression-aicc-fix", "Validates finite support/weights, computes AICc with the intercept degrees of freedom, and distinguishes expected statistical non-identification from real execution failures.", "Prevents undefined lambda choices and silent suppression of toolbox/input errors."),
    "Utils/fGRS.m": ("grs-definition-and-identification-fix", "Applies local finite asset/time support, the GRS factor second-moment denominator, and full-rank covariance gates.", "Corrects the reported GRS statistic and fails closed when its finite-sample system is undefined."),
    "Utils/fMaxDD.m": ("economic-drawdown-fix", "Computes drawdown from a compounded wealth index including initial wealth and leaves paths with internal missing returns undefined.", "Replaces the Dataverse maximum one-period cumulative-return difference, which is not maximum economic drawdown."),
    "Utils/fPredictFamaMacBethPanel.m": ("dimension-runability-fix", "Uses the number of panel rows rather than MATLAB length(mID), which can return the number of columns for short panels.", "Corrects a dimension assertion only; predictions use the same supplied coefficients."),
    "Utils/fPredictPanelRegression.m": ("dimension-runability-fix", "Uses the number of panel rows rather than MATLAB length(mID), which can return the number of columns for short panels.", "Corrects a dimension assertion only; predictions use the same supplied coefficients."),
    "Utils/fSharpeRatio.m": ("sharpe-definition-and-domain-fix", "Aligns scalar/time-varying risk-free rates to the time axis, computes both mean and volatility on excess returns, and returns NaN for insufficient or zero-variance samples.", "Corrects the Sharpe definition and prevents infinite/shape-dependent statistics."),
    "Utils/fWeightedPricingError.m": ("pricing-error-support-and-rank-fix", "Uses each model's own finite asset/time support and requires an invertible residual covariance before computing the quadratic pricing error.", "Prevents unrelated model missingness and singular inverse operations from determining another model's statistic."),
    "Utils/fRemoveOutlier.m": ("retired-global-outlier-helper", "Removes the Dataverse helper retained by M0. M1 estimates a separate cutoff from each already-realized historical week's formation-eligible return cross-section; it does not pool the training window into one cutoff.", "Training and validation labels use their own historical week's cutoff; OOS labels and economic payoff are never outlier-transformed."),
    "Utils/fTruncate.m": ("retired-global-outlier-helper", "Removes the Dataverse full-matrix truncation helper retained by M0 because M1 handles labels inside fixed historical estimation windows.", "Prevents a global sample cutoff from contaminating OOS labels while leaving raw economic payoff untouched."),
    "Utils/fWinsorize.m": ("retired-global-outlier-helper", "Removes the Dataverse full-matrix winsorization helper retained by M0 because M1 handles labels inside fixed historical estimation windows.", "Prevents a global sample cutoff from contaminating OOS labels while leaving raw economic payoff untouched."),
    "b01ReadData.m": ("raw-input-and-provenance-fix", "Preserves raw positive-price/volume inputs before synchronization, validates immutable snapshots, and separates optional event adjustments from the main no-adjustment design.", "Later stages receive an authenticated raw endpoint layer distinct from synchronized statistical inputs; b01 records the selected input mode but does not itself choose a forecast or portfolio."),
    "b02CalculateIndicators.m": ("data-layer-and-characteristic-fix", "Builds separate statistical-label and raw endpoint-P&L layers, corrected characteristics, market proxies, and bit-exact parallel chunks.", "Produces axis-aligned label, predictor, and economic-payoff artifacts with explicit provenance; parallel chunks must equal the serial definitions and therefore introduce no alternate estimand."),
    "b03Table1_ResearchSample.m": ("table1-and-publication-fix", "Uses the corrected synchronized sample and deterministic table publication.", "Table 1 counts and dates are recomputed from the authenticated corrected sample, while deterministic publication changes only file creation and formatting."),
    "b04Table2_TechnicalIndicatorStrategyReturns.m": ("table2-oos-accounting-fix", "Forms technical strategies ex ante and evaluates raw endpoint payoffs with corrected missing-data accounting.", "Table 2 membership is fixed from formation information and its reported returns use the separate economic-payoff layer rather than allowing target-payoff availability to define the sort."),
    "b05CreateCTREND.m": ("cttrend-core-full-fix", "Implements predictor-own-support ranks, paper Eq. (7) weighting, causal outlier windows, Eq. (10) selection, Eq. (11) averaging, and raw endpoint P&L.", "The headline signal follows the paper-defined weighting, selection, and averaging sequence using historical labels only; portfolio evaluation consumes raw economic endpoint returns on the saved formation universe."),
    "b06Table3_UnivariatePortfolioSorts.m": ("table3-paper-alignment", "Uses lagged weekly-average market cap, percent IVOL, and endpoint P&L with ex-ante sorts.", "Aligns Table 3 with the paper and economic accounting."),
    "b07Table4_CrossSectionalRegressions.m": ("table4-statistical-label-fix", "Retains the paper/old synchronized statistical-label regression while using strict OOS CTREND alignment and ex-ante screens.", "Explicitly does not substitute economic endpoint P&L."),
    "b08Table5_PerformanceInSubperiodsAndDifferentMarketStates.m": ("table5-consumer-fix", "Consumes the corrected H-L series, reconstructs only required middle quintiles, aligns dates/factors, and preserves the stated market-state definitions.", "Every Table 5 panel uses the same authenticated CTREND return/date axes as the headline result; the stage cannot silently rebuild H-L with a different support or portfolio rule."),
    "b09RunResearchDesigns.m": ("full-design-corrected-estimation", "Applies the corrected estimator to a complete 3,072-combination manifest before any output filtering, with per-combo audit/provenance and deterministic sharding.", "Scientific definitions match b05; sharding changes scheduling only."),
    "b10Table6_FactorPerformanceAcrossResearchDesignChoices.m": ("table6-comparison-fix", "Reports method-specific weeks plus pairwise/all-method common-week and balanced-cell comparisons with explicit failure/coverage audit.", "Prevents incomparable Sharpe samples from being described as estimator dominance."),
    "b11Figure3_AnomalyAlphas.m": ("figure3-alignment-fix", "Uses corrected portfolios/factors with explicit date alignment and reproducible headless output.", "Figure 3 alphas are estimated only after anomaly and factor calendars are explicitly intersected; headless saving changes presentation only and not the aligned regression inputs."),
    "b12Table7_FrontierExpansionTest.m": ("table7-strict-oos-fix", "Builds the factor table and applies strict past-52-calendar, local-listwise, full-rank fail-closed estimation.", "Corrects both the Dataverse runability defect and Table 7 timing/statistics."),
    "b13Table8_TheCTRENDFactorPerformanceInBigAndLiquidCryptos.m": ("table8-ex-ante-universe-fix", "Computes largest/liquid universes from eligible formation-time information and endpoint payoffs.", "Largest/liquid membership and breakpoints no longer depend on the target return being finite; the retained members are evaluated on the declared endpoint-payoff accounting layer."),
    "b14Table9_CTRENDPortfoliosAndTransactionCosts.m": ("table9-economic-accounting-fix", "Implements full-L1 cost bases, paper half-L1 display, two-leg H-L costs, initial build costs, frozen terminal sales with immediate same-leg reinvestment, and formation-gap episodes without a fabricated terminal liquidation.", "Full audited Table 9 accounting with no post-exit cash state."),
    "b15TableB3_BivariatePortfolioSorts.m": ("table-b3-causal-sort-fix", "Uses predictor-specific bivariate membership after the declared target-tradability screen and reweights surviving cells.", "Table B.3 cells are formed from information available at formation, use explicit survivor weights, and inherit the same endpoint settlement rule as the headline univariate portfolios."),
    "b16TableB4_CTRENDPerformanceDependingOnCryptocurrencyType.m": ("table-b4-universe-fix", "Applies crypto-type membership at formation and evaluates endpoint P&L without outcome-conditioned inclusion.", "Table B.4 type universes are fixed at formation and evaluated on raw endpoint P&L, so a future outcome cannot decide whether an asset enters its reported type portfolio."),
    "b17TableB10_ExtendedPortfolioHoldingPeriod.m": ("table-b10-cohort-fix", "Creates fixed nonoverlapping formation cohorts with fixed members and buy-and-hold drift instead of weekly reselection.", "Aligns Table B.10 with the paper's holding-period experiment."),
    "b18FigureC3_C4_AverageVariableImportance.m": ("figure-c-paper-alignment", "Uses predictor-own X/raw-return support, corrected beta/selected sets, zero importance for unselected variables, and corrected labels/axes.", "Figure C reuses the b05/b09 estimator's support and selected-set definition, while unselected predictors receive explicit zero importance rather than values inferred from another sample."),
    "tests/test_figure_b2_results.m": ("sample-independent-result-validation", "Rebuilds Figure B.2 from the current run's LTW and CTREND paths and verifies every plotted value instead of hard-coding another data treatment's count of flat increments.", "Validation-only correction; the figure generator, factor returns, tables, and estimators are unchanged."),
    "b00GenerateDesignChoices.m": ("design-manifest-and-publication-engineering", "Retains the complete published 3,072-row full grid, adds an explicit baseline-only execution scope, and atomically publishes the manifest with a scope marker.", "The full scientific design grid is unchanged; the added branch and atomic write affect scheduling/provenance only."),
    "b01GenerateArtificialData.m": ("artificial-data-runability-engineering", "Makes the synthetic demonstration safe when an asset never starts, creates mutually consistent coin/token flags, and parallelizes asset-independent availability construction.", "Synthetic-test input only; no empirical production result is constructed from this file."),
    "setup.m": ("setup-and-provenance-engineering", "Adds Utils before use, atomically publishes downloaded factor data, and validates empirical-input provenance before an expensive run.", "Setup/fail-closed behavior only; accepted input values and scientific formulas are unchanged."),
}


M1_DELETION_REASONS = {
    "Utils/fComputeOldFeaturesParallel.m": (
        "m1-replaces-m0-feature-adapter",
        "Drops M0's Dataverse-formula feature wrapper because M1 computes its corrected characteristics and indicators in its own audited parallel b02 implementation.",
        "Removes an M0-only execution adapter; M1's replacement definitions and bit-exact parallel gates remain explicit in M1 b02.",
    ),
    "b00SelectBaselineOnlyForOldRun.m": (
        "m1-replaces-m0-supplementary-adapter",
        "Drops the M0-only old-pipeline baseline selector because M1 has its own design-manifest and explicit supplementary execution path.",
        "Removes an M0-only execution adapter; no M1 scientific result is constructed by this deleted file.",
    ),
    "run_full_pipeline_old.sh": (
        "m1-replaces-m0-pipeline-adapter",
        "Drops the M0 old-pipeline stage wrapper because M1 uses run_full_pipeline_corrected.m/.sh and the corrected runner contract.",
        "Replaces orchestration only; the M1 scientific stages are identified separately in their own files.",
    ),
}


M1_HELPER_GROUPS = {
    "fAlignByDate.m": "Fail-closed date alignment for tables, figures, and factors.",
    "fApplySameLegReinvestment.m": "Settles frozen terminal events and immediately reallocates released wealth among surviving members of the same leg, using equal shares for EW and event-day market capitalization for VW.",
    "fApplyV2RawDataCorrections.m": "Explicit opt-in event-registry sensitivity with price/volume timing audit; main D0/D1/D2 mode remains none.",
    "fAttachEconomicLedgerOptions.m": "Attaches the authenticated weekly terminal-event ledger and exact week-row mapping to every economic portfolio consumer.",
    "fBreakevenTCFromCosts.m": "Derives the transaction-cost rate that equates gross return with the explicitly supplied full-L1 trading-cost base.",
    "fBuildHistoricalWeeklyOutlierAudit.m": "Records, by historical week, the exact formation screen, label support, and frozen outlier cutoff used by a corrected estimator.",
    "fBuildRawOOSPanelOutcome.m": "Attaches raw OOS endpoint outcomes to an already formed ex-ante predictor panel without letting outcome availability define its rows.",
    "fBuildRollingOutlierAudit.m": "Optional pooled-training-window cutoff diagnostic, not called by production b05/b09. Those stages call fBuildHistoricalWeeklyOutlierAudit for separate historical-week cutoffs. This helper records cutoffs only and does not inspect or verify portfolio payoffs.",
    "fBuildTable5PortfolioReturns.m": "Reconstructs Table 5 portfolio returns from corrected fixed membership/weight consumers while preserving fail-closed component weeks.",
    "fBuildTopUniverse.m": "Creates a Top-N universe from the table-specific formation-time eligibility and size definition, with deterministic tie handling.",
    "fBuildWeeklyEndpointPnl.m": "Raw positive-close endpoint P&L plus frozen terminal-event records; portfolio consumers immediately reinvest terminal proceeds in the same leg and never search a later block.",
    "fBuildWeeklyReinvestmentLedger.m": "Maps the frozen mechanical-exit calendar into authenticated weekly entry/exit/event-day-market-cap records before models or portfolios run.",
    "fCleanMarketCapAgainstBitcoin.m": "Applies the audited Bitcoin-relative market-cap plausibility rule without using future portfolio outcomes.",
    "fComputeCharacteristicChunk.m": "Computes the corrected asset-separable characteristic block for one deterministic b02 column chunk.",
    "fComputeMarketRegressionCharacteristics.m": "Computes beta and other market regressions on their documented rolling support; delay now uses the fifth fAlphaBetaSigma output (R-squared), not the fourth (residual skewness).",
    "fComputeTechnicalIndicatorChunk.m": "Computes corrected asset-separable price/volume technical indicators for one deterministic b02 column chunk.",
    "fCorrectedAICc.m": "Computes AICc only where residual variance and effective degrees of freedom, including an intercept, are mathematically defined.",
    "fCreatePanelExAnte.m": "Predictor-union panel constructed before future Y is observed.",
    "fEnsureParallelPoolExact.m": "Creates or validates an exact-size process pool so parallel b02/b09 execution cannot silently use a different topology.",
    "fEstimateAssetPricingSystem.m": "Estimates the corrected time-series asset-pricing system on one common finite sample with explicit identification checks.",
    "fGRSFromReturns.m": "Constructs alphas, residuals, and factor moments on one common finite return sample before applying the corrected GRS formula.",
    "fGetCurrentWeeklyDataBuildID.m": "Reads and validates the immutable weekly-data build identifier consumed by downstream result provenance.",
    "fMaskAuxiliaryOHLC.m": "Applies the synchronized core availability mask to auxiliary OHLC fields without inventing prices or changing preserved raw endpoints.",
    "fMergeAssetChunkStructs.m": "Merges disjoint b02 asset chunks in original column/field order and rejects overlap, gaps, or metadata disagreement.",
    "fPrepareWalkforwardOutcomes.m": "Causal historical-week outlier fit/transform with raw OOS labels and P&L preserved.",
    "fRankPredictorsOwnSupport.m": "Ranks each predictor only among assets for which that predictor is finite at the formation date, rather than imposing one joint complete-case mask across all predictors or conditioning ranks on the future outcome.",
    "fImportanceCS_ENetPredictorSupport.m": "Figure-C importance on the same predictor-specific support and selected set as CTREND.",
    "fLoadEconomicReinvestmentLedger.m": "Loads and hash-validates the separately saved economic ledger against the weekly asset/date axes.",
    "fMeanForecastsFixedSet.m": "Eq. (11) fixed-selected-set mean retaining the 1/J_selected factor and failing closed on missing selected forecasts.",
    "fNormalizePanelWeights.m": "Renormalizes Eq. (7) weights on each predictor/date finite support.",
    "fExtendedHoldingPeriodVW.m": "Fixed-cohort, fixed-member buy-and-hold drift accounting with frozen terminal sales and immediate same-leg reinvestment for Table B.10.",
    "fOLSNeweyWestCalendar.m": "Full-rank, calendar-aware OLS/Newey-West estimation used by strict Table 7.",
    "fPotentialResearchDesignFactorWeeks.m": "Computes formation-time potential factor-week coverage for Table 6 without conditioning the potential set on realized payoff success.",
    "fPublishWeeklyDataBuildManifest.m": "Publishes the weekly-data layer inventory, source hashes, and semantic build identifier atomically.",
    "fReduceKnownUnpenalizedAliases.m": "Removes only deterministic duplicate or unpenalized design-matrix aliases before a regularized fit and records the mapping.",
    "fRegstatsTstatSafe.m": "Provides finite-support conventional regression statistics with explicit rank and degrees-of-freedom failure states.",
    "fSolveFullRankLeastSquares.m": "Normalizes columns, requires full rank, and solves least squares without a pseudoinverse-selected unidentified coefficient vector.",
    "fSplitTrainValidation.m": "Splits an already fixed historical calendar into ordered train and validation dates without using validation or OOS outcomes to choose rows.",
    "fSummarizeResearchDesignEstimatorAudit.m": "Aggregates saved per-design estimator status and coverage without changing any combination result.",
    "fTable6CommonWeekStats.m": "Recomputes each pairwise and all-method Sharpe comparison on the exact intersection of finite calendar weeks, and reports the common-week count instead of comparing method-specific available-case samples.",
    "fTable6BalancedCellGate.m": "Balanced design-cell gate for Table 6 estimator comparisons.",
    "fAuditResearchDesignCoverage.m": "Separates scheduled prediction support, complete forecasts, realized factor availability, and enumerated failure reasons for every method/design/week so missing cells cannot be silently interpreted as zero returns or estimator inferiority.",
    "fValidateUniverseMask.m": "Asserts that a saved portfolio universe depends only on declared formation-time inputs and has the expected dimensions.",
    "fValueWeightedReturnFailClosed.m": "Dormant compatibility helper for the superseded selected-payoff fail-closed sensitivity; production consumers use the declared tradable-universe helper.",
    "fValueWeightedReturnTradableUniverse.m": "Value-weighted economic market payoff after announcement-equivalent target unavailability is removed and surviving formation weights are renormalized.",
    "fValueWeightedMarketReturnStrict.m": "Separates the strict economic market return from statistical vMktRet.",
    "fCumulativeFactorReturnDisplayZeroGaps.m": "Presentation-only zero return at disclosed formation gaps; numeric factor data remain missing.",
    "fSignedAxisLimitsTicks.m": "Explicit signed axes/ticks preventing misleading figure labels.",
    "run_full_pipeline_corrected.m": "Provides the corrected fail-closed MATLAB stage order used by the external immutable runner.",
}


# Added files with no Dataverse counterpart still need a file-specific review
# rationale.  The executable file's own comments explain implementation detail;
# these entries explain why the file exists and bound what it is allowed to do.
M1_ADDED_FILE_REASONS = {
    "Utils/fAssertB09PayloadDigest.m": (
        "b09-payload-integrity-gate",
        "The Dataverse pipeline does not authenticate each saved design-combination MAT file. M1 verifies the whole-file sidecar, embedded combination number, and optional manifest digest before a combo is consumed.",
        "Corrupt, substituted, or misnumbered b09 payloads fail closed; this gate reads identities only and does not alter a forecast or return.",
    ),
    "Utils/fAssertCTRENDAlignment.m": (
        "saved-result-axis-gate",
        "Downstream consumers need proof that saved CTREND dates, asset order, signal dimensions, and weekly-data build identity match their current inputs. M1 adds one explicit alignment assertion.",
        "A stale or differently ordered result is rejected before use; correctly aligned numeric arrays are returned unchanged.",
    ),
    "Utils/fAssertRawInputProvenance.m": (
        "raw-input-content-gate",
        "A saved b01 checkpoint could otherwise be reused after one of its raw files changed. M1 re-hashes every declared raw member and checks its byte count and aggregate certificate.",
        "Mixed raw/checkpoint states fail closed; the helper does not screen, fill, or transform an accepted input value.",
    ),
    "Utils/fAssertSavedResultProvenance.m": (
        "saved-result-provenance-gate",
        "The Dataverse stages do not bind saved dependencies to both executable source and the weekly-data build. M1 checks those two identities before a saved result is reused.",
        "Stale-code or stale-data dependencies fail closed; no scientific array is changed when the identities match.",
    ),
    "Utils/fAssertWeeklyDataBuildManifest.m": (
        "weekly-bundle-integrity-gate",
        "Weekly intermediates span several files that could otherwise be mixed across runs. M1 validates the complete marker, build ID, member inventory, sizes, and hashes as one bundle.",
        "Incomplete or mixed weekly bundles fail before estimation; validated member contents are not modified.",
    ),
    "Utils/fAssertWeeklyDataProvenance.m": (
        "weekly-layer-provenance-gate",
        "M1 must reject weekly intermediates that predate raw-input validation or were created by a different weekly/code build. This helper checks the certificate and both fingerprints together.",
        "Only provenance-compatible weekly data proceed; the test is identity-only and does not redefine returns or predictors.",
    ),
    "Utils/fFileSHA256.m": (
        "streaming-content-identity-helper",
        "Several preprocessing, exit-calendar, and provenance contracts require exact file identities without loading large files into memory. M1 adds a bounded-memory SHA-256 helper.",
        "The helper emits a digest of existing bytes and never transforms a scientific input or output.",
    ),
    "Utils/fPipelineCodeFingerprint.m": (
        "executable-source-fingerprint",
        "Saved stages need a stable identity of executable MATLAB code while excluding logs, job storage, and audit outputs that change during a run. M1 hashes only declared source locations in deterministic order.",
        "Source mixing is detectable without making runtime artifacts part of the scientific-code identity.",
    ),
    "Utils/fValidateInputProvenance.m": (
        "unscreened-input-provenance-gate",
        "A historically pre-screened asset universe cannot reproduce formation-date eligibility or alternative universes and may embed future information. M1 validates the unscreened input contract and records its content identity.",
        "Invalid pre-screened or incomplete inputs fail closed; valid raw values remain untouched for the later declared screens.",
    ),
    "audit/build_causal_external_corruption_manifest.py": (
        "read-only-causal-external-audit",
        "Builds a date-t-only comparison of extreme CMC moves with independently aggregated CoinLore prices and a frozen trailing level-ratio baseline.",
        "Produces candidate evidence only; it neither edits production CMC cells nor enters the default D0/D1/D2 estimand.",
    ),
    "audit/build_causal_point_correction_manifest.py": (
        "read-only-causal-point-audit",
        "Identifies exact asset-date external disagreements using only contemporaneous returns and a preceding 30-day level-ratio history, excluding verified event windows.",
        "Outputs sensitivity candidates with a recorded causal rule; production price, feature, and payoff arrays remain unchanged.",
    ),
    "audit/build_external_corruption_manifest.py": (
        "read-only-two-sided-external-audit",
        "Requires a closed episode with agreeing pre/post external level ratios before labelling an extreme CMC cell as externally contradicted.",
        "This deliberately noncausal two-sided evidence is audit-only and cannot be loaded into the default OOS pipeline.",
    ),
    "audit/build_noncontemporaneous_event_review_list.py": (
        "point-level-event-exclusion-audit",
        "Replaces an over-broad asset-level review filter with exact asset-date matching to verified events, so unrelated events elsewhere in an asset's history do not remove a candidate.",
        "Changes only the human external-review list; no research input or portfolio observation is deleted.",
    ),
    "audit/classify_all_extreme_events.py": (
        "extreme-event-disposition-audit",
        "Assigns every inventoried extreme-return row a documented event/data-quality disposition and checks that the classification inventory is exhaustive.",
        "Creates review metadata only; classifications do not silently adjust the D0/D1/D2 raw panels.",
    ),
    "audit/extract_confirmed_event_windows.m": (
        "read-only-event-window-export",
        "Exports aligned OHLCV and market-cap windows around suspected unit/event breaks so price and volume timing can be reviewed together.",
        "Reads source panels and writes separate audit evidence; source CMC files are never overwritten.",
    ),
    "audit/fetch_coinlore_crosscheck.py": (
        "independent-source-crosscheck",
        "Fetches and caches CoinLore histories only after unambiguous normalized name-and-symbol matching, retaining response hashes for every accepted comparison.",
        "Supplies reproducible external evidence without substituting CoinLore values into production CMC data.",
    ),
    "audit/scan_extreme_raw_returns.m": (
        "full-universe-extreme-return-inventory",
        "Inventories every adjacent-day and Tuesday-to-Tuesday raw CMC gross ratio at or beyond 5 or 0.2 before inspecting CTREND holdings.",
        "Defines the exhaustive review population without deleting assets, editing prices, or conditioning on portfolio relevance.",
    ),
    "audit/validate_v2_raw_corrections.m": (
        "read-only-registry-validation",
        "Applies the optional event registry in memory to the exact listed cells and exports compact before/after evidence for independent review.",
        "Validates a sensitivity registry without editing source CSV files or activating that registry in the default experiment cells.",
    ),
    "run_full_pipeline_corrected.sh": (
        "portable-m1-entry-wrapper",
        "The Dataverse archive lacks a fail-closed headless shell entry. This wrapper resolves MATLAB explicitly, fixes the code working directory, and launches the ordered M1 MATLAB driver.",
        "It changes invocation and error propagation only; stage definitions remain in the versioned M1 MATLAB source.",
    ),
    "tests/run_corrected_unit_tests.m": (
        "m1-unit-test-aggregator",
        "Runs the deterministic M1 unit and invariant suite from a controlled MATLAB path and emits explicit success markers.",
        "Test-only orchestration; it is not called by any scientific stage to construct results.",
    ),
    "tests/test_audit_remediation.m": (
        "independent-audit-regression-tests",
        "Locks the audited Table 5/8, b05-b09 equality, coverage, status-code, payload-digest, and screening-manifest remediations with deterministic fixtures.",
        "A violated remediation blocks validation; the fixtures do not enter empirical estimates.",
    ),
    "tests/test_b05_b09_baseline_results.m": (
        "baseline-result-equality-test",
        "Identifies the unique field-matched b09 baseline and compares its saved predictions and factor returns with b05 on their declared axes.",
        "Detects estimator drift between the headline and design-grid paths without modifying either saved result.",
    ),
    "tests/test_figure_c_predictor_support.m": (
        "figure-c-support-regression-test",
        "Uses a deterministic panel to verify predictor-specific sample sizes, selected-set support, and zero importance for unselected variables in Figure C.",
        "Test-only guard against Figure C silently using a different estimator/support from CTREND.",
    ),
    "tests/test_portfolio_gap_accounting.m": (
        "portfolio-accounting-regression-test",
        "Exercises formation-gap episodes, target-untradable reweighting, terminal sales, and immediate same-leg reinvestment for EW and VW fixtures.",
        "Locks the declared accounting identities; synthetic fixtures never enter empirical factor returns.",
    ),
    "tests/test_table6_results.m": (
        "table6-result-invariant-test",
        "The multi-method Table 6 output can appear complete while methods use incomparable weeks or cells. This test checks dimensions, method/design coverage, common-week statistics, provenance fields, and required publication payloads.",
        "Rejects incomplete or incomparable Table 6 output without filling failures, changing sample membership, or altering any design-cell return.",
    ),
    "tests/test_v2_no_adjustment_mode.m": (
        "raw-no-adjustment-identity-test",
        "Proves that the default raw-adjustment mode is a bit-exact identity map for all supplied OHLCV, market-cap, metadata, and date arrays.",
        "Prevents an optional event-registry sensitivity from leaking into the main D0/D1/D2 experiments.",
    ),
    "tests/test_v2_raw_data_corrections.m": (
        "optional-registry-exactness-test",
        "Uses the declared event assets/dates to verify price and volume factor direction, field coverage, timing, audit output, and untouched controls.",
        "Tests only the opt-in registry sensitivity and does not activate it in the default nine method/data cells.",
    ),
    "tests/test_v2_static_guards.sh": (
        "m1-static-contract-test",
        "Some high-risk source regressions are visible without running MATLAB. This test requires critical corrected helpers and call sites while rejecting explicitly forbidden legacy patterns before production execution.",
        "A source-contract regression fails validation before production execution; the shell test only reads source text and never constructs a scientific number.",
    ),
    "tests/test_weekly_endpoint_pnl.m": (
        "endpoint-pnl-regression-test",
        "Checks internal-gap handling, frozen terminal exits, event-day values, ledger identities, and same-leg reinvestment on deterministic price paths.",
        "Locks economic P&L semantics with synthetic fixtures that are separate from empirical inputs.",
    ),
}


def sha256(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def comment_prefix(path: Path) -> str:
    if path.suffix == ".m":
        return "%"
    if path.suffix == ".bat":
        return "REM"
    return "#"


def hierarchy_marker(prefix: str, level: int, *, detail: bool = False) -> str:
    """Return a valid comment marker whose percent count exposes hierarchy."""
    assert 1 <= level <= 4
    percent = "%" * level + (">>>" if detail else "")
    if prefix == "%":
        return percent
    if prefix == "REM":
        return f"REM {percent}"
    return f"# {percent}"


def format_span(start: int, end: int) -> str:
    if start == end:
        return "insertion-point-" + str(start + 1)
    first = start + 1
    last = end
    return str(first) if first == last else f"{first}-{last}"


def nearby_comment(lines: list[str]) -> str:
    out: list[str] = []
    for line in lines:
        s = line.strip()
        if s.startswith("%") or s.startswith("#"):
            s = s[1:].strip()
            if s and not s.startswith((">>>", "<<<")):
                out.append(s)
        if len(out) == 2:
            break
    return " ".join(out)[:260]


def readable_excerpt(lines: list[str], max_lines: int = 2,
                     max_chars: int = 240) -> str:
    """Return a compact code excerpt for the human block map."""
    nonempty = [" ".join(line.strip().split()) for line in lines if line.strip()]
    if not nonempty:
        return ""
    code = [
        line for line in nonempty
        if not line.startswith(("%", "#", "REM "))
    ]
    chosen = (code or nonempty)[:max_lines]
    excerpt = " | ".join(chosen)
    if len(excerpt) > max_chars:
        excerpt = excerpt[:max_chars - 3].rstrip() + "..."
    return excerpt


def human_span(value: str) -> str:
    if value == "NA":
        return "not present"
    marker = "insertion-point-"
    if value.startswith(marker):
        return f"insertion point before line {value[len(marker):]}"
    if "-" in value:
        first, last = value.split("-", 1)
        return f"lines {first}-{last}"
    return f"line {value}"


def compact_numbers(values: list[int], owner: str = "") -> str:
    """Render [1,2,3,5] as M1-B0001-M1-B0003, M1-B0005."""
    if not values:
        return "none"
    spans: list[tuple[int, int]] = []
    start = previous = values[0]
    for value in values[1:]:
        if value == previous + 1:
            previous = value
            continue
        spans.append((start, previous))
        start = previous = value
    spans.append((start, previous))
    stem = f"{owner}-B" if owner else "B"
    return ", ".join(
        f"{stem}{start:04d}"
        if start == end
        else f"{stem}{start:04d}-{stem}{end:04d}"
        for start, end in spans
    )


def comment_wrap(marker: str, label: str, value: str,
                 width: int = MAX_HEADER_WIDTH) -> list[str]:
    lead = f"{label}: " if label else ""
    content_width = width - len(marker) - 1
    assert content_width >= 40
    wrapped = textwrap.wrap(
        value, width=content_width, initial_indent=lead,
        subsequent_indent=" " * len(lead), break_long_words=True,
        break_on_hyphens=False,
    ) or [lead.rstrip()]
    return [f"{marker} {line}" for line in wrapped]


def owner_for(row: dict[str, str], data_id: str) -> str:
    """Assign each rationale to M0/M1/M2, the D axis, or package code."""
    if row["reference_stage"] == "package-added-to-canonical":
        return "PKG"
    if row["category"] == "data-axis-global-exclusion":
        return data_id
    stage_owner = {
        "dataverse-to-m0": "M0",
        "m0-to-m1": "M1",
        "m0-to-m2": "M2",
    }
    try:
        return stage_owner[row["reference_stage"]]
    except KeyError as exc:
        raise AssertionError(f"unclassified annotation stage: {row}") from exc


def owner_description(owner: str) -> str:
    descriptions = {
        "M0": "M0 lineage relative to Dataverse: runability/publication adapters plus the explicitly shared new-v2 OHLC/volume preprocessing amendment.",
        "M1": "M1 full audited correction added beyond M0.",
        "M2": "M2 causal correction beyond M0, including the shared frozen-exit and immediate same-leg no-cash settlement needed to implement terminal observations.",
        "D1": "D1 raw-panel exclusion; a data-treatment change, not an M-method correction.",
        "D2": "D2 raw-panel exclusion; a data-treatment change, not an M-method correction.",
        "PKG": "Package runner/orchestration/test code with no Dataverse source counterpart.",
    }
    return descriptions[owner]


def stage_description(stage: str) -> tuple[str, str]:
    descriptions = {
        "dataverse-to-m0": (
            "M0 CHANGES RELATIVE TO THE DATAVERSE ORIGINAL",
            "M0 execution/publication adapters and the common new-v2 missing-data preprocessing amendment are shown here; D-axis exclusions, if any, carry a separate D1/D2 owner tag.",
        ),
        "m0-to-m1": (
            "M1 ADDITIONAL CHANGES RELATIVE TO M0",
            "Only corrections introduced by M1 beyond the same-D M0 source are shown here.",
        ),
        "m0-to-m2": (
            "M2 ADDITIONAL CHANGES RELATIVE TO M0",
            "Direct look-ahead/future-data corrections plus the frozen terminal-sale and immediate same-leg reinvestment rule required to replace M0's future-year fallback are shown here.",
        ),
        "package-added-to-canonical": (
            "PACKAGE-ONLY CODE",
            "This runner/orchestration/test file has no Dataverse counterpart and is not itself a scientific-source method delta.",
        ),
    }
    return descriptions[stage]


def conceptual_lineage(method: str, data_id: str, section: str) -> str:
    if section != "source":
        return "Package-only code -> canonical packaged file"
    if method == "M0":
        return f"Dataverse-original -> M0_{data_id}"
    return f"Dataverse-original -> M0_{data_id} -> {method}_{data_id}"


def assign_change_groups(rows: list[dict[str, str]]) -> None:
    """Group repeated rationales so a file states each explanation once."""
    groups: dict[tuple[str, str, str, str, str], str] = {}
    group_counts: dict[str, int] = {}
    block_counts: dict[str, int] = {}
    for row in rows:
        owner = row["change_owner"]
        key = (
            owner, row["reference_stage"], row["category"], row["why"], row["effect"],
        )
        if key not in groups:
            group_counts[owner] = group_counts.get(owner, 0) + 1
            groups[key] = f"{owner}-G{group_counts[owner]:02d}"
        row["change_group"] = groups[key]
        block_counts[owner] = block_counts.get(owner, 0) + 1
        row["owner_block_number"] = str(block_counts[owner])
        row["display_block_id"] = f"{owner}-B{block_counts[owner]:04d}"


def default_added_reason(rel: str) -> tuple[str, str, str]:
    name = Path(rel).name
    if rel in M1_ADDED_FILE_REASONS:
        return M1_ADDED_FILE_REASONS[rel]
    if name in M1_HELPER_GROUPS:
        purpose = M1_HELPER_GROUPS[name].rstrip(".")
        return (
            "m1-audited-helper",
            f"M0 has no dedicated, auditable implementation of this requirement: {purpose}. "
            "M1 adds a named helper so every caller uses the same explicit rule.",
            f"When called by M1, this helper implements only the stated requirement ({purpose}); "
            "its presence does not silently change the M0 or M2 method.",
        )
    if rel.startswith("Utils/fAssert") or "Provenance" in name or "Fingerprint" in name or name == "fFileSHA256.m":
        return ("provenance-engineering", "Adds hash, alignment, build-identity, or saved-result assertions so a run fails closed on mixed inputs/code/results.", "Audit/release safety; scientific arrays are not redefined.")
    if rel.startswith("tests/"):
        return ("deterministic-test", "Adds a deterministic regression/invariant test for the documented method or engineering contract.", "Test-only; not called to construct scientific outputs.")
    if rel.startswith("audit/"):
        return ("audit-tool", "Adds a read-only diagnostic for raw-event, extreme-return, or correction validation.", "Audit/sensitivity support; not part of the default main estimand.")
    if rel.endswith(".sh") or rel.endswith(".py"):
        return ("pipeline-engineering", "Adds portable orchestration, validation, monitoring, or publication logic absent from the Dataverse archive.", "No scientific-number change unless the file is an explicitly named scientific audit tool.")
    return ("added-audited-helper", "Adds an explicit helper required by the documented method, numerical fail-closed rule, or provenance contract.", "See the file's own function contract and the exact call-site annotations.")


def reason_for(method: str, data_id: str, rel: str, current: list[str],
               reference: list[str], stage: str,
               reference_file_exists: bool) -> tuple[str, str, str]:
    changed_nonempty = [line.strip() for line in [*reference, *current] if line.strip()]
    path_case_only = bool(changed_nonempty) and all(
        line.startswith("addpath(") for line in changed_nonempty
    )
    if (
        rel == "b01ReadData.m" and data_id != "D0"
        and stage == "dataverse-to-m0" and not path_case_only
    ):
        ids = "CMCID 3787 / INNBCL" if data_id == "D1" else "CMCID 3787 plus the audited event-affected asset list"
        return (
            "data-axis-global-exclusion",
            f"Implements the declared {data_id} exclusion ({ids}) immediately after aligned raw input loading and moves dependent sanitation/return/save operations after that deletion.",
            "These blocks belong to the D-axis raw-panel counterfactual, not M0/M1/M2; the retained columns then follow the method code.",
        )
    if rel.endswith("fApplyConfiguredGlobalAssetExclusion.m"):
        return (
            "data-axis-global-exclusion",
            f"Validates and removes the exact CMCID list supplied by {data_id}.csv before any return, feature, rank, model, or portfolio calculation.",
            "Implements the D-axis counterfactual uniformly across all dates and methods.",
        )
    if stage == "package-added-to-canonical":
        return default_added_reason(rel)
    if method == "M2":
        if rel not in M2_REASONS:
            raise AssertionError(
                f"unclassified M0-to-M2 scientific delta: {data_id}/{rel}"
            )
        return M2_REASONS[rel]
    if method == "M1" and not current and rel in M1_DELETION_REASONS:
        return M1_DELETION_REASONS[rel]
    if method == "M1" and rel in M1_REASONS:
        return M1_REASONS[rel]
    if rel in M0_REASONS:
        return M0_REASONS[rel]
    if not reference_file_exists:
        return default_added_reason(rel)
    if method == "M1":
        return (
            "m1-full-audit-correction",
            "This block is part of M1's paper-first correction or its fail-closed numerical/provenance implementation.",
            "The adjacent source comments and deterministic M1 tests identify the concrete invariant.",
        )
    return (
        "m0-required-adapter",
        "Required to execute/publish the Dataverse method on the sealed headless pipeline without intentionally changing its scientific formulas.",
        "Engineering/runability only.",
    )


def make_header(method: str, data_id: str, section: str, rel: str,
                canonical: bytes, rows: list[dict[str, str]],
                prefix: str) -> bytes:
    role = {
        "source": "materialized scientific source",
        "runner": "method-specific execution runner",
        "orchestration": "shared package orchestration/test code",
    }[section]
    p4 = hierarchy_marker(prefix, 4)
    p3 = hierarchy_marker(prefix, 3)
    p2 = hierarchy_marker(prefix, 2)
    detail = hierarchy_marker(prefix, 1, detail=True)
    separator4 = f"{p4} " + "=" * (MAX_HEADER_WIDTH - len(p4) - 1)
    separator3 = f"{p3} " + "-" * (MAX_HEADER_WIDTH - len(p3) - 1)

    groups: dict[str, list[tuple[int, dict[str, str]]]] = {}
    for index, row in enumerate(rows, 1):
        groups.setdefault(row["change_group"], []).append((index, row))

    lines = [
        f"{p4} {HEADER_BEGIN}",
        separator4,
        f"{p4} REVIEW-ONLY GUIDE - NOT EXECUTABLE METHOD CODE",
        separator4,
    ]
    lines.extend(comment_wrap(p4, "File", f"{rel} ({role})"))
    lines.extend(comment_wrap(p4, "Experiment", f"{method}_{data_id}"))
    lines.extend(comment_wrap(
        p4, "Method lineage", conceptual_lineage(method, data_id, section)
    ))
    lines.extend(comment_wrap(
        p4, "Hierarchy",
        "%%%% review boundary/navigation | %%% comparison step | %% change owner and reason | "
        "%>>> exact old/new diff block.",
    ))
    lines.extend(comment_wrap(
        p4, "Safety",
        "Every line through V4_END is review-only. Delete this complete header and the remaining "
        "bytes are identical to the canonical materialized file. Body line numbers exclude this header.",
    ))
    lines.extend(comment_wrap(
        p4, "After V4_END",
        "All comments belong to the canonical source body; they are not review-guide annotations.",
    ))
    owners = list(dict.fromkeys(row["change_owner"] for row in rows))
    lines.extend(comment_wrap(p4, "Owners present", ", ".join(owners)))
    for owner in owners:
        lines.extend(comment_wrap(p4, f"Owner {owner}", owner_description(owner)))
    lines.extend(comment_wrap(
        p4, "Scope",
        f"{len(rows)} exact diff block(s) in {len(groups)} de-duplicated reason group(s).",
    ))

    seen_stages: set[tuple[str, str, str, str, str]] = set()
    stages: list[tuple[str, str, str, str, str]] = []
    for row in rows:
        stage_key = (
            row["reference_stage"], row["reference_name"], row["target_name"],
            row["reference_sha256"], row["target_sha256"],
        )
        if stage_key in seen_stages:
            continue
        seen_stages.add(stage_key)
        stages.append(stage_key)

    if section == "source" and method in {"M1", "M2"}:
        method_stage = f"m0-to-{method.lower()}"
        if not any(stage == method_stage for stage, *_ in stages):
            lines.extend(comment_wrap(
                p4, f"{method} delta in this file",
                f"None. After the inherited M0/D-axis changes shown below, the {method} body is "
                "byte-identical to the same-D M0 body.",
            ))

    if method == "M2" and rel == "Utils/fCreatePanelExAnteM2.m":
        lines.extend(comment_wrap(
            p4, "Important terminology",
            "The frozen body says predictors must be 'finite', but the executable M0 convention is "
            "exactly non-NaN (~isnan), so +/-Inf is retained. The body remains unchanged to preserve "
            "the production source hash.",
        ))

    for step, stage_key in enumerate(stages, 1):
        stage, reference, target, _, _ = stage_key
        stage_title, stage_meaning = stage_description(stage)
        stage_rows = [
            (index, row) for index, row in enumerate(rows, 1)
            if (
                row["reference_stage"], row["reference_name"], row["target_name"],
                row["reference_sha256"], row["target_sha256"],
            ) == stage_key
        ]
        stage_group_ids = list(dict.fromkeys(row["change_group"] for _, row in stage_rows))
        lines.extend([p3, separator3])
        lines.extend(comment_wrap(p3, f"STEP {step}", stage_title))
        lines.extend(comment_wrap(p3, "Compared", f"{reference} -> {target}"))
        lines.extend(comment_wrap(p3, "Meaning", stage_meaning))
        lines.extend(comment_wrap(
            p3, "Groups in this step", ", ".join(stage_group_ids)
        ))

        for group_id in stage_group_ids:
            members = groups[group_id]
            row = members[0][1]
            owner = row["change_owner"]
            owner_numbers = [int(member["owner_block_number"]) for _, member in members]
            title = row["category"].replace("-", " ").upper()
            lines.append(p2)
            lines.extend(comment_wrap(
                p2, f"[{group_id}] {title}", compact_numbers(owner_numbers, owner)
            ))
            lines.extend(comment_wrap(p2, "Owner", owner_description(owner)))
            lines.extend(comment_wrap(p2, "Why changed", row["why"]))
            lines.extend(comment_wrap(p2, "Result impact", row["effect"]))

        lines.extend(comment_wrap(
            p3, "Exact blocks", "listed in source-diff order; each block points back to its %% group"
        ))
        for _, member in stage_rows:
            location = (
                f"{member['reference_name']} {human_span(member['reference_lines'])} -> "
                f"{member['target_name']} {human_span(member['target_lines'])}"
            )
            block_label = (
                f"[{member['display_block_id']}/{member['change_group']}] "
                f"{member['operation'].upper()}"
            )
            lines.extend(comment_wrap(detail, block_label, location))
            if member["reference_excerpt"]:
                lines.extend(comment_wrap(detail, "OLD", member["reference_excerpt"]))
            if member["target_excerpt"]:
                label = "ADDED" if member["operation"] in {"insert", "added-file"} else "NEW"
                lines.extend(comment_wrap(detail, label, member["target_excerpt"]))

    lines.extend([p4, separator4, f"{p4} MACHINE AUDIT - NOT NEEDED FOR FIRST-PASS READING", separator4])
    lines.extend(comment_wrap(p4, "Canonical SHA-256", sha256(canonical)))
    lines.extend(comment_wrap(
        p4, "Machine index",
        f"ANNOTATION_INDEX.csv key={method}_{data_id}|{section}|{rel}; it stores exact operations, "
        "owners, line spans, full hashes, context, and excerpts for every block.",
    ))
    for stage, reference, target, reference_sha, target_sha in stages:
        lines.extend(comment_wrap(p4, "Stage", stage))
        lines.extend(comment_wrap(p4, "Compared", f"{reference} -> {target}"))
        lines.extend(comment_wrap(p4, "Reference SHA-256", reference_sha))
        lines.extend(comment_wrap(p4, "Target SHA-256", target_sha))
    lines.extend([separator4, f"{p4} {HEADER_END}"])
    return ("\n".join(lines) + "\n").encode("utf-8") + canonical


def diff_rows(method: str, data_id: str, rel: str,
              target: bytes, reference: bytes | None, *,
              stage: str, reference_name: str,
              target_name: str) -> list[dict[str, str]]:
    current_lines = target.decode("utf-8", errors="replace").splitlines()
    reference_sha = sha256(reference) if reference is not None else "NA"
    target_sha = sha256(target)
    if reference is None:
        category, why, effect = reason_for(
            method, data_id, rel, current_lines, [], stage, False
        )
        return [{
            "reference_stage": stage,
            "reference_name": reference_name,
            "target_name": target_name,
            "operation": "added-file",
            "reference_lines": "NA",
            "target_lines": format_span(0, len(current_lines)),
            "category": category,
            "why": why,
            "effect": effect,
            "context": nearby_comment(current_lines),
            "reference_excerpt": "",
            "target_excerpt": readable_excerpt(current_lines),
            "reference_block": "",
            "target_block": "\n".join(current_lines),
            "reference_sha256": reference_sha,
            "target_sha256": target_sha,
        }]
    reference_lines = reference.decode("utf-8", errors="replace").splitlines()
    matcher = difflib.SequenceMatcher(None, reference_lines, current_lines, autojunk=False)
    rows: list[dict[str, str]] = []
    for operation, i1, i2, j1, j2 in matcher.get_opcodes():
        if operation == "equal":
            continue
        category, why, effect = reason_for(
            method, data_id, rel, current_lines[j1:j2],
            reference_lines[i1:i2], stage, True
        )
        context = nearby_comment(current_lines[max(0, j1 - 3):min(len(current_lines), j2 + 3)])
        rows.append({
            "reference_stage": stage,
            "reference_name": reference_name,
            "target_name": target_name,
            "operation": operation,
            "reference_lines": format_span(i1, i2),
            "target_lines": format_span(j1, j2),
            "category": category,
            "why": why,
            "effect": effect,
            "context": context,
            "reference_excerpt": readable_excerpt(reference_lines[i1:i2]),
            "target_excerpt": readable_excerpt(current_lines[j1:j2]),
            "reference_block": "\n".join(reference_lines[i1:i2]),
            "target_block": "\n".join(current_lines[j1:j2]),
            "reference_sha256": reference_sha,
            "target_sha256": target_sha,
        })
    return rows


def copy_materialized_source(root: Path, method: str, data_id: str, dest: Path) -> dict[str, Path]:
    base = root / "engines" / method / "base"
    overlay = root / "engines" / method / "overlays" / "exclusion"
    shutil.copytree(base, dest)
    origins = {p.relative_to(dest).as_posix(): base / p.relative_to(dest)
               for p in dest.rglob("*") if p.is_file()}
    if data_id != "D0":
        for rel in [Path("b01ReadData.m"), Path("Utils/fApplyConfiguredGlobalAssetExclusion.m")]:
            source = overlay / rel
            target = dest / rel
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(source, target)
            origins[rel.as_posix()] = source
        optional = overlay / "Utils" / "fFileSHA256.m"
        if optional.is_file():
            target = dest / "Utils" / optional.name
            shutil.copy2(optional, target)
            origins[target.relative_to(dest).as_posix()] = optional
    return origins


def copy_common_orchestration(root: Path, dest: Path) -> dict[str, Path]:
    """Copy the shared, experiment-agnostic executable package code.

    These files have no Dataverse counterpart: the public archive did not
    include a portable one-command runner, provenance/release layer, or the
    package-level tests.  They are repeated in all nine mirrors deliberately
    so that each experiment has a self-contained code-review surface.
    """
    origins: dict[str, Path] = {}
    top_level = [Path("run_all.sh"), Path("run_all.m"), Path("run_all.bat")]
    trees = [Path("scripts"), Path("tests"), Path("release")]
    singletons = [Path("environment/environment_check.m"), Path("config/project_config.m")]
    selected: list[Path] = []
    selected.extend(top_level)
    selected.extend(singletons)
    for tree in trees:
        selected.extend(
            p.relative_to(root) for p in (root / tree).rglob("*")
            if p.is_file() and "__pycache__" not in p.parts
        )
    for rel in sorted(set(selected), key=lambda p: p.as_posix()):
        if rel.as_posix() in {"release/FILE_MANIFEST.csv", "release/SHA256SUMS"}:
            # These are generated only after the release tree is staged.  They
            # are inventories of the staged tree, not executable source files.
            continue
        source = root / rel
        if not source.is_file():
            continue
        target = dest / rel
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(source, target)
        origins[rel.as_posix()] = source
    return origins


def annotate_tree(root: Path, original_root: Path, method: str, data_id: str,
                  section: str, tree: Path, origins: dict[str, Path],
                  writer: csv.DictWriter, m0_reference_tree: Path | None = None) -> None:
    for path in sorted((p for p in tree.rglob("*") if p.is_file()),
                       key=lambda p: p.relative_to(tree).as_posix()):
        rel = path.relative_to(tree).as_posix()
        canonical_path = origins[rel]
        canonical = path.read_bytes()
        if path.suffix not in TEXT_SUFFIXES:
            continue
        rows: list[dict[str, str]] = []
        if section != "source":
            rows.extend(diff_rows(
                method, data_id, rel, canonical, None,
                stage="package-added-to-canonical",
                reference_name="NO_DATAVERSE_COUNTERPART",
                target_name=f"{method}_{data_id}:{section}",
            ))
        else:
            original_path = original_root / rel
            original = original_path.read_bytes() if original_path.is_file() else None
            if method in {"M1", "M2"}:
                if m0_reference_tree is None:
                    raise AssertionError(
                        f"{method} annotation requires a materialized same-D M0 reference"
                    )
                m0_path = m0_reference_tree / rel
                m0_bytes = m0_path.read_bytes() if m0_path.is_file() else None
                if m0_bytes is not None:
                    rows.extend(diff_rows(
                        "M0", data_id, rel, m0_bytes, original,
                        stage="dataverse-to-m0",
                        reference_name="Dataverse-original",
                        target_name=f"M0_{data_id}",
                    ))
                rows.extend(diff_rows(
                    method, data_id, rel, canonical, m0_bytes,
                    stage=f"m0-to-{method.lower()}",
                    reference_name=f"M0_{data_id}",
                    target_name=f"{method}_{data_id}",
                ))
            else:
                rows.extend(diff_rows(
                    method, data_id, rel, canonical, original,
                    stage=f"dataverse-to-{method.lower()}",
                    reference_name="Dataverse-original",
                    target_name=f"{method}_{data_id}",
                ))
        if not rows:
            continue
        for row in rows:
            row["change_owner"] = owner_for(row, data_id)
        assign_change_groups(rows)
        annotated = make_header(
            method, data_id, section, rel, canonical, rows,
            comment_prefix(path),
        )
        path.write_bytes(annotated)
        mode = canonical_path.stat().st_mode
        os.chmod(path, stat.S_IMODE(mode))
        for idx, row in enumerate(rows, 1):
            writer.writerow({
                "experiment_id": f"{method}_{data_id}",
                "section": section,
                "relative_path": rel,
                "block": idx,
                "display_block_id": row["display_block_id"],
                "change_owner": row["change_owner"],
                "change_group": row["change_group"],
                "reference_stage": row["reference_stage"],
                "reference_name": row["reference_name"],
                "target_name": row["target_name"],
                "operation": row["operation"],
                "reference_lines": row["reference_lines"],
                "target_lines": row["target_lines"],
                "category": row["category"],
                "why": row["why"],
                "scientific_effect": row["effect"],
                "context": row["context"],
                "reference_excerpt": row["reference_excerpt"],
                "target_excerpt": row["target_excerpt"],
                "reference_sha256": row["reference_sha256"],
                "target_sha256": row["target_sha256"],
                "canonical_sha256": sha256(canonical),
                "annotated_body_sha256": sha256(canonical),
                "canonical_origin": str(canonical_path.relative_to(root)),
            })


def record_deleted_source_files(original_root: Path, method: str, data_id: str,
                                materialized_source: Path,
                                experiment_root: Path,
                                writer: csv.DictWriter,
                                m0_reference_tree: Path | None = None) -> None:
    """Record complete source removals against the method's immediate baseline."""
    if method == "M0":
        reference_root = original_root
        stage = "dataverse-to-m0"
        reference_name = "Dataverse-original"
        reason_method = "M0"
    else:
        if m0_reference_tree is None:
            raise AssertionError(f"{method} deletion audit requires the same-D M0 source")
        reference_root = m0_reference_tree
        stage = f"m0-to-{method.lower()}"
        reference_name = f"M0_{data_id}"
        reason_method = method
    deleted = [
        path for path in reference_root.rglob("*")
        if path.is_file()
        and path.suffix in TEXT_SUFFIXES
        and not (materialized_source / path.relative_to(reference_root)).is_file()
    ]
    if not deleted:
        return
    report = [
        f"# {method}_{data_id}: source files deleted relative to {reference_name}\n",
        "A completely deleted file cannot carry an inline review header. This companion "
        "records its owner, immediate comparison, reason, effect, and hash; every item is also present in "
        "the global `ANNOTATION_INDEX.csv`.\n",
    ]
    for path in sorted(deleted, key=lambda item: item.relative_to(reference_root).as_posix()):
        rel = path.relative_to(reference_root).as_posix()
        reference = path.read_bytes()
        reference_lines = reference.decode("utf-8", errors="replace").splitlines()
        category, why, effect = reason_for(
            reason_method, data_id, rel, [], reference_lines, stage, True,
        )
        row = {
            "reference_stage": stage,
            "category": category,
            "why": why,
            "effect": effect,
        }
        row["change_owner"] = owner_for(row, data_id)
        row["change_group"] = f"{row['change_owner']}-G01"
        row["display_block_id"] = f"{row['change_owner']}-B0001"
        report.extend([
            f"## `{rel}`\n",
            f"- Owner: `{row['change_owner']}` — {owner_description(row['change_owner'])}\n",
            f"- Compared: `{reference_name} -> {method}_{data_id}`\n",
            f"- Category: `{category}`\n",
            f"- Why changed: {why}\n",
            f"- Result impact: {effect}\n",
            f"- Reference SHA-256: `{sha256(reference)}`\n",
        ])
        writer.writerow({
            "experiment_id": f"{method}_{data_id}",
            "section": "source-deletion",
            "relative_path": rel,
            "block": 1,
            "display_block_id": row["display_block_id"],
            "change_owner": row["change_owner"],
            "change_group": row["change_group"],
            "reference_stage": stage,
            "reference_name": reference_name,
            "target_name": f"{method}_{data_id}",
            "operation": "deleted-file",
            "reference_lines": format_span(0, len(reference_lines)),
            "target_lines": "NA",
            "category": category,
            "why": why,
            "scientific_effect": effect,
            "context": nearby_comment(reference_lines),
            "reference_excerpt": readable_excerpt(reference_lines),
            "target_excerpt": "",
            "reference_sha256": sha256(reference),
            "target_sha256": "NA",
            "canonical_sha256": "NA",
            "annotated_body_sha256": "NA",
            "canonical_origin": "DELETED",
        })
    (experiment_root / "DELETED_SOURCE_FILES.md").write_text(
        "\n".join(report).rstrip() + "\n", encoding="utf-8"
    )


def write_manifest(base: Path, filename: str) -> None:
    target = base / filename
    rows = []
    for path in sorted((p for p in base.rglob("*") if p.is_file() and p != target),
                       key=lambda p: p.relative_to(base).as_posix()):
        rows.append(f"{sha256(path.read_bytes())}  {path.relative_to(base).as_posix()}\n")
    target.write_text("".join(rows), encoding="utf-8")


def main() -> int:
    root = Path(__file__).resolve().parents[1]
    original_root = root / "reference" / "dataverse_original_3d0959b1"
    output = root / "annotated_sources"
    if not (original_root / "b01ReadData.m").is_file():
        raise SystemExit(f"missing Dataverse reference: {original_root}")
    if output.exists() or output.is_symlink():
        shutil.rmtree(output)
    output.mkdir()

    # M1 and M2 are reviewed as explicit deltas beyond M0, not as opaque
    # independent rewrites of Dataverse. Materialize all three same-D M0
    # baselines once so each header can show both evidence-chain steps.
    # Materialize all three M0 data-axis variants outside the release tree so
    # annotations can distinguish inherited M0 adapters from true M0->M2
    # look-ahead corrections.
    m0_temp = tempfile.TemporaryDirectory(prefix="cttrend_m0_annotation_reference_")
    m0_reference_root = Path(m0_temp.name)
    m0_references: dict[str, Path] = {}
    for data_id in ("D0", "D1", "D2"):
        target = m0_reference_root / data_id
        copy_materialized_source(root, "M0", data_id, target)
        m0_references[data_id] = target

    index_path = output / "ANNOTATION_INDEX.csv"
    fieldnames = [
        "experiment_id", "section", "relative_path", "block", "display_block_id",
        "change_owner", "change_group", "operation",
        "reference_stage", "reference_name", "target_name",
        "reference_lines", "target_lines", "category", "why",
        "scientific_effect", "context", "reference_excerpt", "target_excerpt",
        "reference_sha256", "target_sha256",
        "canonical_sha256", "annotated_body_sha256", "canonical_origin",
    ]
    with index_path.open("w", newline="", encoding="utf-8") as handle:
        # Force LF even when csv is opened with newline="".  The csv module's
        # default CRLF terminator is valid CSV, but Git treats the carriage
        # return as trailing whitespace in text diffs.
        writer = csv.DictWriter(handle, fieldnames=fieldnames, lineterminator="\n")
        writer.writeheader()
        for experiment in EXPERIMENTS:
            method, data_id = experiment.split("_")
            exp_root = output / experiment
            source = exp_root / "source"
            source_origins = copy_materialized_source(root, method, data_id, source)
            annotate_tree(
                root, original_root, method, data_id, "source", source,
                source_origins, writer,
                m0_reference_tree=m0_references[data_id]
                if method in {"M1", "M2"} else None,
            )
            record_deleted_source_files(
                original_root, method, data_id, source, exp_root, writer,
                m0_reference_tree=m0_references[data_id]
                if method in {"M1", "M2"} else None,
            )

            runner_source = root / "engines" / method / "runner"
            runner = exp_root / "runner"
            shutil.copytree(runner_source, runner)
            runner_origins = {p.relative_to(runner).as_posix(): runner_source / p.relative_to(runner)
                              for p in runner.rglob("*") if p.is_file()}
            annotate_tree(root, original_root, method, data_id, "runner", runner, runner_origins, writer)

            orchestration = exp_root / "orchestration"
            orchestration_origins = copy_common_orchestration(root, orchestration)
            annotate_tree(
                root, original_root, method, data_id, "orchestration",
                orchestration, orchestration_origins, writer,
            )

            exclusion = root / "config" / "exclusions" / f"{data_id}.csv"
            shutil.copy2(exclusion, exp_root / "data_exclusion.csv")
            (exp_root / "EXPERIMENT_ANNOTATION.md").write_text(
                f"# {experiment} annotated review mirror\n\n"
                f"This directory materializes method `{method}` with data treatment `{data_id}`. "
                "Each changed text file begins with a human-oriented V4 comment header. Remove the "
                "complete `CTREND_REVISIT_ANNOTATION_HEADER_V4` block and the remaining bytes are "
                "identical to the executable materialized source.\n\n"
                "The percent-sign hierarchy is semantic:\n\n"
                "1. `%%%%` — review-only boundary, legend, and machine audit;\n"
                "2. `%%%` — one explicit comparison step;\n"
                "3. `%%` — one owner-tagged rationale group (`M0`, `M1`, `M2`, `D1/D2`, or `PKG`);\n"
                "4. `%>>>` — one exact old/new diff block and its body line locations.\n\n"
                "M0 uses `Dataverse -> M0`. Both M1 and M2 use two steps: "
                "`Dataverse -> same-D M0 -> M1/M2`. This visibly separates inherited M0 adapters "
                "from changes introduced by M1 or M2. D-axis exclusions carry their own owner tag.\n\n"
                "- `source/`: materialized MATLAB scientific source;\n"
                "- `runner/`: method-specific parallel and publication runner;\n"
                "- `orchestration/`: shared execution, provenance, release, and test code;\n"
                "- `data_exclusion.csv`: exact D-axis exclusion list;\n"
                "- `ANNOTATED_FILES.sha256`: complete mirror inventory.\n\n"
                "Production never reads this directory; it materializes from `engines/`.\n",
                encoding="utf-8",
            )
            write_manifest(exp_root, "ANNOTATED_FILES.sha256")

    (output / "README.md").write_text(
        "# How to read the annotated source mirrors\n\n"
        "The nine directories are review-only views of the executable experiment cells. Each changed "
        "text file has a V4 comment header whose percent-sign count identifies its role immediately.\n\n"
        "- `%%%%`: review-only guide/audit material, never a production-code modification;\n"
        "- `%%%`: an explicit lineage step (`Dataverse -> M0`, `M0 -> M1`, or `M0 -> M2`);\n"
        "- `%%`: an owner-tagged reason group (`M0`, `M1`, `M2`, `D1/D2`, or `PKG`);\n"
        "- `%>>>`: one exact diff block with old/new excerpts and body line locations.\n\n"
        "M1 and M2 are never shown as opaque direct rewrites: both use the same-D M0 as their immediate "
        "baseline, while inherited M0 changes remain in a separate first step.\n\n"
        "`ANNOTATION_INDEX.csv` is the machine-readable source of truth. It contains the same block/group "
        "IDs, exact line spans, full hashes, contextual anchors, and short before/after excerpts. "
        "`ANNOTATED_RELEASE.sha256` inventories this complete directory.\n\n"
        "Removing a V4 header must reproduce the canonical materialized bytes exactly; the deterministic "
        "equivalence, opcode-coverage, and readability tests enforce that property.\n",
        encoding="utf-8",
    )
    m0_temp.cleanup()
    write_manifest(output, "ANNOTATED_RELEASE.sha256")
    print(f"ANNOTATED_SOURCE_MIRRORS_OK experiments={len(EXPERIMENTS)} index={index_path}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
