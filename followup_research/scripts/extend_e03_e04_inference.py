#!/usr/bin/env python3
"""Add calendar-aware uncertainty, support sensitivity and honest risk metrics.

E03 adds the nonnested squared-Sharpe influence-function comparison (the
regular, distinct-model case) and economic equivalence curves. E04 compares
three fixed supports and block lengths, retaining holes in calendar time.
Statistical H-L below -100% is not an investable wealth path: drawdown is
undefined there, not computed from a negative fictitious NAV.
"""
from concurrent.futures import ProcessPoolExecutor
import csv
from pathlib import Path
import numpy as np
from scipy.stats import norm
from paired_stats import annual_sharpe, block_indices, newey_west

ROOT=Path(__file__).resolve().parents[1]; REPO=ROOT.parent


def read(path):
    with path.open(newline='',encoding='utf-8') as f: return list(csv.DictReader(f))


def write(path,rows):
    with path.open('w',newline='',encoding='utf-8') as f:
        w=csv.DictWriter(f,fieldnames=list(dict.fromkeys(k for r in rows for k in r)))
        w.writeheader();w.writerows(rows)


def sharpe_influence(x):
    """MLE squared-Sharpe influence function; uses one common complete sample."""
    mu=x.mean(0); z=x-mu; cov=z.T@z/len(x)
    if np.linalg.cond(cov)>1e12: raise ValueError('Unidentified covariance')
    direction=np.linalg.solve(cov,mu); theta=float(mu@direction)
    score=z@direction
    return theta,2*score-score**2+theta


def e03():
    out=[]; equivalence=[]
    for p in (0,1):
        for d in (0,1,2):
            eid=f'P{p}_M1_D{d}'
            rows=read(ROOT/'outputs/E01'/eid/'e01_weekly_factors.csv')
            for source in ('external','own'):
                f=np.array([[float(r[f'{source}_{n}']) for n in ('cmkt','csize','cmom')]+
                            [float(r['ctrend'])] for r in rows])
                keep=np.isfinite(f).all(1); n=int(keep.sum()); ff=f[keep]
                lt,il=sharpe_influence(ff[:,:3]); tr,it=sharpe_influence(ff[:,[0,1,3]])
                score=np.where(keep,0.,np.nan); score[keep]=it-il
                # The estimating-function mean is zero; its HAC mean SE is
                # the delta's SE. Missing calendar weeks remain missing.
                reg=newey_west(score,np.empty((len(f),0)))
                se=reg['alpha_se_hac']; delta=tr-lt
                identified=se>1e-12
                out.append(dict(experiment_id=eid,factor_source=source,n=n,
                    max_s2_ltw_mle_weekly=lt,max_s2_trend_mle_weekly=tr,
                    delta_weekly=delta,hac_se=se,
                    ci_low=delta-1.96*se,ci_high=delta+1.96*se,
                    regular_nonnested_p=float(2*norm.sf(abs(delta/se))) if identified else np.nan,
                    status='regular_distinct_model_inference' if identified else 'degenerate_no_normal_test',
                    scope='not_nested_test_not_test_of_all_model_pricing_errors'))
                for target,controls in ((3,[0,1,2]),(2,[0,1,3])):
                    reg=newey_west(np.where(keep,f[:,target],np.nan),f[:,controls])
                    a=reg['alpha']; s=reg['alpha_se_hac']
                    for threshold in (.001,.0025,.005,.01):
                        equivalence.append(dict(experiment_id=eid,factor_source=source,
                            increment='CTREND_given_LTW' if target==3 else 'CMOM_given_TREND',
                            equivalence_margin_weekly_pct=100*threshold,alpha_weekly_pct=100*a,
                            ci90_low_pct=100*(a-norm.ppf(.95)*s),ci90_high_pct=100*(a+norm.ppf(.95)*s),
                            equivalent_at_5pct_TOST=int(a-norm.ppf(.95)*s>-threshold and a+norm.ppf(.95)*s<threshold),
                            interpretation='all_thresholds_disclosed_not_a_result_selected_redundancy_claim'))
    write(ROOT/'outputs/E03/nonnested_squared_sharpe_hac.csv',out)
    write(ROOT/'outputs/E03/economic_equivalence_threshold_curve.csv',equivalence)


