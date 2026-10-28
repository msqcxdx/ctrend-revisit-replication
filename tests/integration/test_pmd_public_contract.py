#!/usr/bin/env python3
# CTREND_REVISIT_FILE_PURPOSE: Check all eighteen public routes, P0 runtime contracts and exclusion lists without launching MATLAB.
# This is a plan-mode integration test: every public experiment ID must resolve
# to the correct inner engine/overlay while writing only to a temporary tree.
# It validates packaging and routing, not the numerical MATLAB estimand.
from pathlib import Path
import csv,subprocess,os,tempfile
ROOT=Path(__file__).resolve().parents[2]
rows=list(csv.DictReader((ROOT/'config/experiments_pmd.csv').open()))
ids={f'P{p}_M{m}_D{d}' for p in range(2) for m in range(3) for d in range(3)}
assert len(rows)==18 and {r['experiment_id'] for r in rows}==ids
with tempfile.TemporaryDirectory(prefix='pmd_paths_') as tmp:
 # Resolve all eighteen commands without starting a production run.
 for r in rows:
  id=r['experiment_id'];p,m,d=id.split('_')
  text=subprocess.check_output([str(ROOT/'run_all.sh'),'experiment',id,'production'],cwd=tmp,
    env={**os.environ,'CTREND_PLAN_ONLY':'1'},text=True)
  assert f'experiment_id={id} ' in text
  assert f'inner_id={id if p=="P0" else m+"_"+d} ' in text
  assert ('p0_extension/' in text)==(p=='P0')
  assert r['unified_missing_preprocessing']==p[1:]
  if p=='P0':
   assert "'"+id+"'" in (ROOT/'p0_extension/tests/verify_experiment_identity.m').read_text(),(id,'MATLAB acceptance ID not admitted')
for d,n in [('D0',0),('D1',1),('D2',28)]:
 # Bind public D labels to exact exclusion cardinalities and critical identities.
 ex=list(csv.DictReader((ROOT/f'config/exclusions/{d}.csv').open()));assert len(ex)==n
 values=[int(x['asset_id']) for x in ex];assert len(set(values))==n
 if d!='D0':assert 3787 in values
 assert not ({2603,9040}&set(values))
subprocess.run([str(ROOT/'p0_extension/tests/test_preprocessing_derivation.sh')],check=True)
subprocess.run([str(ROOT/'p0_extension/tests/test_runtime_packages.sh')],check=True)
assert 'fApplyUnifiedMissingDataPreprocessing' not in (ROOT/'engines/P0_M0/base/b01ReadData.m').read_text()
print('PMD_PUBLIC_CONTRACT_OK experiments=18 routes=18 p0_archives=9 exclusions=28')
