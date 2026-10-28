# Quickstart

## Public check: no MATLAB or vendor data

Use Python 3.10 or newer, Bash and `rg` (ripgrep):

```bash
python3 scripts/public_quickcheck.py
./run_all.sh test
./reproduce_tables.sh
```

The first command verifies public-file hashes, 18 experiment identities, headline/long-table agreement and the original-paper item map. The second executes actual offline source and table-reproduction tests. The third creates a fresh `outputs/public_tables/` directory with: recalculated moments from the original author workbook; checked and reshaped saved experimental headline/main-table cells; two *new diagnostic* SVGs; and input/output SHA-256 inventories. It does not recompute the eighteen model fits or the paper's original figures. To repeat it, pass another fresh output directory. CI runs this lightweight scope.

## Full model re-estimation

The full model workflow is `./reproduce_everything.sh`. It is a separate, expensive operation and must not be confused with the commands above. It requires:

- the exact authorized CMC OHLCV/market-cap snapshot plus separately obtained Fama–French, LTW and UCRY inputs, installed in the expected `data/raw/common/` schema and verified against `data/RAW_INPUTS.sha256`;
- MATLAB R2023b Update 11 with Econometrics, Financial, Optimization, Parallel Computing, and Statistics and Machine Learning Toolboxes;
- separately licensed `regstats2.m` and `parfor_wait.m`, absent from this public export because their redistribution permissions were not established for this release;
- a Linux machine exposing at least 128 logical CPUs to the process, sufficient memory/disk for 18 independent runs, and Python dependencies from `environment/requirements-analysis.txt`;
- the local source files in this checkout plus the separately supplied data and helpers. The controlled annotated mirrors and private acceptance archives are not prerequisites for a **new** full run.

Install the 11-file input bundle with `python3 scripts/data_bundle.py install --source /absolute/authorized/cmc-bundle --aux-data-dir /absolute/authorized/auxiliary --root "$PWD"` (or the documented complete-bundle form), then install **lawfully obtained, exact-version** `regstats2.m` and `parfor_wait.m` in each of `engines/M0/base/Utils/`, `engines/M1/base/Utils/`, `engines/M2/base/Utils/`, and `engines/P0_M0/base/Utils/`. The public preflight compares helper hashes to the accepted source inventory; a newer or different helper is not silently substituted. Next run:

```bash
export MATLAB_BIN=/absolute/path/to/R2023b/bin/matlab
./run_all.sh preflight
./reproduce_everything.sh
```

`preflight` fails clearly if licensed inputs, helper versions, MATLAB or a test are missing. `./run_all.sh preflight` is **not** expected to pass on a code-only clone. `./reproduce_everything.sh` drives all 18 pipelines, verifies registrations and produces a fresh report under `outputs/reproduction/`; its `REPRODUCTION_COMPLETE.json` is written only after every step succeeds. This public-export route has not been validated by a new 18-cell production run and is not an attestation that a new data vintage will reproduce the frozen numbers.

See [DATA_AVAILABILITY.md](DATA_AVAILABILITY.md) and [THIRD_PARTY_MATERIALS.csv](THIRD_PARTY_MATERIALS.csv) before obtaining any input. A different market-data provider or vintage will not reproduce the frozen hashes or, necessarily, the reported numbers. The documented scripts do not confer permission to collect or redistribute any provider's data.
