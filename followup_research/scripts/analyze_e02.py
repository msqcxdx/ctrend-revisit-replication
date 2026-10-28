#!/usr/bin/env python3
"""Isolate the original GRS argument error on all six frozen M0 experiments.

This reuses accepted CTREND and anomaly-hedge outputs; it does not rerun or
alter any model. The first two columns deliberately reproduce the invalid
legacy pairwise-regression system. The third re-estimates one valid system.
"""

from __future__ import annotations

import csv
import hashlib
from pathlib import Path
import re
import sys

import numpy as np
from scipy.io import loadmat
from scipy.stats import f as f_distribution
from accepted_run_roots import accepted_roots

ROOT = Path(__file__).resolve().parents[1]
REPO = ROOT.parent
RUNS = tuple(f"P{p}_M0_D{d}" for p in (0, 1) for d in (0, 1, 2))
LTW_ASSETS = ("mcap", "prc", "maxdprc", "ret_1_0", "ret_2_0",
              "ret_3_0", "ret_4_0", "ret_4_1", "prcvol", "volscaled",
              "stdprcvol")
TI_ASSETS = ("rsi", "stochRSI", "stochK", "stochD", "cci") + tuple(
    f"sma_{n}d" for n in (3, 5, 10, 20, 50, 100, 200)) + (
    "macd", "macd_diff_signal") + tuple(
    f"volsma_{n}d" for n in (3, 5, 10, 20, 50, 100, 200)) + (
    "volmacd", "volmacd_diff_signal", "chaikin", "boll_low", "boll_mid",
    "boll_high", "boll_width")


