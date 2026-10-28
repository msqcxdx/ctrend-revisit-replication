#!/usr/bin/env python3
# CTREND_REVISIT_FILE_PURPOSE: Export verified current-run tables, figures and baseline returns, then build paper-plus-eighteen and paired-support reports without stale reference results.
"""Read registrations, never curated experiment values. Do not re-estimate models."""
import csv
import datetime as dt
import hashlib
import itertools
import json
from pathlib import Path
import re
import shutil
import subprocess
import sys

import numpy as np
from scipy.io import loadmat

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'analysis'))
from publication_evidence import paper_baseline, factor_companion
from paper_factor_comparison import export_paper_comparison
IDS = tuple(f'P{p}_M{m}_D{d}' for p in range(2) for m in (0, 2, 1) for d in range(3))


def sha(path):
    h = hashlib.sha256()
    with path.open('rb') as f:
        for block in iter(lambda: f.read(1024 * 1024), b''):
            h.update(block)
    return h.hexdigest()


def env(path):
    return dict(line.split('=', 1) for line in path.read_text().splitlines() if '=' in line)


def csv_rows(path):
    with path.open(newline='', encoding='utf-8-sig') as f:
        return list(csv.DictReader(f))


def write_csv(path, rows):
    if not rows:
        raise RuntimeError(f'No rows for {path}')
    with path.open('w', newline='', encoding='utf-8') as f:
        w = csv.DictWriter(f, fieldnames=list(rows[0]), lineterminator='\n')
        w.writeheader()
        w.writerows(rows)


def clean_tex(cell):
    cell = cell.strip()
    match = re.fullmatch(r'\\makecell\[c\]\{(.*)\}', cell)
    if match:
        cell = match.group(1)
    previous = None
    while previous != cell:
        previous = cell
        cell = re.sub(r'\\text(?:bf|BF)\{([^{}]*)\}', r'\1', cell)
    cell = cell.replace(r'\\', ' ').replace(r'\%', '%').replace(r'\_', '_')
    cell = cell.replace('$', '').replace('{', '').replace('}', '')
    return re.sub(r'\s+', ' ', re.sub(r'\\[A-Za-z]+', '', cell)).strip()


def table_cells(path):
    """Retain repeated row labels and all columns; do not conflate specifications."""
    rows, header, body = [], [], False
    for raw in path.read_text().splitlines():
        line = raw.strip()
        if line == r'\midrule':
            body = True
            continue
        if line == r'\bottomrule':
            break
        if ' & ' not in line or not line.endswith(r'\\'):
            continue
        if line.startswith('& '):
            line = ' ' + line
        values = [clean_tex(x) for x in line[:-2].split(' & ')]
        if body:
            rows.append(values)
        else:
            header = values
    if path.name == 'trend_model_alphas.tex' and header:
        rows.insert(0, header)
    if not rows:
        raise RuntimeError(f'Cannot parse generated table: {path}')
    counts, cells = {}, {}
    for row in rows:
        label = row[0]
        counts[label] = counts.get(label, 0) + 1
        for col, value in enumerate(row[1:], 1):
            cells[(label, counts[label], col)] = value
    return cells


def statistics(values):
    z = np.asarray(values, dtype=float)
    z = z[np.isfinite(z)]
    n = len(z)
    mean = float(z.mean()) if n else float('nan')
    sd = float(z.std(ddof=1)) if n > 1 else float('nan')
    return dict(weeks=n, mean_weekly_pct=100 * mean, std_weekly_pct=100 * sd,
                t=mean / sd * np.sqrt(n) if sd > 0 else float('nan'),
                sharpe_annualized=mean / sd * np.sqrt(52) if sd > 0 else float('nan'))


def baseline(path):
    mat = loadmat(path, simplify_cells=True, variable_names=['vDates', 'cResults'])
    dates = np.asarray(mat['vDates']).reshape(-1)
    returns = np.asarray(mat['cResults']['VW']['mPortRet'], dtype=float)
    if returns.shape != (6, len(dates)) or len(set(dates)) != len(dates) or not np.isfinite(dates).all():
        raise RuntimeError(f'Invalid baseline date/portfolio dimensions: {path}')
    if not np.equal(dates, np.floor(dates)).all() or not np.all(np.diff(dates) > 0):
        raise RuntimeError(f'Invalid YYYYWW baseline dates: {path}')
    return {int(t): returns[:, j] for j, t in enumerate(dates)}


def common_dates(data, ids):
    supports = [{t for t, r in data[id].items() if np.isfinite(r[-1])} for id in ids]
    return sorted(set.intersection(*supports))


