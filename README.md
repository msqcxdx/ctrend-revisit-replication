# CTREND Revisit: public replication materials

This is a clean-history, rights-screened public companion to the CTREND revisit. It is **not** a copy of the controlled research repository, and a clone does **not** include the licensed CoinMarketCap (CMC) price panel or the complete 18-run MATLAB archives.

The main information-set problem in the published CTREND program is a weekly fallback that can read an observation later than the week being constructed. The revisit separates that timing correction (M2) from the broader statistical and portfolio-accounting audit (M1). Fixing the identified future-data channels alone does not erase the principal gross mean in these experiments; risk, sample support, asset exposure and other definitions matter. These are paired designs on one historical vendor snapshot, not independent samples or evidence of executable trading profits.

Start with [PAPER_REPLICATION.md](PAPER_REPLICATION.md) for the research question and result map, [QUICKSTART.md](QUICKSTART.md) for a clean-clone check, and [DATA_AVAILABILITY.md](DATA_AVAILABILITY.md) before attempting a full run. [README_CN.md](README_CN.md) is the Chinese overview. [KNOWN_LIMITATIONS.md](KNOWN_LIMITATIONS.md) states interpretation limits.

## What is here

- `engines/`, `config/`, `scripts/`, `postprocessing/`, `analysis/`, `tests/`: the frozen method code and orchestration copied from controlled source commit `58c8bad72d318eb7f17610084cc826bfbbbe9511` (file hashes in `provenance/SOURCE_FILE_MAP.csv`).
- `reference/dataverse_files.zip`: the original author-deposited comparison package from [Harvard Dataverse, doi:10.7910/DVN/NTIVT8](https://doi.org/10.7910/DVN/NTIVT8), whose dataset metadata identifies CC0 1.0. Its embedded `fGRS.m` retains a separate BSD notice. This reference is not our input-market-data license.
- `results/comparisons/`: compact, non-asset-level comparison tables, the author-published factor series extracted from the reference workbook, and an inventory of figures. A figure inventory is **not** the figures themselves.
- `provenance/`: a byte-level link to the controlled source and the accepted research-run IDs/hashes, without private run paths.

The `P` axis compares no added uniform missing-data fill (P0) with one documented OHLCV convention (P1). The `M` axis compares published-code scientific definitions (M0), bounded timing/settlement repair (M2), and the broader audit (M1). The `D` axis compares the original CMC universe (D0), whole-history exclusion of INNBCL/CMCID 3787 (D1), and that exclusion plus a frozen set of 27 event-exposed assets (D2). D1/D2 are retrospective sensitivity designs, **not** live investability screens.

## Two levels of replication

1. **Public quick check:** `python3 scripts/public_quickcheck.py`. This checks permitted files, identities, the paper factor moments and the 18-way summary without MATLAB or vendor data. It does not train the models or regenerate all paper tables.
2. **Full re-estimation:** a separately authorized, matching input bundle, MATLAB R2023b Update 11 and the listed toolboxes are required. The controlled complete workflow uses `./reproduce_everything.sh`; see [QUICKSTART.md](QUICKSTART.md). The public source subset deliberately omits two externally supplied MATLAB helpers and raw vendor data, so the public checkout by itself cannot pass the full production preflight.

The original controlled repository remains private and unchanged. No private Git history, run root, or restricted raw-data file was imported into this repository.