def sha(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as fh:
        for part in iter(lambda: fh.read(1024*1024), b""):
            h.update(part)
    return h.hexdigest()


def write(path: Path, rows: list[dict]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", newline="", encoding="utf-8") as fh:
        fields = list(dict.fromkeys(key for row in rows for key in row))
        writer = csv.DictWriter(fh, fieldnames=fields)
        writer.writeheader()
        writer.writerows(rows)


def original_formula(alpha: np.ndarray, residual: np.ndarray,
                     third: np.ndarray, *, exact_grs: bool = False) -> dict:
    """Preserve legacy diagnostics; use divisor T only for exact-system GRS.

    The unbiased residual covariance (T-K-1) needs the finite-sample multiplier
    below AND a factor central second moment divided by T, not T-1.  The
    legacy columns intentionally retain the original code's T-1 denominator.
    """
    support = np.isfinite(residual).all(axis=1) & np.isfinite(third).all(axis=1)
    e = residual[support]
    mu = third[support]
    t, n = e.shape
    l = mu.shape[1]
    out = {"n_weeks": t, "n_assets": n, "third_arg_columns": l,
           "residual_rank": int(np.linalg.matrix_rank(e)) if t else 0,
           "third_arg_rank": int(np.linalg.matrix_rank(mu)) if t else 0,
           "grs_f": np.nan, "grs_p": np.nan, "status": "unidentified",
           "factor_covariance_divisor": "T" if exact_grs else "T-1",
           "inference_assumptions": "iid Gaussian residuals; nominal F reference, not HAC"}
    if t <= n+l or t <= l+1 or out["residual_rank"] < n or out["third_arg_rank"] < l:
        out["status"] = "insufficient_sample_or_rank"
        return out
    cov_e = e.T @ e/(t-l-1)
    mu_mean = mu.mean(axis=0)
    mu_demean = mu-mu_mean
    cov_f = mu_demean.T @ mu_demean/(t if exact_grs else t-1)
    if np.linalg.cond(cov_e) > 1e12 or np.linalg.cond(cov_f) > 1e12:
        out["status"] = "ill_conditioned"
        return out
    numerator = float(alpha @ np.linalg.solve(cov_e, alpha))
    denominator = 1+float(mu_mean @ np.linalg.solve(cov_f, mu_mean))
    statistic = t/n*((t-n-l)/(t-l-1))*numerator/denominator
    out.update(grs_f=statistic, grs_p=float(f_distribution.sf(statistic, n, t-n-l)),
               status="computed")
    return out


def pairwise_regress(y: np.ndarray, factor: np.ndarray) -> tuple[float, float, np.ndarray]:
    support = np.isfinite(y) & np.isfinite(factor).all(axis=1)
    x = np.column_stack((np.ones(int(support.sum())), factor[support]))
    yy = y[support]
    n, k = x.shape
    if n <= k or np.linalg.matrix_rank(x) < k:
        return np.nan, np.nan, np.full(len(y), np.nan)
    b = np.linalg.lstsq(x, yy, rcond=None)[0]
    u = yy-x @ b
    cov = (float(u@u)/(n-k))*np.linalg.inv(x.T@x)
    residual = np.full(len(y), np.nan)
    residual[support] = u
    return float(b[0]), float(b[0]/np.sqrt(cov[0, 0])), residual


def valid_system(y: np.ndarray, factor: np.ndarray) -> dict:
    support = np.isfinite(y).all(axis=1) & np.isfinite(factor).all(axis=1)
    yy = y[support]
    ff = factor[support]
    if not len(yy):
        return {"status": "no_common_weeks", "n_weeks": 0,
                "n_assets": y.shape[1], "third_arg_columns": factor.shape[1]}
    # Exact aliases are the only assets removed; proportional or correlated
    # assets are retained. Record this mapping in the output.
    unique = []
    for col in range(yy.shape[1]):
        if not any(np.array_equal(yy[:, col], yy[:, prior]) for prior in unique):
            unique.append(col)
    yy = yy[:, unique]
    t, n = yy.shape
    k = ff.shape[1]
    if t <= n+k or t <= k+1:
        return {"status": "insufficient_sample", "n_weeks": t,
                "n_assets": n, "third_arg_columns": k,
                "n_exact_aliases_removed": y.shape[1]-n}
    x = np.column_stack((np.ones(t), ff))
    if np.linalg.matrix_rank(x) < k+1:
        return {"status": "factor_design_rank_deficient", "n_weeks": t,
                "n_assets": n, "third_arg_columns": k,
                "n_exact_aliases_removed": y.shape[1]-n}
    beta = np.linalg.lstsq(x, yy, rcond=None)[0]
    resid = yy-x@beta
    result = original_formula(beta[0], resid, ff, exact_grs=True)
    result["n_exact_aliases_removed"] = y.shape[1]-n
    result["retained_input_column_indices"] = "|".join(map(str, unique))
    result["exact_alias_to_retained_input_column"] = "|".join(
        f"{col}:{next(prior for prior in unique if np.array_equal(y[support,col], y[support,prior]))}"
        for col in range(y.shape[1]) if col not in unique)
    result["avg_abs_alpha_pct"] = 100*float(np.mean(np.abs(beta[0])))
    result["median_abs_alpha_pct"] = 100*float(np.median(np.abs(beta[0])))
    return result


def analyze_one(experiment: str, run: Path) -> tuple[list[dict], list[Path]]:
    if not (run / "RUN_COMPLETE").is_file():
        raise ValueError("Frozen M0 run lacks RUN_COMPLETE")
    result = run / "results.staging"
    if not result.is_dir():
        result = run / "results"
    hedge_path = result / "HedgePorts.mat"
    trend_path = result / "CTREND" / "CTREND_Base.mat"
    h = loadmat(hedge_path, squeeze_me=True, struct_as_record=False)
    c = loadmat(trend_path, squeeze_me=True, struct_as_record=False)
    names = [str(n) for n in h["cCharNames"]]
    expected_names = LTW_ASSETS+TI_ASSETS
    indices = [names.index(name) for name in expected_names]
    y = np.asarray(h["mHedgePort"][:, indices], dtype=float)
    trend = np.asarray(c["cResults"].VW.mPortRet[-1], dtype=float)
    dates = np.asarray(c["vDates"], dtype=int).reshape(-1)
    p, _, d = experiment.split("_")
    ltw = ROOT / "outputs" / "E01" / f"{p}_M1_{d}" / "e01_weekly_factors.csv"
    with ltw.open(newline="", encoding="utf-8") as fh:
        rows = list(csv.DictReader(fh))
    if [int(float(r["week_key"])) for r in rows] != list(dates):
        raise ValueError("M0 and external-LTW week axes differ")
    external = np.array([[float(r[f"external_{factor}"])
                          for factor in ("cmkt", "csize", "cmom")]
                         for r in rows])
    full = np.column_stack((external, trend))
    # Original b11 invalidates every factor whenever any of the four is NaN.
    full[~np.isfinite(full).all(axis=1)] = np.nan
    y_original = y.copy()
    y_original[~np.isfinite(full).all(axis=1)] = np.nan
    models = {"CCAPM": (0,), "LTW": (0, 1, 2), "TREND": (0, 1, 3)}
    capm_t = np.array([pairwise_regress(y_original[:, j], full[:, (0,)])[1]
                       for j in range(y.shape[1])])
    selected_original = np.round(np.abs(capm_t), 2) > 1.96
    first = dates <= 201852
    last = dates >= 201901
    capm_t_early = np.array([
        pairwise_regress(np.where(first, y[:, j], np.nan),
                         np.where(first[:, None], full[:, (0,)], np.nan))[1]
        for j in range(y.shape[1])])
    selected_early = np.round(np.abs(capm_t_early), 2) > 1.96
    groups = {"LTW": np.arange(len(LTW_ASSETS)),
              "TI": np.arange(len(LTW_ASSETS), len(expected_names)),
              "All": np.arange(len(expected_names))}
    output = []
    for group, group_index in groups.items():
        for model_name, columns in models.items():
            fx = full[:, columns]
            sel = group_index[selected_original[group_index]]
            if len(sel):
                regressions = [pairwise_regress(y_original[:, j], fx) for j in sel]
                alphas = np.array([r[0] for r in regressions])
                residuals = np.column_stack([r[2] for r in regressions])
                for variant, third in (("legacy_wrong_argument", y_original[:, sel]),
                                       ("argument_only_replaced", fx)):
                    result_diag = original_formula(alphas, residuals, third)
                    output.append({"experiment_id": experiment, "asset_set": group,
                                   "model": model_name, "selection": "full_sample_capm_t_gt_1_96",
                                   "variant": variant, "input_assets": len(sel),
                                   **result_diag})
            for selection, members, sample in (
                ("prespecified_all", group_index, np.ones(len(dates), dtype=bool)),
                ("early_selected_later_test", group_index[selected_early[group_index]], last),
                ("legacy_selected_valid_system", sel, np.ones(len(dates), dtype=bool))):
                if not len(members):
                    continue
                yy = y[:, members].copy()
                xx = full[:, columns].copy()
                yy[~sample] = np.nan
                xx[~sample] = np.nan
                result_diag = valid_system(yy, xx)
                output.append({"experiment_id": experiment, "asset_set": group,
                               "model": model_name, "selection": selection,
                               "variant": "valid_common_system", "input_assets": len(members),
                               **result_diag})
    inputs = [run / "RUN_COMPLETE", hedge_path, trend_path, ltw]
    return output, inputs


def main() -> int:
    out = ROOT / "outputs" / "E02"
    output = []
    inputs = []
    for experiment, run in accepted_roots(RUNS).items():
        rows, source_paths = analyze_one(experiment, run)
        frozen_table = REPO / "results" / "experiments" / experiment / "Tables" / "anomaly_alphas.tex"
        grs_line = next(line for line in frozen_table.read_text(encoding="utf-8").splitlines()
                        if line.startswith("GRS ($p$)"))
        published = [float(x) for x in re.findall(r"(?<![A-Za-z])\d+\.\d+", grs_line)]
        reproduced = [round(100*float(row["grs_p"])+1e-10, 2)
                      for model in ("CCAPM", "LTW", "TREND")
                      for group in ("LTW", "TI", "All")
                      for row in rows if row["model"] == model
                      and row["asset_set"] == group
                      and row["variant"] == "legacy_wrong_argument"]
        if len(published) != 9 or len(reproduced) != 9 or published != reproduced:
            raise ValueError(f"Frozen Table/Figure 3 GRS mismatch: {experiment}: {published} != {reproduced}")
        output.extend(rows)
        inputs.extend(source_paths+[frozen_table])
    write(out / "grs_argument_and_system_audit.csv", output)
    inputs += [
              REPO / "engines" / "M0" / "base" / "b11Figure3_AnomalyAlphas.m",
              REPO / "engines" / "M0" / "base" / "Utils" / "fGRS.m"]
    (out / "INPUTS_SHA256.txt").write_text(
        "".join(f"{sha(path)}  {path}\n" for path in inputs), encoding="utf-8")
    print(f"E02_GRS_AUDIT_OK rows={len(output)} experiments={len(RUNS)}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
