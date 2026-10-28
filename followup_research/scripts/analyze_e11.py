#!/usr/bin/env python3
"""Pair all 3,072 accepted b09 designs by complete frozen design key.

The eighteen accepted run trees are read only.  The three exported MATLAB
DesignChoices tables must be byte-identical before combo numbers are used as
keys.  The thousands of correlated design cells are descriptive sensitivity
analyses, never treated as independent statistical replications.
"""

from __future__ import annotations

import argparse
from concurrent.futures import ProcessPoolExecutor
import csv
from hashlib import sha256
from pathlib import Path

import numpy as np
from scipy.io import loadmat


ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "outputs" / "E11"
METHODS = ("FM", "CFM", "C_ENET_SCS", "C_ENET_SCS_T", "POLS", "CPOLS",
           "C_ENET", "C_ENET_SCS_VAL", "C_ENET_SCS_VAL_T")
PAIRS = ((0, 2), (2, 1), (0, 1))
FIELDS = ["p", "d", "design_key_sha256", "b09_combo_id", "method",
          "from_method", "to_method", "scheduled_weeks",
          "training_calendar_weeks", "scheduled_oos_weeks", "pair_oos_n",
          "from_own_n",
          "to_own_n", "pair_n", "from_own_sharpe", "to_own_sharpe",
          "from_pair_sharpe", "to_pair_sharpe", "delta_sharpe_paired",
          "from_pair_mean_week_pct", "to_pair_mean_week_pct",
          "delta_mean_week_pct", "pair_common_coverage",
          "pair_full_calendar_coverage", "pair_scheduled_oos_coverage"]


def digest(path: Path) -> str:
    h = sha256()
    with path.open("rb") as f:
        for x in iter(lambda: f.read(1024 * 1024), b""):
            h.update(x)
    return h.hexdigest()


def sharpe(a: np.ndarray) -> float:
    a = a[np.isfinite(a)]
    if len(a) < 3:
        return np.nan
    sd = a.std(ddof=1)
    return float(np.sqrt(52)*a.mean()/sd) if sd > 0 else np.nan


def coverage(pair_mask: np.ndarray, training_weeks: int) -> dict[str, float | int]:
    """Report both calendar coverage and design-specific post-training coverage."""
    n_calendar = len(pair_mask)
    if not 0 <= training_weeks < n_calendar:
        raise ValueError("Invalid design-specific training-calendar length")
    n_oos = n_calendar-training_weeks
    n_pair_oos = int(pair_mask[training_weeks:].sum())
    return dict(training_calendar_weeks=training_weeks,
                scheduled_oos_weeks=n_oos, pair_oos_n=n_pair_oos,
                pair_full_calendar_coverage=float(pair_mask.mean()),
                pair_scheduled_oos_coverage=n_pair_oos/n_oos)


def worker(p: int, d: int, limit: int, paths: dict, design_sha: str,
           training_weeks: list[int]) -> tuple[str, int]:
    out = OUT / f"paired_design_cells_P{p}_D{d}.csv"
    out.parent.mkdir(parents=True, exist_ok=True)
    count = 0
    dates0 = None
    with out.open("w", newline="", encoding="utf-8") as f:
        writer = csv.DictWriter(f, fieldnames=FIELDS)
        writer.writeheader()
        for combo in range(1, limit+1):
            data = {}
            for m in (0, 2, 1):
                eid = f"P{p}_M{m}_D{d}"
                path = Path(paths[eid]) / "CTREND" / f"CTREND_Combo{combo}.mat"
                if not path.is_file():
                    raise RuntimeError(f"Missing accepted design result: {path}")
                r = loadmat(path, simplify_cells=True,
                            variable_names=["mTrend_5", "vDates", "cTrendNames"])
                dates = np.asarray(r["vDates"], dtype=int).reshape(-1)
                if dates0 is None:
                    dates0 = dates
                if not np.array_equal(dates, dates0):
                    raise RuntimeError(f"Different calendar for {eid} combo={combo}")
                names = tuple(str(x) for x in np.atleast_1d(r["cTrendNames"]))
                if names != METHODS:
                    raise RuntimeError(f"Method ordering differs: {eid} combo={combo}")
                x = np.asarray(r["mTrend_5"], dtype=float)
                if x.shape != (len(dates), len(METHODS)):
                    raise RuntimeError(f"Unexpected factor array: {eid} combo={combo}")
                data[m] = x
            for j, method in enumerate(METHODS):
                for m0, m1 in PAIRS:
                    a, b = data[m0][:, j], data[m1][:, j]
                    mask = np.isfinite(a) & np.isfinite(b)
                    if mask[:training_weeks[combo-1]].any():
                        raise RuntimeError("Paired factor became finite inside its training schedule")
                    aa, bb = a[mask], b[mask]
                    writer.writerow(dict(
                        p=p, d=d, design_key_sha256=design_sha,
                        b09_combo_id=combo, method=method,
                        from_method=f"M{m0}", to_method=f"M{m1}",
                        scheduled_weeks=len(dates),
                        from_own_n=int(np.isfinite(a).sum()),
                        to_own_n=int(np.isfinite(b).sum()),
                        pair_n=int(mask.sum()),
                        from_own_sharpe=sharpe(a), to_own_sharpe=sharpe(b),
                        from_pair_sharpe=sharpe(aa), to_pair_sharpe=sharpe(bb),
                        delta_sharpe_paired=sharpe(bb)-sharpe(aa),
                        from_pair_mean_week_pct=100*aa.mean() if len(aa) else np.nan,
                        to_pair_mean_week_pct=100*bb.mean() if len(bb) else np.nan,
                        delta_mean_week_pct=100*(bb-aa).mean() if len(aa) else np.nan,
                        **coverage(mask, training_weeks[combo-1]),
                        # Retained for historical CSV readers: this is a
                        # full-calendar fraction, NOT scheduled-OOS coverage.
                        pair_common_coverage=float(mask.mean()),
                    ))
                    count += 1
            if combo % 256 == 0 or combo == limit:
                print(f"E11_PROGRESS P{p}_D{d} combos={combo}/{limit} rows={count}",
                      flush=True)
    return str(out), count


