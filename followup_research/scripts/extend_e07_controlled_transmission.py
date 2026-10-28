#!/usr/bin/env python3
"""Separate saved-signal, coverage, weighting and evaluation-label channels.

This is a controlled re-sort, NOT refitting or a feasible alternative account.
Both methods use the same M1 lagged capitalization and economic payoff. Own-
forecast and shared-forecast universes are reported side by side. No unknown
selected payoff is silently discarded; intraweek-exit weeks are flagged as
unsuitable for interpreting opening-weight products as full portfolio P&L.
Raw OOS statistical labels are not mislabeled as outlier-cleaned labels.
"""
import csv
from pathlib import Path
import h5py
import numpy as np
from scipy.io import loadmat
from scipy.stats import spearmanr
from analyze_e07 import load, write_csv
from paired_stats import newey_west

ROOT=Path(__file__).resolve().parents[1]; REPO=ROOT.parent; OUT=ROOT/'outputs/E07'


def capped_weights(cap, maximum=.10):
    """Proportional redistribution with a hard per-asset cap; no residual cash."""
    cap=np.asarray(cap,float)
    if len(cap)*maximum < 1-1e-12:
        return None
    if not np.isfinite(cap).all() or np.any(cap<=0):
        raise ValueError('Weights require positive finite formation caps')
    w=np.zeros(len(cap)); active=np.ones(len(cap),bool); residual=1.
    while active.any():
        ids=np.flatnonzero(active)
        proposal=residual*cap[ids]/cap[ids].sum()
        hit=proposal>maximum+1e-14
        if not hit.any():
            w[ids]=proposal; break
        pinned=ids[hit]; w[pinned]=maximum
        active[pinned]=False; residual=1-w.sum()
    assert abs(w.sum()-1)<1e-12 and w.max()<=maximum+1e-12
    return w


def direct_sort(pred,cap,payoff,eligible,mode):
    ok=eligible & np.isfinite(pred) & np.isfinite(cap) & (cap>0)
    out=dict(formation_count=int(ok.sum()),low_count=0,high_count=0,
             low_max_weight=np.nan,high_max_weight=np.nan,direct_hl=np.nan,
             status='insufficient_formation')
    if ok.sum()<25:return out
    q=np.quantile(pred[ok],np.linspace(0,1,6),method='hazen')
    low=ok & (pred>=q[0]) & (pred<=q[1])
    high=ok & (pred>q[-2]) & (pred<=q[-1])
    out.update(low_count=int(low.sum()),high_count=int(high.sum()))
    if min(low.sum(),high.sum())<5:return out
    weights=[]
    for mask in (low,high):
        c=cap[mask]
        w=np.full(len(c),1/len(c)) if mode=='EW' else (
            c/c.sum() if mode=='VW' else capped_weights(c))
        if w is None:
            out['status']='10pct_cap_infeasible_no_cash_allowed';return out
        weights.append(w)
    out.update(low_max_weight=float(weights[0].max()),high_max_weight=float(weights[1].max()))
    if not np.isfinite(payoff[low|high]).all():
        out['status']='selected_payoff_missing_no_renormalization';return out
    out.update(status='direct_only',direct_hl=float(weights[1]@payoff[high]-weights[0]@payoff[low]))
    return out


def ic(pred,target,mask):
    n=int(mask.sum())
    if n<10 or np.unique(pred[mask]).size<3 or np.unique(target[mask]).size<3:return np.nan
    return float(spearmanr(pred[mask],target[mask]).statistic)


