#!/usr/bin/env python3
# CTREND_REVISIT_FILE_PURPOSE: Derive corrected M1 Table 7 direction from frozen accepted factors without rerunning b09.
"""Independent, parent-hash-bound Table 7 correction on the original OOS windows."""

from __future__ import annotations

import csv
import hashlib
import json
from pathlib import Path
import sys

import numpy as np
from scipy.io import loadmat


REPO = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(REPO / "followup_research/scripts"))
from accepted_run_roots import accepted_roots  # noqa: E402


NULLS = ((3,), (0, 3), (0, 1, 3), (0, 1, 2))
NAMES = ("CMKT", "CSMB", "CMOM", "CTREND")
RUNS = tuple(f"P{p}_M1_D{d}" for p in (0, 1) for d in (0, 1, 2))


def digest(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as stream:
        for part in iter(lambda: stream.read(1024 * 1024), b""):
            h.update(part)
    return h.hexdigest()


def regression(y: np.ndarray, x: np.ndarray) -> tuple[float, float, int]:
    """Reproduce the saved Table 7 generalized-alpha/HAC convention."""
    good = np.isfinite(y) & np.isfinite(x)
    design = np.column_stack((np.ones(int(good.sum())), x[good]))
    beta = np.linalg.lstsq(design, y[good], rcond=None)[0]
    residual = y[good]-design@beta
    bread = np.linalg.inv(design.T@design)
    scores = np.zeros((len(y), 2))
    scores[good] = design*residual[:, None]
    meat = scores.T@scores
    lags = int(np.floor(4*(good.sum()/100)**(2/9)+.5))
    for lag in range(1, lags+1):
        cross = scores[lag:].T@scores[:-lag]
        meat += (1-lag/(lags+1))*(cross+cross.T)
    cov = bread@meat@bread
    return float(beta[0]*100), float(beta[0]/np.sqrt(cov[0, 0])), int(good.sum())


def write_csv(path: Path, rows: list[dict]) -> None:
    with path.open("w", newline="", encoding="utf-8") as stream:
        writer = csv.DictWriter(stream, fieldnames=list(rows[0]))
        writer.writeheader()
        writer.writerows(rows)


def main() -> None:
    output = REPO / "analysis/isolated_corrections/table7_direction"
    output.mkdir(parents=True, exist_ok=True)
    rows: list[dict] = []
    parents: list[dict] = []
    for experiment, run in accepted_roots(RUNS).items():
        result = run / "results"
        if not result.is_dir():
            result = run / "results.staging"
        diagnostic_path = result / "Table7_FrontierExpansionDiagnostics.mat"
        factor_path = (REPO / "followup_research/outputs/E01" / experiment /
                       "e01_weekly_factors.csv")
        diag = loadmat(diagnostic_path, squeeze_me=True,
                       struct_as_record=False)["rTable7Diagnostics"]
        with factor_path.open(newline="", encoding="utf-8") as stream:
            factors_csv = list(csv.DictReader(stream))
        weeks = np.array([int(float(row["week_key"])) for row in factors_csv])
        if not np.array_equal(weeks, np.asarray(diag.vDates).reshape(-1)):
            raise ValueError(f"Table 7 calendar mismatch: {experiment}")
        factors = np.array([[float(row[f"external_{name}"]) for name in
                             ("cmkt", "csize", "cmom")]+[float(row["ctrend"])]
                            for row in factors_csv])
        first_oos = int(diag.iIdxFirstOut)-1
        for null_index, null in enumerate(NULLS):
            for alt in range(4):
                if alt in null:
                    continue
                columns = (*null, alt)
                legacy = np.full((len(weeks), 2), np.nan)
                corrected = legacy.copy()
                flips = [0, 0]
                for t in range(first_oos, len(weeks)):
                    train = factors[t-52:t, columns]
                    train = train[np.isfinite(train).all(axis=1)]
                    if not np.isfinite(factors[t, columns]).all():
                        continue
                    for system, k in enumerate((len(null), len(columns))):
                        x = train[:, :k]
                        if len(x) <= k:
                            continue
                        cov = np.atleast_2d(np.cov(x, rowvar=False))
                        if (np.linalg.matrix_rank(cov) < k or
                                np.linalg.cond(cov, 1) > 1e12):
                            continue
                        mean = x.mean(axis=0)
                        direction = np.linalg.solve(cov, mean)
                        variance = float(direction@cov@direction)
                        if not np.isfinite(variance) or variance <= 0:
                            continue
                        budget = direction.sum()
                        if abs(budget) <= np.spacing(max(1, np.linalg.norm(direction))):
                            raise ValueError("Legacy zero-budget case needs separate support audit")
                        old_weight = direction/budget
                        old_weight *= .1/np.sqrt(old_weight@cov@old_weight)
                        new_weight = .1*direction/np.sqrt(variance)
                        observation = factors[t, columns[:k]]
                        legacy[t, system] = observation@old_weight
                        corrected[t, system] = observation@new_weight
                        flips[system] += int(budget < 0)
                stored = diag.cSpanningDiagnostics[alt, null_index]
                expected = np.column_stack((stored.vTangPortY,
                                            stored.vTangPortXY))
                error = float(np.nanmax(np.abs(legacy-expected)))
                if not np.allclose(legacy, expected, rtol=1e-7,
                                   atol=1e-9, equal_nan=True):
                    raise ValueError(f"Legacy Table 7 reconstruction failed: {experiment} {null} {alt}")
                old_alpha, old_t, old_n = regression(legacy[:, 1], legacy[:, 0])
                new_alpha, new_t, new_n = regression(corrected[:, 1], corrected[:, 0])
                if (abs(old_alpha-100*diag.mGenAlphas[alt, null_index]) > 1e-6 or
                        abs(old_t-diag.mGenAlphasT[alt, null_index]) > 1e-5 or
                        old_n != new_n):
                    raise ValueError(f"Published Table 7 cell mismatch: {experiment} {null} {alt}")
                rows.append(dict(experiment_id=experiment,
                                 null_factor_set="+".join(NAMES[i] for i in null),
                                 added_factor=NAMES[alt], common_oos_weeks=new_n,
                                 legacy_alpha_pct=old_alpha, legacy_hac_t=old_t,
                                 corrected_alpha_pct=new_alpha, corrected_hac_t=new_t,
                                 null_direction_flips=flips[0],
                                 combined_direction_flips=flips[1],
                                 max_legacy_reconstruction_error=error))
        parents.append(dict(experiment_id=experiment,
                            run_complete_sha256=digest(run / "RUN_COMPLETE"),
                            table7_diagnostics_sha256=digest(diagnostic_path),
                            weekly_factors_sha256=digest(factor_path)))
    if len(rows) != 42 or len(parents) != 6:
        raise ValueError("Incomplete six-experiment Table 7 derivation")
    table = output / "table7_direction_corrected_42_cells.csv"
    write_csv(table, rows)
    receipt = dict(scope="six_M1_Table7_only_no_b09_reestimation",
                   formula="direction=Sigma^-1*mean; weight=0.1*direction/sqrt(direction'*Sigma*direction)",
                   script_sha256=digest(Path(__file__)),
                   output_sha256=digest(table), parents=parents)
    (output / "RECEIPT.json").write_text(json.dumps(receipt, indent=2)+"\n",
                                          encoding="utf-8")
    print(f"TABLE7_DIRECTION_CORRECTION_OK cells={len(rows)} parents={len(parents)} "
          f"changed_cells={sum(row['null_direction_flips']+row['combined_direction_flips']>0 for row in rows)}")


if __name__ == "__main__":
    main()
