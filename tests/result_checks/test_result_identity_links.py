#!/usr/bin/env python3
# CTREND_REVISIT_FILE_PURPOSE: Cross-check run, table, figure, diagnostic and source-export identities so reports cannot mix distinct runs for one experiment.
# Every derivative must point back to the same accepted research_run_id and
# content hash.  The test follows the identity chain rather than comparing
# rounded headline numbers, which could coincide across different runs.
from pathlib import Path
import csv, hashlib

R=Path(__file__).resolve().parents[2]
def rows(path):return list(csv.DictReader(path.open()))
def sha(path):
    with path.open('rb') as f:return hashlib.file_digest(f,'sha256').hexdigest()
public={r['experiment_id']:r for r in rows(R/'provenance/accepted_18/PUBLIC_RUN_IDENTITIES.csv')}
source=R/'results/comparisons/source_tables'
for name in ('RUN_IDENTITIES_18.csv','exact_headline_from_mat.csv'):
    records=rows(source/name)
    assert len(records)==len(public) and {r['experiment_id'] for r in records}==set(public)
    for row in records:
        id=row['experiment_id'];assert row['research_run_id']==public[id]['research_run_id'],(id,name)
        if 'run_complete_sha256' in row:assert row['run_complete_sha256']==public[id]['run_complete_sha256']
for row in rows(source/'EIGHTEEN_EXPERIMENT_FIGURE_INVENTORY.csv'):
    # PNG and editable FIG companions are independently content-addressed.
    for kind in ('png','fig'):
        assert sha(R/'results/experiments'/row['experiment_id']/row[kind+'_relative_path'])==row[kind+'_sha256']
for row in rows(R/'results/diagnostics/portfolio_diagnostics/BASELINE_DIAGNOSTIC_IDENTITIES.csv'):
    assert sha(R/'results/experiments'/row['experiment_id']/'CTREND/CTREND_Base.mat')==row['baseline_sha256']
ledger=R/'provenance/accepted_18/source_table_export.sha256.txt'
listed={rel:digest for digest,rel in (line.split('  ',1) for line in ledger.read_text().splitlines())}
assert set(listed)=={str(p.relative_to(source)) for p in source.rglob('*') if p.is_file()}
for rel,digest in listed.items():assert sha(source/rel)==digest,rel
print('RESULT_IDENTITY_LINKS_OK runs=18 figures=1 diagnostics=1 source_tables=1')
