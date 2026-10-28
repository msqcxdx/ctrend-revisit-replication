#!/usr/bin/env python3
# CTREND_REVISIT_FILE_PURPOSE: diagnose eighteen accepted runs; publication orchestration, validation or saved-result analysis, not a model-definition edit.
# Inputs: compact accepted result copies plus their saved holding/payoff audits.
# Outputs: support, holding overlap, and fixed-weight payoff-exchange CSVs.
# Boundary: diagnostics compare already formed portfolios; they never refit a
# signal or use a counterfactual payoff when terminal-trade ledgers differ.
"""Read accepted baseline copies; quantify matching support, holdings and payoff.

No model is refitted. Fixed-weight payoff exchanges are deliberately restricted
to dates without within-week terminal trades in either donor, since a simple
dot product cannot reproduce the event-day reinvestment ledger.
"""
from pathlib import Path
import argparse,csv,hashlib,itertools,math
from functools import lru_cache
import numpy as np
from scipy.io import loadmat

ROOT=Path(__file__).resolve().parents[1]
parser=argparse.ArgumentParser(description=__doc__)
parser.add_argument('--results-root',type=Path,default=ROOT/'results',
                    help='Root containing the eighteen exported experiments; default is the included reference snapshot.')
RESULTS=parser.parse_args().results_root.resolve()
OUT=RESULTS/'diagnostics/portfolio_diagnostics'
OUT.mkdir(parents=True,exist_ok=True)
IDS=[f'P{p}_M{m}_D{d}' for p in range(2) for m in (0,2,1) for d in range(3)]
def write(name, rows):
    assert rows,name
    with (OUT/name).open('w',newline='') as f:
        w=csv.DictWriter(f,list(rows[0]),lineterminator='\n');w.writeheader();w.writerows(rows)
@lru_cache(maxsize=2)
def base(id):
    p=RESULTS/'experiments'/id/'CTREND/CTREND_Base.mat'
    s=loadmat(p,simplify_cells=True,variable_names=['cResults','mYhat','vAssetID','vDates','mRetPnlOOS','mSelected'])
    s['sha']=hashlib.sha256(p.read_bytes()).hexdigest()
    return s
def stats(x):
    x=np.asarray(x); x=x[np.isfinite(x)];n=len(x)
    mean=np.mean(x) if n else np.nan;sd=np.std(x,ddof=1) if n>1 else np.nan
    return dict(n=n,mean_pct=100*mean,std_pct=100*sd,t=mean/sd*np.sqrt(n) if sd>0 else np.nan,sharpe=np.sqrt(52)*mean/sd if sd>0 else np.nan)
def aligned(a,b):
    dates,ta,tb=np.intersect1d(a['vDates'],b['vDates'],return_indices=True)
    assets,aa,ab=np.intersect1d(a['vAssetID'],b['vAssetID'],return_indices=True)
    return dates,ta,tb,assets,aa,ab
def correlation(x,y):
    mask=np.isfinite(x)&np.isfinite(y)
    return float(np.corrcoef(x[mask],y[mask])[0,1]) if mask.sum()>1 else np.nan

pairs=[]
# Enumerate all eighteen cells once, then derive planned one-axis comparisons.
for p in range(2):
 for d in range(3):
  for m,n in ((0,2),(2,1),(0,1)):pairs.append(('M',f'P{p}_M{m}_D{d}',f'P{p}_M{n}_D{d}'))
for m in (0,2,1):
 for d in range(3):pairs.append(('P',f'P0_M{m}_D{d}',f'P1_M{m}_D{d}'))
for p in range(2):
 for m in (0,2,1):
  for d,e in ((0,1),(1,2),(0,2)):pairs.append(('D',f'P{p}_M{m}_D{d}',f'P{p}_M{m}_D{e}'))

overlap=[];swaps=[];events=[];identity=[]
# Summarize each accepted baseline on its own finite support before any paired
# intersection is constructed.
for id in IDS:
    s=base(id);v=s['cResults']['VW'];mask=np.asarray(s['vDates'])==202016
    assert mask.sum()==1
    t=int(np.flatnonzero(mask)[0]);asset=np.flatnonzero(s['vAssetID']==3787)
    i=int(asset[0]) if len(asset) else None
    identity.append(dict(experiment_id=id,baseline_sha256=s['sha'],**stats(v['mPortRet'][-1])))
    payoff=float(s['mRetPnlOOS'][i,t]) if i is not None and 'mRetPnlOOS' in s else np.nan
    # Saved mWts represents non-members with NaN. This is a zero holding,
    # not a missing realized return: never apply this replacement to payoff.
    low=float(np.nan_to_num(v['mWts'][i,t,0],nan=0.)) if i is not None else 0.
    high=float(np.nan_to_num(v['mWts'][i,t,-1],nan=0.)) if i is not None else 0.
    events.append(dict(experiment_id=id,result_year_week=202016,asset_id=3787,present=int(i is not None),
        forecast=float(s['mYhat'][i,t]) if i is not None else np.nan,low_weight=low,high_weight=high,
        saved_asset_payoff=payoff,direct_opening_weight_hl_contribution_pct=100*(high-low)*payoff,
        saved_week_hl_pct=100*v['mPortRet'][-1,t],
        within_week_trade_cost_base_low=float(v.get('mWithinWeekTradeCostBaseFull',np.zeros((len(s['vDates']),5)))[t,0]),
        within_week_trade_cost_base_high=float(v.get('mWithinWeekTradeCostBaseFull',np.zeros((len(s['vDates']),5)))[t,-1])))

