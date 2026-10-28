#!/usr/bin/env python3
"""Audit baseline M2/M1 formation and predictor support on five named weeks.

This reads only the twelve accepted M2/M1 baseline runs.  It does not infer a
unique training/selection failure from a missing forecast: a stage label is
reported only where the saved input and the baseline b05 rule identify it.
Rows are the union of the two methods' extreme-leg holdings, with partners'
unheld/missing-forecast records retained.  All parent markers are checked.
"""

from __future__ import annotations

import csv
from hashlib import sha256
import json
from pathlib import Path

import h5py
import numpy as np
from scipy.io import loadmat


ROOT = Path(__file__).resolve().parents[1]
REPO = ROOT.parent
OUT = ROOT / "outputs/E07"
WEEKS = (201628, 201750, 202013, 202016, 202103)


def digest(path: Path) -> str:
    h = sha256()
    with path.open("rb") as f:
        for chunk in iter(lambda: f.read(2**20), b""):
            h.update(chunk)
    return h.hexdigest()


def accepted() -> dict[str, dict[str, str]]:
    with (ROOT / "outputs/E11/accepted_run_paths.csv").open(newline="") as f:
        rows = {r["experiment_id"]: r for r in csv.DictReader(f)}
    for p in (0, 1):
        for m in (1, 2):
            for d in (0, 1, 2):
                eid = f"P{p}_M{m}_D{d}"
                marker = Path(rows[eid]["accepted_run_root"]) / "RUN_COMPLETE"
                if digest(marker) != rows[eid]["run_complete_sha256"]:
                    raise RuntimeError(f"Accepted marker changed: {eid}")
    return rows


def source_weekly(run: Path) -> Path:
    found = [run / folder / "bCharacteristicsOLHC_Combo1.mat"
             for folder in ("data", "data.staging")
             if (run / folder / "bCharacteristicsOLHC_Combo1.mat").is_file()]
    if len(found) != 1:
        raise RuntimeError(f"Exactly one accepted weekly input expected: {run}")
    return found[0]


