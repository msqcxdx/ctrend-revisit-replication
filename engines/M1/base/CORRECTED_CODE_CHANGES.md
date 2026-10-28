# M1 Fully Audited Pipeline: Correction Register

## 1. Purpose and authority

This document describes the scientific differences between the published-code
method (M0) and the fully audited method (M1). It is a current specification,
not a chronological development log and not evidence that a run succeeded.
Run success is established only by the immutable run inventories,
`RUN_COMPLETE`, result checks, and experiment registration.

The decision order is:

1. reject engineering, timing, accounting, statistical-domain, or numerical
   errors;
2. follow an explicit and internally consistent paper definition;
3. retain the published implementation when the paper is silent and the
   implementation is not erroneous;
4. disclose every necessary choice when the paper is ambiguous or conflicts
   with the implementation.

The normative package-level specification is
`docs/METHOD_BOUNDARIES.md`. Deterministic enforcement is provided by
`tests/integration/test_method_boundary_contract.py` and the M1 engine tests.

## 2. Summary of the correction classes

| Area | Published-code issue | M1 treatment | Principal consumers |
|---|---|---|---|
| Future-data access | A missing weekly endpoint may fall back to a later observation in the same calendar-year block | Freeze the terminal calendar before models; sell at the last tradable close and immediately reinvest within the same leg | b02 and all weekly consumers |
| Outcome preprocessing | A realized target-week return can help determine its own truncation or winsorization | Clean only already-realized historical training/validation labels; never transform the current OOS target | b05, b07, b09, b18 |
| Economic payoff | Cleaned synchronized labels are used as if they were realizable investment returns | Separate statistical labels from raw positive-close endpoint P&L | Portfolio tables, figures, turnover, costs |
| Formation support | Realized t+1 outcome support can determine model-training rows or predictor ranks | Estimate/rank on formation support; apply declared target availability only when the executable portfolio is allocated | b05, b09, Figure C, sort helpers |
| Target availability and settlement | The public path conflates an unavailable target, a terminal event, and a later relisting | Remove an entirely unavailable target before breakpoints; sell a frozen terminal holding and immediately reinvest all proceeds among same-leg survivors | b04-b06, b08-b10, b13-b17 |
| Predictor support | One predictor's missingness can shrink every other predictor's rank/estimation support | Rank and estimate each predictor on its own eligible formation-time support | b05, b09, b18 |
| Forecast combination | Selected forecasts can be dynamically reweighted or averaged without the paper's denominator | Freeze the validation-selected set, require every selected forecast OOS, and retain `1/J_selected` | b05, b09, Figure C |
| Indicator definitions | Several windows, oscillators, and volume/price indicators differ from the paper or cross gaps | Use paper parameters and require a continuous valid history after a gap | b02, Table 2, CTREND predictors |
| Market series | Missing-return assets can remain in the denominator and receive an implicit zero return | Normalize only on asset-days where both return and lagged market cap are defined | Market characteristics and Table 5 |
| Table-specific definitions | Several market-cap, IVOL, rolling-window, holding-period, and importance definitions differ from the paper | Apply the audited paper-first definitions described below | Tables 3, 7, 9, B.10; Figure C |
| Statistical domain | Singular, rank-deficient, or non-common samples can still emit numerical values | Apply support, rank, degree-of-freedom, and common-sample checks; return NaN when undefined | Tables 4, 6, 7; alphas and tests |
| Publication | Files can be overwritten, mixed across runs, or accepted without complete b09 coverage | Use sealed runtimes, independent process groups, inventories, 3,072 sidecars, and atomic publication | Entire production run |

These changes can interact. M1-versus-M0 is the joint effect of the complete
audited correction and must not be interpreted as the causal effect of any
single row in this table. M2 exists specifically to isolate the removal of
demonstrable look-ahead channels while retaining unrelated M0 definitions.

## 3. Input and time-series construction

### 3.1 Preserve the unscreened raw panel

An asset that is ineligible for one strategy must not be deleted from the
upstream panel. M1 retains stablecoins, low-market-cap assets, short histories,
and internal gaps in the raw input. Dynamic strategy-specific eligibility is
applied only by the consumer that needs it.

M1 verifies that OHLC, volume, market cap, and metadata have identical,
strictly ordered date and asset axes. It rejects silent date/asset
intersections, duplicated CMCIDs, inconsistent column order, or an invalid BTC
metadata anchor. Raw source files are hashed before and after snapshotting and
again before publication.

