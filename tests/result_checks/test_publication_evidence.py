#!/usr/bin/env python3
# CTREND_REVISIT_FILE_PURPOSE: Independently audit paper benchmarks, citations, saved-figure companions, annotation counts, and optional result-check wiring.
# This test joins prose to machine-readable evidence: cited paper values,
# numerical companions for plotted bars, page mappings, and optional-audit
# wiring must all be reproducible from committed sources.
import csv
import io
import json
import math
import re
import statistics
import sys
import tempfile
from pathlib import Path
import zipfile
from xml.etree import ElementTree as ET

import numpy as np
from scipy.io import loadmat, savemat

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'analysis'))
from publication_evidence import paper_baseline, factor_companion, figure_bars
from paper_factor_comparison import (load_published_factor, workbook_series,
                                    comparison_rows, week_key, return_statistics)

paper = paper_baseline(ROOT)
# Fixed citation evidence is not a constraint on any experiment's estimates.
assert paper == dict(mean=3.87, t=5.19, std=14.34, sharpe=1.94), paper
author, author_source = load_published_factor(ROOT)
actual_author = return_statistics(author)
# The immutable author data must independently agree with cited rounded cells.
# Experiment/common counts are derived, not pinned to historical sample sizes.
for source_key, table_key in [('mean_weekly_pct','mean'),('std_weekly_pct','std'),
                              ('t','t'),('sharpe_annualized','sharpe')]:
    assert round(actual_author[source_key], 2) == paper[table_key]
folder = ROOT / 'results/comparisons/paper_factor'
provenance = json.loads((folder / 'PAPER_FACTOR_PROVENANCE.json').read_text())
assert provenance['archive_sha256'] == author_source['archive_sha256']
assert provenance['workbook_sha256'] == author_source['workbook_sha256']
with (folder / 'PAPER_WEEKLY_RETURNS.csv').open() as f:
    exported_author = {int(r['year_week']):float(r['paper_hl_return']) for r in csv.DictReader(f)}
assert exported_author == author
for name in ('README.md', 'README_CN.md'):
    text = (ROOT / name).read_text()
    assert f"| Paper (published factor) | {actual_author['weeks']} | {actual_author['mean_weekly_pct']:.4f} |" in text
    assert 'CTREND.xlsx' in text and 'paper_factor/' in text
    assert '仅关闭公共 b01' not in text

# Read every accepted MAT independently; date keys, not row positions, define
# supports. Recompute scalar summaries with the stdlib rather than the exporter.
ids = [f'P{p}_M{m}_D{d}' for p in range(2) for m in (0, 2, 1) for d in range(3)]
raw = {'Paper':author}
for id in ids:
    mat = loadmat(ROOT / 'results/experiments' / id / 'CTREND/CTREND_Base.mat', simplify_cells=True)
    raw[id] = dict(zip(map(int, np.atleast_1d(mat['vDates'])), mat['cResults']['VW']['mPortRet'][-1]))
all_dates = sorted(set.intersection(*[{t for t,v in z.items() if np.isfinite(v)} for z in raw.values()]))
assert provenance['all_series_common_dates'] == all_dates
assert provenance['all_series_common_weeks'] == len(all_dates)
experiment_dates = set.intersection(*[{t for t,v in raw[id].items() if np.isfinite(v)} for id in ids])
with (folder / 'NINETEEN_WAY_WEEKLY_RETURNS.csv').open() as f:
    panel = list(csv.DictReader(f))
assert [int(r['year_week']) for r in panel] == sorted(set.union(*[set(v) for v in raw.values()]))
for row in panel:
    t = int(row['year_week'])
    assert int(row['all_eighteen_common']) == int(t in experiment_dates)
    assert int(row['all_nineteen_common']) == int(t in all_dates)
    for id in raw:
        assert np.isclose(float(row[id]),raw[id].get(t,float('nan')),rtol=1e-12,atol=1e-12,equal_nan=True), (id,t)
with (folder / 'PAPER_EXPERIMENT_SUPPORT_DIFFERENCES.csv').open() as f:
    support_rows = {(r['experiment_id'],int(r['year_week']),r['support_status']) for r in csv.DictReader(f)}
