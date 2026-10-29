#!/usr/bin/env python3
"""Export accepted isolated E07 gate traces without changing parent results.

This reads only complete, numerically reconciled native-audit run roots. The
asset-week CSV retains simultaneous failure flags as well as the first failed
production gate; the latter must not be interpreted as a unique causal reason.
"""

from __future__ import annotations

import argparse
import csv
import gzip
import hashlib
import json
from collections import Counter
from pathlib import Path

import h5py
import numpy as np
from scipy.io import loadmat


CODEBOOK = (
    "not_model_week", "stablecoin_filter", "formation_cap_filter",
    "formation_price_filter", "predictor_panel_not_formed",
    "no_validation_component_forecast", "selection_fit_not_identified",
    "estimated_empty_selected_set", "selected_panel_predictor_missing",
    "selected_component_forecast_unavailable", "unresolved", "forecast_finite",
)
FLAG_BITS = {
    "stablecoin": 1, "formation_cap_fail": 2, "formation_price_fail": 4,
    "at_least_one_raw_predictor_nan": 8, "predictor_panel_absent": 16,
    "at_least_one_selected_raw_predictor_nonfinite": 32,
    "at_least_one_selected_panel_predictor_nonfinite": 64,
    "forecast_finite": 128,
}
HEADER = [
    "experiment_id", "parent_research_run_id", "year_week", "cmcid",
    "first_failed_gate_code", "first_failed_gate", "simultaneous_flags_bitmask",
    "raw_predictors_finite", "raw_predictors_nan",
    "selected_raw_predictors_nonfinite", "selected_panel_predictors_nonfinite",
    "in_model_panel", "forecast",
]


