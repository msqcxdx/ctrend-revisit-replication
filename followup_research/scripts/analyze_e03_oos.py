#!/usr/bin/env python3
"""Paired 52-calendar-week out-of-sample factor opportunity for E03.

This is a deliberately uniform extension of Table 7: LTW, TREND, and the
four-factor opportunity set share the same complete training rows and OOS
weeks. It is not described as an executed borrowing/margin account.
"""

from __future__ import annotations

import csv
from pathlib import Path
import sys

import numpy as np
from scipy.io import loadmat

from paired_stats import annual_sharpe, newey_west
from accepted_run_roots import accepted_roots


ROOT = Path(__file__).resolve().parents[1]
RUNS = tuple(f"P{p}_M1_D{d}" for p in (0, 1) for d in (0, 1, 2))
MODELS = {"BASE": (0, 1), "LTW": (0, 1, 2), "TREND": (0, 1, 3),
          "FULL": (0, 1, 2, 3)}


def read(path: Path) -> list[dict]:
    with path.open(newline="", encoding="utf-8") as fh:
        return list(csv.DictReader(fh))


def write(path: Path, rows: list[dict]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", newline="", encoding="utf-8") as fh:
        writer = csv.DictWriter(fh, fieldnames=list(rows[0]))
        writer.writeheader()
        writer.writerows(rows)


def opportunity_weights(training: np.ndarray, target_vol: float = .1) -> tuple[np.ndarray, str]:
    """Positive-risk-scaled maximum-Sharpe direction for excess-return factors.

    A long-short spread is not a fully invested risky asset. There is no
    economic sum-to-one budget for this factor vector; normalize its risk,
    not the signed sum of its exposures. Dividing first by a negative sum
    would turn the positive expected-return direction into its opposite.
    """
    n, k = training.shape
    if n <= k:
        return np.full(k,np.nan), "n_le_k"
    cov = np.cov(training, rowvar=False)
    cov = np.atleast_2d(cov)
    if np.linalg.matrix_rank(cov) < k or np.linalg.cond(cov) > 1e12:
        return np.full(k,np.nan), "covariance_unidentified"
    mu = training.mean(axis=0)
    direction = np.linalg.solve(cov, mu)
    variance = float(direction@cov@direction)
    if not np.isfinite(variance) or variance <= 0:
        return np.full(k,np.nan), "invalid_portfolio_variance"
    weight = direction * target_vol/np.sqrt(variance)
    assert float(mu@weight) >= -1e-12
    assert np.isclose(float(weight@cov@weight),target_vol**2,rtol=1e-10)
    return weight, "ok"


def tangency(training: np.ndarray, observation: np.ndarray) -> tuple[float, str]:
    weight, reason = opportunity_weights(training)
    return float(observation@weight), reason


def main() -> int:
    out = ROOT / "outputs" / "E03"
    weekly = []
    summary = []
    weight_audit = []
    minimum_rows_summary = []
    for experiment, run in accepted_roots(RUNS).items():
        path = run / "results" / "CTREND" / "CTREND_Base.mat"
        if not path.is_file():
            path = run / "results.staging" / "CTREND" / "CTREND_Base.mat"
        meta = loadmat(path, squeeze_me=True, struct_as_record=False,
                       variable_names=["vDates", "vModelDates"])
        weeks = np.asarray(meta["vDates"], dtype=int).reshape(-1)
        model_dates = np.asarray(meta["vModelDates"], dtype=int).reshape(-1)
        first_model_index = int(np.flatnonzero(weeks == model_dates[0])[0])
        first_oos = first_model_index+52
        rows = read(ROOT / "outputs" / "E01" / experiment
                    / "e01_weekly_factors.csv")
        if weeks.tolist() != [int(float(r["week_key"])) for r in rows]:
            raise ValueError(f"Weekly axes disagree: {experiment}")
        for source in ("external", "own"):
            f = np.array([[float(r[f"{source}_{name}"]) for name in
                           ("cmkt", "csize", "cmom")]
                          + [float(r["ctrend"])] for r in rows])
            oos = {name: np.full(len(f), np.nan) for name in MODELS}
            failures = {name: {} for name in MODELS}
            legacy = {name: np.full(len(f),np.nan) for name in MODELS}
            min26 = {name: np.full(len(f),np.nan) for name in MODELS}
            for t in range(first_oos, len(f)):
                window = f[t-52:t]
                complete = window[np.isfinite(window).all(axis=1)]
                reason_by_model = {}
                for name, columns in MODELS.items():
                    reason = "oos_missing" if not np.isfinite(f[t]).all() else ""
                    if len(complete) <= 4:
                        reason = "insufficient_complete_training"
                    if not reason:
                        w,reason = opportunity_weights(complete[:,columns])
                        oos[name][t] = float(f[t,columns]@w)
                        if reason == "ok":
                            # Audit the discarded normalization, never use it
                            # as the economically preferred opportunity series.
                            legacy[name][t] = oos[name][t]*np.sign(w.sum()) if abs(w.sum())>1e-12 else np.nan
                            if len(complete) >= 26:
                                min26[name][t] = oos[name][t]
                            weight_audit.append({"experiment_id":experiment,"factor_source":source,
                                "model":name,"week_key":int(weeks[t]),
                                "training_start_week":int(weeks[t-52]),
                                "training_last_week":int(weeks[t-1]),
                                "n_training":len(complete),"signed_exposure_sum":float(w.sum()),
                                "gross_factor_exposure":float(np.abs(w).sum()),
                                "old_budget_normalization_reverses_direction":int(w.sum()<0),
                                **{f"exposure_{label}":float(w[list(columns).index(j)]) if j in columns else 0.
                                   for j,label in enumerate(("cmkt","csize","cmom","ctrend"))}})
                    failures[name][reason] = failures[name].get(reason, 0)+1
                    reason_by_model[name] = reason
                weekly.append({"experiment_id": experiment,
                               "factor_source": source, "week_key": int(weeks[t]),
                               "training_calendar_weeks": 52,
                               "training_all_factor_complete": len(complete),
                               **{f"return_{name.lower()}": oos[name][t]
                                  for name in MODELS},
                               **{f"failure_{name.lower()}":reason_by_model[name]
                                  for name in MODELS}})
            pair = np.isfinite(np.column_stack(list(oos.values()))).all(axis=1)
            if pair.sum() < 50:
                raise ValueError(f"Too few paired OOS observations: {experiment} {source}")
            clean = {name: np.where(pair, values, np.nan) for name, values in oos.items()}
            d_trend_ltw = clean["TREND"]-clean["LTW"]
            d_full_ltw = clean["FULL"]-clean["LTW"]
            reg = newey_west(d_trend_ltw, np.zeros((len(f), 0)))
            summary.append({"experiment_id": experiment, "factor_source": source,
                            "first_oos_week": int(weeks[first_oos]),
                            "n_paired_oos": int(pair.sum()),
                            **{f"sharpe_{name.lower()}": annual_sharpe(values)
                               for name, values in clean.items()},
                            "trend_minus_ltw_mean_pct": 100*float(np.nanmean(d_trend_ltw)),
                            "trend_minus_ltw_hac_se_pct": 100*reg["alpha_se_hac"],
                            "trend_minus_ltw_hac_t": reg["alpha_t_hac"],
                            "trend_minus_ltw_ci_low_pct": 100*reg["alpha_ci_low"],
                            "trend_minus_ltw_ci_high_pct": 100*reg["alpha_ci_high"],
                            "full_minus_ltw_mean_pct": 100*float(np.nanmean(d_full_ltw)),
                            "target_in_sample_weekly_vol": 0.1,
                            "risk_target_interpretation": "statistical_scale_10pct_weekly_not_leverage_feasibility",
                            **{f"old_budget_direction_flip_count_{name.lower()}":int(np.count_nonzero(
                                pair & np.isfinite(legacy[name]) & (np.abs(legacy[name]-oos[name])>1e-12)))
                               for name in MODELS},
                            "complete_training_rule": "same four-factor rows in prior 52 calendar positions"})
            common26 = np.isfinite(np.column_stack(list(min26.values()))).all(axis=1)
            minimum_rows_summary.append({"experiment_id":experiment,"factor_source":source,
                "minimum_complete_training_rows":26,"n_paired_oos":int(common26.sum()),
                **{f"sharpe_{name.lower()}":annual_sharpe(np.where(common26,x,np.nan))
                   for name,x in min26.items()},
                "sensitivity_scope":"prespecified_half_window_support_not_performance_selected"})
    write(out / "paired_52week_oos_weekly.csv", weekly)
    write(out / "paired_52week_oos_summary.csv", summary)
    write(out / "paired_52week_oos_weights.csv", weight_audit)
    write(out / "paired_52week_oos_min26_summary.csv", minimum_rows_summary)
    print(f"E03_OOS_OK configurations={len(summary)} weekly_rows={len(weekly)}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
