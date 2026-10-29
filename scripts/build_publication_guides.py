#!/usr/bin/env python3
# CTREND_REVISIT_FILE_PURPOSE: Generate bilingual research READMEs and the experiment/result map from accepted eighteen-cell tables.
"""Documentation only; never changes engine source, raw inputs or saved arrays."""
from pathlib import Path
import csv
import sys

R=Path(__file__).resolve().parents[1]
sys.path.insert(0, str(R/'analysis'))
from publication_evidence import paper_baseline
from paper_factor_comparison import load_published_factor, return_statistics
def rows(p):return list(csv.DictReader((R/p).open()))
own=rows('results/comparisons/source_tables/exact_headline_from_mat.csv')
common={x['experiment']:x for x in rows('results/comparisons/source_tables/common_week/eighteen_experiment_all_common_summary.csv')}
paper_series, paper_provenance=load_published_factor(R)
paper_own=return_statistics(paper_series)
paper_all_common={x['series_id']:x for x in rows('results/comparisons/paper_factor/NINETEEN_WAY_ALL_COMMON_SUMMARY.csv')}
paper_pairs=rows('results/comparisons/paper_factor/NINETEEN_WAY_PAIRWISE_COMMON_SUMMARY.csv')
paper_m0=next(x for x in paper_pairs if x['first']=='Paper' and x['second']=='P0_M0_D0')
def result_table(cn=False):
    headings=['实验','自身周数','均值 %','均值 t','年化 Sharpe','共同周均值 %','共同周 Sharpe'] if cn else ['Experiment','Own weeks','Mean %','Mean t','Annual Sharpe','Common mean %','Common Sharpe']
    text='| '+' | '.join(headings)+' |\n|'+'|'.join(['---']+['---:']*(len(headings)-1))+'|\n'
    c=paper_all_common['Paper']
    text+=f"| Paper (published factor) | {paper_own['weeks']} | {paper_own['mean_weekly_pct']:.4f} | {paper_own['t']:.4f} | {paper_own['sharpe_annualized']:.4f} | {float(c['mean_weekly_pct']):.4f} | {float(c['sharpe_annualized']):.4f} |\n"
    for x in own:
        c=paper_all_common[x['experiment_id']]
        vals=[x['experiment_id'],x['finite_hl_weeks']]+[f'{float(x[k]):.4f}' for k in ['hl_mean_weekly_pct_exact','hl_t_exact','hl_sharpe_annualized_exact']]+[f'{float(c[k]):.4f}' for k in ['mean_weekly_pct','sharpe_annualized']]
        text+='| '+' | '.join(vals)+' |\n'
    return text

