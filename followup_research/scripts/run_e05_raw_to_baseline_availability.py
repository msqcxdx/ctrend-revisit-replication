#!/usr/bin/env python3
"""Isolated raw-byte-to-b05 replay with a future terminal-quote intervention.

The original vendor files are copied verbatim.  In an audit-only source copy,
the intervention is made in b01 memory *after* vendor validation and before
missing-data preprocessing.  Control and shock have identical audit source,
and neither is registered as a production run.  The control must reproduce
the accepted baseline numbers bitwise.  Earlier-week differences are reported
as findings, not suppressed to manufacture a passing causal test.
"""

from __future__ import annotations

import argparse
import csv
from hashlib import sha256
import json
import os
from pathlib import Path
import shutil
import subprocess
import time
import uuid

import numpy as np
from scipy.io import loadmat


ROOT = Path(__file__).resolve().parents[1]
REPO = ROOT.parent
ANCHOR = "vUnifiedDateKey = year(dtDate)*10000 + month(dtDate)*100 + day(dtDate);"
INJECTION = """% E05 AUDIT ONLY: same source in control and shocked runs.
% Parent raw CSV bytes and dates are never changed; the future availability
% intervention occurs after input validation and before P1 preprocessing.
if strcmp(getenv('CTREND_E05_AVAILABILITY_SCENARIO'),'future_terminal')
    iE05Asset = find(vAssetID_Close == str2double(getenv('CTREND_E05_TARGET_ID')));
    assert(isscalar(iE05Asset),'E05 target CMCID must occur once');
    iE05Cutoff = str2double(getenv('CTREND_E05_CUTOFF'));
    lE05Future = year(dtDate)*10000+month(dtDate)*100+day(dtDate) >= iE05Cutoff;
    assert(any(lE05Future) && any(~lE05Future),'E05 cutoff outside panel');
    mOpen(lE05Future,iE05Asset)=NaN;
    mHigh(lE05Future,iE05Asset)=NaN;
    mLow(lE05Future,iE05Asset)=NaN;
    mClose(lE05Future,iE05Asset)=NaN;
    mME(lE05Future,iE05Asset)=NaN;
    mVolume(lE05Future,iE05Asset)=NaN;
    fprintf('E05_IN_MEMORY_FUTURE_TERMINAL cmcid=%d cutoff=%d rows=%d\\n', ...
        vAssetID_Close(iE05Asset),iE05Cutoff,nnz(lE05Future));
elseif ~strcmp(getenv('CTREND_E05_AVAILABILITY_SCENARIO'),'control')
    error('Unknown E05 availability scenario');
end

"""


def digest(path: Path) -> str:
    h = sha256()
    with path.open("rb") as f:
        for block in iter(lambda: f.read(2**20), b""):
            h.update(block)
    return h.hexdigest()


def matlab_quote(path: Path) -> str:
    return str(path).replace("'", "''")


def data_file(run: Path, name: str) -> Path:
    found = [run / folder / name for folder in ("data", "data.staging")
             if (run / folder / name).is_file()]
    if len(found) != 1:
        raise RuntimeError(f"Expected one parent input {name}")
    return found[0]


def equivalent(a: np.ndarray, b: np.ndarray) -> np.ndarray:
    if a.shape != b.shape:
        raise RuntimeError(f"Comparison axes differ: {a.shape} vs {b.shape}")
    return (a == b) | (np.isnan(a) & np.isnan(b))


def base(path: Path) -> dict:
    obj = loadmat(path, squeeze_me=True, struct_as_record=False,
                  variable_names=["vDates", "vModelDates", "vAssetID", "mYhat",
                                  "mBeta", "mSelected", "mRetPnlOOS", "cResults"])
    return {"weeks": np.asarray(obj["vDates"], dtype=int).ravel(),
            "model_weeks": np.asarray(obj["vModelDates"], dtype=int).ravel(),
            "ids": np.asarray(obj["vAssetID"], dtype=int).ravel(),
            "forecast": np.asarray(obj["mYhat"], dtype=float),
            "beta": np.asarray(obj["mBeta"], dtype=float),
            "selected": np.asarray(obj["mSelected"]),
            "payoff": np.asarray(obj["mRetPnlOOS"], dtype=float),
            "weights": np.asarray(obj["cResults"].VW.mWts, dtype=float),
            "hl": np.asarray(obj["cResults"].VW.mPortRet, dtype=float)[-1, :].ravel()}


