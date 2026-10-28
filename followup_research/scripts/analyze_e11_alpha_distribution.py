#!/usr/bin/env python3
"""Compare LTW-controlled alpha across all matched accepted design cells.

Alpha is descriptive here: thousands of highly correlated designs do not
become independent experiments.  Every pair is re-estimated on its own same-
week support with the *external* LTW controls fixed within each P,D cell.
"""

from __future__ import annotations

from concurrent.futures import ProcessPoolExecutor
import csv
from pathlib import Path

import numpy as np
from scipy.io import loadmat


ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "outputs" / "E11"
PAIRS = ((0, 2), (2, 1), (0, 1))
METHODS = ("FM", "CFM", "C_ENET_SCS", "C_ENET_SCS_T", "POLS", "CPOLS",
           "C_ENET", "C_ENET_SCS_VAL", "C_ENET_SCS_VAL_T")
FIELDS = ("p", "d", "b09_combo_id", "method", "from_method", "to_method",
          "paired_weeks", "alpha_from_pct_per_week", "alpha_to_pct_per_week",
          "paired_alpha_difference_pct_per_week", "status")


def one_cell(p: int, d: int, roots: dict[str, str]) -> tuple[str, int]:
    factors_file = ROOT / "outputs" / "E01" / f"P{p}_M1_D{d}" / "e01_weekly_factors.csv"
    with factors_file.open(newline="", encoding="utf-8") as handle:
        factors_rows = list(csv.DictReader(handle))
    weeks = np.array([int(float(row["week_key"])) for row in factors_rows], dtype=int)
    controls = np.array([[float(row[f"external_{name}"])
                          for name in ("cmkt", "csize", "cmom")]
                         for row in factors_rows])
    file = OUT / f"paired_design_ltw_alpha_P{p}_D{d}.csv"
    count = 0
    with file.open("w", newline="", encoding="utf-8") as handle:
        writer = csv.DictWriter(handle, fieldnames=FIELDS)
        writer.writeheader()
        for combo in range(1, 3073):
            values = {}
            for m in (0, 2, 1):
                eid = f"P{p}_M{m}_D{d}"
                path = Path(roots[eid]) / "CTREND" / f"CTREND_Combo{combo}.mat"
                data = loadmat(path, simplify_cells=True,
                               variable_names=["mTrend_5", "vDates", "cTrendNames"])
                if not np.array_equal(np.asarray(data["vDates"], dtype=int).ravel(), weeks):
                    raise ValueError(f"Date mismatch for {eid} combo={combo}")
                if tuple(str(x) for x in np.atleast_1d(data["cTrendNames"])) != METHODS:
                    raise ValueError(f"Method order mismatch for {eid} combo={combo}")
                values[m] = np.asarray(data["mTrend_5"], dtype=float)
            for index, method in enumerate(METHODS):
                for m0, m1 in PAIRS:
                    a, b = values[m0][:, index], values[m1][:, index]
                    support = np.isfinite(a) & np.isfinite(b) & np.isfinite(controls).all(axis=1)
                    n = int(support.sum())
                    record = {"p": p, "d": d, "b09_combo_id": combo,
                              "method": method, "from_method": f"M{m0}",
                              "to_method": f"M{m1}", "paired_weeks": n}
                    if n < 20:
                        record.update(alpha_from_pct_per_week=np.nan,
                                      alpha_to_pct_per_week=np.nan,
                                      paired_alpha_difference_pct_per_week=np.nan,
                                      status="insufficient_pair_weeks")
                    else:
                        x = np.column_stack((np.ones(n), controls[support]))
                        if np.linalg.matrix_rank(x) < x.shape[1]:
                            record.update(alpha_from_pct_per_week=np.nan,
                                          alpha_to_pct_per_week=np.nan,
                                          paired_alpha_difference_pct_per_week=np.nan,
                                          status="rank_deficient")
                        else:
                            beta = np.linalg.lstsq(x,
                                np.column_stack((a[support], b[support])), rcond=None)[0]
                            record.update(alpha_from_pct_per_week=100*float(beta[0, 0]),
                                          alpha_to_pct_per_week=100*float(beta[0, 1]),
                                          paired_alpha_difference_pct_per_week=100*float(beta[0, 1]-beta[0, 0]),
                                          status="descriptive_matched_design")
                    writer.writerow(record)
                    count += 1
            if combo % 256 == 0:
                print(f"E11_ALPHA_PROGRESS P{p}_D{d} combo={combo}/3072 rows={count}", flush=True)
    return file.name, count


def main() -> None:
    with (OUT / "accepted_run_paths.csv").open(newline="", encoding="utf-8") as handle:
        rows = list(csv.DictReader(handle))
    roots = {row["experiment_id"]: row["result_root"] for row in rows}
    if len(roots) != 18:
        raise ValueError("All 18 accepted roots are required")
    if any(not (Path(row["accepted_run_root"]) / "RUN_COMPLETE").is_file()
           for row in rows):
        raise ValueError("One or more accepted source runs are incomplete")
    with ProcessPoolExecutor(max_workers=6) as pool:
        done = list(pool.map(lambda_pair, [(p, d, roots) for p in (0, 1) for d in (0, 1, 2)]))
    if sum(count for _, count in done) != 497664:
        raise ValueError(f"Unexpected paired alpha row count: {done}")
    summary = []
    for path, count in done:
        print(f"E11_ALPHA_FILE_OK {path} rows={count}", flush=True)
    for p in (0, 1):
        for d in (0, 1, 2):
            path = OUT / f"paired_design_ltw_alpha_P{p}_D{d}.csv"
            grouped: dict[tuple[str, str, str], list[float]] = {}
            with path.open(newline="", encoding="utf-8") as handle:
                for row in csv.DictReader(handle):
                    key = row["method"], row["from_method"], row["to_method"]
                    grouped.setdefault(key, []).append(float(row["paired_alpha_difference_pct_per_week"]))
            for key in sorted(grouped):
                x = np.asarray(grouped[key]); finite = x[np.isfinite(x)]
                summary.append({
                    "p": p, "d": d, "method": key[0],
                    "from_method": key[1], "to_method": key[2],
                    "design_count": len(x), "identified_count": len(finite),
                    "median_paired_delta_alpha_pct_per_week": float(np.median(finite)) if len(finite) else np.nan,
                    "p10_delta_alpha_pct": float(np.quantile(finite, .1)) if len(finite) else np.nan,
                    "p90_delta_alpha_pct": float(np.quantile(finite, .9)) if len(finite) else np.nan,
                    "fraction_delta_alpha_positive": float(np.mean(finite > 0)) if len(finite) else np.nan,
                    "interpretation": "correlated_design_distribution_not_independent_trials",
                })
    path = OUT / "paired_design_ltw_alpha_summary.csv"
    with path.open("w", newline="", encoding="utf-8") as handle:
        writer = csv.DictWriter(handle, fieldnames=list(summary[0]))
        writer.writeheader()
        writer.writerows(summary)
    print(f"E11_ALPHA_COMPLETE paired_rows=497664 groups={len(summary)}")


def lambda_pair(item: tuple[int, int, dict[str, str]]) -> tuple[str, int]:
    return one_cell(*item)


if __name__ == "__main__":
    main()