def read_method(eid: str, identity: dict[str, str], names: list[str],
                audit_weeks: tuple[int, ...] = WEEKS) -> dict:
    result = Path(identity["result_root"]) / "CTREND/CTREND_Base.mat"
    a = loadmat(result, squeeze_me=True, struct_as_record=False,
                variable_names=["vDates", "vAssetID", "mYhat", "mSelected",
                                "vModelDates", "cResults"])
    ids = np.asarray(a["vAssetID"], dtype=int).ravel()
    weeks = np.asarray(a["vDates"], dtype=int).ravel()
    forecast = np.asarray(a["mYhat"], dtype=float)
    selection = np.asarray(a["mSelected"], dtype=bool)
    weights = np.asarray(a["cResults"].VW.mWts, dtype=float)
    if forecast.shape != (len(ids), len(weeks)) or weights.shape != (len(ids), len(weeks), 5):
        raise RuntimeError(f"Result axis mismatch: {eid}")
    if selection.shape != (len(weeks)-52, len(names)):
        raise RuntimeError(f"Unexpected baseline 52-week model axis: {eid}")
    if "vModelDates" in a and not np.array_equal(a["vModelDates"], weeks[52:]):
        raise RuntimeError(f"Saved model-date axis disagrees: {eid}")
    weekly = source_weekly(Path(identity["accepted_run_root"]))
    lookup = {int(w): i for i, w in enumerate(weeks)}
    out = dict(ids=ids, weeks=weeks, forecast=forecast, selection=selection,
               weights=weights, source_sha256=digest(weekly), result_sha256=digest(result),
               fields={})
    with h5py.File(weekly) as h:
        axis = np.asarray(h["rData"]["yrmoda"], dtype=int).ravel()
        source_ids = np.asarray(h["rMetaData"]["vID"], dtype=int).ravel()
        if not np.array_equal(source_ids, ids):
            raise RuntimeError(f"Source/result asset axes differ: {eid}")
        stable = np.asarray(h["rMetaData"]["lIsStable"], dtype=bool).ravel()
        source_index = {}
        for week in audit_weeks:
            ix = np.flatnonzero(axis == week)
            if len(ix) != 1 or ix[0] <= 0:
                raise RuntimeError(f"Missing previous formation week: {eid} {week}")
            source_index[week] = int(ix[0])-1
        if len(audit_weeks) > 10:
            # HDF5 random single-column reads are prohibitively slow for all
            # model weeks. Read each field once, then select the same columns
            # in memory. The five-week path below remains unchanged.
            indices = np.asarray([source_index[week] for week in audit_weeks], dtype=int)
            cap_all = np.asarray(h["rData"]["mME"][:], dtype=float)[:, indices]
            close_all = np.asarray(h["rData"]["mClose"][:], dtype=float)[:, indices]
            indicator_all = np.stack([
                np.asarray(h["rChars"][name][:], dtype=float)[:, indices]
                for name in names
            ], axis=2)
            if indicator_all.shape != (len(ids), len(audit_weeks), 28):
                raise RuntimeError(f"Predictor matrix mismatch: {eid}")
            for k, week in enumerate(audit_weeks):
                out["fields"][week] = dict(t=lookup[week], cap=cap_all[:, k],
                                           close=close_all[:, k], stable=stable,
                                           indicators=indicator_all[:, k, :])
        else:
            for week in audit_weeks:
                t = lookup[week]
                j = source_index[week]
                cap = np.asarray(h["rData"]["mME"][:, j], dtype=float).ravel()
                close = np.asarray(h["rData"]["mClose"][:, j], dtype=float).ravel()
                indicators = np.column_stack([
                    np.asarray(h["rChars"][name][:, j], dtype=float).ravel()
                    for name in names
                ])
                if indicators.shape != (len(ids), 28):
                    raise RuntimeError(f"Predictor matrix mismatch: {eid} {week}")
                out["fields"][week] = dict(t=t, cap=cap, close=close, stable=stable,
                                           indicators=indicators)
    return out


def stage(model: str, cap: float, close: float, stable: bool,
          predictors: np.ndarray, selected: np.ndarray, forecast: float) -> str:
    if stable:
        return "formation_stablecoin_excluded"
    if not np.isfinite(cap) or cap == 0 or cap < 1e6:
        return "formation_market_cap_excluded"
    if not np.isfinite(close) or close < 0:
        return "formation_price_excluded"
    if model == "M2" and np.isnan(predictors).any():
        return "M2_joint_predictor_NaN_gate"
    if model == "M1" and not np.isfinite(predictors).any():
        return "M1_no_finite_predictor"
    if np.isfinite(forecast):
        return "saved_forecast_finite"
    if not selected.any():
        return "selected_set_empty_or_fit_unidentified"
    if model == "M1" and not np.isfinite(predictors[selected]).all():
        return "M1_selected_predictor_missing"
    return "model_stage_unresolved_from_saved_fields"


