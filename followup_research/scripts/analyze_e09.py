#!/usr/bin/env python3
"""Recompute statistical H-L net returns and conditional short-fee scenarios.

This script does not infer historical exchange-level borrowability, depth,
intraday margin calls, or execution prices from aggregate CMC data.
"""

from __future__ import annotations

import csv
from pathlib import Path
import sys

import numpy as np
from scipy.io import loadmat

from paired_stats import annual_sharpe, newey_west


ROOT = Path(__file__).resolve().parents[1]
REPO = ROOT.parent
OUT = ROOT / "outputs" / "E09"
FEES = ((0.004, 0.003), (0.005, 0.004), (0.006, 0.005))
ANNUAL_SHORT_BORROW_SCENARIOS = (0.0, 0.10, 0.50, 1.00)


def write(path: Path, rows: list[dict]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", newline="", encoding="utf-8") as fh:
        writer = csv.DictWriter(fh, fieldnames=list(rows[0]))
        writer.writeheader()
        writer.writerows(rows)


def main() -> int:
    fixed_rows = []
    account_rows = []
    # Only M1 stores the full, asset-week paired L1 cost basis. M2 does not;
    # using its scalar average turnover would silently change the estimand.
    for p in (0, 1):
        for method in (1,):
            for d in (0, 1, 2):
                experiment = f"P{p}_M{method}_D{d}"
                file = REPO / "results" / "experiments" / experiment / "CTREND" / "CTREND_Base.mat"
                r = loadmat(file, squeeze_me=True, struct_as_record=False)
                portfolio = r["cResults"].VW
                gross = np.asarray(portfolio.mPortRet[-1], dtype=float).reshape(-1)
                cost = np.asarray(portfolio.mCostBaseFull, dtype=float)
                weeks = np.asarray(r["vDates"], dtype=int).reshape(-1)
                if cost.shape != (len(weeks), 6):
                    raise ValueError(f"Saved cost-base axes disagree: {experiment}")
                pair = np.isfinite(gross) & np.isfinite(cost[:, 0]) & np.isfinite(cost[:, 4])
                if pair.sum() < 100:
                    raise ValueError(f"Insufficient paired gross/cost weeks: {experiment}")
                for short_rate, long_rate in FEES:
                    net = gross-short_rate*cost[:, 0]-long_rate*cost[:, 4]
                    net[~pair] = np.nan
                    stats = newey_west(net, np.empty((len(weeks), 0)))
                    fixed_rows.append({
                        "experiment_id": experiment,
                        "short_trade_cost_per_full_l1": short_rate,
                        "long_trade_cost_per_full_l1": long_rate,
                        "n_paired": int(pair.sum()),
                        "gross_paired_mean_pct": 100*float(gross[pair].mean()),
                        "net_mean_pct": 100*float(np.nanmean(net)),
                        "net_hac_ci_low_pct": 100*stats["alpha_ci_low"],
                        "net_hac_ci_high_pct": 100*stats["alpha_ci_high"],
                        "net_annual_sharpe": annual_sharpe(net),
                        "mean_low_leg_full_l1": float(cost[pair, 0].mean()),
                        "mean_high_leg_full_l1": float(cost[pair, 4].mean()),
                        "weekly_end_equity_nonpositive_count": int(np.count_nonzero(net[pair] <= -1)),
                    })
                # A fixed fee on unit weekly opening short notional is a
                # scenario, NOT a mathematical upper/lower bound on the
                # real borrowing bill (which depends on intraperiod notional).
                for annual_borrow in ANNUAL_SHORT_BORROW_SCENARIOS:
                    short_rate, long_rate = FEES[1]
                    net = gross-short_rate*cost[:, 0]-long_rate*cost[:, 4]-annual_borrow/52
                    net[~pair] = np.nan
                    account_rows.append({
                        "experiment_id": experiment,
                        "trade_cost_scenario": "middle_0.5pct_short_0.4pct_long",
                        "annual_short_borrow_fee_assumed": annual_borrow,
                        "gross_long_notional": 1.0, "gross_short_notional": 1.0,
                        "initial_equity_assumed": 1.0,
                        "n_paired": int(pair.sum()),
                        "conditional_weekly_net_mean_pct": 100*float(np.nanmean(net)),
                        "conditional_weekly_net_annual_sharpe": annual_sharpe(net),
                        "week_end_nonpositive_equity_count": int(np.count_nonzero(net[pair] <= -1)),
                        "historical_borrowability_verified": 0,
                        "intraday_margin_path_observed": 0,
                        "interpretation": "unit_opening_notional_fee_scenario_not_mathematical_bound_or_executable_account",
                    })
    write(OUT / "fixed_transaction_fee_statistical_factor.csv", fixed_rows)
    write(OUT / "conditional_borrow_fee_scenarios_not_account.csv", account_rows)
    print(f"E09_FIXED_FEES_OK configurations=6 fee_rows={len(fixed_rows)} "
          f"conditional_rows={len(account_rows)}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