def risk(y):
    v=y[np.isfinite(y)]; q=np.quantile(v,.05)
    # Only contiguous, observed returns and strictly positive gross returns
    # define a NAV. Do not close missing weeks with fabricated zero returns.
    active=np.flatnonzero(np.isfinite(y)); contiguous=(len(active)>0 and len(active)==active[-1]-active[0]+1)
    if contiguous and np.all(v>-1):
        lognav=np.r_[0.,np.cumsum(np.log1p(v))]
        drawdown=float(np.max(-np.expm1(lognav-np.maximum.accumulate(lognav))))
        nav_status='identified_statistical_unconstrained_path'
    else:
        drawdown=np.nan;nav_status='undefined_negative_gross_or_unobserved_weeks'
    return dict(n=len(v),mean_pct=100*v.mean(),sd_pct=100*v.std(ddof=1),
        downside_deviation_pct=100*np.sqrt(np.mean(np.minimum(v,0)**2)),
        p01_pct=100*np.quantile(v,.01),p05_pct=100*q,expected_shortfall05_pct=100*v[v<=q].mean(),
        p95_pct=100*np.quantile(v,.95),p99_pct=100*np.quantile(v,.99),
        worst_week_pct=100*v.min(),best_week_pct=100*v.max(),
        subminus100=int((v<=-1).sum()),drawdown=drawdown,drawdown_status=nav_status)


def one_e04(task):
    p,d,before,after=task
    weekly=read(REPO/'results/comparisons/paper_factor/NINETEEN_WAY_WEEKLY_RETURNS.csv')
    factor_rows=read(ROOT/'outputs/E01'/f'P{p}_M1_D{d}'/'e01_weekly_factors.csv')
    if [int(r['year_week']) for r in weekly]!=[int(float(r['week_key'])) for r in factor_rows]:
        raise ValueError('Calendar mismatch')
    a=np.array([float(r[f'P{p}_M{before}_D{d}']) for r in weekly])
    b=np.array([float(r[f'P{p}_M{after}_D{d}']) for r in weekly])
    factors=np.array([[float(r[f'external_{s}']) for s in ('cmkt','csize','cmom')] for r in factor_rows])
    # Include the published author factor, not merely the 18 own experiments.
    names=[k for k in weekly[0] if k.startswith('P') and '_M' in k]
    all19=np.isfinite(np.array([[float(r[k]) for k in names+['Paper']] for r in weekly])).all(1)
    pair=np.isfinite(a)&np.isfinite(b)
    supports={'pair_returns':pair,'pair_with_external_LTW':pair&np.isfinite(factors).all(1),
              'all19_with_external_LTW':all19&np.isfinite(factors).all(1)}
    rows=[];risks=[];masks=[]
    for support,keep in supports.items():
        aa=np.where(keep,a,np.nan);bb=np.where(keep,b,np.nan)
        da=bb-aa; point=annual_sharpe(bb)-annual_sharpe(aa)
        for method,y in ((before,aa),(after,bb)):
            risks.append(dict(P=p,D=d,before=before,after=after,method=method,support=support,**risk(y)))
        for i,r in enumerate(weekly):
            masks.append(dict(P=p,D=d,before=before,after=after,support=support,week=int(r['year_week']),
                included=int(keep[i]),before_finite=int(np.isfinite(a[i])),after_finite=int(np.isfinite(b[i])),
                external_factors_finite=int(np.isfinite(factors[i]).all())))
        for block in (4,8,13):
            rng=np.random.default_rng(20261026+1000*p+100*d+10*before+after+block)
            sr=[];means=[];alphas=[]
            for _ in range(1000):
                ix=block_indices(len(a),block,rng)
                sr.append(annual_sharpe(bb[ix])-annual_sharpe(aa[ix]));means.append(np.nanmean(da[ix]))
                alphas.append(newey_west(da[ix],factors[ix])['alpha'])
            alpha=newey_west(da,factors)
            row=dict(P=p,D=d,before=before,after=after,support=support,n=int(keep.sum()),
                     alpha_n=alpha['n'],block_weeks=block,reps=1000)
            for name,estimate,draw in (('sharpe',point,sr),('mean_week_pct',100*np.nanmean(da),100*np.asarray(means)),
                                        ('alpha_week_pct',100*alpha['alpha'],100*np.asarray(alphas))):
                lo,hi=np.quantile(draw,[.025,.975]);center=np.asarray(draw)-estimate
                row.update({name:estimate,f'{name}_ci_low':float(lo),f'{name}_ci_high':float(hi),
                            f'{name}_centered_p':(1+np.count_nonzero(abs(center)>=abs(estimate)))/1001})
            rows.append(row)
    return rows,risks,masks


def main():
    e03()
    tasks=[(p,d,a,b) for p in (0,1) for d in (0,1,2) for a,b in ((0,2),(2,1),(0,1))]
    with ProcessPoolExecutor(max_workers=12) as pool: result=list(pool.map(one_e04,tasks))
    for j,file in enumerate(('support_block_sensitivity.csv','paired_risk_distribution.csv','support_calendar_audit.csv')):
        write(ROOT/'outputs/E04'/file,[r for group in result for r in group[j]])
    print('E03_E04_EXTENDED_INFERENCE_OK paths=18 supports=3 blocks=4,8,13',flush=True)


if __name__=='__main__': main()
