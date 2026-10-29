#!/usr/bin/env python3
"""Audit future-only daily quote shocks in the ten remaining M1/M2 cells.

The accepted b01 and b02 files are read-only. The probe executes the actual
accepted b02 source body from its original directory, while routing its input
to the accepted absolute DATA path and its outputs to isolated audit folders.
No raw download or b01 reconstruction is certified by this test.
"""

from __future__ import annotations

import argparse
import csv
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import uuid

from run_e05_b02_perturbation import compare, function_text
from run_e06_upstream_hybrids import ROOT, quote, sha


ENGINE = {"M1": "ctrend_corrected_pipeline",
          "M2": "ctrend_lookahead_only_pipeline"}
ALREADY_TESTED = {"P0_M1_D1", "P0_M2_D1"}


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--work-root", type=Path, required=True)
    parser.add_argument("--matlab", type=Path, required=True)
    parser.add_argument("--workers", type=int, default=96)
    parser.add_argument("--experiment", action="append")
    args = parser.parse_args()
    if not args.matlab.is_file() or not os.access(args.matlab, os.X_OK):
        raise FileNotFoundError(args.matlab)
    if not 1 <= args.workers < len(os.sched_getaffinity(0)):
        raise ValueError("MATLAB worker budget exceeds CPU affinity")
    work = args.work_root.resolve()
    if work.exists():
        raise FileExistsError(work)
    if shutil.disk_usage(work.parent).free < 12 * 2**30:
        raise RuntimeError("Need at least 12 GiB scratch headroom")
    identities = {r["experiment_id"]: r for r in csv.DictReader(
        (ROOT / "outputs/E11/accepted_run_paths.csv").open(newline=""))}
    experiments = args.experiment or [f"P{p}_M{m}_D{d}"
                                      for p in (0, 1) for m in (1, 2)
                                      for d in (0, 1, 2)
                                      if f"P{p}_M{m}_D{d}" not in ALREADY_TESTED]
    if len(experiments) != len(set(experiments)) or any(
            re.fullmatch(r"P[01]_M[12]_D[012]", eid) is None or
            eid not in identities for eid in experiments):
        raise ValueError("Unsupported, duplicate or unaccepted experiment")
    output = ROOT / "outputs/E05/production_b02_daily_future_perturbation_extended.csv"
    if output.exists():
        raise FileExistsError(output)
    work.mkdir()
    receipt = {"research_run_id": str(uuid.uuid4()), "status": "running",
               "scope": "accepted_b01_daily_panel_to_real_b02_not_raw_download_or_b01_rebuild",
               "driver_sha256": sha(Path(__file__)),
               "base_probe_sha256": sha(ROOT / "scripts/run_e05_b02_perturbation.py"),
               "experiments": experiments, "workers": args.workers,
               "results": []}
    receipt_path = work / "receipt.json"
    receipt_path.write_text(json.dumps(receipt, indent=2) + "\n")
    rows = []
    try:
        for eid in experiments:
            identity = identities[eid]
            parent = Path(identity["accepted_run_root"])
            source = parent / "runtime" / ENGINE[eid.split("_")[1]]
            data = [p for folder in ("data", "data.staging")
                    if (p := parent / folder).is_dir() and
                    (p / "b0DataOLHC.mat").is_file()]
            if len(data) != 1:
                raise RuntimeError(f"Expected one accepted daily input: {eid}")
            data = data[0]
            originals = [parent / "RUN_COMPLETE", source / "b02CalculateIndicators.m",
                         data / "b0DataOLHC.mat",
                         data / "bCharacteristicsOLHC_Combo1.mat"]
            before = {str(p): sha(p) for p in originals}
            if before[str(parent / "RUN_COMPLETE")] != identity["run_complete_sha256"]:
                raise RuntimeError(f"Accepted marker changed: {eid}")
            folder = work / eid
            folder.mkdir()
            for child in ("jobs", "prefs", "control", "future_values"):
                (folder / child).mkdir()
            text = function_text(source / "b02CalculateIndicators.m")
            text, n = re.subn(r"sInDataPath\s*=\s*'\./DATA/';",
                              f"sInDataPath='{quote(data)}/';", text, count=1)
            if n != 1:
                raise RuntimeError(f"Accepted b02 input-path anchor differs: {eid}")
            helper = folder / "e05_real_b02_probe.m"
            helper.write_text(text)
            expr = (f"cd('{quote(source)}');addpath('{quote(folder)}');"
                    f"c=parcluster('local');c.JobStorageLocation='{quote(folder / 'jobs')}';"
                    f"c.NumWorkers={args.workers};parpool(c,{args.workers});"
                    f"sAuditOut='{quote(folder / 'control')}';iAuditMode=0;e05_real_b02_probe;"
                    f"sAuditOut='{quote(folder / 'future_values')}';iAuditMode=1;e05_real_b02_probe;"
                    "delete(gcp('nocreate'));")
            env = {**os.environ, "MATLAB_PREFDIR": str(folder / "prefs"),
                   "OMP_NUM_THREADS": "1", "MKL_NUM_THREADS": "1",
                   "OPENBLAS_NUM_THREADS": "1"}
            print(f"E05_B02_EXTENDED_START {eid} workers={args.workers}", flush=True)
            with (folder / "pipeline.log").open("w") as log:
                rc = subprocess.run([str(args.matlab), "-licmode", "onlinelicensing",
                                     "-nodisplay", "-nosplash", "-batch", expr],
                                    stdout=log, stderr=subprocess.STDOUT, env=env).returncode
            if before != {str(p): sha(p) for p in originals}:
                raise RuntimeError(f"Accepted b02 input changed: {eid}")
            if rc:
                raise RuntimeError(f"{eid} b02 probe failed rc={rc}; see {folder / 'pipeline.log'}")
            new_rows = compare(folder / "control/bCharacteristicsOLHC_Combo1.mat",
                               folder / "future_values/bCharacteristicsOLHC_Combo1.mat",
                               data / "bCharacteristicsOLHC_Combo1.mat", eid)
            rows.extend(new_rows)
            receipt["results"].append({"experiment_id": eid,
                                       "research_run_id": identity["research_run_id"],
                                       "accepted_input_hashes": before,
                                       "probe_sha256": sha(helper),
                                       "field_rows": len(new_rows)})
            receipt_path.write_text(json.dumps(receipt, indent=2) + "\n")
            print(f"E05_B02_EXTENDED_DONE {eid} fields={len(new_rows)}", flush=True)
        with output.open("w", newline="") as f:
            writer = csv.DictWriter(f, fieldnames=list(rows[0]))
            writer.writeheader()
            writer.writerows(rows)
        receipt["status"] = "complete"
        receipt["output_sha256"] = sha(output)
        print(f"E05_B02_EXTENDED_COMPLETE cells={len(experiments)}", flush=True)
    except BaseException as exc:
        receipt["status"] = "failed"
        receipt["error"] = repr(exc)
        raise
    finally:
        receipt_path.write_text(json.dumps(receipt, indent=2) + "\n")


if __name__ == "__main__":
    main()
