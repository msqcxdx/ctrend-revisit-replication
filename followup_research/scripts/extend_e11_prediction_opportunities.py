#!/usr/bin/env python3
"""Read the complete accepted design grid: forecasts and factor opportunities.

Counts use the stored asset axis and the DESIGN-SPECIFIC post-training
calendar; they are not coverage conditional on an unknown eligible universe.
Opportunity sets for M0/M2/M1 share all three returns and the SAME external
LTW weeks within each cell. No count of correlated designs is a t-test N.
Writes only isolated supplement output; no models are re-estimated.
"""
import argparse
from concurrent.futures import ProcessPoolExecutor
import csv
import json
from pathlib import Path
import time
import numpy as np
from scipy.io import loadmat
from analyze_e11 import ROOT, OUT, METHODS, digest
from paired_stats import max_squared_sharpe


def worker(p,d,paths,designs,limit):
    name=f'forecast_opportunity_grid_P{p}_D{d}.csv';temp=OUT/(name+'.partial')
    factors=list(csv.DictReader((ROOT/'outputs/E01'/f'P{p}_M1_D{d}'/'e01_weekly_factors.csv').open()))
    weeks=np.array([int(float(r['week_key'])) for r in factors])
    f=np.array([[float(r[f'external_{n}']) for n in ('cmkt','csize','cmom')] for r in factors])
    rows=0; start=time.time()
    with temp.open('w',newline='') as stream:
        writer=None
        for combo in range(1,limit+1):
            ntrain=int(designs[combo-1]['vNumIn']);available={};predictions={}
            for m in (0,2,1):
                path=Path(paths[f'P{p}_M{m}_D{d}'])/'CTREND'/f'CTREND_Combo{combo}.mat'
                r=loadmat(path,simplify_cells=True,variable_names=['mYhat','mTrend_5','vDates','vAssetID','cTrendNames'])
                if not np.array_equal(weeks,np.asarray(r['vDates'],int).ravel()):raise ValueError('calendar')
                if tuple(str(n) for n in np.atleast_1d(r['cTrendNames']))!=METHODS:raise ValueError('model order')
                forecast=np.asarray(r['mYhat'],float)
                nassets=len(np.asarray(r['vAssetID']).ravel())
                if forecast.shape!=(nassets,len(weeks),len(METHODS)):raise ValueError('forecast axes')
                count=np.isfinite(forecast[:,ntrain:,:]).sum(axis=0)
                predictions[m]=(nassets,count)
                available[m]=np.asarray(r['mTrend_5'],float)
                del forecast,r
            for j,method in enumerate(METHODS):
                common=np.isfinite(f).all(axis=1)
                for m in (0,2,1):common &= np.isfinite(available[m][:,j])
                common[:ntrain]=False
                for m in (0,2,1):
                    count=predictions[m][1][:,j];assets=predictions[m][0]
                    row=dict(p=p,d=d,method_family=f'M{m}',b09_combo_id=combo,estimator=method,
                        training_calendar_weeks=ntrain,scheduled_oos_weeks=len(count),stored_assets=assets,
                        forecast_asset_week_count=int(count.sum()),weeks_with_any_forecast=int((count>0).sum()),
                        mean_forecast_assets_per_scheduled_week=float(count.mean()),
                        denominator='stored_assets_not_formation_eligible_universe',
                        own_finite_portfolio_weeks=int(np.isfinite(available[m][ntrain:,j]).sum()),
                        common_three_method_and_external_factor_weeks=int(common.sum()),
                        opportunity_status='insufficient_common_weeks',
                        max_s2_base=np.nan,max_s2_ltw=np.nan,max_s2_trend=np.nan,max_s2_full=np.nan,
                        full_minus_ltw=np.nan,trend_minus_ltw=np.nan)
                    if common.sum()>=20:
                        z=np.column_stack((f[common],available[m][common,j]))
                        try:
                            val={key:max_squared_sharpe(z[:,cols]) for key,cols in
                                 {'base':(0,1),'ltw':(0,1,2),'trend':(0,1,3),'full':(0,1,2,3)}.items()}
                            row.update(opportunity_status='computed_descriptive_common_system',
                                **{'max_s2_'+k:v for k,v in val.items()},
                                full_minus_ltw=val['full']-val['ltw'],trend_minus_ltw=val['trend']-val['ltw'])
                            if row['full_minus_ltw']<-1e-10:raise RuntimeError('nested opportunity identity')
                        except (ValueError,np.linalg.LinAlgError):row['opportunity_status']='unidentified_covariance'
                    if writer is None:writer=csv.DictWriter(stream,fieldnames=list(row));writer.writeheader()
                    writer.writerow(row);rows+=1
            if combo%128==0 or combo==limit:
                stream.flush();print(f'E11_EXT_PROGRESS P{p}D{d} {combo}/{limit} elapsed={time.time()-start:.0f}s',flush=True)
    temp.replace(OUT/name)
    return dict(p=p,d=d,path=name,rows=rows,sha256=digest(OUT/name))


def main():
    ap=argparse.ArgumentParser();ap.add_argument('--workers',type=int,default=6)
    ap.add_argument('--limit',type=int,default=3072);args=ap.parse_args()
    if not 1<=args.limit<=3072:raise ValueError('limit')
    if len({digest(OUT/f'design_choices_M{m}.csv') for m in (0,2,1)})!=1:raise ValueError('design identity')
    rows=list(csv.DictReader((OUT/'accepted_run_paths.csv').open()))
    paths={r['experiment_id']:r['result_root'] for r in rows}
    designs=list(csv.DictReader((OUT/'design_choices_M1.csv').open()))
    with ProcessPoolExecutor(max_workers=min(args.workers,6)) as pool:
        jobs=[pool.submit(worker,p,d,paths,designs,args.limit) for p in (0,1) for d in (0,1,2)]
        files=[j.result() for j in jobs]
    if any(r['rows']!=args.limit*len(METHODS)*3 for r in files):raise ValueError('scope incomplete')
    (OUT/'prediction_opportunity_receipt.json').write_text(json.dumps(dict(
        status='complete' if args.limit==len(designs) else 'bounded_test_only',
        designs_per_cell=args.limit,outputs=files,accepted_run_table_sha256=digest(OUT/'accepted_run_paths.csv'),
        script_sha256=digest(Path(__file__)),method='all3_common_week_descriptive_no_independent_design_pvalue'),indent=2)+'\n')
    print('E11_PREDICTION_OPPORTUNITIES_OK',flush=True)


if __name__=='__main__':main()
