#!/usr/bin/env python3
"""Run paired opportunity, fixed-test-asset and rolling analyses from saved inputs.

Only the fresh output directory is writable. Large arrays and original MATLAB
results are never edited. Parallelism is over twelve P/D/benchmark settings;
each process uses single-threaded BLAS and the same deterministic resamples for
all models, pricing measures and OOS comparisons within that setting.
"""
from __future__ import annotations
import os
for key in ('OPENBLAS_NUM_THREADS','OMP_NUM_THREADS','MKL_NUM_THREADS'):
    os.environ[key]='1'
import argparse
from concurrent.futures import ProcessPoolExecutor
import csv
from datetime import datetime,timezone
import hashlib
import json
from pathlib import Path
import platform
import numpy as np
import scipy
from core import (METHODS,MODELS,PAIRS,block_counts,factor_statistics,interval,influence,
                  contrast_diagnostic,holm,pricing_statistics,regression_hac,grs,
                  rolling_opportunities,oos_statistics)


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def write(path,rows):
    fields=list(dict.fromkeys(k for row in rows for k in row))
    with path.open('w',newline='') as f:
        w=csv.DictWriter(f,fieldnames=fields); w.writeheader();w.writerows(rows)


def unique_assets(y,names):
    kept=[]; audit=[]
    for j,name in enumerate(names):
        prior=next((k for k in kept if np.array_equal(y[:,j],y[:,k],equal_nan=True)),None)
        if prior is None: kept.append(j)
        audit.append(dict(asset=str(name),retained=int(prior is None),alias_of='' if prior is None else str(names[prior])))
    return y[:,kept],audit


