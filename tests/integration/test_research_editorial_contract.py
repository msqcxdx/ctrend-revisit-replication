#!/usr/bin/env python3
# CTREND_REVISIT_FILE_PURPOSE: Check standalone research prose, Markdown table structure and display-only numeric formatting.
"""Editorial checks do not assert empirical values or alter numerical results."""
# The checks below cover wording independence, table parseability, and display
# rounding only.  They deliberately do not turn rounded prose values into
# empirical acceptance thresholds.
from pathlib import Path
import re
import sys

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'analysis'))
from publication_style import display_cell, format_tables

docs = [ROOT / name for name in (
    'README.md', 'README_CN.md', 'RUNBOOK.md', 'STUDY_OVERVIEW.md',
    'ORIGINAL_DATAVERSE_CODE_COMPARISON.md', 'p0_extension/README.md',
    'p0_extension/DERIVATION.md', 'analysis/README.md', 'results/README.md',
    'postprocessing/README.md', 'tests/README.md')]
docs += sorted((ROOT / 'docs').glob('*.md'))
docs += sorted((ROOT / 'results/comparisons').rglob('*.md'))
iteration = re.compile(
    r'previous version|earlier version|first[- ]edition|superseded|'
    r'new-v2|current release|current version|legacy version|'
    r'上一个版本|上一版|上个版本|旧版|新版|第一版|本轮|这一轮|版本迭代', re.I)
for path in docs:
    text = path.read_text()
    prose = re.sub(r'```.*?```', '', text, flags=re.S)
    prose = re.sub(r'`[^`]*`', '', prose)
    assert not iteration.search(prose), (path, iteration.search(prose))
    assert len(re.findall(r'^# ', prose, re.M)) == 1, path
    width = None
    for line in text.splitlines():
        if line.startswith('|') and line.endswith('|'):
            cells = re.split(r'(?<!\\)\|', line[1:-1])
            if width is None:
                width = len(cells)
            assert len(cells) == width, (path, line)
        else:
            width = None

assert display_cell('0.123456789') == '0.1235'
assert display_cell('-0.0000001') == '0.0000'
for token in ['P0_M1_D2', '3072', 'NaN', '202016', '3.91 (5.14)']:
    assert display_cell(token) == token
example = '| label | start_year_week | value |\n|---|---|---|\n| H\\|L | 202016 | 1.23456789 |\n'
formatted = format_tables(example)
assert '| H\\|L | 2020W16 | 1.2346 |' in formatted
assert format_tables('| ID | value |\n|---|---|\n| P0_M1_D2 | 3072 |\n').endswith('| P0_M1_D2 | 3072 |\n')
print(f'RESEARCH_EDITORIAL_CONTRACT_OK documents={len(docs)} standalone_prose=1 table_structure=1 display_only=1')
