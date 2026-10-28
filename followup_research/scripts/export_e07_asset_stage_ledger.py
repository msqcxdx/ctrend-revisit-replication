#!/usr/bin/env python3
"""Export observed forecast-to-holding states from the 18 accepted base runs.

This is a read-only, asset-by-week diagnostic.  A missing saved forecast has
many possible causes; the ledger deliberately does not invent a unique model
rejection code.  Opening-weight times asset payoff is a *direct* contribution,
not the full return when same-leg intraweek reinvestment occurred.
"""

from __future__ import annotations

import argparse
import csv
import gzip
import hashlib
import io
import json
import os
from pathlib import Path

import h5py
import numpy as np
from scipy.io import loadmat


ROOT = Path(__file__).resolve().parents[1]
REPO = ROOT.parent
DEFAULT_OUT = ROOT / "outputs" / "E07"
FIELDS = (
    "experiment_id", "year_week", "cmcid", "forecast_finite", "saved_forecast",
    "formation_lagged_cap_finite", "formation_lagged_cap_usd",
    "formation_lagged_close_finite", "formation_lagged_close_usd",
    "formation_lagged_weekly_volume_sum_usd", "formation_lagged_prcvol_characteristic",
    "prcvol_definition", "weekly_volume_missing_rule", "saved_payoff_finite",
    "saved_asset_payoff", "low_leg_opening_weight", "high_leg_opening_weight",
    "saved_holding_state", "signed_direct_hl_contribution", "payoff_definition",
)
SUMMARY_FIELDS = (
    "experiment_id", "year_week", "asset_universe", "forecast_count",
    "no_forecast_count", "forecast_but_unheld_count", "low_holding_count",
    "high_holding_count", "held_without_finite_forecast_count",
    "held_without_finite_payoff_count", "no_forecast_despite_finite_lag_cap_close_count",
    "saved_hl_return", "direct_hl_return_if_complete", "direct_vs_saved_residual",
    "payoff_definition",
)


def digest(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(2**20), b""):
            h.update(chunk)
    return h.hexdigest()


def accepted_roots() -> dict[str, dict[str, str]]:
    path = ROOT / "outputs" / "E11" / "accepted_run_paths.csv"
    with path.open(newline="", encoding="utf-8") as stream:
        rows = list(csv.DictReader(stream))
    if len(rows) != 18 or len({r["experiment_id"] for r in rows}) != 18:
        raise RuntimeError("E07 requires all 18 distinct accepted run identities")
    for row in rows:
        marker = Path(row["accepted_run_root"]) / "RUN_COMPLETE"
        if not marker.is_file() or digest(marker) != row["run_complete_sha256"]:
            raise RuntimeError(f"Accepted run marker differs: {row['experiment_id']}")
    return {row["experiment_id"]: row for row in rows}


def source_data(run_root: Path) -> Path:
    candidates = [run_root / "data" / "bCharacteristicsOLHC_Combo1.mat",
                  run_root / "data.staging" / "bCharacteristicsOLHC_Combo1.mat"]
    found = [p for p in candidates if p.is_file()]
    if len(found) != 1:
        raise RuntimeError(f"Expected exactly one accepted bCharacteristics source: {candidates}")
    return found[0]


