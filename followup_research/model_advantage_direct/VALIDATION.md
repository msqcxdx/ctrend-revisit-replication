# Validation scope

The direct comparison was calculated in Python 3.12.12, NumPy 2.5.3 and
SciPy 1.18.1. Validation covers this isolated analysis, not a new full run of
the eighteen MATLAB experiments.

- All eighteen saved VW H−L sequences match their original `CTREND_Base.mat`
  arrays; parent completion identities and baseline hashes remained unchanged.
- Nine synthetic tests cover covariance conventions, block-count equivalence,
  algebraic decompositions, singular systems, OLS/GRS inputs, calendar-aware
  HAC, tangency direction, future-training perturbation, degenerate inference
  and an end-to-end input fixture. All pass.
- The entire twelve-setting analysis was run twice with the same seed and
  5,000 draws per 4/8/12-week block. All fourteen result CSVs are byte-identical.
  `verify_results.py --compare /second/result/directory` checks this directly.
- E03 opportunity differences and saved rolling paths were independently
  reconstructed under E03's definitions. E04's eighteen pairwise comparisons
  match their saved point estimates. No output was copied into an estimated
  model-difference cell as a substitute for recalculation.
- No bootstrap covariance failures occurred in the reported model, pricing or
  OOS comparisons. Two method-level settings (M1/D0 with reconstructed LTW,
  under P0 and P1) do not reject the common-factor spanning boundary and are
  explicitly left without ordinary inferential p values or intervals.
- The controlled repository's saved-result audit passes, including original
  baseline support and the analytical Table 7/delay publication tables.

One separate, pre-existing controlled-archive check is not represented as
passing: `followup_research/scripts/test_followup_documentation.py` compares
historical manifests to current copies of `analyze_e02.py`,
`analyze_e03_oos.py`, `analyze_e11.py` and `extract_e08_asset_contributions.py`
and reports source-hash differences. These four files and those manifests
are unchanged by this analysis. The independently checked input values,
E03/E04 reconciliation and new run receipt do not rely on that check passing.
This module neither rewrites historical receipts nor claims that every
controlled-repository test passes.

These validations establish reproducibility and the stated numerical
contracts. They do not prove exact bootstrap size under heavy tails, establish
market-data truth or liquidity, or convert ex-post exclusions into live rules.
