# Tests and result verification

## Public checkout: offline tests

```bash
./run_all.sh test
```

This command needs Python, Bash and ripgrep, but does not start MATLAB or
download data. It checks:

- Shell syntax, distributed-file integrity, source mappings and the eighteen-cell
  experiment registry.
- The nine M/D source materializations and the six P0 M1/M2 derivations, including
  asset-exclusion placement and the P0/M2 volume policy.
- Engine guards, M1 inventory contracts, M2 return consumers and CPU-capacity
  detection.
- Synthetic data-bundle installation and the eight documented external-helper
  locations. Installed helpers must match the required versions; they are not
  part of the public distribution.
- Saved aggregate consistency, paper-item coverage, and the author's factor
  series decoded from the original workbook.

Success is reported as `PUBLIC_OFFLINE_TESTS_OK`. It means these checks passed;
it does not mean that the eighteen MATLAB experiments were rerun, that their
full private result trees were verified, or that a downloader was tested.

For a separate reconstruction of the distributed summaries, use:

```bash
./reproduce_tables.sh /absolute/fresh/output/directory
```

This recalculates the author's factor statistics and arranges the saved
experimental aggregates. It does not fit models or recreate per-asset data.

## Full empirical execution

After installing authorized inputs and the required helpers as described in
`QUICKSTART.md`, run `./run_all.sh preflight`. This checks the actual local data
bundle and helper versions, then runs MATLAB environment and unit tests,
including parallel/serial equivalence and a small b09 runner smoke test.
Missing inputs, helpers or MATLAB are reported as missing prerequisites; a
code-only checkout cannot pass this production preflight.

`./reproduce_everything.sh` orchestrates the complete eighteen-experiment route.
`./run_all.sh verify-all` checks locally generated experiment registrations and
their result inventories. It is intended for completed local runs, not for a
fresh checkout containing only the public aggregate CSVs. See `QUICKSTART.md`
for inputs, software and execution settings.

## Additional audit utilities

Some source files in this directory describe checks against the controlled
research archive. They are retained for methodological inspection but are not
called by the public offline suite. In particular:

- `tests/result_checks/run_publication_checks.sh` and its snapshot tests need
  the controlled compact-result tree, accepted-run receipts, and detailed
  diagnostic tables. The public aggregate CSVs are not a substitute.
- Annotation-equivalence and annotation-coverage tests need the separate
  annotated-source mirror, which is not distributed here.
- Controlled documentation-layout and method-boundary tests can require the
  controlled document set and extracted original-source tree.

These utilities are not standalone public-checkout tests. The commands above,
`tests/run_tests.sh`, and `scripts/preflight.sh` define the public test surface;
neither entry point claims to run omitted acquisition or annotation suites.
