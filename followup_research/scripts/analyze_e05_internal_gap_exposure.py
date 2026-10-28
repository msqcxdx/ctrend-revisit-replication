#!/usr/bin/env python3
"""Audit whether future-resuming CMC close gaps reach P1 core data or holdings.

The production P1 filler stops at the last *original* close.  A gap is
therefore called internal only after a later quote exists.  This read-only
audit enumerates raw gaps of at least 14 days and checks their actual P1
filled/core cells and saved P0/P1 M1 forecasts and opening holdings.  It
does not infer an exchange delisting or assert a unique missing-data cause.
"""

from __future__ import annotations

import csv
from datetime import date
from hashlib import sha256
import json
import math
from pathlib import Path

import h5py
import numpy as np
from scipy.io import loadmat


ROOT = Path(__file__).resolve().parents[1]
REPO = ROOT.parent
OUT = ROOT / "outputs" / "E05"


def digest(path: Path) -> str:
    h = sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(2**20), b""):
            h.update(block)
    return h.hexdigest()


def accepted() -> dict[str, dict[str, str]]:
    with (ROOT / "outputs/E11/accepted_run_paths.csv").open(newline="") as stream:
        rows = {row["experiment_id"]: row for row in csv.DictReader(stream)}
    for eid in ("P0_M1_D1", "P1_M1_D1"):
        marker = Path(rows[eid]["accepted_run_root"]) / "RUN_COMPLETE"
        if digest(marker) != rows[eid]["run_complete_sha256"]:
            raise RuntimeError(f"Parent run identity changed: {eid}")
    return rows


def data_file(run: Path, name: str) -> Path:
    found = [run / folder / name for folder in ("data", "data.staging")
             if (run / folder / name).is_file()]
    if len(found) != 1:
        raise RuntimeError(f"Expected one accepted input {run}/{name}")
    return found[0]


def read_raw(path: Path) -> tuple[list[date], np.ndarray, np.ndarray]:
    days: list[date] = []
    values: list[list[float]] = []
    with path.open(newline="", encoding="utf-8") as stream:
        reader = csv.reader(stream)
        header = next(reader)
        ids = np.array([int(x) for x in header[1:]], dtype=int)
        if len(set(ids)) != len(ids):
            raise RuntimeError("Raw close has duplicate CMC IDs")
        for line in reader:
            if len(line) != len(header):
                raise RuntimeError("Raw close row has wrong width")
            days.append(date.fromisoformat(line[0]))
            values.append([float(x) if x else math.nan for x in line[1:]])
    if any((b-a).days != 1 for a,b in zip(days[:-1],days[1:])):
        raise RuntimeError("Raw close calendar is not daily-contiguous")
    return days, ids, np.asarray(values, dtype=float).T


