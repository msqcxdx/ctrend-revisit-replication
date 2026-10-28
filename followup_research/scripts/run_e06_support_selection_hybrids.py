#!/usr/bin/env python3
"""Run dependency-explicit C+D model-stage hybrids, retaining M2 labels/P&L.

C (own-predictor ranks/support) and D (identified component fits, normalized
selection weights and a fixed selected set) are moved as one documented
block. Mixing M2's all-X filter with C would silently close C again. These
are CD on M2 inputs and CD on AB inputs; neither is called full M1. Baseline
has no validation holdout, so a 12-week validation correction is not activated.
Accepted sources/results are read-only. Inputs and derived code are hashed.
CD and ABCD have separate source, preference and job directories and run
concurrently within the observed CPU affinity budget.
"""
import argparse
from concurrent.futures import ThreadPoolExecutor
import csv
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import time
import uuid
from run_e06_upstream_hybrids import sha, exact_replace, quote, ROOT, REPO


def run_variant(args,variant,vroot,code,inputs,inventory,workers):
    """Refit a model-only hybrid in its own MATLAB client and job store."""
    expr=(f"cd('{quote(code)}'); addpath('Utils'); set(0,'DefaultFigureVisible','off'); "
          f"c=parcluster('local'); c.JobStorageLocation='{quote(vroot/'jobs')}'; "
          f"c.NumWorkers={workers};parpool(c,{workers}); "
          "run('b05CreateCTREND.m');delete(gcp('nocreate'));fprintf('E06_CD_VARIANT_OK\\n');")
    env={**os.environ,'MATLAB_PREFDIR':str(vroot/'prefs'),'OMP_NUM_THREADS':'1',
         'OPENBLAS_NUM_THREADS':'1','MKL_NUM_THREADS':'1'}
    print(f'E06_CD_START {variant} workers={workers}',flush=True);start=time.time()
    with (vroot/'pipeline.log').open('w') as f:
        rc=subprocess.run([args.matlab,'-licmode','onlinelicensing','-nodisplay','-nosplash','-batch',expr],
            stdout=f,stderr=subprocess.STDOUT,env=env,cwd=code).returncode
    if rc:raise RuntimeError(f'{variant} failed rc={rc}; preserved {vroot}')
    if inputs!={str(p.relative_to(code)):sha(p) for p in (code/'DATA').glob('*.mat')}:
        raise ValueError(f'Hybrid modified its input data: {variant}')
    if inventory!={str(p.relative_to(code)):sha(p) for p in code.rglob('*.m')}:
        raise ValueError(f'Hybrid source changed during execution: {variant}')
    output=code/'Results/CTREND/CTREND_Base.mat'
    (vroot/'COMPLETED.json').write_text(json.dumps(dict(variant=variant,result=str(output),
        workers=workers,sha256=sha(output),seconds=time.time()-start),indent=2)+'\n')
    print(f'E06_CD_DONE {variant}',flush=True)


def dependencies(names):
    """Only copy the model helper dependency closure, never the portfolio engine."""
    folder=REPO/'engines/M1/base/Utils'; seen=set(); todo=list(names)
    while todo:
        name=todo.pop()
        if name in seen:continue
        path=folder/(name+'.m')
        if not path.is_file():raise ValueError(f'Missing model dependency {name}')
        seen.add(name)
        todo.extend(n for n in set(re.findall(r'\b(f\w+)\s*\(',path.read_text()))
                    if n not in seen and (folder/(n+'.m')).is_file())
    if any('Sort' in n or 'Ledger' in n or 'Reinvest' in n or 'Pnl' in n for n in seen):
        raise ValueError('Unexpected economic-accounting dependency in model-only closure')
    return sorted(seen)


