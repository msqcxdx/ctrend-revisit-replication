#!/usr/bin/env python3
"""Accept E01--E11 artifacts and scientific counterexample tests separately.

Calendar/design counts come from authenticated parents, not observed Sharpe
values or convenient week counts. Partial identification stays partial even
when every file passes. E12 is excluded: do not read/write its output tree.
All source and artifact writes remain inside the isolated follow-up directory.
"""
from __future__ import annotations
import csv
import gzip
import hashlib
import json
import os
from pathlib import Path
import subprocess
import sys
import numpy as np
from scipy.io import loadmat

ROOT=Path(__file__).resolve().parents[1]
REPO=ROOT.parent
OUT=ROOT/'outputs'
SCRIPTS=ROOT/'scripts'
BASE_COMMIT='c35b257f45fae3a52d32abddc6e05476343a20f6'
PLAN_SHA='c41d4bf0f4cc985fbf85b80358f84b4855cc735b04086c6ec57d9f7b1eb869ed'
ACTIVE=tuple(f'E{i:02}' for i in range(1,12))
REQUIRED={
'E01':'eight_mixed_benchmarks.csv factor_source_summary.csv paired_benchmark_alpha_difference.csv external_workbook_metadata_audit.json coauthor_workbook_distribution_receipt.json E01_SUMMARY_CN.md',
'E02':'grs_argument_and_system_audit.csv',
'E03':'dual_increment_and_four_models.csv paired_52week_oos_summary.csv paired_52week_oos_weekly.csv paired_52week_oos_weights.csv paired_52week_oos_min26_summary.csv nonnested_squared_sharpe_hac.csv economic_equivalence_threshold_curve.csv',
'E04':'paired_method_differences.csv paired_risk_distribution.csv support_block_sensitivity.csv support_calendar_audit.csv',
'E05':'formation_snapshot_and_future_availability_perturbation.csv formation_channel_summary.csv P0_M1_D1_production_b05_future_perturbation.csv P0_M2_D1_production_b05_future_perturbation.csv production_b02_daily_future_perturbation.csv production_b02_daily_future_perturbation_extended.csv receipts/b02_remaining_10cells_receipt.json raw_internal_close_gaps_14d_asset_exposure.csv raw_internal_gap_held_week_details.csv raw_internal_close_gaps_14d_receipt.json raw_to_baseline_future_terminal_weekly.csv raw_to_baseline_future_terminal_receipt.json held_gap_external_quote_evidence.csv held_gap_external_quote_receipt.json ardor_bitswift_2018W02_held_week_trades.csv ardor_bitswift_2018W02_receipt.json E05_HELD_GAP_EXTERNAL_EVIDENCE_CN.md',
'E06':'ordered_weight_payoff_mechanism.csv HYBRID_RECEIPT.json hybrid_baseline_summary.csv hybrid_baseline_weekly.csv hybrid_paired_effects.csv hybrid_forecast_to_holdings_weekly.csv hybrid_forecast_to_holdings_summary.csv sensitivity_grid_common_week.csv sensitivity_grid_module_effects.csv E06_SENSITIVITY_GRID_CN.md SENSITIVITY_GRID_RECEIPT.json sensitivity_innbcl_2020W16.csv SENSITIVITY_INNBCL_RECEIPT.json',
'E07':'asset_week_forecast_holding_stages.csv.gz weekly_forecast_holding_stage_counts.csv asset_stage_export_receipt.json weekly_forecast_to_holdings.csv paired_m2_m1_forecast_weights_payoff.csv forecast_group_summary.csv forecast_coverage_weight_switch_by_week.csv key_week_asset_forecast_weight_transitions.csv controlled_coverage_weighting_by_week.csv controlled_coverage_weighting_summary.csv controlled_coverage_same_calendar.csv raw_label_vs_economic_payoff_rank_ic.csv key_week_model_support_diagnostics.csv key_week_model_support_summary.csv key_week_model_support_receipt.json native_failure_audit/EXPORT_RECEIPT.json native_failure_audit/full_baseline_field_equality.csv E07_PREDICTOR_CAUSE_EVIDENCE_CN.md',
'E08':'asset_week_direct_contributions.csv.gz weekly_concentration_and_reconciliation.csv top_100_positive_and_negative_asset_week_contributions.csv event_evidence_catalog.csv binance_cocos_exchange_window_20210114_20210124.csv binance_cocos_exchange_window_receipt.json innbcl_project_swap_chronology_2020.csv innbcl_project_swap_chronology_receipt.json innbcl_contract_creation_chronology.csv innbcl_contract_creation_receipt.json E08_PRIORITY_EVENT_ADJUDICATION_CN.md',
'E09':'fixed_transaction_fee_statistical_factor.csv conditional_borrow_fee_scenarios_not_account.csv opening_liquidity_proxy_by_leg_week.csv opening_liquidity_proxy_summary.csv fixed_holdings_cost_accounting_weekly.csv fixed_holdings_cost_accounting_summary.csv E09_HISTORICAL_TRADING_DATA_EVIDENCE_CN.md',
'E10':'all_phases_holding_comparison.csv published_ledger_vs_fixed_cohort.csv all_phase_envelopes.csv symmetric_cohort_tail_differences.csv COHORT_LEDGER_RECEIPT.json observation_test.log',
'E11':'accepted_run_paths.csv paired_design_summary.csv paired_design_ltw_alpha_summary.csv paired_method_by_market_state.csv formation_known_market_states.csv p0_primary_method_family_holm.csv prediction_opportunity_receipt.json prediction_opportunity_grid_summary.csv',
}


