# Saved-result postprocessing

`./run_all.sh b20 --from-registrations /fresh/absolute/output` builds a new
report **only after all 18 experiments have completed and registered in the
same checkout**. The public repository contains compact published summaries,
not the 18 accepted baseline MAT files; `./run_all.sh b20` without new local
registrations is therefore not a public quick-replication command.

For a rights-screened quick check of the author workbook and saved aggregate
cells, use [`reproduce_tables.sh`](../reproduce_tables.sh). This does not
re-estimate any CTREND model or recreate the paper's private figure files.

`b19CommonWeekRobustness.m` remains a post-estimation robustness module. With
valid locally produced P1 inner-engine registrations, run:

```bash
MATLAB_BIN=/absolute/path/to/R2023b/bin/matlab \
  ./run_all.sh b19 /fresh/absolute/output/directory
```

It checks the saved baselines and reports own, fixed-nine and pairwise common
weeks. Missing returns remain missing; they are not set to zero. Each result
is bound to registered local inputs with an output checksum inventory.