def read_experiment(eid: str, accepted: dict[str, str]) -> dict:
    base_path = REPO / "results" / "experiments" / eid / "CTREND" / "CTREND_Base.mat"
    base = loadmat(base_path, squeeze_me=True, struct_as_record=False,
                   variable_names=["vAssetID", "vDates", "mYhat", "mRetPnlOOS", "cResults"])
    ids = np.asarray(base["vAssetID"], dtype=int).reshape(-1)
    weeks = np.asarray(base["vDates"], dtype=int).reshape(-1)
    forecast = np.asarray(base["mYhat"], dtype=float)
    portfolio = base["cResults"].VW
    weights = np.asarray(portfolio.mWts, dtype=float)
    saved = np.asarray(portfolio.mPortRet, dtype=float)[-1, :].reshape(-1)
    if len(set(ids)) != len(ids) or len(set(weeks)) != len(weeks):
        raise RuntimeError(f"Duplicate asset/week key: {eid}")
    if (forecast.shape != (len(ids), len(weeks)) or
            weights.shape != (len(ids), len(weeks), 5) or
            saved.shape != (len(weeks),)):
        raise RuntimeError(f"Saved CTREND axis mismatch: {eid}")
    if np.any(np.isfinite(weights) & (weights < 0)):
        raise RuntimeError(f"Negative opening leg weight: {eid}")

    data_path = source_data(Path(accepted["accepted_run_root"]))
    with h5py.File(data_path) as handle:
        rdata = handle["rData"]
        all_weeks = np.asarray(rdata["yrmoda"], dtype=int).reshape(-1)
        data_ids = np.asarray(handle["rMetaData"]["vID"], dtype=int).reshape(-1)
        selection = np.flatnonzero((all_weeks >= 201416) & (all_weeks <= 202222))
        if not np.array_equal(data_ids, ids) or not np.array_equal(all_weeks[selection], weeks):
            raise RuntimeError(f"Accepted data and result axes differ: {eid}")
        if selection[0] == 0:
            raise RuntimeError(f"No formation-lag observation: {eid}")
        lag_index = selection - 1
        cap = np.asarray(rdata["mME"][:, lag_index], dtype=float)
        close = np.asarray(rdata["mClose"][:, lag_index], dtype=float)
        # The same feature NAME does not imply the same unit across methods.
        # M0/M2 prcvol = log(mean(CMC USD volume * USD price) + 1e-10).
        # M1 prcvol = mean(CMC USD volume). Neither is a weekly total.
        # Export the actual weekly USD sum independently, with its missing
        # rule: M0/M2 allow partial sums; M1 requires all daily core cells.
        prcvol = np.asarray(handle["rChars"]["prcvol"][:, lag_index], dtype=float)
        dollar_volume = np.asarray(rdata["mVolume"][:, lag_index], dtype=float)
        corrected = "_M1_" in eid
        prcvol_definition = ("mean_7day_CMC_USD_volume" if corrected else
                              "log_mean_7day_CMC_USD_volume_times_USD_price_plus_1e-10")
        volume_missing_rule = "all_daily_core_cells" if corrected else "at_least_one_daily_core_cell"
        if "_M0_" in eid:
            payoff = np.asarray(rdata["mReturns"][:, selection], dtype=float)
            payoff_definition = "M0_saved_weekly_return"
        else:
            payoff = np.asarray(base["mRetPnlOOS"], dtype=float)
            payoff_definition = "saved_economic_endpoint_payoff"
    if cap.shape != forecast.shape or close.shape != forecast.shape or payoff.shape != forecast.shape:
        raise RuntimeError(f"Formation/payoff axis mismatch: {eid}")
    return dict(ids=ids, weeks=weeks, forecast=forecast, cap=cap, close=close,
                dollar_volume=dollar_volume, prcvol=prcvol,
                prcvol_definition=prcvol_definition, volume_missing_rule=volume_missing_rule,
                payoff=payoff, weights=weights,
                saved=saved, payoff_definition=payoff_definition,
                base_sha256=digest(base_path), weekly_data_sha256=digest(data_path))


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--experiment", action="append", help="Smoke-test one or more experiment IDs")
    parser.add_argument("--output-dir", type=Path, default=DEFAULT_OUT)
    args = parser.parse_args()
    accepted = accepted_roots()
    experiments = args.experiment or sorted(accepted)
    if len(set(experiments)) != len(experiments) or not set(experiments) <= set(accepted):
        raise ValueError("Unknown or duplicate experiment ID")
    out = args.output_dir.resolve()
    out.mkdir(parents=True, exist_ok=True)
    asset_file = out / "asset_week_forecast_holding_stages.csv.gz"
    summary_file = out / "weekly_forecast_holding_stage_counts.csv"
    temp_asset = out / (asset_file.name + ".partial")
    temp_summary = out / (summary_file.name + ".partial")
    expected_weekly = {}
    existing = ROOT / "outputs" / "E07" / "weekly_forecast_to_holdings.csv"
    with existing.open(newline="", encoding="utf-8") as stream:
        for row in csv.DictReader(stream):
            expected_weekly[(row["experiment_id"], int(row["year_week"]))] = row
    inputs: list[dict] = []
    total_rows = 0
    total_weeks = 0
    try:
        with temp_asset.open("wb") as raw, temp_summary.open("w", newline="", encoding="utf-8") as summ:
            with gzip.GzipFile(filename="", mode="wb", fileobj=raw, mtime=0,
                               compresslevel=2) as compressed:
                with io.TextIOWrapper(compressed, encoding="utf-8", newline="") as text:
                    assets = csv.writer(text)
                    weekly = csv.writer(summ)
                    assets.writerow(FIELDS)
                    weekly.writerow(SUMMARY_FIELDS)
                    for eid in experiments:
                        s = read_experiment(eid, accepted[eid])
                        n = len(s["ids"])
                        for t, week in enumerate(s["weeks"]):
                            f = s["forecast"][:, t]
                            cap = s["cap"][:, t]
                            close = s["close"][:, t]
                            volume = s["dollar_volume"][:, t]
                            payoff = s["payoff"][:, t]
                            low = np.nan_to_num(s["weights"][:, t, 0], nan=0.0)
                            high = np.nan_to_num(s["weights"][:, t, 4], nan=0.0)
                            forecast_ok = np.isfinite(f)
                            low_held = low > 0
                            high_held = high > 0
                            held = low_held | high_held
                            payoff_ok = np.isfinite(payoff)
                            cap_ok = np.isfinite(cap)
                            close_ok = np.isfinite(close)
                            direct = (high - low) * payoff
                            direct_sum = float(np.sum(direct[held])) if np.any(held) and payoff_ok[held].all() else np.nan
                            stored = float(s["saved"][t])
                            old = expected_weekly[(eid, int(week))]
                            if (int(old["asset_universe"]) != n or
                                    int(old["forecast_count"]) != int(forecast_ok.sum()) or
                                    int(old["low_holding_count"]) != int(low_held.sum()) or
                                    int(old["high_holding_count"]) != int(high_held.sum()) or
                                    not np.allclose(float(old["saved_hl_return"]), stored, equal_nan=True)):
                                raise RuntimeError(f"Existing E07 weekly summary differs: {eid} {week}")
                            weekly.writerow((eid, int(week), n, int(forecast_ok.sum()),
                                int((~forecast_ok).sum()), int((forecast_ok & ~held).sum()),
                                int(low_held.sum()), int(high_held.sum()),
                                int((held & ~forecast_ok).sum()), int((held & ~payoff_ok).sum()),
                                int((~forecast_ok & cap_ok & close_ok).sum()), stored,
                                direct_sum, stored - direct_sum if np.isfinite(stored) and np.isfinite(direct_sum) else np.nan,
                                s["payoff_definition"]))
                            for i, asset_id in enumerate(s["ids"]):
                                state = ("both" if low_held[i] and high_held[i] else
                                         "low" if low_held[i] else "high" if high_held[i] else "not_held")
                                assets.writerow((eid, int(week), int(asset_id), int(forecast_ok[i]), f[i],
                                    int(cap_ok[i]), cap[i], int(close_ok[i]), close[i], volume[i],
                                    s["prcvol"][i,t],s["prcvol_definition"],s["volume_missing_rule"],
                                    int(payoff_ok[i]), payoff[i], low[i], high[i], state,
                                    direct[i] if held[i] and payoff_ok[i] else "", s["payoff_definition"]))
                            total_rows += n
                            total_weeks += 1
                        inputs.append({"experiment_id": eid,
                                       "research_run_id": accepted[eid]["research_run_id"],
                                       "run_complete_sha256": accepted[eid]["run_complete_sha256"],
                                       "base_mat_sha256": s["base_sha256"],
                                       "weekly_data_mat_sha256": s["weekly_data_sha256"],
                                       "asset_weeks": n * len(s["weeks"])})
                        print(f"E07_STAGE_PROGRESS {eid} asset_weeks={n*len(s['weeks'])}", flush=True)
        os.replace(temp_asset, asset_file)
        os.replace(temp_summary, summary_file)
        receipt = {"scope": experiments, "asset_week_rows": total_rows,
                   "weekly_rows": total_weeks, "asset_ledger_sha256": digest(asset_file),
                   "weekly_summary_sha256": digest(summary_file), "inputs": inputs,
                   "interpretation": "Saved states only; no unique missing-forecast reason or full reinvestment allocation"}
        (out / "asset_stage_export_receipt.json").write_text(
            json.dumps(receipt, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
        print(f"E07_STAGE_LEDGER_OK experiments={len(experiments)} "
              f"asset_weeks={total_rows} weekly_rows={total_weeks}", flush=True)
    finally:
        temp_asset.unlink(missing_ok=True)
        temp_summary.unlink(missing_ok=True)


if __name__ == "__main__":
    main()
