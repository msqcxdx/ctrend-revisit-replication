#!/usr/bin/env python3
"""Describe every holding-period phase and symmetric tail differences.

Ranges are descriptive across dependent timing conventions, not confidence
intervals and not independent replications. Tail rows retain the original
week and cohort identity; no outlier is deleted from any return statistic.
"""
import csv
from pathlib import Path
import numpy as np

ROOT=Path(__file__).resolve().parents[1]
OUT=ROOT/'outputs/E10'


def write(name,rows):
    with (OUT/name).open('w',newline='') as f:
        w=csv.DictWriter(f,fieldnames=list(rows[0]));w.writeheader();w.writerows(rows)


def main():
    summary=list(csv.DictReader((OUT/'published_ledger_vs_fixed_cohort.csv').open()))
    envelopes=[];tails=[]
    for eid in sorted({r['experiment_id'] for r in summary}):
        weekly=list(csv.DictReader((OUT/f'{eid}_weekly_holding.csv').open()))
        for h in range(1,7):
            group=[r for r in summary if r['experiment_id']==eid and int(r['holding_weeks'])==h]
            assert sorted(int(r['phase']) for r in group)==list(range(1,h+1))
            row=dict(experiment_id=eid,holding_weeks=h,all_phases=h)
            for field in ('n_pair','fixed_mean_pct','fixed_sharpe','fixed_external_ltw_alpha_pct',
                          'fixed_alpha_hac_ci_low_pct','fixed_alpha_hac_ci_high_pct','published_mean_pct'):
                values=np.array([float(r[field]) for r in group])
                row[field+'_phase_min']=float(values.min())
                row[field+'_phase_max']=float(values.max())
            row['interpretation']='phase_range_not_CI_or_independent_replications'
            envelopes.append(row)
            for phase in range(1,h+1):
                cells=[r for r in weekly if int(r['holding_weeks'])==h and int(r['phase'])==phase
                       and np.isfinite(float(r['fixed_cohort_hl_return']))
                       and np.isfinite(float(r['published_repeated_signal_sort_hl_return']))]
                cells.sort(key=lambda r:float(r['fixed_cohort_hl_return'])-float(r['published_repeated_signal_sort_hl_return']))
                for direction,chosen in (('most_negative',cells[:5]),('most_positive',cells[-5:][::-1])):
                    for rank,r in enumerate(chosen,1):
                        tails.append(dict(experiment_id=eid,holding_weeks=h,phase=phase,
                            year_week=r['year_week'],cohort_formation_week=r['cohort_formation_week'],
                            direction=direction,rank=rank,
                            fixed_cohort_hl_return=r['fixed_cohort_hl_return'],
                            published_repeated_signal_sort_hl_return=r['published_repeated_signal_sort_hl_return'],
                            fixed_minus_published=float(r['fixed_cohort_hl_return'])-float(r['published_repeated_signal_sort_hl_return']),
                            interpretation='weekly_arithmetic_location_not_single_asset_or_causal_attribution'))
    write('all_phase_envelopes.csv',envelopes)
    write('symmetric_cohort_tail_differences.csv',tails)
    print(f'E10_PHASE_SENSITIVITY_OK envelopes={len(envelopes)} tails={len(tails)}')


if __name__=='__main__':main()
