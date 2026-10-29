# CTREND Revisit: public replication materials

This is a clean-history, rights-screened public companion to the CTREND revisit. It is **not** a copy of the controlled research repository, and a clone does **not** include the licensed CoinMarketCap (CMC) price panel or the complete 18-run MATLAB archives.

The main information-set problem in the published CTREND program is a weekly fallback that can read an observation later than the week being constructed. The revisit separates that timing correction (M2) from the broader statistical and portfolio-accounting audit (M1). Fixing the identified future-data channels alone does not erase the principal gross mean in these experiments; risk, sample support, asset exposure and other definitions matter. These are paired designs on one historical vendor snapshot, not independent samples or evidence of executable trading profits.

Start with [PAPER_REPLICATION.md](PAPER_REPLICATION.md) for the research question and result map, [QUICKSTART.md](QUICKSTART.md) for tested commands, and [DATA_AVAILABILITY.md](DATA_AVAILABILITY.md) before attempting a full run. [README_CN.md](README_CN.md) is the Chinese overview. [KNOWN_LIMITATIONS.md](KNOWN_LIMITATIONS.md) states interpretation limits; [PUBLIC_VALIDATION.md](docs/PUBLIC_VALIDATION.md) records what was actually tested in a fresh export.

## What is here

- `engines/`, `config/`, `scripts/`, `postprocessing/`, `analysis/`, `tests/`: scientific method code plus public-checkout orchestration derived from controlled source commit `e634a51d53cfb56dccd35d16ce2009bb824cef18`. Internal identifiers consistently use `ctrend`/`CTREND`; `provenance/SOURCE_FILE_MAP.csv` records source and public hashes, and the public-only preflight/test/documentation substitutions are explicit in `public_overrides/`.
- `reference/dataverse_files.zip`: the original author-deposited comparison package from [Harvard Dataverse, doi:10.7910/DVN/NTIVT8](https://doi.org/10.7910/DVN/NTIVT8), whose dataset metadata identifies CC0 1.0. Its embedded `fGRS.m` retains a separate BSD notice. This reference is not our input-market-data license.
- `results/comparisons/`: compact, non-asset-level comparison tables, the author-published factor series extracted from the reference workbook, and an inventory of figures. A figure inventory is **not** the figures themselves.
- `provenance/`: a byte-level link to the controlled source and the accepted research-run IDs/hashes, without private run paths.
- `followup_research/model_advantage_direct/`: paired model-advantage tests,
  fixed-asset pricing comparisons and rolling opportunity comparisons, with
  code, compact results and a Chinese interpretation. Restricted input panels
  are not included.

The `P` axis compares no added uniform missing-data fill (P0) with one documented OHLCV convention (P1). The `M` axis compares published-code scientific definitions (M0), bounded timing/settlement repair (M2), and the broader audit (M1). The `D` axis compares the original CMC universe (D0), whole-history exclusion of INNBCL/CMCID 3787 (D1), and that exclusion plus a frozen set of 27 event-exposed assets (D2). D1/D2 are retrospective sensitivity designs, **not** live investability screens.

## Relative model advantage

On the common P0/D0 sample with external LTW, TREND's weekly maximum squared-
Sharpe advantage is 0.05800 for M0, 0.02398 for M2 and −0.01850 for M1. The
**direct** M0-to-M1 change is −0.07649, with a paired-block 95% interval
[−0.12228, −0.02762] and p = 0.0012 (three-contrast Holm p = 0.0036).
The total decline persists across P/D and benchmark sensitivities; the two
adjacent contrasts are weaker after adjustment.

This does not imply that every pricing result fails: the fixed-test-asset
pricing-error comparison does not establish an M0-to-M1 deterioration. Rolling
opportunity portfolios support an overall Sharpe decline, but not a significant
M0-to-M2 decline in the primary setting. These are statistical factor
opportunities, not executable trading accounts. See the
[methods and output guide](followup_research/model_advantage_direct/README.md)
and [Chinese results](followup_research/model_advantage_direct/RESULTS_CN.md).

## Two levels of replication

1. **Public quick replication:** `python3 scripts/public_quickcheck.py` verifies export identity; `./reproduce_tables.sh` independently reads the author workbook, recalculates its H–L moments, checks the saved 18-cell aggregate evidence, and creates two clearly labelled diagnostic SVGs. It does **not** train models or recreate the original paper's figures.
2. **Full re-estimation:** `./reproduce_everything.sh` is the one-command 18-cell route **after** separately authorized inputs and the exact required MATLAB helpers have been installed. The public checkout deliberately omits those third-party files. Production preflight fails if inputs, helpers, MATLAB or required tests are missing. A fresh full run from this public checkout has not been claimed as completed; see [QUICKSTART.md](QUICKSTART.md).

The controlled repository remains private; its eighteen accepted experimental archives are unchanged. No private Git history, run root, or restricted raw-data file was imported into this repository. The current mapping covers the published **original** paper; a final revisit-manuscript map and release tag await a frozen manuscript and author approval.