def setting(task):
    path,p,d,source,reps,seed=task
    data=np.load(path,allow_pickle=False); weeks=data['weeks']; n=len(weeks)
    f=np.column_stack([data[source],*[data[f'ct_m{m}'] for m in (0,2,1)]])
    common=np.isfinite(f).all(1); ones=np.ones((1,n)); point=factor_statistics(f,ones)
    metadata=dict(P=f'P{p}',D=f'D{d}',factor_source=source,n_common=int(common.sum()),
                  first_week=int(weeks[common][0]),last_week=int(weeks[common][-1]))
    out={name:[] for name in ('advantage_levels','advantage_changes','incremental_decomposition',
                              'pricing_fixed_assets','pricing_changes','pricing_asset_audit','pricing_support_calendar',
                              'oos_comparison','oos_changes','oos_training_audit','support_calendar',
                              'legacy_reconciliation','numerical_diagnostics')}
    for i,w in enumerate(weeks):
        out['support_calendar'].append(dict(P=f'P{p}',D=f'D{d}',factor_source=source,week=int(w),
            included_main=int(common[i]),**{f'finite_{name}':int(np.isfinite(f[i,j])) for j,name in enumerate(
                ('cmkt','csmb','cmom','ctrend_m0','ctrend_m2','ctrend_m1'))}))
    # Shared L cancels exactly in each method contrast.
    assert np.allclose(point['delta'][0,2],point['delta'][0,0]+point['delta'][0,1],atol=1e-12)
    level_diag=[contrast_diagnostic(f,2,j+3) for j in range(3)]
    change_diag=[contrast_diagnostic(f,a+3,b+3) for a,b,_ in PAIRS]
    inf={name:influence(f,list(cols)) for name,cols in MODELS.items()}
    panels=[]
    for panel_m in (1,0):
        y,audit=unique_assets(data[f'test_m{panel_m}'],data['asset_names'])
        for a in audit: out['pricing_asset_audit'].append(dict(P=f'P{p}',D=f'D{d}',factor_source=source,panel=f'M{panel_m}',**a))
        q=pricing_statistics(f,y,ones); residual_info={}; scores={}
        for i,w in enumerate(weeks):
            out['pricing_support_calendar'].append(dict(P=f'P{p}',D=f'D{d}',factor_source=source,
                panel=f'M{panel_m}',week=int(w),included_pricing=int(q['keep'][i]),
                included_factors=int(common[i]),all_test_assets_finite=int(np.isfinite(y[i]).all())))
        for name,cols in MODELS.items():
            restricted=np.where(q['keep'][:,None],f,np.nan)
            aa,_,sc,_,_=regression_hac(y,restricted[:,list(cols)])
            scores[name]=sc@(2*aa/y.shape[1])*1e4
            residual_info[name]=grs(restricted[:,list(cols)],y)
        panels.append((panel_m,y,q,scores,residual_info))
    oos=[]; first_oos=int(data['first_model_indices'].max())+52
    for minimum in (5,26):
        r,audit=rolling_opportunities(f,first_oos,minimum)
        q=oos_statistics(r,ones); oos.append((minimum,r,q))
        for a in audit:
            out['oos_training_audit'].append(dict(P=f'P{p}',D=f'D{d}',factor_source=source,
                minimum_training=minimum,week=int(weeks[a['index']]),
                train_start_week=int(weeks[a['train_start']]),train_end_week=int(weeks[a['train_end']]),
                **{k:v for k,v in a.items() if k not in ('index','train_start','train_end')}))
    # Replicate the prior E03 definitions separately; never splice old cells
    # into the six-column common-support results.
    legacy_f=np.column_stack([data[source],data['ct_m1'],data['ct_m1'],data['ct_m1']])
    lp=factor_statistics(legacy_f,ones)
    expected=data[f'legacy_d_{source}']; observed=lp['d'][0,2]
    if not np.isclose(observed,expected[1],rtol=1e-10,atol=1e-12): raise ValueError('E03 point reconciliation failed')
    lr,_=rolling_opportunities(legacy_f,int(data['first_model_indices'][2])+52,5,ddof=1)
    old=data[f'legacy_oos_{source}']
    if not np.allclose(lr[:,[0,3]],old,rtol=1e-9,atol=1e-11,equal_nan=True):
        raise ValueError('E03 rolling reconciliation failed')
    out['legacy_reconciliation'].append(dict(**metadata,existing_E03_n=int(expected[0]),
        recomputed_E03_d=observed,saved_E03_d=float(expected[1]),
        E03_Nminus1_equivalent=observed*(int(expected[0])-1)/int(expected[0]),
        new_common_d_m1=float(point['d'][0,2]),existing_OOS_max_abs_difference=float(np.nanmax(abs(lr[:,[0,3]]-old))),
        status='matched_existing_definitions',new_oos_difference_reason='six_column_training_support_and_N_covariance'))
    for block in (8,4,12):
        bseed=seed+10000*p+1000*d+100*(source=='own')+block
        counts=block_counts(n,block,reps,bseed); boot=factor_statistics(f,counts)
        meta={**metadata,'block_weeks':block,'bootstrap_reps':reps,'seed':bseed}
        change_rows=[]
        for j,m in enumerate(METHODS):
            diag=level_diag[j]; score=inf[m]-inf['LTW']
            estimate=point['d'][0,j]
            inference=interval(estimate,boot['d'][:,j],diag['inference_status'],score)
            out['advantage_levels'].append({**meta,'method':m,'s2_ltw':point['s2']['LTW'][0],
                's2_trend':point['s2'][m][0],
                's2_ltw_descriptive_ci_low':np.nanquantile(boot['s2']['LTW'],.025),
                's2_ltw_descriptive_ci_high':np.nanquantile(boot['s2']['LTW'],.975),
                's2_trend_descriptive_ci_low':np.nanquantile(boot['s2'][m],.025),
                's2_trend_descriptive_ci_high':np.nanquantile(boot['s2'][m],.975),**diag,**inference})
            vct=point['s2'][f'A_{m}'][0]-point['s2']['LTW'][0]
            vmom=point['s2'][f'A_{m}'][0]-point['s2'][m][0]
            av=point['alpha'][0,j]; rv=point['risk'][0,j]
            am=point['alpha_mom'][0,j]; rm=point['risk_mom'][0,j]
            assert np.isclose(vct,av**2/rv**2,atol=1e-11,rtol=1e-9)
            assert np.isclose(vmom,am**2/rm**2,atol=1e-11,rtol=1e-9)
            assert np.isclose(estimate,vct-vmom,atol=1e-12)
            inc=dict(**meta,method=m,v_ct=vct,v_mom=vmom,d_identity_error=estimate-(vct-vmom),
                     alpha_ct_weekly_pct=100*av,residual_ct_sd_weekly_pct=100*rv,
                     alpha_mom_weekly_pct=100*am,residual_mom_sd_weekly_pct=100*rm)
            for label,values in [('v_ct',boot['s2'][f'A_{m}']-boot['s2']['LTW']),
                                 ('v_mom',boot['s2'][f'A_{m}']-boot['s2'][m])]:
                inc[f'{label}_descriptive_ci_low'],inc[f'{label}_descriptive_ci_high']=np.nanquantile(values,[.025,.975])
            ar=interval(100*av,100*boot['alpha'][:,j]); inc.update({f'alpha_ct_{k}':v for k,v in ar.items() if k!='estimate'})
            out['incremental_decomposition'].append(inc)
        for j,(a,b,label) in enumerate(PAIRS):
            diag=change_diag[j]; m0,m1=METHODS[a],METHODS[b]
            change_rows.append({**meta,'contrast':label,'before':m0,'after':m1,**diag,
                **interval(point['delta'][0,j],boot['delta'][:,j],diag['inference_status'],inf[m1]-inf[m0])})
        for row,pv in zip(change_rows,holm([r['p_two_sided'] for r in change_rows])): row['p_holm_three_contrasts']=pv
        out['advantage_changes'].extend(change_rows)
        # All test portfolios and all four models share one support per panel.
        for panel_m,y,q,scores,grs_info in panels:
            bp=pricing_statistics(f,y,counts)
            pm={**meta,'panel_source':f'M{panel_m}','panel_role':'primary' if panel_m==1 else 'sensitivity',
                'n_pricing':int(q['n'][0]),'n_assets':y.shape[1]}
            for j,name in enumerate(MODELS):
                out['pricing_fixed_assets'].append(dict(**pm,model=name,mean_squared_alpha_pct2=q['msa'][0,j],
                    mean_absolute_alpha_pct=q['maa'][0,j],**grs_info[name]))
            for measure in ('msa','maa'):
                before=q[measure][0,1:]-q[measure][0,0]; draw=bp[measure][:,1:]-bp[measure][:,[0]]
                for j,m in enumerate(METHODS):
                    status='regular' if measure=='msa' else 'regular_exploratory_nonsmooth_MAE'
                    sc=scores[m]-scores['LTW'] if measure=='msa' else None
                    out['pricing_changes'].append(dict(**pm,metric=measure,comparison=f'{m}_minus_LTW',
                        direction='negative_favors_TREND',**interval(before[j],draw[:,j],status,sc)))
                for a,b,label in PAIRS:
                    status='regular' if measure=='msa' else 'regular_exploratory_nonsmooth_MAE'
                    sc=scores[METHODS[b]]-scores[METHODS[a]] if measure=='msa' else None
                    out['pricing_changes'].append(dict(**pm,metric=measure,comparison=f'delta_{label}',
                        direction='negative_means_relative_pricing_improves',
                        **interval(before[b]-before[a],draw[:,b]-draw[:,a],status,sc)))
        for minimum,r,q in oos:
            bq=oos_statistics(r,counts)
            om={**meta,'minimum_training':minimum,'n_oos':int(q['n'][0]),'target_weekly_vol':.1,
                'inference_scope':'conditional_saved_rolling_strategy_not_retrained_bootstrap'}
            for j,name in enumerate(MODELS):
                out['oos_comparison'].append(dict(**om,model=name,mean_weekly_pct=q['mean'][0,j],annualized_sharpe=q['sr'][0,j]))
            for metric,change in (('diff','delta'),('mdiff','mdelta')):
                for j,m in enumerate(METHODS):
                    out['oos_changes'].append(dict(**om,metric='sharpe' if metric=='diff' else 'mean_weekly_pct',
                        comparison=f'{m}_minus_LTW',**interval(q[metric][0,j],bq[metric][:,j])))
                for j,(_,_,label) in enumerate(PAIRS):
                    out['oos_changes'].append(dict(**om,metric='sharpe' if metric=='diff' else 'mean_weekly_pct',
                        comparison=f'delta_{label}',**interval(q[change][0,j],bq[change][:,j])))
        reconstructed=np.array([point['alpha'][0,j]**2/point['risk'][0,j]**2
                                -point['alpha_mom'][0,j]**2/point['risk_mom'][0,j]**2 for j in range(3)])
        out['numerical_diagnostics'].append(dict(
            **meta,invalid_factor_draws=int((~np.isfinite(boot['delta']).all(1)).sum()),
            covariance_divisor='N',zero_fill_returns=0,regularization=0,
            maximum_decomposition_identity_error=float(np.max(abs(point['d'][0]-reconstructed)))))
    print(f'SETTING_COMPLETE P{p} D{d} {source} common={common.sum()} reps={reps}',flush=True)
    return out


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--input-dir',type=Path,required=True);parser.add_argument('--output-dir',type=Path,required=True)
    parser.add_argument('--replicates',type=int,default=5000);parser.add_argument('--seed',type=int,default=20261029)
    parser.add_argument('--workers',type=int,default=12)
    args=parser.parse_args()
    if args.replicates<5000: raise ValueError('At least 5000 replicates are required for the research run.')
    if args.output_dir.exists(): raise ValueError('Output directory must be new.')
    receipt=json.loads((args.input_dir/'INPUT_RECEIPT.json').read_text())
    for ds in receipt['datasets']:
        if sha(args.input_dir/ds['file'])!=ds['sha256']: raise ValueError('Isolated input differs.')
    before={r['file']:sha(args.input_dir/r['file']) for r in receipt['datasets']}
    script_root=Path(__file__).resolve().parent
    scripts={p.name:sha(p) for p in script_root.glob('*.py')}
    jobs=[(args.input_dir/r['file'],r['P'],r['D'],s,args.replicates,args.seed) for r in receipt['datasets'] for s in ('external','own')]
    collected={}
    with ProcessPoolExecutor(max_workers=min(args.workers,len(jobs))) as pool:
        for output in pool.map(setting,jobs):
            for name,rows in output.items(): collected.setdefault(name,[]).extend(rows)
    collected['e04_reconciliation']=receipt['E04_point_reconciliation']
    args.output_dir.mkdir(parents=True)
    for name,rows in collected.items(): write(args.output_dir/f'{name}.csv',rows)
    after={r['file']:sha(args.input_dir/r['file']) for r in receipt['datasets']}
    assert before==after
    record=dict(format='ctrend-model-advantage-direct',completed_utc=datetime.now(timezone.utc).isoformat(),
        run_id='model_advantage_direct_'+datetime.now(timezone.utc).strftime('%Y%m%dT%H%M%SZ'),
        python=platform.python_version(),numpy=np.__version__,scipy=scipy.__version__,
        replicates=args.replicates,seed=args.seed,blocks=[8,4,12],settings=len(jobs),
        source_scripts_sha256=scripts,protocol_sha256=sha(script_root/'PROTOCOL_CN.md'),
        source_inputs=receipt,isolated_inputs_before=before,isolated_inputs_after=after,
        model_training_performed=False,existing_results_overwritten=False,
        result_files={p.name:sha(p) for p in args.output_dir.glob('*.csv')},
        inference='paired calendar blocks; unresolved spanning is not interpreted as equality')
    (args.output_dir/'RUN_RECEIPT.json').write_text(json.dumps(record,indent=2,ensure_ascii=False)+'\n')
    print(f'ANALYSIS_COMPLETE settings={len(jobs)} output={args.output_dir}',flush=True)


if __name__=='__main__': main()
