#!/usr/bin/env python3
"""Refit the 12 accepted M1/M2 baselines solely to record native gates.

Every experiment is copied to a fresh, isolated work root. Accepted source,
weekly inputs and result files are hashed before and after. M1 uses its saved
per-window model status without changing any executable source. M2 receives
only an audit output from its walk-forward helper in the isolated copy. The
derived forecasts, coefficients, selected sets, P&L and complete portfolio
struct must compare bit-for-bit (isequaln) with the accepted parent result.
No b00-b04, b09 or original run directory is written.
"""

from __future__ import annotations

import argparse
import csv
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import time
import uuid

import h5py
import numpy as np


ROOT = Path(__file__).resolve().parents[1]
AUDITOR = ROOT / "native_failure_audit/audit_after_b05.m"
IDENTITIES = ROOT / "outputs/E11/accepted_run_paths.csv"
METHOD_DIR = {"M1": "ctrend_corrected_pipeline",
              "M2": "ctrend_lookahead_only_pipeline"}
CODEBOOK = (
    "not_model_week", "stablecoin_filter", "formation_cap_filter",
    "formation_price_filter", "predictor_panel_not_formed",
    "no_validation_component_forecast", "selection_fit_not_identified",
    "estimated_empty_selected_set", "selected_panel_predictor_missing",
    "selected_component_forecast_unavailable", "unresolved", "forecast_finite",
)