def summarize(paths: list[Path], limit: int) -> None:
    groups: dict[tuple, list[dict]] = {}
    for path in paths:
        for row in csv.DictReader(path.open(newline="", encoding="utf-8")):
            key = (row["p"], row["d"], row["method"],
                   row["from_method"], row["to_method"])
            groups.setdefault(key, []).append(row)
    summaries = []
    for key, rows in sorted(groups.items()):
        n = np.array([int(r["pair_n"]) for r in rows])
        delta = np.array([float(r["delta_sharpe_paired"]) for r in rows])
        valid = np.isfinite(delta) & (n >= 20)
        x = delta[valid]
        summaries.append(dict(
            p=key[0], d=key[1], method=key[2],
            from_method=key[3], to_method=key[4],
            design_count=len(rows), valid_paired_design_count=int(valid.sum()),
            valid_design_fraction=float(valid.mean()),
            median_pair_weeks=float(np.median(n)),
            median_delta_sharpe=float(np.median(x)) if len(x) else np.nan,
            p10_delta_sharpe=float(np.percentile(x,10)) if len(x) else np.nan,
            p90_delta_sharpe=float(np.percentile(x,90)) if len(x) else np.nan,
            fraction_to_sharpe_higher=float(np.mean(x > 0)) if len(x) else np.nan,
            interpretation="correlated_design_distribution_not_independent_trials",
        ))
    out = OUT / "paired_design_summary.csv"
    with out.open("w", newline="", encoding="utf-8") as f:
        writer = csv.DictWriter(f, fieldnames=list(summaries[0]))
        writer.writeheader()
        writer.writerows(summaries)
    print(f"E11_SUMMARY_OK groups={len(summaries)} designs_per_group={limit}",
          flush=True)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--limit", type=int, default=3072)
    parser.add_argument("--workers", type=int, default=6)
    args = parser.parse_args()
    if not 1 <= args.limit <= 3072:
        raise ValueError("limit must be in 1..3072")
    hashes = {digest(OUT / f"design_choices_M{m}.csv") for m in (0,2,1)}
    if len(hashes) != 1:
        raise RuntimeError("DesignChoices differ: combo IDs are not pairing keys")
    with (OUT / "design_choices_M1.csv").open(newline="", encoding="utf-8") as f:
        designs = list(csv.DictReader(f))
    if len(designs) != 3072 or any(int(row["b09_combo_id"]) != i
                                   for i, row in enumerate(designs, start=1)):
        raise RuntimeError("Design-choice rows are not the canonical combo order")
    training_weeks = [int(row["vNumIn"]) for row in designs]
    with (OUT / "accepted_run_paths.csv").open(newline="", encoding="utf-8") as f:
        paths = {r["experiment_id"]: r["result_root"] for r in csv.DictReader(f)}
    if len(paths) != 18:
        raise RuntimeError("Need exactly eighteen accepted runs")
    with ProcessPoolExecutor(max_workers=min(args.workers,6)) as pool:
        jobs = [pool.submit(worker,p,d,args.limit,paths,next(iter(hashes)),training_weeks)
                for p in (0,1) for d in (0,1,2)]
        completed = [j.result() for j in jobs]
    if any(n != args.limit*len(METHODS)*len(PAIRS) for _,n in completed):
        raise RuntimeError("Pairwise grid row count mismatch")
    summarize([Path(p) for p,_ in completed], args.limit)
    print(f"E11_COMPLETE combos_per_outer_cell={args.limit} "
          f"paired_rows={sum(n for _,n in completed)}", flush=True)


if __name__ == "__main__":
    main()
