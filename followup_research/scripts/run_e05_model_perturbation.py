#!/usr/bin/env python3
"""Run read-only production-model future-input perturbations for P0 D1 M1/M2.

No b01/b02 rebuilding is claimed. In-memory shocks are injected after the
accepted weekly input is loaded. Original model code remains untouched; only
new audit CSVs/logs are written. Control fits must be bitwise identical.
"""
import argparse
import csv
import json
import os
from pathlib import Path
import subprocess
import uuid
from run_e06_upstream_hybrids import ROOT, sha, quote


def main():
    ap=argparse.ArgumentParser();ap.add_argument('--work-root',required=True)
    ap.add_argument('--matlab',required=True);ap.add_argument('--workers',type=int,default=28)
    args=ap.parse_args();work=Path(args.work_root).resolve()
    if work.exists():raise FileExistsError(work)
    work.mkdir();out=ROOT/'outputs/E05'
    identities={r['experiment_id']:r for r in csv.DictReader((ROOT/'outputs/E11/accepted_run_paths.csv').open())}
    receipt=dict(research_run_id=str(uuid.uuid4()),scope='b05_real_model_not_full_raw_pipeline',
        script_sha256=sha(Path(__file__).with_name('test_e05_production_model_perturbation.m')),
        exit_calendar='held_fixed_not_tested',inputs=[],status='running')
    try:
        for m,engine in ((2,'cttrend_lookahead_only_pipeline'),(1,'cttrend_corrected_pipeline')):
            eid=f'P0_M{m}_D1';r=identities[eid];run=Path(r['accepted_run_root'])
            source=run/'runtime'/engine;result=Path(r['result_root'])/'CTREND/CTREND_Base.mat'
            paths=[run/'RUN_COMPLETE',source/'b05CreateCTREND.m',result]
            for folder in ('data','data.staging'):
                f=run/folder/'bCharacteristicsOLHC_Combo1.mat'
                if f.is_file():paths.append(f)
            before={str(p):sha(p) for p in paths}
            if before[str(run/'RUN_COMPLETE')]!=r['run_complete_sha256']:raise ValueError('parent identity')
            v=work/eid;v.mkdir();(v/'jobs').mkdir();(v/'prefs').mkdir()
            expr=(f"addpath('{quote(ROOT/'scripts')}'); c=parcluster('local'); "
                f"c.JobStorageLocation='{quote(v/'jobs')}';c.NumWorkers={args.workers};parpool(c,{args.workers}); "
                f"test_e05_production_model_perturbation('{quote(source)}','{quote(result)}',"
                f"'{quote(out/(eid+'_production_b05_future_perturbation.csv'))}',202016);delete(gcp('nocreate'));")
            print(f'E05_REFIT_START {eid}',flush=True)
            with (v/'pipeline.log').open('w') as log:
                rc=subprocess.run([args.matlab,'-licmode','onlinelicensing','-nodisplay','-nosplash','-batch',expr],
                    stdout=log,stderr=subprocess.STDOUT,env={**os.environ,'MATLAB_PREFDIR':str(v/'prefs'),
                    'OMP_NUM_THREADS':'1','OPENBLAS_NUM_THREADS':'1','MKL_NUM_THREADS':'1'}).returncode
            if before!={str(p):sha(p) for p in paths}:raise ValueError('Accepted input was changed')
            receipt['inputs'].append(dict(experiment_id=eid,research_run_id=r['research_run_id'],sha256=before))
            if rc:raise RuntimeError(f'{eid} refit test failed rc={rc}; inspect {v}')
            print(f'E05_REFIT_DONE {eid}',flush=True)
        receipt['status']='production_model_stage_passed_raw_preprocessing_not_tested'
    except BaseException as e:receipt['status']='failed';receipt['error']=repr(e);raise
    finally:(work/'receipt.json').write_text(json.dumps(receipt,indent=2)+'\n')


if __name__=='__main__':main()