### 3.2 Common new-v2 missing-data preprocessing

Before synchronization or feature construction, all three methods apply the
same declared rule. Inside an asset's observed lifetime, a missing/invalid open,
high, low, or close is filled from the strictly previous valid close. A
non-finite or negative volume/turnover observation is zero. Leading prices and prices after the
last original nonmissing close remain missing, so the rule cannot fabricate an
asset before listing or after its mechanical terminal date. The unmodified raw
vendor arrays and an exact fill audit are preserved for provenance.

### 3.3 Weekly boundaries

Scheduled weekly endpoint fields use the observation at the declared endpoint
after the common preprocessing layer. They cannot search later in the calendar
year. The mechanical last-positive-close calendar is frozen before model or
portfolio formation, and every weekly field carries and checks the same
explicit calendar axis.

## 4. Statistical labels versus economic P&L

M1 maintains distinct layers:

- `mReturns` and `mRetLead`: synchronized core-close statistical labels;
- `mPnlReturns` and `mPnlRetLead`: raw positive-close endpoint economic
  returns;
- `vMktRet`: the statistical market-characteristic proxy;
- `vMktPnl`: the economic market-return series.

Historical label cleaning serves model training only. For each realized
training or validation week, the cutoff is estimated from that week's
formation-eligible return cross-section and applied only to that historical
label. The target OOS week neither sets nor receives the outlier transform.
Truncation and winsorization never alter raw investment P&L.

Table 4 deliberately remains a statistical-label predictive regression. It is
not converted into an endpoint-P&L regression. Portfolio returns, turnover,
transaction costs, and cumulative economic paths use the raw endpoint layer.

## 5. Formation, ranking, and walking-forward estimation

### 5.1 Formation versus holding

Model estimation and predictor ranks use formation information rather than the
realized target outcome. At executable allocation, binary target
unavailability is treated as announcement-equivalent: the unavailable asset
is removed before breakpoints and survivor weights are renormalized. If a held
asset reaches its frozen terminal date, the position is sold at that last
tradable close and all proceeds are immediately invested among surviving
members of the same leg. EW uses equal recipient shares; VW uses event-day
market capitalization. No cash, cross-leg transfer, later week, or relisting
quote may enter the accounting.

### 5.2 Predictor-own support

Each predictor is ranked to `[-0.5, 0.5]` using its own formation-time observed
and eligible cross-section. The panel is the union of predictor-specific rows.
Equation (7) estimates predictor `j` only on its own finite `X_j/Y/W` support
and renormalizes weights on that date and support. Missingness in a different
predictor cannot change predictor `j`'s rank or coefficient sample.

### 5.3 Validation and combination

Models that require validation reserve the final 12 calendar weeks of the
in-sample period. The selected component set is frozen after validation and is
not re-estimated on a recombined train-plus-validation sample. Equation (10)
selection requires a complete component-forecast vector. OOS, every selected
component must be available; otherwise the combined forecast fails closed.
Equation (11) retains the explicit `1/J_selected` average.

The b05 baseline and the field-matched b09 baseline use the same estimator.
The baseline must be located by its complete design fields, not assumed to be
physical combo 1.

## 6. Technical indicators and market characteristics

M1 aligns declared windows and formulas with the paper and Appendix A,
including the relevant SMA, RSI, stochastic, CCI, Chaikin, Bollinger, and
price/volume oscillator definitions. Fixed windows reacquire a complete
continuous history after a gap. The project EMA convention and its documented
initialization are retained where intended.

The dynamic market statistic normalizes lagged market-cap weights only across
asset-days with an observed return and valid formation eligibility. An asset
with a missing return cannot occupy denominator weight while contributing an
implicit zero payoff.

## 7. Paper-table and figure contracts

### Table 3

Use lagged weekly-average market capitalization, IVOL in percentage units, and
endpoint economic P&L. Table 3's characteristic definitions do not replace the
formation-date market-cap variable used by Equation (7); the published code
also used different variables in these two consumers.

### Table 4

Retain the established statistical-label scale and regression meaning. Do not
substitute portfolio P&L or impose an arbitrary Fama-MacBeth minimum cross
section beyond actual identification requirements.

### Table 6

Create and verify the complete 3,072-design manifest before any reporting
filter. The paper table retains method-specific available-case Sharpe ratios.
Parallel audit outputs additionally report common-week, balanced-cell,
coverage, overlap, and failure-reason comparisons so method differences are
not mislabeled as pure estimator effects.

