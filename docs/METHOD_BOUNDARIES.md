# Scientific and Data Boundaries

This document specifies the eighteen P/M/D experiments. The executable
contracts enforce these boundaries. Unprefixed M_D identifiers denote the P1
inner engine unless a fixed-P comparison is explicitly stated.

## 1. Design decomposition

The design crosses two input conventions, three methods, and three fixed data
universes. Within each fixed P group:

- `M2_Dk - M0_Dk` isolates demonstrable look-ahead repairs plus the terminal
  settlement implementation needed to remove later-price access coherently;
- `M1_Dk - M2_Dk` isolates the remaining full-audit corrections;
- `M1_Dk - M0_Dk` is the total method contrast;
- `Mm_D1 - Mm_D0` is the INNBCL sensitivity;
- `Mm_D2 - Mm_D1` is the incremental event-asset sensitivity.

These are sample estimator/universe decompositions, not structural causal
effects.

The following input convention applies only to the nine P1 cells; P0 omits it. Within an
asset's observed lifetime, a missing/invalid open, high, low, or close is filled
from the strictly prior valid close; non-finite or negative volume/turnover is zero.
Leading and post-terminal prices remain missing. The same stage freezes each
asset's last positive close before any model is run. M0 records but does not
consume that calendar downstream; M1/M2 use it for economic settlement.

Within P0, M2 retains M0's b02 volume cleaning: an all-zero/missing row is
missing, volume <= 1e-6 (including zero) becomes NaN, and the subsequent
zero-volume/nonzero-return condition remains in its original order. P1/M0
and P1/M2 preserve explicit zeros and screen only small positive volume.
Zero versus missing affects volume indicators and estimation support; this
is a P convention, not an additional M2 future-data correction. Thus a P
contrast measures filling and its associated downstream volume policy jointly.

The availability convention is common to M1 and M2. Full-history cessation
of quotes supplies a frozen mechanical-exit proxy. This is an assumption, not
observed advance notice; freezing does not make retrospective information
contemporaneously available. A held position is sold at the
frozen last tradable close and the proceeds are immediately allocated only to
surviving members of the same leg. EW uses equal recipient shares; VW uses
event-day market capitalization. Cash retention, cross-leg transfer, later
prices, return magnitudes, and relisting values are forbidden.

## 2. M0: published-code method

M0 preserves the downstream scientific method expressed by the original
Dataverse code, conditional on the declared P input convention and D universe.
Allowed differences are limited to:

1. case-sensitive path and headless publication adapters;
2. dependencies explicitly called but absent from the archive;
3. syntax, spelling, undefined-variable, and dimension repairs needed to
   execute the computation already expressed by the source;
4. deterministic process safety, provenance, and release wrappers;
5. b02 asset-chunk scheduling proven bitwise equal for all 59 saved fields;
6. b09 sharding that partitions the unchanged 1–3,072 loop into mutually
   exclusive global ranges and merges without changing payloads;
7. in P1 only, the common OHLC previous-close and volume/turnover-zero input rule; and
8. publication of the frozen mechanical-exit calendar for provenance, without
   consuming it in M0's downstream portfolio calculations.

Beyond that declared input convention, M0 does not repair known economic,
statistical, timing, or paper-alignment problems.
`test_method_boundary_contract.py` requires the exact 18-file P1 M0 delta
against Dataverse and rejects undeclared changes. P0 M0 has a separately
verified unfilled source identity.

## 3. M1: fully audited method

M1 applies the paper-first correction standard. When the paper is explicit,
the paper controls. When it is silent, the published implementation is kept
unless it has a demonstrable look-ahead, economic-accounting, statistical,
numerical-identification, or engineering error.

Core M1 boundaries include:

- raw close/volume are preserved before synchronization; statistical labels
  and raw positive-close endpoint economic P&L are separate layers;
- outlier rules are fitted only on realized historical training labels and
  never transform OOS portfolio payoff;
- model-estimation support and predictor ranks do not depend on the realized
  t+1 outcome; declared target unavailability may be used later when the
  executable portfolio is allocated;
- each predictor is ranked and estimated on its own formation-time support;
- validation selection requires the complete component-forecast vector,
  freezes the selected set, and keeps the `1/J_selected` average;
- any selected component forecast missing at OOS fails closed; a completely
  unavailable target is removed before breakpoints and survivors are
  reweighted; a frozen terminal holding is sold at its last tradable close and
  immediately reinvested within the same leg, with no cash or cross-leg state;
- Table 3 uses lagged weekly-average market cap, percent IVOL, and endpoint
  P&L; Table 4 deliberately remains a statistical-label regression;
- Table 7 uses exactly the prior 52 calendar positions with local listwise
  deletion and full-rank fail-closed estimation;
- Figure 3 passes each model's factor returns, not its test-asset returns,
  to GRS; joint tests use a common finite-date sample and remove only exact
  duplicate test-asset series before forming the system covariance;
