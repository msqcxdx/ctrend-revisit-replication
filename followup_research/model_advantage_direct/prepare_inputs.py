#!/usr/bin/env python3
"""Build isolated aggregate-factor/test-portfolio inputs from completed runs.

This adapter reads local archive paths from an operator-supplied run index.
It never writes to that index, the underlying runs, or existing follow-up data.
The resulting NPZ files contain restricted derived inputs: do not publish them.
"""
from __future__ import annotations
import argparse
import csv
import hashlib
import json
from pathlib import Path
import numpy as np
from scipy.io import loadmat, whosmat

LTW_ASSETS=("mcap","prc","maxdprc","ret_1_0","ret_2_0","ret_3_0","ret_4_0","ret_4_1","prcvol","volscaled","stdprcvol")
TI_ASSETS=("rsi","stochRSI","stochK","stochD","cci")+tuple(f'sma_{n}d' for n in (3,5,10,20,50,100,200))+(
    "macd","macd_diff_signal")+tuple(f'volsma_{n}d' for n in (3,5,10,20,50,100,200))+(
    "volmacd","volmacd_diff_signal","chaikin","boll_low","boll_mid","boll_high","boll_width")
ASSETS=LTW_ASSETS+TI_ASSETS


def digest(path):
    h=hashlib.sha256()
    with path.open('rb') as f:
        for block in iter(lambda:f.read(1024*1024),b''): h.update(block)
    return h.hexdigest()


def read(path):
    with path.open(newline='') as f: return list(csv.DictReader(f))


