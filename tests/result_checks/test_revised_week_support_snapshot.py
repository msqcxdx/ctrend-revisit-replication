#!/usr/bin/env python3
# CTREND_REVISIT_FILE_PURPOSE: Recompute finite-week masks and statistics from eighteen saved baselines; never hardcode expected finite counts.
# The common sample is derived from actual year-week keys and finite H-L returns
# on every run.  No historical week count is embedded as an acceptance target,
# so a legitimate sample change remains auditable rather than falsely failing.
from pathlib import Path
import csv,hashlib
import numpy as np
from scipy.io import loadmat
R=Path(__file__).resolve().parents[2];S=R/'results'
def rows(rel):return list(csv.DictReader((S/rel).open()))
weekly=rows('comparisons/source_tables/common_week/eighteen_experiment_weekly_returns.csv')
dates=np.array([int(x['year_week']) for x in weekly]);ids=[x for x in weekly[0] if x.startswith('P')]
panel=np.array([[float(x[id]) for id in ids] for x in weekly]);finite=np.isfinite(panel);common=np.all(finite,axis=1)
assert np.array_equal(common,np.array([int(x['all_eighteen_common']) for x in weekly],dtype=bool))
summ={x['experiment']:x for x in rows('comparisons/source_tables/common_week/eighteen_experiment_all_common_summary.csv')}
own={x['experiment_id']:x for x in rows('comparisons/source_tables/exact_headline_from_mat.csv')}
for j,id in enumerate(ids):
 # Re-read each MAT baseline and independently reproduce own/common support statistics.
 s=loadmat(S/'experiments'/id/'CTREND/CTREND_Base.mat',simplify_cells=True,variable_names=['vDates','cResults'])
 assert np.array_equal(dates,s['vDates'])
 x=np.asarray(s['cResults']['VW']['mPortRet'][-1]);assert np.allclose(x,panel[:,j],equal_nan=True,rtol=1e-12,atol=1e-12)
 assert finite[:,j].sum()==int(own[id]['finite_hl_weeks'])
 assert common.sum()==int(summ[id]['n'])
 z=x[common];mean=100*z.mean();sd=100*z.std(ddof=1)
 assert np.isclose(mean,float(summ[id]['mean_pct']),atol=1e-10)
 assert np.isclose(np.sqrt(52)*mean/sd,float(summ[id]['annualized_sharpe']),atol=1e-10)
print('CURRENT_18_WEEK_SUPPORT_RECOMPUTED_OK common_weeks=',common.sum())
