#!/usr/bin/env python3
"""Trace saved forecasts to opening holdings and direct weekly payoff.

This is a read-only post-run diagnostic.  A missing forecast is not assigned
an invented unique reason code.  Cross-method payoff swaps are evaluated only
when every selected weight has a finite payoff in both saved payoff matrices.
"""

from __future__ import annotations

import csv
from pathlib import Path

import numpy as np
from scipy.io import loadmat


ROOT = Path(__file__).resolve().parents[1]
REPO = ROOT.parent
OUT = ROOT / "outputs" / "E07"


def write_csv(path: Path, rows: list[dict]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", encoding="utf-8", newline="") as f:
        writer = csv.DictWriter(f, fieldnames=list(rows[0]))
        writer.writeheader()
        writer.writerows(rows)


def load(eid: str) -> dict:
    file = REPO / "results" / "experiments" / eid / "CTREND" / "CTREND_Base.mat"
    r = loadmat(file, squeeze_me=True, struct_as_record=False,
                variable_names=["vAssetID", "vDates", "mYhat", "mRetPnlOOS", "cResults"])
    result = r["cResults"].VW
    ids = np.asarray(r["vAssetID"], dtype=int).reshape(-1)
    weeks = np.asarray(r["vDates"], dtype=int).reshape(-1)
    forecast = np.asarray(r["mYhat"], dtype=float)
    weights = np.asarray(result.mWts, dtype=float)
    returns = np.asarray(result.mPortRet, dtype=float)
    pnl = np.asarray(r["mRetPnlOOS"], dtype=float) if "mRetPnlOOS" in r else None
    assert len(ids) == len(set(ids)) and len(weeks) == len(set(weeks))
    assert forecast.shape == (len(ids), len(weeks))
    assert weights.shape == (len(ids), len(weeks), 5)
    assert returns.shape == (6, len(weeks))
    if pnl is not None:
        assert pnl.shape == forecast.shape
    return dict(ids=ids, weeks=weeks, forecast=forecast, weights=weights,
                returns=returns, pnl=pnl)


def support(w: np.ndarray) -> np.ndarray:
    return np.isfinite(w) & (w > 0)


def weight_stats(w: np.ndarray) -> tuple[int, float, float, float]:
    x = w[support(w)]
    if not len(x):
        return 0, np.nan, np.nan, np.nan
    return len(x), float(x.sum()), float(np.max(x)), float(np.sum((x/x.sum())**2))


def signed_fixed_payoff(low: np.ndarray, high: np.ndarray,
                        payoff: np.ndarray) -> float:
    selected = support(low) | support(high)
    if not selected.any() or not np.isfinite(payoff[selected]).all():
        return np.nan
    # Never multiply zero by an unrelated missing payoff: 0 * NaN is NaN.
    return float(np.dot(np.nan_to_num(high[selected]), payoff[selected]) -
                 np.dot(np.nan_to_num(low[selected]), payoff[selected]))


def main() -> None:
    weekly = []
    paired = []
    for p in (0, 1):
        for d in (0, 1, 2):
            series = {m: load(f"P{p}_M{m}_D{d}") for m in (0, 2, 1)}
            a, b = series[2], series[1]
            assert np.array_equal(a["weeks"], b["weeks"])
            assert np.array_equal(a["ids"], b["ids"])
            for m, s in series.items():
                eid = f"P{p}_M{m}_D{d}"
                for t, week in enumerate(s["weeks"]):
                    wl = s["weights"][:, t, 0]
                    wh = s["weights"][:, t, 4]
                    ln, lsum, lmax, lhhi = weight_stats(wl)
                    hn, hsum, hmax, hhhi = weight_stats(wh)
                    yhat = s["forecast"][:, t]
                    weekly.append(dict(experiment_id=eid, year_week=int(week),
                                       asset_universe=len(s["ids"]),
                                       forecast_count=int(np.isfinite(yhat).sum()),
                                       no_forecast_count=int((~np.isfinite(yhat)).sum()),
                                       low_holding_count=ln, high_holding_count=hn,
                                       low_weight_sum=lsum, high_weight_sum=hsum,
                                       low_max_weight=lmax, high_max_weight=hmax,
                                       low_hhi=lhhi, high_hhi=hhhi,
                                       saved_hl_return=float(s["returns"][-1, t])))
            for t, week in enumerate(a["weeks"]):
                ids = a["ids"]
                y2 = np.isfinite(a["forecast"][:, t])
                y1 = np.isfinite(b["forecast"][:, t])
                low2, high2 = a["weights"][:, t, 0], a["weights"][:, t, 4]
                low1, high1 = b["weights"][:, t, 0], b["weights"][:, t, 4]
                h2, h1 = support(high2), support(high1)
                l2, l1 = support(low2), support(low1)
                pay2, pay1 = a["pnl"][:, t], b["pnl"][:, t]
                r22 = signed_fixed_payoff(low2, high2, pay2)
                r21 = signed_fixed_payoff(low2, high2, pay1)
                r11 = signed_fixed_payoff(low1, high1, pay1)
                r12 = signed_fixed_payoff(low1, high1, pay2)
                paired.append(dict(
                    p=p, d=d, year_week=int(week),
                    m2_forecast_count=int(y2.sum()),
                    m1_forecast_count=int(y1.sum()),
                    both_forecast_count=int((y2 & y1).sum()),
                    only_m2_forecast_count=int((y2 & ~y1).sum()),
                    only_m1_forecast_count=int((y1 & ~y2).sum()),
                    m2_low_count=int(l2.sum()), m1_low_count=int(l1.sum()),
                    low_holding_intersection=int((l2 & l1).sum()),
                    low_holding_union=int((l2 | l1).sum()),
                    m2_high_count=int(h2.sum()), m1_high_count=int(h1.sum()),
                    high_holding_intersection=int((h2 & h1).sum()),
                    high_holding_union=int((h2 | h1).sum()),
                    saved_m2_hl=float(a["returns"][-1, t]),
                    saved_m1_hl=float(b["returns"][-1, t]),
                    m2_weights_m2_payoff_direct=r22,
                    m2_weights_m1_payoff_direct=r21,
                    m1_weights_m1_payoff_direct=r11,
                    m1_weights_m2_payoff_direct=r12,
                    m2_fixed_weights_payoff_switch=r21-r22,
                    m1_payoff_fixed_weight_switch=r11-r21,
                    direct_m2_to_m1_total=r11-r22,
                    m2_direct_vs_saved_residual=r22-a["returns"][-1, t],
                    m1_direct_vs_saved_residual=r11-b["returns"][-1, t],
                ))
    write_csv(OUT / "weekly_forecast_to_holdings.csv", weekly)
    write_csv(OUT / "paired_m2_m1_forecast_weights_payoff.csv", paired)
    # Reconciliation is diagnostic, not an unconditional equality: same-leg
    # intraweek re-investment can add a separately saved ledger contribution.
    residual = [r for r in paired if np.isfinite(r["m1_direct_vs_saved_residual"])
                and abs(r["m1_direct_vs_saved_residual"]) > 1e-10]
    print(f"E07_TRANSMISSION_OK weekly={len(weekly)} paired={len(paired)} "
          f"m1_nonzero_direct_reconciliation_residuals={len(residual)}")


if __name__ == "__main__":
    main()
