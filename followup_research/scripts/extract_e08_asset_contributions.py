#!/usr/bin/env python3
"""Extract all-week asset contributions from frozen M1/M2 baseline factors.

Direct contribution uses opening VW weight times saved asset economic payoff.
Same-leg intraweek liquidation/reinvestment is retained as a separate
weekly accounting residual, not spuriously allocated to a receiving coin.
"""

from __future__ import annotations

import csv
import gzip
from pathlib import Path
import sys

import numpy as np
import h5py
from scipy.io import loadmat
from accepted_run_roots import accepted_roots


ROOT = Path(__file__).resolve().parents[1]
REPO = ROOT.parent
OUT = ROOT / "outputs" / "E08"
M0_RUNS = tuple(f"P{p}_M0_D{d}" for p in (0, 1) for d in (0, 1, 2))


def coin_names() -> dict[int, tuple[str, str]]:
    r = loadmat(REPO / "data" / "raw" / "common" / "MetaData.mat",
                squeeze_me=True, struct_as_record=False)["rMetaData"]
    return {int(asset): (str(symbol), str(name)) for asset, symbol, name in
            zip(r.vID, r.cSymbol, r.cName)}


def audit_events(audit: object, n_weeks: int) -> np.ndarray:
    if isinstance(audit, np.ndarray) and len(audit) >= 5:
        low, high = audit[0], audit[4]
        if hasattr(low, "vEventDateCount") and hasattr(high, "vEventDateCount"):
            low_events = np.asarray(low.vEventDateCount).reshape(-1)
            high_events = np.asarray(high.vEventDateCount).reshape(-1)
            if len(low_events) == n_weeks and len(high_events) == n_weeks:
                return (low_events+high_events) > 0
    return np.zeros(n_weeks, dtype=bool)


def main() -> int:
    OUT.mkdir(parents=True, exist_ok=True)
    names = coin_names()
    asset_file = OUT / "asset_week_direct_contributions.csv.gz"
    weekly_file = OUT / "weekly_concentration_and_reconciliation.csv"
    asset_fields = ("experiment_id", "week_key", "cmcid", "symbol", "name",
                    "leg", "opening_weight", "asset_payoff_used_for_baseline",
                    "payoff_source", "signed_direct_hl_contribution")
    weekly_fields = ("experiment_id", "week_key", "n_long", "n_short",
                     "max_long_weight", "max_short_weight",
                     "top3_short_weight", "short_weight_hhi",
                     "direct_hl_sum", "saved_hl", "accounting_residual",
                     "has_same_leg_exit_event", "missing_selected_payoff")
    n_asset_rows = 0
    n_week_rows = 0
    accepted_m0_runs = accepted_roots(M0_RUNS)
    with gzip.open(asset_file, "wt", newline="", encoding="utf-8", compresslevel=6) as a_fh, \
         weekly_file.open("w", newline="", encoding="utf-8") as w_fh:
        asset_writer = csv.DictWriter(a_fh, fieldnames=asset_fields)
        weekly_writer = csv.DictWriter(w_fh, fieldnames=weekly_fields)
        asset_writer.writeheader()
        weekly_writer.writeheader()
        for p in (0, 1):
            for method in (0, 2, 1):
                for d in (0, 1, 2):
                    experiment = f"P{p}_M{method}_D{d}"
                    mat = REPO / "results" / "experiments" / experiment / "CTREND" / "CTREND_Base.mat"
                    result = loadmat(mat, squeeze_me=True, struct_as_record=False)
                    asset_ids = np.asarray(result["vAssetID"], dtype=int).reshape(-1)
                    weeks = np.asarray(result["vDates"], dtype=int).reshape(-1)
                    if method == 0:
                        run = accepted_m0_runs[experiment]
                        if not (run / "RUN_COMPLETE").is_file():
                            raise ValueError(f"M0 archive not accepted: {experiment}")
                        weekly_mat = run / "data.staging" / "bCharacteristicsOLHC_Combo1.mat"
                        with h5py.File(weekly_mat) as source:
                            all_weeks = np.asarray(source["rData"]["yrmoda"]).reshape(-1).astype(int)
                            selected_weeks = (all_weeks >= 201416) & (all_weeks <= 202222)
                            if not np.array_equal(all_weeks[selected_weeks], weeks):
                                raise ValueError(f"M0 weekly payoff calendar mismatch: {experiment}")
                            payoff = np.asarray(source["rData"]["mReturns"][:, selected_weeks])
                        payoff_source = "M0_baseline_weekly_return"
                    else:
                        payoff = np.asarray(result["mRetPnlOOS"])
                        payoff_source = "saved_economic_endpoint_payoff"
                    portfolios = result["cResults"].VW
                    weights = np.asarray(portfolios.mWts)
                    returns = np.asarray(portfolios.mPortRet[-1]).reshape(-1)
                    if weights.shape != (len(asset_ids), len(weeks), 5) or payoff.shape != weights.shape[:2]:
                        raise ValueError(f"Asset/week/weight axes disagree for {experiment}")
                    event = audit_events(getattr(portfolios, "cSameLegReinvestmentAudit", None), len(weeks))
                    for t, week in enumerate(weeks):
                        low = np.nan_to_num(weights[:, t, 0], nan=0.0)
                        high = np.nan_to_num(weights[:, t, 4], nan=0.0)
                        selected = (low != 0) | (high != 0)
                        missing = np.any(selected & ~np.isfinite(payoff[:, t]))
                        direct = (high-low)*payoff[:, t]
                        direct_sum = float(np.nansum(direct)) if not missing else np.nan
                        stored = float(returns[t])
                        residual = stored-direct_sum if np.isfinite(stored) and np.isfinite(direct_sum) else np.nan
                        if np.isfinite(stored) and not event[t] and not missing and abs(residual) > 1e-10:
                            raise ValueError(f"Non-event payoff identity fails {experiment} {week}: {residual}")
                        for leg, weight, sign in (("long", high, 1), ("short", low, -1)):
                            for i in np.flatnonzero(weight != 0):
                                symbol, name = names.get(int(asset_ids[i]), ("", ""))
                                asset_writer.writerow({
                                    "experiment_id": experiment, "week_key": int(week),
                                    "cmcid": int(asset_ids[i]), "symbol": symbol, "name": name,
                                    "leg": leg, "opening_weight": float(weight[i]),
                                    "asset_payoff_used_for_baseline": float(payoff[i, t]),
                                    "payoff_source": payoff_source,
                                    "signed_direct_hl_contribution": float(sign*weight[i]*payoff[i, t]),
                                })
                                n_asset_rows += 1
                        short_positive = low[low > 0]
                        weekly_writer.writerow({
                            "experiment_id": experiment, "week_key": int(week),
                            "n_long": int(np.count_nonzero(high)),
                            "n_short": int(np.count_nonzero(low)),
                            "max_long_weight": float(high.max(initial=0)),
                            "max_short_weight": float(low.max(initial=0)),
                            "top3_short_weight": float(np.sort(short_positive)[-3:].sum()),
                            "short_weight_hhi": float(np.square(short_positive).sum()),
                            "direct_hl_sum": direct_sum, "saved_hl": stored,
                            "accounting_residual": residual,
                            "has_same_leg_exit_event": int(event[t]),
                            "missing_selected_payoff": int(missing),
                        })
                        n_week_rows += 1
    print(f"E08_ASSET_CONTRIBUTIONS_OK configurations=18 "
          f"asset_rows={n_asset_rows} week_rows={n_week_rows}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