def build(repo: Path,index: Path,out: Path):
    if out.exists(): raise ValueError('Use a fresh input directory; no archive is overwritten.')
    rows={r['experiment_id']:r for r in read(index)}
    weekly_path=repo/'results/comparisons/paper_factor/NINETEEN_WAY_WEEKLY_RETURNS.csv'
    weekly=read(weekly_path); weeks=np.array([int(r['year_week']) for r in weekly])
    assert len(weeks)==len(set(weeks)) and np.all(np.diff(weeks)>0)
    sources={}; runs=[]; settings=[]; e04_checks=[]
    def track(path,label):
        sources[label]={'label':label,'sha256':digest(path),'size_bytes':path.stat().st_size}
    track(weekly_path,'saved_eighteen_method_weekly_factors')
    old=read(repo/'followup_research/outputs/E03/nonnested_squared_sharpe_hac.csv')
    legacy=read(repo/'followup_research/outputs/E03/paired_52week_oos_weekly.csv')
    track(repo/'followup_research/outputs/E03/nonnested_squared_sharpe_hac.csv','existing_E03_hac')
    track(repo/'followup_research/outputs/E03/paired_52week_oos_weekly.csv','existing_E03_oos')
    e04_path=repo/'followup_research/outputs/E04/paired_method_differences.csv'
    e04=read(e04_path); track(e04_path,'existing_E04_paired_returns')
    out.mkdir(parents=True)
    external_reference=None
    for p in range(2):
        for d in range(3):
            arrays={'weeks':weeks}; starts=[]
            for m in (0,2,1):
                eid=f'P{p}_M{m}_D{d}'; row=rows[eid]; run=Path(row['accepted_run_root']); result=Path(row['result_root'])
                if digest(run/'RUN_COMPLETE')!=row['run_complete_sha256']:
                    raise ValueError(f'Run identity differs: {eid}')
                base=result/'CTREND/CTREND_Base.mat'
                c=loadmat(base,squeeze_me=True,struct_as_record=False,variable_names=['cResults','vDates','vModelDates'])
                assert np.array_equal(np.asarray(c['vDates']).reshape(-1),weeks)
                saved=np.array([float(r[eid]) for r in weekly]); actual=np.asarray(c['cResults'].VW.mPortRet[-1]).reshape(-1)
                if not np.allclose(saved,actual,rtol=1e-12,atol=1e-13,equal_nan=True):
                    raise ValueError(f'VW H-L export differs from base: {eid}')
                arrays[f'ct_m{m}']=saved
                if 'vModelDates' in c:
                    start=int(np.flatnonzero(weeks==np.asarray(c['vModelDates']).reshape(-1)[0])[0])
                else:
                    # M0/M2 save one mBeta row per trailing model week but no
                    # separate model-date vector. Infer their declared grid,
                    # not the outcome-dependent first finite portfolio week.
                    shapes={name:shape for name,shape,_ in whosmat(base)}
                    start=len(weeks)-shapes['mBeta'][0]
                    assert 0<=start<len(weeks)
                starts.append(start)
                track(base,f'{eid}/CTREND_Base.mat')
                runs.append({'experiment_id':eid,'research_run_id':row['research_run_id'],
                             'run_complete_sha256':row['run_complete_sha256'],'base_sha256':digest(base)})
                if m in (0,1):
                    hedge=result/'HedgePorts.mat'; h=loadmat(hedge,squeeze_me=True,struct_as_record=False)
                    if 'vDates' in h: assert np.array_equal(h['vDates'].reshape(-1),weeks)
                    names=[str(v) for v in np.asarray(h['cCharNames']).reshape(-1)]
                    arrays[f'test_m{m}']=np.asarray(h['mHedgePort'])[:,[names.index(x) for x in ASSETS]]
                    track(hedge,f'{eid}/HedgePorts.mat')
            eid=f'P{p}_M1_D{d}'
            path=repo/f'followup_research/outputs/E01/{eid}/e01_weekly_factors.csv'
            factors=read(path); track(path,f'{eid}/E01_factors')
            assert [int(float(r['week_key'])) for r in factors]==weeks.tolist()
            assert np.allclose(arrays['ct_m1'],[float(r['ctrend']) for r in factors],equal_nan=True,rtol=1e-12,atol=1e-13)
            for source in ('external','own'):
                arrays[source]=np.array([[float(r[f'{source}_{k}']) for k in ('cmkt','csize','cmom')] for r in factors])
                if source=='external':
                    if external_reference is None: external_reference=arrays[source].copy()
                    else: assert np.array_equal(external_reference,arrays[source],equal_nan=True)
                r=next(r for r in old if r['experiment_id']==eid and r['factor_source']==source)
                arrays[f'legacy_d_{source}']=np.array([float(r['n']),float(r['delta_weekly'])])
                previous={int(r['week_key']):r for r in legacy if r['experiment_id']==eid and r['factor_source']==source}
                arrays[f'legacy_oos_{source}']=np.array([[float(previous[int(w)][f'return_{k}']) if int(w) in previous else np.nan
                                                        for k in ('ltw','trend')] for w in weeks])
            # E04 asks a different question (single-factor return differences),
            # but must agree when its own pairwise support is reconstructed.
            for a,b in ((0,2),(2,1),(0,1)):
                aa,bb=arrays[f'ct_m{a}'],arrays[f'ct_m{b}']
                keep=np.isfinite(aa)&np.isfinite(bb)&np.isfinite(arrays['external']).all(1)
                expected=next(r for r in e04 if (r['P'],r['D'],r['before'],r['after'])==
                              (f'P{p}',f'D{d}',f'M{a}',f'M{b}'))
                values={'n_pair':int(keep.sum()),'mean_before_pct':100*aa[keep].mean(),
                        'mean_after_pct':100*bb[keep].mean(),
                        'mean_difference_pct':100*(bb[keep]-aa[keep]).mean(),
                        'sharpe_before':np.sqrt(52)*aa[keep].mean()/aa[keep].std(ddof=1),
                        'sharpe_after':np.sqrt(52)*bb[keep].mean()/bb[keep].std(ddof=1)}
                values['sharpe_difference']=values['sharpe_after']-values['sharpe_before']
                for key,value in values.items():
                    if not np.isclose(value,float(expected[key]),rtol=1e-10,atol=1e-12):
                        raise ValueError(f'E04 reconciliation failed: P{p} D{d} M{a}->M{b} {key}')
                e04_checks.append(dict(P=f'P{p}',D=f'D{d}',before=f'M{a}',after=f'M{b}',**values,
                                       status='matched_E04_pairwise_support_and_sample_SD'))
            arrays['first_model_indices']=np.array(starts)
            arrays['asset_names']=np.array(ASSETS)
            path=out/f'P{p}_D{d}.npz'; np.savez_compressed(path,**arrays)
            settings.append({'P':p,'D':d,'file':path.name,'sha256':digest(path)})
    manifest={'format':'ctrend-model-advantage-inputs','run_ids':runs,'source_files':list(sources.values()),
              'datasets':settings,'baseline':'saved VW H-L','return_units':'decimal_weekly',
              'external_LTW_identical_across_all_PD':True,'all_18_baselines_match_saved_csv':True,
              'E04_point_reconciliation':e04_checks,
              'redistribution':'restricted inputs; do not include NPZ in public repository'}
    (out/'INPUT_RECEIPT.json').write_text(json.dumps(manifest,ensure_ascii=False,indent=2)+'\n')
    print(f'INPUTS_READY datasets={len(settings)} baselines={len(runs)} output={out}',flush=True)


if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--repository-root',type=Path,required=True)
    parser.add_argument('--run-index',type=Path,required=True)
    parser.add_argument('--output',type=Path,required=True)
    args=parser.parse_args(); build(args.repository_root.resolve(),args.run_index.resolve(),args.output.resolve())
