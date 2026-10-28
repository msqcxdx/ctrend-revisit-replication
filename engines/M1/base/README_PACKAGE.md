# CTREND Corrected Pipeline v2

This directory contains the single corrected replication pipeline. A working
checkout may have local `DATA/` and `Results/` links, but the release archive
does not include either directory. Any result copied from another checkout is
valid only when its source fingerprint, data-build ID, and required run ID
match the current pipeline; filenames alone are never treated as provenance.
The v2-specific estimand and Table 6 output contract are summarized in
`V2_METHOD_SPECIFICATION.md`; the two influential endpoint events are
documented in `EVENT_RETURN_AUDIT.md`. The isolated-copy boundary is recorded
in `V2_FORK_PROVENANCE.txt`.

## Authoritative conventions

- b02 keeps raw returns. Each already-realized historical training or
  validation week is cleaned using the two quantiles of that week's own
  formation-eligible return cross-section. A target OOS week is never used
  to fit or apply its own cutoff. Economic portfolio P&L always uses raw
  endpoint returns and is never capped/deleted by label preprocessing.
- `CTREND_Base.mat` therefore stores two explicitly different OOS outcomes.
  `mRetLabelOOS` is the raw strict core-return statistical label and is used
  by Table 4; `mRetPnlOOS` is the raw positive-close endpoint economic
  return and is used by every portfolio, factor-return, turnover,
  transaction-cost, and holding-period calculation. Table 4 therefore
  remains a statistical-label regression and is not silently converted to
  an endpoint-P&L regression.
- Validation variants reserve exactly the most recent 12 calendar weeks of
  each in-sample window. They do not use a fractional split and do not re-fit
  the forecasting model after validation selection. Every walk-forward API
  requires an explicit complete calendar axis and fails closed if it is
  omitted.
- Table 6 outlier keys share the same raw weekly inputs. They differ only in
  the historical weekly label transform inside each estimator/window. The
  fixed 12-week validation block is already historical and each of its weeks
  uses its own formation-universe cutoff. The paper's
  `Data Set / Outlier treatment` display label is retained for row-by-row
  comparability, but in the corrected pipeline it means estimator-outcome
  preprocessing, not ex-post cleaning of the data set or realized payoff.
  Consequently, benchmark CSMB/CMOM payoffs are invariant to this label choice
  and remain displayed rather than being reported as N/A.
- The paper Table 6 is retained and explicitly labelled method-specific
  available-case. Parallel outputs use the six baseline estimators, one
  equal-weight/no-validation estimator definition per balanced design cell,
  and report exact own-week, pairwise-common, and all-method-common Sharpe
  ratios, support dates/counts, Jaccard overlap, and b09 coverage status.
  Missing weeks are never filled with zero. Pairwise/all-method distribution
  summaries also require the same compared methods to have defined Sharpes
  and to have both at least 50% common/scheduled-week availability and at
  least 50% common/union-week overlap in the same design cell. Both
  denominators are reported separately. Each method cannot silently choose
  its own successful cells.
- All Table 6 predictive regressions use market-cap WLS. The `vUseValueWts`
  switch changes only EW versus VW factor-portfolio accounting, so otherwise
  identical design twins use the same predictions.
- CFM and CPOLS implement equation (9) with a fixed `1/J` over the complete
  prespecified component set. Equal-weighted CS-C-ENet and C-ENet use a fixed
  `1/J_selected` over the window's selected set. If any required component is
  unavailable for an asset-week, the combination is undefined; missing
  components never trigger a time-varying `1/J_t` reweighting.
- Elastic-net keeps the paper's `alpha=0.5`. AICc counts MATLAB's nonzero-
  predictor `FitInfo.DF` plus the fitted intercept and admits only finite,
  strictly positive MSE with `n-k-1>0`; zero/NaN/Inf MSE and nonfinite AICc
  candidates cannot be selected.
- Assets with internal history gaps stay in the asset universe. Missing
  asset-date cells remain `NaN`; a missing realized return for any selected
  holding makes that portfolio leg's return `NaN`. It is never replaced by
  zero, and the other holdings are never reweighted after observing returns.
- A missing Bitcoin market-cap quote does not delete other assets on that
  date. Core gaps one-way mask auxiliary OHLC cells, momentum requires a
  complete price chain between its endpoints, and sparse assets with any
  usable core history remain in the panel.
- There is one corrected convention only. The pipeline does not produce a
  competing clean-P&L, missing-as-zero, post-return-reweighted, or correction-
  ablation result. The paper's own Table 6 design grid remains because it is a
  published-paper output, but every grid point obeys the same correctness
  constraints.
- OLS coefficients use common finite observations, while every Newey-West
  lag remains measured on the original weekly calendar. Missing weeks are
  never deleted before HAC score pairs are formed.
- Extended H-week portfolios apply price/market-cap/stablecoin eligibility
  only at block formation, then keep fixed members with buy-and-hold drift.
  Cumulative factor-return plots and drawdown statistics never bridge an
  internal gap.

## Required CMC input

The raw input must be an unscreened daily panel. It must retain stablecoins,
assets that never exceed a later portfolio market-cap threshold, and assets
with internal gaps. Stablecoin and market-cap choices are applied later using
formation-time information.

Place `screening_summary.json` beside the source `DATA/` directory (the code
also resolves per-file symlinks). The preferred certificate is:

```json
{
  "exclude_stablecoins": false,
  "min_marketcap": 0,
  "strict_contiguous": false
}
```

An exporter may instead retain a positive configured threshold if it proves
that `keep_all_assets=true`, input equals kept assets, and dropped assets are
zero; `b01` then verifies sub-threshold market-cap cells directly.
`MetaData.mat` must retain `vStableCoin` and at least one stablecoin. The
packaged input certificate reports 10,314 of 10,314 retained assets. See
`INPUT_DATA_REQUIREMENTS.md` for the complete contract.