def sha(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as f:
        for chunk in iter(lambda: f.read(2**20), b""):
            h.update(chunk)
    return h.hexdigest()


def exact_bytes(path: Path, old: bytes, new: bytes) -> None:
    source = path.read_bytes()
    if source.count(old) != 1:
        raise ValueError(f"Audit patch anchor is not unique: {path}: {old!r}")
    path.write_bytes(source.replace(old, new))


def instrument_m2(code: Path) -> None:
    """Add branch observations, never alter a numerical assignment."""
    helper = code / "Utils/fWalkforwardCSENET.m"
    exact_bytes(helper,
        b"function [vYhat, mBeta, lSelected, vYhatWts] = fWalkforwardCSENET",
        b"function [vYhat, mBeta, lSelected, vYhatWts, rNativeAudit] = fWalkforwardCSENET")
    old = b"lSelected   = false(iNumIter, iNumIndepVars); % Indicates whether variable was selected"
    exact_bytes(helper, old, old + b"\ncNativeWindowStatus = cell(iNumIter,1); % Isolated E07 status output")
    old = b"lKeepPred  = vBeta > 0;"
    new = (old + b"\n        if any(lKeepPred)\n"
           b"            e07WindowStatus = 'estimated_nonempty_selected';\n"
           b"        else\n"
           b"            e07WindowStatus = 'estimated_empty_selected';\n"
           b"        end")
    exact_bytes(helper, old, new)
    old = b"vYhatTemp       = NaN(size(vYout));"
    exact_bytes(helper, old,
        b"e07WindowStatus = 'validation_all_component_forecasts_nan';\n        " + old)
    old = b"cYhatWts{iIdxI}       = vYhatTempWts;"
    exact_bytes(helper, old, old + b"\n    cNativeWindowStatus{iIdxI} = e07WindowStatus;")
    source = helper.read_bytes()
    final_end = source.rstrip().rfind(b"\nend")
    if final_end < 0 or source.rstrip()[final_end:] != b"\nend":
        raise ValueError("M2 helper does not end in the expected function end")
    source = (source[:final_end] +
        b"\nrNativeAudit = struct();\n"
        b"rNativeAudit.cWindowStatus = cNativeWindowStatus;\n" +
        source[final_end:])
    helper.write_bytes(source)
    b05 = code / "b05CreateCTREND.m"
    exact_bytes(b05,
        b"[vYhatTemp, mBeta, mSelected] = fWalkforwardCSENET",
        b"[vYhatTemp, mBeta, mSelected, ~, rNativeAudit] = fWalkforwardCSENET")


def copied_source_inventory(code: Path) -> dict[str, str]:
    return {str(p.relative_to(code)): sha(p)
            for p in sorted(code.rglob("*.m")) if p.is_file()}


def materialize(source: Path, data: Path, cell: Path, method: str) -> Path:
    code = cell / "source"
    shutil.copytree(source, code,
        ignore=lambda parent, names: {"DATA", "Results"} & set(names)
        if Path(parent) == source else set())
    isolated_data = code / "DATA"
    isolated_data.mkdir()
    names = ["bCharacteristicsOLHC_Combo1.mat",
             "b2EconomicReinvestmentLedger.mat"]
    if method == "M1":
        names += [f"bCharacteristicsOLHC_Combo{i}.mat" for i in (2, 3, 4)]
        names += ["WeeklyDataBuildManifest.mat"]
    for name in names:
        shutil.copy2(data / name, isolated_data / name)
        (isolated_data / name).chmod(0o444)
    (code / "Results/CTREND").mkdir(parents=True)
    if method == "M2":
        instrument_m2(code)
    return code


def audit_axes(output: Path) -> dict[str, int]:
    with h5py.File(output) as h:
        stage = np.asarray(h["e07Stage"], dtype=np.uint8)
        ids = np.asarray(h["e07AssetID"]).ravel()
        weeks = np.asarray(h["e07Dates"]).ravel()
        if stage.shape != (len(weeks), len(ids)) or len(weeks) < 53:
            raise ValueError(f"Native audit axes differ: {output}")
        if np.any(stage[52:] == 10) or np.any(stage[52:] > 11):
            raise ValueError(f"Unresolved or invalid model-week stage: {output}")
        counts = np.bincount(stage[52:].ravel(), minlength=len(CODEBOOK))
        return {CODEBOOK[i]: int(n) for i, n in enumerate(counts) if n}


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--work-root", required=True, type=Path)
    ap.add_argument("--matlab", required=True, type=Path)
    ap.add_argument("--workers", type=int, default=64)
    ap.add_argument("--experiment", action="append")
    args = ap.parse_args()
    work = args.work_root.resolve()
    if work.exists():
        raise FileExistsError(f"Refuse to mix with an existing root: {work}")
    if not AUDITOR.is_file() or not args.matlab.is_file():
        raise FileNotFoundError("Audit source or MATLAB executable missing")
    if args.workers < 1 or args.workers >= len(os.sched_getaffinity(0)):
        raise ValueError("Worker count exceeds observed CPU affinity")
    if shutil.disk_usage(work.parent).free < 15 * 2**30:
        raise RuntimeError("Need at least 15 GiB isolated scratch headroom")
    with IDENTITIES.open(newline="") as f:
        identities = {r["experiment_id"]: r for r in csv.DictReader(f)}
    expected = [f"P{p}_M{m}_D{d}"
                for p in (0, 1) for m in (2, 1) for d in (0, 1, 2)]
    chosen = args.experiment or expected
    if len(chosen) != len(set(chosen)) or any(e not in expected for e in chosen):
        raise ValueError("Only the 12 accepted M1/M2 baseline cells are in scope")
    work.mkdir()
    manifest: dict = {
        "format": "ctrend-e07-isolated-native-failure-audit-v1",
        "research_run_id": str(uuid.uuid4()),
        "status": "running", "scope": "baseline_only_no_b09",
        "experiments": chosen, "workers": args.workers,
        "auditor_sha256": sha(AUDITOR), "driver_sha256": sha(Path(__file__)),
        "results": [],
    }
    journal = work / "manifest.json"
    journal.write_text(json.dumps(manifest, indent=2) + "\n")
    try:
        for eid in chosen:
            method = eid.split("_")[1]
            identity = identities[eid]
            parent = Path(identity["accepted_run_root"])
            results = Path(identity["result_root"])
            source = parent / "runtime" / METHOD_DIR[method]
            data_candidates = [parent / folder for folder in ("data", "data.staging")
                               if (parent / folder / "bCharacteristicsOLHC_Combo1.mat").is_file()]
            if len(data_candidates) != 1:
                raise ValueError(f"Expected one accepted weekly input for {eid}")
            data = data_candidates[0]
            baseline = results / "CTREND/CTREND_Base.mat"
            marker = parent / "RUN_COMPLETE"
            watched = [marker, baseline, source / "b05CreateCTREND.m",
                       source / "Utils/fWalkforwardCSENET.m",
                       source / "DesignChoices.mat",
                       data / "bCharacteristicsOLHC_Combo1.mat",
                       data / "b2EconomicReinvestmentLedger.mat"]
            if method == "M1":
                watched += [data / f"bCharacteristicsOLHC_Combo{i}.mat"
                            for i in (2, 3, 4)]
                watched += [data / "WeeklyDataBuildManifest.mat"]
            before = {str(p): sha(p) for p in watched}
            if before[str(marker)] != identity["run_complete_sha256"]:
                raise ValueError(f"Accepted completion marker changed: {eid}")
            cell = work / eid
            cell.mkdir()
            code = materialize(source, data, cell, method)
            source_inventory = copied_source_inventory(code)
            jobs = cell / "jobs"
            prefs = cell / "prefs"
            jobs.mkdir()
            prefs.mkdir()
            output = cell / "native_audit.mat"
            window_output = cell / "native_window_status.csv"
            matlab_expr = (
                f"cd('{str(code).replace(chr(39),chr(39)*2)}');"
                "addpath('./Utils');set(0,'DefaultFigureVisible','off');"
                "c=parcluster('local');"
                f"c.JobStorageLocation='{str(jobs).replace(chr(39),chr(39)*2)}';"
                f"c.NumWorkers={args.workers};parpool(c,{args.workers});"
                "run('b05CreateCTREND.m');"
                f"run('{str(AUDITOR).replace(chr(39),chr(39)*2)}');"
                "delete(gcp('nocreate'));"
            )
            env = {**os.environ, "MATLAB_PREFDIR": str(prefs),
                   "OMP_NUM_THREADS": "1", "MKL_NUM_THREADS": "1",
                   "OPENBLAS_NUM_THREADS": "1", "CTREND_E07_METHOD": method,
                   "CTREND_E07_PARENT_BASE": str(baseline),
                   "CTREND_E07_DERIVED_BASE": str(code / "Results/CTREND/CTREND_Base.mat"),
                   "CTREND_E07_OUTPUT": str(output),
                   "CTREND_E07_WINDOW_OUTPUT": str(window_output)}
            print(f"E07_NATIVE_START {eid} workers={args.workers}", flush=True)
            start = time.time()
            log = cell / "pipeline.log"
            with log.open("w") as stream:
                rc = subprocess.run([str(args.matlab), "-licmode", "onlinelicensing",
                                     "-nodisplay", "-nosplash", "-batch", matlab_expr],
                                    cwd=code, env=env, stdout=stream,
                                    stderr=subprocess.STDOUT).returncode
            if rc:
                raise RuntimeError(f"{eid} MATLAB rc={rc}; preserve {cell}")
            text = log.read_text(errors="replace")
            if "E07_BASELINE_NUMERIC_BITWISE_OK" not in text or "E07_NATIVE_AUDIT_OK" not in text:
                raise RuntimeError(f"{eid} lacks acceptance markers; preserve {cell}")
            if not output.is_file() or not window_output.is_file():
                raise FileNotFoundError("Native asset or window audit is missing")
            if source_inventory != copied_source_inventory(code):
                raise RuntimeError(f"Derived MATLAB source mutated during run: {eid}")
            if before != {str(p): sha(p) for p in watched}:
                raise RuntimeError(f"Accepted parent input mutated during run: {eid}")
            result = {"experiment_id": eid,
                      "parent_research_run_id": identity["research_run_id"],
                      "parent_hashes": before, "source_inventory": source_inventory,
                      "native_audit_sha256": sha(output),
                      "native_window_status_sha256": sha(window_output),
                      "derived_base_sha256": sha(code / "Results/CTREND/CTREND_Base.mat"),
                      "stage_counts": audit_axes(output),
                      "elapsed_seconds": round(time.time()-start, 3)}
            manifest["results"].append(result)
            journal.write_text(json.dumps(manifest, indent=2) + "\n")
            print(f"E07_NATIVE_DONE {eid} elapsed_seconds={result['elapsed_seconds']}",
                  flush=True)
        manifest["status"] = "complete"
    except BaseException as exc:
        manifest["status"] = "failed"
        manifest["error"] = repr(exc)
        raise
    finally:
        journal.write_text(json.dumps(manifest, indent=2) + "\n")


if __name__ == "__main__":
    main()
