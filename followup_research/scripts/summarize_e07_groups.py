#!/usr/bin/env python3
"""Summarize matched forecast-support groups without assigning causal labels."""

from __future__ import annotations

import csv
from pathlib import Path

import numpy as np


ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "outputs" / "E07"


def records(path: Path) -> list[dict]:
    with path.open(newline="", encoding="utf-8") as handle:
        return list(csv.DictReader(handle))


def finite_median(rows: list[dict], key: str) -> float:
    values = np.array([float(row[key]) for row in rows], dtype=float)
    values = values[np.isfinite(values)]
    return float(np.median(values)) if len(values) else np.nan


def main() -> None:
    groups = records(OUT / "forecast_group_characteristics_by_week.csv")
    ranks = records(OUT / "same_payoff_forecast_rank_by_week.csv")
    result = []
    for p in (0, 1):
        for d in (0, 1, 2):
            same = [row for row in ranks if row["p"] == str(p) and row["d"] == str(d)]
            for name in ("both", "only_m2", "only_m1"):
                selected = [row for row in groups if row["p"] == str(p)
                            and row["d"] == str(d) and row["forecast_group"] == name]
                if len(selected) != 423 or len(same) != 423:
                    raise ValueError(f"Weekly support count is not 423 for P{p} D{d} {name}")
                result.append({
                    "p": p, "d": d, "forecast_group": name,
                    "asset_week_forecasts": sum(int(row["n"]) for row in selected),
                    "median_weekly_count": float(np.median([int(row["n"]) for row in selected])),
                    "median_weekly_market_cap_usd": finite_median(selected, "formation_cap_median_usd"),
                    "median_weekly_dollar_volume_usd": finite_median(selected, "formation_dollar_volume_median_usd"),
                    "median_weekly_observed_age_weeks": finite_median(selected, "observed_age_weeks_median"),
                    "median_weekly_m1_payoff_finite_fraction": finite_median(selected, "m1_payoff_finite_fraction"),
                    "common_forecast_spearman_median": finite_median(same, "m2_m1_forecast_spearman"),
                    "m2_same_payoff_rank_ic_median": finite_median(same, "m2_same_payoff_rank_ic"),
                    "m1_same_payoff_rank_ic_median": finite_median(same, "m1_same_payoff_rank_ic"),
                    "interpretation_scope": "descriptive_support_group_not_causal_module_effect",
                })
    path = OUT / "forecast_group_summary.csv"
    with path.open("w", newline="", encoding="utf-8") as handle:
        writer = csv.DictWriter(handle, fieldnames=list(result[0]))
        writer.writeheader()
        writer.writerows(result)
    print(f"E07_GROUP_SUMMARY_OK rows={len(result)}")


if __name__ == "__main__":
    main()
