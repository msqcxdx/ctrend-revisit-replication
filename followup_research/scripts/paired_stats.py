#!/usr/bin/env python3
"""Small, auditable time-series estimators for follow-up analyses.

The bootstrap resamples contiguous blocks of the full 423-position calendar,
including all missing values. It never compresses observed weeks together
before resampling. This matters for the CTREND internal formation gaps.
"""

from __future__ import annotations

import math
import numpy as np
from scipy.stats import norm


def newey_west(y: np.ndarray, factors: np.ndarray, lag: int = 4) -> dict:
    keep = np.isfinite(y) & np.isfinite(factors).all(axis=1)
    x = np.column_stack((np.ones(int(keep.sum())), factors[keep]))
    yy = y[keep]
    n, k = x.shape
    if n <= k+lag or np.linalg.matrix_rank(x) < k:
        raise ValueError(f"Rank or sample failure: N={n}, K={k}")
    beta = np.linalg.lstsq(x, yy, rcond=None)[0]
    u = yy-x @ beta
    xu = x*u[:, None]
    # Embed scores back on the uncompressed original calendar. A missing
    # research week must not make the surrounding valid weeks adjacent.
    xu_calendar = np.zeros((len(y), k))
    xu_calendar[keep] = xu
    meat = xu_calendar.T @ xu_calendar
    for h in range(1, min(lag, len(y)-1)+1):
        cross = xu_calendar[h:].T @ xu_calendar[:-h]
        meat += (1-h/(lag+1))*(cross+cross.T)
    bread = np.linalg.inv(x.T @ x)
    covariance = bread @ meat @ bread
    se = np.sqrt(np.maximum(np.diag(covariance), 0))
    residual_sd = math.sqrt(float(u @ u)/(n-k))
    return {"n": n, "alpha": float(beta[0]),
            "alpha_se_hac": float(se[0]),
            "alpha_t_hac": float(beta[0]/se[0]),
            "alpha_p_hac": float(2*norm.sf(abs(beta[0]/se[0]))),
            "alpha_ci_low": float(beta[0]-1.96*se[0]),
            "alpha_ci_high": float(beta[0]+1.96*se[0]),
            "beta": beta, "residual_sd": residual_sd,
            "r2": 1-float(u@u)/float(((yy-yy.mean())**2).sum()),
            "support": keep}


def annual_sharpe(y: np.ndarray) -> float:
    valid = y[np.isfinite(y)]
    return float(math.sqrt(52)*valid.mean()/valid.std(ddof=1))


def block_indices(n: int, block: int, rng: np.random.Generator) -> np.ndarray:
    starts = rng.integers(0, n, size=math.ceil(n/block))
    return np.concatenate([(start+np.arange(block)) % n
                           for start in starts])[:n]


def bootstrap_paired(y: np.ndarray, x: np.ndarray, statistic,
                     reps: int = 1000, block: int = 8,
                     seed: int = 20261026) -> dict:
    """Percentile CI and centered bootstrap p for a paired difference."""
    if len(y) != len(x):
        raise ValueError("Paired calendar lengths disagree")
    rng = np.random.default_rng(seed)
    estimate = statistic(y, x)
    draws = []
    for _ in range(reps):
        idx = block_indices(len(y), block, rng)
        try:
            value = statistic(y[idx], x[idx])
            if math.isfinite(value):
                draws.append(value)
        except (ValueError, ZeroDivisionError, np.linalg.LinAlgError):
            continue
    if len(draws) < 0.95*reps:
        raise ValueError(f"Too many invalid bootstrap replicates: {len(draws)}/{reps}")
    draws = np.asarray(draws)
    centered = draws-estimate
    p = (1+int(np.count_nonzero(np.abs(centered) >= abs(estimate))))/(len(draws)+1)
    low, high = np.quantile(draws, [0.025, 0.975])
    return {"estimate": estimate, "ci_low": float(low),
            "ci_high": float(high), "centered_p": float(p),
            "reps_valid": len(draws), "block_weeks": block,
            "seed": seed}


def max_squared_sharpe(f: np.ndarray) -> float:
    valid = f[np.isfinite(f).all(axis=1)]
    if len(valid) <= f.shape[1] or np.linalg.matrix_rank(np.cov(valid, rowvar=False)) < f.shape[1]:
        raise ValueError("Unidentified factor covariance")
    mu = valid.mean(axis=0)
    cov = np.atleast_2d(np.cov(valid, rowvar=False))
    if np.linalg.cond(cov) > 1e12:
        raise ValueError("Ill-conditioned factor covariance")
    return float(mu @ np.linalg.solve(cov, mu))
