# Validation scope for this public checkout

On 2026-10-28 UTC, the public export was generated into a new empty directory
from controlled source commit `58c8bad72d318eb7f17610084cc826bfbbbe9511`.
The generated `SOURCE_FILE_MAP.csv` and `PUBLIC_SHA256SUMS` matched the working
public export byte-for-byte. The local test environment was Linux x86-64,
Python 3.12.12, Bash 5.1.16 and ripgrep 15.2.0.

The following commands were run in the **fresh export**:

```bash
./run_all.sh test
./reproduce_tables.sh /absolute/fresh/output/directory
```

Both exited successfully. The offline suite reported `PUBLIC_OFFLINE_TESTS_OK`,
including nine-cell source materialization, engine/topology and M1 inventory
guards, P0/M2 volume and consumer contracts, a synthetic data-bundle interface
test, and the public table-reproduction test. The second command independently
decoded the original author workbook and recalculated its 371 finite weekly
returns, mean, t statistic and annualized Sharpe. It checked and rearranged
894 saved main-table cells for the eighteen experiments and produced two new
diagnostic SVGs, with input and output SHA-256 inventories. It did **not**
re-estimate any experimental model.

On a code-only export, `./run_all.sh preflight` correctly stopped at the missing
licensed input bundle. No MATLAB production run or eighteen-cell clean-room
re-estimation is claimed for this public checkout. That route still requires
separately authorized data, the exact external helpers, a licensed MATLAB
installation and sufficient computing resources. The accepted eighteen-run
identities and hashes refer to the unchanged controlled archive, not to runs
performed by the public quick check.
