#!/usr/bin/env python3
# CTREND_REVISIT_FILE_PURPOSE: Authenticate the author's published factor workbook and compare its actual weekly returns with accepted experiments on date-keyed supports.
# This is saved-result analysis only: it does not estimate a model, modify any
# experiment return, or fabricate the author's unavailable holdings and legs.
"""Published factor evidence shared by snapshot and fresh-run report builders."""
import csv
import hashlib
import io
import itertools
import json
from pathlib import Path
import posixpath
import re
import zipfile
from xml.etree import ElementTree as ET

import numpy as np

SHEET_NS = {'s': 'http://schemas.openxmlformats.org/spreadsheetml/2006/main'}
REL_NS = {'r': 'http://schemas.openxmlformats.org/package/2006/relationships'}
DOCUMENT_REL = 'http://schemas.openxmlformats.org/officeDocument/2006/relationships'
WORKBOOK_MEMBER = 'Results/CTREND/CTREND.xlsx'


def digest(payload):
    return hashlib.sha256(payload).hexdigest()


def week_key(value):
    # The author uses 52 within-year blocks, NOT ISO weeks or spreadsheet dates.
    # Validate the key before joining; never round an invalid/fractional key.
    if not re.fullmatch(r'\d{6}', str(value)):
        raise ValueError(f'Invalid YYYYWW key: {value!r}')
    key = int(value)
    if not 1000 <= key // 100 <= 9999 or not 1 <= key % 100 <= 52:
        raise ValueError(f'Week is outside the author 01--52 calendar: {value}')
    return key


def workbook_series(payload):
    """Decode the named OOXML sheet, including shared-string headers, offline."""
    with zipfile.ZipFile(io.BytesIO(payload)) as book:
        # A ZIP member or relationship must be unique: first-match selection
        # would hide ambiguous data instead of authenticating the workbook.
        names = book.namelist()
        if len(names) != len(set(names)):
            raise ValueError('Duplicate workbook ZIP members')
        strings = []
        if 'xl/sharedStrings.xml' in names:
            tree = ET.fromstring(book.read('xl/sharedStrings.xml'))
            strings = [''.join(node.itertext()) for node in tree.findall('s:si', SHEET_NS)]
        workbook = ET.fromstring(book.read('xl/workbook.xml'))
        sheets = [s for s in workbook.findall('s:sheets/s:sheet', SHEET_NS)
                  if s.get('name') == 'Data from Study']
        if len(sheets) != 1:
            raise ValueError('Published Data from Study sheet is not unique')
        rel_id = sheets[0].get(f'{{{DOCUMENT_REL}}}id')
        rels = ET.fromstring(book.read('xl/_rels/workbook.xml.rels'))
        targets = [r for r in rels.findall('r:Relationship', REL_NS) if r.get('Id') == rel_id]
        if len(targets) != 1 or targets[0].get('TargetMode') == 'External':
            raise ValueError('Invalid published worksheet relationship')
        target = targets[0].get('Target', '')
        sheet_path = target.lstrip('/') if target.startswith('/') else posixpath.normpath(posixpath.join('xl', target))
        sheet = ET.fromstring(book.read(sheet_path))
        cells = {}
        for cell in sheet.findall('s:sheetData/s:row/s:c', SHEET_NS):
            address = cell.get('r')
            if not address or address in cells:
                raise ValueError('Missing or duplicate worksheet cell address')
            node = cell.find('s:v', SHEET_NS)
            value = node.text if node is not None else None
            if cell.get('t') == 's':
                # Shared-string indices (e.g. 0, 1) are labels, never observations.
                value = strings[int(value)]
            elif cell.get('t') == 'inlineStr':
                value = ''.join(cell.find('s:is', SHEET_NS).itertext())
            elif cell.get('t') in ('e', 'b'):
                raise ValueError(f'Non-numeric data cell type: {address}')
            cells[address] = value
        if cells.get('A1') != 'YYYYWW' or cells.get('B1') != 'CTREND':
            raise ValueError('Published factor header does not identify YYYYWW/CTREND')
        row_ids = sorted({int(re.fullmatch(r'[AB](\d+)', a).group(1)) for a in cells
                          if re.fullmatch(r'[AB]\d+', a)} - {1})
        values = {}
        previous = None
        for row in row_ids:
            date, value = cells.get(f'A{row}'), cells.get(f'B{row}')
            if date is None and value is None:
                continue
            key = week_key(date)
            if key in values or (previous is not None and key <= previous):
                raise ValueError('Published dates must be unique and increasing')
            values[key] = float(value) if value is not None else float('nan')
            previous = key
        if not values:
            raise ValueError('Published factor contains no observations')
        return values