def comparisons(data):
    own, common, pairs, weekly = [], [], [], []
    ids = tuple(data)
    shared = common_dates(data, ids)
    if len(shared) < 2:
        raise RuntimeError('Fewer than two common weeks; no complete common-week report can be claimed')
    for id in ids:
        for t, r in sorted(data[id].items()):
            weekly.append(dict(experiment_id=id, week=t, low=r[0], high=r[4], hl=r[5]))
        own.append(dict(experiment_id=id, **statistics([r[5] for r in data[id].values()])))
        for index, name in ((0, 'L'), (4, 'H'), (5, 'H-L')):
            z = [data[id][t][index] for t in shared]
            if not np.isfinite(z).all():
                raise RuntimeError(f'{id}: finite H-L with missing leg on common support')
            common.append(dict(experiment_id=id, portfolio=name, **statistics(z)))
    # All 153 pairs include every one-axis contrast and all key multi-axis paths.
    # Return-spread t statistics below are descriptive, not a Sharpe-difference test.
    for a, b in itertools.combinations(ids, 2):
        dates = common_dates(data, (a, b))
        x = [data[a][t][5] for t in dates]
        y = [data[b][t][5] for t in dates]
        sa, sb = statistics(x), statistics(y)
        axes = ','.join(axis for axis, av, bv in zip(('P', 'M', 'D'), a.split('_'), b.split('_')) if av != bv)
        pairs.append(dict(first=a, second=b, changed_axes=axes,
                          common_weeks=len(dates), first_mean_pct=sa['mean_weekly_pct'],
                          second_mean_pct=sb['mean_weekly_pct'],
                          delta_mean_pct_second_minus_first=sb['mean_weekly_pct'] - sa['mean_weekly_pct'],
                          first_sharpe=sa['sharpe_annualized'], second_sharpe=sb['sharpe_annualized'],
                          delta_sharpe_second_minus_first=sb['sharpe_annualized'] - sa['sharpe_annualized'],
                          paired_spread_t=statistics(np.asarray(y) - x)['t'],
                          shared_dates=';'.join(map(str, dates))))
    return own, common, pairs, weekly


def markdown(headers, rows):
    def fmt(x):
        if isinstance(x, (float, np.floating)):
            x = f'{x:.6g}' if np.isfinite(x) else 'NA'
        return str(x).replace('|', r'\|').replace('\n', ' ')
    return '\n'.join(['| ' + ' | '.join(map(fmt, headers)) + ' |',
                      '|' + '|'.join(['---'] * len(headers)) + '|'] +
                     ['| ' + ' | '.join(map(fmt, row)) + ' |' for row in rows])


