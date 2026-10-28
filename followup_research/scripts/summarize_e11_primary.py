#!/usr/bin/env python3
"""Apply Holm multiplicity control to the fixed P0, three-D, three-M-path family."""

from __future__ import annotations

import csv
from pathlib import Path

import numpy as np


ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "outputs" / "E11" / "p0_primary_method_family_holm.csv"


def holm(values: np.ndarray) -> np.ndarray:
    order = np.argsort(values)
    adjusted = np.empty(len(values))
    running = 0.0
    for rank, index in enumerate(order):
        running = max(running, min(1.0, (len(values)-rank)*float(values[index])))
        adjusted[index] = running
    return adjusted


def main() -> None:
    source = ROOT / "outputs" / "E04" / "paired_method_differences.csv"
    with source.open(newline="", encoding="utf-8") as handle:
        rows = [row for row in csv.DictReader(handle) if row["P"] == "P0"]
    if len(rows) != 9:
        raise ValueError(f"Expected exactly nine fixed P0 comparisons, got {len(rows)}")
    alpha = holm(np.array([float(row["alpha_difference_hac_p"]) for row in rows]))
    sharpe = holm(np.array([float(row["sharpe_p_centered_block8"]) for row in rows]))
    result = []
    for index, row in enumerate(rows):
        result.append({
            "p": row["P"], "d": row["D"],
            "from_method": row["before"], "to_method": row["after"],
            "paired_weeks": row["n_pair"],
            "alpha_difference_pct_per_week": row["alpha_difference_pct"],
            "alpha_hac_p_unadjusted": row["alpha_difference_hac_p"],
            "alpha_holm_p_within_nine": float(alpha[index]),
            "annual_sharpe_difference": row["sharpe_difference"],
            "sharpe_block8_p_unadjusted": row["sharpe_p_centered_block8"],
            "sharpe_holm_p_within_nine": float(sharpe[index]),
            "family_definition": "P0_fixed_3D_x_3Mpaths_nine_Holm_two_separate_outcome_families",
            "scope": "multiplicity_adjusted_existing_E04_not_independent_design_replications",
        })
    with OUT.open("w", newline="", encoding="utf-8") as handle:
        writer = csv.DictWriter(handle, fieldnames=list(result[0]))
        writer.writeheader()
        writer.writerows(result)
    print(f"E11_HOLM_OK comparisons={len(result)}")


if __name__ == "__main__":
    main()
