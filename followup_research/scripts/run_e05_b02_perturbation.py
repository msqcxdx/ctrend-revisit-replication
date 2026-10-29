#!/usr/bin/env python3
"""Replay accepted production b02 after an audited in-memory future quote shock.

The input is the accepted b01 DAILY panel (not a raw-download rebuild). Normal
provenance checks still run against that read-only parent before intervention.
Only output locations, a baseline-design bound, and the explicitly logged
shock are changed. Derived weekly files are TEST artifacts, never registered
as production runs. A control must match accepted numeric fields bitwise.
"""
import argparse
import csv
import json
import os
from pathlib import Path
import re
import subprocess
import uuid
import h5py
import numpy as np
from run_e06_upstream_hybrids import ROOT,sha,quote


INJECTION=r"""
% E05 audit intervention AFTER read-only loading/validation, before any b02
% calculation. Keep every pre-cutoff value, asset, and missing cell unchanged.
if iAuditMode==1
    lE05Future=yrmoda>=20200415;
    mE05Scale=1+.12*sin((1:nnz(lE05Future))'*.17+(1:size(mClose,2))*.13);
    cE05Fields={'mClose','mOpen','mHigh','mLow','mME','mVolume', ...
        'mCloseEconomicRaw','mClosePnlRaw','mMEEconomicRaw','mVolumeRaw'};
    for iE05Field=1:numel(cE05Fields)
        sE05Field=cE05Fields{iE05Field};
        if exist(sE05Field,'var')
            eval([sE05Field,'(lE05Future,:)=',sE05Field,'(lE05Future,:).*mE05Scale;']);
        end
    end
    mE05Ret=[NaN(1,size(mClose,2));mClose(2:end,:)./mClose(1:end-1,:)-1];
    % Preserve exactly the accepted b01 return-observability mask. Values of
    % observable future returns are recomputed consistently with the shock.
    lE05Update=repmat(lE05Future,1,size(mClose,2)) & isfinite(mReturns);
    mReturns(lE05Update)=mE05Ret(lE05Update);
    if exist('mClosePnlRaw','var'),mE05Economic=mClosePnlRaw;else,mE05Economic=mCloseEconomicRaw;end
    tE05Original=tMechanicalExitCalendar;
    [tMechanicalExitCalendar,~]=fBuildAndFreezeMechanicalExitCalendar( ...
        mE05Economic,yrmoda,rMetaData.vID(:),rMetaData.cSymbol(:), ...
        fullfile(sAuditOut,'value_shock_calendar.csv'));
    assert(isequaln(tE05Original.last_tradable_index,tMechanicalExitCalendar.last_tradable_index), ...
        'Future value shock must not change quote availability or exit dates');
    fprintf('E05_DAILY_VALUE_SHOCK cutoff=20200415 rows=%d\n',nnz(lE05Future));
end
"""


def function_text(source):
    text=source.read_text().replace('\r\n','\n')
    text=text.replace('clear; clc; close all;','clc; close all;')
    text,n=re.subn(r"sOutDataPath\s*=\s*'./DATA/';","sOutDataPath=[sAuditOut,filesep];",text,count=1)
    if n!=1:raise ValueError('output-path anchor')
    # The first dimensions statement occurs after empirical raw-data checks
    # in M1, and after input loading in M2. Later inner-loop statements stay.
    anchor='[iNumObs, iNumAssets] = size(mClose);'
    if text.count(anchor)!=1:raise ValueError('daily intervention anchor')
    text=text.replace(anchor,INJECTION+'\n'+anchor)
    anchor="load('DesignChoices.mat','tDataCombos');"
    if text.count(anchor)!=1:raise ValueError('design anchor')
    text=text.replace(anchor,anchor+"\ntDataCombos=tDataCombos(1,:); % audit: baseline input only\n")
    local=re.search(r'(?m)^function ',text)
    if not local:raise ValueError('Expected production b02 local functions')
    # Keep production's SCRIPT workspace semantics. Wrapping its dynamic
    # load() in a function makes parfor mistake loaded arrays for functions;
    # that is a probe harness failure, not a scientific b02 failure.
    return text


