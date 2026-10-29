#!/usr/bin/env python3
"""Calendar-preserving model comparisons; no data access or model training.

Returns are decimal weekly spreads/excess returns. All moment calculations
use one complete-case mask for the competing models and divisor N. Zeros in
masked arrays below are algebraic placeholders with zero weight, not returns.
"""
from __future__ import annotations

import numpy as np
from scipy.stats import chi2, f as f_distribution, norm

METHODS = ("M0", "M2", "M1")
MODELS = {"LTW": (0, 1, 2), **{m: (0, 1, j+3) for j, m in enumerate(METHODS)}}
PAIRS = ((0, 1, "02"), (1, 2, "21"), (0, 2, "01"))
COND_LIMIT = 1e12


def block_counts(length: int, block: int, reps: int, seed: int) -> np.ndarray:
    """Draw circular blocks on the uncompressed calendar, paired across columns."""
    rng = np.random.default_rng(seed)
    starts = rng.integers(0, length, (reps, (length+block-1)//block))
    indices = ((starts[..., None]+np.arange(block)) % length).reshape(reps, -1)[:, :length]
    counts = np.zeros((reps, length), dtype=float)
    np.add.at(counts, (np.arange(reps)[:, None], indices), 1)
    return counts


def moments(data: np.ndarray, counts: np.ndarray, mask=None):
    if mask is None:
        mask = np.isfinite(data).all(axis=1)
    mask = mask & np.isfinite(data).all(axis=1)
    w = counts*mask
    n = w.sum(axis=1)
    clean = np.where(mask[:, None], data, 0.)
    mu = w@clean/n[:, None]
    k = data.shape[1]
    second = (w@np.einsum('ti,tj->tij', clean, clean).reshape(len(data), -1)).reshape(-1,k,k)
    cov = second/n[:,None,None]-mu[:,:,None]*mu[:,None,:]
    return n, mu, (cov+cov.transpose(0,2,1))/2


def solve_identified(cov: np.ndarray, rhs: np.ndarray, n: np.ndarray):
    """Never regularize a singular covariance or silently replace its output."""
    eig = np.linalg.eigvalsh(cov)
    ok = (n > cov.shape[-1]+1) & (eig[:,0]>0) & (eig[:,-1]/np.maximum(eig[:,0],1e-300)<COND_LIMIT)
    out = np.full_like(rhs, np.nan)
    if ok.any():
        if rhs.ndim == 2:
            out[ok] = np.linalg.solve(cov[ok], rhs[ok,...,None])[...,0]
        else:
            out[ok] = np.linalg.solve(cov[ok], rhs[ok])
    return out, ok


def factor_statistics(data: np.ndarray, counts: np.ndarray):
    n, mu, cov = moments(data, counts)
    s2, weights = {}, {}
    for name, cols in {**MODELS, **{f'A_{m}':(0,1,2,j+3) for j,m in enumerate(METHODS)}}.items():
        ids = list(cols)
        w, _ = solve_identified(cov[:,ids][:,:,ids], mu[:,ids], n)
        s2[name] = np.einsum('bi,bi->b',mu[:,ids],w)
        weights[name] = w
    d = np.column_stack([s2[m]-s2['LTW'] for m in METHODS])
    delta = np.column_stack([d[:,b]-d[:,a] for a,b,_ in PAIRS])
    alpha, risk, alpha_mom, risk_mom = [],[],[],[]
    for j,m in enumerate(METHODS):
        for target, controls, alphas, risks in (
            (j+3,[0,1,2],alpha,risk), (2,[0,1,j+3],alpha_mom,risk_mom)):
            beta,_=solve_identified(cov[:,controls][:,:,controls],cov[:,controls,target],n)
            a=mu[:,target]-np.einsum('bi,bi->b',mu[:,controls],beta)
            var=cov[:,target,target]-np.einsum('bi,bi->b',cov[:,target,controls],beta)
            alphas.append(a); risks.append(np.where(var>0,np.sqrt(np.maximum(var,0)),np.nan))
    return dict(n=n,s2=s2,weights=weights,d=d,delta=delta,
                alpha=np.column_stack(alpha),risk=np.column_stack(risk),
                alpha_mom=np.column_stack(alpha_mom),risk_mom=np.column_stack(risk_mom))


def hac_cov(scores: np.ndarray, lag=4):
    """Scores already include inverse-design normalization; missing dates are zero scores."""
    out=scores.T@scores
    for h in range(1,min(lag,len(scores)-1)+1):
        cross=scores[h:].T@scores[:-h]
        out+=(1-h/(lag+1))*(cross+cross.T)
    return (out+out.T)/2


def regression_hac(y, factors):
    if y.ndim == 1: y=y[:,None]
    keep=np.isfinite(y).all(1)&np.isfinite(factors).all(1)
    x=np.column_stack([np.ones(keep.sum()),factors[keep]])
    if len(x)<=x.shape[1]+1 or np.linalg.cond(x.T@x)>COND_LIMIT:
        raise ValueError('regression_unidentified')
    inv=np.linalg.inv(x.T@x)
    beta=np.linalg.lstsq(x,y[keep],rcond=None)[0]
    residual=y[keep]-x@beta
    score=np.zeros_like(y,dtype=float)
    score[keep]=residual*(x@inv[:,0])[:,None]
    return beta[0],hac_cov(score),score,residual,keep


def contrast_diagnostic(data, col_a, col_b):
    """Test the common-factor spanning boundary before regular direct inference."""
    keep=np.isfinite(data).all(1)
    f=np.where(keep[:,None],data,np.nan)
    a,cov,_,_,_=regression_hac(f[:,[col_a,col_b]],f[:,:2])
    if np.linalg.matrix_rank(cov)<2 or np.linalg.cond(cov)>COND_LIMIT:
        return dict(spanning_hac_p=np.nan,inference_status='degenerate_spanning_covariance')
    p=float(chi2.sf(a@np.linalg.solve(cov,a),2))
    return dict(spanning_hac_p=p,inference_status=('regular_conditional_on_nonspanning'
                if p<.05 else 'spanning_not_rejected_inference_unresolved'))


def influence(data, cols):
    keep=np.isfinite(data).all(1)
    x=data[keep][:,cols]; mu=x.mean(0); z=x-mu
    cov=z.T@z/len(x)
    if np.linalg.cond(cov)>COND_LIMIT: raise ValueError('covariance_unidentified')
    w=np.linalg.solve(cov,mu); theta=float(mu@w); u=z@w
    result=np.zeros(len(data)); result[keep]=(2*u-u*u+theta)/len(x)
    return result


def interval(estimate, draws, status='regular', scores=None):
    valid=np.isfinite(draws); clean=draws[valid]
    out={'estimate':float(estimate),'bootstrap_valid':int(valid.sum()),
         'bootstrap_invalid':int((~valid).sum()),'inference_status':status}
    if not np.isfinite(estimate) or not len(clean):
        return {**out,'inference_status':'unidentified_estimate','ci_low':np.nan,'ci_high':np.nan,'p_two_sided':np.nan}
    lo,hi=np.quantile(clean,[.025,.975])
    out.update(descriptive_boot_ci_low=float(lo),descriptive_boot_ci_high=float(hi))
    if valid.mean()<.99: status='too_many_invalid_bootstrap_draws'
    if scores is not None:
        se=float(np.sqrt(max(float(hac_cov(scores[:,None])[0,0]),0)))
        out['hac_se']=se
        if se<=1e-12: status='degenerate_influence'
    good=status.startswith('regular')
    out.update(inference_status=status,ci_low=float(lo) if good else np.nan,
               ci_high=float(hi) if good else np.nan,
               p_two_sided=float((1+np.count_nonzero(abs(clean-estimate)>=abs(estimate)))/(1+len(clean))) if good else np.nan)
    if scores is not None:
        out.update(hac_ci_low=estimate-1.96*se if good else np.nan,
                   hac_ci_high=estimate+1.96*se if good else np.nan,
                   hac_p=float(2*norm.sf(abs(estimate/se))) if good else np.nan)
    return out


def holm(ps):
    """Three prespecified contrasts; an unavailable test remains unavailable."""
    p=np.asarray(ps,float); out=np.full_like(p,np.nan)
    order=np.argsort(np.where(np.isfinite(p),p,np.inf))
    value=0.
    for i,j in enumerate(order):
        if np.isfinite(p[j]):
            value=max(value,(len(p)-i)*p[j]); out[j]=min(1.,value)
    return out


def pricing_statistics(factors,y,counts):
    combined=np.column_stack([factors,y])
    keep=np.isfinite(combined).all(1)
    w=counts*keep; n=w.sum(1)
    ff=np.where(keep[:,None],factors,0.); yy=np.where(keep[:,None],y,0.)
    mu=w@ff/n[:,None]; my=w@yy/n[:,None]
    cov=(w@np.einsum('ti,tj->tij',ff,ff).reshape(len(ff),-1)).reshape(-1,6,6)/n[:,None,None]-mu[:,:,None]*mu[:,None,:]
    cross=(w@np.einsum('ti,tj->tij',ff,yy).reshape(len(ff),-1)).reshape(-1,6,y.shape[1])/n[:,None,None]-mu[:,:,None]*my[:,None,:]
    alpha={}
    for name,cols in MODELS.items():
        ids=list(cols); beta,_=solve_identified(cov[:,ids][:,:,ids],cross[:,ids],n)
        alpha[name]=my-np.einsum('bi,bij->bj',mu[:,ids],beta)
    msa=np.column_stack([np.mean(alpha[m]**2,1)*1e4 for m in MODELS])
    maa=np.column_stack([np.mean(abs(alpha[m]),1)*100 for m in MODELS])
    return dict(n=n,msa=msa,maa=maa,alpha=alpha,keep=keep)


def grs(factors,y):
    keep=np.isfinite(factors).all(1)&np.isfinite(y).all(1)
    f=factors[keep]; yy=y[keep]; n,k=f.shape; assets=yy.shape[1]
    x=np.column_stack([np.ones(n),f]); beta=np.linalg.lstsq(x,yy,rcond=None)[0]
    e=yy-x@beta; cov=e.T@e/(n-k-1)
    result=dict(grs_f=np.nan,grs_p=np.nan,residual_rank=int(np.linalg.matrix_rank(e)),
                grs_status='singular_or_insufficient_residual_system')
    if n<=assets+k or result['residual_rank']<assets or np.linalg.cond(cov)>COND_LIMIT:
        return result
    z=f-f.mean(0); cf=z.T@z/n
    if np.linalg.cond(cf)>COND_LIMIT: return result
    s2=float(f.mean(0)@np.linalg.solve(cf,f.mean(0)))
    stat=n/assets*(n-assets-k)/(n-k-1)*(beta[0]@np.linalg.solve(cov,beta[0]))/(1+s2)
    return dict(grs_f=float(stat),grs_p=float(f_distribution.sf(stat,assets,n-assets-k)),
                residual_rank=result['residual_rank'],grs_status='nominal_iid_normal_F_reference')


def rolling_opportunities(factors,first_oos,minimum=5,ddof=0):
    """Common six-column training mask; every weight is estimated before t."""
    n=len(factors); returns=np.full((n,4),np.nan); audit=[]
    for t in range(first_oos,n):
        window=factors[t-52:t]; keep=np.isfinite(window).all(1); train=window[keep]
        reason='ok'; gross=[]; flips=[]
        if len(train)<minimum: reason='insufficient_complete_training'
        elif not np.isfinite(factors[t]).all(): reason='evaluation_missing'
        if reason=='ok':
            for j,(name,cols) in enumerate(MODELS.items()):
                x=train[:,cols]; mu=x.mean(0); z=x-mu; cov=z.T@z/(len(x)-ddof)
                if np.linalg.matrix_rank(cov)<3 or np.linalg.cond(cov)>COND_LIMIT:
                    reason='covariance_unidentified'; break
                direction=np.linalg.solve(cov,mu); var=float(direction@cov@direction)
                if not np.isfinite(var) or var<=0: reason='invalid_variance'; break
                weight=direction*.1/np.sqrt(var)
                assert mu@weight >= -1e-12
                assert np.isclose(weight@cov@weight,.01,rtol=1e-10)
                returns[t,j]=factors[t,list(cols)]@weight
                gross.append(float(abs(weight).sum())); flips.append(int(weight.sum()<0))
        if reason!='ok': returns[t,:]=np.nan
        audit.append(dict(index=t,train_start=t-52,train_end=t-1,n_training=len(train),status=reason,
                          gross_max=max(gross) if gross else np.nan,
                          old_normalization_flip_count=sum(flips) if reason=='ok' else 0))
    return returns,audit


def oos_statistics(returns,counts):
    n,mu,cov=moments(returns,counts)
    # Report conventional annualized sample Sharpe; N-1 for descriptive SD.
    var=np.diagonal(cov,axis1=1,axis2=2)*n[:,None]/(n[:,None]-1)
    sr=np.sqrt(52)*mu/np.sqrt(var)
    diff=sr[:,1:]-sr[:,[0]]
    mdiff=(mu[:,1:]-mu[:,[0]])*100
    return dict(n=n,mean=mu*100,sr=sr,diff=diff,mdiff=mdiff,
                delta=np.column_stack([diff[:,b]-diff[:,a] for a,b,_ in PAIRS]),
                mdelta=np.column_stack([mdiff[:,b]-mdiff[:,a] for a,b,_ in PAIRS]))