def load_published_factor(root):
    """Read the immutable original ZIP, not a rerun of M0 or a rounded table."""
    root = Path(root)
    archive = root / 'reference/dataverse_files.zip'
    with zipfile.ZipFile(archive) as original:
        if original.namelist().count(WORKBOOK_MEMBER) != 1:
            raise ValueError('Original ZIP must contain exactly one factor workbook')
        payload = original.read(WORKBOOK_MEMBER)
    # When the unmodified extracted reference is present, prove that the two
    # representations contain identical bytes. The ZIP is always the authority.
    extracted = root / 'reference/dataverse_original_3d0959b1' / WORKBOOK_MEMBER
    if extracted.exists() and extracted.read_bytes() != payload:
        raise ValueError('Extracted published workbook differs from original ZIP')
    series = workbook_series(payload)
    provenance = dict(source='author_published_factor_not_local_M0',
                      archive='reference/dataverse_files.zip',
                      archive_sha256=digest(archive.read_bytes()),
                      workbook_member=WORKBOOK_MEMBER, workbook_sha256=digest(payload),
                      worksheet='Data from Study', date_column='YYYYWW',
                      return_column='CTREND', return_units='decimal_weekly_HL_return',
                      calendar='author_52_within_year_blocks_not_ISO',
                      available_portfolio='H-L only; no quintile/holdings series inferred',
                      full_support=return_statistics(series))
    return series, provenance


def return_statistics(series):
    # Sample SD (ddof=1) and ordinary mean t replicate the Table 3 convention.
    # Statistical returns are never gap-filled, clipped, or compounded here.
    dates = sorted(t for t, value in series.items() if np.isfinite(value))
    z = np.asarray([series[t] for t in dates], dtype=float)
    n = len(z)
    mean = float(z.mean()) if n else float('nan')
    sd = float(z.std(ddof=1)) if n > 1 else float('nan')
    return dict(weeks=n, first_week=dates[0] if n else '', last_week=dates[-1] if n else '',
                mean_weekly_pct=100 * mean, std_weekly_pct=100 * sd,
                t=float(mean / sd * np.sqrt(n)) if sd > 0 else float('nan'),
                sharpe_annualized=float(mean / sd * np.sqrt(52)) if sd > 0 else float('nan'))


def common_support(series, ids):
    return sorted(set.intersection(*[{t for t, v in series[id].items() if np.isfinite(v)} for id in ids]))


def pair_summary(series, first, second, dates):
    # Pairwise intersections and the fixed all-series intersection answer
    # different questions. Always save the precise keys and contrast direction.
    a = {t: series[first][t] for t in dates}
    b = {t: series[second][t] for t in dates}
    x, y = np.asarray(list(a.values())), np.asarray(list(b.values()))
    sa, sb = return_statistics(a), return_statistics(b)
    delta = return_statistics({t: b[t] - a[t] for t in dates})
    correlation = float(np.corrcoef(x, y)[0, 1]) if len(dates) > 1 and np.std(x) > 0 and np.std(y) > 0 else float('nan')
    return dict(first=first, second=second, common_weeks=len(dates),
                first_week=dates[0] if dates else '', last_week=dates[-1] if dates else '',
                first_mean_pct=sa['mean_weekly_pct'], second_mean_pct=sb['mean_weekly_pct'],
                delta_mean_pp_second_minus_first=delta['mean_weekly_pct'],
                first_sharpe=sa['sharpe_annualized'], second_sharpe=sb['sharpe_annualized'],
                delta_sharpe_second_minus_first=sb['sharpe_annualized'] - sa['sharpe_annualized'],
                paired_spread_t=delta['t'], correlation=correlation,
                rmse_pp=float(100 * np.sqrt(np.mean((y - x) ** 2))) if len(dates) else float('nan'),
                shared_dates=';'.join(map(str, dates)))