def main():
    roots={r['experiment_id']:Path(r['accepted_run_root']) for r in csv.DictReader(
        (ROOT/'outputs/E11/accepted_run_paths.csv').open())}
    rows=[]; prediction=[]; summaries=[]
    for p in (0,1):
        for d in (0,1,2):
            eid=f'P{p}_M1_D{d}'; one=load(eid); two=load(f'P{p}_M2_D{d}')
            if not np.array_equal(one['ids'],two['ids']):raise ValueError('asset identity')
            if not np.array_equal(one['weeks'],two['weeks']):raise ValueError('week identity')
            raw=loadmat(REPO/'results/experiments'/eid/'CTREND/CTREND_Base.mat',
                        squeeze_me=True,struct_as_record=False,
                        variable_names=['mRetLabelOOS','cResults'])
            label=np.asarray(raw['mRetLabelOOS'],float)
            ledger=raw['cResults'].VW
            data=roots[eid]/'data/bCharacteristicsOLHC_Combo1.mat'
            if not data.is_file():data=roots[eid]/'data.staging/bCharacteristicsOLHC_Combo1.mat'
            with h5py.File(data) as f:
                weeks=np.asarray(f['rData/yrmoda'],int).ravel()
                loc=np.flatnonzero(np.isin(weeks,one['weeks']))
                assert np.array_equal(weeks[loc],one['weeks']) and loc.min()>0
                cap=np.asarray(f['rData/mME'][:,loc-1])
                close=np.asarray(f['rData/mClose'][:,loc-1])
                stable=np.asarray(f['rMetaData/lIsStable'],bool).ravel()
                needs=np.asarray(f['rData/mPnlRequiresReinvestment'][:,loc],bool)
            for t,week in enumerate(one['weeks']):
                f1=one['forecast'][:,t];f2=two['forecast'][:,t]; pay=one['pnl'][:,t]
                form=np.isfinite(cap[:,t])&(cap[:,t]>=1e6)&np.isfinite(close[:,t])&(close[:,t]>0)&~stable
                both=form&np.isfinite(f1)&np.isfinite(f2)
                same=both&np.isfinite(pay)&np.isfinite(label[:,t])
                for m,forecast in ((2,f2),(1,f1)):
                    raw_support=both&np.isfinite(label[:,t]); pnl_support=both&np.isfinite(pay)
                    prediction.append(dict(p=p,d=d,year_week=int(week),method=f'M{m}',
                        same_asset_evaluation_count=int(same.sum()),
                        raw_stat_label_count=int(raw_support.sum()),economic_payoff_count=int(pnl_support.sum()),
                        label_rank_ic_same_assets=ic(forecast,label[:,t],same),
                        pnl_rank_ic_same_assets=ic(forecast,pay,same),
                        label_rank_ic_own_label_support=ic(forecast,label[:,t],raw_support),
                        pnl_rank_ic_own_pnl_support=ic(forecast,pay,pnl_support),
                        interpretation='M1_raw_OOS_statistical_label_NOT_cleaned_target'))
                    for support,mask in (('own_forecast',form),('both_forecast',both)):
                        for mode in ('VW','EW','VW_cap10pct'):
                            result=direct_sort(forecast,cap[:,t],pay,mask,mode)
                            # An exit anywhere in the compared formation
                            # universe is conservatively excluded from the
                            # paired direct-payoff summary, not assigned to a
                            # guessed receiving asset.
                            noexit=not bool(np.any(needs[:,t] & (form if support=='own_forecast' else both)))
                            rows.append(dict(p=p,d=d,year_week=int(week),method=f'M{m}',
                                support=support,weighting=mode,
                                no_exit_in_comparison_universe=int(noexit),**result))
            print(f'E07_CONTROLLED_PROGRESS P{p}D{d}',flush=True)
    for p in (0,1):
        for d in (0,1,2):
            for support in ('own_forecast','both_forecast'):
                for mode in ('VW','EW','VW_cap10pct'):
                    a=[r for r in rows if r['p']==p and r['d']==d and r['support']==support and r['weighting']==mode and r['method']=='M2']
                    b=[r for r in rows if r['p']==p and r['d']==d and r['support']==support and r['weighting']==mode and r['method']=='M1']
                    assert [r['year_week'] for r in a]==[r['year_week'] for r in b]
                    ya=np.array([r['direct_hl'] for r in a]);yb=np.array([r['direct_hl'] for r in b])
                    keep=np.isfinite(ya)&np.isfinite(yb)&np.array([bool(r['no_exit_in_comparison_universe']) for r in a])
                    delta=np.where(keep,yb-ya,np.nan)
                    reg=newey_west(delta,np.empty((len(delta),0))) if keep.sum()>10 else None
                    summaries.append(dict(p=p,d=d,support=support,weighting=mode,
                        paired_no_exit_weeks=int(keep.sum()),
                        m2_mean_pct=100*float(ya[keep].mean()) if keep.any() else np.nan,
                        m1_mean_pct=100*float(yb[keep].mean()) if keep.any() else np.nan,
                        paired_difference_pct=100*reg['alpha'] if reg else np.nan,
                        ci_low_hac_pct=100*reg['alpha_ci_low'] if reg else np.nan,
                        ci_high_hac_pct=100*reg['alpha_ci_high'] if reg else np.nan,
                        interpretation='controlled_sort_M1_cap_and_payoff_not_refitted_or_real_account'))
    # Comparing the two support summaries above also changes calendar weeks.
    # Use the intersection of all FOUR portfolios for a coverage-only
    # contrast, conditional on saved forecasts and the common cap/payoff layer.
    matched=[]
    for p in (0,1):
        for d in (0,1,2):
            for mode in ('VW','EW','VW_cap10pct'):
                cells={}
                valid=[]
                for support in ('own_forecast','both_forecast'):
                    for method in ('M2','M1'):
                        cell=[r for r in rows if r['p']==p and r['d']==d and
                              r['weighting']==mode and r['support']==support and r['method']==method]
                        if cells:
                            assert [r['year_week'] for r in cell]==calendar
                        else:
                            calendar=[r['year_week'] for r in cell]
                        y=np.array([r['direct_hl'] for r in cell])
                        cells[support,method]=y
                        valid.append(np.isfinite(y)&np.array([bool(r['no_exit_in_comparison_universe']) for r in cell]))
                keep=np.logical_and.reduce(valid)
                own=cells['own_forecast','M1']-cells['own_forecast','M2']
                shared=cells['both_forecast','M1']-cells['both_forecast','M2']
                contrast=np.where(keep,shared-own,np.nan)
                reg=newey_west(contrast,np.empty((len(contrast),0))) if keep.sum()>10 else None
                row=dict(p=p,d=d,weighting=mode,four_portfolio_common_weeks=int(keep.sum()))
                for (support,method),y in cells.items():
                    row[f'{support}_{method}_mean_pct']=100*float(y[keep].mean()) if keep.any() else np.nan
                row.update(shared_minus_own_method_difference_pct=100*reg['alpha'] if reg else np.nan,
                    ci_low_hac_pct=100*reg['alpha_ci_low'] if reg else np.nan,
                    ci_high_hac_pct=100*reg['alpha_ci_high'] if reg else np.nan,
                    interpretation='same_calendar_four_portfolios_saved_forecasts_not_retraining_or_causal_effect')
                matched.append(row)
    write_csv(OUT/'controlled_coverage_same_calendar.csv',matched)
    write_csv(OUT/'controlled_coverage_weighting_by_week.csv',rows)
    write_csv(OUT/'controlled_coverage_weighting_summary.csv',summaries)
    write_csv(OUT/'raw_label_vs_economic_payoff_rank_ic.csv',prediction)
    print(f'E07_CONTROLLED_OK sorts={len(rows)} IC={len(prediction)} paired_summaries={len(summaries)}')


if __name__=='__main__':main()
