#!/usr/bin/env python3
# CTREND_REVISIT_FILE_PURPOSE: Verify complete compact-result membership and byte identities against eighteen accepted full-run source inventories.
# Inputs: curated results/MANIFEST.sha256 plus accepted-run member identities.
# Exact membership and hashes prevent a report from mixing runs or silently
# dropping artifacts; logs, office files, and other non-release files are rejected.
from pathlib import Path
import csv,hashlib
R=Path(__file__).resolve().parents[2];S=R/'results'
manifest=S/'MANIFEST.sha256'
listed=dict((rel,digest) for digest,rel in (line.split('  ',1) for line in manifest.read_text().splitlines()))
actual={str(p.relative_to(S)) for p in S.rglob('*') if p.is_file() and p!=manifest}
assert set(listed)==actual
for rel,h in listed.items():assert hashlib.sha256((S/rel).read_bytes()).hexdigest()==h,rel
ids={f'P{p}_M{m}_D{d}' for p in range(2) for m in range(3) for d in range(3)}
registry=list(csv.DictReader((R/'provenance/accepted_18/PUBLIC_RUN_IDENTITIES.csv').open()))
assert {r['experiment_id'] for r in registry}==ids
members=list(csv.DictReader((R/'provenance/accepted_18/RESULT_MEMBER_IDENTITIES.csv').open()))
for r in members:
 p=R/r['relative_path'];assert p.is_file(),p
 assert hashlib.sha256(p.read_bytes()).hexdigest()==r['sha256'],p
for id in ids:
 # Minimum table/figure counts and baseline presence are checked for every cell.
 root=S/'experiments'/id
 assert len(list((root/'Figures').glob('*.png')))==16,id
 assert len(list((root/'Tables').glob('*.tex'))) >= 19,id
 assert (root/'CTREND/CTREND_Base.mat').is_file()
assert not any(p.suffix in {'.pdf','.doc','.docx','.log','.pid'} for p in S.rglob('*') if p.is_file())
print('ACCEPTED_18_RESULT_SNAPSHOT_OK',len(actual),len(members))
