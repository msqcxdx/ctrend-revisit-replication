#!/usr/bin/env python3
"""Pre-formation bull/bear and volatility-state paired method contrasts.

The state at week t uses only project-built market-factor observations through
t-1.  A 12-week trailing return defines bull/bear; the 12-week trailing
volatility is compared with the median of the 52 trailing-volatility readings
available through t-1.  These are descriptive state definitions, not a
historical independent market chronology or a method-selection rule.
"""

from __future__ import annotations

import csv
from pathlib import Path

import numpy as np

from paired_stats import annual_sharpe, bootstrap_paired, newey_west


ROOT = Path(__file__).resolve().parents[1]
REPO = ROOT.parent
OUT = ROOT / "outputs" / "E11"


def read(path: Path) -> list[dict]:
    with path.open(newline="", encoding="utf-8") as handle:
        return list(csv.DictReader(handle))


def state_labels(market: np.ndarray) -> tuple[np.ndarray, np.ndarray]:
    n = len(market)
    trend = np.full(n, "unknown", dtype=object)
    volatility = np.full(n, "unknown", dtype=object)
    prior_vol = np.full(n, np.nan)
    for t in range(12, n):
        history = market[t-12:t]
        if np.isfinite(history).all():
            trend[t] = "prior_12w_positive" if np.prod(1+history)-1 >= 0 else "prior_12w_negative"
            prior_vol[t] = np.std(history, ddof=1)
        # The 52 comparator readings all describe windows ending before t.
        if t >= 64 and np.isfinite(prior_vol[t-52:t+1]).all():
            cutoff = float(np.median(prior_vol[t-52:t]))
            volatility[t] = "prior_vol_high" if prior_vol[t] >= cutoff else "prior_vol_low"
    return trend, volatility


def main() -> None:
    weekly = read(REPO / "results" / "comparisons" / "source_tables" /
                  "common_week" / "eighteen_experiment_weekly_returns.csv")
    weeks = np.array([int(row["year_week"]) for row in weekly], dtype=int)
    output = []
    states_out = []
    for p in (0, 1):
        for d in (0, 1, 2):
            base = read(ROOT / "outputs" / "E01" / f"P{p}_M1_D{d}" /
                        "e01_weekly_factors.csv")
            if len(base) != len(weekly) or not np.array_equal(
                    [int(float(row["week_key"])) for row in base], weeks):
                raise ValueError(f"State and factor calendar mismatch: P{p} D{d}")
            market = np.array([float(row["own_cmkt"]) for row in base])
            controls = np.array([[float(row[f"external_{name}"])
                                  for name in ("cmkt", "csize", "cmom")]
                                 for row in base])
            trend, volatility = state_labels(market)
            for week, trend_name, vol_name in zip(weeks, trend, volatility):
                states_out.append({"p": p, "d": d, "week_key": int(week),
                                   "prior_12w_market_state": trend_name,
                                   "prior_market_volatility_state": vol_name,
                                   "information_cutoff": "strictly_before_target_week"})
            for before, after in ((0, 2), (2, 1), (0, 1)):
                a = np.array([float(row[f"P{p}_M{before}_D{d}"]) for row in weekly])
                b = np.array([float(row[f"P{p}_M{after}_D{d}"]) for row in weekly])
                for dimension, labels, names in (
                    ("market_12w", trend, ("prior_12w_positive", "prior_12w_negative")),
                    ("market_volatility", volatility, ("prior_vol_high", "prior_vol_low")),
                ):
                    for state in names:
                        include = labels == state
                        valid = include & np.isfinite(a) & np.isfinite(b) & np.isfinite(controls).all(axis=1)
                        if valid.sum() < 30:
                            output.append({"p": p, "d": d, "from_method": f"M{before}",
                                           "to_method": f"M{after}", "state_dimension": dimension,
                                           "state": state, "paired_weeks": int(valid.sum()),
                                           "status": "too_few_identified_weeks"})
                            continue
                        aa = np.where(valid, a, np.nan)
                        bb = np.where(valid, b, np.nan)
                        diff = bb-aa
                        alpha = newey_west(diff, controls)
                        boot = bootstrap_paired(bb, aa,
                                lambda x, y: annual_sharpe(x)-annual_sharpe(y),
                                reps=1000, block=8,
                                seed=20261026+1000*p+100*d+10*before+after+
                                     (0 if dimension == "market_12w" else 2)+
                                     (0 if state in ("prior_12w_positive", "prior_vol_high") else 1))
                        output.append({
                            "p": p, "d": d, "from_method": f"M{before}",
                            "to_method": f"M{after}", "state_dimension": dimension,
                            "state": state, "paired_weeks": int(valid.sum()),
                            "mean_difference_pct_per_week": 100*float(np.nanmean(diff)),
                            "alpha_difference_pct_per_week": 100*alpha["alpha"],
                            "alpha_hac_ci_low_pct": 100*alpha["alpha_ci_low"],
                            "alpha_hac_ci_high_pct": 100*alpha["alpha_ci_high"],
                            "alpha_hac_p": alpha["alpha_p_hac"],
                            "annual_sharpe_from": annual_sharpe(aa),
                            "annual_sharpe_to": annual_sharpe(bb),
                            "annual_sharpe_difference": boot["estimate"],
                            "sharpe_block8_ci_low": boot["ci_low"],
                            "sharpe_block8_ci_high": boot["ci_high"],
                            "sharpe_block8_centered_p": boot["centered_p"],
                            "status": "descriptive_market_state_no_selection_by_state",
                        })
            print(f"E11_STATES_PROGRESS P{p}_D{d}", flush=True)
    for file, rows in ((OUT / "formation_known_market_states.csv", states_out),
                       (OUT / "paired_method_by_market_state.csv", output)):
        with file.open("w", newline="", encoding="utf-8") as handle:
            fields = list(dict.fromkeys(key for row in rows for key in row))
            writer = csv.DictWriter(handle, fieldnames=fields)
            writer.writeheader()
            writer.writerows(rows)
    print(f"E11_STATES_OK state_rows={len(states_out)} contrasts={len(output)}")


if __name__ == "__main__":
    main()
