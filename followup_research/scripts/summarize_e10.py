#!/usr/bin/env python3
"""Summarize all E10 cohort phases without choosing the best-looking phase."""

from __future__ import annotations

import csv
from pathlib import Path
import numpy as np

from paired_stats import annual_sharpe, newey_west


ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "outputs" / "E10"


def mean_or_nan(x: np.ndarray) -> float:
    valid = x[np.isfinite(x)]
    return float(valid.mean()) if len(valid) else np.nan


def main() -> None:
    rows = []
    published_rows=[]
    for p in (0,1):
        for d in (0,1,2):
            eid = f"P{p}_M1_D{d}"
            week_rows = list(csv.DictReader((OUT / f"{eid}_weekly_holding.csv").open()))
            factor_rows=list(csv.DictReader((ROOT/'outputs/E01'/eid/'e01_weekly_factors.csv').open()))
            factors_by_week={int(float(r['week_key'])):np.array([float(r[f'external_{n}'])
                            for n in ('cmkt','csize','cmom')]) for r in factor_rows}
            for h in range(1,7):
                for phase in range(1,h+1):
                    group = [r for r in week_rows if int(r["holding_weeks"])==h
                             and int(r["phase"])==phase]
                    fixed = np.array([float(r["fixed_cohort_hl_return"])
                                      for r in group])
                    reset = np.array([float(r["legacy_style_repeated_cap_hl_return"])
                                      for r in group])
                    paired = np.isfinite(fixed)&np.isfinite(reset)
                    if paired.sum()<20:
                        raise RuntimeError(f"Insufficient paired E10 weeks: {eid} H={h} phase={phase}")
                    f = fixed.copy(); z = reset.copy()
                    f[~paired]=np.nan; z[~paired]=np.nan
                    delta = f-z
                    stat = newey_west(delta,np.empty((len(delta),0)),lag=max(4,h-1))
                    rows.append(dict(
                        experiment_id=eid,holding_weeks=h,phase=phase,
                        scheduled_positions=len(group),fixed_n=int(np.isfinite(fixed).sum()),
                        legacy_style_n=int(np.isfinite(reset).sum()),
                        pair_n=int(paired.sum()),
                        fixed_pair_mean_week_pct=100*mean_or_nan(f),
                        reset_pair_mean_week_pct=100*mean_or_nan(z),
                        paired_mean_difference_week_pct=100*mean_or_nan(delta),
                        paired_mean_difference_hac_ci_low_pct=100*stat["alpha_ci_low"],
                        paired_mean_difference_hac_ci_high_pct=100*stat["alpha_ci_high"],
                        fixed_pair_annual_sharpe=annual_sharpe(f),
                        reset_pair_annual_sharpe=annual_sharpe(z),
                        exit_holding_weeks=sum(int(float(r["exit_holding_count"]))>0 for r in group),
                        no_recipient_weeks=sum(int(float(r["no_recipient"]))>0 for r in group),
                        inference_note="HAC_on_original_phase_calendar;_all_phases_reported",
                    ))
                    original=np.array([float(r['published_repeated_signal_sort_hl_return']) for r in group])
                    controls=np.array([factors_by_week[int(r['year_week'])] for r in group])
                    common=np.isfinite(fixed)&np.isfinite(original)&np.isfinite(controls).all(1)
                    fx=np.where(common,fixed,np.nan);old=np.where(common,original,np.nan)
                    diff=newey_west(fx-old,controls,lag=max(4,h-1))
                    alpha=newey_west(fx,controls,lag=max(4,h-1))
                    mean=newey_west(fx-old,np.empty((len(fx),0)),lag=max(4,h-1))
                    formed={int(r['cohort_formation_week']) for r in group if float(r['formation_valid'])==1}
                    published_rows.append(dict(experiment_id=eid,holding_weeks=h,phase=phase,
                        n_pair=int(common.sum()),nonoverlapping_formed_cohorts=len(formed),
                        weekly_positions_not_independent_cohort_count=len(group),
                        fixed_mean_pct=100*mean_or_nan(fx),published_mean_pct=100*mean_or_nan(old),
                        fixed_sharpe=annual_sharpe(fx),published_sharpe=annual_sharpe(old),
                        mean_diff_pct=100*mean['alpha'],mean_diff_hac_ci_low_pct=100*mean['alpha_ci_low'],
                        mean_diff_hac_ci_high_pct=100*mean['alpha_ci_high'],
                        fixed_external_ltw_alpha_pct=100*alpha['alpha'],
                        fixed_alpha_hac_ci_low_pct=100*alpha['alpha_ci_low'],
                        fixed_alpha_hac_ci_high_pct=100*alpha['alpha_ci_high'],
                        alpha_diff_pct=100*diff['alpha'],alpha_diff_hac_ci_low_pct=100*diff['alpha_ci_low'],
                        alpha_diff_hac_ci_high_pct=100*diff['alpha_ci_high'],
                        interpretation='same_initial_signal_cap_payoff;original_resorts_weekly_vs_fixed_members_drift_reinvest'))
    file = OUT / "all_phases_holding_comparison.csv"
    with file.open("w",newline="",encoding="utf-8") as f:
        writer=csv.DictWriter(f,fieldnames=list(rows[0]))
        writer.writeheader();writer.writerows(rows)
    with (OUT/'published_ledger_vs_fixed_cohort.csv').open('w',newline='',encoding='utf-8') as f:
        w=csv.DictWriter(f,fieldnames=list(published_rows[0]));w.writeheader();w.writerows(published_rows)
    print(f"E10_SUMMARY_OK phase_rows={len(rows)} H_range=1..6 all_phases=1")


if __name__=="__main__":
    main()
