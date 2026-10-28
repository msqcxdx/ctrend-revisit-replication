#!/usr/bin/env python3
"""Summarize authenticated A/B and dependent C+D baseline re-estimations.

Own weeks, AB-common weeks, and whole-path-common weeks are kept separate.
Effects are paired weekly returns, not differences of unrelated Sharpe medians.
A also changes synchronized cap/support wherever a price hole used to erase
them; it is a history-layer intervention, not an isolated X-value intervention.
The full M1 endpoint is an external reference, not labeled equal to ABCD.
"""
import argparse
import csv
import json
from pathlib import Path
import re
import numpy as np
from scipy.io import loadmat
from analyze_e03_e04 import write_table
from paired_stats import annual_sharpe,newey_west,max_squared_sharpe
from run_e06_upstream_hybrids import ROOT,REPO,sha


def main():
    ap=argparse.ArgumentParser();ap.add_argument('--ab-root',required=True);ap.add_argument('--cd-root',required=True)
    ap.add_argument('--experiment',default='P0_M2_D1')
    ap.add_argument('--out-dir')
    args=ap.parse_args();ab=Path(args.ab_root);cd=Path(args.cd_root)
    if re.fullmatch(r'P[01]_M2_D[012]',args.experiment) is None:
        raise ValueError('Unsupported E06 sensitivity parent')
    out=Path(args.out_dir) if args.out_dir else ROOT/'outputs/E06'
    if args.experiment!='P0_M2_D1' and out.resolve()==(ROOT/'outputs/E06').resolve():
        raise ValueError('Noncanonical sensitivity requires its own --out-dir')
    out.mkdir(parents=True,exist_ok=True)
    paths={};source_receipts=[]
    for root,variants in ((ab,('control','A','B','AB')),(cd,('CD','ABCD'))):
        manifest=json.loads((root/'manifest.json').read_text())
        if not manifest['status'].endswith(('not_yet_run','not_full_M1')):raise ValueError('hybrid incomplete')
        if manifest.get('experiment_id',manifest.get('parent',{}).get('experiment_id'))!=args.experiment:
            raise ValueError('Hybrid parent experiment mismatch')
        source_receipts.append(dict(path=str(root/'manifest.json'),sha256=sha(root/'manifest.json'),
                                    research_run_id=manifest['research_run_id']))
        for name in variants:
            done=json.loads((root/name/'COMPLETED.json').read_text());path=Path(done['result'])
            if sha(path)!=done['sha256']:raise ValueError('hybrid result digest')
            paths[name]=path
    p1=args.experiment.replace('_M2_','_M1_')
    paths['accepted_M1']=REPO/'results/experiments'/p1/'CTREND/CTREND_Base.mat'
    data={k:loadmat(v,squeeze_me=True,struct_as_record=False,
                   variable_names=['vDates','vAssetID','mYhat','mBeta','mSelected','cResults']) for k,v in paths.items()}
    weeks=np.asarray(data['control']['vDates'],int).ravel();ids=data['control']['vAssetID']
    factors=list(csv.DictReader((ROOT/'outputs/E01'/p1/'e01_weekly_factors.csv').open()))
    assert list(weeks)==[int(float(r['week_key'])) for r in factors]
    f=np.array([[float(r['external_'+n]) for n in ('cmkt','csize','cmom')] for r in factors])
    ret={};weekly=[];summary=[];effects=[]
    for name,z in data.items():
        assert np.array_equal(weeks,np.asarray(z['vDates'],int).ravel()) and np.array_equal(ids,z['vAssetID'])
        ret[name]=np.asarray(z['cResults'].VW.mPortRet)[-1]
        for t,w in enumerate(weeks):
            weights=np.asarray(z['cResults'].VW.mWts)[:,t]
            weekly.append(dict(variant=name,year_week=int(w),hl_return=float(ret[name][t]),
                finite_forecasts=int(np.isfinite(z['mYhat'][:,t]).sum()),
                low_max_weight=float(np.nanmax(weights[:,0])) if np.isfinite(weights[:,0]).any() else np.nan,
                high_max_weight=float(np.nanmax(weights[:,-1])) if np.isfinite(weights[:,-1]).any() else np.nan))
    shared={
        'AB_common':np.isfinite(np.column_stack([ret[k] for k in ('control','A','B','AB')])).all(1),
        'whole_path_common':np.isfinite(np.column_stack(list(ret.values()))).all(1)}
    for name,y in ret.items():
        for support,mask in [('own',np.isfinite(y))]+list(shared.items()):
            keep=mask&np.isfinite(y)&np.isfinite(f).all(1);yy=np.where(keep,y,np.nan)
            reg=newey_west(yy,f)
            z=np.column_stack((f[keep],y[keep]))
            opportunities={label:max_squared_sharpe(z[:,cols]) for label,cols in
                {'base':(0,1),'ltw':(0,1,2),'trend':(0,1,3),'full':(0,1,2,3)}.items()}
            summary.append(dict(variant=name,support=support,weeks=int(keep.sum()),
                mean_pct=100*float(np.nanmean(yy)),annual_sharpe=annual_sharpe(yy),
                ltw_alpha_pct=100*reg['alpha'],alpha_ci_low_pct=100*reg['alpha_ci_low'],
                alpha_ci_high_pct=100*reg['alpha_ci_high'],
                forecast_cells=int(np.isfinite(data[name]['mYhat']).sum()),
                worst_week_pct=100*float(np.nanmin(yy)),best_week_pct=100*float(np.nanmax(yy)),
                **{f'max_s2_{k}_weekly':v for k,v in opportunities.items()},
                opportunity_scope='descriptive_same_support_excess_factor_opportunity_not_account'))
    definitions={
        'A_given_original_history':{'A':1,'control':-1},
        'B_given_original_history':{'B':1,'control':-1},
        'AB_interaction':{'AB':1,'A':-1,'B':-1,'control':1},
        'CD_given_original_history':{'CD':1,'control':-1},
        'CD_given_AB_history':{'ABCD':1,'AB':-1},
        'AB_CD_interaction':{'ABCD':1,'AB':-1,'CD':-1,'control':1},
        'ABCD_total':{'ABCD':1,'control':-1},
        'remaining_to_full_M1_not_a_single_module':{'accepted_M1':1,'ABCD':-1},
        'full_M1_total':{'accepted_M1':1,'control':-1}}
    for name,coef in definitions.items():
        for support in ('relevant_common','whole_path_common'):
            keep=np.isfinite(f).all(1)
            for k in coef:keep &= np.isfinite(ret[k])
            if support=='whole_path_common':keep &= shared['whole_path_common']
            y=np.where(keep,sum(v*ret[k] for k,v in coef.items()),np.nan)
            reg=newey_west(y,f);mean=newey_west(y,np.empty((len(y),0)))
            effects.append(dict(effect=name,support=support,paired_weeks=int(keep.sum()),
                mean_difference_pct=100*mean['alpha'],mean_ci_low_pct=100*mean['alpha_ci_low'],
                mean_ci_high_pct=100*mean['alpha_ci_high'],ltw_alpha_difference_pct=100*reg['alpha'],
                alpha_ci_low_pct=100*reg['alpha_ci_low'],alpha_ci_high_pct=100*reg['alpha_ci_high'],
                scope=f'baseline_{args.experiment}_not_3072_design_grid'))
    # Path additivity is checked on the SAME common calendar.
    path=shared['whole_path_common']
    np.testing.assert_allclose((ret['AB']-ret['control']+ret['ABCD']-ret['AB']+
        ret['accepted_M1']-ret['ABCD'])[path],(ret['accepted_M1']-ret['control'])[path],atol=1e-12)
    write_table(out/'hybrid_baseline_weekly.csv',weekly)
    write_table(out/'hybrid_baseline_summary.csv',summary)
    write_table(out/'hybrid_paired_effects.csv',effects)
    (out/'HYBRID_RECEIPT.json').write_text(json.dumps(dict(scope=f'{args.experiment}_baseline_only',
        experiment_id=args.experiment,
        runs=source_receipts,results={k:dict(path=str(v),sha256=sha(v)) for k,v in paths.items()},
        limitations=['C_and_D_dependency_block','no_validation_holdout_in_baseline',
                     'A_changes_price_hole_synchronization_including_formation_cap_support',
                     'ABCD_retains_M2_labels_and_portfolio_not_full_M1']),indent=2)+'\n')
    print(f'E06_HYBRID_SUMMARY_OK variants={len(paths)} effects={len(effects)}')


if __name__=='__main__':main()