paper_dates = set(author)
expected_differences = set()
for id in ids:
    experiment_own = {t for t,v in raw[id].items() if np.isfinite(v)}
    expected_differences.update((id,t,'author_only' if t in paper_dates else 'experiment_only')
                                for t in paper_dates ^ experiment_own)
assert support_rows == expected_differences
for filename, balanced in [('NINETEEN_WAY_OWN_SUPPORT_SUMMARY.csv',False),
                           ('NINETEEN_WAY_ALL_COMMON_SUMMARY.csv',True)]:
    with (folder / filename).open() as f:
        rows = list(csv.DictReader(f))
    assert [r['series_id'] for r in rows] == list(raw)
    for row in rows:
        values = raw[row['series_id']]
        dates = all_dates if balanced else sorted(t for t,v in values.items() if np.isfinite(v))
        z = [float(values[t]) for t in dates]
        mean, sd = statistics.mean(z), statistics.stdev(z)
        expected_values = dict(mean_weekly_pct=100*mean, std_weekly_pct=100*sd,
                               t=math.sqrt(len(z))*mean/sd,
                               sharpe_annualized=math.sqrt(52)*mean/sd)
        assert int(row['weeks']) == len(z)
        for key, value in expected_values.items():
            assert np.isclose(float(row[key]), value, rtol=1e-12, atol=1e-12), (filename,row['series_id'],key)
with (folder / 'NINETEEN_WAY_PAIRWISE_COMMON_SUMMARY.csv').open() as f:
    rows = list(csv.DictReader(f))
assert len(rows) == len(raw)*(len(raw)-1)//2
assert len({(r['first'],r['second']) for r in rows}) == len(rows)
for filename, fixed in [('NINETEEN_WAY_PAIRWISE_COMMON_SUMMARY.csv',False),
                        ('PAPER_EXPERIMENT_ALL_COMMON_COMPARISONS.csv',True)]:
    with (folder / filename).open() as f:
        for row in csv.DictReader(f):
            a, b = raw[row['first']], raw[row['second']]
            dates = all_dates if fixed else sorted(t for t in set(a)&set(b) if np.isfinite(a[t]) and np.isfinite(b[t]))
            assert row['shared_dates'] == ';'.join(map(str,dates))
            z = [float(b[t]-a[t]) for t in dates]
            mean, sd = statistics.mean(z), statistics.stdev(z)
            assert np.isclose(float(row['delta_mean_pp_second_minus_first']),100*mean,atol=1e-12)
            assert np.isclose(float(row['paired_spread_t']),math.sqrt(len(z))*mean/sd,atol=1e-12)

# OOXML negative cases guard the very bug that can count header shared-string
# indices as returns, and reject ambiguous/fractional/non-author calendar keys.
with zipfile.ZipFile(ROOT / 'reference/dataverse_files.zip') as original:
    workbook_payload = original.read('Results/CTREND/CTREND.xlsx')
with zipfile.ZipFile(io.BytesIO(workbook_payload)) as book:
    members = {name:book.read(name) for name in book.namelist()}
ns = {'s':'http://schemas.openxmlformats.org/spreadsheetml/2006/main'}
sheet_path = 'xl/worksheets/sheet2.xml'
for invalid_date in ('202053', '202001.5', str(next(iter(author)))):
    tree = ET.fromstring(members[sheet_path])
    tree.find("s:sheetData/s:row/s:c[@r='A3']/s:v",ns).text = invalid_date
    bad = io.BytesIO()
    with zipfile.ZipFile(bad,'w') as changed:
        for name,payload in members.items():
            changed.writestr(name,ET.tostring(tree) if name==sheet_path else payload)
    try:
        workbook_series(bad.getvalue())
        raise AssertionError(f'Invalid published key accepted: {invalid_date}')
    except ValueError:
        pass
assert week_key(202052)==202052 and week_key(202101)==202101
synthetic=comparison_rows({202051:.01,202052:.02,202101:.03},
    {'A':{202050:.7,202051:.05,202052:.06,202101:.07},
     'B':{202051:float('nan'),202052:.04,202101:.05,202102:.9}})