### Table 7

Use exactly the preceding 52 calendar positions, local listwise deletion, and
no search into older weeks to refill the window. Rank or conditioning failure
returns NaN.

### Table 8 and Table 9

Large/liquid membership is determined at formation, not by t+1 payoff
availability. Table 9 distinguishes full L1 cost bases from the paper's
displayed half-L1 GKX turnover. H-L displayed turnover is the average of the
two legs' half-L1 turnover; H-L cost is the sum of the two leg costs. The first
OOS target is built from cash and incurs cost.

A frozen terminal settlement includes the observed holding return, the sale,
and the immediate same-leg purchase in the full-L1 cost base. The resulting
end-of-week weights remain fully invested in surviving risky holdings.

A formation gap breaks the accounting episode. Turnover, cost, and net return
on the first target after a gap are undefined, but a complete target can become
the state for the next adjacent transition. A missing prior selected payoff
makes the next transition unobservable. No terminal liquidation is fabricated.

### Table B.10

Preserve the Dataverse block phase `(1, 1+H, ...)`; use fixed nonoverlapping
formation cohorts, fixed members, buy-and-hold weight drift, and frozen
terminal sales followed by immediate same-leg reinvestment. Do not reselect
members every week. A partial final calendar block uses only observed positions
and does not invent future weeks.

### Figures C.3-C.4

Use the same predictor-own ranks, betas, and validation-selected set as b05 and
b09. Predictor `N_j` depends only on predictor `j` being observed at t and its
raw return being observed at t+1. An unselected variable has importance zero;
an estimation failure remains missing and must not be encoded as zero.

## 8. Statistical and numerical fail-closed rules

M1 checks sample support, rank, conditioning, degrees of freedom, paired
samples, and covariance definition before reporting a statistic. Undefined
Sharpe ratios, alphas, t statistics, GRS tests, regressions, or portfolio legs
remain NaN. Missing or failed computations are never filled with zero.

Table 6 stores named estimation states and distinguishes structural
non-identification, insufficient history or cross-section, missing endpoints,
empty selection, rank failure, undefined AICc, numerical failure, and expected
coverage rejection. Engineering coverage gates certify execution completeness;
they do not enter an estimator or turn a failed week into data.

## 9. Intended definitions that must not be “cleaned up”

The following are deliberate boundaries, not unresolved defects:

- Table 4 remains a statistical-label regression;
- b08 synchronization, the documented EMA definition, weekly-volatility
  parameter, and risk-free weekend adjustment are retained;
- no arbitrary Fama-MacBeth minimum sample threshold is added;
- dormant helpers are not rewritten merely for style;
- declared target unavailability is removed before breakpoints and survivors
  are reweighted; frozen terminal holdings are sold and immediately reinvested
  inside the same leg, with no cash or cross-leg transfer;
- Table 9 uses the cost and turnover distinctions described above;
- Table B.10 remains a fixed-cohort design;
- `vMktRet` and `vMktPnl` cannot be interchanged;
- supplementary variants run explicitly and cannot edit production source in
  place;
- no unfrozen terminal liquidation, later delisting/relisting price, or
  formation-gap cash observation is fabricated.

## 10. Engineering and publication boundary

Engineering changes are allowed only when they do not change the scientific
value definition. Examples include the bitwise-tested b02 asset-chunk schedule,
lossless b09 range sharding, headless figure export, portable relative paths,
and provenance/publication wrappers.

Each production run uses regular run-local raw snapshots, an immutable runtime
package, isolated staging DATA and Results, independent phase process groups,
atomic result files with SHA-256 sidecars, and a complete 3,072-combo manifest.
Source, runner, runtime, raw input, design, and result inventories are checked
again before publication. `RUN_COMPLETE` is written only after all required
tables, figures, supplementary outputs, and inventories pass.

## 11. Interpretation

Paper-versus-M0 differences can combine code and data-version differences.
M0-versus-M1 on the same D universe measures the joint effect of the full
audited method revision. It cannot identify the isolated effect of outlier
processing or any other single correction. M0-versus-M2 on the same D universe
is the designated look-ahead ablation; M2-versus-M1 captures the remaining
audited corrections.

A NaN denotes an undefined or unobservable quantity, not a zero return. The
results may support or weaken the paper's economic conclusions, but the source
audit does not by itself establish misconduct or identify the contribution of
each error separately.
