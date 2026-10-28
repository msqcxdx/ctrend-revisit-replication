# Quickstart

## Public check: no MATLAB or vendor data

Use Python 3.10 or newer:

```bash
python3 scripts/public_quickcheck.py
```

The command verifies the public source-file ledger, 18 experiment identifiers, headline/long-table agreement, table/figure map coverage, and independently recomputes four moments from the author-published weekly CTREND factor. It does not recompute the eighteen model fits or every published table. CI runs only this lightweight scope.

## Full model re-estimation

The full controlled workflow is `./reproduce_everything.sh`. It is a separate, expensive operation and must not be confused with the command above. It requires:

- the exact authorized CMC OHLCV/market-cap snapshot plus separately obtained Fama–French, LTW and UCRY inputs, installed in the expected `data/raw/common/` schema and verified against `data/RAW_INPUTS.sha256`;
- MATLAB R2023b Update 11 with Econometrics, Financial, Optimization, Parallel Computing, and Statistics and Machine Learning Toolboxes;
- separately licensed `regstats2.m` and `parfor_wait.m`, absent from this public export because their redistribution permissions were not established for this release;
- the complete controlled code/annotation package and sufficient CPU, RAM and disk. This public checkout is a reviewable source subset, not a turnkey reproduction of the 18 accepted runs.

See [DATA_AVAILABILITY.md](DATA_AVAILABILITY.md) and [THIRD_PARTY_MATERIALS.csv](THIRD_PARTY_MATERIALS.csv) before obtaining any input. A different market-data provider or vintage will not reproduce the frozen hashes or, necessarily, the reported numbers. The documented scripts do not confer permission to collect or redistribute any provider's data.
