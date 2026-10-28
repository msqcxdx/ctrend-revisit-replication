#!/usr/bin/env python3
"""Extend E07 saved-input stage diagnostics to every baseline model week.

The labels describe observable gates in accepted M1/M2 inputs; they are not
native, unique failure codes from a newly instrumented training run. Both
accepted runs and the five-week predecessor artifact remain read-only.
"""

from __future__ import annotations

import csv
import json
from pathlib import Path

import numpy as np
from scipy.io import loadmat

from diagnose_e07_key_week_model_support import (
    OUT, ROOT, WEEKS, accepted, digest, read_method, stage,
)


def main() -> None:
    identities = accepted()
    canonical = loadmat(Path(identities["P1_M1_D1"]["result_root"]) /
                        "CTREND/CTREND_Base.mat", squeeze_me=True,
                        variable_names=["cTechnicalIndicators"])
    names = [str(x) for x in canonical["cTechnicalIndicators"].ravel()]
    if len(names) != 28 or len(set(names)) != 28:
        raise RuntimeError("Expected 28 unique baseline technical indicators")
    output = OUT / "all_week_model_support_diagnostics.csv"
    summary = OUT / "all_week_model_support_summary.csv"
    receipt = OUT / "all_week_model_support_receipt.json"
    if any(p.exists() for p in (output, summary, receipt)):
        raise FileExistsError("Refuse to overwrite an E07 all-week audit artifact")
    fieldnames = ["experiment_id", "year_week", "cmcid", "union_extreme_holdings",
                  "formation_cap", "formation_close", "stablecoin",
                  "raw_predictors_finite", "raw_predictors_NaN",
                  "selected_predictors", "selected_predictors_missing",
                  "missing_predictor_names", "missing_selected_names",
                  "forecast_finite", "saved_forecast", "low_opening_weight",
                  "high_opening_weight", "diagnostic_stage"]
    counts: dict[tuple[str, str], int] = {}
    parents: list[dict] = []
    key_rows: dict[tuple[str, int, int], dict] = {}
    total = 0
    with output.open("w", newline="", encoding="utf-8") as f:
        writer = csv.DictWriter(f, fieldnames=fieldnames)
        writer.writeheader()
        for p in (0, 1):
            for d in (0, 1, 2):
                pair = {}
                left = f"P{p}_M1_D{d}"
                right = f"P{p}_M2_D{d}"
                baseline = loadmat(Path(identities[left]["result_root"]) /
                                   "CTREND/CTREND_Base.mat", squeeze_me=True,
                                   variable_names=["vDates"])
                all_weeks = tuple(int(v) for v in np.asarray(baseline["vDates"]).ravel()[52:])
                for m in (2, 1):
                    eid = f"P{p}_M{m}_D{d}"
                    pair[m] = read_method(eid, identities[eid], names, all_weeks)
                    parents.append({"experiment_id": eid,
                                    "research_run_id": identities[eid]["research_run_id"],
                                    "result_sha256": pair[m]["result_sha256"],
                                    "weekly_input_sha256": pair[m]["source_sha256"]})
                if not np.array_equal(pair[1]["ids"], pair[2]["ids"]) or not np.array_equal(
                        pair[1]["weeks"], pair[2]["weeks"]):
                    raise RuntimeError(f"M2/M1 axes differ: P{p} D{d}")
                ids = pair[1]["ids"]
                for week in all_weeks:
                    t = pair[1]["fields"][week]["t"]
                    union = np.zeros(len(ids), dtype=bool)
                    for m in (1, 2):
                        w = pair[m]["weights"][:, t, :]
                        union |= np.isfinite(w[:, 0]) & (w[:, 0] > 0)
                        union |= np.isfinite(w[:, -1]) & (w[:, -1] > 0)
                    for i in np.flatnonzero(union):
                        for m in (2, 1):
                            z = pair[m]
                            eid = f"P{p}_M{m}_D{d}"
                            fields = z["fields"][week]
                            pred = fields["indicators"][i]
                            selected = z["selection"][t-52]
                            weights = z["weights"][i, t, :]
                            forecast = z["forecast"][i, t]
                            label = stage(f"M{m}", fields["cap"][i],
                                          fields["close"][i], bool(fields["stable"][i]),
                                          pred, selected, forecast)
                            if np.isfinite(forecast) != (label == "saved_forecast_finite"):
                                raise RuntimeError(f"Forecast/stage mismatch: {eid} {week} {ids[i]}")
                            if np.any(np.isfinite(weights[[0, -1]]) &
                                      (weights[[0, -1]] > 0)) and not np.isfinite(forecast):
                                raise RuntimeError(f"Held asset lacks forecast: {eid} {week} {ids[i]}")
                            row = dict(experiment_id=eid, year_week=week,
                                       cmcid=int(ids[i]), union_extreme_holdings=1,
                                       formation_cap=float(fields["cap"][i]),
                                       formation_close=float(fields["close"][i]),
                                       stablecoin=int(fields["stable"][i]),
                                       raw_predictors_finite=int(np.isfinite(pred).sum()),
                                       raw_predictors_NaN=int(np.isnan(pred).sum()),
                                       selected_predictors=int(selected.sum()),
                                       selected_predictors_missing=int((~np.isfinite(pred[selected])).sum()),
                                       missing_predictor_names=";".join(
                                           n for n, v in zip(names, pred) if not np.isfinite(v)),
                                       missing_selected_names=";".join(
                                           n for n, v, use in zip(names, pred, selected)
                                           if use and not np.isfinite(v)),
                                       forecast_finite=int(np.isfinite(forecast)),
                                       saved_forecast=float(forecast),
                                       low_opening_weight=float(weights[0]),
                                       high_opening_weight=float(weights[-1]),
                                       diagnostic_stage=label)
                            writer.writerow(row)
                            counts[(eid, label)] = counts.get((eid, label), 0) + 1
                            total += 1
                            if week in WEEKS:
                                key_rows[(eid, week, int(ids[i]))] = row
                print(f"E07_ALL_WEEK_PAIR_DONE P{p} D{d} rows={total}", flush=True)
                del pair
    old = OUT / "key_week_model_support_diagnostics.csv"
    with old.open(newline="", encoding="utf-8") as f:
        previous = {(r["experiment_id"], int(r["year_week"]), int(r["cmcid"])): r
                    for r in csv.DictReader(f)}
    if set(previous) != set(key_rows):
        raise RuntimeError("All-week audit failed five-week key identity equality")
    for key, old_row in previous.items():
        new_row = key_rows[key]
        for name in fieldnames:
            if old_row[name] != str(new_row[name]):
                raise RuntimeError(f"All-week/key-week disagreement at {key} {name}")
    with summary.open("w", newline="", encoding="utf-8") as f:
        writer = csv.writer(f)
        writer.writerow(("experiment_id", "diagnostic_stage", "asset_week_rows"))
        writer.writerows((eid, label, n) for (eid, label), n in sorted(counts.items()))
    receipt.write_text(json.dumps({
        "scope": "all_baseline_model_weeks_union_extreme_holdings_saved_input_diagnostics_not_native_failure_codes",
        "rows": total, "five_week_rows_reproduced": len(previous), "parents": parents,
        "outputs": {output.name: digest(output), summary.name: digest(summary)},
        "unresolved_rows": sum(n for (eid, label), n in counts.items()
                               if label == "model_stage_unresolved_from_saved_fields")},
        indent=2) + "\n")
    print(f"E07_ALL_WEEK_SUPPORT_OK rows={total}", flush=True)


if __name__ == "__main__":
    main()
