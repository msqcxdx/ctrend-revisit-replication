#!/usr/bin/env python3
"""Isolated baseline-only A/B factorial around an accepted P/D M2 run.

Control re-estimates b05 from its authenticated weekly input and must match
saved forecasts, betas, selection and portfolio returns before any hybrid.
A removes the close-erasure assignment (and its synchronization effect).
The legacy inequality also treats NaN != NaN as true, so A affects missing-
return days too, not only finite returns flagged by the outlier thresholds.
B replaces only the 28 technical-indicator class/formulas with the M1 ones.
AB measures their interaction. All retain M2 labels, support, selection,
market-cap rules and the accepted endpoint/reinvestment accounting.
This is NOT all of M1 and does NOT claim to complete modules C/D/E.
Only baseline data setting 1 is built; no accepted source/input is edited.
Each P/D sensitivity receives a separate --work-root and immutable receipt.
The authenticated control completes before A, B and AB start in isolated
MATLAB clients; the latter three run concurrently within CPU affinity.
"""
import argparse
from concurrent.futures import ThreadPoolExecutor
import csv
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import time
import uuid

ROOT=Path(__file__).resolve().parents[1];REPO=ROOT.parent


def sha(path):
    h=hashlib.sha256()
    with path.open('rb') as f:
        for b in iter(lambda:f.read(2**20),b''):h.update(b)
    return h.hexdigest()


def exact_replace(path,old,new):
    text=path.read_text()
    if text.count(old)!=1:raise ValueError(f'Patch anchor not unique: {path}: {old}')
    path.write_text(text.replace(old,new))


def quote(p):return str(p).replace("'","''")


def run_variant(args,variant,vroot,code,inventory,baseline,workers):
    """Run one isolated MATLAB client and verify its immutable source/output."""
    expr=(f"cd('{quote(code)}'); addpath('Utils'); set(0,'DefaultFigureVisible','off'); "
          f"c=parcluster('local'); c.JobStorageLocation='{quote(vroot/'jobs')}'; "
          f"c.NumWorkers={workers}; parpool(c,{workers}); ")
    if variant!='control':expr+="run('b02CalculateIndicators.m'); "
    expr+="run('b05CreateCTREND.m'); "
    if variant=='control':
        expr+=(f"a=load('{quote(baseline)}'); b=load('./Results/CTREND/CTREND_Base.mat'); "
               "assert(isequaln(a.mYhat,b.mYhat),'Control predictions differ'); "
               "assert(isequaln(a.mBeta,b.mBeta),'Control betas differ'); "
               "assert(isequaln(a.mSelected,b.mSelected),'Control selected components differ'); "
               "assert(isequaln(a.cResults.VW.mPortRet,b.cResults.VW.mPortRet),'Control returns differ'); "
               "fprintf('E06_CONTROL_BITWISE_OK\\n'); ")
    expr+="delete(gcp('nocreate')); fprintf('E06_VARIANT_OK\\n');"
    env={**os.environ,'MATLAB_PREFDIR':str(vroot/'prefs'),'OMP_NUM_THREADS':'1',
         'OPENBLAS_NUM_THREADS':'1','MKL_NUM_THREADS':'1'}
    print(f'E06_START variant={variant} workers={workers} root={vroot}',flush=True)
    start=time.time()
    with (vroot/'pipeline.log').open('w') as f:
        rc=subprocess.run([args.matlab,'-licmode','onlinelicensing','-nodisplay','-nosplash',
                           '-batch',expr],stdout=f,stderr=subprocess.STDOUT,env=env,cwd=code).returncode
    if rc:raise RuntimeError(f'{variant} failed rc={rc}; preserved {vroot}')
    if inventory!={str(p.relative_to(code)):sha(p) for p in code.rglob('*.m')}:
        raise ValueError(f'Derived source mutated while running: {variant}')
    result=code/'Results/CTREND/CTREND_Base.mat'
    (vroot/'COMPLETED.json').write_text(json.dumps(dict(variant=variant,
        workers=workers,result=str(result),sha256=sha(result),seconds=time.time()-start),indent=2)+'\n')
    print(f'E06_DONE variant={variant}',flush=True)


