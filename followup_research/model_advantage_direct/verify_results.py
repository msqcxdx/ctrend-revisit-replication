#!/usr/bin/env python3
"""Check saved aggregate identities and, optionally, a same-seed recalculation.

Uses only the standard library and public summaries. It does not need vendor
inputs, start MATLAB, estimate models, or certify any economic assumption.
"""
import argparse
import csv
import hashlib
import json
import math
from pathlib import Path


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def verify(root,compare=None):
    receipt=json.loads((root/'RUN_RECEIPT.json').read_text())
    for name,expected in receipt['result_files'].items():
        assert digest(root/name)==expected, name
        if compare is not None:
            assert digest(compare/name)==expected, f'non-reproducible CSV: {name}'
    for name,expected in receipt['source_scripts_sha256'].items():
        assert digest(Path(__file__).parent/name)==expected, f'script identity: {name}'
    assert digest(Path(__file__).parent/'PROTOCOL_CN.md')==receipt['protocol_sha256']
    assert receipt['isolated_inputs_before']==receipt['isolated_inputs_after']
    assert receipt['source_inputs']['all_18_baselines_match_saved_csv']
    assert receipt['source_inputs']['external_LTW_identical_across_all_PD']
    assert not receipt['model_training_performed'] and not receipt['existing_results_overwritten']
    def read(name):
        with (root/f'{name}.csv').open(newline='') as f: return list(csv.DictReader(f))
    def key(r): return r['P'],r['D'],r['factor_source'],r['block_weeks']
    def close(a,b): assert math.isclose(float(a),float(b),abs_tol=1e-10,rel_tol=1e-9),(a,b)
    levels={(key(r),r['method']):r for r in read('advantage_levels')}
    groups={key(r) for r in read('advantage_levels')}
    assert len(groups)==receipt['settings']*len(receipt['blocks'])
    for group in groups:
        rows=[levels[group,m] for m in ('M0','M2','M1')]
        assert len({r['n_common'] for r in rows})==1
        for r in rows:
            close(r['s2_ltw'],rows[0]['s2_ltw'])
            close(r['estimate'],float(r['s2_trend'])-float(r['s2_ltw']))
    for r in read('advantage_changes'):
        close(r['estimate'],float(levels[key(r),r['after']]['estimate'])-
              float(levels[key(r),r['before']]['estimate']))
        if not r['inference_status'].startswith('regular'):
            assert math.isnan(float(r['p_two_sided']))
        assert int(r['bootstrap_valid'])+int(r['bootstrap_invalid'])==receipt['replicates']
    for r in read('incremental_decomposition'):
        close(float(r['v_ct'])-float(r['v_mom']),levels[key(r),r['method']]['estimate'])
        close(r['v_ct'],(float(r['alpha_ct_weekly_pct'])/float(r['residual_ct_sd_weekly_pct']))**2)
        close(r['v_mom'],(float(r['alpha_mom_weekly_pct'])/float(r['residual_mom_sd_weekly_pct']))**2)
    support={}
    for r in read('support_calendar'):
        group=(r['P'],r['D'],r['factor_source'])
        support[group]=support.get(group,0)+int(r['included_main'])
        assert int(r['included_main'])==all(int(v) for k,v in r.items() if k.startswith('finite_'))
    for group in groups: assert support[group[:3]]==int(levels[group,'M0']['n_common'])
    for r in read('legacy_reconciliation'):
        close(r['recomputed_E03_d'],r['saved_E03_d'])
        assert float(r['existing_OOS_max_abs_difference'])<1e-9
    e04=read('e04_reconciliation')
    assert len(e04)==18 and all(r['status'].startswith('matched_E04') for r in e04)
    print(f'MODEL_ADVANTAGE_RESULTS_OK settings={receipt["settings"]} files={len(receipt["result_files"])} '
          f'same_seed_recalculation={int(compare is not None)}')


if __name__=='__main__':
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('--results',type=Path,default=Path(__file__).parent/'results')
    p.add_argument('--compare',type=Path)
    args=p.parse_args();verify(args.results,args.compare)
