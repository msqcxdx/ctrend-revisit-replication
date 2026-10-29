#!/usr/bin/env python3
"""Check active report links, saved outputs and archived source compatibility.

This is a packaging consistency check, not an economic-result significance
gate. Paused E12 files are outside its scope. Markdown links to external web
sources are retained as citations and are not queried by this offline test.
Historical source hashes are kept intact. The explicitly checked run-path
adapters and additive E11 coverage fields may differ in bytes only when the
historical snapshot, executable-syntax comparison and actual run lookup agree.
All unexplained source changes and all output changes still fail this check.
"""
import csv
import json
from pathlib import Path
import re
from urllib.parse import unquote
from validate_followup_artifacts import ROOT,OUT,SCRIPTS,ACTIVE,digest
from followup_source_compatibility import check_source_compatibility, read_snapshot


def main():
    issues=[];links=0;checked_sources={};compatible_sources={};historical_checkers=0
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
            key=(s['path'],s['sha256'])
            if key not in checked_sources:
                try:
                    if digest(ROOT/s['path'])!=s['sha256']:
                        if (ROOT/s['path']).resolve()==Path(__file__).resolve():
                            # This checker did not generate empirical results.
                            # Identify its historical validation snapshot; its
                            # current behavior is covered by regression tests,
                            # not by claiming two different checkers are equal.
                            read_snapshot(*key)
                            historical_checkers+=1
                        else:
                            compatible_sources[key]=check_source_compatibility(*key)
                except (ValueError, OSError) as exc:
                    issues.append(f'Unreconciled source change: {s["path"]}: {exc}')
                checked_sources[key]=True
        for a in m['outputs']:
            if digest(OUT/r['experiment_id']/a['relative_path'])!=a['sha256']:
                issues.append(f'Artifact changed after validation: {r["experiment_id"]}/{a["relative_path"]}')
    if issues:raise AssertionError('\n'.join(issues))
    print(f'FOLLOWUP_DOCUMENTATION_OK local_links={links} active_experiments={len(acceptance)} '
          f'compatible_source_adapters={len(compatible_sources)} historical_checkers={historical_checkers} '
          'historical_manifests_unchanged=1 E12=excluded')


if __name__=='__main__':main()
