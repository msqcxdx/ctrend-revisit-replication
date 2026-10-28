#!/usr/bin/env python3
"""Compare M2/M1 forecast-coverage groups using one common saved payoff."""

from __future__ import annotations

import csv
from pathlib import Path

import h5py
import numpy as np
from scipy.io import loadmat
from scipy.stats import spearmanr


ROOT=Path(__file__).resolve().parents[1]
REPO=ROOT.parent
OUT=ROOT/"outputs"/"E07"


def median(x: np.ndarray) -> float:
    x=x[np.isfinite(x)]
    return float(np.median(x)) if len(x) else np.nan


def corr(x: np.ndarray,y: np.ndarray) -> float:
    good=np.isfinite(x)&np.isfinite(y)
    if good.sum()<10 or np.unique(x[good]).size<3 or np.unique(y[good]).size<3:
        return np.nan
    return float(spearmanr(x[good],y[good]).statistic)


def write(file: Path,rows: list[dict]) -> None:
    file.parent.mkdir(parents=True,exist_ok=True)
    with file.open("w",newline="",encoding="utf-8") as f:
        w=csv.DictWriter(f,fieldnames=list(rows[0]));w.writeheader();w.writerows(rows)


def main() -> None:
    roots={r["experiment_id"]:Path(r["accepted_run_root"])
           for r in csv.DictReader((ROOT/"outputs/E11/accepted_run_paths.csv").open())}
    weekly=[];groups=[]
    for p in (0,1):
        for d in (0,1,2):
            names=[f"P{p}_M{m}_D{d}" for m in (2,1)]
            mat=[]
            for eid in names:
                r=loadmat(REPO/"results"/"experiments"/eid/"CTREND"/"CTREND_Base.mat",
                          squeeze_me=True,struct_as_record=False,
                          variable_names=["mYhat","mRetPnlOOS","vDates","vAssetID"])
                mat.append(r)
            a,b=mat
            dates=np.asarray(a["vDates"],dtype=int).ravel()
            if not np.array_equal(dates,b["vDates"]) or not np.array_equal(a["vAssetID"],b["vAssetID"]):
                raise RuntimeError(f"M2/M1 axes disagree P{p}D{d}")
            data=roots[names[1]]/"data"/"bCharacteristicsOLHC_Combo1.mat"
            if not data.is_file():data=roots[names[1]]/"data.staging"/"bCharacteristicsOLHC_Combo1.mat"
            with h5py.File(data) as f:
                r=f["rData"];weeks_all=np.asarray(r["yrmoda"][:],dtype=int).ravel()
                cap=np.asarray(r["mME"][:],dtype=float)
                close=np.asarray(r["mClose"][:],dtype=float)
                dollar=np.asarray(f["rChars"]["prcvol"][:],dtype=float)
            sample_idx=np.flatnonzero((weeks_all>=201416)&(weeks_all<=202222))
            if not np.array_equal(weeks_all[sample_idx],dates):
                raise RuntimeError(f"M1 DATA week axes disagree P{p}D{d}")
            historical_valid=np.isfinite(close)&(close>0)
            first=np.where(historical_valid.any(axis=1),historical_valid.argmax(axis=1),len(weeks_all))
            f2=np.asarray(a["mYhat"],dtype=float)
            f1=np.asarray(b["mYhat"],dtype=float)
            common_payoff=np.asarray(b["mRetPnlOOS"],dtype=float)
            for t,week in enumerate(dates):
                idx=sample_idx[t]-1
                y2,y1=f2[:,t],f1[:,t]
                is2,is1=np.isfinite(y2),np.isfinite(y1)
                masks={"both":is2&is1,"only_m2":is2&~is1,"only_m1":~is2&is1}
                age=np.where(first<=idx,idx-first,np.nan).astype(float)
                c=cap[:,idx]
                vol=dollar[:,idx]
                pnl=common_payoff[:,t]
                joint=masks["both"]&np.isfinite(pnl)
                weekly.append(dict(p=p,d=d,year_week=int(week),
                                   both_forecast_count=int(masks["both"].sum()),
                                   only_m2_forecast_count=int(masks["only_m2"].sum()),
                                   only_m1_forecast_count=int(masks["only_m1"].sum()),
                                   m2_m1_forecast_spearman=corr(y2[masks["both"]],y1[masks["both"]]),
                                   m2_same_payoff_rank_ic=corr(y2[joint],pnl[joint]),
                                   m1_same_payoff_rank_ic=corr(y1[joint],pnl[joint]),
                                   common_payoff_definition="M1_saved_economic_PnL"))
                for name,mask in masks.items():
                    groups.append(dict(p=p,d=d,year_week=int(week),forecast_group=name,
                                       n=int(mask.sum()),
                                       formation_cap_median_usd=median(c[mask]),
                                       formation_dollar_volume_median_usd=median(vol[mask]),
                                       observed_age_weeks_median=median(age[mask]),
                                       m1_payoff_finite_fraction=float(np.isfinite(pnl[mask]).mean()) if mask.any() else np.nan,
                                       m1_payoff_p05= float(np.quantile(pnl[mask&np.isfinite(pnl)],.05)) if (mask&np.isfinite(pnl)).any() else np.nan,
                                       m1_payoff_p95= float(np.quantile(pnl[mask&np.isfinite(pnl)],.95)) if (mask&np.isfinite(pnl)).any() else np.nan,
                                       scope="diagnostic_group_not_causal_event_code"))
            print(f"E07_GROUP_PROGRESS P{p}_D{d} weeks={len(dates)}",flush=True)
    write(OUT/"forecast_group_characteristics_by_week.csv",groups)
    write(OUT/"same_payoff_forecast_rank_by_week.csv",weekly)
    print(f"E07_GROUPS_OK weekly={len(weekly)} group_rows={len(groups)}",flush=True)


if __name__=="__main__":main()