def comparison_rows(paper, experiments):
    # Callers supply either authenticated saved baselines or freshly verified
    # registrations. This module never reads the curated experiment snapshot.
    if not experiments or 'Paper' in experiments:
        raise ValueError('Experiments must be nonempty and may not replace Paper')
    series = {'Paper': paper, **experiments}
    for values in series.values():
        for t in values:
            if week_key(t) != t:
                raise ValueError('Comparison dates must be integer YYYYWW keys')
    ids = tuple(series)
    shared = common_support(series, ids)
    if len(shared) < 2:
        raise ValueError('Fewer than two all-series common weeks')
    experiment_shared = set(common_support(series, tuple(experiments)))
    all_dates = sorted(set.union(*[set(v) for v in series.values()]))
    shared_set = set(shared)
    weekly = [dict(year_week=t, **{id: series[id].get(t, float('nan')) for id in ids},
                   all_eighteen_common=int(t in experiment_shared),
                   all_nineteen_common=int(t in shared_set)) for t in all_dates]
    own = [dict(series_id=id, **return_statistics(series[id])) for id in ids]
    common = [dict(series_id=id, **return_statistics({t: series[id][t] for t in shared})) for id in ids]
    pairs = [pair_summary(series, a, b, common_support(series, (a, b)))
             for a, b in itertools.combinations(ids, 2)]
    fixed = [pair_summary(series, 'Paper', id, shared) for id in experiments]
    return dict(series=series, own=own, common=common, pairs=pairs, fixed=fixed,
                weekly=weekly, shared=shared, experiment_shared=sorted(experiment_shared))


def write_csv(path, rows):
    with path.open('w', encoding='utf-8', newline='') as f:
        writer = csv.DictWriter(f, list(rows[0]), lineterminator='\n')
        writer.writeheader()
        writer.writerows(rows)


def markdown_table(rows, fields):
    def show(value):
        if isinstance(value, float):
            return f'{value:.4f}' if np.isfinite(value) else 'NA'
        return str(value).replace('|', r'\|')
    return '\n'.join(['| ' + ' | '.join(label for key, label in fields) + ' |',
                      '|' + '|'.join('---' for field in fields) + '|'] +
                     ['| ' + ' | '.join(show(row[key]) for key, label in fields) + ' |' for row in rows])


