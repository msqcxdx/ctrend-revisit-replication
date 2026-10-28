#!/usr/bin/env python3
# CTREND_REVISIT_FILE_PURPOSE: Compare original and corrected delay-hedge rows and appendix placement across all accepted methods.
"""Read-only summary of 18 parent-bound delay corrections."""

import csv
from hashlib import sha256
import json
from pathlib import Path
import sys

import numpy as np
from scipy.io import loadmat


ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "followup_research/scripts"))
from accepted_run_roots import accepted_roots  # noqa: E402


RUNS = tuple(f"P{p}_M{m}_D{d}" for p in (0, 1)
             for m in (0, 1, 2) for d in (0, 1, 2))
OUT = ROOT / "analysis/isolated_corrections/delay"


def digest(path: Path) -> str:
    value = sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            value.update(chunk)
    return value.hexdigest()


def describe(values: np.ndarray) -> tuple[int, float, float, str]:
    finite = values[np.isfinite(values)]
    n = len(finite)
    if n < 3 or finite.std(ddof=1) == 0:
        return n, np.nan, np.nan, "undefined"
    mean_pct = float(finite.mean()*100)
    tstat = float(finite.mean()/(finite.std(ddof=1)/np.sqrt(n)))
    return n, mean_pct, tstat, "B8_anomaly" if abs(tstat) >= 1.96 else "B5_insignificant"


def main() -> None:
    parents = accepted_roots(RUNS)
    rows = []
    source_hashes = {}
    for experiment, run in parents.items():
        path = OUT / experiment / "delay_hedge_weekly.csv"
        source_hashes[experiment] = digest(path)
        with path.open(newline="", encoding="utf-8") as stream:
            weekly = list(csv.DictReader(stream))
        dates = [int(row["year_week"]) for row in weekly]
        result_root = run / "results"
        if not result_root.is_dir():
            result_root = run / "results.staging"
        accepted_dates = np.asarray(loadmat(result_root / "HedgePorts.mat",
                                           variable_names=["vDates"])["vDates"]).reshape(-1)
        if dates != [int(date) for date in accepted_dates] or dates != sorted(set(dates)):
            raise ValueError(f"Delay calendar incomplete: {experiment}")
        old = np.array([float(row["legacy_delay_hedge"]) for row in weekly])
        fixed = np.array([float(row["corrected_delay_hedge"]) for row in weekly])
        old_n, old_mean, old_t, old_table = describe(old)
        new_n, new_mean, new_t, new_table = describe(fixed)
        table_root = result_root / "Tables"
        old_b5 = (table_root / "insignificant_anomaly_strategy_returns.tex").read_text()
        old_b8 = (table_root / "anomaly_strategy_returns.tex").read_text()
        actual = ("B5_insignificant" if any(line.startswith("delay &")
                  for line in old_b5.splitlines()) else
                  "B8_anomaly" if any(line.startswith("delay &")
                  for line in old_b8.splitlines()) else "absent")
        if actual != old_table:
            raise ValueError(f"Saved Table B.5/B.8 delay placement does not match old hedge: {experiment}")
        both = np.isfinite(old) & np.isfinite(fixed)
        rows.append(dict(experiment_id=experiment, legacy_finite_weeks=old_n,
                         corrected_finite_weeks=new_n,
                         shared_finite_weeks=int(both.sum()),
                         changed_shared_weeks=int(np.count_nonzero(
                             both & (np.abs(old-fixed) > 1e-10))),
                         legacy_hl_mean_pct=old_mean, corrected_hl_mean_pct=new_mean,
                         legacy_hl_t=old_t, corrected_hl_t=new_t,
                         legacy_appendix=old_table, corrected_appendix=new_table))
    summary = OUT / "delay_appendix_summary.csv"
    with summary.open("w", newline="", encoding="utf-8") as stream:
        writer = csv.DictWriter(stream, fieldnames=list(rows[0]))
        writer.writeheader()
        writer.writerows(rows)
    receipt = dict(scope="eighteen_delay_HL_B5_B8_placement_no_b09_reestimation",
                   script_sha256=digest(Path(__file__)),
                   source_weekly_sha256=source_hashes,
                   summary_sha256=digest(summary))
    (OUT / "SUMMARY_RECEIPT.json").write_text(json.dumps(receipt, indent=2)+"\n",
                                              encoding="utf-8")
    print(f"DELAY_APPENDIX_COMPARISON_OK experiments={len(rows)}")


if __name__ == "__main__":
    main()