def main() -> None:
    identities = accepted()
    canonical = loadmat(Path(identities["P1_M1_D1"]["result_root"]) /
                        "CTREND/CTREND_Base.mat", squeeze_me=True,
                        variable_names=["cTechnicalIndicators"])
    names = [str(x) for x in canonical["cTechnicalIndicators"].ravel()]
    if len(names) != 28 or len(set(names)) != 28:
        raise RuntimeError("Expected 28 unique saved baseline technical indicators")
    rows: list[dict] = []
    inputs: list[dict] = []
    for p in (0, 1):
        for d in (0, 1, 2):
            pair = {}
            for m in (2, 1):
                eid = f"P{p}_M{m}_D{d}"
                pair[m] = read_method(eid, identities[eid], names)
                inputs.append(dict(experiment_id=eid,
                                   research_run_id=identities[eid]["research_run_id"],
                                   result_sha256=pair[m]["result_sha256"],
                                   weekly_input_sha256=pair[m]["source_sha256"]))
            if not np.array_equal(pair[1]["ids"], pair[2]["ids"]) or not np.array_equal(pair[1]["weeks"], pair[2]["weeks"]):
                raise RuntimeError(f"M2/M1 axes differ: P{p} D{d}")
            ids = pair[1]["ids"]
            for week in WEEKS:
                t = pair[1]["fields"][week]["t"]
                union = np.zeros(len(ids), dtype=bool)
                for m in (1, 2):
                    w = pair[m]["weights"][:, t, :]
                    union |= np.isfinite(w[:, 0]) & (w[:, 0] > 0)
                    union |= np.isfinite(w[:, -1]) & (w[:, -1] > 0)
                for i in np.flatnonzero(union):
                    for m in (2, 1):
                        z = pair[m]
                        f = z["fields"][week]
                        preds = f["indicators"][i]
                        selected = z["selection"][t-52]
                        w = z["weights"][i, t, :]
                        yhat = z["forecast"][i, t]
                        label = stage(f"M{m}", f["cap"][i], f["close"][i],
                                      bool(f["stable"][i]), preds, selected, yhat)
                        if np.isfinite(yhat) != (label == "saved_forecast_finite"):
                            raise RuntimeError(f"Forecast/stage disagreement: P{p} M{m} D{d} {week} {ids[i]}")
                        if np.any(np.isfinite(w[[0, -1]]) & (w[[0, -1]] > 0)) and not np.isfinite(yhat):
                            raise RuntimeError(f"Held asset lacks forecast: P{p} M{m} D{d} {week} {ids[i]}")
                        rows.append(dict(experiment_id=f"P{p}_M{m}_D{d}",
                            year_week=week, cmcid=int(ids[i]), union_extreme_holdings=1,
                            formation_cap=float(f["cap"][i]),
                            formation_close=float(f["close"][i]),
                            stablecoin=int(f["stable"][i]),
                            raw_predictors_finite=int(np.isfinite(preds).sum()),
                            raw_predictors_NaN=int(np.isnan(preds).sum()),
                            selected_predictors=int(selected.sum()),
                            selected_predictors_missing=int((~np.isfinite(preds[selected])).sum()),
                            missing_predictor_names=";".join(name for name, value in zip(names, preds) if not np.isfinite(value)),
                            missing_selected_names=";".join(name for name, value, use in zip(names, preds, selected) if use and not np.isfinite(value)),
                            forecast_finite=int(np.isfinite(yhat)),
                            saved_forecast=float(yhat),
                            low_opening_weight=float(w[0]),
                            high_opening_weight=float(w[-1]),
                            diagnostic_stage=label))
    output = OUT / "key_week_model_support_diagnostics.csv"
    with output.open("w", newline="", encoding="utf-8") as f:
        writer = csv.DictWriter(f, fieldnames=list(rows[0]))
        writer.writeheader(); writer.writerows(rows)
    counts = {}
    for row in rows:
        key = (row["experiment_id"], row["diagnostic_stage"])
        counts[key] = counts.get(key, 0)+1
    summary = OUT / "key_week_model_support_summary.csv"
    with summary.open("w", newline="", encoding="utf-8") as f:
        writer = csv.writer(f)
        writer.writerow(("experiment_id", "diagnostic_stage", "asset_week_rows"))
        writer.writerows((eid, label, n) for (eid, label), n in sorted(counts.items()))
    receipt = dict(scope="five_key_weeks_union_extreme_holdings_M2_vs_M1_not_unique_causal_reasons",
                   weeks=WEEKS, rows=len(rows), parents=inputs,
                   outputs={output.name:digest(output),summary.name:digest(summary)},
                   unresolved_rows=sum(r["diagnostic_stage"] == "model_stage_unresolved_from_saved_fields" for r in rows))
    (OUT / "key_week_model_support_receipt.json").write_text(json.dumps(receipt, indent=2)+"\n")
    print(f"E07_KEY_WEEK_SUPPORT_OK rows={len(rows)} unresolved={receipt['unresolved_rows']}")


if __name__ == "__main__":
    main()