def digest(path):
    h=hashlib.sha256()
    with Path(path).open('rb') as f:
        for b in iter(lambda:f.read(2**20),b''):h.update(b)
    return h.hexdigest()


def rows(path):
    with Path(path).open(newline='',encoding='utf-8') as f:return list(csv.DictReader(f))


def require_hash(path,expected):
    if digest(path)!=expected:raise ValueError(f'Hash mismatch: {path}')


def count_csv(path):
    opener=gzip.open if path.suffix=='.gz' else open
    with opener(path,'rt',newline='',encoding='utf-8') as f:
        r=csv.reader(f)
        if not next(r,None):raise ValueError(f'CSV header missing: {path}')
        return sum(1 for _ in r)


def research_receipts():
    audited=[]
    for name,item in json.loads((ROOT/'AUDIT_RUNS.json').read_text()).items():
        path=Path(item['receipt'])
        if not path.is_absolute():path=REPO/path
        r=json.loads(path.read_text())
        if r['status']!=item['required_status']:raise ValueError(f'Incomplete audit: {name}')
        for source in r.get('inputs',[]):
            for file,sha in source.get('sha256',source.get('files',{})).items():require_hash(file,sha)
        for result in r.get('results',[]):
            for file,sha in result.get('accepted_input_hashes',{}).items():require_hash(file,sha)
        audited.append(dict(name=name,path=str(path),sha256=digest(path),research_run_id=r['research_run_id'],status=r['status']))
    h=json.loads((OUT/'E06/HYBRID_RECEIPT.json').read_text())
    for r in h['runs']:
        require_hash(r['path'],r['sha256']);state=json.loads(Path(r['path']).read_text())
        if state['status']=='failed':raise ValueError('Failed hybrid registered')
        for file,sha in state.get('inputs',{}).items():require_hash(file,sha)
    for r in h['results'].values():require_hash(r['path'],r['sha256'])
    return audited


