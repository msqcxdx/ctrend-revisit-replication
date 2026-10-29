# CTREND corrected pipeline v2 validation record

> Historical record only. This file documents the July 2026 run and its
> then-current input/payoff convention. The isolated 24-August-2026 new-v2
> 3 x 3 source instead applies common OHLC/volume preprocessing and uses a
> frozen terminal calendar with immediate same-leg reinvestment in M1/M2.
> Counts, checks, and result claims below are not acceptance evidence for the
> new source; `docs/METHOD_BOUNDARIES.md` is normative.

Validation date: 2026-07-25 UTC

## Isolation

- Scientific source is confined to `corrected_code_v2`; operational scripts
  are confined to `b09_parallel_runner_v2`.
- The current `corrected_code` tree was not edited. It has no regular file
  with a 2026-07-24 modification time.
- v2 has one deliberate bootstrap symlink:
  `DATA -> ../corrected_code/DATA`. It reads the existing canonical raw-input
  source only. The full v2 runner snapshots those raw inputs into a new
  run-local staging tree and rebuilds all derived DATA and Results.
- v2 has its own regular `DesignChoices.mat`. It has no Results or canonical
  pointer before the first v2 launch.
- The runtime package excludes DATA, Results, logs, the audit cache,
  external-source responses, MATLAB preferences and prior packages.

## Raw-event coverage and correction validation

- Raw inventories contain all 12,146 adjacent-day and 5,173 fixed-week
  extreme events across 2,833 assets.
- Every event asset was searched externally; 1,645 exact
  name-plus-symbol matches have SHA-bound CoinLore histories.
- Every event has a row-level v2 disposition. Unresolved and corroborated
  events remain unchanged.
- The independently produced CMC decision package verified all 17 internal
  hashes and reproduced all 2,600 candidate CMC observations: 2,570 fresh
  daily matches plus 30 intraday reaggregations. Its input SHA256 is
  `8ec3aaa6585484a26b74fa0d2d09a2e95e584a1e13d902d7ca76a691dd72f262`.
  It did not supply a second independent historical source or a verified
  exchange candle, so it establishes no production CMC error.
- Real raw-data validation retained the 579 relevant asset columns and
  verified seven same-CMCID historical unit rules, ten exact market-cap
  cells and zero newly missing price dates. All 2,600 disputed closes remain
  finite and exactly unchanged.
- The observed changed-close mask equals the seven registered unit-history
  masks exactly. No unregistered close, volume cell, asset column or asset
  order changed. NPXS (2603) and PUNDIX (9040) remain unchanged independent
  columns despite the documented project swap.

## Executable checks

- MATLAB R2023b Code Analyzer processed all 131 production/test/runner MATLAB
  files. It reported no parse or syntax diagnostic. The 147 messages are lint or
  performance classes (`AGROW`, `ASGLU`, `ASGSL`, `BDSCI`, `DATST`, `INUSA`,
  `INUSD`, `ISCLSTR`, `MSNU`, `NASGU`, `NOSEMI`, `PFBNS`, `PREALL`, `PROPLC`,
  `SEPEX`, `ST2NM`, and `UNRCH`).
- All 26 corrected/v2 deterministic MATLAB unit tests passed under the
  requested R2023b online-license binary:
  `CORRECTED_UNIT_TESTS_OK count=26`.
- `tests/test_v2_raw_data_corrections.m` independently checks every manual
  scale/cap rule, transition OHLC validity, unchanged volume, preservation
  of disputed bitCNY and unrelated 1,000-fold returns, and non-splicing of
  different CMCIDs.
- The real-data registry validation passed with:
  `assets=579 price_rules=7 cap_cells=10 missing_price_dates=0
  external_dates=0 external_extreme_prices_preserved=2600
  assets_removed=0`.
- `tests/test_v2_static_guards.sh` passed, every v2 shell entry passed
  `bash -n`, and the runner process-group/fault-control suite passed after
  testing invalid worker counts, ownership, stale/no-progress handling and
  cleanup.
- The production runner now executes two real-result invariants after the
  complete b09 merge and before Table 6/publication: exact b05 versus
  field-matched b09 baseline equality, and Figure B.2 resumption on identical
  common support after an internal gap.
- After b10, a second result invariant verifies all 6,144
  design-by-breakpoint cells, six baseline methods, 15 method pairs, 55,296
  applicable paper method-cells, strict common-week/coverage table dimensions,
  support ordering, balanced-cell masks and common provenance. Every strict
  Table 6 CSV/MAT payload is also a required publication output.
- The causal manifest and both complete disposition CSVs were regenerated
  from cached raw evidence and reproduced byte-for-byte.

## Scientific consumer checks

- Raw vendor bytes are validated/hashed before the correction layer.
- Same-CMCID unit corrections occur before corrected positive closes are
  captured, before core synchronization, and before any return, weekly
  aggregation, characteristic or technical indicator. Economic endpoint
  P&L therefore uses corrected raw units. Extreme returns and one-source
  disagreements remain observed; only a vendor-missing endpoint is `NaN`.
- No correction consumes CTREND holdings, predictor ranks, selection,
  portfolio payoff, or a future observation.