def export_paper_comparison(root, output, experiments):
    """Write numerical provenance and all supports; return the same evidence."""
    paper, provenance = load_published_factor(root)
    evidence = comparison_rows(paper, experiments)
    output = Path(output)
    output.mkdir(parents=True, exist_ok=True)
    provenance['comparison_series'] = len(evidence['series'])
    provenance['experiment_common_weeks'] = len(evidence['experiment_shared'])
    provenance['all_series_common_weeks'] = len(evidence['shared'])
    provenance['all_series_common_dates'] = evidence['shared']
    (output / 'PAPER_FACTOR_PROVENANCE.json').write_text(json.dumps(provenance, indent=2, allow_nan=False) + '\n')
    write_csv(output / 'PAPER_WEEKLY_RETURNS.csv', [dict(year_week=t, paper_hl_return=r) for t, r in paper.items()])
    for name, key in [('NINETEEN_WAY_WEEKLY_RETURNS', 'weekly'),
                      ('NINETEEN_WAY_OWN_SUPPORT_SUMMARY', 'own'),
                      ('NINETEEN_WAY_ALL_COMMON_SUMMARY', 'common'),
                      ('NINETEEN_WAY_PAIRWISE_COMMON_SUMMARY', 'pairs'),
                      ('PAPER_EXPERIMENT_ALL_COMMON_COMPARISONS', 'fixed')]:
        write_csv(output / f'{name}.csv', evidence[key])
    # Expose source-versus-replication sample differences explicitly: overall
    # moment agreement cannot conceal earlier dates or missing formation weeks.
    support_rows = []
    paper_dates = {t for t,v in paper.items() if np.isfinite(v)}
    for id, values in experiments.items():
        experiment_dates = {t for t,v in values.items() if np.isfinite(v)}
        for t in sorted(paper_dates ^ experiment_dates):
            support_rows.append(dict(experiment_id=id, year_week=t,
                support_status='author_only' if t in paper_dates else 'experiment_only'))
    # A future exact-support replication legitimately has no discrepancies.
    with (output / 'PAPER_EXPERIMENT_SUPPORT_DIFFERENCES.csv').open('w', newline='') as f:
        writer = csv.DictWriter(f, ['experiment_id','year_week','support_status'], lineterminator='\n')
        writer.writeheader()
        writer.writerows(support_rows)
    summary_fields = [('series_id', '序列'), ('weeks', '有限周'), ('first_week', '首周'),
                      ('last_week', '末周'), ('mean_weekly_pct', '周均值%'),
                      ('std_weekly_pct', '标准差%'), ('t', '普通均值 t'),
                      ('sharpe_annualized', '年化 Sharpe')]
    pair_fields = [('second', '实验'), ('common_weeks', '配对周数'),
                   ('first_mean_pct', '作者均值%'), ('second_mean_pct', '实验均值%'),
                   ('delta_mean_pp_second_minus_first', '实验−作者百分点'),
                   ('paired_spread_t', '收益差配对 t'), ('first_sharpe', '作者 Sharpe'),
                   ('second_sharpe', '实验 Sharpe'), ('correlation', '相关系数')]
    p = provenance['full_support']
    interpretation = ''
    indexed = {r['second']:r for r in evidence['fixed']}
    if all(f'P0_M{m}_D{d}' in indexed for m in (0,2,1) for d in range(3)):
        m0, m2 = indexed['P0_M0_D0'], indexed['P0_M2_D0']
        m1 = [indexed[f'P0_M1_D{d}'] for d in range(3)]
        interpretation = f'''## 主要读数与含义

在固定十九方共同周上，P0/M0/D0 相对作者均值差为
{m0['delta_mean_pp_second_minus_first']:.4f} 个百分点（配对 t={m0['paired_spread_t']:.4f}）；
P0/M2/D0 为 {m2['delta_mean_pp_second_minus_first']:.4f} 个百分点
（配对 t={m2['paired_spread_t']:.4f}），但 Sharpe 由作者的
{m2['first_sharpe']:.4f} 变为 {m2['second_sharpe']:.4f}。
判断指定前视通道的修复是否改变收益证据，必须同时查看均值和风险，
不能预设均值一定下降或消失。

P0/M1 的 D0、D1、D2 相对作者均值差依次为
{', '.join(f"{r['delta_mean_pp_second_minus_first']:.4f}" for r in m1)} 个百分点，
配对 t 依次为 {', '.join(f"{r['paired_spread_t']:.4f}" for r in m1)}。
经济幅度与检验精度须分开报告：不能仅凭均值变化就宣布差异显著，
普通配对 t 不包含 HAC 或多重检验调整。
十九方共同日期没有令方法定义、训练样本或资产集合变成相同；这不是单一错误的
独立因果效应，也不证明报价可成交或组合可做空。

'''
    text = f'''# 作者公布因子与十八项实验：逐周对齐的十九方比较

## 数据来源和可比较范围

作者的实际 H-L 序列来自未改动的 `reference/dataverse_files.zip` 中
`{WORKBOOK_MEMBER}`，工作表 `Data from Study`，不是本项目 M0 重跑收益。
工作簿 SHA256：`{provenance['workbook_sha256']}`。逐周原值见
[PAPER_WEEKLY_RETURNS.csv](PAPER_WEEKLY_RETURNS.csv)，完整来源与共同日期见
[PAPER_FACTOR_PROVENANCE.json](PAPER_FACTOR_PROVENANCE.json)。

日期沿用作者的每年 52 周分块 YYYYWW，而非 ISO 周；按日期键连接，收益使用小数原值。
原序列的完整有限支持为 {p['weeks']} 周（{p['first_week']}–{p['last_week']}）：
周均值 {p['mean_weekly_pct']:.8f}%，标准差 {p['std_weekly_pct']:.8f}%，
普通均值 t={p['t']:.8f}，年化 Sharpe={p['sharpe_annualized']:.8f}。
Table 3（期刊 p.3130；PDF p.15）的披露值另保留在论文基准表，
不以实验值反推作者序列。作者与每个实验各自有限日期的差异见
[PAPER_EXPERIMENT_SUPPORT_DIFFERENCES.csv](PAPER_EXPERIMENT_SUPPORT_DIFFERENCES.csv)。

## 各自支持：不能直接当作同样本方法效应

{markdown_table(evidence['own'], summary_fields)}

## 全十九方共同支持：主要同样本比较

十八项实验的共同支持为 {len(evidence['experiment_shared'])} 周；加入作者序列后为
{len(evidence['shared'])} 周（{evidence['shared'][0]}–{evidence['shared'][-1]}，不保证连续）。
下表每一行均使用这同一日期集合。不填充统计收益，不重新估计任何模型。

{markdown_table(evidence['common'], summary_fields)}

## 作者与各实验各自的配对共同支持

配对支持可大于全十九方交集，因此这张表的差值不能直接拼接为 P/M/D 路径。
差值方向均为实验减作者；t 检验逐周收益差的均值，不是 Sharpe 差检验。

{markdown_table([r for r in evidence['pairs'] if r['first'] == 'Paper'], pair_fields)}

## 固定全十九方支持的作者−实验比较

{markdown_table(evidence['fixed'], pair_fields)}

{interpretation}## 统计与解释边界

均值/标准差为周百分数，Sharpe 按 √52 年化，标准差使用 n−1 分母。
普通均值 t 与配对差 t 未进行 HAC 或多重检验调整；不能把 Sharpe 的数值差
直接称为显著差，也不能凭这些配对值识别单一代码缺陷的因果贡献。
匹配原文四舍五入的总体统计量不意味着逐周序列完全相同；相关系数和 RMSE
记录在 [NINETEEN_WAY_PAIRWISE_COMMON_SUMMARY.csv](NINETEEN_WAY_PAIRWISE_COMMON_SUMMARY.csv)。
该表包含全部两两日期交集，固定支持的作者配对另见
[PAPER_EXPERIMENT_ALL_COMMON_COMPARISONS.csv](PAPER_EXPERIMENT_ALL_COMMON_COMPARISONS.csv)。
主键面板与两个共同周标记见
[NINETEEN_WAY_WEEKLY_RETURNS.csv](NINETEEN_WAY_WEEKLY_RETURNS.csv)。

作者工作簿只提供 CTREND H-L，不提供分位腿、逐币持仓或 3,072 个研究设计。
因此 L/H、固定权重交换 payoff、持仓重合度及设计单元配对仍限于实验数据；
不能拿本项目 M0 的这些对象冒充作者原始输出。
'''
    (output / 'NINETEEN_WAY_COMMON_WEEK_COMPARISON_CN.md').write_text(text, encoding='utf-8')
    evidence['provenance'] = provenance
    return evidence
