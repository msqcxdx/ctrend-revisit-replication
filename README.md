# CTREND Revisit: public replication materials

This is a clean-history, rights-screened public companion to the CTREND revisit. It is **not** a copy of the controlled research repository, and a clone does **not** include the licensed CoinMarketCap (CMC) price panel or the complete 18-run MATLAB archives.

The main information-set problem in the published CTREND program is a weekly fallback that can read an observation later than the week being constructed. The revisit separates that timing correction (M2) from the broader statistical and portfolio-accounting audit (M1). Fixing the identified future-data channels alone does not erase the principal gross mean in these experiments; risk, sample support, asset exposure and other definitions matter. These are paired designs on one historical vendor snapshot, not independent samples or evidence of executable trading profits.

Start with [PAPER_REPLICATION.md](PAPER_REPLICATION.md) for the research question and result map, [QUICKSTART.md](QUICKSTART.md) for tested commands, and [DATA_AVAILABILITY.md](DATA_AVAILABILITY.md) before attempting a full run. [README_CN.md](README_CN.md) is the Chinese overview. [KNOWN_LIMITATIONS.md](KNOWN_LIMITATIONS.md) states interpretation limits; [PUBLIC_VALIDATION.md](docs/PUBLIC_VALIDATION.md) records what was actually tested in a fresh export.

## What is here

- `engines/`, `config/`, `scripts/`, `postprocessing/`, `analysis/`, `tests/`: the frozen scientific method code plus public-checkout orchestration from controlled source commit `58c8bad72d318eb7f17610084cc826bfbbbe9511`. `provenance/SOURCE_FILE_MAP.csv` records both hashes for every copied file; the three public-only preflight/test/documentation substitutions are explicit in `public_overrides/`.
- `reference/dataverse_files.zip`: the original author-deposited comparison package from [Harvard Dataverse, doi:10.7910/DVN/NTIVT8](https://doi.org/10.7910/DVN/NTIVT8), whose dataset metadata identifies CC0 1.0. Its embedded `fGRS.m` retains a separate BSD notice. This reference is not our input-market-data license.
- `results/comparisons/`: compact, non-asset-level comparison tables, the author-published factor series extracted from the reference workbook, and an inventory of figures. A figure inventory is **not** the figures themselves.
- `provenance/`: a byte-level link to the controlled source and the accepted research-run IDs/hashes, without private run paths.

The `P` axis compares no added uniform missing-data fill (P0) with one documented OHLCV convention (P1). The `M` axis compares published-code scientific definitions (M0), bounded timing/settlement repair (M2), and the broader audit (M1). The `D` axis compares the original CMC universe (D0), whole-history exclusion of INNBCL/CMCID 3787 (D1), and that exclusion plus a frozen set of 27 event-exposed assets (D2). D1/D2 are retrospective sensitivity designs, **not** live investability screens.

## Two levels of replication

1. **Public quick replication:** `python3 scripts/public_quickcheck.py` verifies export identity; `./reproduce_tables.sh` independently reads the author workbook, recalculates its H–L moments, checks the saved 18-cell aggregate evidence, and creates two clearly labelled diagnostic SVGs. It does **not** train models or recreate the original paper's figures.
2. **Full re-estimation:** `./reproduce_everything.sh` is the one-command 18-cell route **after** separately authorized inputs and the exact required MATLAB helpers have been installed. The public checkout deliberately omits those third-party files. Production preflight fails if inputs, helpers, MATLAB or required tests are missing. A fresh full run from this public checkout has not been claimed as completed; see [QUICKSTART.md](QUICKSTART.md).

The original controlled repository remains private and unchanged. No private Git history, run root, or restricted raw-data file was imported into this repository. The current mapping covers the published **original** paper; a final revisit-manuscript map and release tag await a frozen manuscript and author approval.
