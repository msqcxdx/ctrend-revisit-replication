#!/usr/bin/env python3
"""Check active local report links, statuses and per-output source hashes.

This is a packaging consistency check, not an economic-result significance
gate. Paused E12 files are outside its scope. Markdown links to external web
sources are retained as citations and are not queried by this offline test.
"""
import csv
import json
from pathlib import Path
import re
from urllib.parse import unquote
from validate_followup_artifacts import ROOT,OUT,SCRIPTS,ACTIVE,digest


def main():
    issues=[];links=0
    docs=list(ROOT.glob('*.md'))
    for eid in ACTIVE:
        docs.extend((OUT/eid).glob('*.md'))
    for path in docs:
        if 'E12' in path.name:continue
        body=path.read_text()
        for target in re.findall(r'\[[^\]]*\]\(([^)]+)\)',body):
            target=unquote(target.split('#')[0])
            if not target or re.match(r'^[a-zA-Z]+://',target):continue
            links+=1
            if not (path.parent/target).exists():issues.append(f'{path.name}: missing {target}')
    with (ROOT/'ARTIFACT_ACCEPTANCE.csv').open() as f:acceptance=list(csv.DictReader(f))
    with (ROOT/'EXPERIMENT_REGISTER.csv').open() as f:registry={r['experiment_id']:r for r in csv.DictReader(f)}
    if {r['experiment_id'] for r in acceptance}!=set(ACTIVE):issues.append('Active acceptance set')
    for r in acceptance:
        m=json.loads((OUT/r['experiment_id']/'ARTIFACT_MANIFEST.json').read_text())
        if r['scientific_status']!=registry[r['experiment_id']]['status'] or m['scientific_status']!=r['scientific_status']:
            issues.append(f'Scientific status mismatch {r["experiment_id"]}')
        for s in m['scripts']:
            if digest(ROOT/s['path'])!=s['sha256']:issues.append(f'Script changed after validation: {s["path"]}')
        for a in m['outputs']:
            if digest(OUT/r['experiment_id']/a['relative_path'])!=a['sha256']:
                issues.append(f'Artifact changed after validation: {r["experiment_id"]}/{a["relative_path"]}')
    if issues:raise AssertionError('\n'.join(issues))
    print(f'FOLLOWUP_DOCUMENTATION_OK local_links={links} active_experiments={len(acceptance)} E12=excluded')


if __name__=='__main__':main()
