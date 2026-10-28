# P0 execution layer: nine unfilled P/M/D cells

Public entry: `./run_all.sh experiment P0_M0_D0 production` (or any
other P0 M/D ID). All nine P0 cells are runnable. M0 uses the preserved unfilled
`engines/P0_M0` scientific source; M1/M2 use the no-fill derivation
described below. The common root P/M/D entry supplies cross-P host locking and
public registration.

`P0` omits the uniform OHLC previous-close fill and volume-to-zero input
convention. For M1 and M2, the same-D P0/P1 executable difference is confined
to b01 for M1, and to b01 plus the declared b02 volume block for M2.
P0/M2 retains P0/M0's all-zero/missing-row rule and volume <= 1e-6 screen,
including zero-to-NaN. P1/M0 and P1/M2 preserve explicit zeros. This is a
preprocessing convention, not a future-information repair. In particular,
the frozen mechanical exit calendar, same-leg reinvestment, M1 economic/statistical
separation, M2 timing/settlement definitions, and D-axis exclusions are held fixed.

The nine identities cross `M0`, `M1`, and `M2` with `D0`, `D1`, and `D2`,
all prefixed `P0_`. D1 and D2 intentionally share the
same executable source; their frozen exclusion CSVs differ.

Run all gates first:

```bash
./p0_extension/run_all.sh preflight
```

When MATLAB is available, preflight includes a real P0-M1 `b01ReadData` run
on the packaged raw inputs and passes its resulting checkpoint through the
unchanged production b02 prologue. The all-false auxiliary audit sentinel in
that checkpoint records that P0 filled no input cells; it is not unified
missing-data preprocessing.

Materialize a source without running MATLAB:

```bash
./p0_extension/run_all.sh materialize P0_M1_D0 /absolute/fresh/output
```

Run one full production cell or launch it detached:

```bash
./run_all.sh experiment P0_M1_D0 production
./run_all.sh launch P0_M1_D0
```

Every run starts from the package raw inputs, executes the full M pipeline and
all 3,072 b09 designs, writes an explicit P/M/D launch manifest, and is
registered only after source, DATA, Results, sidecars, output coverage, and
checkpoint identity pass independent verification.
