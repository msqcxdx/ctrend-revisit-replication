#!/usr/bin/env python3
"""Validate and compress the observed E10 asset ledgers without dropping rows.

Checks fully invested legs, no undisclosed new cohort members, drifted end to
next opening continuity, and original-phase identity. Empty trade files are
valid only if the corresponding actual exit counters are all zero. A separate
synthetic test exercises nonempty sale/recipient transactions.
"""
import csv
import gzip
from itertools import groupby
import json
import math
from pathlib import Path
import shutil
from run_e06_upstream_hybrids import ROOT,sha


def compress(path):
    target=path.with_suffix(path.suffix+'.gz');temporary=target.with_suffix('.partial')
    with path.open('rb') as src,temporary.open('wb') as raw:
        with gzip.GzipFile(fileobj=raw,mode='wb',filename='',mtime=0,compresslevel=6) as dst:
            shutil.copyfileobj(src,dst,2**20)
    temporary.replace(target)
    # Retain the uncompressed diagnostic files as well; no accepted input is
    # removed by this packaging step. Both representations have manifests.
    return dict(path=target.name,sha256=sha(target),size_bytes=target.stat().st_size)


def main():
    out=ROOT/'outputs/E10';receipt=dict(status='pass',experiments=[],observer_return_equality='asserted_in_each_MATLAB_run')
    for p in (0,1):
        for d in (0,1,2):
            eid=f'P{p}_M1_D{d}'
            table=list(csv.DictReader((out/(eid+'_weekly_holding.csv')).open()))
            key=lambda r:tuple(int(r[k]) for k in ('holding_weeks','phase','year_week'))
            states={key(r):r for r in table};counts=0;groups=0;prior={};cohort={}
            path=out/(eid+'_cohort_asset_weights.csv')
            with path.open(newline='') as f:
                for state,rr in groupby(csv.DictReader(f),key):
                    rows=list(rr);counts+=len(rows);groups+=1
                    h,phase,week=state;main=states[state];formed=int(rows[0]['cohort_formation_week'])
                    if formed!=int(main['cohort_formation_week']):raise ValueError('Cohort phase mismatch')
                    ids=[int(r['cmcid']) for r in rows]
                    if len(set(ids))!=len(ids):raise ValueError('Duplicate cohort asset')
                    ckey=(h,phase,formed)
                    if ckey not in cohort:cohort[ckey]=set(ids)
                    if not set(ids)<=cohort[ckey]:raise ValueError('Undeclared new cohort member')
                    for leg in ('low','high'):
                        opening={int(r['cmcid']):float(r[leg+'_opening_weight']) for r in rows}
                        ending={int(r['cmcid']):float(r[leg+'_end_weight']) for r in rows}
                        if abs(sum(opening.values())-1)>1e-10:raise ValueError('Opening leg does not sum to 1')
                        if int(main['payoff_complete']) and abs(sum(ending.values())-1)>1e-10:
                            raise ValueError('Ending leg does not sum to 1')
                        prev=prior.get((h,phase,leg))
                        if prev and prev[0]==formed and prev[1]:
                            for aid in set(opening)|set(prev[2]):
                                if abs(opening.get(aid,0)-prev[2].get(aid,0))>1e-10:
                                    raise ValueError('Unannounced within-cohort rebalance')
                        prior[(h,phase,leg)]=(formed,bool(int(main['payoff_complete'])),ending)
            trade_path=out/(eid+'_cohort_reinvestment_trades.csv')
            trades=list(csv.DictReader(trade_path.open()))
            exits=sum(int(r['exit_holding_count']) for r in table)
            if not trades and exits:raise ValueError('Missing observed terminal transactions')
            if trades:
                sums={}
                for r in trades:
                    k=key(r)+(int(r['leg']),int(r['event_date']))
                    sums[k]=sums.get(k,0)+float(r['signed_trade_value'])
                if any(abs(v)>1e-8 for v in sums.values()):raise ValueError('Unbalanced event transactions')
            receipt['experiments'].append(dict(experiment_id=eid,asset_rows=counts,
                formed_leg_week_pairs=groups,trade_rows=len(trades),recorded_exit_holdings=exits,
                asset_csv_sha256=sha(path),trade_csv_sha256=sha(trade_path),compressed=compress(path)))
            print(f'E10_LEDGER_VERIFIED {eid} asset_rows={counts} trades={len(trades)}',flush=True)
    (out/'COHORT_LEDGER_RECEIPT.json').write_text(json.dumps(receipt,indent=2)+'\n')


if __name__=='__main__':main()