def new_e05_receipts(byid,T):
    """Check new raw-gap and raw-to-baseline work without deciding its finding."""
    gap=json.loads((OUT/'E05/raw_internal_close_gaps_14d_receipt.json').read_text())
    p0=byid['P0_M1_D1'];p1=byid['P1_M1_D1']
    p1run=Path(p1['accepted_run_root'])
    def one_parent_data(name):
        paths=[p1run/part/name for part in ('data','data.staging') if (p1run/part/name).is_file()]
        if len(paths)!=1:raise ValueError(f'E05 parent data ambiguous: {name}')
        return paths[0]
    expected={
        'raw_close_sha256':one_parent_data('close_cmc.csv'),
        'p1_b0_sha256':one_parent_data('b0DataOLHC.mat'),
        'p0_base_sha256':Path(p0['result_root'])/'CTREND/CTREND_Base.mat',
        'p1_base_sha256':Path(p1['result_root'])/'CTREND/CTREND_Base.mat',
        'p0_run_complete_sha256':Path(p0['accepted_run_root'])/'RUN_COMPLETE',
        'p1_run_complete_sha256':p1run/'RUN_COMPLETE',
    }
    for key,path in expected.items():require_hash(path,gap['inputs'][key])
    gap_csv=OUT/'E05/raw_internal_close_gaps_14d_asset_exposure.csv'
    detail_csv=OUT/'E05/raw_internal_gap_held_week_details.csv'
    require_hash(gap_csv,gap['output_sha256'])
    require_hash(detail_csv,gap['held_week_detail_sha256'])
    if count_csv(gap_csv)!=gap['gap_rows']:
        raise ValueError('E05 gap count mismatch')
    if count_csv(detail_csv)!=gap['held_asset_gap_week_rows']:
        raise ValueError('E05 held-gap detail count mismatch')
    chain=json.loads((OUT/'E05/raw_to_baseline_future_terminal_receipt.json').read_text())
    if chain['status']=='failed' or chain['parent']['experiment_id']!='P1_M1_D1':
        raise ValueError('E05 raw chain failed or has wrong parent')
    if chain['parent']['run_complete_sha256']!=p1['run_complete_sha256']:
        raise ValueError('E05 raw chain parent identity')
    require_hash(SCRIPTS/'run_e05_raw_to_baseline_availability.py',chain['driver_sha256'])
    require_hash(Path(chain['work_root'])/'receipt.json',chain['source_receipt_sha256'])
    for path,sha in chain['parent_hashes_before'].items():require_hash(path,sha)
    for variant in ('control','future_terminal'):
        result=chain[variant]
        prefix=Path(chain['work_root'])/variant/'source'
        require_hash(prefix/'Results/CTREND/CTREND_Base.mat',result['result_sha256'])
        require_hash(prefix/'DATA/b0DataOLHC.mat',result['generated_b0_sha256'])
        require_hash(prefix/'DATA/bCharacteristicsOLHC_Combo1.mat',result['generated_weekly_sha256'])
        for name,sha in result['raw_input_hashes'].items():require_hash(prefix/'DATA'/name,sha)
    weekly=OUT/'E05/raw_to_baseline_future_terminal_weekly.csv'
    require_hash(weekly,chain['weekly_sha256'])
    if count_csv(weekly)!=T:raise ValueError('E05 raw-chain calendar count')
    if chain['control_last_quote_date']==chain['shock_last_quote_date']:
        raise ValueError('E05 terminal intervention ineffective')
    ext=json.loads((OUT/'E05/held_gap_external_quote_receipt.json').read_text())
    if ext['rows']!=6 or ext['matched_external_audit_rows']!=3:
        raise ValueError('E05 external held-gap audit coverage')
    require_hash(OUT/'E05/raw_internal_gap_held_week_details.csv',ext['held_parent']['sha256'])
    for name,sha in ext['external_parents'].items():
        require_hash(OUT/'E05/source_evidence'/name,sha)
    for name,sha in ext['output'].items():require_hash(OUT/'E05'/name,sha)
    quoted=rows(OUT/'E05/held_gap_external_quote_evidence.csv')
    if len(quoted)!=6 or {int(r['cmcid']) for r in quoted}!={184,659,1037,1454,3949,7096}:
        raise ValueError('E05 six held-gap identity set')
    if any(r['external_held_week_quote_days'] for r in quoted if r['audit_status']=='not_in_frozen_external_audit'):
        raise ValueError('E05 non-audited quote cells must remain empty')
    onchain=json.loads((OUT/'E05/ardor_bitswift_2018W02_receipt.json').read_text())
    source=OUT/'E05/source_evidence/ardor_bitswift_2018W02'
    require_hash(source/'coin_exchange_trades_chain1_exchange4_1170_1210.json',onchain['raw_response_sha256'])
    require_hash(source/'matching_block_responses.json',onchain['block_response_sha256'])
    require_hash(OUT/'E05/ardor_bitswift_2018W02_held_week_trades.csv',
                 onchain['output']['ardor_bitswift_2018W02_held_week_trades.csv'])
    trades=rows(OUT/'E05/ardor_bitswift_2018W02_held_week_trades.csv')
    if len(trades)!=8 or onchain['output']['rows']!=len(trades) or onchain['held_week_matches']!=8 or \
            onchain['matches_on_cmc_missing_day_2018_01_14']!=2 or \
            sum(r['utc'].startswith('2018-01-14') for r in trades)!=2 or \
            any((r['cmcid'],r['chain'],r['exchange'],r['usd_price'])!=('659','1','4','') for r in trades):
        raise ValueError('E05 on-chain Bitswift evidence boundary')
    return {'raw_internal_close_gaps_14d_asset_exposure.csv':gap['gap_rows'],
            'raw_internal_gap_held_week_details.csv':gap['held_asset_gap_week_rows'],
            'raw_to_baseline_future_terminal_weekly.csv':T,
            'held_gap_external_quote_evidence.csv':6,
            'ardor_bitswift_2018W02_held_week_trades.csv':8}


