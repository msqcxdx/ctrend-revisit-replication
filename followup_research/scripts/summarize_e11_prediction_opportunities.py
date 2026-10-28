#!/usr/bin/env python3
"""Describe the full forecast/opportunity grid without treating designs as IID.

All three methods in a cell use exactly the same evaluation weeks. Sample-
length sensitivities (20/52/104 weeks) are reported together, not selected for
favorable estimates. These are distributions, not thousands of independent
hypothesis tests. Coverage denominators are the stored asset panel, not an
unobserved formation-eligible universe.
"""
import csv
import json
from collections import defaultdict
from pathlib import Path
import numpy as np
from analyze_e11 import OUT, digest


def main():
    receipt=json.loads((OUT/'prediction_opportunity_receipt.json').read_text())
    if receipt['status']!='complete':raise ValueError('Full design scan required')
    summaries=[]
    for item in receipt['outputs']:
        path=OUT/item['path']
        if digest(path)!=item['sha256']:raise ValueError('Grid output changed')
        groups=defaultdict(list)
        with path.open(newline='') as f:
            for row in csv.DictReader(f):groups[(row['method_family'],row['estimator'])].append(row)
        for (method,estimator),rows in sorted(groups.items()):
            if len(rows)!=receipt['designs_per_cell']:raise ValueError('Incomplete design group')
            for minimum in (20,52,104):
                selected=[r for r in rows if r['opportunity_status']=='computed_descriptive_common_system'
                          and int(r['common_three_method_and_external_factor_weeks'])>=minimum]
                result=dict(p=item['p'],d=item['d'],method_family=method,estimator=estimator,
                    minimum_common_weeks=minimum,designs=len(rows),opportunity_identified_designs=len(selected),
                    no_finite_portfolio_designs=sum(int(r['own_finite_portfolio_weeks'])==0 for r in rows),
                    zero_forecast_designs=sum(int(r['forecast_asset_week_count'])==0 for r in rows),
                    median_own_finite_weeks=float(np.median([int(r['own_finite_portfolio_weeks']) for r in rows])),
                    median_mean_forecast_assets=float(np.median([float(r['mean_forecast_assets_per_scheduled_week']) for r in rows])),
                    coverage_denominator='stored_assets_and_design_specific_scheduled_weeks',
                    inference='descriptive_correlated_designs_not_independent_replications')
                for key in ('max_s2_ltw','full_minus_ltw','trend_minus_ltw'):
                    values=np.array([float(r[key]) for r in selected])
                    for label,q in (('p10',.1),('median',.5),('p90',.9)):
                        result[f'{key}_{label}']=float(np.quantile(values,q)) if len(values) else np.nan
                    if key=='trend_minus_ltw':
                        result['trend_beats_ltw_fraction']=float(np.mean(values>0)) if len(values) else np.nan
                summaries.append(result)
    path=OUT/'prediction_opportunity_grid_summary.csv'
    with path.open('w',newline='') as f:
        w=csv.DictWriter(f,fieldnames=list(summaries[0]));w.writeheader();w.writerows(summaries)
    print(f'E11_PREDICTION_OPPORTUNITY_SUMMARY_OK rows={len(summaries)}')


if __name__=='__main__':main()
