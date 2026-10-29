# Direct tests of TREND's relative model advantage

This analysis compares **models**, not just CTREND's standalone Sharpe ratio.
It reads saved VW high-minus-low returns for M0, M2 and M1 and the same LTW
benchmark within each P/D cell. No baseline model is refitted and no accepted
production output or E01–E11 result is overwritten.

Read [RESULTS_CN.md](RESULTS_CN.md) for the findings and
[PROTOCOL_CN.md](PROTOCOL_CN.md) for the fixed specifications. The primary
specification is P0/D0 with the externally published LTW series; P1, D1/D2,
and the corresponding M1/E01 reconstructed LTW are sensitivities. A reconstructed
benchmark is held fixed across M0/M2/M1, not changed with each method.
The [validation record](VALIDATION.md) distinguishes numerical recomputation,
historical source identities and checked compatibility of portable adapters.

## Main findings

On the 337 jointly observed weeks of the primary specification, the weekly
maximum squared-Sharpe advantage of TREND over LTW is 0.05800 for M0, 0.02398
for M2, and −0.01850 for M1. The **direct** M0-to-M1 change is −0.07649,
with an 8-week paired-block 95% interval [−0.12228, −0.02762], two-sided
p = 0.0012, and Holm-adjusted p = 0.0036 across the three method contrasts.
Both adjacent contrasts are weaker after this multiplicity adjustment.
The total decline retains its sign and adjusted significance across the twelve
P/D/benchmark settings and the 4/8/12-week blocks; these are correlated
sensitivities, not independent replications.

This does **not** establish that every pricing conclusion fails. On a fixed
38-portfolio primary test panel, the change in relative mean squared alpha
from M0 to M1 is not significant (p = 0.8978). Rolling opportunity portfolios
show a large M0-to-M1 Sharpe decline but not a significant M0-to-M2 decline in
the primary specification. These are unconstrained factor opportunities, not
levered trading-account profits. M2 retains a positive model advantage under
the reconstructed LTW benchmark. No insignificant test is called equivalence.

## Estimands and inference

The input columns are CMKT, CSMB, CMOM, CTREND_M0, CTREND_M2 and CTREND_M1.
L uses the first three; T_m replaces CMOM by CTREND_m; A_m includes all four
factors for that method. Define S²(F) = μ′Σ⁻¹μ and D_m = S²(T_m) − S²(L).
Positive D favors TREND. Contrasts 02, 21 and 01 mean **after minus before**
along M0 → M2 → M1. They are paired tests, not comparisons of two separate
significance labels. S² is weekly and uses covariance divisor N throughout.

All competing models share the six-column finite mask. The full 423-position
source calendar is retained during resampling; absent returns are not zero-filled
and holes are not compressed into adjacent weeks. Week labels use the original
study's within-calendar-year grouping, not ISO weeks. Neither the 337-week
intersection nor the number of valid pricing/OOS observations is imposed in code.

Circular moving-block resampling uses 5,000 draws at each of 8 (primary), 4 and
12 weeks, with seed 20261029 plus documented setting/block offsets. Each draw
re-estimates means, covariances, alphas, model advantages and their differences.
Intervals are percentile intervals; two-sided p values use the centered
bootstrap distribution with the add-one correction. They are not exact inverses
of one another. HAC(4) influence-function results and three-contrast Holm
adjustments are reported separately. No adjustment across all sensitivity
settings is claimed. The inference assumes suitable dependence, moments and
approximate stationarity; extreme observations can make intervals asymmetric.

