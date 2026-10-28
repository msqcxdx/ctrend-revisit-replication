#!/usr/bin/env python3
"""Run E03 factor-opportunity and E04 paired return inference off frozen runs."""

from __future__ import annotations

import csv
from pathlib import Path
import sys

import numpy as np

from paired_stats import (annual_sharpe, block_indices,
                          max_squared_sharpe, newey_west)


ROOT = Path(__file__).resolve().parents[1]
REPO = ROOT.parent
ALL = ROOT / "outputs"


def read_table(path: Path) -> list[dict]:
    with path.open(newline="", encoding="utf-8") as fh:
        return list(csv.DictReader(fh))


def write_table(path: Path, rows: list[dict]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", newline="", encoding="utf-8") as fh:
        writer = csv.DictWriter(fh, fieldnames=list(rows[0]))
        writer.writeheader()
        writer.writerows(rows)


def numeric(rows: list[dict], key: str) -> np.ndarray:
    return np.array([float(r[key]) for r in rows], dtype=float)


def e03() -> None:
    rows_out: list[dict] = []
    models = {"BASE": (0, 1), "LTW": (0, 1, 2),
              "TREND": (0, 1, 3), "FULL": (0, 1, 2, 3)}
    for p in (0, 1):
        for d in (0, 1, 2):
            exp = f"P{p}_M1_D{d}"
            rows = read_table(ALL / "E01" / exp / "e01_weekly_factors.csv")
            for source in ("external", "own"):
                factor = np.column_stack(
                    [numeric(rows, f"{source}_{name}")
                     for name in ("cmkt", "csize", "cmom")]
                    + [numeric(rows, "ctrend")]
                )
                common = np.isfinite(factor).all(axis=1)
                if common.sum() < 100:
                    raise ValueError(f"Low E03 common support: {exp} {source}")
                factor[~common, :] = np.nan
                values = {name: max_squared_sharpe(factor[:, columns])
                          for name, columns in models.items()}
                # Direct non-nested LTW-vs-TREND comparison on the paired
                # factor calendar. No p-value ranking is used.
                rng = np.random.default_rng(20261026+100*p+10*d+
                                            (0 if source == "external" else 1))
                delta_draws = []
                for _ in range(1000):
                    idx = block_indices(len(factor), 8, rng)
                    try:
                        z = factor[idx]
                        delta_draws.append(
                            max_squared_sharpe(z[:, models["TREND"]])
                            -max_squared_sharpe(z[:, models["LTW"]]))
                    except ValueError:
                        continue
                if len(delta_draws) < 950:
                    raise ValueError(f"Insufficient E03 bootstrap: {exp} {source}")
                observed_delta = values["TREND"]-values["LTW"]
                delta_ci = np.quantile(delta_draws, (0.025, 0.975))
                centered = np.asarray(delta_draws)-observed_delta
                delta_p = (1+np.count_nonzero(np.abs(centered) >= abs(observed_delta))) / (1+len(centered))
                for target, conditioning, base_model in (
                    ("CTREND", factor[:, 3], factor[:, (0, 1, 2)]),
                    ("CMOM", factor[:, 2], factor[:, (0, 1, 3)])):
                    reg = newey_west(conditioning, base_model)
                    boot_rng = np.random.default_rng(20261027+100*p+10*d+
                                                     (0 if source == "external" else 1)+
                                                     (0 if target == "CTREND" else 1000))
                    alpha_draws = []
                    for _ in range(1000):
                        idx = block_indices(len(factor), 8, boot_rng)
                        try:
                            alpha_draws.append(
                                newey_west(conditioning[idx], base_model[idx])["alpha"])
                        except ValueError:
                            continue
                    if len(alpha_draws) < 950:
                        raise ValueError(f"E03 alpha bootstrap failure: {exp} {target}")
                    alpha_ci = np.quantile(alpha_draws, (0.025, 0.975))
                    alpha_centered = np.asarray(alpha_draws)-reg["alpha"]
                    alpha_boot_p = (1+np.count_nonzero(
                        np.abs(alpha_centered) >= abs(reg["alpha"]))) / (1+len(alpha_centered))
                    rows_out.append({
                        "experiment_id": exp, "factor_source": source,
                        "n_common": int(common.sum()), "tested_increment": target,
                        "incremental_alpha_pct": 100*reg["alpha"],
                        "alpha_se_hac_pct": 100*reg["alpha_se_hac"],
                        "alpha_t_hac": reg["alpha_t_hac"],
                        "alpha_ci_low_pct": 100*reg["alpha_ci_low"],
                        "alpha_ci_high_pct": 100*reg["alpha_ci_high"],
                        "alpha_ci_low_block8_pct": 100*float(alpha_ci[0]),
                        "alpha_ci_high_block8_pct": 100*float(alpha_ci[1]),
                        "alpha_p_centered_block8": alpha_boot_p,
                        "residual_sd_pct": 100*reg["residual_sd"],
                        "max_s2_base_weekly": values["BASE"],
                        "max_s2_ltw_weekly": values["LTW"],
                        "max_s2_trend_weekly": values["TREND"],
                        "max_s2_full_weekly": values["FULL"],
                        "max_s2_trend_minus_ltw_weekly": values["TREND"]-values["LTW"],
                        "max_s2_trend_minus_ltw_ci_low_block8": float(delta_ci[0]),
                        "max_s2_trend_minus_ltw_ci_high_block8": float(delta_ci[1]),
                        "max_s2_trend_minus_ltw_p_centered_block8": delta_p,
                        "max_s2_full_minus_ltw_weekly": values["FULL"]-values["LTW"],
                        "max_s2_full_minus_trend_weekly": values["FULL"]-values["TREND"],
                    })
                # Exact nested-model identity is a strong implementation check.
                x_ltw = factor[:, (0, 1, 2)]
                x_trend = factor[:, (0, 1, 3)]
                a_trend = newey_west(factor[:, 3], x_ltw)
                a_mom = newey_west(factor[:, 2], x_trend)
                for delta, reg in (
                    (values["FULL"]-values["LTW"], a_trend),
                    (values["FULL"]-values["TREND"], a_mom),
                ):
                    predicted = reg["alpha"]**2 / (reg["residual_sd"]**2)
                    # Sample factor covariance uses N-1 while the OLS
                    # residual standard error uses N-K; adjust exactly.
                    predicted *= (common.sum()-1)/(common.sum()-4)
                    if not np.isclose(delta, predicted, atol=1e-11, rtol=1e-10):
                        raise ValueError(f"Nested Sharpe identity failed: {exp}")
    write_table(ALL / "E03" / "dual_increment_and_four_models.csv", rows_out)
    print(f"E03_FACTOR_MODELS_OK rows={len(rows_out)}")


def e04() -> None:
    weekly = read_table(REPO / "results" / "comparisons" / "source_tables"
                        / "common_week" / "eighteen_experiment_weekly_returns.csv")
    week_key = [int(r["year_week"]) for r in weekly]
    rows_out: list[dict] = []
    for p in (0, 1):
        for d in (0, 1, 2):
            factor_rows = read_table(ALL / "E01" / f"P{p}_M1_D{d}"
                                     / "e01_weekly_factors.csv")
            if [int(float(r["week_key"])) for r in factor_rows] != week_key:
                raise ValueError("E04 factor and outcome calendar mismatch")
            factors = np.column_stack(
                [numeric(factor_rows, f"external_{name}")
                 for name in ("cmkt", "csize", "cmom")]
            )
            for m_before, m_after in ((0, 2), (2, 1), (0, 1)):
                before = numeric(weekly, f"P{p}_M{m_before}_D{d}")
                after = numeric(weekly, f"P{p}_M{m_after}_D{d}")
                pair = np.isfinite(before) & np.isfinite(after) & np.isfinite(factors).all(axis=1)
                if pair.sum() < 100:
                    raise ValueError("Too few paired weeks")
                a = before.copy()
                b = after.copy()
                a[~pair] = np.nan
                b[~pair] = np.nan
                d_y = b-a
                reg = newey_west(d_y, factors)
                # Draw the original full-calendar triplet together, preserving
                # within-block missingness and contemporaneous factor alignment.
                rng = np.random.default_rng(20261026+100*p+10*d+3*m_before+m_after)
                sharpe_draws = []
                alpha_draws = []
                for _ in range(1000):
                    idx = block_indices(len(a), 8, rng)
                    if np.isfinite(a[idx]).sum() < 80:
                        continue
                    sharpe_draws.append(annual_sharpe(b[idx])-annual_sharpe(a[idx]))
                    try:
                        alpha_draws.append(newey_west(d_y[idx], factors[idx])["alpha"])
                    except ValueError:
                        continue
                if len(sharpe_draws) < 950 or len(alpha_draws) < 950:
                    raise ValueError("Too few valid E04 bootstrap draws")
                sharpe_diff = annual_sharpe(b)-annual_sharpe(a)
                sharpe_ci = np.quantile(sharpe_draws, (0.025, 0.975))
                centered = np.asarray(sharpe_draws)-sharpe_diff
                sharpe_p = (1+np.count_nonzero(abs(centered) >= abs(sharpe_diff))) / (1+len(centered))
                alpha_ci = np.quantile(alpha_draws, (0.025, 0.975))
                mean_pct = 100*float(np.nanmean(d_y))
                rows_out.append({
                    "P": f"P{p}", "D": f"D{d}",
                    "before": f"M{m_before}", "after": f"M{m_after}",
                    "n_pair": int(pair.sum()),
                    "mean_before_pct": 100*float(np.nanmean(a)),
                    "mean_after_pct": 100*float(np.nanmean(b)),
                    "mean_difference_pct": mean_pct,
                    "sharpe_before": annual_sharpe(a),
                    "sharpe_after": annual_sharpe(b),
                    "sharpe_difference": sharpe_diff,
                    "sharpe_ci_low_block8": float(sharpe_ci[0]),
                    "sharpe_ci_high_block8": float(sharpe_ci[1]),
                    "sharpe_p_centered_block8": sharpe_p,
                    "alpha_difference_pct": 100*reg["alpha"],
                    "alpha_difference_hac_se_pct": 100*reg["alpha_se_hac"],
                    "alpha_difference_hac_p": reg["alpha_p_hac"],
                    "alpha_difference_ci_low_hac_pct": 100*reg["alpha_ci_low"],
                    "alpha_difference_ci_high_hac_pct": 100*reg["alpha_ci_high"],
                    "alpha_difference_ci_low_block8_pct": 100*float(alpha_ci[0]),
                    "alpha_difference_ci_high_block8_pct": 100*float(alpha_ci[1]),
                    "before_p05_pct": 100*float(np.nanquantile(a, 0.05)),
                    "after_p05_pct": 100*float(np.nanquantile(b, 0.05)),
                    "before_subminus100_count": int(np.count_nonzero(a < -1)),
                    "after_subminus100_count": int(np.count_nonzero(b < -1)),
                    "block_weeks": 8, "bootstrap_valid": len(sharpe_draws),
                })
    write_table(ALL / "E04" / "paired_method_differences.csv", rows_out)
    print(f"E04_PAIRED_OK comparisons={len(rows_out)}")


def main() -> int:
    e03()
    e04()
    return 0


if __name__ == "__main__":
    sys.exit(main())