- Table 9 separates full-L1 cost bases, paper half-L1 displays, two-leg H-L
  costs, initial builds, within-week forced sales, gaps, and episodes;
- Table B.10 preserves the Dataverse block phase and uses fixed
  nonoverlapping cohorts, fixed members, buy-and-hold drift, and the same
  no-cash reinvestment ledger;
- Figure C uses the same predictor-own support, beta, and selected set as the
  corrected CTREND estimator.

The annotation index exposes M1 as two exact steps: Dataverse→same-D M0 and
same-D M0→M1. Every M1 delta beyond M0, including complete file deletion, is
indexed in `annotated_sources/ANNOTATION_INDEX.csv`.

## 4. M2: bounded future-data ablation

M2 is defined directly relative to M0, not as an arbitrary subset of M1 files.
Its scientific delta is exactly 33 files and is restricted by an executable
allowlist.

### 4.1 Included changes

1. **Weekly endpoint and settlement.** In P1, the common preprocessing stage
   fills interior OHLC gaps from the prior close; P0 does not apply this fill. A scheduled endpoint
   cannot search the remainder of the calendar year. If a holding reaches its
   pre-model frozen terminal date, it is sold there and immediately reinvested
   within the same leg; cash is never an end state.
2. **No target self-cleaning.** M2 freezes an untransformed M0-synchronized
   weekly return layer before M0's contemporaneous outlier path. Each realized
   historical week is cleaned on its own formation-screened cross-section,
   before predictor support. The current OOS target is not cleaned, and raw
   portfolio payoff is untouched.
3. **Ex-ante model support.** Realized t+1 outcome support cannot determine
   model-training rows or predictor ranks. After a forecast exists, binary
   target unavailability is treated as announcement-equivalent at executable
   portfolio allocation.
4. **Formation-date screens.** Price and market-cap screens use lagged
   formation values rather than payoff-period values.
5. **Declared target availability.** A completely unavailable target is
   removed before portfolio breakpoints and EW/VW weights are renormalized
   over tradable survivors. A frozen terminal holding earns its last-trade
   payoff, and proceeds are reallocated only within the same leg. Return
   magnitude never defines this availability mask.
6. **No payoff-conditioned reporting start.** Table 5 and Table 6 sample
   boundaries begin at formation-time forecast support, not at the first week
   with complete realized portfolio payoff.
7. **No current-target payoff in GKX drift.** Turnover required to enter target
   t uses the preceding holdings' already-realized payoff. A missing prior
   selected payoff makes the next transition unobservable.

### 4.2 Explicitly excluded changes

M2 retains M0's model families, hyperparameters, validation fraction,
selection and averaging rules, joint all-predictor support, indicator/EMA
definitions, market proxy, synchronized-price return convention, inference,
and table definitions except where removing future conditioning is logically
unavoidable. In particular, M2 does **not** import:

- M1 unsynchronized raw-positive-close price panel;
- predictor-union / predictor-own-support Eq. (7) estimation;
- M1 complete-vector/fixed-selected-set forecast combination rules;
- strict past-52-calendar Table 7 rewrite;
- Table 9 episode/full accounting rewrite;
- M1 buy-and-hold Table B.10 rewrite (M2 retains M0's block phase and
  repeated formation-weight design, but uses the common no-cash terminal
  reinvestment ledger);
- predictor-own-support Figure C importance;
- M1's corrected Figure 3 GRS factor input and joint-system sample rules;
  M2 retains the published b11 GRS call because it is not a look-ahead repair.

Table 4 remains a retrospective M0 statistical-label regression. Only its
eligibility screen is moved to formation time. Table 5's local M0 return layer
is retained for its state definitions; only its start boundary changes.

The untransformed M2 economic payoff is an endpoint ratio built from M0's
synchronized close, not from M1's unsynchronized raw-positive-close panel.
This distinction is essential to interpreting `M2-M0` as the bounded
future-data/settlement ablation with a distinct retained statistical convention.

### 4.3 Exact M0→M2 source allowlist

