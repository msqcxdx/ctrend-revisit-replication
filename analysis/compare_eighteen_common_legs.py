#!/usr/bin/env python3
# CTREND_REVISIT_FILE_PURPOSE: Recompute L, H and H-L on exactly the same eighteen-baseline common weeks, with no leg-specific deletion.
# Input: each experiment's accepted CTREND_Base.mat with a common date axis.
# Output: one CSV of leg moments on the single intersection defined by finite
# H-L returns in all eighteen cells. Missing observations are never filled.
# Failure means the saved date axes disagree or fewer than two common weeks exist.
from pathlib import Path
import csv
import numpy as np
from scipy.io import loadmat
R=Path(__file__).resolve().parents[1]
ids=[f'P{p}_M{m}_D{d}' for p in range(2) for m in (0,2,1) for d in range(3)]
# First bind every matrix to one exact calendar; positional comparisons are
# invalid unless this equality assertion succeeds.
data={};dates=None
for id in ids:
 s=loadmat(R/'results/experiments'/id/'CTREND/CTREND_Base.mat',simplify_cells=True,variable_names=['vDates','cResults'])
 if dates is None:dates=s['vDates']
 assert np.array_equal(dates,s['vDates'])
 data[id]=np.asarray(s['cResults']['VW']['mPortRet'])
# Select common weeks once from H-L and apply that unchanged mask to L and H.
# This prevents each leg from silently receiving a different sample.
shared=np.logical_and.reduce([np.isfinite(x[-1]) for x in data.values()]);n=int(shared.sum());assert n>1
rows=[]
for id,x in data.items():
 for k,name in [(0,'L'),(4,'H'),(5,'H-L')]:
  z=x[k,shared];assert np.isfinite(z).all(),(id,name)
  mean=z.mean();sd=z.std(ddof=1)
  rows.append(dict(experiment_id=id,portfolio=name,support='all_eighteen_HL_common',n=n,mean_pct=100*mean,std_pct=100*sd,
    t=mean/sd*np.sqrt(n) if sd>0 else np.nan,sharpe=mean/sd*np.sqrt(52) if sd>0 else np.nan))
out=R/'results/diagnostics/portfolio_diagnostics/COMMON_WEEK_LEGS_AND_HL.csv'
with out.open('w',newline='') as f:
 w=csv.DictWriter(f,list(rows[0]),lineterminator='\n');w.writeheader();w.writerows(rows)
print('COMMON_WEEK_LEGS_OK experiments=18 n=',n)