def sha(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as f:
        for chunk in iter(lambda: f.read(2**20), b""):
            h.update(chunk)
    return h.hexdigest()


def read_manifest(root: Path) -> dict:
    manifest = json.loads((root / "manifest.json").read_text())
    if manifest["status"] != "complete" or len(manifest["results"]) != 6:
        raise ValueError(f"Not a complete six-cell native audit: {root}")
    return manifest


def export_cell(root: Path, result: dict, out: Path) -> tuple[list[dict], Counter]:
    eid = result["experiment_id"]
    cell = root / eid
    audit = cell / "native_audit.mat"
    windows = cell / "native_window_status.csv"
    baseline = cell / "source/Results/CTREND/CTREND_Base.mat"
    if (sha(audit) != result["native_audit_sha256"] or
        sha(windows) != result["native_window_status_sha256"] or
        sha(baseline) != result["derived_base_sha256"]):
        raise ValueError(f"Accepted isolated audit changed: {eid}")
    parent_hashes = result["parent_hashes"]
    if any(sha(Path(name)) != digest for name, digest in parent_hashes.items()):
        raise ValueError(f"Accepted parent input changed: {eid}")

    base = loadmat(baseline, variable_names=["mYhat", "vDates", "vAssetID"])
    forecasts = np.asarray(base["mYhat"], dtype=np.float64)
    ids_base = np.asarray(base["vAssetID"]).ravel().astype(np.int64)
    dates_base = np.asarray(base["vDates"]).ravel().astype(np.int64)
    summary = []
    window_counts = Counter()
    with windows.open(newline="") as f:
        window_rows = list(csv.DictReader(f))
    for row in window_rows:
        window_counts[row["model_window_status"]] += 1
    with h5py.File(audit) as h:
        ids = np.asarray(h["e07AssetID"]).ravel().astype(np.int64)
        dates = np.asarray(h["e07Dates"]).ravel().astype(np.int64)
        if not (np.array_equal(ids, ids_base) and
                np.array_equal(dates, dates_base) and
                forecasts.shape == (len(ids), len(dates))):
            raise ValueError(f"Native axes and numerical baseline differ: {eid}")
        if len(window_rows) != len(dates)-52:
            raise ValueError(f"Native window count differs: {eid}")
        if any(int(row["year_week"]) != int(dates[52+i])
               for i, row in enumerate(window_rows)):
            raise ValueError(f"Native window calendar differs: {eid}")
        stage = h["e07Stage"]
        flags = h["e07Flags"]
        finite = h["e07PredictorsFinite"]
        missing = h["e07PredictorsNaN"]
        raw_selected = h["e07SelectedRawMissing"]
        panel_selected = h["e07SelectedPanelMissing"]
        panel = h["e07PanelPresent"]
        if any(arr.shape != (len(dates), len(ids)) for arr in
               (stage, flags, finite, missing, raw_selected, panel_selected, panel)):
            raise ValueError(f"Native per-cell matrix axes differ: {eid}")
        counts = Counter()
        target = out / f"{eid}_native_asset_week.csv.gz"
        with gzip.open(target, "wt", newline="", compresslevel=6) as f:
            writer = csv.writer(f)
            writer.writerow(HEADER)
            for t in range(52, len(dates)):
                row_stage = np.asarray(stage[t, :], dtype=np.uint8)
                row_flags = np.asarray(flags[t, :], dtype=np.uint16)
                row_finite = np.asarray(finite[t, :], dtype=np.uint8)
                row_missing = np.asarray(missing[t, :], dtype=np.uint8)
                row_raw = np.asarray(raw_selected[t, :], dtype=np.uint8)
                row_panel = np.asarray(panel_selected[t, :], dtype=np.uint8)
                row_present = np.asarray(panel[t, :], dtype=np.uint8)
                row_forecast = forecasts[:, t]
                if np.any(row_stage == 10) or np.any(row_stage > 11):
                    raise ValueError(f"Unresolved model-window gate: {eid} {dates[t]}")
                if not np.array_equal(row_stage == 11, np.isfinite(row_forecast)):
                    raise ValueError(f"Forecast-finite stage differs: {eid} {dates[t]}")
                counts.update(map(int, row_stage))
                writer.writerows((
                    eid, result["parent_research_run_id"], int(dates[t]), int(ids[j]),
                    int(row_stage[j]), CODEBOOK[int(row_stage[j])], int(row_flags[j]),
                    int(row_finite[j]), int(row_missing[j]), int(row_raw[j]),
                    int(row_panel[j]), int(row_present[j]),
                    repr(float(row_forecast[j])) if np.isfinite(row_forecast[j]) else "",
                ) for j in range(len(ids)))
    expected_counts = result["stage_counts"]
    if {CODEBOOK[k]: v for k, v in counts.items()} != expected_counts:
        raise ValueError(f"Export counts do not match the verified audit: {eid}")
    for code, count in sorted(counts.items()):
        summary.append({"experiment_id": eid, "parent_research_run_id":
                        result["parent_research_run_id"], "stage_code": code,
                        "first_failed_gate": CODEBOOK[code], "asset_week_rows": count,
                        "share_of_model_asset_weeks": count/(len(ids)*(len(dates)-52)),
                        "asset_count": len(ids), "model_weeks": len(dates)-52,
                        "csv_sha256": sha(target)})
    return summary, window_counts


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--run-root", type=Path, action="append", required=True)
    ap.add_argument("--output-root", type=Path, required=True)
    args = ap.parse_args()
    out = args.output_root.resolve()
    if out.exists():
        raise FileExistsError(f"Refuse to mix with existing exports: {out}")
    manifests = [(r.resolve(), read_manifest(r.resolve())) for r in args.run_root]
    cells = [(r, x) for r, m in manifests for x in m["results"]]
    eids = [x["experiment_id"] for _, x in cells]
    if len(eids) != 12 or len(set(eids)) != 12:
        raise ValueError("Need all 12 distinct accepted M1/M2 baseline cells")
    out.mkdir(parents=True)
    summaries = []
    windows = []
    try:
        for root, result in cells:
            rows, statuses = export_cell(root, result, out)
            summaries.extend(rows)
            windows.extend({"experiment_id": result["experiment_id"],
                            "model_window_status": status, "windows": count}
                           for status, count in sorted(statuses.items()))
            print(f"E07_EXPORTED {result['experiment_id']}", flush=True)
        with (out / "native_stage_summary.csv").open("w", newline="") as f:
            writer = csv.DictWriter(f, fieldnames=list(summaries[0]))
            writer.writeheader()
            writer.writerows(summaries)
        with (out / "native_window_status_summary.csv").open("w", newline="") as f:
            writer = csv.DictWriter(f, fieldnames=list(windows[0]))
            writer.writeheader()
            writer.writerows(windows)
        with (out / "parent_derived_pairs.csv").open("w", newline="") as f:
            writer = csv.writer(f)
            writer.writerow(["experiment_id", "parent_base", "derived_base"])
            for root, result in cells:
                candidates = [p for p in result["parent_hashes"]
                              if p.endswith("/CTREND/CTREND_Base.mat")]
                if len(candidates) != 1:
                    raise ValueError("Accepted parent baseline identity is ambiguous")
                writer.writerow([result["experiment_id"], candidates[0],
                                 root / result["experiment_id"] /
                                 "source/Results/CTREND/CTREND_Base.mat"])
        by_id = {r["experiment_id"]: root for root, r in cells}
        with (out / "paired_m2_m1_native_stage_transitions.csv").open(
                "w", newline="") as f:
            writer = csv.writer(f)
            writer.writerow(["preprocessing", "data_design", "m2_stage_code",
                             "m2_stage", "m1_stage_code", "m1_stage",
                             "asset_week_rows"])
            for p in (0, 1):
                for d in (0, 1, 2):
                    m2 = f"P{p}_M2_D{d}"
                    m1 = f"P{p}_M1_D{d}"
                    with h5py.File(by_id[m2] / m2 / "native_audit.mat") as a, \
                         h5py.File(by_id[m1] / m1 / "native_audit.mat") as b:
                        if not (np.array_equal(a["e07AssetID"][:],b["e07AssetID"][:])
                                and np.array_equal(a["e07Dates"][:],b["e07Dates"][:])):
                            raise ValueError(f"Paired M2/M1 axes differ: P{p} D{d}")
                        pair = np.asarray(a["e07Stage"][52:],dtype=np.uint8)*12 + \
                            np.asarray(b["e07Stage"][52:],dtype=np.uint8)
                        matrix = np.bincount(pair.ravel(),minlength=144).reshape(12,12)
                        for i,j in zip(*np.nonzero(matrix)):
                            writer.writerow([f"P{p}",f"D{d}",int(i),CODEBOOK[i],
                                             int(j),CODEBOOK[j],int(matrix[i,j])])
        with (out / "innbcl_2020w16_native_gates.csv").open("w", newline="") as f:
            writer = csv.writer(f)
            writer.writerow(["experiment_id", "cmcid", "year_week", "stage_code",
                             "first_failed_gate", "simultaneous_flags_bitmask",
                             "raw_predictors_finite", "raw_predictors_nan",
                             "selected_raw_predictors_nonfinite", "in_model_panel"])
            for root, result in cells:
                with h5py.File(root / result["experiment_id"] /
                               "native_audit.mat") as h:
                    ids = np.asarray(h["e07AssetID"]).ravel()
                    dates = np.asarray(h["e07Dates"]).ravel()
                    asset = np.where(ids==3787)[0]
                    week = np.where(dates==202016)[0]
                    if len(asset)==1 and len(week)==1:
                        a,t = int(asset[0]),int(week[0])
                        code = int(h["e07Stage"][t,a])
                        writer.writerow([result["experiment_id"],3787,202016,
                                         code,CODEBOOK[code],int(h["e07Flags"][t,a]),
                                         int(h["e07PredictorsFinite"][t,a]),
                                         int(h["e07PredictorsNaN"][t,a]),
                                         int(h["e07SelectedRawMissing"][t,a]),
                                         int(h["e07PanelPresent"][t,a])])
        receipt = {"format": "ctrend-e07-native-gates-export-v1",
                   "interpretation": "first_failed_gate_is_ordered_code_path_not_unique_cause",
                   "flag_bits": FLAG_BITS,
                   "source_manifests": {str(r): sha(r / "manifest.json")
                                        for r, _ in manifests},
                   "files_sha256": {p.name: sha(p) for p in sorted(out.iterdir())
                                    if p.is_file()}}
        (out / "EXPORT_RECEIPT.json").write_text(json.dumps(receipt, indent=2)+"\n")
    except BaseException:
        (out / "EXPORT_INCOMPLETE").write_text("Export failed; do not use this directory.\n")
        raise


if __name__ == "__main__":
    main()
