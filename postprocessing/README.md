# Saved-result robustness analysis

## b20: complete eighteen-cell evidence

Run `./run_all.sh b20` to reconstruct the P0/P1 × M0/M1/M2 × D0/D1/D2
comparison from the included accepted baseline files. It produces common-week
returns, P/M/D contrasts, holding/forecast overlap, restricted payoff swaps,
the nineteen-way report and bilingual guides. No model is re-estimated and
no MATLAB production task is started. See [analysis](../analysis/README.md).

## b19: fixed-P nine-cell registered-run analysis

`b19CommonWeekRobustness.m` is the first numbered module after the reproduced
b00--b18 pipeline. It is intentionally stored outside every method engine: it
is a post-estimation robustness comparison, not a change to Dataverse-derived
scientific source.

For the P1 inner-engine registry, after all nine experiments have valid
package registrations, run:

```bash
MATLAB_BIN=/absolute/path/to/R2023b/bin/matlab \
  ./run_all.sh b19 /fresh/absolute/output/directory
```

The launcher revalidates all nine registrations and hashes each saved
`CTREND_Base.mat`. It reports own-support statistics, strict all-nine support,
M0/M2/M1 common support within each D treatment, D0/D1/D2 common support within
each method, and every pairwise intersection. Missing returns are never filled
or set to zero. No pipeline stage or completed run root is rerun or modified.

`b19_input_bindings.csv`, `B19_OUTPUTS.sha256`, and `B19_COMPLETE.env` bind the
postprocessor to exact accepted inputs without recording site-specific paths.