def main():
    ap=argparse.ArgumentParser();ap.add_argument('--work-root',required=True)
    ap.add_argument('--matlab',required=True);ap.add_argument('--workers',type=int,default=96)
    ap.add_argument('--experiment',default='P0_M2_D1')
    args=ap.parse_args();work=Path(args.work_root).resolve()
    if re.fullmatch(r'P[01]_M2_D[012]',args.experiment) is None:
        raise ValueError('E06 requires one accepted P[01]_M2_D[012] parent')
    if work.exists():raise FileExistsError(f'Preserve existing experiment: {work}')
    if not 1<=args.workers<=len(os.sched_getaffinity(0))-1:raise ValueError('Worker budget')
    if shutil.disk_usage(work.parent).free<15*2**30:raise RuntimeError('Need 15 GiB headroom')
    rows=list(csv.DictReader((ROOT/'outputs/E11/accepted_run_paths.csv').open()))
    identity=next(r for r in rows if r['experiment_id']==args.experiment)
    parent=Path(identity['accepted_run_root']);results=Path(identity['result_root'])
    source=parent/'runtime/ctrend_lookahead_only_pipeline'
    data=parent/'data.staging'
    if not data.is_dir():data=parent/'data'
    if sha(parent/'RUN_COMPLETE')!=identity['run_complete_sha256']:raise ValueError('Parent changed')
    baseline=results/'CTREND/CTREND_Base.mat'
    design=source/'DesignChoices.mat'
    inputs=[parent/'RUN_COMPLETE',baseline,design,
            data/'bCharacteristicsOLHC_Combo1.mat',data/'b0DataOLHC.mat',
            data/'b2EconomicReinvestmentLedger.mat']
    original={str(p):sha(p) for p in inputs}
    work.mkdir();manifest=dict(research_run_id=str(uuid.uuid4()),parent=identity,
        experiment_id=args.experiment,scope='baseline_only_A_B_factorial',inputs=original,workers=args.workers,
        frozen_other_modules='M2 label/support/selection/weekly portfolio rules',
        definitions={'A':'no daily-outlier-induced close holes; preserve M2 label rule',
                     'B':'M1 technical_indicators class and 28-indicator parameter calls',
                     'AB':'A and B together; not full M1'},status='running')
    # Control must pass before any hybrid starts.  The three hybrids depend on
    # immutable accepted inputs, not on one another, so isolate and run them
    # concurrently.  Budget one client plus its workers per variant.
    cpu=len(os.sched_getaffinity(0))
    parallel_hybrids=cpu>=24 and args.workers>=3
    hybrid_workers=min(args.workers,(cpu-3)//3) if parallel_hybrids else args.workers
    manifest['execution_topology']=dict(control_workers=args.workers,
        hybrid_clients=3 if parallel_hybrids else 1,
        hybrid_workers_per_client=hybrid_workers,
        max_hybrid_matlab_processes=3*(hybrid_workers+1) if parallel_hybrids else hybrid_workers+1)
    (work/'manifest.json').write_text(json.dumps(manifest,indent=2)+'\n')
    try:
        hybrid_jobs=[]
        for variant in ('control','A','B','AB'):
            vroot=work/variant;code=vroot/'source';code.mkdir(parents=True)
            for p in source.rglob('*.m'):
                # Do not copy symlinked DATA/Results or accidentally read a
                # separate runtime. Only authenticated run-local code files.
                if 'DATA' in p.relative_to(source).parts or 'Results' in p.relative_to(source).parts:continue
                target=code/p.relative_to(source);target.parent.mkdir(parents=True,exist_ok=True)
                shutil.copy2(p,target)
            dd=code/'DATA';dd.mkdir();(code/'Results/CTREND').mkdir(parents=True)
            shutil.copy2(design,code/'DesignChoices.mat')
            if variant=='control':
                for name in ('bCharacteristicsOLHC_Combo1.mat','b2EconomicReinvestmentLedger.mat'):
                    shutil.copy2(data/name,dd/name)
            else:
                shutil.copy2(data/'b0DataOLHC.mat',dd/'b0DataOLHC.mat')
                # b02 consumes these fixed ancillary series too.
                for name in ('F-F_Research_Data_Factors_daily.CSV','LTW_3factor.mat','UCRY.csv'):
                    if (data/name).is_file():shutil.copy2(data/name,dd/name)
                exact_replace(code/'b02CalculateIndicators.m','for iIdxC = 1:iNumDataCombos',
                    '% E06 baseline design only; all 28 X and input screens retained.\nfor iIdxC = 1:1')
            if 'A' in variant:
                exact_replace(code/'b02CalculateIndicators.m','rData.mClose(lChanged)  = NaN;',
                    '% E06 module A: do not propagate a label outlier into price history.\n    % Daily cleaned returns remain unchanged; economic payoffs remain separate.')
            if 'B' in variant:
                for name in ('technical_indicators.m','fComputeTechnicalIndicatorChunk.m'):
                    shutil.copy2(REPO/'engines/M1/base/Utils'/name,code/'Utils'/name)
                exact_replace(code/'Utils/fComputeOldFeaturesParallel.m',
                    'cIndicatorChunks{iIdxChunk} = iComputeIndicatorChunk(',
                    'cIndicatorChunks{iIdxChunk} = fComputeTechnicalIndicatorChunk(')
            inventory={str(p.relative_to(code)):sha(p) for p in code.rglob('*.m')}
            (vroot/'source_inventory.json').write_text(json.dumps(inventory,indent=2)+'\n')
            (vroot/'jobs').mkdir();(vroot/'prefs').mkdir()
            if variant=='control':
                run_variant(args,variant,vroot,code,inventory,baseline,args.workers)
            else:
                hybrid_jobs.append((variant,vroot,code,inventory))
        if parallel_hybrids:
            with ThreadPoolExecutor(max_workers=3) as pool:
                futures=[pool.submit(run_variant,args,variant,vroot,code,inventory,baseline,hybrid_workers)
                         for variant,vroot,code,inventory in hybrid_jobs]
                errors=[]
                for future in futures:
                    try:future.result()
                    except BaseException as exc:errors.append(repr(exc))
                if errors:raise RuntimeError('Parallel hybrid failure(s): '+'; '.join(errors))
        else:
            for variant,vroot,code,inventory in hybrid_jobs:
                run_variant(args,variant,vroot,code,inventory,baseline,hybrid_workers)
        if original!={str(p):sha(p) for p in inputs}:raise ValueError('Accepted inputs changed')
        manifest['status']='AB_factorial_complete_CDE_not_yet_run'
    except BaseException as exc:
        manifest['status']='failed';manifest['error']=repr(exc);raise
    finally:(work/'manifest.json').write_text(json.dumps(manifest,indent=2)+'\n')


if __name__=='__main__':main()
