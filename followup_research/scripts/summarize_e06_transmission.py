#!/usr/bin/env python3
"""Trace real E06 hybrid refits into forecast coverage, members and weights.

All comparisons are software interventions conditional on one P/D baseline
inputs. They are neither natural causal effects nor full-grid conclusions.
Jaccard uses actual extreme-leg positions; an empty union is undefined.
"""
import argparse
import csv
import json
from pathlib import Path
import numpy as np
from scipy.io import loadmat
from scipy.stats import spearmanr
from analyze_e03_e04 import write_table
from run_e06_upstream_hybrids import ROOT,sha


def main():
    ap=argparse.ArgumentParser();ap.add_argument('--out-dir',default=str(ROOT/'outputs/E06'))
    args=ap.parse_args();out=Path(args.out_dir)
    receipt=json.loads((out/'HYBRID_RECEIPT.json').read_text())
    data={}
    for variant,item in receipt['results'].items():
        p=Path(item['path'])
        if sha(p)!=item['sha256']:raise ValueError('Hybrid output identity')
        data[variant]=loadmat(p,simplify_cells=True,variable_names=['vDates','vAssetID','mYhat','mSelected','cResults'])
    weekly=[];summary=[];control=data['control']
    for name,z in data.items():
        if name=='control':continue
        assert np.array_equal(z['vAssetID'],control['vAssetID']) and np.array_equal(z['vDates'],control['vDates'])
        for t,week in enumerate(z['vDates']):
            x=control['mYhat'][:,t];y=z['mYhat'][:,t];both=np.isfinite(x)&np.isfinite(y)
            row=dict(variant=name,year_week=int(week),control_forecasts=int(np.isfinite(x).sum()),
                hybrid_forecasts=int(np.isfinite(y).sum()),shared_forecasts=int(both.sum()),
                forecast_spearman=float(spearmanr(x[both],y[both]).statistic) if both.sum()>3 and np.unique(x[both]).size>1 and np.unique(y[both]).size>1 else np.nan)
            for leg,j in (('low',0),('high',4)):
                a=np.nan_to_num(control['cResults']['VW']['mWts'][:,t,j],nan=0.)
                b=np.nan_to_num(z['cResults']['VW']['mWts'][:,t,j],nan=0.)
                union=(a>0)|(b>0);formed=(a.sum()>0 and b.sum()>0)
                row.update({leg+'_control_holdings':int((a>0).sum()),leg+'_hybrid_holdings':int((b>0).sum()),
                    leg+'_jaccard':float(((a>0)&(b>0)).sum()/union.sum()) if union.any() else np.nan,
                    leg+'_weight_l1':float(np.abs(a-b).sum()) if formed else np.nan,
                    leg+'_hybrid_hhi':float(b@b) if b.sum()>0 else np.nan,
                    leg+'_hybrid_max_weight':float(b.max()) if b.sum()>0 else np.nan})
            weekly.append(row)
        group=[r for r in weekly if r['variant']==name]
        result=dict(variant=name,calendar_weeks=len(group),
            scope=receipt.get('experiment_id','P0_M2_D1')+'_baseline_refit_not_natural_causal_effect')
        for k in group[0]:
            if k in ('variant','year_week'):continue
            v=np.array([r[k] for r in group],float);v=v[np.isfinite(v)]
            result['mean_'+k]=float(v.mean()) if len(v) else np.nan
        summary.append(result)
    write_table(out/'hybrid_forecast_to_holdings_weekly.csv',weekly)
    write_table(out/'hybrid_forecast_to_holdings_summary.csv',summary)
    print(f'E06_TRANSMISSION_OK rows={len(weekly)} variants={len(summary)}')


if __name__=='__main__':main()
