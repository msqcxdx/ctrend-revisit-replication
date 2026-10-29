# Validation scope for this public checkout

On 2026-10-29 UTC, the public export was generated into a new empty directory
from controlled source commit `e634a51d53cfb56dccd35d16ce2009bb824cef18`.
The generated `SOURCE_FILE_MAP.csv` and `PUBLIC_SHA256SUMS` matched the working
public export byte-for-byte after the consistent `ctrend`/`CTREND` namespace
normalization. The local test environment was Linux x86-64,
Python 3.12.12, Bash 5.1.16 and ripgrep 15.2.0.

The following commands were run in the **fresh export**:

```bash
./run_all.sh test
./reproduce_tables.sh /absolute/fresh/output/directory
python3 followup_research/model_advantage_direct/test_analysis.py
```

All three exited successfully. The offline suite reported `PUBLIC_OFFLINE_TESTS_OK`,
including nine-cell source materialization, engine/topology and M1 inventory
guards, P0/M2 volume and consumer contracts, a synthetic data-bundle interface
test, the locally installed helper-file contract, and the public table-reproduction
test. The helper test covers the eight documented installation paths, rejects
incorrect helper versions and changed public source, and uses synthetic bytes
without distributing third-party files. The second command independently
decoded the original author workbook and recalculated its 371 finite weekly
returns, mean, t statistic and annualized Sharpe. It checked and rearranged
894 saved main-table cells for the eighteen experiments and produced two new
diagnostic SVGs, with input and output SHA-256 inventories. It did **not**
re-estimate any experimental model.

The direct-model summary check verified its fourteen CSVs, script receipts,
common-support counts and advantage/decomposition identities. The separate
NumPy/SciPy synthetic suite passed nine tests for missing-calendar handling,
singularity, model-difference algebra, pricing inputs, positive tangency
direction, future-training perturbations and an end-to-end fixture. The
authorized numerical calculation was reproduced with the same seed before
export; all fourteen result CSVs matched byte-for-byte. No restricted NPZ input
was exported. See the module's [validation scope](../followup_research/model_advantage_direct/VALIDATION.md)
for the distinction from historical controlled-archive manifest checks.

On a code-only export, `./run_all.sh preflight` correctly stopped at the missing
licensed input bundle. No MATLAB production run or eighteen-cell clean-room
re-estimation is claimed for this public checkout. That route still requires
separately authorized data, the exact external helpers, a licensed MATLAB
installation and sufficient computing resources. The accepted eighteen-run
identities and hashes refer to the unchanged controlled archive, not to runs
performed by the public quick check.
