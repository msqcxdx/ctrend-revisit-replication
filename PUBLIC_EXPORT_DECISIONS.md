# Public-export decision record

Source identity: controlled repository commit `e634a51d53cfb56dccd35d16ce2009bb824cef18`. The deterministic copier is `scripts/build_public_export.py`; its copied files are listed with controlled and public hashes in `provenance/SOURCE_FILE_MAP.csv`. The public-owned guides/adapters and all copied files are covered by `provenance/PUBLIC_SHA256SUMS`. The public checkout uses `ctrend`/`CTREND` consistently, preserves executable file modes, and lists its public-only overrides. The original author's reference ZIP and the accepted 18-run results are separate, unmodified evidence.

A clean export from an authorized local copy of the controlled commit can be built with `python3 scripts/build_public_export.py --source /absolute/controlled/repository --target /absolute/fresh/public-export`. The source must be clean and at the exact commit. No Git history, raw vendor data or private output tree is imported. The copier applies the documented public namespace, listed overrides and matching base-file inventories; it does not change model calculations. The original 18-run hashes identify archived research outputs and are not expected to equal public source-file hashes.

## Included

- P/M/D MATLAB and orchestration source, configuration, analysis code, source-level tests, and the 12-KB, design-only `engines/M1/base/DesignChoices.mat` required for M1 runtime packaging. The public preflight/test scripts and `tests/README.md` specify checks available in this checkout, without claiming to run withheld acquisition or annotation suites; `postprocessing/README.md` explains the absence of accepted private baselines. The four override pairs have different source/public hashes in the ledger and do not change any model calculation.
- The original Fieberg et al. Dataverse ZIP, under its dataset-specific CC0 metadata and the embedded third-party notice. Its 68 regular ZIP members were compared byte-for-byte by MD5 against all 68 file checksums returned by the Harvard Dataverse dataset API on 2026-10-28: zero missing, modified or extra members.
- Author-published factor returns and compact, non-asset-level saved research summaries, including the paper-item table/figure inventory and the 18 run IDs with hashes.
- A tested quick-replication command that decodes the author workbook again, recalculates its moments, checks and reshapes saved aggregate cells, and emits two explicitly diagnostic SVGs without MATLAB or vendor inputs.
- Direct model-comparison code, guides, aggregate estimates, date-only support
  audits and path-free receipts in `followup_research/model_advantage_direct/`.
  The exporter explicitly selects top-level Python/Markdown files and
  `results/` CSV/JSON files, never its private input directory.

## Excluded

- All original CMC price/volume/market-cap matrices, auxiliary LTW/Fama–French/UCRY files, and downloader code whose collection route needs channel-specific authorization review.
- Detailed per-asset positions and returns, source-price panels, complete MATLAB run roots, logs, runtime directories, large follow-up payloads, and internal path receipts.
- Direct-comparison NPZ inputs and factor/test-asset return panels. Their hashes
  identify authorized inputs but do not provide the observations or permission
  to redistribute them.
- Controlled copies of `regstats2.m` and `parfor_wait.m`: file-specific redistribution rights for these exact copies were not established. A full user must obtain them under the upstream terms.
- The controlled repository's Git history and duplicate annotated source mirrors. These mirrors are not runtime dependencies; the public source-plus-data route still requires the external inputs, exact helper versions, MATLAB and substantial computing resources. No full clean-room rerun is claimed.

## Scope of validation

`python3 scripts/public_quickcheck.py` checks this export and saved summaries only. `./reproduce_tables.sh` makes one fresh author-factor calculation, but only redraws/transcribes experimental saved aggregates; it does not retrain the 18 models. `./run_all.sh preflight` is a different gate and fails until real licensed inputs, exact helpers and MATLAB are installed. `results/comparisons/source_tables/RUN_IDENTITIES_18.csv` references accepted controlled runs by identity/hash, not by public download URL. No public DOI, permission to redistribute CMC raw data, or claim of real executable investment returns is implied.

The current `TABLE_FIGURE_MAP.csv` maps the published original CTREND paper (19 tables, seven figures). The taskbook mentions 26 tables and five figures for a manuscript draft, but the accessible draft/archived source inventory did not support assigning those identifiers reliably. A final revisit-manuscript map remains pending its frozen table/figure list; no identifiers were invented.
