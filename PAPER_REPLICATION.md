# Paper replication and evidence map

This repository accompanies a revisit of Fieberg, Liedtke, Poddig, Walker and Zaremba, *A Trend Factor for the Cross Section of Cryptocurrency Returns*, JFQA 60 (2025), 3116–3153, DOI [10.1017/S0022109024000747](https://doi.org/10.1017/S0022109024000747). The revisit manuscript version and author list should be cited from the manuscript itself; neither is inferred here.

Read the public results in this order:

1. `results/comparisons/source_tables/NINETEEN_WAY_HEADLINE.csv`: paper values plus the eighteen P×M×D cells. This is a *saved summary*, not a new computation from raw CMC data.
2. `results/comparisons/source_tables/EIGHTEEN_EXPERIMENT_ALL_TABLE_CELLS.csv`: saved experiment-side cells for paper tables. A blank cell means no exported value, not zero.
3. `results/comparisons/source_tables/EIGHTEEN_EXPERIMENT_FIGURE_INVENTORY.csv`: identities and hashes of accepted figures held in the controlled archive. The public checkout does not contain every PNG/FIG.
4. `results/comparisons/paper_factor/PAPER_WEEKLY_RETURNS.csv`: the author's published H–L factor series, derived from the CC0 Dataverse workbook. Its 371 finite weeks, mean, standard deviation, t statistic and annualized Sharpe are recalculated by the quick check. This is the author's actual series, not a surrogate M0 series.
5. [Direct relative-model comparison](followup_research/model_advantage_direct/README.md):
   paired M0→M2→M1 changes in TREND's advantage over LTW, incremental-information
   decomposition, fixed-asset pricing errors and rolling opportunity portfolios.
   This independent analysis has its own inferential limits and does not alter
   the original paper-item mapping or the eighteen baselines.

The table/figure-to-code/permission mapping for the **published CTREND paper** is [TABLE_FIGURE_MAP.csv](TABLE_FIGURE_MAP.csv). It covers nine main tables, three main figures, ten appendix tables and four appendix figures (19 tables and seven figures). The internal release taskbook's separate estimate of “26 tables and five figures” does not match this published-paper inventory, and no final revisit manuscript with that numbering was available for a defensible row-by-row map. Do not represent this CSV as a final-revisit-manuscript map; update it when that manuscript is frozen.

## Interpretation of the contrasts

M0 approximates the released program's scientific definitions, subject to necessary execution-only adaptations. M2 addresses the specified timing and terminal-settlement channels while intentionally retaining other M0 definitions. M1 applies the broader audit, including the separation of historical label cleaning from raw economic payoff, predictor support, paper-aligned statistics and portfolio accounting. M1's Table 7 tangency-direction sign issue was an error introduced in the revisit implementation and later corrected in presentation; it is **not** attributed to the original authors. The fourth-versus-fifth `delay` output issue belongs to the original code, concerns one characteristic, and is **not** a retraining fix for the 28 main CTREND predictors.

The empirical hierarchy is: predictor performance, factor risk-adjusted returns, incremental model comparisons, and executable net trading returns. A positive gross H–L return alone does not establish the latter. The 3,072 research designs are correlated choices, not 3,072 independent statistical replications.

Saved run identities and acceptance hashes are in `results/comparisons/source_tables/RUN_IDENTITIES_18.csv`; paths are relative descriptors for a controlled archive, not downloadable destinations. The source bytes copied here are separately listed in `provenance/SOURCE_FILE_MAP.csv`. Full run trees, logs, and licensed input files are available only through the controlled project under applicable permissions.

The executable public quick-replication route is `./reproduce_tables.sh`. It recalculates the author factor's 371-week moments from the original workbook and reshapes the saved aggregate cells into fresh CSVs. It does not estimate CTREND anew. The produced SVGs are diagnostic redraws and must not be cited as reproductions of the original paper's Figures 1–3 or appendices. Full model re-estimation is a separate, licensed-input route described in [QUICKSTART.md](QUICKSTART.md).