assert synthetic['shared']==[202052,202101]
assert synthetic['own'][0]['weeks']==3
assert synthetic['weekly'][0]['Paper']!=synthetic['weekly'][0]['Paper']  # Missing, not zero.
assert next(r for r in synthetic['pairs'] if r['second']=='A')['common_weeks']==3
assert synthetic['fixed'][0]['common_weeks']==2
with tempfile.TemporaryDirectory() as tmp:
    mini=Path(tmp)
    (mini/'reference/dataverse_original_3d0959b1/Results/CTREND').mkdir(parents=True)
    with zipfile.ZipFile(mini/'reference/dataverse_files.zip','w') as original:
        original.writestr('Results/CTREND/CTREND.xlsx',workbook_payload)
    (mini/'reference/dataverse_original_3d0959b1/Results/CTREND/CTREND.xlsx').write_bytes(b'not original')
    try:
        load_published_factor(mini)
        raise AssertionError('Altered extracted author reference accepted')
    except ValueError:
        pass

source = ROOT / 'results/comparisons/source_tables'
for path in [*source.glob('*.csv'), *source.glob('*.md'), ROOT / 'results/comparisons/NINETEEN_WAY_FULL_REPORT_CN.md']:
    text = path.read_text()
    for physical, printed in re.findall(r'PDF pp?\.([0-9–]+)（期刊 p{1,2}\.([0-9–]+)）', text):
        assert list(map(int, physical.split('–'))) == [int(x)-3115 for x in printed.split('–')], path
    assert 'Table 3 后的正文图' not in text, path
    assert 'M2 只修直接前视' not in text, path
    assert '四因子 Avg/Sharpe 已在 Table B.2 两个面板逐项列出' not in text, path

with (ROOT / 'results/comparisons/FACTOR_FIGURE_NUMERICAL_COMPANION.csv').open() as f:
    saved = list(csv.DictReader(f))
ids = [f'P{p}_M{m}_D{d}' for p in range(2) for m in (0, 2, 1) for d in range(3)]
expected = [r for id in ids for r in factor_companion(ROOT / 'results/experiments', id)]
# Row order is part of the publication contract because the CSV feeds tables directly.
assert len(saved) == len(expected)
for got, want in zip(saved, expected):
    for key, value in want.items():
        if isinstance(value, (float, np.floating)):
            assert np.isclose(float(got[key]), value, rtol=1e-12, atol=1e-12, equal_nan=True), (got['experiment_id'],key)
        else:
            assert got[key] == str(value), (got['experiment_id'],key)

# A future sample can have different joint-factor and baseline supports.
# Do not make the observed agreement of those moments a hardcoded gate.
with tempfile.TemporaryDirectory() as tmp:
    folder = Path(tmp) / 'fixture'
    (folder / 'Figures').mkdir(parents=True)
    (folder / 'CTREND').mkdir()
    bars = {'type': 'specgraph.barseries', 'properties': {'XData': [1,2,3,4], 'YData': [9.,2.,3.,4.]}}
    for n in (1,2):
        savemat(folder / f'Figures/b06Table3_UnivariatePortfolioSorts_figure0{n}.fig', {'hgS_070000': bars})
    savemat(folder / 'CTREND/CTREND_Base.mat', {'vDates':[202001,202002,202003],
            'cResults':{'VW':{'mPortRet':np.tile([.01,.02,.03],(6,1))}}})
    assert factor_companion(Path(tmp), 'fixture')[0]['ctrend_moments_match'] == 0
    bars['properties']['XData'] = [1,1,3,4]
    bad = folder / 'bad.fig'
    savemat(bad, {'hgS_070000':bars})
    try:
        figure_bars(bad)
        raise AssertionError('Duplicate bars were accepted')
    except ValueError:
        pass

with (ROOT / 'annotated_sources/BODY_IDENTITIES.csv').open() as f:
    bodies = len(list(csv.DictReader(f)))
with (ROOT / 'annotated_sources/ANNOTATION_INDEX.csv').open() as f:
    blocks = len(list(csv.DictReader(f)))
assert f'{bodies:,} bodies and {blocks:,} lineage blocks' in (ROOT/'docs/AUDIT_AND_ANNOTATIONS.md').read_text()
assert (ROOT/'tests/result_checks/run_publication_checks.sh').is_file()
assert (ROOT/'docs/FULL_RESULT_ACCESS.md').is_file()
print('PUBLICATION_EVIDENCE_OK paper=1 published_factor=1 nineteen_way=1 pairwise=1 citations=1 factor_companions=1 dynamic_support=1 independent_audit=1')