- Each historical training/validation week fits its 1--99% label-cleaning
  cutoffs on that historical week's own formation-eligible cross-section.
  The target OOS label and endpoint payoff are not transformed.
- Figure 1 tick positions and labels use the same explicit vector and include
  zero. Figure B.2 keeps each gap missing and restarts every later contiguous
  cumulative-return episode without carrying a level across the gap.
- Table 6 retains 55,296 paper available-case cells and separately computes
  own-week, pairwise common-week, all-method common-week and balanced-cell
  diagnostics from saved weekly returns without imputation.

## Publication controls

- The scientific MATLAB fingerprint covers executable `.m` sources only.
- Top-level, launch, shard and fault-test source inventories likewise cover
  executable MATLAB sources; the rejected external-disagreement list stays
  under `audit/output` and is absent from the runtime package.
- The v2 package uses the established single
  `ctrend_corrected_pipeline/` archive root and excludes audit evidence.
- Package preflight verifies archive stability, executable MATLAB
  availability, absence of DATA/Results, required v2 files and exact
  source/runtime inventory equality without creating a run or starting
  MATLAB.
- The final archive layout check found one package root, the required
  `DesignChoices.mat`, and no DATA, Results, log, audit directory or CSV.
  The top-level preflight completed with `RUNNER_PACKAGE_PREFLIGHT_OK`.
- The full runner defaults to `CORE_START_STEP=setup`, creates a new
  `corrected_v2_*` run root, snapshots raw inputs, writes only run-local
  derived staging and uses independent process groups and phase PID files.
- The b09 compute profile is four MATLAB clients with 31 process workers
  each: 124 workers plus four clients on the 128-core host.

The deterministic checks establish high confidence in the specified code
and data invariants. They do not assert that any nontrivial empirical
pipeline can be proven literally error-free before execution. Publication
still fails closed unless every phase, all 3,072 b09 payloads, supplementary
variants, inventories, `RUN_COMPLETE` and canonical activation checks pass.

## Post-run publication-wiring maintenance (2026-07-28 UTC)

The sealed v2 result remains bound to its immutable run-time package and was
not recomputed. After final acceptance, the future-run source and runner were
minimally updated so that:

- supplementary and final publication gates require the explicit
  paper-method-specific Table 6 names rather than obsolete generic aliases;
- the value-weighted Table 6 Panel B and Panel D captions generate
  variant-specific filenames and cannot overwrite the main variants;
- deterministic static guards assert the named main/VW contracts.

Both modified shell entries pass `bash -n`, and
`tests/test_v2_static_guards.sh` returns `V2_STATIC_GUARDS_OK`. This is an
engineering/publication fix only; it changes no estimator, sample, return,
portfolio, table value, or sealed result file. The maintenance package has a
new SHA and must not be presented as the package that produced the sealed
research run. A post-maintenance MATLAB Code Analyzer attempt did not run
because MathWorks online licensing returned error 5201; no pipeline was
started. The sealed run's earlier full analyzer, 26 tests and result-level
acceptance remain unchanged, while the maintenance branch separately passed
shell syntax, static guards, runner fault-control tests and package/source
preflight.

## Presentation amendment (2026-07-28 UTC)

Two confirmed display defects were fixed without changing scientific
payloads:

- Figure 1C leaves the scientific factor matrix unchanged at 326 finite and
  97 missing common-support weeks in 14 episodes. Its disclosed display copy
  leaves the first 61 rows undefined and sets the 36 later internal gaps to
  0% increments, producing 362 continuous plotted points. The axis explicitly
  says `Cumulative Return (%; gaps = 0%)`; this display copy is never used by
  a table, estimator, Sharpe calculation or portfolio.
- Figures C.3/C.4 now escape each predictor-name underscore exactly once, so
  `macd_diff_signal` and `volmacd_diff_signal` are not rendered as TeX
  subscripts.

All 26 MATLAB tests passed after the source edit. An isolated rendering copy
was hash-identical to the sealed runtime and wrote only to temporary staging.
The result-level presentation validator opened all three `.fig` files and
reported:

`V2_PRESENTATION_ACCEPTANCE_OK scientific_common=326
scientific_missing=97 display_initial_missing=61 display_zero_gap=36
display_finite=362 figure_c_diagnostics_exact=1`.

The amendment replaces only six presentation files (three `.fig`/`.png`
pairs). Figure-C importance, selection, dates, aliases, ranks and support
diagnostics are field-for-field identical to the sealed predecessor. No data
preprocessing, estimator, portfolio, table, b09 combination or supplementary
stage was rerun.

The largest negative Figure-1C step was independently attributed to the
finite 2020W16 CTREND observation, not to a gap: H-L was -548.9038%, its low
leg was +549.6828%, and its high leg was +0.7789%. CMCID 3787 (INNBCL) had
78.1469% of the low-leg formation weight and a +703.1398% raw endpoint
return, contributing -549.4817 percentage points to H-L. All 105 holdings
in each leg had an observed payoff. The CMC endpoint is reproduced by the
official-source audit but strongly disagrees with the sole independent
CoinLore history; no second independent or identity-verified exchange source
established a causal correction. It therefore remains finite under the
approved “do not remove an extreme solely because it is extreme” rule.