EN='''# CTREND revisit: preprocessing × method × data universe

[Chinese README](README_CN.md) · [Runbook](RUNBOOK.md) · [Full nineteen-way report (Chinese)](results/comparisons/NINETEEN_WAY_FULL_REPORT_CN.md)

Independent E01–E11 follow-up analyses, code, evidence boundaries, and verified
result tables are in [followup_research](followup_research/README_CN.md). The
larger detail tables have a split payload and a one-command restore step; these
analyses do not alter the eighteen accepted production runs. E12 is paused.

**Reproduction entry:** see the self-contained
[Chinese reproduction guide](REPRODUCTION_GUIDE_CN.md). After environment setup,
`./reproduce_everything.sh` runs all checks, eighteen sequential production
experiments, full acceptance, and **fresh registered-run** comparison reports.
It uses the installed sealed inputs; it does not launch live data acquisition.

CMC collection and MATLAB export are documented in
[cmc_acquisition](cmc_acquisition/README.md). The three non-CMC auxiliary inputs
are obtained separately; see their [sources, download methods and required formats](cmc_acquisition/README.md#non-cmc-auxiliary-inputs-outside-this-module).

## Motivation and principal findings

The reproducibility of a return-prediction result depends on information timing,
data construction, estimation support and portfolio accounting. An audit of the
published CTREND implementation identifies concerns in each of these areas.
Look-ahead is the most fundamental concern: information unavailable when a
position is formed cannot support an out-of-sample trading interpretation,
regardless of how large its effect on a reported return happens to be.
One particularly direct example is the following future-data access:
when a scheduled weekly value is missing, `fResampleLiuEtAl.m` can search the
entire calendar-year matrix, rather than the current week. A later observation
can therefore enter an earlier weekly characteristic. Its exact fallback is
`mDataTemp(find(~isnan(mDataTemp(:,idx)),1,'last'),idx)`. Other outcome-dependent
formation and cleaning rules complicate the interpretation of the published
strategy as an implementable out-of-sample investment rule.

The empirical question is therefore broader than whether a coding error exists:
which implementation choices materially affect the evidence, and through which
channels? This repository reproduces the published method and compares a bounded
timing/settlement correction with a broader audit. It contains **18 accepted experiments**, not
18 independent samples: two preprocessing conventions (P), three methods (M),
and three all-history asset universes (D). The paper's reported table values and
its published weekly factor series form the nineteenth comparator. Original author code is included separately
as an unmodified reference, not as the production entry point.

The ablation does **not** support the statement that correcting look-ahead alone
eliminates mean returns. M0 closely reproduces the paper's aggregate moments,
but not its exact weekly path. M2's weekly mean is
approximately 4.1–4.5%, but its volatility rises and annualized Sharpe falls
to approximately 1.45–1.55. M1's D0 mean is approximately 0.05%, with a Sharpe
near zero; excluding INNBCL restores about 2.66% per week, and excluding the
additional event-asset set leaves about 2.50–2.51%. Hence the important result
is an interaction between methodology, portfolio composition and data exposure,
not a monotone sequence in which every repair reduces returns. Statistical
significance, factor-adjusted alpha, costs and drawdowns must be read alongside
the raw mean. These are gross long–short factor returns, not guaranteed returns
of a fully collateralized, practically shortable account.

The evidence distinguishes a principled objection from its empirical magnitude.
Look-ahead remains an error even when correcting the specified channels does not
eliminate the mean return. Conversely, a large performance change does not by
itself identify a particular defect as its cause. Source-level contrasts,
common-week comparisons and portfolio diagnostics make that distinction explicit.

## Experiment design

An experiment is `P{0,1}_M{0,1,2}_D{0,1,2}`. The full machine-readable grid is
[experiments_pmd.csv](config/experiments_pmd.csv). Method contrasts follow
**M0 → M2 → M1**, not the numerical order of the labels.

### P: common missing-data preprocessing

**P0** does not apply the common filling layer. It does not mean
“no preprocessing”: original date alignment, market-cap screening, returns,
outlier rules and each characteristic's own missing-value behavior remain.
The unfilled M0 source is stored under `engines/P0_M0`;
P0 M1 disables the common b01 fill. P0 M2 also uses the b02 volume-cleaning
block of P0/M0; it is not a b01-only derivation.

Volume cleaning must also respect this distinction. In **P0, M2 retains
M0's b02 rules**: an all-zero/missing volume row is missing, and volume
`<= 1e-6`, including an explicit zero, becomes NaN. The subsequent
zero-volume/nonzero-return condition is retained in its original order; the
earlier threshold already removes zeros. In **P1, M0/M2 preserve explicit
zeros** from the common input convention and screen only small positive
volume (`0 < volume <= 1e-6`). Zero is a numerical observation; NaN denotes
unavailability. They need not produce the same volume indicators, estimation
support or portfolios. Preserving zeros is a declared P1 convention, not an
additional M2 timing repair. The P0/P1 M2 contrast therefore includes both
the b01 fill and its consistent downstream volume treatment; it does not
identify the effect of price filling alone.

**P1** applies a declared common data convention before the method-specific
pipeline. A missing/invalid OHLC field is replaced by the last valid close
strictly before that day; missing, infinite or negative volume/turnover is
zeroed. It does not use today's close to repair today's open. Leading prices
without an earlier close and prices after the mechanical terminal boundary
remain missing. OHLC/volume filling does not imply that market cap is forward
filled. Original screening and technical/characteristic calculations still run.

Previous-price filling is a common empirical convention, not a universally
correct economic repair: a repeated quote can create a zero return, and zero
volume need not mean a verified absence of trading. That is why P is a separately
reported sensitivity. Moreover, **P1 does not prevent later M0/M2 outlier rules
from creating new NaNs** in the synchronized price/feature history.

### M: published method, bounded look-ahead ablation and broader audit

| Issue / consequence | M0 | M2 | M1 |
|---|---|---|---|
| Calendar-year last-observation fallback can read a future date | Retained | Removed | Removed |
| Outcome availability/holding-period data can affect formation or sample start | Retained | Specified causal screens repaired, subject to exit-proxy assumption below | Repaired under the same assumption |
| Outlier fit/transform timing can use target information | Published path | Historical own-week cross-sections | Historical own-week label cross-sections |
| TRUNC/WIN masks also delete synchronized close/OHLCV/cap cells, affecting features | Retained | Retained | Label cleaning separated from raw economic/feature inputs |
| Predictors use joint complete support rather than own observed support | Retained | Retained | Own-formation support ranks and component-specific estimation support |
| Paper-alignment details of indicators, validation, forecast combination and Figure C | Retained | Retained except a specified future-data channel | Audited definitions with fixed selected set and `1/J_selected` |
| Table 3 cap/IVOL scale; Table 7 past-calendar window and singularity checks | Published definitions | Published definitions | Audited definitions |
| Published `delay` uses expanded-regression residual skewness as R² | Retained for reproduction | Retained for bounded ablation | Fifth output (actual R²); one-characteristic comparison also reports all 18 |
| Figure 3 GRS receives test-asset returns where factor returns are required | Retained | Retained (not look-ahead) | Actual model-factor returns on a common sample; exact duplicate test assets removed |
| Initial/gap accounting, turnover cost bases, fixed holding cohorts | Published definitions | Published except bounded causal/terminal changes | Explicit economic accounting and deterministic invariants |
| Runability, asset-chunk parallelism, 8×15 b09, headless output, hashes | Supported | Supported | Supported |

M0 is not an attempt to correct the author's economic or statistical design.
Engineering adaptations are allowed only without intentional scientific-number
changes; P and D remain explicit experimental modifications. P0 M0 D0 is the
closest reproduction of the unfilled original design. The paper and our vendor
snapshot are not guaranteed to have identical sample membership.

M2 is derived from M0, not by arbitrarily undoing selected M1 files. It preserves
the published feature formulas, joint support and most ancillary table accounting.
M2 is not a single-line or purely timing-only treatment:
it also implements the declared endpoint/terminal no-cash reinvestment
convention needed for the chosen formation rule. M0→M2 identifies this bundle,
not the isolated effect of one fallback statement.

TRUNC and WIN are distinct design alternatives. TRUNC makes an extreme return
label missing; WIN clips that label. In M0/M2 both also mask the synchronized
price history at hit cells. The retained cleaned daily labels still feed their
statistical characteristics/weekly calculations: equal price masks do not make
the two alternatives identical. In M1, cleaning a model label does not erase
the raw price used for a technical indicator or alter realized portfolio P&L.
Unclipped feature inputs are a declared audited construction, not a claim that
every raw observation is clean. The 3,072 designs do **not** constitute a separate
“winsorize the price path and rebuild X” robustness experiment.

M1/M2 use historical **own-week cross-sectional** outlier thresholds rather than
a threshold pooled across the full training window. Statistical-label regressions, notably
Table 4, are not silently converted into raw-P&L regressions.

### Terminal settlement and the information assumption

M1/M2 freeze a mechanical exit calendar from the available complete price
history. A terminal holding is settled at the prescribed last observed close,
then proceeds are immediately reinvested into surviving holdings of the same
leg; VW uses the applicable contemporaneous survivor market caps. It is not
retained as idle cash. Entirely unavailable targets are handled by the frozen
eligibility convention, not fabricated zero payoffs. Invalid reinvestment inputs
must fail closed. Internal missing observations and a truly terminal series
ending are separate cases.

There is **no announcement-time dataset**. A frozen retrospective calendar is
an explicit proxy/sensitivity assumption about advance tradability information;
freezing it before execution does not prove that the final date was knowable
historically. Therefore “strict real-time implementability proved solely from
the observed panel” is not an appropriate claim for these results.

### D: all-history universe exclusions, without unit-price repairs

- D0 keeps the original CMCID panel, including INNBCL. No split/merge adjustment.
- D1 removes CMCID 3787 / INNBCL at every date, before market aggregates, screens,
  ranks, model estimation and portfolio sorting. It is not a one-week deletion.
- D2 removes D1 plus the frozen 27 event-affected CMCIDs: 28 exclusions in total.
  See [D2.csv](config/exclusions/D2.csv) and the
  [event registry](config/event_asset_registry_v20260811.csv).

Different exchanges and fields can switch units on different dates. A CMC
aggregate can consequently contain mixed-unit candles and nonsynchronous price
and volume transitions. HYDRO and SHND illustrate why applying one integer
factor to a guessed boundary is not generally defensible. D2 avoids making
that repair: it is a deliberately broader whole-asset sensitivity, not a claim
that every excluded quote is wrong. Some registered events had stronger unit
evidence than others; both are retained in the published classification.

NPXS (2603) and PUNDIX (9040) are different CMCIDs: they are **not** spliced and
are **not** excluded merely because their project migrated. A 1:1 name/contract
change alone is not a mechanical unit event warranting D2 exclusion. YAM's
non-fixed elastic-supply rebase is also not treated as a constant-unit split.
LFG (11086), ROOM (8351), HANZO (9765) and DNotes/NOTE (184) are documented
1:1/non-scaling examples retained; see [event scope](docs/EVENT_EXCLUSION_SCOPE.md).
The registry is a documented frozen list, not a proof that all events in the
world have been found. Full retrospective event discovery is not rerun here.

## Nineteen-way principal-result comparison

Mean and volatility use weekly percent units; Sharpe is annualized with √52.
The displayed mean t is the ordinary sample-mean t, not a HAC alpha test.
Own-support and common-support statistics are distinct. The author-published
`Results/CTREND/CTREND.xlsx` in the unmodified Dataverse ZIP supplies 371 finite
H-L returns, 2015W16–2022W22. Their full-support mean, SD, ordinary t and
annualized Sharpe round to Table 3's 3.87%, 14.34%, 5.19 and 1.94. The table
below instead preserves recomputed precision and includes the actual factor in
the date-keyed **nineteen-way** common support. YYYYWW uses the author's
52-within-year-block calendar, not ISO weeks.

@@TABLE@@

All 19 share 337 finite H-L weeks, 2015W25–2022W22; adding the author leaves
the eighteen-experiment intersection unchanged in this snapshot. Own support is 349 weeks
for M0, 353 for M2 and 337 for M1 in these saved baselines. These are observed
counts, not hardcoded acceptance thresholds. The 423-position calendar includes
initial history requirements and internal non-formation weeks. A display-only
zero increment bridges cumulative-figure gaps; it never fills statistical
returns for mean, Sharpe, alpha or common-week membership.

The [full report](results/comparisons/NINETEEN_WAY_FULL_REPORT_CN.md) provides
paper locations and a discussion of every table and figure. Tables
with many rows are accompanied by original TeX/CSV outputs, not silently reduced
to one headline row. Figure files include the saved `.fig` representation.

Two calculations warrant explicit methodological definitions.
In the author code, `delay` uses the fourth expanded-regression output as
R-squared, although that output is residual skewness and the fifth is R-squared.
M0/M2 retain the author formula for their stated method contrasts; the M1
appendix uses the fifth output. A [same-input comparison](analysis/isolated_corrections/CORRECTION_COMPARISON_CN.md)
quantifies this source error in all eighteen experiments. In Table 7, M1 scales
the zero-cost tangency direction Σ⁻¹μ by a positive factor to target volatility,
without dividing by a possibly negative exposure sum. The compact TeX tables,
source CSV and full report use these definitions consistently. Neither
calculation changes CTREND's 28 technical predictors or its baseline returns.
The [table-source ledger](provenance/analytical_tables/TABLE_IDENTITIES.csv)
links the M1 Table 7 and delay rows to their saved-input calculations and parent
run references; the complete-run archives remain intact.

## Ablation and mechanism evidence

1. **P0→P1:** compare the same M/D. Filling changes feature availability, ranks,
   selection and weights; it is not just a cosmetic curve repair. Its aggregate
   baseline effect is comparatively small here, especially for M1, but that
   does not establish harmlessness for each asset/week/design.
2. **M0→M2:** on fixed common weeks, the mean generally remains high while risk
   increases. Outcome-dependent exclusions can suppress a tail in M0; removing
   that condition need not lower the mean. The change is not explained merely
   by M2 having four more own-support weeks.
3. **M2→M1:** label/history separation, support and estimator/accounting changes
   alter investable forecasts and weights. The two methods' joint-finite
   forecasts correlate about 0.989, yet low-leg holding Jaccard is only about
   0.54–0.57 and high-leg Jaccard about 0.59–0.62. High aggregate forecast
   correlation is not equality of sorted portfolios.
4. **INNBCL mechanism:** at 2020W16 M1 puts about 78.92% of its low leg in INNBCL.
   M0/M2 have no finite forecast for this asset. M1 and M2 save the same raw
   endpoint return, +703.14%; M1's total H-L that week is −554.87%. Thus the
   first-order divergence is exposure, not a different stored raw price ratio.
   That one week explains about 63.2% of M1's D1−D0 mean improvement; the rest
   comes from the other weeks' re-estimated portfolios. D1 is a full re-estimation,
   not simply subtracting the INNBCL loss from an unchanged portfolio.
5. **Fixed-weight payoff swap:** all six P/D pairs compare M1/M2 weights crossed
   with both endpoint arrays on the same four-corner-observed support. Weeks
   with either donor's within-week terminal trades are excluded from this
   static-weight test. The own-method diagonals reconstruct saved returns.
   Holding weights fixed, switching endpoint arrays leaves these restricted
   sample means unchanged. This points to allocation rather than the endpoint
   formula on that support; it says nothing definitive about the excluded
   terminal weeks or the separate causal effect of each M1 code edit.
6. **D1→D2 and interactions:** further event-asset exclusion does not produce a
   uniform improvement. The report gives same-M contrasts, 12 M×D differences
   in differences and eight telescoping key paths. Path contributions depend
   on the order because the method and universe interact. They are descriptive
   computational ablations, not independently randomized causal estimates.

Machine-readable evidence: [45 contrasts](results/comparisons/P_M_D_KEY_CONTRASTS_ALL_COMMON.csv),
[interactions](results/comparisons/METHOD_DATA_INTERACTIONS_ALL_COMMON.csv),
[paths](results/comparisons/KEY_PATH_DECOMPOSITIONS_ALL_COMMON.csv),
[holdings/forecast overlap](results/diagnostics/portfolio_diagnostics/KEY_PAIR_FORECAST_HOLDINGS_OVERLAP.csv),
[payoff exchange](results/diagnostics/portfolio_diagnostics/FIXED_WEIGHT_ENDPOINT_EXCHANGE.csv),
[INNBCL holdings](results/diagnostics/portfolio_diagnostics/INNBCL_2020W16_SAVED_HOLDINGS.csv).
No single-edit re-estimation was run for every M1 correction; mechanisms not
identified by these saved-output diagnostics remain qualified explanations.

## What is included

### Statistical interpretation

An individual strategy's positive mean and the significance of its difference
from another strategy are separate hypotheses. The roughly 2.61-percentage-point
M1 D1−D0 improvement has an ordinary paired t of about 1.32: its large point
estimate is not precise evidence of a general improvement. All nine P contrasts
have absolute ordinary paired t below 1.96; this is not an equivalence test.
The displayed difference tests do not adjust for serial dependence or multiple
comparisons. Tail concentration, the retrospective exit proxy and the availability
of short positions remain substantive limits on investment interpretation.

| Component | Location / role |
|---|---|
| Entry points | `run_all.sh`, `run_all.m`, `run_all.bat`; Linux production described below |
| Public 18-cell grid | `config/experiments_pmd.csv`; inner nine-cell IDs retained only for engine compatibility |
| Scientific engines | `engines/M0`, `M1`, `M2`; frozen unfilled M0 at `engines/P0_M0`; P0 overlays in `p0_extension` |
| Review code | `annotated_sources/P*_M*_D*/source`; not executed; body hashes identify production equivalents |
| Original source | `reference/dataverse_files.zip` and its extracted reference; unmodified comparison material |
| Raw inputs | `data/raw/common` with SHA256 inventories; supplied vendor snapshot, not a live data download |
| Accepted compact results | `results/experiments/P*_M*_D*`; tables, figures and baseline forecast/holding MAT |
| Full-run identities | `provenance/accepted_18`; original run/acceptance/result hashes and copied-member hashes |
| Reports / diagnostics | `results/comparisons`, `results/diagnostics`, `analysis`, `postprocessing` |
| Tests and releases | `tests`, `p0_extension/tests`, engine tests, `release` |

The compact Git repository does not contain all 18 × 3,072 large design MAT
files, run-local raw snapshots or worker job stores. They remain in the accepted
full-run archives. Every run had 3,072/3,072 MAT and matching sidecars; compact
member hashes bind the files included here. The [full-result access guide](docs/FULL_RESULT_ACCESS.md)
provides the per-run index, request procedure and verification requirements.
A fresh production run regenerates
the entire design grid and its final inventory, not only this compact subset.
The report is accompanied by source tables and machine-readable diagnostics.
Manuscripts are outside the scope of this code-and-results package.

## One-command reproduction

For the complete study, use a fresh extraction/checkout, install both
`environment/requirements-analysis.txt` and `cmc_acquisition/requirements.txt`,
set the paths below, then run `./reproduce_everything.sh`. Do not separately run
preflight/test/plan/all/b20. Its explicit `--resume` option revalidates and skips
registered cells; unregistered cells restart in new roots, preserving failures.
Source/input changes block resume. The default refuses existing registrations.
The commands below remain available for individual experiments and diagnostics.

Use Linux, MATLAB R2023b Update 11 and the toolboxes in
[TOOLBOXES.txt](environment/TOOLBOXES.txt). Authenticate online licensing before
launch. Set machine-specific paths through environment variables, never source
edits. The tested production topology requires at least 128 available logical
CPUs: b09 uses eight clients with 15 workers each. Other separable phases use
their verified parallel schedules; serial I/O/merge cannot guarantee 100% CPU.

```bash
export MATLAB_BIN=/absolute/path/to/R2023b/bin/matlab
export WORK_BASE=/absolute/data_disk/ctrend_work
export RUN_BASE=/absolute/data_disk/ctrend_runs
./run_all.sh preflight
./run_all.sh plan

# Closest reproduction of the published, unfilled, unexcluded method:
./run_all.sh experiment P0_M0_D0 production
# Bounded look-ahead/terminal-settlement ablation:
./run_all.sh experiment P0_M2_D0 production
# Broader audited method, same raw universe:
./run_all.sh experiment P0_M1_D0 production
# Example: common fill + broader audit + INNBCL exclusion:
./run_all.sh experiment P1_M1_D1 production
```

Each command is a **complete** raw-to-b18/design/supplement/inventory/acceptance
pipeline. D1 and D2 use the same engine with a different immutable registry.
For a detached task use `./run_all.sh launch P1_M1_D2`; for all 18 sequentially
use `./run_all.sh all production`. Do not launch multiple full 128-CPU tasks
on the same resource allocation. Host locks guard the public P/M/D entry points.
Do not use a shared exact `RUN_ROOT` or `JOB_STORAGE_ROOT` for a batch.

Existing output directories are not permission to overwrite a run. Failures
preserve their source/inventory/checkpoints; no missing return is filled with
zero to make an acceptance check pass. `./run_all.sh verify-all` revalidates
registered full runs when those run roots are present. Included compact results
can be checked separately with the result snapshot tests.

Rebuild the saved-result analysis without MATLAB or b00–b18 reruns:

```bash
python3 -m pip install -r environment/requirements-analysis.txt
./run_all.sh b20
```

Without arguments, `b20` runs the **included reference snapshot** diagnostics
and report builder, not the results of a new production execution. For accepted
local runs, use `./run_all.sh b20 --from-registrations /absolute/fresh/report_dir`.
The complete wrapper already does this and writes a source-bound completion
record under `outputs/reproduction/`; it never overwrites reference `results/`.
Current-run reports include paper benchmarks, the source-hashed published factor,
generated tables/figures, nineteen-way own/common-week and paper–experiment
paired statistics, plus eighteen-cell P/M/D comparisons. Reference
holding/payoff-mechanism narratives are not silently reused as fresh evidence.
`b19` is a nine-cell, fixed-P analysis interface, not the eighteen-cell
acceptance entry. See the [Runbook](RUNBOOK.md) for monitoring,
cross-host transfer, data identity and failure boundaries.

## Reading modifications

The annotated mirrors use `%%%%` for reading-only provenance, `%%%` for the
parent→child lineage, `%% [M0/M1/M2/P/D]` for the owner and rationale, and `%>>>`
for each exact changed block. Dataverse→P0 M0, D/P treatments and M0→M2/M1
are separate steps. Whole added helpers are one declared added-file block;
deleted blocks/files are indexed. Header removal must reproduce canonical
materialized bytes. These copies are for review and never on the production path.

See [annotation guide](docs/AUDIT_AND_ANNOTATIONS.md),
[issue register](docs/ISSUE_AND_CORRECTION_REGISTER.md) and
[method boundaries](docs/METHOD_BOUNDARIES.md). The publication tests verify
the public routing, all eighteen materializations, hashes, annotation bodies,
result membership and recomputed diagnostic identities. Passing them is evidence
of those tested contracts, not a guarantee of error-free economic data.
'''

