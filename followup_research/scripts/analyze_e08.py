#!/usr/bin/env python3
"""Summarize symmetric tails and concentration in the E08 contribution ledger."""

from __future__ import annotations

import csv
import gzip
import heapq
from pathlib import Path
import sys

import numpy as np


ROOT = Path(__file__).resolve().parents[1]
REPO = ROOT.parent
OUT = ROOT / "outputs" / "E08"


def write(path: Path, rows: list[dict]) -> None:
    with path.open("w", newline="", encoding="utf-8") as fh:
        writer = csv.DictWriter(fh, fieldnames=list(rows[0]))
        writer.writeheader()
        writer.writerows(rows)


def main() -> int:
    with (REPO / "config" / "event_asset_registry_v20260811.csv").open(newline="") as fh:
        event_ids = {int(r["asset_id"]): r for r in csv.DictReader(fh)}
    top_positive = []
    top_negative = []
    counted = 0
    with gzip.open(OUT / "asset_week_direct_contributions.csv.gz", "rt",
                   newline="", encoding="utf-8") as fh:
        for row in csv.DictReader(fh):
            value = float(row["signed_direct_hl_contribution"])
            if not np.isfinite(value):
                continue
            counted += 1
            if len(top_positive) < 100:
                heapq.heappush(top_positive, (value, counted, row))
            elif value > top_positive[0][0]:
                heapq.heapreplace(top_positive, (value, counted, row))
            if len(top_negative) < 100:
                heapq.heappush(top_negative, (-value, counted, row))
            elif -value > top_negative[0][0]:
                heapq.heapreplace(top_negative, (-value, counted, row))
    tail = []
    for direction, heap, reverse in (("positive", top_positive, True),
                                     ("negative", top_negative, False)):
        ordered = sorted((item[2] for item in heap),
                         key=lambda row: float(row["signed_direct_hl_contribution"]),
                         reverse=reverse)
        for rank, row in enumerate(ordered, 1):
            event = event_ids.get(int(row["cmcid"]))
            tail.append({"tail": direction, "rank": rank, **row,
                         "in_frozen_D2_event_registry": int(bool(event and event["in_D2"] == "1")),
                         "registry_event_ids": event["event_ids"] if event else "",
                         "registry_reason": event["reason"] if event else ""})
    write(OUT / "top_100_positive_and_negative_asset_week_contributions.csv", tail)
    with (OUT / "weekly_concentration_and_reconciliation.csv").open(newline="") as fh:
        rows = list(csv.DictReader(fh))
    summary = []
    for experiment in sorted({row["experiment_id"] for row in rows}):
        selected = [row for row in rows if row["experiment_id"] == experiment
                    and np.isfinite(float(row["saved_hl"]))]
        returns = np.array([float(row["saved_hl"]) for row in selected])
        short_max = np.array([float(row["max_short_weight"]) for row in selected])
        short_top3 = np.array([float(row["top3_short_weight"]) for row in selected])
        residuals = np.array([float(row["accounting_residual"]) for row in selected])
        summary.append({
            "experiment_id": experiment, "n_finite_weeks": len(returns),
            "mean_return_pct": 100*float(returns.mean()),
            "p01_return_pct": 100*float(np.quantile(returns, 0.01)),
            "p05_return_pct": 100*float(np.quantile(returns, 0.05)),
            "p95_return_pct": 100*float(np.quantile(returns, 0.95)),
            "p99_return_pct": 100*float(np.quantile(returns, 0.99)),
            "weeks_hl_below_minus_100pct": int(np.count_nonzero(returns < -1)),
            "weeks_short_max_weight_over_10pct": int(np.count_nonzero(short_max > 0.1)),
            "weeks_short_max_weight_over_25pct": int(np.count_nonzero(short_max > 0.25)),
            "median_top3_short_weight": float(np.median(short_top3)),
            "weeks_with_intraweek_exit": sum(int(row["has_same_leg_exit_event"]) for row in selected),
            "weeks_with_nonzero_reinvestment_residual": int(np.count_nonzero(
                np.isfinite(residuals) & (np.abs(residuals) > 1e-9))),
        })
    write(OUT / "tail_and_concentration_summary.csv", summary)
    print(f"E08_TAIL_OK asset_rows_evaluated={counted} experiments={len(summary)}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