def compare(control,changed,accepted,eid):
    result=[]
    with h5py.File(control) as a,h5py.File(changed) as b,h5py.File(accepted) as c:
        weeks=np.asarray(a['rData/yrmoda'],int).ravel()
        for f in (b,c):assert np.array_equal(weeks,np.asarray(f['rData/yrmoda'],int).ravel())
        names=['rChars/'+k for k in a['rChars']]
        datafields=['mReturns','mRetLead','mClose','mME','mVolume','mReturnsM2Raw','mRetLeadM2Raw',
            'mPnlReturns','mPnlRetLead','mPnlReturnsM2','mPnlRetLeadM2']
        names += ['rData/'+n for n in datafields if n in a['rData']]
        for name in names:
            x=np.asarray(a[name]);y=np.asarray(b[name]);original=np.asarray(c[name])
            if x.shape!=y.shape or x.shape!=original.shape:raise ValueError('Array axes '+name)
            identical=(x==original)|(np.isnan(x)&np.isnan(original))
            if not identical.all():raise ValueError(f'Control rebuild not bitwise equal: {eid} {name}')
            # One-day-lead labels of week 15 legitimately read April 15.
            # They become known later and are excluded from the pre-cut test.
            end=202014 if 'RetLead' in name else 202015
            prefix=weeks<=end
            if x.shape[-1]!=len(weeks):raise ValueError('Unexpected weekly matrix axis')
            delta=~((x==y)|(np.isnan(x)&np.isnan(y)))
            past=int(delta[...,prefix].sum());future=int(delta[...,~prefix].sum())
            result.append(dict(experiment_id=eid,field=name,last_tested_past_week=end,
                control_equal_accepted=1,past_changed_cells=past,later_changed_cells=future,
                scope='accepted_b01_daily_panel_to_real_b02_not_raw_download_or_b01_rebuild'))
            if past:raise ValueError(f'Historical b02 field changed: {eid} {name} n={past}')
        if not any(r['later_changed_cells'] for r in result):raise ValueError('Future shock had no effect')
    return result


def main():
    ap=argparse.ArgumentParser();ap.add_argument('--work-root',required=True)
    ap.add_argument('--matlab',required=True);ap.add_argument('--workers',type=int,default=96)
    args=ap.parse_args();work=Path(args.work_root).resolve()
    if work.exists():raise FileExistsError(work)
    work.mkdir();rows=[]
    identities={r['experiment_id']:r for r in csv.DictReader((ROOT/'outputs/E11/accepted_run_paths.csv').open())}
    receipt=dict(research_run_id=str(uuid.uuid4()),status='running',inputs=[],
        audit='isolated b02 daily quote perturbation, no production acceptance',
        driver_sha256=sha(Path(__file__)))
    try:
        for m,engine in ((2,'ctrend_lookahead_only_pipeline'),(1,'ctrend_corrected_pipeline')):
            eid=f'P0_M{m}_D1';parent=Path(identities[eid]['accepted_run_root']);source=parent/'runtime'/engine
            data=parent/'data';data=data if data.is_dir() else parent/'data.staging'
            original={str(p):sha(p) for p in (parent/'RUN_COMPLETE',source/'b02CalculateIndicators.m',
                data/'b0DataOLHC.mat',data/'bCharacteristicsOLHC_Combo1.mat')}
            if original[str(parent/'RUN_COMPLETE')]!=identities[eid]['run_complete_sha256']:raise ValueError('Parent marker')
            folder=work/eid;folder.mkdir();(folder/'jobs').mkdir();(folder/'prefs').mkdir()
            helper=folder/'e05_real_b02_probe.m';helper.write_text(function_text(source/'b02CalculateIndicators.m'))
            (folder/'control').mkdir();(folder/'future_values').mkdir()
            expr=(f"cd('{quote(source)}');addpath('{quote(folder)}');c=parcluster('local');"
                f"c.JobStorageLocation='{quote(folder/'jobs')}';c.NumWorkers={args.workers};parpool(c,{args.workers});"
                f"sAuditOut='{quote(folder/'control')}';iAuditMode=0;e05_real_b02_probe;"
                f"sAuditOut='{quote(folder/'future_values')}';iAuditMode=1;e05_real_b02_probe;delete(gcp('nocreate'));")
            print(f'E05_B02_START {eid}',flush=True)
            with (folder/'pipeline.log').open('w') as log:
                rc=subprocess.run([args.matlab,'-licmode','onlinelicensing','-nodisplay','-nosplash','-batch',expr],
                    stdout=log,stderr=subprocess.STDOUT,env={**os.environ,'MATLAB_PREFDIR':str(folder/'prefs'),
                    'OMP_NUM_THREADS':'1','MKL_NUM_THREADS':'1','OPENBLAS_NUM_THREADS':'1'}).returncode
            if original!={p:sha(Path(p)) for p in original}:raise ValueError('Parent input changed')
            receipt['inputs'].append(dict(experiment_id=eid,files=original,probe_sha256=sha(helper)))
            if rc:raise RuntimeError(f'{eid} b02 probe failed rc={rc}: {folder}')
            rows.extend(compare(folder/'control/bCharacteristicsOLHC_Combo1.mat',
                folder/'future_values/bCharacteristicsOLHC_Combo1.mat',data/'bCharacteristicsOLHC_Combo1.mat',eid))
            print(f'E05_B02_PAST_INVARIANT_OK {eid}',flush=True)
        path=ROOT/'outputs/E05/production_b02_daily_future_perturbation.csv'
        with path.open('w',newline='') as f:
            w=csv.DictWriter(f,fieldnames=list(rows[0]));w.writeheader();w.writerows(rows)
        receipt['status']='b02_passed_b01_and_calendar_asof_not_certified';receipt['output_sha256']=sha(path)
    except BaseException as e:receipt['status']='failed';receipt['error']=repr(e);raise
    finally:(work/'receipt.json').write_text(json.dumps(receipt,indent=2)+'\n')


if __name__=='__main__':main()
