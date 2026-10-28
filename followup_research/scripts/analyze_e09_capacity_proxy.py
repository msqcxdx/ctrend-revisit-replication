#!/usr/bin/env python3
"""Bound opening-leg capacity using lagged CMC aggregate dollar volume.

This is a formation-time liquidity *proxy*, not exchange order-book depth,
actual short availability, an executable fill, or a real brokerage account.
Only accepted M1 saved baseline holdings are evaluated.  Missing/zero proxy
volume is reported separately rather than imputed as infinite capacity.
"""

from __future__ import annotations

import csv
import gzip
from collections import defaultdict
from itertools import groupby
from pathlib import Path

import h5py
import numpy as np
from scipy.io import loadmat


ROOT = Path(__file__).resolve().parents[1]
REPO = ROOT.parent
OUT = ROOT / "outputs" / "E09"
CAPITAL_USD = (1_000_000, 10_000_000, 100_000_000)


def write(path: Path, rows: list[dict]) -> None:
    with path.open("w", newline="", encoding="utf-8") as handle:
        writer = csv.DictWriter(handle, fieldnames=list(rows[0]))
        writer.writeheader()
        writer.writerows(rows)


def proxy_capacity(weights,volume):
    """Full-leg participation constraint, not executable venue capacity.

    A missing selected quote-volume constraint is unknown, not zero weight.
    A known zero binds at zero. The observed-subset minimum is separately
    returned and never substituted for a complete-leg result.
    """
    weights=np.asarray(weights,float);volume=np.asarray(volume,float)
    if weights.shape!=volume.shape or (len(weights) and
        (not np.isfinite(weights).all() or np.any(weights<=0))):
        raise ValueError('Expected matching strictly positive selected weights')
    observed=np.isfinite(volume)&(volume>=0)
    constraints=volume[observed]/weights[observed]
    complete=bool(len(weights)) and bool(observed.all())
    bound=float(constraints.min()) if complete else np.nan
    return bound,complete,observed,constraints


def source_data(eid: str, run: Path) -> tuple[dict[int, int], dict[int, int], np.ndarray]:
    baseline = loadmat(REPO / "results" / "experiments" / eid / "CTREND" /
                       "CTREND_Base.mat", squeeze_me=True, struct_as_record=False,
                       variable_names=["vAssetID", "vDates"])
    ids = np.asarray(baseline["vAssetID"], dtype=int).ravel()
    weeks = np.asarray(baseline["vDates"], dtype=int).ravel()
    path = run / "data" / "bCharacteristicsOLHC_Combo1.mat"
    if not path.is_file():
        path = run / "data.staging" / "bCharacteristicsOLHC_Combo1.mat"
    with h5py.File(path) as handle:
        all_weeks = np.asarray(handle["rData"]["yrmoda"][:], dtype=int).ravel()
        volume = np.asarray(handle["rChars"]["prcvol"][:], dtype=float)
    positions = np.flatnonzero((all_weeks >= 201416) & (all_weeks <= 202222))
    if not np.array_equal(all_weeks[positions], weeks) or volume.shape[0] != len(ids):
        raise ValueError(f"M1 formation-volume axes disagree for {eid}")
    return ({int(asset): pos for pos, asset in enumerate(ids)},
            {int(week): int(positions[i])-1 for i, week in enumerate(weeks)}, volume)