def new_e08_cocos_source(byid):
    """Check frozen one-venue COCOS evidence without treating it as a CMC repair."""
    receipt=json.loads((OUT/'E08/binance_cocos_exchange_window_receipt.json').read_text())
    source=OUT/'E08/source_evidence/binance_cocos_20210114_20210124'
    status=source/'HTTP_STATUS.json'
    require_hash(status,receipt['source_status_sha256'])
    responses=json.loads(status.read_text())['responses']
    if len(responses)!=11 or sum(r['http_status']==200 for r in responses)!=8 or \
            receipt['source_zip_count']!=8 or \
            receipt['official_archive_missing_dates']!=['2021-01-20','2021-01-21','2021-01-22']:
        raise ValueError('E08 official archive window')
    for item in responses:
        if item['http_status']==200:
            require_hash(source/item['file'],item['sha256'])
        elif item['http_status']!=404 or item['file'] is not None:
            raise ValueError('E08 unexpected archive status')
    parent=REPO/'results/diagnostics/p0_selected_week_asset_audit/P0_KEY_WEEK_ASSET_METHOD_ROWS.csv.gz'
    require_hash(parent,receipt['accepted_cmc_asset_week_parent_sha256'])
    if receipt['accepted_cmc_endpoint']['research_run_id']!=byid['P0_M1_D0']['research_run_id'] or \
            receipt['observed_old_close_to_new_open_ratio']!=1000.0:
        raise ValueError('E08 accepted parent identity or exchange ratio')
    require_hash(OUT/'E08/binance_cocos_exchange_window_20210114_20210124.csv',
                 receipt['output']['binance_cocos_exchange_window_20210114_20210124.csv'])
    daily=rows(OUT/'E08/binance_cocos_exchange_window_20210114_20210124.csv')
    if len(daily)!=11 or receipt['output']['rows']!=len(daily) or \
            daily[5]['close_time_utc']!='2021-01-19T01:59:59.999000+00:00' or \
            daily[7]['archive_http_status']!='404' or daily[9]['open_usdt']!='0.69500000':
        raise ValueError('E08 daily archive audit data')
    chronology=json.loads((OUT/'E08/innbcl_project_swap_chronology_receipt.json').read_text())
    require_hash(OUT/'E08/source_evidence/innbcl_project_2020/bitcointalk_topic_5242368_page1.html',
                 chronology['raw_html_sha256'])
    path=OUT/'E08/innbcl_project_swap_chronology_2020.csv'
    require_hash(path,chronology['output_csv_sha256'])
    timeline=rows(path)
    if len(timeline)!=2 or chronology['rows']!=2 or \
            [r['post_id'] for r in timeline]!=['54369970','54617317'] or \
            any(r['event_day_in_april_proven']!='no' for r in timeline):
        raise ValueError('E08 INNBCL chronology scope')
    contract_receipt=json.loads((OUT/'E08/innbcl_contract_creation_receipt.json').read_text())
    contract_source=OUT/'E08/source_evidence/innbcl_contract_chronology'
    for name,sha in contract_receipt['source_hashes'].items():
        require_hash(contract_source/name,sha)
    contract_path=OUT/'E08/innbcl_contract_creation_chronology.csv'
    require_hash(contract_path,contract_receipt['output_csv_sha256'])
    contracts=rows(contract_path)
    if len(contracts)!=2 or contract_receipt['rows']!=2 or \
            [r['contract_role'] for r in contracts]!=['old','new'] or \
            [r['created_utc'] for r in contracts]!=[
                '2019-02-05T19:10:10+00:00','2020-05-18T07:11:59+00:00'] or \
            [r['before_2020_04_16'] for r in contracts]!=['true','false'] or \
            [r['token_decimals'] for r in contracts]!=['10','6']:
        raise ValueError('E08 INNBCL on-chain creation chronology')
    return {'binance_cocos_exchange_window_20210114_20210124.csv':11,
            'innbcl_project_swap_chronology_2020.csv':2,
            'innbcl_contract_creation_chronology.csv':2}


def new_e06_sensitivities(T,byid):
    """Validate independent baseline A/B/C+D refits over all six P/D cells."""
    counts={}
    for p in (0,1):
        for d in (0,1,2):
            eid=f'P{p}_M2_D{d}'
            if eid=='P0_M2_D1':continue  # Original, separately accepted E06 run.
            root=OUT/'E06/sensitivities'/eid
            receipt=json.loads((root/'HYBRID_RECEIPT.json').read_text())
            if receipt['experiment_id']!=eid or receipt['scope']!=eid+'_baseline_only':
                raise ValueError(f'E06 sensitivity identity: {eid}')
            if len(receipt['runs'])!=2:
                raise ValueError(f'E06 incomplete run pair: {eid}')
            states=[]
            for run in receipt['runs']:
                require_hash(run['path'],run['sha256'])
                state=json.loads(Path(run['path']).read_text())
                if state['experiment_id']!=eid or state['research_run_id']!=run['research_run_id']:
                    raise ValueError(f'E06 manifest identity: {eid}')
                for file,sha in state.get('inputs',{}).items():require_hash(file,sha)
                states.append(state)
            ab,cd=states
            if ab['status']!='AB_factorial_complete_CDE_not_yet_run' or \
                    cd['status']!='CD_and_ABCD_complete_not_full_M1':
                raise ValueError(f'E06 refit phase incomplete: {eid}')
            if ab['parent']['research_run_id']!=byid[eid]['research_run_id'] or \
                    ab['parent']['run_complete_sha256']!=byid[eid]['run_complete_sha256'] or \
                    cd['ab_manifest_sha256']!=receipt['runs'][0]['sha256']:
                raise ValueError(f'E06 parent chain differs: {eid}')
            if set(receipt['results'])!={'control','A','B','AB','CD','ABCD','accepted_M1'}:
                raise ValueError(f'E06 missing module result: {eid}')
            for result in receipt['results'].values():require_hash(result['path'],result['sha256'])
            expected={'hybrid_baseline_weekly.csv':7*T,
                'hybrid_baseline_summary.csv':7*3,
                'hybrid_paired_effects.csv':9*2,
                'hybrid_forecast_to_holdings_weekly.csv':6*T,
                'hybrid_forecast_to_holdings_summary.csv':6}
            for name,n in expected.items():
                path=root/name
                if count_csv(path)!=n:raise ValueError(f'E06 sensitivity axis: {eid}/{name}')
                counts[f'sensitivities/{eid}/{name}']=n
    grid=json.loads((OUT/'E06/SENSITIVITY_GRID_RECEIPT.json').read_text())
    expected={f'P{p}_M2_D{d}' for p in (0,1) for d in (0,1,2)}
    if {item['experiment_id'] for item in grid['sources']}!=expected:
        raise ValueError('E06 sensitivity grid cell identity')
    for item in grid['sources']:
        eid=item['experiment_id']
        root=OUT/'E06' if eid=='P0_M2_D1' else OUT/'E06/sensitivities'/eid
        require_hash(root/'HYBRID_RECEIPT.json',item['receipt_sha256'])
        require_hash(root/'hybrid_baseline_summary.csv',item['summary_sha256'])
        require_hash(root/'hybrid_paired_effects.csv',item['paired_sha256'])
    for name,sha in grid['outputs'].items():
        require_hash(OUT/'E06'/name,sha)
        if name.endswith('.csv'):
            if count_csv(OUT/'E06'/name)!=grid['rows'][name]:
                raise ValueError(f'E06 grid row count: {name}')
            counts[name]=grid['rows'][name]
    trace=json.loads((OUT/'E06/SENSITIVITY_INNBCL_RECEIPT.json').read_text())
    if {r['experiment_id'] for r in trace['sources']}!={'P0_M2_D0','P1_M2_D0'}:
        raise ValueError('E06 D0 trace source set')
    for item in trace['sources']:
        require_hash(OUT/'E06/sensitivities'/item['experiment_id']/'HYBRID_RECEIPT.json',
                     item['receipt_sha256'])
    trace_path=OUT/'E06/sensitivity_innbcl_2020W16.csv'
    require_hash(trace_path,trace['output_sha256'])
    if count_csv(trace_path)!=trace['rows']:
        raise ValueError('E06 INNBCL trace row count')
    counts[trace_path.name]=trace['rows']
    return counts


