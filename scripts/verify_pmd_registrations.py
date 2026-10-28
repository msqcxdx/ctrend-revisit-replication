#!/usr/bin/env python3
# CTREND_REVISIT_FILE_PURPOSE: Revalidate all eighteen full-run inner registrations before accepting the public P/M/D suite.
"""Check all public registrations against their accepted inner identities."""
from pathlib import Path
import csv,hashlib,subprocess,sys
root=Path(__file__).resolve().parents[1]
def env(p):return dict(x.split('=',1) for x in p.read_text().splitlines() if '=' in x)
rows=list(csv.DictReader((root/'config/experiments_pmd.csv').open()))
selected=set(sys.argv[1:]) or {x['experiment_id'] for x in rows}
assert selected <= {x['experiment_id'] for x in rows}
for row in rows:
    if row['experiment_id'] not in selected:continue
    id=row['experiment_id'];p=root/'outputs/experiments'/id/'PMD_REGISTRATION.env'
    x=env(p);assert x['experiment_id']==id
    inner=root/x['inner_registration_relative']
    assert hashlib.sha256(inner.read_bytes()).hexdigest()==x['inner_registration_sha256']
    y=env(inner)
    assert y['experiment_id']==x['inner_experiment_id']
    driver=root/('p0_extension/scripts/register_completed_run.sh' if id.startswith('P0_') else 'scripts/register_completed_run.sh')
    subprocess.run([str(driver),x['inner_experiment_id'],y['run_root']],check=True)
print('PMD_REGISTRATIONS_OK experiments=',len(selected))
