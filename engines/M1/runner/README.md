# M1 production runner

This directory contains M1 operational tooling and remains outside the frozen
M1 scientific source in `engines/M1/base`. The top-level runner self-binds its
production scripts to a separate immutable snapshot before it takes the global
lock or creates mutable run state. Runtime archives retain the established
`ctrend_corrected_pipeline/` root only as an on-disk compatibility identifier
for completed-run provenance; it is not another method or experiment.

It changes only scheduling and filesystem isolation. Forecast definitions,
outlier handling, portfolio accounting, coverage rules, and every saved
research result continue to come from the packaged `engines/M1/base` source.
Do not add an estimator or empirical convention to this directory.

The canonical pipeline remains unchanged and can still run all 3,072 Table 6
designs in one process. This runner accelerates the same `b09` code by:

1. extracting eight byte-identical copies of the M1 runtime package;
2. linking every copy to the same certified weekly `DATA/` files;
3. assigning disjoint contiguous chunks of combinations to eight isolated
   result directories;
4. running eight persistent MATLAB clients with 15 process workers each
   (120 workers plus eight clients on the 128-core host);
5. validating every combo's exact MAT-file SHA-256 and merging only matching
   run/data/code/design provenance into run-local canonical staging.

No shard shares or concurrently writes a manifest. The merge step requires
exactly one byte-certified result and sidecar for every combo and enforces the
canonical pipeline's predeclared 50% eligible-week coverage floor with zero
unexpected failures.

Launch:

```bash
B09_ORCHESTRATOR_PID=$$
B09_ORCHESTRATOR_START_TICKS="$(awk '{print $22}' \
  "/proc/$B09_ORCHESTRATOR_PID/stat")"
export B09_ORCHESTRATOR_PID B09_ORCHESTRATOR_START_TICKS
RESEARCH_RUN_ID=<the-run-id-of-canonical-combo-1> ./launch_b09_shards.sh
```

When `FIRST_COMBO=2` (the normal resume mode), `RESEARCH_RUN_ID` must equal
the ID already stored in canonical combo 1. A fresh all-combo run may omit it
and receive a newly generated UUID. The bound shell must remain alive while
the shards run; the end-to-end wrapper establishes this lease automatically.

Inspect the latest run:

```bash
./check_b09_shards.sh
```

After all eight shard supervisors finish successfully, merge:

```bash
./merge_b09_shards.sh /absolute/path/to/the/run_directory
```

If a particular range later needs to be rerun, leave `engines/M1/base`
untouched and use the staged copy and manifest of one stopped shard:

```bash
./run_b09_range.sh /absolute/path/to/the/run_directory SHARD START END
```

This recomputes only the requested inclusive range with the same research run
ID, code fingerprint, data build, and isolated result directory.

The run directory and research run ID are written to
`latest_run_path.txt` and `latest_research_run_id.txt`.

## Full 128-core orchestration

For a direct internal M1 recomputation, use:

```bash
./build_runtime_package.sh \
  <PROJECT_ROOT>/ctrend_m1_pipeline.tar.gz

./run_production.sh \
  <PROJECT_ROOT>/ctrend_m1_pipeline.tar.gz
```

The package builder excludes `DATA/`, `Results/`, logs, and MATLAB
preferences. The wrapper refuses a package whose executable source inventory
differs from the current `engines/M1/base` tree. Before taking the global lock
or creating a run, the top-level runner re-executes from its own immutable
snapshot; package, source, runtime, DesignChoices and raw-source mappings are
then sealed and rechecked at their publication boundaries.

Each recomputation writes to a new run root. Results remain below
`results.staging/` until the full 3,072-combination manifest plus 3,072 payload
sidecars, main outputs, supplementary outputs, provenance IDs, phase records,
and SHA-256 inventories pass. The wrapper constructs one immutable bundle
containing `DATA`, `Results`, `DesignChoices` and `RUN_COMPLETE`, then atomically
switches the single `.canonical/current` pointer. Failed activation validation
restores the preceding pointer. `latest_started_run_path.txt` may therefore
identify a failed or active run, while `latest_successful_run_path.txt` always
identifies the last published run.

The wrapper runs common preprocessing with up to 64 workers, overlaps
independent baseline-downstream and canonical-combo work where safe, assigns
Table 6 combinations 2–3,072 to eight persistent 15-worker shards, merges them,
then checks the actual b05/b09 baseline equality and the disclosed zero-gap Figure
B.2 payload before running `b10`. A second result phase verifies the paper and
strict-common-week Table 6 dimensions, support gates and provenance before the
explicitly parameterized supplementary variants.
During b09, the main orchestrator log reports completed payloads out of 3,072,
percentage complete, and each shard's state and payload count every monitor
interval; `check_b09_shards.sh` additionally shows its most recent combo line.
Each production shard is bound to the orchestrator's Linux PID and process
start tick. If the orchestrator is killed in a way that bypasses shell traps,
the shard detects the missing or reused PID on its next heartbeat, fails
closed, and stops its independently grouped MATLAB client and workers.
The physical combo 1 manifest seed and every shard share one research-design
run ID. Physical combo 1 is not the paper/b05 baseline; consumers and tests
locate that row by its complete design fields (setting 517 in the 2026-07-20
manifest).

Every MATLAB or external phase runs in its own process group. After a
successful leader exit, `PHASE_EXIT_GRACE_SECONDS` permits normal pool workers
to drain without a signal. A group that persists beyond the bounded grace is
terminated and the phase fails closed; failed leaders receive immediate
owned-group cleanup.

## Script roles

- `run_production.sh`: end-to-end high-throughput coordinator;
- `run_owned_process.sh`: run one phase in its own session/process group and
  atomically record owner, pid, status and completion evidence;
- `build_runtime_package.sh`: build a clean, source-matched runtime
  archive without data, results, logs, or preferences;
- `launch_b09_shards.sh`: create eight isolated packaged-code workspaces and
  assign disjoint Table 6 chunks;
- `run_b09_shard.sh`: execute the ranges assigned to one shard, with retry
  limited to recognized MATLAB/pool startup failures;
- `check_b09_shards.sh`: display running/completed state and latest progress;
- `run_b09_range.sh`: recompute one explicit missing or failed range without
  modifying the frozen M1 source;
- `resume_b09_legacy_four_shards.sh`: validate and resume an exact historical
  four-shard recovery plan; it is not the current 8-by-15 production path;
- `merge_b09_shards.sh` and `merge_b09_shards.m`: reject mixed/stale/incomplete
  shards and move the unique byte-certified 3,072-combination set into run-local
  canonical staging;
- `tests/test_runner_fault_controls.sh`: deterministic mutation, timeout,
  process-group cleanup, completion and rollback fault-injection tests.

## Runtime files

`runs/`, `latest_run_path.txt`, and `latest_research_run_id.txt` are generated
shard state. The end-to-end wrapper stores its complete logs, staged source,
shard checkpoints, final results, and `RUN_COMPLETE` manifest under the
run-specific root. MATLAB preference and parallel-job directories are
ownership-marked temporary state and are removed only after realpath/prefix
validation. Generated `latest*.txt`, superseded launcher logs and failed run
roots are not production source and may be removed after verifying that they
are neither active nor the target of `.canonical/current`.
