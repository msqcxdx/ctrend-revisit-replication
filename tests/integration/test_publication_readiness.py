#!/usr/bin/env python3
# CTREND_REVISIT_FILE_PURPOSE: Validate bilingual entry documentation, portable links, engineering purpose headers and absence of manuscripts.
# Repository-hygiene contract only: verify reader navigation, portable links,
# required terminology, English/Chinese boundaries, and excluded manuscript
# formats.  Empirical acceptance is performed by result_checks, not here.
from pathlib import Path
import re
R=Path(__file__).resolve().parents[2]
docs=['README.md','README_CN.md','RUNBOOK.md','REPRODUCTION_GUIDE_CN.md','docs/REPOSITORY_MAP.md','docs/OUTPUTS_AND_INTERPRETATION.md',
 'docs/METHOD_BOUNDARIES.md','docs/ISSUE_AND_CORRECTION_REGISTER.md','docs/AUDIT_AND_ANNOTATIONS.md',
 'analysis/README.md','results/README.md','results/comparisons/NINETEEN_WAY_FULL_REPORT_CN.md']
broken=[]
for rel in docs:
 p=R/rel;assert p.is_file() and p.stat().st_size
 for link in re.findall(r'\[[^\]]+\]\(([^)]+)\)',p.read_text()):
  link=link.strip('<>').split('#',1)[0]
  if not link or '://' in link or link.startswith('mailto:'):continue
  if not (p.parent/link).exists():broken.append((rel,link))
assert not broken,broken
report=(R/'results/comparisons/NINETEEN_WAY_FULL_REPORT_CN.md').read_text()
for location in re.findall(r'PDF pp?\.([0-9–]+)（期刊 p{1,2}\.([0-9–]+)）',report):
 physical,printed=([int(x) for x in part.split('–')] for part in location)
 assert physical==[x-3115 for x in printed],location
assert 'PDF p.2（期刊 p.3117）' in report
assert (R/'results/comparisons/PAPER_ITEM_LOCATIONS.csv').is_file()
for root in ['scripts','tests','analysis','postprocessing','p0_extension/scripts','p0_extension/tests']:
 # Every project-authored executable must explain its role near the file top.
 for p in (R/root).rglob('*'):
  if not p.is_file() or p.suffix not in {'.sh','.py','.m','.bat'}:continue
  assert 'CTREND_REVISIT_FILE_PURPOSE:' in '\n'.join(p.read_text().splitlines()[:8]),p
readme=(R/'README.md').read_text()
for token in ['P0_M0_D0','P0_M2_D0','P0_M1_D0','P1_M1_D1','all production','b20',
 '337','INNBCL','78.92%','63.2%','3,072','announcement-time','README_CN.md']:
 assert token in readme,token
assert re.search(r'[\u3400-\u9fff]',(R/'README_CN.md').read_text())
assert not re.search(r'[\u3400-\u9fff]',readme)
assert not re.search(r'[\u3400-\u9fff]',(R/'RUNBOOK.md').read_text())
for p in R.rglob('*'):
 if not p.is_file() or '.git' in p.parts or 'runtime' in p.parts or 'outputs' in p.parts:continue
 assert p.suffix.lower() not in {'.pdf','.doc','.docx'},p
 assert 'manuscript' not in p.name.lower(),p
print('PUBLICATION_READINESS_OK bilingual_readme=1 english_runbook=1 portable_links=1 no_manuscripts=1')