def calendar_date(path: Path, target: int) -> str:
    with path.open(newline="", encoding="utf-8") as f:
        matches = [r for r in csv.DictReader(f) if int(float(r["asset_id"])) == target]
    if len(matches) != 1:
        raise RuntimeError("E05 target missing or duplicate in calendar")
    return matches[0]["last_tradable_date"]


def clone(parent_source: Path, parent_run: Path, target: Path) -> dict[str,str]:
    code = target / "source"
    code.mkdir(parents=True)
    for src in parent_source.rglob("*"):
        rel = src.relative_to(parent_source)
        if any(x in rel.parts for x in ("DATA", "Results")) or src.is_symlink():
            continue
        dst = code / rel
        if src.is_dir():
            dst.mkdir(exist_ok=True, parents=True)
        elif src.is_file():
            dst.parent.mkdir(exist_ok=True, parents=True)
            shutil.copy2(src, dst)
    original = (code / "b01ReadData.m").read_text()
    if original.count(ANCHOR) != 1:
        raise RuntimeError("b01 future-availability injection anchor differs")
    (code / "b01ReadData.m").write_text(original.replace(ANCHOR, INJECTION+ANCHOR))
    inputs = ("close_cmc.csv", "open_cmc.csv", "high_cmc.csv", "low_cmc.csv",
              "market_cap_cmc.csv", "volume_cmc.csv", "MetaData.mat",
              "F-F_Research_Data_Factors_daily.CSV", "LTW_3factor.xlsx",
              "LTW_3factor.mat",
              "UCRY.csv", "screening_summary.json")
    data = code / "DATA"
    data.mkdir()
    hashes = {}
    for name in inputs:
        src = data_file(parent_run, name)
        dst = data / name
        shutil.copy2(src, dst)
        hashes[name] = digest(src)
        if digest(dst) != hashes[name]:
            raise RuntimeError(f"Copied input changed: {name}")
    (code / "Results/CTREND").mkdir(parents=True)
    return hashes


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--work-root", type=Path, required=True)
    ap.add_argument("--matlab", type=Path, required=True)
    ap.add_argument("--workers", type=int, default=64)
    ap.add_argument("--target-id", type=int, default=52)
    ap.add_argument("--cutoff", type=int, default=20200415)
    args = ap.parse_args()
    work = args.work_root.resolve()
    if work.exists():
        raise FileExistsError(work)
    if not args.matlab.is_file() or not os.access(args.matlab, os.X_OK):
        raise FileNotFoundError(args.matlab)
    if not 1 <= args.workers <= len(os.sched_getaffinity(0))-1:
        raise ValueError("Worker budget")
    if shutil.disk_usage(work.parent).free < 8*2**30:
        raise RuntimeError("Need 8 GiB headroom before E05 replay")
    with (ROOT / "outputs/E11/accepted_run_paths.csv").open(newline="") as f:
        identity = next(r for r in csv.DictReader(f) if r["experiment_id"] == "P1_M1_D1")
    parent = Path(identity["accepted_run_root"])
    source = parent / "runtime/ctrend_corrected_pipeline"
    accepted_result = Path(identity["result_root"]) / "CTREND/CTREND_Base.mat"
    protected = [parent / "RUN_COMPLETE", source / "b01ReadData.m",
                 source / "b02CalculateIndicators.m", source / "b05CreateCTREND.m",
                 accepted_result]
    before = {str(path): digest(path) for path in protected}
    if before[str(parent / "RUN_COMPLETE")] != identity["run_complete_sha256"]:
        raise RuntimeError("Accepted parent marker differs")
    work.mkdir()
    receipt = {"research_run_id": str(uuid.uuid4()), "status": "running",
               "scope": "raw_bytes_to_b01_b02_b05_baseline_P1_M1_D1_synthetic_future_terminal",
               "not_a_production_run": True, "parent": identity,
               "parent_hashes_before": before, "driver_sha256": digest(Path(__file__)),
               "target_id": args.target_id, "cutoff": args.cutoff, "workers": args.workers}
    try:
        copied = {}
        for variant in ("control", "future_terminal"):
            folder = work / variant
            folder.mkdir()
            copied[variant] = clone(source, parent, folder)
            if copied[variant] != copied.get("control"):
                raise RuntimeError("Control/shock copied different raw bytes")
            code = folder / "source"
            (folder / "jobs").mkdir()
            (folder / "prefs").mkdir()
            expr = (f"cd('{matlab_quote(code)}');addpath('Utils');"
                    "set(0,'DefaultFigureVisible','off');"
                    f"c=parcluster('local');c.JobStorageLocation='{matlab_quote(folder/'jobs')}';"
                    f"c.NumWorkers={args.workers};parpool(c,{args.workers});"
                    "run('b01ReadData.m');run('b02CalculateIndicators.m');"
                    "run('b05CreateCTREND.m');delete(gcp('nocreate'));"
                    "fprintf('E05_RAW_TO_BASELINE_OK\\n');")
            env = {**os.environ, "MATLAB_PREFDIR": str(folder / "prefs"),
                   "CTREND_E05_AVAILABILITY_SCENARIO": variant,
                   "CTREND_E05_TARGET_ID": str(args.target_id),
                   "CTREND_E05_CUTOFF": str(args.cutoff),
                   "CTREND_DATA_TREATMENT_ID": "D1",
                   "CTREND_ASSET_EXCLUSION_FILE": str(REPO / "config/exclusions/D1.csv"),
                   "CTREND_ASSET_EXCLUSION_SHA256": digest(REPO / "config/exclusions/D1.csv"),
                   "CTREND_RAW_ADJUSTMENT_MODE": "none",
                   "CTREND_CORE_EXPERIMENT_ID": "P1_M1_D1_E05_AUDIT_ONLY",
                   "PIPELINE_SCOPE": "baseline",
                   "OMP_NUM_THREADS": "1", "MKL_NUM_THREADS": "1",
                   "OPENBLAS_NUM_THREADS": "1"}
            print(f"E05_CHAIN_START {variant}", flush=True)
            start = time.time()
            with (folder / "pipeline.log").open("w") as log:
                rc = subprocess.run([str(args.matlab), "-licmode", "onlinelicensing",
                                     "-nodisplay", "-nosplash", "-batch", expr],
                                    cwd=code, env=env, stdout=log,
                                    stderr=subprocess.STDOUT).returncode
            if rc:
                raise RuntimeError(f"{variant} MATLAB rc={rc}; inspect {folder/'pipeline.log'}")
            if any(digest(code / "DATA" / name) != value
                   for name,value in copied[variant].items()):
                raise RuntimeError("Audit raw vendor bytes changed")
            receipt[variant] = {"seconds": time.time()-start,
                "result_sha256": digest(code / "Results/CTREND/CTREND_Base.mat"),
                "raw_input_hashes": copied[variant],
                "modified_b01_sha256": digest(code / "b01ReadData.m"),
                "generated_b0_sha256": digest(code / "DATA/b0DataOLHC.mat"),
                "generated_weekly_sha256": digest(code / "DATA/bCharacteristicsOLHC_Combo1.mat")}
            print(f"E05_CHAIN_DONE {variant}", flush=True)
        parent_result = base(accepted_result)
        control = base(work / "control/source/Results/CTREND/CTREND_Base.mat")
        shock = base(work / "future_terminal/source/Results/CTREND/CTREND_Base.mat")
        if any(not np.array_equal(parent_result[key], control[key])
               for key in ("weeks", "model_weeks", "ids")):
            raise RuntimeError("Control baseline axes differ from parent")
        if any(not np.all(equivalent(parent_result[key], control[key]))
               for key in ("forecast", "beta", "selected", "payoff", "weights", "hl")):
            raise RuntimeError("Control baseline numeric values differ from parent")
        if any(not np.array_equal(control[key], shock[key])
               for key in ("weeks", "model_weeks", "ids")):
            raise RuntimeError("Shock changed calendar or asset axes")
        cut_week = args.cutoff // 10000 * 100 + ((
            __import__("datetime").date(args.cutoff//10000,
                args.cutoff//100%100,args.cutoff%100).timetuple().tm_yday-1)//7+1)
        rows = []
        for t,week in enumerate(control["weeks"]):
            forecast = int((~equivalent(control["forecast"][:,t],
                                        shock["forecast"][:,t])).sum())
            weights = int((~equivalent(control["weights"][:,t,:],
                                       shock["weights"][:,t,:])).sum())
            payoff = int((~equivalent(control["payoff"][:,t],
                                      shock["payoff"][:,t])).sum())
            rows.append({"week_key": int(week), "before_shock_week": int(week < cut_week),
                         "changed_forecast_cells": forecast,
                         "changed_opening_weight_cells": weights,
                         "changed_asset_payoff_cells": payoff,
                         "control_hl": float(control["hl"][t]),
                         "shock_hl": float(shock["hl"][t])})
        output = ROOT / "outputs/E05/raw_to_baseline_future_terminal_weekly.csv"
        with output.open("w", newline="") as f:
            writer = csv.DictWriter(f, fieldnames=list(rows[0]))
            writer.writeheader();writer.writerows(rows)
        receipt["weekly_sha256"] = digest(output)
        receipt["cut_week"] = cut_week
        receipt["past_changed_forecast_cells"] = sum(r["changed_forecast_cells"] for r in rows if r["before_shock_week"])
        receipt["past_changed_weight_cells"] = sum(r["changed_opening_weight_cells"] for r in rows if r["before_shock_week"])
        receipt["past_changed_payoff_cells"] = sum(r["changed_asset_payoff_cells"] for r in rows if r["before_shock_week"])
        receipt["later_changed_forecast_cells"] = sum(r["changed_forecast_cells"] for r in rows if not r["before_shock_week"])
        receipt["later_changed_weight_cells"] = sum(r["changed_opening_weight_cells"] for r in rows if not r["before_shock_week"])
        receipt["later_changed_payoff_cells"] = sum(r["changed_asset_payoff_cells"] for r in rows if not r["before_shock_week"])
        receipt["control_last_quote_date"] = calendar_date(
            work / "control/source/DATA/mechanical_exit_calendar.csv",args.target_id)
        receipt["shock_last_quote_date"] = calendar_date(
            work / "future_terminal/source/DATA/mechanical_exit_calendar.csv",args.target_id)
        if receipt["control_last_quote_date"] == receipt["shock_last_quote_date"]:
            raise RuntimeError("Terminal-availability intervention was ineffective")
        if not any(receipt[k] for k in ("later_changed_weight_cells",
                                            "later_changed_payoff_cells",
                                            "later_changed_forecast_cells")):
            raise RuntimeError("Future terminal intervention had no downstream effect")
        receipt["status"] = ("past_invariant_under_synthetic_terminal" if
            not any(receipt[k] for k in ("past_changed_forecast_cells",
                "past_changed_weight_cells", "past_changed_payoff_cells")) else
            "past_changed_future_availability_assumption_exposed")
        if before != {str(path): digest(path) for path in protected}:
            raise RuntimeError("Accepted parent files changed")
        print("E05_RAW_TO_BASELINE_COMPARE",receipt["status"],flush=True)
    except BaseException as exc:
        receipt["status"] = "failed"
        receipt["error"] = repr(exc)
        raise
    finally:
        (work / "receipt.json").write_text(json.dumps(receipt, indent=2)+"\n")


if __name__ == "__main__":
    main()
