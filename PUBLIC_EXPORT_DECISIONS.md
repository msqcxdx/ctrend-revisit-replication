# Public-export decision record

Source identity: controlled repository commit `58c8bad72d318eb7f17610084cc826bfbbbe9511`. The deterministic copier is `scripts/build_public_export.py`; its 717 copied files are listed with controlled and public hashes in `provenance/SOURCE_FILE_MAP.csv`. A separate all-public-file inventory is `provenance/PUBLIC_SHA256SUMS`. Original 18-run `RUN_COMPLETE`, acceptance receipts, research run IDs and results were not edited.

## Included

- P/M/D MATLAB and orchestration source, configuration, analysis code and source-level tests. One preflight regex literal was redacted; it has no numerical role.
- The original Fieberg et al. Dataverse ZIP, under its dataset-specific CC0 metadata and the embedded third-party notice. Its 68 regular ZIP members were compared byte-for-byte by MD5 against all 68 file checksums returned by the Harvard Dataverse dataset API on 2026-10-28: zero missing, modified or extra members.
- Author-published factor returns and compact, non-asset-level saved research summaries, including the paper-item table/figure inventory and the 18 run IDs with hashes.
- Lightweight checks that run without MATLAB or licensed inputs.

## Excluded

- All original CMC price/volume/market-cap matrices, auxiliary LTW/Fama–French/UCRY files, and downloader code whose collection route needs channel-specific authorization review.
- Detailed per-asset positions and returns, source-price panels, complete MATLAB run roots, logs, runtime directories, large follow-up payloads, and internal path receipts.
- Controlled copies of `regstats2.m` and `parfor_wait.m`: file-specific redistribution rights for these exact copies were not established. A full user must obtain them under the upstream terms.
- The controlled repository's Git history and duplicate annotated source mirrors. Their omission reduces rights and history risk but means this public subset is not a turnkey source archive for complete MATLAB re-estimation.

## Scope of validation

`python3 scripts/public_quickcheck.py` checks this export and saved summaries only. It does not make a fresh empirical estimate. `results/comparisons/source_tables/RUN_IDENTITIES_18.csv` references accepted controlled runs by identity/hash, not by public download URL. No public DOI, permission to redistribute CMC raw data, or claim of real executable investment returns is implied.

The current `TABLE_FIGURE_MAP.csv` maps the published original CTREND paper (19 tables, seven figures). The taskbook mentions 26 tables and five figures for a manuscript draft, but the accessible draft/archived source inventory did not support assigning those identifiers reliably. A final revisit-manuscript map remains pending its frozen table/figure list; no identifiers were invented.
