#!/usr/bin/env python3
"""Attribute M2-to-M1 opening-weight changes by *observed* forecast coverage.

The same saved M1 asset payoff is used on both sides.  These are accounting
groups, not causal effects of any individual source-code correction.  A week
with an unavailable payoff for any selected asset fails closed.
"""

from __future__ import annotations

import csv
from pathlib import Path

import numpy as np

from analyze_e07 import load, support
from extract_e08_asset_contributions import coin_names


ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "outputs" / "E07"
KEY_WEEKS = {201628, 201750, 202013, 202016, 202103}
GROUPS = ("both_forecast", "only_m2_forecast", "only_m1_forecast", "neither_forecast")


def write(path: Path, rows: list[dict]) -> None:
    with path.open("w", newline="", encoding="utf-8") as handle:
        writer = csv.DictWriter(handle, fieldnames=list(rows[0]))
        writer.writeheader()
        writer.writerows(rows)


def main() -> None:
    existing = {(int(row["p"]), int(row["d"]), int(row["year_week"])): row
                for row in csv.DictReader((OUT / "paired_m2_m1_forecast_weights_payoff.csv").open(
                    newline="", encoding="utf-8"))}
    names = coin_names()
    weekly = []
    key_assets = []
    valid_weeks = 0
    for p in (0, 1):
        for d in (0, 1, 2):
            m2 = load(f"P{p}_M2_D{d}")
            m1 = load(f"P{p}_M1_D{d}")
            if not np.array_equal(m2["ids"], m1["ids"]) or not np.array_equal(m2["weeks"], m1["weeks"]):
                raise RuntimeError(f"M2/M1 saved axes differ P{p}D{d}")
            for t, week in enumerate(m2["weeks"]):
                f2 = np.isfinite(m2["forecast"][:, t])
                f1 = np.isfinite(m1["forecast"][:, t])
                groups = (f2 & f1, f2 & ~f1, ~f2 & f1, ~f2 & ~f1)
                low2, high2 = m2["weights"][:, t, 0], m2["weights"][:, t, 4]
                low1, high1 = m1["weights"][:, t, 0], m1["weights"][:, t, 4]
                held2 = support(low2) | support(high2)
                held1 = support(low1) | support(high1)
                union = held2 | held1
                payoff = m1["pnl"][:, t]
                common_valid = bool(union.any() and np.isfinite(payoff[union]).all() and
                                    held1.any() and held2.any())
                delta = (np.nan_to_num(high1, nan=0.0) - np.nan_to_num(low1, nan=0.0) -
                         np.nan_to_num(high2, nan=0.0) + np.nan_to_num(low2, nan=0.0))
                total = float(np.dot(delta[union], payoff[union])) if common_valid else np.nan
                prior = float(existing[(p, d, int(week))]["m1_payoff_fixed_weight_switch"])
                if not np.allclose(total, prior, atol=1e-10, rtol=0, equal_nan=True):
                    raise RuntimeError(f"Existing E07 fixed-payoff switch disagrees P{p}D{d} {week}")
                valid_weeks += int(common_valid)
                parts = []
                for label, mask in zip(GROUPS, groups):
                    active = union & mask
                    contribution = float(np.dot(delta[active], payoff[active])) if common_valid else np.nan
                    parts.append(contribution)
                    weekly.append(dict(
                        p=p, d=d, year_week=int(week), forecast_group=label,
                        assets=int(mask.sum()), selected_union_assets=int(active.sum()),
                        selected_by_m2=int((held2 & mask).sum()),
                        selected_by_m1=int((held1 & mask).sum()),
                        common_payoff_valid=int(common_valid),
                        m1_minus_m2_signed_weight_sum=float(delta[mask].sum()),
                        fixed_m1_payoff_contribution_to_weight_switch=contribution,
                        total_fixed_m1_payoff_weight_switch=total,
                        interpretation="observed_forecast_group_not_causal_module_effect"))
                if common_valid and abs(sum(parts) - total) > 1e-10:
                    raise RuntimeError(f"Group contributions fail to sum P{p}D{d} {week}")
                if int(week) in KEY_WEEKS:
                    for i in np.flatnonzero(union | (f2 ^ f1)):
                        symbol, name = names.get(int(m2["ids"][i]), ("", ""))
                        group = next(label for label, mask in zip(GROUPS, groups) if mask[i])
                        key_assets.append(dict(
                            p=p, d=d, year_week=int(week), cmcid=int(m2["ids"][i]),
                            symbol=symbol, name=name, forecast_group=group,
                            m2_forecast=float(m2["forecast"][i, t]),
                            m1_forecast=float(m1["forecast"][i, t]),
                            m2_low_weight=float(np.nan_to_num(low2[i])),
                            m2_high_weight=float(np.nan_to_num(high2[i])),
                            m1_low_weight=float(np.nan_to_num(low1[i])),
                            m1_high_weight=float(np.nan_to_num(high1[i])),
                            m1_saved_asset_payoff=float(payoff[i]),
                            common_payoff_valid=int(common_valid),
                            fixed_payoff_weight_switch_contribution=(
                                float(delta[i] * payoff[i]) if common_valid else np.nan)))
            print(f"E07_TRANSITION_PROGRESS P{p}D{d} weeks={len(m2['weeks'])}", flush=True)
    if len(weekly) != 6 * 423 * len(GROUPS):
        raise RuntimeError("Unexpected forecast-group/week coverage")
    write(OUT / "forecast_coverage_weight_switch_by_week.csv", weekly)
    write(OUT / "key_week_asset_forecast_weight_transitions.csv", key_assets)
    print(f"E07_FORECAST_WEIGHT_TRANSITIONS_OK weekly_groups={len(weekly)} "
          f"key_asset_rows={len(key_assets)} common_payoff_weeks={valid_weeks}")


if __name__ == "__main__":
    main()