def build(root, output):
    if not output.is_absolute() or output.exists():
        raise RuntimeError('Output must be an absolute, fresh directory')
    # Full run acceptance, not mere file counts. Existing scientific verifiers
    # remain authoritative and no completion/provenance gate is bypassed.
    subprocess.run([sys.executable, str(root / 'scripts/verify_pmd_registrations.py')], check=True)
    output.mkdir(parents=True)
    registry = csv_rows(root / 'config/output_registry.csv')
    # Figure 3 has a numeric companion in addition to the registry's PNGs.
    # Include it explicitly when working with the full paper output registry.
    if any(row['paper_item'] == 'Figure 3' for row in registry):
        registry.append(dict(paper_item='Figure 3', producer_step='b11',
                             required_output_pattern='Tables/anomaly_alphas.tex',
                             minimum_matches='1', experiments='all'))
    benchmarks = csv_rows(root / 'results/comparisons/source_tables/CURATED_PAPER_BENCHMARKS.csv')
    shutil.copy2(root / 'results/comparisons/source_tables/CURATED_PAPER_BENCHMARKS.csv', output)
    documentation = output / 'documentation'
    documentation.mkdir()
    for item in registry:
        if item['experiments'] != 'common':
            continue
        source = root / item['required_output_pattern']
        shutil.copy2(source, documentation / source.name)
    identities, inventory, cells, data = [], [], {}, {}
    for id in IDS:
        public_path = root / 'outputs/experiments' / id / 'PMD_REGISTRATION.env'
        public = env(public_path)
        inner_path = (root / public['inner_registration_relative']).resolve()
        if not inner_path.is_relative_to(root) or sha(inner_path) != public['inner_registration_sha256']:
            raise RuntimeError(f'Registration binding mismatch: {id}')
        reg = env(inner_path)
        run, results = Path(reg['run_root']), Path(reg['results_root'])
        if sha(run / 'RUN_COMPLETE') != reg['run_complete_sha256']:
            raise RuntimeError(f'Completion binding mismatch: {id}')
        identities.append(dict(experiment_id=id, research_run_id=reg['research_run_id'],
                               run_root=str(run), results_root=str(results),
                               public_registration_sha256=sha(public_path),
                               inner_registration_sha256=sha(inner_path),
                               results_inventory_sha256=reg['results_inventory_sha256'],
                               run_complete_sha256=sha(run / 'RUN_COMPLETE')))
        target = output / 'experiments' / id
        target.mkdir(parents=True)
        selected = {results / 'CTREND/CTREND_Base.mat'}
        for item in registry:
            if item['experiments'] == 'common':
                continue
            if item['experiments'] != 'all' and item['experiments'] != id.split('_')[1]:
                continue
            matched = sorted({p for pattern in item['required_output_pattern'].split('|') for p in results.glob(pattern) if p.is_file()})
            if len(matched) < int(item['minimum_matches']):
                raise RuntimeError(f'{id}: missing {item["paper_item"]}')
            selected.update(matched)
            if item['paper_item'] == 'Figure 1':
                for source in matched:
                    fig = source.with_suffix('.fig')
                    if not fig.is_file():
                        raise RuntimeError(f'Missing Figure 1 numerical source: {fig}')
                    selected.add(fig)
                    inventory.append(dict(experiment_id=id, paper_item='Figure 1 numerical source',
                                          path=str((target / fig.relative_to(results)).relative_to(output)), sha256=sha(fig)))
            for source in matched:
                if source.suffix == '.tex':
                    for (label, occurrence, column), value in table_cells(source).items():
                        key = (item['paper_item'], source.name, label, occurrence, column)
                        cells.setdefault(key, {})[id] = value
                inventory.append(dict(experiment_id=id, paper_item=item['paper_item'],
                                      path=str((target / source.relative_to(results)).relative_to(output)), sha256=sha(source)))
        for source in sorted(selected):
            dest = target / source.relative_to(results)
            dest.parent.mkdir(parents=True, exist_ok=True)
            before = sha(source)
            shutil.copy2(source, dest)
            if sha(dest) != before or sha(source) != before:
                raise RuntimeError(f'Export source changed: {source}')
        data[id] = baseline(target / 'CTREND/CTREND_Base.mat')
    write_csv(output / 'RUN_IDENTITIES.csv', identities)
    write_csv(output / 'PAPER_OUTPUTS.csv', inventory)
    write_csv(output / 'ALL_TABLE_CELLS.csv', [dict(paper_item=k[0], filename=k[1], row_label=k[2], row_occurrence=k[3], column_index=k[4], **{id: v.get(id, 'NOT_APPLICABLE') for id in IDS}) for k, v in sorted(cells.items())])
    own, common, pairs, weekly = comparisons(data)
    for name, rows in [('HEADLINE_OWN_WEEKS', own), ('COMMON_WEEK_LEGS', common), ('PAIRED_ABLATIONS', pairs), ('WEEKLY_RETURNS', weekly)]:
        write_csv(output / f'{name}.csv', rows)
    # The author factor is a distinct, source-hashed comparator. The eighteen
    # experiment inputs below come ONLY from the verified registrations above.
    paper_evidence = export_paper_comparison(root, output / 'paper_factor',
        {id: {t: r[5] for t, r in data[id].items()} for id in IDS})
    # Same full intersection for decompositions: differences telescope only
    # when every leg of a multi-step path uses the same dates.
    common_hl = {r['experiment_id']: r for r in common if r['portfolio'] == 'H-L'}
    balanced = [dict(first=a, second=b, changed_axes=','.join(axis for axis, av, bv in zip(('P', 'M', 'D'), a.split('_'), b.split('_')) if av != bv),
                     common_weeks=common_hl[a]['weeks'],
                     delta_mean_pct_second_minus_first=common_hl[b]['mean_weekly_pct']-common_hl[a]['mean_weekly_pct'],
                     delta_sharpe_second_minus_first=common_hl[b]['sharpe_annualized']-common_hl[a]['sharpe_annualized']) for a, b in itertools.combinations(IDS, 2)]
    write_csv(output / 'ALL_COMMON_ABLATIONS.csv', balanced)
    # Reuse the existing read-only diagnostics on these exported MATs, not on
    # the reference snapshot. Numerical holdings/payoff logic is unchanged.
    subprocess.run([sys.executable, str(root / 'analysis/diagnose_eighteen_accepted_runs.py'),
                    '--results-root', str(output)], check=True)
    has_figure1 = any(item['paper_item'] == 'Figure 1' for item in registry)
    if has_figure1:
        companion = [r for id in IDS for r in factor_companion(output / 'experiments', id)]
        write_csv(output / 'FACTOR_FIGURE_NUMERICAL_COMPANION.csv', companion)
    paper = paper_baseline(root)
    report = ['# 本次完整复现：论文与十八组实验', '',
              '本报告仅消费已验收登记的本次结果，不读取随包附带的实验数值。论文表格披露值来自独立整理的基准表；作者实际 H-L 周收益来自原始 Dataverse ZIP 的 CTREND.xlsx。未披露项不从 M0 推算。所有均值为周百分比，Sharpe 按 √52 年化。baseline 均值 t 按 mean/(sd/√n) 计算，不是 HAC 调整或 Sharpe 差检验；表格原始回归统计另按生成表保留。', '',
              '## 1. 主要结果与论文逐项对照', '',
              markdown(['方法', '有效周', '周均值 %', '标准差 %', 't', '年化 Sharpe'],
                       [[r[k] for k in ('series_id', 'weeks', 'mean_weekly_pct', 'std_weekly_pct', 't', 'sharpe_annualized')] for r in paper_evidence['own']]), '',
              f"上表 Paper 为作者工作簿全精度重算。论文 Table 3 的披露值另为均值 {paper['mean']:.2f}%、标准差 {paper['std']:.2f}%、t={paper['t']:.2f}、Sharpe={paper['sharpe']:.2f}。作者工作簿来源哈希见 [PAPER_FACTOR_PROVENANCE.json](paper_factor/PAPER_FACTOR_PROVENANCE.json)。", '',
              '全部生成表格单元见 [ALL_TABLE_CELLS.csv](ALL_TABLE_CELLS.csv)；每张表和图的本次文件及哈希见 [PAPER_OUTPUTS.csv](PAPER_OUTPUTS.csv)。Table B.1 方法定义文件在 documentation/。未匹配的论文行明确显示“无同名匹配”，不填入参考实验数值。', '']
    for item in dict.fromkeys(r['paper_item'] for r in benchmarks):
        report += [f'### {item}', '']
        for p in ('P0', 'P1'):
            ids = [id for id in IDS if id.startswith(p)]
            lines = []
            for row in benchmarks:
                if row['paper_item'] != item:
                    continue
                values = []
                for id in ids:
                    matched = [v[id] for k, v in cells.items() if k[0] == item and k[2:] == (row['experiment_row_label'], int(row['experiment_row_occurrence']), int(row['experiment_column_index'])) and id in v]
                    if len(matched) == 1:
                        values.append(matched[0])
                    elif item == 'Table B.2' and row['experiment_row_label'] == 'CTREND' and id.split('_')[1] in ('M0', 'M2'):
                        values.append('原表未输出；见 FIG/基准补充')
                    else:
                        values.append('无唯一同名匹配；参见原表')
                lines.append([row['metric'], row['paper_value'], *values])
            report += [f'#### {p}', '', markdown(['指标', '论文', *ids], lines), '']
    if has_figure1:
        report += ['### Figure 1 数值及 CTREND 补充统计', '',
                   'M0/M2 的 Table B.2 原始 TeX 省略 CTREND 行，不代表没有该因子的收益。全部四因子的实际柱高见 [FACTOR_FIGURE_NUMERICAL_COMPANION.csv](FACTOR_FIGURE_NUMERICAL_COMPANION.csv)，由本次保存 FIG 读取；该文件另列 baseline 自身有限周统计。FIG 的四因子共同支持与 baseline 自身支持分开标识，数值不一致不会被强行覆盖。原表未输出、统计量不可定义、论文未披露不是同一种缺失。', '',
                   markdown(['实验', '基准自身周数', '基准均值%', '基准标准差%', '基准 Sharpe', 'FIG 均值%', 'FIG Sharpe'],
                            [[r[k] for k in ('experiment_id','baseline_own_weeks','baseline_own_mean_pct','baseline_own_std_pct','baseline_own_sharpe_annualized','figure_mean_pct','figure_sharpe_annualized')] for r in companion if r['factor']=='CTREND']), '']
    report += ['### 图形及其他输出入口', '']
    for item in dict.fromkeys(r['paper_item'] for r in inventory):
        if not ('Figure' in item or 'audit' in item):
            continue
        report += [f'#### {item}', '']
        report += [f'- {r["experiment_id"]}：[本次输出]({r["path"]})' for r in inventory if r['paper_item'] == item]
        report += ['']
    report += ['## 2. 共同周稳健性', '',
               '作者因子与十八项实验按作者每年 52 周分块的 YYYYWW 日期键取有限 H-L 交集（不是 ISO 周），不把缺失收益补零。十九方的统计量如下。', '',
               markdown(['方法', '共同周', 'H-L 周均值 %', '标准差 %', '普通均值 t', 'H-L 年化 Sharpe'], [[r[k] for k in ('series_id', 'weeks', 'mean_weekly_pct', 'std_weekly_pct', 't', 'sharpe_annualized')] for r in paper_evidence['common']]), '',
               '全部十九方两两配对比较、固定交集上的作者−实验收益差、相关系数及来源边界见 [作者因子共同周报告](paper_factor/NINETEEN_WAY_COMMON_WEEK_COMPARISON_CN.md)。作者仅提供 H-L，不伪造分位腿或持仓。十八项实验的逐腿共同支持结果另见 [COMMON_WEEK_LEGS.csv](COMMON_WEEK_LEGS.csv)，实验逐周底稿见 [WEEKLY_RETURNS.csv](WEEKLY_RETURNS.csv)，十九方底稿见 [NINETEEN_WAY_WEEKLY_RETURNS.csv](paper_factor/NINETEEN_WAY_WEEKLY_RETURNS.csv)。', '',
               '## 3. P/M/D 消融比较', '',
               '下表每次只改变一个维度，统一使用十八组交集。差值方向均为第二项减第一项。同一交集上的 M0→M2→M1 均值及 Sharpe 差值可相加；不同配对共同周上的差值不可直接拼接为路径分解。', '',
               markdown(['第一项', '第二项', '改变维度', '共同周', '均值差 %', 'Sharpe 差'], [[r[k] for k in ('first', 'second', 'changed_axes', 'common_weeks', 'delta_mean_pct_second_minus_first', 'delta_sharpe_second_minus_first')] for r in balanced if ',' not in r['changed_axes']]), '',
               '所有两两比较另见 [PAIRED_ABLATIONS.csv](PAIRED_ABLATIONS.csv)（各配对自己的交集）和 [ALL_COMMON_ABLATIONS.csv](ALL_COMMON_ABLATIONS.csv)（统一交集）。配对收益差的 t 值不是 Sharpe 差的显著性检验；这些对比本身也不能证明因果机制。', '',
               '本次持仓、预测重合度见 [KEY_PAIR_FORECAST_HOLDINGS_OVERLAP.csv](diagnostics/portfolio_diagnostics/KEY_PAIR_FORECAST_HOLDINGS_OVERLAP.csv)，固定权重交换 payoff 见 [FIXED_WEIGHT_ENDPOINT_EXCHANGE.csv](diagnostics/portfolio_diagnostics/FIXED_WEIGHT_ENDPOINT_EXCHANGE.csv)，事件周归因见 [INNBCL_2020W16_SAVED_HOLDINGS.csv](diagnostics/portfolio_diagnostics/INNBCL_2020W16_SAVED_HOLDINGS.csv)。这些诊断均从本次 baseline MAT 重算。固定权重交换只在四角共有且无周内退出交易的支持上成立；不能把开仓权重点乘误当成含再投资的交易账本。', '',
               '## 4. 验收与来源', '',
               '每个实验的 run ID、完成标记及全量结果清单哈希见 [RUN_IDENTITIES.csv](RUN_IDENTITIES.csv)。本目录仅复制表图及 baseline MAT；全部 3,072 个设计 MAT 和中间 DATA 保留在原 run root。REPORT_FILES.sha256 校验本次报告与导出文件。', '']
    (output / 'CURRENT_RUN_COMPARISON_CN.md').write_text('\n'.join(report), encoding='utf-8')
    entries = [(str(p.relative_to(output)), sha(p)) for p in sorted(output.rglob('*')) if p.is_file()]
    (output / 'REPORT_FILES.sha256').write_text(''.join(f'{digest}  {name}\n' for name, digest in entries))
    (output / 'REPORT_COMPLETE.json').write_text(json.dumps(dict(experiments=len(IDS), comparison_series=len(paper_evidence['series']),
                                                               paper_workbook_sha256=paper_evidence['provenance']['workbook_sha256'],
                                                               all_nineteen_common_weeks=len(paper_evidence['shared']),
                                                               source='verified_current_registrations', completed_utc=dt.datetime.now(dt.timezone.utc).isoformat(),
                                                               report_inventory_sha256=sha(output / 'REPORT_FILES.sha256')), indent=2) + '\n')
    print(f'CURRENT_RUN_REPORT_OK experiments={len(IDS)} output={output}')


if __name__ == '__main__':
    if len(sys.argv) != 2:
        raise SystemExit('usage: report_registered_runs.py ABSOLUTE_FRESH_OUTPUT_DIR')
    build(ROOT, Path(sys.argv[1]))
