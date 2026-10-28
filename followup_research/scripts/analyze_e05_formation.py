#!/usr/bin/env python3
"""Rebuild accepted and future-blind formation weights from frozen M1 forecasts.

This isolates the portfolio-eligibility channel.  It does *not* rerun b01--b05
after future-price perturbation, and therefore does not certify the entire
forecasting pipeline as causally invariant.  Missing-payoff zero marks are a
transparent statistical sensitivity, not observed executable prices.
"""

from __future__ import annotations

import csv
from pathlib import Path

import h5py
import numpy as np
from scipy.io import loadmat


ROOT = Path(__file__).resolve().parents[1]
REPO = ROOT.parent
OUT = ROOT / "outputs" / "E05"


def write(path: Path, rows: list[dict]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", newline="", encoding="utf-8") as f:
        writer = csv.DictWriter(f, fieldnames=list(rows[0]))
        writer.writeheader()
        writer.writerows(rows)


def weights(forecast: np.ndarray, cap: np.ndarray, eligible: np.ndarray) -> tuple[np.ndarray, np.ndarray]:
    out = np.zeros((len(forecast), 5))
    if eligible.sum() < 25:
        return out, np.zeros(5,dtype=int)
    breaks = np.quantile(forecast[eligible], np.arange(6)/5,
                         method="hazen")  # MATLAB quantile(...,'Method','exact')
    counts = np.zeros(5,dtype=int)
    for i in range(5):
        l = eligible & (forecast >= breaks[i] if i == 0 else forecast > breaks[i])
        l &= forecast <= breaks[i+1]
        counts[i] = l.sum()
        if counts[i]:
            out[l,i] = cap[l]/cap[l].sum()
    # Accepted b05 sets lHedgeOnly=true: H-L requires its TWO extreme
    # groups, not five valid groups. Changing eligibility must not quietly
    # add a stricter intermediate-group gate to the counterfactual.
    if counts[0] < 5 or counts[-1] < 5:
        return np.zeros_like(out), counts
    return out, counts


def formation_only_weights(forecast, cap, entry_price, stable):
    """Formation API deliberately accepts no future payoff/availability array."""
    eligible = (np.isfinite(forecast) & np.isfinite(cap) & (cap >= 1e6)
                & (cap > 0) & np.isfinite(entry_price) & (entry_price > 0) & ~stable)
    return weights(forecast, cap, eligible)


def main() -> None:
    accepted = list(csv.DictReader((ROOT / "outputs" / "E11" /
                                    "accepted_run_paths.csv").open()))
    roots = {r["experiment_id"]: Path(r["accepted_run_root"])
             for r in accepted if "_M1_" in r["experiment_id"]}
    if len(roots) != 6:
        raise RuntimeError("Need six accepted M1 roots")
    rows = []
    errors = []
    for eid, root in sorted(roots.items()):
        data = root / "data" / "bCharacteristicsOLHC_Combo1.mat"
        if not data.is_file():
            data = root / "data.staging" / "bCharacteristicsOLHC_Combo1.mat"
        with h5py.File(data) as f:
            rd = f["rData"]
            weeks_all = np.asarray(rd["yrmoda"][:], dtype=int).ravel()
            me = np.asarray(rd["mME"][:], dtype=float)
            close = np.asarray(rd["mClose"][:], dtype=float)
            stable = np.asarray(f["rMetaData"]["lIsStable"][:],
                                dtype=bool).ravel()
            ids_data = np.asarray(f["rMetaData"]["vID"][:],
                                  dtype=int).ravel()
        sample = (weeks_all >= 201416) & (weeks_all <= 202222)
        cap = np.concatenate([np.full((len(me),1),np.nan),me[:,:-1]],axis=1)[:,sample]
        price = np.concatenate([np.full((len(me),1),np.nan),close[:,:-1]],axis=1)[:,sample]
        base = loadmat(REPO / "results" / "experiments" / eid / "CTREND" /
                       "CTREND_Base.mat", squeeze_me=True, struct_as_record=False,
                       variable_names=["mYhat","mRetPnlOOS","vDates","vAssetID","cResults"])
        weeks = np.asarray(base["vDates"],dtype=int).ravel()
        ids = np.asarray(base["vAssetID"],dtype=int).ravel()
        if not np.array_equal(ids,ids_data) or not np.array_equal(weeks,weeks_all[sample]):
            raise RuntimeError(f"E05 accepted DATA axes disagree: {eid}")
        yhat = np.asarray(base["mYhat"],dtype=float)
        pnl = np.asarray(base["mRetPnlOOS"],dtype=float)
        saved = np.asarray(base["cResults"].VW.mWts,dtype=float)
        for t,week in enumerate(weeks):
            formation = (np.isfinite(yhat[:,t]) & np.isfinite(cap[:,t]) &
                         (cap[:,t] >= 1e6) & (cap[:,t]>0) &
                         np.isfinite(price[:,t]) & (price[:,t]>=0) & ~stable)
            target = formation & np.isfinite(pnl[:,t])
            replay,n_replay = weights(yhat[:,t],cap[:,t],target)
            strict,n_strict = formation_only_weights(yhat[:,t],cap[:,t],price[:,t],stable)
            actual = np.nan_to_num(saved[:,t,:],nan=0)
            # CTREND_Base is a hedge-only sort: the three middle portfolios
            # are intentionally not saved. Reconcile the two priced legs.
            replay_legs = replay[:,[0,4]]
            actual_legs = actual[:,[0,4]]
            if np.max(np.abs(replay_legs-actual_legs)) > 1e-10:
                errors.append((eid,int(week),float(np.max(np.abs(replay_legs-actual_legs)))))
            # A post-formation change in target availability can change the
            # retrospective baseline weight vector, but cannot enter the
            # strict formation-only calculation.
            perturbed = np.isfinite(pnl[:,t]).copy()
            if formation.any():
                index = np.flatnonzero(formation)[0]
                perturbed[index] = ~perturbed[index]
            changed,_ = weights(yhat[:,t],cap[:,t],formation & perturbed)
            # Independent call after the target availability perturbation;
            # this is an API-level eligibility test, not a model refit test.
            strict_after,_ = formation_only_weights(yhat[:,t].copy(),cap[:,t].copy(),
                                                    price[:,t].copy(),stable.copy())
            strict_l1 = float(np.abs(strict_after-strict).sum())
            if strict_l1 != 0:
                raise RuntimeError("Formation-only portfolio changed under future-only perturbation")
            selected = (strict[:,0]>0) | (strict[:,4]>0)
            missing = selected & ~np.isfinite(pnl[:,t])
            complete = bool(selected.any() and not missing.any())
            zero_mark = np.where(np.isfinite(pnl[:,t]),pnl[:,t],0.0)
            strict_zero = (float(np.dot(strict[:,4],zero_mark)-
                                 np.dot(strict[:,0],zero_mark)) if selected.any() else np.nan)
            direct_complete = strict_zero if complete else np.nan
            rows.append(dict(
                experiment_id=eid,year_week=int(week),
                formation_forecast_cap_price_eligible_n=int(formation.sum()),
                retrospective_target_available_n=int(target.sum()),
                formation_only_quintile_counts="|".join(map(str,n_strict)),
                accepted_replay_quintile_counts="|".join(map(str,n_replay)),
                strict_low_count=int((strict[:,0]>0).sum()),
                strict_high_count=int((strict[:,4]>0).sum()),
                strict_low_missing_payoff_count=int(((strict[:,0]>0)&missing).sum()),
                strict_high_missing_payoff_count=int(((strict[:,4]>0)&missing).sum()),
                strict_low_missing_payoff_weight=float(strict[missing,0].sum()),
                strict_high_missing_payoff_weight=float(strict[missing,4].sum()),
                saved_vs_formation_only_l1=float(np.abs(actual_legs-strict[:,[0,4]]).sum()),
                accepted_replay_after_target_availability_toggle_l1=float(np.abs(replay_legs-changed[:,[0,4]]).sum()),
                strict_formation_after_target_toggle_l1=strict_l1,
                strict_direct_hl_if_all_selected_payoffs_observed=direct_complete,
                strict_zero_mark_missing_payoffs_hl_scenario=strict_zero,
                saved_hl=float(base["cResults"].VW.mPortRet[-1,t]),
                economic_executable_status="unverified_no_announcement_or_order_book",
            ))
        print(f"E05_PROGRESS {eid} weeks={len(weeks)}",flush=True)
    if errors:
        write(OUT / "baseline_reconstruction_mismatches.csv",
              [dict(experiment_id=e,year_week=t,max_abs_weight_error=x) for e,t,x in errors])
        raise RuntimeError(f"Accepted baseline weight replay failed {len(errors)} weeks; see mismatch CSV")
    (OUT / "baseline_reconstruction_mismatches.csv").unlink(missing_ok=True)
    write(OUT / "formation_snapshot_and_future_availability_perturbation.csv",rows)
    print(f"E05_FORMATION_CHANNEL_OK weeks={len(rows)} exact_baseline_replay=1; "
          "full_b01_b05_future_perturbation=NOT_YET_TESTED",flush=True)


if __name__=="__main__":
    main()