CN='''# CTREND 复核：预处理 × 方法 × 数据范围

[English README](README.md) · [英文运行手册](RUNBOOK.md) · [十九方完整对比报告](results/comparisons/NINETEEN_WAY_FULL_REPORT_CN.md)

独立的 E01–E11 补充实验、代码、证据边界和验收结果见
[followup_research](followup_research/README_CN.md)。大体量逐行明细以分卷提供，
可按该目录说明恢复；补充实验没有覆盖原 18 组生产运行。E12 暂停。

**复现入口：参见 [完整复现指南](REPRODUCTION_GUIDE_CN.md)。**
配置软件后，`./reproduce_everything.sh` 会从封存输入依次运行全部检查、18 项完整实验、
验收和本次结果对比，不触发联网采集。默认要求全新执行；`--resume` 才复核并跳过已
登记实验，未登记项在新 root 重新开始。报告写入 `outputs/reproduction/`，不覆盖
随包参考 `results/`。不带参数的 `run_all.sh b20` 仅重建参考快照分析；新结果单独
导出使用 `run_all.sh b20 --from-registrations /absolute/fresh/report_dir`，一键入口
已自动执行此步骤。

## 研究动机与主要发现

收益预测研究的可复现性不仅取决于估计模型，还取决于信息时间、数据构造、有效样本
和投资组合会计。CTREND 的公开实现涉及上述多个方面，其中数据前视是最重要的
原则性问题：建仓时使用尚不可得的信息，会削弱样本外投资解释；这一判断不取决于
错误对平均收益的影响大小。一个直接的例子在 `fResampleLiuEtAl.m`：周末值缺失时，回退搜索的是全年
`mDataTemp`，不是当周数据，因此可能把年末才出现的值放进年初的周度变量。
具体语句是 `mDataTemp(find(~isnan(mDataTemp(:,idx)),1,'last'),idx)`。
此外，目标收益可观测性参与建仓筛选、清洗和样本起点，也使“真正样本外策略”的
解释需要重新审视。

研究因此不仅识别代码问题，还通过分解实验评估各类处理的实证影响与作用机制。
这里提供论文原值及作者公布的因子序列，加十八套已验收实验，而不是十八个独立样本。
结果不支持“只修前视，主要平均收益就消失”：M0 基本复现原文的总体统计量，
但并非逐周路径完全相同；M2 周均收益仍约 4.1%–4.5%，但波动增大，
年化 Sharpe 降至约 1.45–1.55。M1 在 D0 上的周均收益约为 0.05%，Sharpe 接近零；
排除 INNBCL 后周均收益约为 2.66%，进一步排除事件资产后约为 2.50%–2.51%。
关键机制在于方法如何改变持仓，并由此影响资产暴露与数据敏感性，而非每项修正都
必然降低收益。经济评价还须结合因子调整收益、交易成本、波动与回撤。
H-L 是多空因子收益，不能直接解释为充分抵押且可实际做空账户的收益率。

原则性判断与影响程度需要区分：M2 没有使主要平均收益消失，并不意味着前视可被
接受；M1 的较大绩效变化，也不构成某一处代码修改的单独因果证明。共同周比较和
持仓诊断用于进一步辨别这些差异，原始报价的真实性与可成交性则不由回测自行验证。

## 三个维度的详细设计

公共 ID 为 `P{0,1}_M{0,1,2}_D{0,1,2}`，共 18 项；M 的比较顺序为 M0→M2→M1。
机器可读配置见[18项配置](config/experiments_pmd.csv)。

### P：是否统一处理原始缺失

P0 不启用公共填充层，但仍执行数据同步、市值筛选、收益和异常标签处理，以及
各特征自身的缺失值规则。P0 的 M0 未填充源码保存在 `engines/P0_M0`；
P0 的 M1 关闭公共 b01 填充；M2 除此之外还使用与 P0/M0 相同的 b02 成交量清洗块。

P1 在各 M 方法处理前，以严格早于当日的最后有效收盘价填充缺失或非法的 OHLC
字段；成交量、成交额的缺失值、Inf 或负值置零。不以当日收盘倒填当日开盘；
没有前值的序列起点及终止边界之后仍保留价格缺失。该规则不意味着市值也被前填。
后续数据筛选和指标计算按各方法的定义执行。

成交量清洗也必须服从这一分组：**P0 的 M2 与 M0 使用相同的 b02 规则**，整行
零或缺失的成交量置为缺失，`volume <= 1e-6`（含显式零）置为 NaN；后续
“零成交量且收益非零”的条件保留原顺序，但零已被前一阈值处理。
**P1 的 M0/M2 保留显式零**，仅对 `0 < volume <= 1e-6` 的小正数作阈值处理。
数值零和不可用的 NaN 含义不同，会影响成交量指标、估计支持和组合。
保留零属于 P1 的输入约定，不属于 M2 的前视修复；P0/P1 的 M2 对比同时涵盖
b01 填充及配套的下游成交量规则，不能解释为单独的价格填充效应。

前值填充是一项数据约定，并非对真实成交价格的验证：它可能引入零收益并掩盖陈旧
报价；将缺失成交量置零也不等于确认没有交易。因此 P 被单独设置为敏感性维度。
即使 P1 填充了输入缺口，M0/M2 的异常值处理仍可能使量价单元变为 NaN；原始缺失
处理与标签清洗引入的缺失属于两个不同环节。

### M：原实现、前视消融、全面审计实现

| 原代码问题或约定 | M0 | M2 | M1 |
|---|---|---|---|
| 缺失周末值可以搜索全年未来观测 | 保留 | 修复 | 修复 |
| 未来收益支持参与建仓/样本起点，或使用持有期价格市值筛选 | 保留 | 修复指定通道，受退出日历假设约束 | 同样修复 |
| outlier阈值/变换读取目标期信息 | 原路径 | 历史逐周截面 | 历史逐周标签截面 |
| TRUNC/WIN连带挖空量价及市值，污染后续指标可观测性 | 保留 | 保留 | 标签清洗与量价历史分离 |
| 所有predictor共用完整支持 | 保留 | 保留 | 各指标自身formation支持rank及回归支持 |
| 技术指标、validation、组合平均、Figure C与论文/定义不一致 | 保留 | 除明确前视通道外保留 | 按审计定义修复 |
| Table3市值/IVOL尺度，Table7固定过去日历窗及奇异性 | 原做法 | 原做法 | 按定义修复 |
| 原代码 `delay` 把扩展回归残差偏度误作 R² | 保留以复现原口径 | 保留以限定前视消融 | 改读第 5 个输出，并另列十八组单项比较 |
| Figure 3 的 GRS 把检验资产收益误传为因子收益 | 保留 | 保留（不属于前视） | 传入实际模型因子收益；共同周估计并仅去除完全重复的检验资产 |
| 初始建仓、gap、双腿成本、长期固定cohort会计 | 原做法 | 除因果/终止处理外保留 | 明确经济会计 |
| 可运行性、等价并行、headless图形、哈希发布 | 支持 | 支持 | 支持 |

M0 保留原作者的经济与统计设计；工程适配及并行加速以不改变科学数值为边界，
P/D 则属于明确的实验处理。P0_M0_D0 最接近原文未填充、未排除资产的实现，
但本研究数据快照与论文样本不保证完全一致。

M2 的修改范围直接相对于 M0 定义，保留其特征公式、联合支持和多数附表会计。
除了指定前视通道的修复，M2 还包含端点结算与终止后的即刻再投资。因此 M0→M2
衡量的是一组有明确边界的处理，不能解释为某一行未来回填代码的独立效应。

TRUNC 与 WIN 是两个设计选项：前者将极端标签置为 NaN，后者将标签压至阈值。
但 M0/M2 的两种选项都会在命中位置使同步价格等字段变为缺失。清洗后的日收益
仍进入统计特征与周收益等计算，因此相同价格掩码并不意味着相同结果。M1 将标签
清洗与技术指标的量价输入、经济 P&L 分离；这也不等于认定所有原始报价都是真实
成交价。3,072 项设计不包含“先对价格路径缩尾，再重算 X”的独立稳健性实验。

M1/M2 使用历史逐周截面的异常标签阈值，而非跨整个训练窗口合并估计阈值。
Table 4 等统计标签回归保留其统计对象，不改为原始经济收益回归。

### 终止结算与信息假设

M1/M2 根据完整价格历史构造并冻结机械退出日历，在指定最后有价时点结算，所得
资金立即再投资于同腿其余持仓；VW 使用相应当日市值，不保留闲置现金。整周不可用
资产按冻结的可交易性约定处理；再投资输入不完整时，收益仍记为不可核算。周中
偶然缺失与序列终止分别处理。

我们没有公告时间数据。用完整历史推断退出日是明确的可交易性替代假设；“运行前
冻结”本身不能证明投资者当年提前知道终止日。因此不能宣称这套结果仅凭价格面板
已证明严格实时可实现。退出日历是需要披露的研究假设，而非已观察到的公告记录。

### D：全历史排除，不调整价格、不拼接币种

D0保留原始CMCID含INNBCL，不做拆并币量价修补。D1在所有日期删除3787，位置在
市场聚合、筛选、特征、rank、训练、投资组合之前，不是只删2020W16。D2在D1上
再删冻结事件表中27个ID，总共28个，见[D2排除表](config/exclusions/D2.csv)和
[事件分类](config/event_asset_registry_v20260811.csv)。

不同交易所、不同字段的单位切换未必同步，CMC聚合后可能混合单位，HYDRO和SHND
说明了单一边界与比例修正的适用限制。本设计使用全币种排除来衡量敏感性，而不对
每次异常的真假或修补方式作判断。事件分类区分了单位证据较强的情形与不能安全
定位聚合数据边界的情形；D2 不意味着所有被排除报价均为错误。

NPXS(2603)/PUNDIX(9040)是两个不同ID，不拼接，也不因项目迁移就纳入D2。1:1
改名/换合约本身不构成整数单位改变的排除理由；YAM非固定rebase也不当成常数
拆并币处理。LFG(11086)、ROOM(8351)、HANZO(9765)及NOTE(184)是保留的1:1/
非缩放例子，详见[事件排除说明](docs/EVENT_EXCLUSION_SCOPE.md)。冻结事件表不是
“所有事件已穷尽”的证明。

## 论文加十八组主要结果

收益以周百分比表示，Sharpe 按 √52 年化；均值 t 为普通样本均值检验，
不是 HAC 因子调整收益检验。未改动 Dataverse ZIP 中的 `Results/CTREND/CTREND.xlsx`
提供作者公布的 371 个有限 H-L 周收益（2015W16–2022W22）；完整支持的均值、标准差、
普通 t 和 Sharpe 分别舍入为 Table 3 的 3.87%、14.34%、5.19 和 1.94。
以下使用重算精度，并把实际作者序列加入十九方日期交集。YYYYWW 沿用作者每年
52 周分块，不是 ISO 周。

@@TABLE@@

十九方共同周为 337 个（2015W25–2022W22），加入作者序列没有改变本快照中十八组
实验的共同交集。M0、M2、M1 的各自可用样本分别为
349、353、337 周；这些是观测结果，不是验收门槛。完整日历的 423 个位置包含
初始训练期和内部未形成组合的周。累计图以零增量连接缺口仅用于展示；均值、
Sharpe、因子调整收益与共同周筛选均保留统计收益的缺失状态。

@@PAPER_PAIR_CN@@

## 机制证据与识别范围

1. P0→P1同M同D比较：填充会改变指标观测、排序、入选和权重，不只是曲线美化。
   此处基准平均影响较小，尤其M1，但不能推出每币每周或3072设计都不敏感。
2. M0→M2：共同周上仍然是均值保持较高、风险上升；不是仅因为M2多4周。删除
   未来支持条件可能释放原本被过滤掉的尾部，修前视没有“均值必然下降”的定理。
3. M2→M1：在共同有限单元上预测相关约0.989，但L腿持仓Jaccard只有约0.54–0.57，
   H腿约0.59–0.62。预测相关高不代表五分位及市值权重相同。
4. INNBCL：2020W16 M1 的 L 腿约 78.92% 配置于该币；M0/M2 对该币没有有限预测。M1/M2
   保存的其原始endpoint收益同为+703.14%，M1该周整体H-L为−554.87%。首先是
   持仓暴露不同，不是两套原始价格比率不同。该周解释M1 D1−D0均值改善约63.2%，
   其余来自其它周重新估计的组合；不能只从原组合中减掉该币就代替D1。
5. 固定权重交换payoff：在六个P/D单元中，仅取两方都无周中终止交易、四个交叉
   权重×收益组合都可核算的共同样本。自身对角项可重构原组合收益；固定权重后
   交换endpoint数组不改变该限制样本均值。这支持分配/权重机制，不能推广到已排除
   的终止交易周，也不能区分每个M1修改的独立因果贡献。
6. D1→D2不是单调改善；完整报告列出45个关键一对一、12个M×D双重差分和8条
   可加总验证的关键路径。方法与数据交互，所以路径分项依赖顺序，不是随机因果实验。

详细逐图逐表、共同周及三维消融见[完整报告](results/comparisons/NINETEEN_WAY_FULL_REPORT_CN.md)。

两项计算需明确其方法定义。原作者 b02 把扩展市场回归的第 4 个输出当作 R²，
但该输出实际是残差偏度，第 5 个才是 R²；M0/M2 按各自消融范围保留原公式，
M1 附录采用第 5 个输出。[十八组同输入比较](analysis/isolated_corrections/CORRECTION_COMPARISON_CN.md)
单独量化这一原始源码问题的影响。Table 7 中，M1 沿 Σ⁻¹μ 的切点方向以正比例
系数缩放至目标波动率，不除以可能为负的权重和。TeX 表、源 CSV 和完整报告
统一使用上述定义，两项计算均不改变 CTREND 的 28 个技术预测量及基准收益。
[表格来源清单](provenance/analytical_tables/TABLE_IDENTITIES.csv)关联 M1 Table 7、
delay 附录与其保存输入的单项计算、父运行参考文件；完整运行档案保持原样。
机器可读[关键比较](results/comparisons/P_M_D_KEY_CONTRASTS_ALL_COMMON.csv)、
[交互](results/comparisons/METHOD_DATA_INTERACTIONS_ALL_COMMON.csv)、
[路径](results/comparisons/KEY_PATH_DECOMPOSITIONS_ALL_COMMON.csv)、
[持仓重合](results/diagnostics/portfolio_diagnostics/KEY_PAIR_FORECAST_HOLDINGS_OVERLAP.csv)、
[交换收益](results/diagnostics/portfolio_diagnostics/FIXED_WEIGHT_ENDPOINT_EXCHANGE.csv)可独立复查。

## 如何复现与阅读

### 推断与经济解释

单个策略均值为正，与它相对另一策略的差异显著，是不同的统计问题。M1 的 D1−D0
均值改善约 2.61 个百分点，但普通配对 t 约为 1.32；不能仅由点估计较大推断普遍
改善。P 维度九项配对 t 的绝对值均低于 1.96，同样不构成预处理等价性证明。这些
比较未做序列相关稳健调整或多重检验校正。极端观测集中度、退出信息代理和实际
可做空性，都应与均值、因子调整收益及成本一起评价。

英文[运行手册](RUNBOOK.md)给出完整环境、入口和失败边界。Linux生产使用MATLAB
R2023b Update11及列出的工具箱，至少128个可用逻辑CPU；b09为8个client×15workers。
串行保存、合并阶段瞬时CPU低是正常的，不承诺每个时刻100%。所有本机路径由环境
变量提供，不修改代码。

```bash
export MATLAB_BIN=/absolute/path/to/R2023b/bin/matlab
export WORK_BASE=/absolute/data_disk/ctrend_work
export RUN_BASE=/absolute/data_disk/ctrend_runs
./run_all.sh preflight
./run_all.sh experiment P0_M0_D0 production
# 分别改成 P0_M2_D0、P0_M1_D0 或任意其它完整 P/M/D ID
# 单项后台：
./run_all.sh launch P1_M1_D2
# 十八项顺序执行，不是同时启动：
./run_all.sh all production
```

每项从raw开始执行完整b00–b18、3072设计、补充输出、inventory、完成与登记。
`./run_all.sh verify-all`复核本机登记的完整run；公开compact结果可由独立结果测试
核对，不伪造成本机新跑的registration。仅重建结果分析用：

```bash
python3 -m pip install -r environment/requirements-analysis.txt
./run_all.sh b20
```

b20 不重估模型；b19 用于固定 P 的九项登记分析。包内保留原始 CSV/因子输入、原始
Dataverse压缩包及解压参考、18项表图和baseline持仓预测MAT、原结果成员哈希。
完整18×3072设计MAT和worker工作目录在数据盘成功run档案，不重复塞进Git。
逐项身份索引、向维护者申请传输的方法和接收核验要求见[完整结果获取说明](docs/FULL_RESULT_ACCESS.md)；
Git 仓库没有提供完整 run 的公开下载地址，不应把 compact 文件误认作全量档案。
研究报告附有逐表数据和机器可读诊断；论文稿件不属于代码与结果包的内容。

含注释源码在`annotated_sources/P*_M*_D*/source`，不参与生产。`%%%%`仅帮助阅读，
`%%%`标父子血缘，`%% [M0/M1/M2/P/D]`解释归属和原因，`%>>>`标每段精确变更。
新增整文件作为一个代码块，删除另有索引；剥离新增头注释必须恢复原生产字节。
公共调度只存一份，以功能头注释解释；不假装它来自论文源码。

结果、输入和源代码身份由清单绑定；含注释阅读副本须与执行代码正文一致。
测试验证相应契约，经济解释和数据质量则需要在所列假设下独立评价。
'''