A HAC joint-alpha test checks the shared-factor spanning boundary before
regular model-difference inference. Failure to reject spanning is marked
unresolved, not equality. Numerical singularity, excessive conditioning or a
degenerate influence function is not repaired by pseudoinverse, ridge or zeros.
Unresolved cases retain descriptive bootstrap ranges but no inferential p/CI.
See [Barillas, Kan, Robotti and Shanken](https://www.cesarerobotti.com/wp-content/uploads/2019/04/BKRS-JFQA.pdf)
for the overlapping-model/spanning issue. The diagnostic does not guarantee
exact finite-sample size.

The fixed-asset primary panel uses the same M1/HedgePorts returns in all models;
the M0/HedgePorts panel is a full sensitivity. The 39 candidate characteristics
and technical indicators are fixed before inspecting significance. Only exact
duplicate series, including their missing masks, are removed and mapped.
All retained assets and all factors share one evaluation mask. Mean squared
alpha (MSA, percentage points squared) is primary; mean absolute alpha (MAE,
percentage points) is exploratory because of nonsmoothness near zero. Pricing
error contrasts are TREND minus LTW: **negative** means improvement, the reverse
of D's direction. GRS uses the actual factor returns and a nominal iid-normal
F reference; its p values are not a direct model-ranking test.

Rolling opportunities use the previous 52 calendar positions, shared complete
training observations, and positive scaling of Σ⁻¹μ to 10% weekly volatility.
There is no normalization by a possibly negative sum of exposures. The common
evaluation start is 52 calendar positions after the latest declared model-grid
start. At least 5 complete training observations matches the E03 convention;
at least 26 is the prespecified sensitivity. Reported OOS Sharpe uses sample
SD (N−1) and √52 annualization. Its bootstrap conditions on the saved estimated
rolling strategy; it does not re-estimate that strategy or CTREND inside each
draw. Borrowing, leverage limits, margin, costs and execution are outside scope.

## Commands and data boundary

From the repository root, with Python 3.10+, NumPy and SciPy installed:

```bash
python3 followup_research/model_advantage_direct/test_analysis.py
python3 followup_research/model_advantage_direct/verify_results.py
```

The first command is a synthetic economic/statistical regression suite. The
second checks saved summary identities and receipts using only the standard
library. Neither needs CMC data or MATLAB. These checks are not full production
re-estimation.

For an authorized analyst with the accepted result archives, existing E01
factor exports, E03/E04 reference tables and a local run index:

```bash
python3 followup_research/model_advantage_direct/prepare_inputs.py \
  --repository-root "$PWD" \
  --run-index /absolute/local/accepted_run_paths.csv \
  --output /absolute/fresh/model_advantage_inputs

python3 followup_research/model_advantage_direct/run_analysis.py \
  --input-dir /absolute/fresh/model_advantage_inputs \
  --output-dir /absolute/fresh/model_advantage_results \
  --replicates 5000 --workers 12

python3 followup_research/model_advantage_direct/verify_results.py \
  --results /absolute/fresh/model_advantage_results
```

The run index must provide `experiment_id`, `accepted_run_root`, `result_root`,
`research_run_id`, and `run_complete_sha256` for all 18 cells. The adapter checks
their saved `CTREND_Base.mat` VW H−L against the method return panel, reads the
two fixed `HedgePorts.mat` panels, and preserves the declared model dates.
It independently reconciles E03 and E04 before creating six NPZ inputs and
`INPUT_RECEIPT.json`. Existing destinations are never overwritten. See the
adapter's explicit file/field selections for the complete input contract.

The public repository deliberately does **not** include these NPZ files, the
local index or the restricted derived factor/test-portfolio input panels.
Full numeric recomputation needs those separately authorized materials, not
just a public clone. Public summaries and synthetic checks are self-contained.
Twelve worker processes handle independent settings with single-threaded BLAS;
this is a lightweight analysis of saved inputs, not eighteen MATLAB jobs.

To verify deterministic recomputation, rerun to a different fresh output
directory using the same inputs/seed, then pass `--compare /second/output`
to `verify_results.py`. All result CSVs must be identical in the same recorded
environment; receipt timestamps are allowed to differ. Floating-point library
differences across platforms need not give byte-identical results.

## Output map

| File in `results/` | Content |
|---|---|
| `advantage_levels.csv` | S²(L), S²(T_m), D_m, intervals and spanning status |
| `advantage_changes.csv` | Three direct Δ contrasts, intervals, bootstrap/HAC/Holm p values |
| `incremental_decomposition.csv` | V_CT, V_MOM, CT/MOM conditional alpha and residual risk; identity errors |
| `pricing_fixed_assets.csv` | Four models' MSA/MAE and auxiliary GRS for each fixed panel |
| `pricing_changes.csv` | Relative pricing errors and their method changes; `maa` denotes MAE |
| `pricing_asset_audit.csv` | Prespecified candidate names and exact-duplicate aliases |
| `pricing_support_calendar.csv` | Dates and common pricing-support indicators, without asset returns |
| `oos_comparison.csv`, `oos_changes.csv` | Common OOS mean, Sharpe, relative advantages and changes |
| `oos_training_audit.csv` | Prior training window, observation count, failures, exposure/direction diagnostics |
| `support_calendar.csv` | Six input-finiteness flags and main support, without factor values |
| `legacy_reconciliation.csv` | Existing E03 definitions independently reconstructed, not spliced into new cells |
| `e04_reconciliation.csv` | E04 pairwise single-factor moments independently reconstructed |
| `numerical_diagnostics.csv` | Invalid draws and algebraic decomposition checks |
| `RUN_RECEIPT.json` | Parent run IDs, input/script/output hashes, versions, seed and scope |

Metadata `n_common/first_week/last_week` always describes the main factor
intersection. Pricing uses `n_pricing` and its own calendar; rolling analyses
use `n_oos` and the `ok` entries of their training audit. `bootstrap_invalid`
is explicitly counted; inferential output requires at least 99% valid draws.
`descriptive_*` fields are not proofs against a null hypothesis, especially for
nonnegative increments and unresolved spanning.

E03's M1 four-column support and N−1 rolling covariance are reconstructed
separately before using this study's common six-column support and N convention.
E04's standalone returns are checked on its pairwise support. Table 7 shares
the positive tangency-direction convention but estimates a rolling
frontier-expansion regression, not this full-sample S² contrast. Different
estimands should not have their cells equated. All accepted baselines and
existing follow-up outputs remain unchanged.