def main() -> None:
    runs = {row["experiment_id"]: Path(row["accepted_run_root"])
            for row in csv.DictReader((ROOT / "outputs" / "E11" /
                                       "accepted_run_paths.csv").open(newline="", encoding="utf-8"))}
    weekly: list[dict] = []
    expected_rows=0
    with gzip.open(ROOT / "outputs" / "E08" /
                   "asset_week_direct_contributions.csv.gz", "rt",
                   newline="", encoding="utf-8") as handle:
        rows = (row for row in csv.DictReader(handle) if "_M1_" in row["experiment_id"])
        for eid, experiment_group in groupby(rows, lambda row: row["experiment_id"]):
            if eid not in runs or not (runs[eid] / "RUN_COMPLETE").is_file():
                raise ValueError(f"Missing accepted M1 production run: {eid}")
            asset_pos, formation_pos, volume = source_data(eid, runs[eid])
            expected_rows+=2*len(formation_pos)
            by_week: dict[int, list[dict]] = defaultdict(list)
            for holding in experiment_group:
                by_week[int(holding["week_key"])].append(holding)
            if not set(by_week).issubset(formation_pos):
                raise ValueError(f"Saved M1 holdings contain a non-scheduled week: {eid}")
            for week in formation_pos:
                holdings = by_week[week]
                for leg in ("long", "short"):
                    leg_rows = [row for row in holdings if row["leg"] == leg]
                    weights = np.array([float(row["opening_weight"]) for row in leg_rows])
                    formation_volume = np.array([
                        volume[asset_pos[int(row["cmcid"])], formation_pos[week]]
                        for row in leg_rows], dtype=float)
                    usable = np.isfinite(formation_volume) & (formation_volume > 0)
                    full_bound,complete,observed,constraints=proxy_capacity(weights,formation_volume)
                    zero = observed & (formation_volume == 0)
                    # A known zero is a binding zero capacity. An unobserved
                    # selected volume makes full-leg capacity unidentified,
                    # even if the other selected assets are very liquid.
                    row = {
                        "experiment_id": eid, "week_key": week, "leg": leg,
                        "selected_assets": len(leg_rows),
                        "assets_with_positive_finite_lagged_cmc_dollar_volume": int(usable.sum()),
                        "all_selected_proxy_volumes_observed": int(complete),
                        "assets_with_observed_zero_volume":int(zero.sum()),
                        "assets_with_unknown_or_invalid_volume":int((~observed).sum()),
                        "one_percent_participation_opening_capital_bound_usd": .01*full_bound,
                        "five_percent_participation_opening_capital_bound_usd": .05*full_bound,
                        "ten_percent_participation_opening_capital_bound_usd": .10*full_bound,
                        "five_pct_observed_subset_bound_not_full_leg":float(.05*constraints.min()) if len(constraints) else np.nan,
                        "volume_source": "lagged_CMC_aggregated_prcvol_characteristic",
                        "scope": "opening_position_proxy_only_no_turnover_or_order_book",
                    }
                    for capital in CAPITAL_USD:
                        key = f"max_proxy_participation_for_{capital}_usd_capital"
                        row[key] = (np.inf if zero.any() else float(np.max(
                            capital*weights/formation_volume))) if complete else np.nan
                    weekly.append(row)
            print(f"E09_CAPACITY_PROGRESS {eid}", flush=True)
    if len(weekly) != expected_rows:
        raise ValueError(f"Unexpected M1 leg-week count: {len(weekly)}")
    OUT.mkdir(parents=True, exist_ok=True)
    write(OUT / "opening_liquidity_proxy_by_leg_week.csv", weekly)
    summary = []
    for eid in sorted({row["experiment_id"] for row in weekly}):
        for leg in ("long", "short"):
            group = [row for row in weekly if row["experiment_id"] == eid and row["leg"] == leg]
            full = [row for row in group if row["all_selected_proxy_volumes_observed"]]
            cap = np.array([row["five_percent_participation_opening_capital_bound_usd"]
                            for row in full], dtype=float)
            summary.append({
                "experiment_id": eid, "leg": leg, "scheduled_weeks": len(group),
                "weeks_with_complete_nonnegative_aggregate_volume_proxy": len(full),
                "weeks_with_known_zero_volume_holding":sum(bool(row["assets_with_observed_zero_volume"]) for row in full),
                "median_five_pct_opening_capital_bound_usd": float(np.median(cap)) if len(cap) else np.nan,
                "p05_five_pct_opening_capital_bound_usd": float(np.quantile(cap, .05)) if len(cap) else np.nan,
                "complete_proxy_weeks_with_1m_capital_over_5pct": int(np.count_nonzero(cap < 1_000_000)),
                "complete_proxy_weeks_with_10m_capital_over_5pct": int(np.count_nonzero(cap < 10_000_000)),
                "complete_proxy_weeks_with_100m_capital_over_5pct": int(np.count_nonzero(cap < 100_000_000)),
                "interpretation": "participation_constraint_under_aggregate_volume_proxy_not_true_execution_bound",
            })
    write(OUT / "opening_liquidity_proxy_summary.csv", summary)
    print(f"E09_CAPACITY_PROXY_OK weekly_leg_rows={len(weekly)} summary_rows={len(summary)}")


if __name__ == "__main__":
    main()