def lead_with_evidence(text,start,end,before):
    i=text.index(start);j=text.index(end,i)
    block=text[i:j]
    text=text[:i]+text[j:]
    at=text.index(before)
    return text[:at]+block+text[at:]

# Report numerical agreement separately from sequence agreement; matching
# rounded moments is not a substitute for checking date-keyed weekly paths.
pair_en=f"""On its {paper_m0['common_weeks']}-week intersection with P0_M0_D0, the
author factor has mean {float(paper_m0['first_mean_pct']):.4f}% versus
{float(paper_m0['second_mean_pct']):.4f}% for the replication; weekly correlation
is {float(paper_m0['correlation']):.4f}, not one. Its published full sample and
the M0 run therefore are not interchangeable series. Source hashes, the
nineteen-way panel, all pairwise intersections, and fixed-support paired return
differences are provided in the [published-factor comparison](results/comparisons/paper_factor/NINETEEN_WAY_COMMON_WEEK_COMPARISON_CN.md).
Only H-L is published in that workbook; author holdings, quintile legs and
design-cell returns are not inferred from M0.
"""
pair_cn=f"""在作者与 P0_M0_D0 的 {paper_m0['common_weeks']} 周交集上，作者均值为
{float(paper_m0['first_mean_pct']):.4f}%，实验为 {float(paper_m0['second_mean_pct']):.4f}%；
逐周相关系数为 {float(paper_m0['correlation']):.4f}，并非完全相同序列。总体舍入值相近
不能代替逐周路径核验。来源哈希、十九方面板、各自配对交集和固定支持的收益差见
[作者因子共同周报告](results/comparisons/paper_factor/NINETEEN_WAY_COMMON_WEEK_COMPARISON_CN.md)。
工作簿仅提供 H-L，不将 M0 分位腿、持仓或设计收益冒充作者原始数据。
"""
EN=EN.replace('The [full report](results/comparisons/NINETEEN_WAY_FULL_REPORT_CN.md) provides',pair_en+'\nThe [full report](results/comparisons/NINETEEN_WAY_FULL_REPORT_CN.md) provides')
CN=CN.replace('@@PAPER_PAIR_CN@@',pair_cn)