```text
Utils/fApplySameLegReinvestment.m
Utils/fAttachEconomicLedgerOptions.m
Utils/fBreakevenTCFromCosts.m
Utils/fBuildWeeklyEndpointPnl.m
Utils/fBuildWeeklyReinvestmentLedger.m
Utils/fCleanWeeklyLabelsM2.m
Utils/fCreatePanelExAnteM2.m
Utils/fDemeanWeeklyM2.m
Utils/fDepDoubleSort.m
Utils/fFilterM2EstimationSupport.m
Utils/fIndepDoubleSort.m
Utils/fLoadEconomicReinvestmentLedger.m
Utils/fResampleLiuEtAl.m
Utils/fSingleSortFast.m
Utils/fSingleSortMulti.m
Utils/fWalkforwardCENET.m
Utils/fWalkforwardCSENET.m
Utils/fWalkforwardFamaMacBethPanel.m
Utils/fWalkforwardPanelRegression.m
b02CalculateIndicators.m
b04Table2_TechnicalIndicatorStrategyReturns.m
b05CreateCTREND.m
b06Table3_UnivariatePortfolioSorts.m
b07Table4_CrossSectionalRegressions.m
b08Table5_PerformanceInSubperiodsAndDifferentMarketStates.m
b09RunResearchDesigns.m
b10Table6_FactorPerformanceAcrossResearchDesignChoices.m
b13Table8_TheCTRENDFactorPerformanceInBigAndLiquidCryptos.m
b14Table9_CTRENDPortfoliosAndTransactionCosts.m
b15TableB3_BivariatePortfolioSorts.m
b16TableB4_CTRENDPerformanceDependingOnCryptocurrencyType.m
b17TableB10_ExtendedPortfolioHoldingPeriod.m
b18FigureC3_C4_AverageVariableImportance.m
```

`test_m2_derivation_scope.sh` verifies the frozen-parent inventory and enforces
this M0-to-M2 allowlist. `test_m2_consumer_matrix.py` independently checks the return-layer,
screen, panel, reporting-boundary, sort, and forbidden-M1 contracts.

### 4.4 NaN versus Inf clarification

In P1, after raw-input preprocessing has converted non-finite raw OHLC to
missing and non-finite or negative raw volume/turnover to zero, M0 still
defines missing *derived model-panel* observations by `isnan`, not by
`isfinite`. M2 must not broaden that downstream convention because doing so
would be an unrelated model/outlier change. `fCreatePanelExAnteM2.m` contains
an inherited-review comment saying every M0 predictor must be “finite”; for
the frozen downstream engine this word means “not NaN under M0's convention,”
not mathematically finite. The executable condition is
`any(isnan(mX),2)`, and deterministic tests require a derived ±Inf value to
remain in the model panel/payoff. This does not override the separate common
raw-price/raw-volume sanitation rule in Section 1.

## 5. Data axis

All cells consume the same immutable vendor snapshot and perform no manual
price/volume event adjustment.

- **D0:** original CMC panels; all assets retained.
- **D1:** D0 with CMCID 3787 / INNBCL removed for its entire history.
- **D2:** D1 plus 27 frozen same-CMCID event assets removed for their entire
  histories.

Deletion happens synchronously across close, open, high, low, volume, market
cap, and metadata after raw hashes/axes are checked and before sanitation,
synchronization, feature construction, training, or portfolio formation.

The 27-event set contains 18 confirmed fixed-unit events and nine confirmed
events whose exchange-aggregated field boundary is not safely reversible.
These assets are excluded because exchange feeds can switch identity/unit at
different times; a single global multiply/divide rule can create false OHLC,
volume, or market-cap histories. D2 is therefore a conservative retrospective
sensitivity, not a claim that event assets have zero economic returns.

NPXS (2603) and PUNDIX (9040) are separate CMCIDs and are not spliced or
excluded merely because of the project migration. YAM (6539) is a non-fixed
elastic-supply rebase, so a fixed integer correction is not defined and it is
retained. Exact IDs, event classes, and reasons are in
`config/event_asset_registry_v20260811.csv`; exact deletion lists are in
`config/exclusions/`.

## 6. Core variable layers

- `rData.mReturns`, `rData.mRetLead`: M0 synchronized statistical labels.
- `rData.mReturnsM2Raw`, `rData.mRetLeadM2Raw`: untransformed
  M0-synchronized returns used as M2 model labels.
- `rData.mPnlReturnsM2`, `rData.mPnlRetLeadM2`: M2 economic endpoint P&L
  built from the synchronized close; terminal events are supplied by the
  separately authenticated same-leg reinvestment ledger.
- `rData.mPnlReturns`, `rData.mPnlRetLead`: M1 raw positive-close endpoint
  economic P&L, paired with the same authenticated terminal-event ledger.
- `rData.vMktRet`: statistical characteristic proxy.
- M1's strict economic market return is a separate P&L series.

No method may silently substitute one layer for another.

## 7. Paper-output mapping

| Producer | Paper items |
|---|---|
| b03 | Table 1 |
| b04 | Table 2, B.5, B.8 |
| b05–b06 | Figure 1, Table 3, B.2, Figure B.2 |
| b07–b08 | Tables 4–5 |
| b09–b10 | Table 6, Figure 2, B.6, Figure B.1 |
| b11 | Figure 3, Table B.9 |
| b12–b14 | Tables 7–9 |
| b15–b17 | Tables B.3, B.4, B.10 |
| b18 | Figures C.3–C.4 |

The machine-readable required output patterns are in
`config/output_registry.csv`.