def liu_week_keys(days: list[date]) -> np.ndarray:
    """Match production fResampleLiuEtAl's seven-row calendar-year blocks."""
    years = np.array([d.year for d in days], dtype=int)
    keys = np.zeros(len(days), dtype=int)
    for year in np.unique(years):
        positions = np.flatnonzero(years == year)
        n_weeks = len(positions) // 7
        if n_weeks == 0:
            continue
        serial = np.minimum(np.arange(len(positions)) // 7 + 1, n_weeks)
        keys[positions] = year * 100 + serial
    return keys


def load_b0(path: Path) -> dict[str, np.ndarray]:
    with h5py.File(path) as handle:
        out = {key: np.asarray(handle[key], dtype=float)
               for key in ("mClosePnlRaw", "mClose", "mME")}
        out["ids"] = np.asarray(handle["rMetaData"]["vID"], dtype=int).ravel()
        out["dates"] = np.asarray(handle["yrmoda"], dtype=int).ravel()
    return out


def load_base(eid: str) -> dict[str, np.ndarray]:
    path = REPO / "results" / "experiments" / eid / "CTREND/CTREND_Base.mat"
    obj = loadmat(path, squeeze_me=True, struct_as_record=False,
                  variable_names=["vAssetID", "vDates", "mYhat", "mRetPnlOOS", "cResults"])
    w = np.asarray(obj["cResults"].VW.mWts, dtype=float)
    return {"ids": np.asarray(obj["vAssetID"], dtype=int).ravel(),
            "weeks": np.asarray(obj["vDates"], dtype=int).ravel(),
            "forecast": np.asarray(obj["mYhat"], dtype=float),
            "payoff": np.asarray(obj["mRetPnlOOS"], dtype=float),
            "weights": w,
            "held": np.isfinite(w[:, :, 0]) & (w[:, :, 0] > 0) |
                    np.isfinite(w[:, :, -1]) & (w[:, :, -1] > 0),
            "sha256": digest(path)}


def main() -> None:
    runs = accepted()
    p1run = Path(runs["P1_M1_D1"]["accepted_run_root"])
    raw_path = data_file(p1run, "close_cmc.csv")
    b0_path = data_file(p1run, "b0DataOLHC.mat")
    days, raw_ids, raw = read_raw(raw_path)
    core = load_b0(b0_path)
    numeric_dates = np.array([d.year*10000+d.month*100+d.day for d in days])
    if not np.array_equal(numeric_dates, core["dates"]):
        raise RuntimeError("Raw/B0 dates disagree")
    if any(x.shape != (len(core["ids"]), len(days)) for x in
           (core["mClosePnlRaw"], core["mClose"], core["mME"])):
        raise RuntimeError("Accepted B0 axes disagree")
    raw_index = {int(x): i for i,x in enumerate(raw_ids)}
    p0, p1 = load_base("P0_M1_D1"), load_base("P1_M1_D1")
    model_index = {name: {int(x): i for i,x in enumerate(data["ids"])}
                   for name,data in (("p0",p0),("p1",p1))}
    week_index = {name: {int(x): i for i,x in enumerate(data["weeks"])}
                  for name,data in (("p0",p0),("p1",p1))}
    if not np.array_equal(p0["weeks"], p1["weeks"]):
        raise RuntimeError("P0/P1 baseline week axes disagree")
    week_keys = liu_week_keys(days)
    week_spans: dict[int, tuple[int,int]] = {}
    for k,key in enumerate(week_keys):
        if key not in week_spans:
            week_spans[int(key)] = (k,k)
        else:
            week_spans[int(key)] = (week_spans[int(key)][0],k)
    rows: list[dict] = []
    held_details: list[dict] = []
    for j, aid in enumerate(core["ids"]):
        observed = np.flatnonzero(np.isfinite(raw[raw_index[int(aid)]]) &
                                  (raw[raw_index[int(aid)]] > 0))
        for left,right in zip(observed[:-1],observed[1:]):
            length = int(right-left-1)
            if length < 14:
                continue
            gap = slice(left+1,right)
            keys = set(map(int, week_keys[gap]))
            fully_inside = {key for key in keys if
                            week_spans[key][0] >= left+1 and week_spans[key][1] < right}
            outcome: dict[str, int] = {}
            for label,base in (("p0",p0),("p1",p1)):
                asset = model_index[label].get(int(aid))
                positions = [week_index[label][x] for x in keys
                             if x in week_index[label]]
                full_positions = [week_index[label][x] for x in fully_inside
                                  if x in week_index[label]]
                outcome[label+"_forecast_weeks"] = (sum(bool(x) for x in
                    np.isfinite(base["forecast"][asset,positions]))
                    if asset is not None else 0)
                outcome[label+"_held_weeks"] = (sum(bool(x) for x in
                    base["held"][asset,positions]) if asset is not None else 0)
                outcome[label+"_forecast_fully_inside_weeks"] = (sum(bool(x) for x in
                    np.isfinite(base["forecast"][asset,full_positions]))
                    if asset is not None else 0)
                outcome[label+"_held_fully_inside_weeks"] = (sum(bool(x) for x in
                    base["held"][asset,full_positions]) if asset is not None else 0)
                if asset is not None:
                    for position in positions:
                        if not base["held"][asset,position]:
                            continue
                        key = int(base["weeks"][position])
                        w_low = float(base["weights"][asset,position,0])
                        w_high = float(base["weights"][asset,position,-1])
                        payoff = float(base["payoff"][asset,position])
                        held_details.append({
                            "method": label.upper(), "cmcid": int(aid), "year_week": key,
                            "last_pre_gap_quote": days[left].isoformat(),
                            "first_post_gap_quote": days[right].isoformat(),
                            "week_fully_inside_raw_close_gap": int(key in fully_inside),
                            "week_first_date": days[week_spans[key][0]].isoformat(),
                            "week_last_date": days[week_spans[key][1]].isoformat(),
                            "low_opening_weight": w_low,
                            "high_opening_weight": w_high,
                            "saved_economic_asset_payoff": payoff,
                            "opening_weight_signed_direct_hl_contribution":
                                ((w_high if np.isfinite(w_high) else 0.0) -
                                 (w_low if np.isfinite(w_low) else 0.0)) * payoff,
                            "scope": "direct_opening_contribution_not_full_reinvestment_ledger"})
            rows.append({"cmcid": int(aid), "last_pre_gap_quote": days[left].isoformat(),
                         "first_post_gap_quote": days[right].isoformat(),
                         "missing_calendar_days": length,
                         "full_ltw_week_blocks_inside_gap": len(fully_inside),
                         "p1_economic_close_filled_days": int(np.isfinite(
                             core["mClosePnlRaw"][j,gap]).sum()),
                         "p1_core_close_finite_days": int(np.isfinite(
                             core["mClose"][j,gap]).sum()),
                         "p1_core_market_cap_finite_days": int(np.isfinite(
                             core["mME"][j,gap]).sum()),
                         "p1_core_price_and_cap_finite_days": int((np.isfinite(
                             core["mClose"][j,gap]) & np.isfinite(
                             core["mME"][j,gap])).sum()),
                         **outcome,
                         "interpretation": "raw_CMC_gap_not_verified_delisting_or_relisting"})
    if not rows:
        raise RuntimeError("No internal gaps met the prespecified 14-day threshold")
    OUT.mkdir(parents=True, exist_ok=True)
    path = OUT / "raw_internal_close_gaps_14d_asset_exposure.csv"
    with path.open("w", newline="", encoding="utf-8") as stream:
        writer = csv.DictWriter(stream, fieldnames=list(rows[0]))
        writer.writeheader();writer.writerows(rows)
    detail_path = OUT / "raw_internal_gap_held_week_details.csv"
    with detail_path.open("w", newline="", encoding="utf-8") as stream:
        writer = csv.DictWriter(stream, fieldnames=list(held_details[0]))
        writer.writeheader(); writer.writerows(held_details)
    summary = {"gap_rows": len(rows), "assets": len({r["cmcid"] for r in rows}),
               "gap_days": sum(r["missing_calendar_days"] for r in rows),
               "gaps_with_p1_core_price_and_cap": sum(r["p1_core_price_and_cap_finite_days"]>0 for r in rows),
               "gaps_with_p1_forecast": sum(r["p1_forecast_weeks"]>0 for r in rows),
               "gaps_with_p1_holding": sum(r["p1_held_weeks"]>0 for r in rows),
               "gaps_with_p0_holding": sum(r["p0_held_weeks"]>0 for r in rows),
               "gaps_with_p1_holding_fully_inside": sum(r["p1_held_fully_inside_weeks"]>0 for r in rows),
               "gaps_with_p0_holding_fully_inside": sum(r["p0_held_fully_inside_weeks"]>0 for r in rows),
               "held_asset_gap_week_rows": len(held_details),
               "held_fully_inside_gap_week_rows": sum(r["week_fully_inside_raw_close_gap"] for r in held_details),
               "scope": "CMC_raw_close_gaps_to_accepted_B0_core_and_saved_M1_base_holdings_not_event_causality",
               "inputs": {"raw_close_sha256": digest(raw_path),
                          "p1_b0_sha256": digest(b0_path),
                          "p0_base_sha256": p0["sha256"],
                          "p1_base_sha256": p1["sha256"],
                          "p0_run_complete_sha256": runs["P0_M1_D1"]["run_complete_sha256"],
                          "p1_run_complete_sha256": runs["P1_M1_D1"]["run_complete_sha256"]},
               "output_sha256": digest(path),
               "held_week_detail_sha256": digest(detail_path)}
    (OUT / "raw_internal_close_gaps_14d_receipt.json").write_text(
        json.dumps(summary, indent=2, ensure_ascii=False)+"\n", encoding="utf-8")
    print("E05_INTERNAL_GAP_AUDIT_OK", summary["gap_rows"],
          summary["gaps_with_p1_core_price_and_cap"],
          summary["gaps_with_p1_holding"])


if __name__ == "__main__":
    main()