def main():
    ap=argparse.ArgumentParser();ap.add_argument('--ab-root',required=True)
    ap.add_argument('--work-root',required=True);ap.add_argument('--matlab',required=True)
    ap.add_argument('--workers',type=int,default=96);args=ap.parse_args()
    ab=Path(args.ab_root).resolve();work=Path(args.work_root).resolve()
    if work.exists():raise FileExistsError(work)
    if not 1<=args.workers<len(os.sched_getaffinity(0)):
        raise ValueError('Worker budget exceeds observed CPU affinity')
    record=json.loads((ab/'manifest.json').read_text())
    if record['status']!='AB_factorial_complete_CDE_not_yet_run':raise ValueError('AB must be verified complete')
    eid=record.get('experiment_id',record['parent']['experiment_id'])
    if not re.fullmatch(r'P[01]_M2_D[012]',eid):raise ValueError('Unsupported E06 parent identity')
    deps=dependencies(['fWalkforwardCSENET','fCreatePanelExAnte','fRankPredictorsOwnSupport'])
    work.mkdir(); manifest=dict(research_run_id=str(uuid.uuid4()),experiment_id=eid,ab_parent=str(ab),
        ab_manifest_sha256=sha(ab/'manifest.json'),definitions={
            'CD':'M1 own support + identified model/selection; M2 precleaned weekly labels and portfolio',
            'ABCD':'CD on A+B upstream input; M2 statistical-label and portfolio rules remain'},
        dependency_closure=deps,workers=args.workers,status='running')
    cpu=len(os.sched_getaffinity(0))
    parallel_hybrids=cpu>=16 and args.workers>=2
    hybrid_workers=min(args.workers,(cpu-4)//2) if parallel_hybrids else args.workers
    manifest['execution_topology']=dict(hybrid_clients=2 if parallel_hybrids else 1,
        workers_per_client=hybrid_workers,
        max_matlab_processes=2*(hybrid_workers+1) if parallel_hybrids else hybrid_workers+1)
    (work/'manifest.json').write_text(json.dumps(manifest,indent=2)+'\n')
    try:
        jobs=[]
        for variant,parent_name in (('CD','control'),('ABCD','AB')):
            source=ab/parent_name/'source';vroot=work/variant;code=vroot/'source';code.mkdir(parents=True)
            for p in source.rglob('*.m'):
                if any(n in p.relative_to(source).parts for n in ('DATA','Results')):continue
                dest=code/p.relative_to(source);dest.parent.mkdir(parents=True,exist_ok=True);shutil.copy2(p,dest)
            (code/'DATA').mkdir();(code/'Results/CTREND').mkdir(parents=True)
            for name in ('bCharacteristicsOLHC_Combo1.mat','b2EconomicReinvestmentLedger.mat'):
                shutil.copy2(source/'DATA'/name,code/'DATA'/name)
            shutil.copy2(source/'DesignChoices.mat',code/'DesignChoices.mat')
            for name in deps:shutil.copy2(REPO/'engines/M1/base/Utils'/(name+'.m'),code/'Utils'/(name+'.m'))
            path=code/'b05CreateCTREND.m';text=path.read_text()
            start=text.index("lAvail = all(~isnan(mChars_L1),3)")
            end=text.index('% Get asset weights',start)
            text=text[:start]+('% E06 C+D: keep formation-eligible union; rank each X on its own support.\n')+text[end:]
            path.write_text(text)
            exact_replace(path,"mCharsUse = permute(fCrossSectTransChars(permute(mChars_L1, [1,3,2]), 'rank'), [1,3,2]);",
                "[mCharsUse,~] = fRankPredictorsOwnSupport(mChars_L1,isfinite(mME_L1'));")
            exact_replace(path,"[mC, vY, mID, vW] = fCreatePanelExAnteM2( ...\n    mCharsUse,mRetRaw',mWts_L1);",
                "[mC, vY, mID, vW] = fCreatePanelExAnte( ...\n    mCharsUse,mRetRaw',mWts_L1,'lKeepPredictorUnion',true);")
            exact_replace(path,'fWalkforwardCSENET(vY, mC, mID, vW,...',
                'fWalkforwardCSENET(vYEstimation, mC, mID, vW,...')
            exact_replace(path,'"vYEstimation",vYEstimation);',
                '"vAllTimeID",vTimeID(:),"sOutlierTreatment",\'none\', ...\n    "lDemeanY",false);')
            exact_replace(path,"'lPredictorOwnSupport',false,","'lPredictorOwnSupport',true,")
            inputs={str(p.relative_to(code)):sha(p) for p in (code/'DATA').glob('*.mat')}
            inventory={str(p.relative_to(code)):sha(p) for p in code.rglob('*.m')}
            (vroot/'inputs.json').write_text(json.dumps(inputs,indent=2)+'\n')
            (vroot/'source_inventory.json').write_text(json.dumps(inventory,indent=2)+'\n')
            (vroot/'jobs').mkdir();(vroot/'prefs').mkdir()
            jobs.append((variant,vroot,code,inputs,inventory))
        if parallel_hybrids:
            with ThreadPoolExecutor(max_workers=2) as pool:
                futures=[pool.submit(run_variant,args,variant,vroot,code,inputs,inventory,hybrid_workers)
                         for variant,vroot,code,inputs,inventory in jobs]
                errors=[]
                for future in futures:
                    try:future.result()
                    except BaseException as exc:errors.append(repr(exc))
                if errors:raise RuntimeError('Parallel C/D hybrid failure(s): '+'; '.join(errors))
        else:
            for variant,vroot,code,inputs,inventory in jobs:
                run_variant(args,variant,vroot,code,inputs,inventory,hybrid_workers)
        manifest['status']='CD_and_ABCD_complete_not_full_M1'
    except BaseException as e:manifest['status']='failed';manifest['error']=repr(e);raise
    finally:(work/'manifest.json').write_text(json.dumps(manifest,indent=2)+'\n')


if __name__=='__main__':main()