# Pairwise diagnostics align by saved dates and CMCIDs. Fixed-weight exchanges
# are restricted to rows where a plain dot product reproduces both ledgers.
for axis,ida,idb in pairs:
    a,b=base(ida),base(idb);dates,ta,tb,assets,aa,ab=aligned(a,b)
    va,vb=a['cResults']['VW'],b['cResults']['VW']
    ra,rb=va['mPortRet'][-1,ta],vb['mPortRet'][-1,tb]
    common=np.isfinite(ra)&np.isfinite(rb)
    x=a['mYhat'][aa][:,ta];y=b['mYhat'][ab][:,tb]
    row=dict(axis=axis,from_experiment=ida,to_experiment=idb,common_weeks=int(common.sum()),
        common_forecast_cells=int((np.isfinite(x)&np.isfinite(y)).sum()),forecast_correlation=correlation(x,y),
        weekly_return_correlation=correlation(ra,rb))
    for leg,k in [('low',0),('high',4)]:
        js=[];l1=[]
        for j in np.flatnonzero(common):
            wa=np.nan_to_num(va['mWts'][:,ta[j],k],nan=0.);wb=np.nan_to_num(vb['mWts'][:,tb[j],k],nan=0.)
            sa=set(a['vAssetID'][wa>0]);sb=set(b['vAssetID'][wb>0]);union=sa|sb
            if union:js.append(len(sa&sb)/len(union))
            # Include unmatched CMCIDs, rather than comparing only survivors.
            da=dict(zip(a['vAssetID'],wa));db=dict(zip(b['vAssetID'],wb))
            l1.append(sum(abs(da.get(z,0)-db.get(z,0)) for z in union))
        row[f'{leg}_jaccard_mean']=float(np.mean(js));row[f'{leg}_full_l1_mean']=float(np.mean(l1))
    overlap.append(row)

    if not (axis=='M' and '_M2_' in ida and '_M1_' in idb):continue
    # Four corner counterfactual: donor weights a/b, donor endpoint a/b. All
    # corners use one identical support and no terminal trade in either leg.
    cash_a=np.asarray(va['mWithinWeekTradeCostBaseFull'])[ta][:,[0,4]]
    cash_b=np.asarray(vb['mWithinWeekTradeCostBaseFull'])[tb][:,[0,4]]
    no_event=np.all(np.isfinite(cash_a)&(cash_a==0),axis=1)&np.all(np.isfinite(cash_b)&(cash_b==0),axis=1)
    pa=a['mRetPnlOOS'][aa][:,ta];pb=b['mRetPnlOOS'][ab][:,tb]
    arrays={}
    for wn,s,vi,ix,tx in [('M2',a,va,aa,ta),('M1',b,vb,ab,tb)]:
      for pn,pay in [('M2',pa),('M1',pb)]:
        w=vi['mWts'][ix][:,tx,:];legvals=[]
        for k in (0,4):
            ws=np.nan_to_num(w[:,:,k],nan=0.)
            sums=ws.sum(axis=0);good=np.isclose(sums,1,atol=1e-10)&np.all((ws==0)|np.isfinite(pay),axis=0)
            ret=np.sum(ws*np.nan_to_num(pay,nan=0.),axis=0);ret[~good]=np.nan;legvals.append(ret)
        arrays[f'W{wn}_R{pn}']=legvals[1]-legvals[0]
    valid=common&no_event
    for v in arrays.values():valid &= np.isfinite(v)
    assert valid.sum()>1,(ida,idb,'empty exchange support')
    for diagonal,saved in [('WM2_RM2',ra),('WM1_RM1',rb)]:
        assert np.allclose(arrays[diagonal][valid],saved[valid],atol=1e-10,rtol=1e-10),(ida,idb,diagonal)
    for key,x in arrays.items():
        swaps.append(dict(from_experiment=ida,to_experiment=idb,corner=key,
            support='four_corner_common_no_terminal_trade',**stats(x[valid])))

write('BASELINE_DIAGNOSTIC_IDENTITIES.csv',identity)
write('KEY_PAIR_FORECAST_HOLDINGS_OVERLAP.csv',overlap)
write('FIXED_WEIGHT_ENDPOINT_EXCHANGE.csv',swaps)
write('INNBCL_2020W16_SAVED_HOLDINGS.csv',events)
print('CURRENT_18_DIAGNOSTICS_OK',len(identity),len(overlap),len(swaps),len(events))