def new_e07_key_support(byid):
    receipt=json.loads((OUT/'E07/key_week_model_support_receipt.json').read_text())
    expected={f'P{p}_M{m}_D{d}' for p in (0,1) for m in (1,2) for d in (0,1,2)}
    if {r['experiment_id'] for r in receipt['parents']}!=expected:
        raise ValueError('E07 key-week parent set')
    for parent in receipt['parents']:
        eid=parent['experiment_id'];source=byid[eid]
        if parent['research_run_id']!=source['research_run_id']:
            raise ValueError(f'E07 key-week parent ID: {eid}')
        require_hash(Path(source['result_root'])/'CTREND/CTREND_Base.mat',parent['result_sha256'])
        run=Path(source['accepted_run_root'])
        weekly=[run/part/'bCharacteristicsOLHC_Combo1.mat' for part in ('data','data.staging')
                if (run/part/'bCharacteristicsOLHC_Combo1.mat').is_file()]
        if len(weekly)!=1:raise ValueError(f'E07 weekly input ambiguity: {eid}')
        require_hash(weekly[0],parent['weekly_input_sha256'])
    if receipt['scope']!='five_key_weeks_union_extreme_holdings_M2_vs_M1_not_unique_causal_reasons':
        raise ValueError('E07 key-week scope changed')
    for name,sha in receipt['outputs'].items():require_hash(OUT/'E07'/name,sha)
    detailed=rows(OUT/'E07/key_week_model_support_diagnostics.csv')
    if len(detailed)!=receipt['rows']:
        raise ValueError('E07 key-week row count')
    if {int(r['year_week']) for r in detailed}!=set(receipt['weeks']):
        raise ValueError('E07 key-week calendar')
    grouped={}
    for row in detailed:
        if int(row['forecast_finite'])!=int(row['diagnostic_stage']=='saved_forecast_finite'):
            raise ValueError('E07 diagnostic stage disagrees with saved forecast')
        if (float(row['low_opening_weight'])>0 or float(row['high_opening_weight'])>0) \
                and not int(row['forecast_finite']):
            raise ValueError('E07 held key-week asset has no saved forecast')
        key=row['experiment_id'],row['diagnostic_stage']
        grouped[key]=grouped.get(key,0)+1
    registered={(r['experiment_id'],r['diagnostic_stage']):int(r['asset_week_rows'])
                for r in rows(OUT/'E07/key_week_model_support_summary.csv')}
    if registered!=grouped:
        raise ValueError('E07 key-week stage summary disagrees with detail')
    if sum(v for (eid,stage),v in grouped.items()
           if stage=='model_stage_unresolved_from_saved_fields')!=receipt['unresolved_rows']:
        raise ValueError('E07 unresolved row count')
    return {'key_week_model_support_diagnostics.csv':receipt['rows'],
            'key_week_model_support_summary.csv':len(grouped)}


