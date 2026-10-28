#!/usr/bin/env python3
"""Refit the accepted M1/M2 baseline model under future-only E05 shocks.

This is an isolated audit, not a replacement production run. Each cell uses
its own MATLAB client, worker pool, preferences and job directory. Accepted
inputs are read-only and are hashed before and after the intervention.
"""

from __future__ import annotations

import argparse
from concurrent.futures import ThreadPoolExecutor, as_completed
import csv
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import time
import uuid

from run_e06_upstream_hybrids import ROOT, quote, sha


ENGINE = {"M1": "cttrend_corrected_pipeline",
          "M2": "cttrend_lookahead_only_pipeline"}
ALREADY_TESTED = {"P0_M1_D1", "P0_M2_D1"}


def run_cell(eid: str, identity: dict, work: Path, matlab: Path,
             workers: int, cutoff: int) -> dict:
    method = eid.split("_")[1]
    parent = Path(identity["accepted_run_root"])
    source = parent / "runtime" / ENGINE[method]
    result = Path(identity["result_root"]) / "CTREND/CTREND_Base.mat"
    weekly = [p for folder in ("data", "data.staging")
              if (p := parent / folder / "bCharacteristicsOLHC_Combo1.mat").is_file()]
    if len(weekly) != 1:
        raise RuntimeError(f"Expected one accepted weekly input for {eid}")
    inputs = [parent / "RUN_COMPLETE", source / "b05CreateCTREND.m",
              result, weekly[0]]
    before = {str(p): sha(p) for p in inputs}
    if before[str(parent / "RUN_COMPLETE")] != identity["run_complete_sha256"]:
        raise RuntimeError(f"Accepted parent identity changed for {eid}")
    cell = work / eid
    cell.mkdir()
    (cell / "jobs").mkdir()
    (cell / "prefs").mkdir()
    output = cell / "production_b05_future_perturbation.csv"
    expr = (f"addpath('{quote(ROOT / 'scripts')}'); c=parcluster('local');"
            f"c.JobStorageLocation='{quote(cell / 'jobs')}';"
            f"c.NumWorkers={workers};parpool(c,{workers});"
            f"test_e05_production_model_perturbation('{quote(source)}',"
            f"'{quote(result)}','{quote(output)}',{cutoff});"
            "delete(gcp('nocreate'));")
    env = {**os.environ, "MATLAB_PREFDIR": str(cell / "prefs"),
           "OMP_NUM_THREADS": "1", "OPENBLAS_NUM_THREADS": "1",
           "MKL_NUM_THREADS": "1"}
    start = time.time()
    print(f"E05_EXTENDED_START {eid} workers={workers}", flush=True)
    with (cell / "pipeline.log").open("w") as log:
        rc = subprocess.run([str(matlab), "-licmode", "onlinelicensing",
                             "-nodisplay", "-nosplash", "-batch", expr],
                            stdout=log, stderr=subprocess.STDOUT, env=env).returncode
    if before != {str(p): sha(p) for p in inputs}:
        raise RuntimeError(f"Accepted input changed during {eid}")
    if rc or not output.is_file():
        raise RuntimeError(f"{eid} MATLAB rc={rc}; see {cell / 'pipeline.log'}")
    rows = list(csv.DictReader(output.open(newline="")))
    if len(rows) != 3 or {r["variant"] for r in rows} != {
            "control", "future_values", "future_missingness"}:
        raise RuntimeError(f"Incomplete E05 variants for {eid}")
    if any(int(r["changed_past_predictions"]) or
           int(r["changed_past_beta_cells"]) or
           int(r["changed_past_selection_cells"]) for r in rows):
        raise RuntimeError(f"Future shock changed a past model result in {eid}")
    print(f"E05_EXTENDED_DONE {eid} seconds={time.time()-start:.1f}", flush=True)
    return {"experiment_id": eid, "research_run_id": identity["research_run_id"],
            "accepted_input_hashes": before, "result": str(output),
            "result_sha256": sha(output), "seconds": time.time()-start,
            "variant_rows": rows}


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--work-root", type=Path, required=True)
    parser.add_argument("--matlab", type=Path, required=True)
    parser.add_argument("--workers-per-cell", type=int, default=28)
    parser.add_argument("--concurrent-cells", type=int, default=4)
    parser.add_argument("--cutoff", type=int, default=202016)
    parser.add_argument("--experiment", action="append")
    args = parser.parse_args()
    if not args.matlab.is_file() or not os.access(args.matlab, os.X_OK):
        raise FileNotFoundError(args.matlab)
    cpu = len(os.sched_getaffinity(0))
    if (args.concurrent_cells < 1 or args.workers_per_cell < 1 or
            args.concurrent_cells * (args.workers_per_cell + 1) > cpu):
        raise ValueError("MATLAB process budget exceeds CPU affinity")
    work = args.work_root.resolve()
    if work.exists():
        raise FileExistsError(work)
    if shutil.disk_usage(work.parent).free < 12 * 2**30:
        raise RuntimeError("Need at least 12 GiB free before E05 audit")
    identities = {r["experiment_id"]: r for r in csv.DictReader(
        (ROOT / "outputs/E11/accepted_run_paths.csv").open(newline=""))}
    experiments = args.experiment or [f"P{p}_M{m}_D{d}"
                                      for p in (0, 1) for m in (1, 2)
                                      for d in (0, 1, 2)
                                      if f"P{p}_M{m}_D{d}" not in ALREADY_TESTED]
    if len(experiments) != len(set(experiments)) or any(
            re.fullmatch(r"P[01]_M[12]_D[012]", eid) is None or
            eid not in identities for eid in experiments):
        raise ValueError("Unsupported, duplicate, or unaccepted experiment")
    work.mkdir()
    receipt = {"research_run_id": str(uuid.uuid4()), "status": "running",
               "scope": "isolated_b05_baseline_future_input_shock_not_production",
               "driver_sha256": sha(Path(__file__)),
               "matlab_test_sha256": sha(ROOT / "scripts/test_e05_production_model_perturbation.m"),
               "experiments": experiments, "workers_per_cell": args.workers_per_cell,
               "concurrent_cells": args.concurrent_cells, "results": [], "errors": []}
    receipt_path = work / "receipt.json"
    receipt_path.write_text(json.dumps(receipt, indent=2) + "\n")
    with ThreadPoolExecutor(max_workers=args.concurrent_cells) as pool:
        futures = {pool.submit(run_cell, eid, identities[eid], work, args.matlab,
                               args.workers_per_cell, args.cutoff): eid
                   for eid in experiments}
        for future in as_completed(futures):
            eid = futures[future]
            try:
                receipt["results"].append(future.result())
            except BaseException as exc:
                receipt["errors"].append({"experiment_id": eid, "error": repr(exc)})
                print(f"E05_EXTENDED_FAILED {eid} {exc!r}", flush=True)
            receipt_path.write_text(json.dumps(receipt, indent=2) + "\n")
    receipt["status"] = "complete" if not receipt["errors"] else "failed"
    receipt_path.write_text(json.dumps(receipt, indent=2) + "\n")
    if receipt["errors"]:
        raise RuntimeError("One or more E05 cells failed; preserve work root")
    print(f"E05_EXTENDED_COMPLETE cells={len(experiments)}", flush=True)


if __name__ == "__main__":
    main()