EN=lead_with_evidence(EN,'## Nineteen-way principal-result comparison','## Ablation and mechanism evidence','## Experiment design')
CN=lead_with_evidence(CN,'## 论文加十八组主要结果','## 机制证据与识别范围','## 三个维度的详细设计')
# Keep interpretation with the findings rather than nesting it in execution.
for lang,title,following,destination in [('EN','### Statistical interpretation','| Component |','## What is included'),
                                       ('CN','### 推断与经济解释','英文[运行手册]','## 如何复现与阅读')]:
    text=EN if lang=='EN' else CN
    i=text.index(title);j=text.index(following,i)
    block=text[i:j].replace('### ','## ',1)
    text=text[:i]+text[j:]
    at=text.index(destination);text=text[:at]+block+text[at:]
    if lang=='EN':EN=text
    else:CN=text
(R/'README.md').write_text(EN.replace('@@TABLE@@',result_table()))
(R/'README_CN.md').write_text(CN.replace('@@TABLE@@',result_table(True)))
(R/'results/README.md').write_text('''# Accepted eighteen-experiment result snapshot

The results cover P0/P1 × M0/M1/M2 × D0/D1/D2. Each experiment includes
Tables, Figures, and CTREND/CTREND_Base.mat are traced to their accepted runs.
Figures, baseline MAT files and all but two tables per M1 experiment retain
the full-run bytes. The M1 Table 7 and delay appendix tables use the saved-input
component calculations under ../analysis/isolated_corrections; their source
ledger is ../provenance/analytical_tables/TABLE_IDENTITIES.csv. The complete-run
copy ledger is ../provenance/accepted_18/RESULT_MEMBER_IDENTITIES.csv, including
the unchanged table references stored in ../provenance/accepted_18/table_reference.
The complete 3072-design trees remain in the full-run archive, not in this
compact Git snapshot. See [full-result access](../docs/FULL_RESULT_ACCESS.md)
and its run-identity index for requesting and verifying those directories.
No registration is fabricated for the compact files.

comparisons/NINETEEN_WAY_FULL_REPORT_CN.md presents the research findings.
comparisons/source_tables contains the table/figure data and common-week series.
comparisons/paper_factor contains the authenticated author factor, nineteen-way
finite-date intersections, own/common statistics and all pairwise comparisons.
MANIFEST.sha256 authenticates all compact results and report members.
diagnostics/portfolio_diagnostics uses the saved baseline portfolios.
A separate, narrowly scoped audit at
[`diagnostics/p0_selected_week_asset_audit`](diagnostics/p0_selected_week_asset_audit/FIELD_DICTIONARY.md)
contains compressed asset-by-method rows for nine P0 baselines and five
preselected weeks, 90 EW/VW portfolio summaries, five short-history SMA
examples, five future-backfill examples, and the saved reinvestment event-week
audit. It has its own source-run manifest and SHA256 checksums. The export
script is [`analysis/export_p0_key_week_asset_audit.py`](../analysis/export_p0_key_week_asset_audit.py).
It does not replace any original result file or full-run inventory.
A mean t is not a HAC alpha t. Presentation-only zero-increment gaps
are not observed economic returns. Missing values remain missing in statistics.
''')
(R/'analysis/README.md').write_text('''# Saved-result analysis

Run `./run_all.sh b20` from the package root. It reads the 18 accepted compact
CTREND_Base.mat files, validates the saved-return reconstruction, derives 45
pairwise forecast/holding diagnostics and restricted four-corner endpoint swaps,
and rebuilds the merged nineteen-way report and P/M/D contrasts. It does not
start MATLAB, rerun b00–b18, change weights or impute missing payoffs.

`diagnose_eighteen_accepted_runs.py` computes baseline diagnostics;
`build_nineteen_way_report.py` combines paper cells,
common-week evidence and portfolio diagnostics. Each output has a result manifest.
`render_m1_publication_tables.py` keeps the bundled M1 Table 7 and delay
appendix TeX/CSV/Markdown consistent with their saved-input component calculations;
it preserves full-run table references and does not touch a production run.
`paper_factor_comparison.py` reads the actual published factor workbook directly
from the unmodified author ZIP and adds date-keyed nineteen-way and paired
comparisons. It never substitutes an M0 run for the author series; the fresh-run
exporter uses the same module with only newly verified experiment baselines.
`../postprocessing/b20EighteenCellAblation.sh` is the public entry.
The MATLAB b19 interface operates on a fixed-P nine-cell registry;
b20 covers the complete eighteen-cell analysis.

The [single-component comparison](isolated_corrections/CORRECTION_COMPARISON_CN.md)
examines the author-source `delay` output ordinal and this study's M1 Table 7
direction on the saved run inputs. The full-run files remain unchanged; no b09
design is re-estimated. The CSVs, MATLAB scripts, and SHA-256 receipts are under
`isolated_corrections/`.
''')
# Dependency declarations are maintained independently of research prose.
# Rebuilding a README must not rewrite the environment needed by other tools.
print('PUBLICATION_GUIDES_OK bilingual=1 experiments=18')