def main():
    if subprocess.run(['git','merge-base','--is-ancestor',BASE_COMMIT,'HEAD'],cwd=REPO).returncode:
        raise ValueError('Frozen parent commit is not an ancestor')
    subprocess.run(['git','diff','--exit-code',BASE_COMMIT,'--','.',
        ':(exclude)followup_research',':(exclude)README.md',':(exclude)README_CN.md'],
        cwd=REPO,check=True,stdout=subprocess.DEVNULL)
    register={r['experiment_id']:r for r in rows(ROOT/'EXPERIMENT_REGISTER.csv')}
    if set(register)!=set(ACTIVE)|{'E12'} or register['E12']['status']!='paused_by_user':
        raise ValueError('E01--E11 scope/E12 pause contract differs')
    checks=ROOT/'validation';checks.mkdir(exist_ok=True)
    with (checks/'scientific_contracts.log').open('w') as log:
        subprocess.run([sys.executable,str(SCRIPTS/'test_scientific_contracts.py')],check=True,
            stdout=log,stderr=subprocess.STDOUT,env={**os.environ,'OPENBLAS_NUM_THREADS':'1'})
    for line in (REPO/'data/RAW_INPUTS.sha256').read_text().splitlines():
        sha,file=line.split(maxsplit=1);require_hash(REPO/'data/raw/common'/file.lstrip('*'),sha)
    accepted=OUT/'E11/accepted_run_paths.csv';parents=rows(accepted)
    ids={f'P{p}_M{m}_D{d}' for p in (0,1) for m in (0,1,2) for d in (0,1,2)}
    if len(parents)!=len(ids) or {r['experiment_id'] for r in parents}!=ids:raise ValueError('Parent factorial identity')
    byid={r['experiment_id']:r for r in parents};cal={}
    for r in parents:
        require_hash(Path(r['accepted_run_root'])/'RUN_COMPLETE',r['run_complete_sha256'])
        w=np.asarray(loadmat(Path(r['result_root'])/'CTREND/CTREND_Base.mat',variable_names=['vDates'])['vDates'],int).ravel()
        if len(set(w))!=len(w) or not (np.diff(w)>0).all():raise ValueError('Calendar')
        cal[r['experiment_id']]=w
    first=next(iter(cal.values()))
    if any(not np.array_equal(first,w) for w in cal.values()):raise ValueError('Parent calendar mismatch')
    T=len(first);m1=sorted(e for e in ids if '_M1_' in e);n=len(m1)
    nd=len(rows(OUT/'E11/design_choices_M1.csv'))
    if len({digest(OUT/'E11'/f'design_choices_M{m}.csv') for m in (0,1,2)})!=1:raise ValueError('Design keys')
    receipts=research_receipts()
    coauthor=json.loads((OUT/'E01/coauthor_workbook_distribution_receipt.json').read_text())
    workbook=REPO/'data/raw/common/LTW_3factor.xlsx'
    require_hash(workbook,coauthor['local_input_sha256'])
    if coauthor['downloaded_workbook_sha256']!=coauthor['local_input_sha256'] or \
            coauthor['downloaded_size_bytes']!=workbook.stat().st_size or \
            coauthor['publisher_page']!='https://xiwuacademic.com/data-and-code/' or \
            coauthor['byte_identical'] is not True:
        raise ValueError('E01 coauthor workbook distribution identity')
    counts={eid:{} for eid in ACTIVE}
    counts['E01']={'eight_mixed_benchmarks.csv':n*10,'factor_source_summary.csv':n*3,
        'paired_benchmark_alpha_difference.csv':n*3,**{f'{e}/e01_weekly_factors.csv':T for e in m1}}
    counts['E02']['grs_argument_and_system_audit.csv']=n*3*3*5
    for r in rows(OUT/'E02/grs_argument_and_system_audit.csv'):
        if r['status']=='computed' and r['variant']=='valid_common_system' and r['factor_covariance_divisor']!='T':
            raise ValueError('Exact GRS covariance convention')
    counts['E03']={'dual_increment_and_four_models.csv':n*4,'paired_52week_oos_summary.csv':n*2,
        'paired_52week_oos_min26_summary.csv':n*2,'nonnested_squared_sharpe_hac.csv':n*2,
        'economic_equivalence_threshold_curve.csv':n*2*2*4}
    counts['E04']={'paired_method_differences.csv':n*3,'support_block_sensitivity.csv':n*3*3*3,
        'paired_risk_distribution.csv':n*3*3*2,'support_calendar_audit.csv':n*3*3*T}
    counts['E05']={'formation_snapshot_and_future_availability_perturbation.csv':n*T,'formation_channel_summary.csv':n}
    counts['E05'].update(new_e05_receipts(byid,T))
    for m in (1,2):
        probe=rows(OUT/'E05'/f'P0_M{m}_D1_production_b05_future_perturbation.csv')
        if {r['variant'] for r in probe}!={'control','future_values','future_missingness'}:raise ValueError('b05 scope')
        if any(int(r[k]) for r in probe for k in ('changed_past_predictions','changed_past_beta_cells','changed_past_selection_cells')):
            raise ValueError('b05 historical output changed')
        if any(int(r['changed_later_predictions'])==0 for r in probe if r['variant']!='control'):
            raise ValueError('b05 shock did not reach later outputs')
    probe=rows(OUT/'E05/production_b02_daily_future_perturbation.csv')
    if {r['experiment_id'] for r in probe}!={'P0_M1_D1','P0_M2_D1'}:raise ValueError('b02 probe scope')
    if any(int(r['past_changed_cells']) or not int(r['control_equal_accepted']) for r in probe):
        raise ValueError('b02 historical/control output changed')
    extended=rows(OUT/'E05/production_b02_daily_future_perturbation_extended.csv')
    remaining={f'P{p}_M{m}_D{d}' for p in (0,1) for m in (1,2) for d in (0,1,2)}-{'P0_M1_D1','P0_M2_D1'}
    receipt=json.loads((OUT/'E05/receipts/b02_remaining_10cells_receipt.json').read_text())
    if receipt['status']!='complete' or set(receipt['experiments'])!=remaining or len(receipt['results'])!=10:
        raise ValueError('E05 remaining b02 experiment identity')
    require_hash(SCRIPTS/'run_e05_b02_perturbation_remaining.py',receipt['driver_sha256'])
    require_hash(SCRIPTS/'run_e05_b02_perturbation.py',receipt['base_probe_sha256'])
    require_hash(OUT/'E05/production_b02_daily_future_perturbation_extended.csv',receipt['output_sha256'])
    if {r['experiment_id'] for r in extended}!=remaining or any(
            int(r['past_changed_cells']) or not int(r['control_equal_accepted']) for r in extended):
        raise ValueError('E05 remaining b02 historical/control output changed')
    if {r['experiment_id']:sum(x['experiment_id']==r['experiment_id'] for x in extended)
            for r in receipt['results']}!={r['experiment_id']:r['field_rows'] for r in receipt['results']}:
        raise ValueError('E05 remaining b02 field counts')
    counts['E05']['production_b02_daily_future_perturbation.csv']=len(probe)
    counts['E05']['production_b02_daily_future_perturbation_extended.csv']=len(extended)
    counts['E06']={'ordered_weight_payoff_mechanism.csv':n,'hybrid_baseline_weekly.csv':7*T,
        'hybrid_baseline_summary.csv':7*3,'hybrid_paired_effects.csv':9*2,
        'hybrid_forecast_to_holdings_weekly.csv':6*T,'hybrid_forecast_to_holdings_summary.csv':6}
    counts['E06'].update(new_e06_sensitivities(T,byid))
    a=json.loads((OUT/'E07/asset_stage_export_receipt.json').read_text())
    if set(a['scope'])!=ids or a['asset_week_rows']!=sum(r['asset_weeks'] for r in a['inputs']):raise ValueError('E07 scope')
    for r in a['inputs']:
        identity=byid[r['experiment_id']]
        if r['research_run_id']!=identity['research_run_id'] or r['run_complete_sha256']!=identity['run_complete_sha256']:
            raise ValueError('E07 source identity')
        require_hash(Path(identity['result_root'])/'CTREND/CTREND_Base.mat',r['base_mat_sha256'])
    require_hash(OUT/'E07/asset_week_forecast_holding_stages.csv.gz',a['asset_ledger_sha256'])
    require_hash(OUT/'E07/weekly_forecast_holding_stage_counts.csv',a['weekly_summary_sha256'])
    counts['E07']={'asset_week_forecast_holding_stages.csv.gz':a['asset_week_rows'],
        'weekly_forecast_holding_stage_counts.csv':sum(map(len,cal.values())),
        'controlled_coverage_weighting_by_week.csv':n*T*2*2*3,'controlled_coverage_weighting_summary.csv':n*2*3,
        'controlled_coverage_same_calendar.csv':n*3,'raw_label_vs_economic_payoff_rank_ic.csv':n*T*2}
    counts['E07'].update(new_e07_key_support(byid))
    native=OUT/'E07/native_failure_audit'
    native_receipt=json.loads((native/'EXPORT_RECEIPT.json').read_text())
    native_equality=rows(native/'full_baseline_field_equality.csv')
    if native_receipt['format']!='cttrend-e07-native-gates-export-v1' or \
            {r['experiment_id'] for r in native_equality}!={f'P{p}_M{m}_D{d}'
            for p in (0,1) for m in (1,2) for d in (0,1,2)} or \
            any(r['all_fields_isequaln']!='1' for r in native_equality):
        raise ValueError('E07 native baseline equivalence')
    for name,sha in native_receipt['files_sha256'].items():require_hash(native/name,sha)
    for source,sha in native_receipt['source_manifests'].items():require_hash(Path(source)/'manifest.json',sha)
    counts['E07']['native_failure_audit/full_baseline_field_equality.csv']=12
    counts['E08']['weekly_concentration_and_reconciliation.csv']=sum(map(len,cal.values()))
    counts['E08'].update(new_e08_cocos_source(byid))
    counts['E09']={'fixed_transaction_fee_statistical_factor.csv':n*3,'conditional_borrow_fee_scenarios_not_account.csv':n*4,
        'opening_liquidity_proxy_by_leg_week.csv':n*T*2,'opening_liquidity_proxy_summary.csv':n*2,
        'fixed_holdings_cost_accounting_weekly.csv':n*T*2,'fixed_holdings_cost_accounting_summary.csv':n*3}
    a=json.loads((OUT/'E10/COHORT_LEDGER_RECEIPT.json').read_text())
    if a['status']!='pass' or {r['experiment_id'] for r in a['experiments']}!=set(m1):raise ValueError('E10 receipt')
    if 'E10_OBSERVATION_TEST_OK' not in (OUT/'E10/observation_test.log').read_text():raise ValueError('Nonempty exit test')
    for r in a['experiments']:
        eid=r['experiment_id'];name=eid+'_cohort_asset_weights.csv'
        require_hash(OUT/'E10'/name,r['asset_csv_sha256']);require_hash(OUT/'E10'/r['compressed']['path'],r['compressed']['sha256'])
        require_hash(OUT/'E10'/(eid+'_cohort_reinvestment_trades.csv'),r['trade_csv_sha256'])
        counts['E10'][name]=counts['E10'][r['compressed']['path']]=r['asset_rows']
        counts['E10'][eid+'_cohort_reinvestment_trades.csv']=r['trade_rows']
        counts['E10'][eid+'_weekly_holding.csv']=sum(T-phase+1 for h in range(1,7) for phase in range(1,h+1))
    counts['E10'].update({'all_phases_holding_comparison.csv':n*21,'published_ledger_vs_fixed_cohort.csv':n*21,'all_phase_envelopes.csv':n*6})
    a=json.loads((OUT/'E11/prediction_opportunity_receipt.json').read_text())
    if a['status']!='complete' or a['designs_per_cell']!=nd:raise ValueError('Full grid incomplete')
    require_hash(accepted,a['accepted_run_table_sha256'])
    from analyze_e11 import METHODS
    for r in a['outputs']:
        require_hash(OUT/'E11'/r['path'],r['sha256']);counts['E11'][r['path']]=nd*len(METHODS)*3
    for p in (0,1):
        for d in (0,1,2):
            for prefix in ('paired_design_cells','paired_design_ltw_alpha'):
                counts['E11'][f'{prefix}_P{p}_D{d}.csv']=nd*len(METHODS)*3
    for m in (0,1,2):counts['E11'][f'design_choices_M{m}.csv']=nd
    sources=[dict(path=str(p.relative_to(ROOT)),sha256=digest(p)) for p in sorted(SCRIPTS.iterdir())
        if p.is_file() and p.suffix in ('.py','.m') and 'e12' not in p.name]
    summary=[]
    for eid in ACTIVE:
        for name in set(REQUIRED[eid].split())|set(counts[eid]):
            if not (OUT/eid/name).is_file():raise ValueError(f'Missing {eid}/{name}')
        artifacts=[]
        for p in sorted((OUT/eid).rglob('*')):
            if not p.is_file() or p.name=='ARTIFACT_MANIFEST.json' or '__pycache__' in p.parts:continue
            if p.name.endswith('.partial'):raise ValueError(f'Unfinished output: {p}')
            name=str(p.relative_to(OUT/eid));item=dict(relative_path=name,size_bytes=p.stat().st_size,sha256=digest(p))
            if p.suffix=='.csv' or p.name.endswith('.csv.gz'):
                item['rows']=count_csv(p)
                if name in counts[eid] and item['rows']!=counts[eid][name]:raise ValueError(f'Axis-derived count: {eid}/{name}')
            artifacts.append(item)
        manifest=dict(experiment_id=eid,artifact_validation='pass',scientific_status=register[eid]['status'],
            scientific_limit=register[eid]['remaining_condition'],parent_code_commit=BASE_COMMIT,
            plan_pdf_sha256=PLAN_SHA,accepted_18_run_identity_table_sha256=digest(accepted),
            raw_inputs_manifest_sha256=digest(REPO/'data/RAW_INPUTS.sha256'),raw_files_hash_checked=True,
            scientific_contract_test_log_sha256=digest(checks/'scientific_contracts.log'),
            experiment_receipts=receipts,scripts=sources,outputs=artifacts,E12_excluded=True)
        (OUT/eid/'ARTIFACT_MANIFEST.json').write_text(json.dumps(manifest,indent=2,ensure_ascii=False)+'\n')
        summary.append(dict(experiment_id=eid,scientific_status=register[eid]['status'],checked_files=len(artifacts),
            checked_rows=sum(r.get('rows',0) for r in artifacts),artifact_validation='pass'))
        print(f'FOLLOWUP_ARTIFACT_OK {eid} status={register[eid]["status"]} files={len(artifacts)}',flush=True)
    with (ROOT/'ARTIFACT_ACCEPTANCE.csv').open('w',newline='') as f:
        w=csv.DictWriter(f,fieldnames=list(summary[0]));w.writeheader();w.writerows(summary)
    print('FOLLOWUP_ARTIFACT_VALIDATION_OK active_experiments=11 E12=excluded',flush=True)


if __name__=='__main__':main()