## Running

After replacing the input, run every empirical output from this directory:

```bash
./run_full_pipeline_corrected.sh
```

The default `full` scope executes the main `b00`–`b18` path and then invokes
`run_supplementary_outputs.sh` for Figure B.1/Table B.6 and Table B.7. The
supplementary helper uses the paper's existing switches and restores the main
tables after saving independently named appendix outputs. Set
`PIPELINE_SCOPE=baseline` to omit Table 6, or `PIPELINE_SCOPE=table6` to run the
research-design grid from already certified weekly inputs. Every route uses
the normal estimation scripts; existing result files are not prediction
caches.

The input certificate and source fingerprint are stored in `b0DataOLHC.mat` and
propagated into weekly intermediates. Old intermediates, or intermediates made
before any corrected MATLAB source subsequently changed, are rejected.
`CTREND_Base.mat`, `HedgePorts.mat`, and every Table 6 combination are also
bound to their source-code fingerprint and data-build ID.

Optional environment variables:

- `PIPELINE_SCOPE`: `full` (default), `baseline`, or `table6`
- `CODE_DIR`, `MATLAB_BIN`, `PARALLEL_WORKERS`, `MATLAB_PREFDIR`
- `PIPELINE_START_STEP`, `PIPELINE_END_STEP`: resume only within the same
  certified data build and unchanged source tree
- `PIPELINE_COMBO_START`, `PIPELINE_COMBO_END`: explicitly choose a `b09` chunk;
  every combination in the range is recomputed
- `PIPELINE_RESEARCH_RUN_ID`: required to be the same across all chunks of one
  research-design run

`b09` stores scheduled, independently eligible, estimated/finite, failed, and
unexpected-failure week counts plus per-week status codes for every
combination and method. The predeclared operational acceptance threshold is
50% coverage on eligible prediction, quintile-factor, and tertile-factor weeks
with zero unexpected failures. The floor accommodates structurally
unidentified/undefined early weeks in the paper's 26-week rolling designs,
but prevents one finite week from certifying a method that fails on most
eligible weeks. Toolbox, license, input, dimension,
and other unexpected exceptions are never covered by this tolerance. `b10`
refuses incomplete, mixed, stale, or materially failed
combination files by checking both the aggregate manifest and each combo,
along with full `DesignChoices`, code fingerprint, and data-build ID.

Every supported shell entry requires an explicitly supplied
`PARALLEL_WORKERS` value to be a positive integer. Invalid zero, negative,
fractional, non-finite, or textual values fail before MATLAB starts.

Table 6 intentionally retains the paper's method-specific finite-week sample.
`b10` therefore writes a companion LaTeX table of median method-specific
weekly `N` using the same row groupings, plus CSV/MAT files containing the
exact `N` for every design-method cell; Table B.6 receives corresponding
value-weighted-only files. Because `N` may differ, cross-method Table 6
differences are method-and-sample differences and must not be described as
pure method effects. The paper table is not replaced; a separately labelled
parallel common-week comparison audit is also written.

The top-level runner validates and exports `MATLAB_BIN`; supplementary child
processes print and reuse that exact executable. Penalized-regression toolbox,
license, input, dimension, and unknown numerical exceptions propagate instead
of being converted by a bare catch into silent all-NaN outputs. Only explicitly
named statistical non-identification cases return a non-estimated status.

## Verification status

Before the final empirical run, the executable MATLAB source passed the
MATLAB R2023b parser and the project’s synthetic checks for OOS, accounting,
calendar, provenance, AICc, fixed-set forecast combinations, and
parallel/serial invariance. The delivery includes deterministic tests; tests,
shell launch controls, and documentation do not enter the scientific MATLAB
fingerprint.

The certified predecessor rebuilt the provenance chain and all baseline,
3,072-combination Table 6, observation-count, and supplementary outputs. Its
scientific MATLAB fingerprint is
`dd3da08ac622b8350fc786e10d8a55a1694b0c28baa8e4d62e0b9d779312b62b`,
its data-build ID is `a49400ad-cb3a-4a56-8849-a5b68bf257e6`, and its research
design run ID is `e3432b7d-451a-4b74-bcda-30b2ccdba954`.

The original orchestrator rejected b10 after MATLAB returned success because
pool workers were still naturally draining. A validated recovery ran only the
previously missing explicit supplementary variants; no completed b00--b18 or
b09 combination was rerun. It proved all 6,196 pre-existing result files
unchanged before sealing `RUN_COMPLETE` and activating the canonical bundle.

Final acceptance subsequently found one active-consumer defect: b05 correctly
saved a hedge-only L/H/H-L matrix, but b08 consumed it as a complete five-
portfolio matrix and left Table 5 Q2--Q4 empty. The current canonical is the
sealed Table-5-only amendment
`corrected_20260723_084441_790149208_table5_amendment`, research run ID
`affcbe0c-dfd1-4d2c-97cb-42a95f8f1a98`, and MATLAB fingerprint
`9c58598625a7d1f8c59ed8ef6224059bad9c59f281cbfd3d2aa5b3d9e7d98f8f`.
Only b08 was executed. The other 6,208 results, including all 3,072 Table 6
payloads, are byte-identical inherited predecessor outputs; all 6,209 final
files passed the amended inventory. The required input remains the full
10,314-asset universe.

The local amendment gate is not a general cross-fingerprint resume mode. It
requires the weekly inputs and b05 result to match the exact authorized
predecessor fingerprint, data-build ID, dates, assets, and dimensions. Normal
clean runs retain the original strict current-fingerprint gate.
