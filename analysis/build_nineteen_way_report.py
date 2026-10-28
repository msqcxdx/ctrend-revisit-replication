#!/usr/bin/env python3
# CTREND_REVISIT_FILE_PURPOSE: build nineteen way report; publication orchestration, validation or saved-result analysis, not a model-definition edit.
# Inputs: curated paper benchmarks, eighteen accepted baseline exports, and
# machine-readable common-week/diagnostic CSVs already checked elsewhere.
# Output: publication Markdown/CSV companions under results/comparisons.
# Boundary: this formatter never loads training panels or estimates a model;
# every displayed contrast must remain traceable to an accepted saved result.
"""Merge paper-item evidence, common-week results and P/M/D ablations.

Uses only accepted exported returns and diagnostics. All contrasts are rebuilt
on one all-eighteen finite-week support; no missing week is replaced by zero.
"""
from pathlib import Path
import csv,itertools,math,statistics,re
from publication_style import display_cell,format_tables
from publication_evidence import factor_companion
from paper_factor_comparison import export_paper_comparison

ROOT=Path(__file__).resolve().parents[1]
OUT=ROOT/'results/comparisons'
FIRST=OUT/'source_tables'
DIAG=ROOT/'results/diagnostics/portfolio_diagnostics'
# Small I/O and formatting helpers keep the report body below declarative.
def read(p):return list(csv.DictReader(p.open()))
def write(name,rows):
    with (OUT/name).open('w',newline='') as f:
        w=csv.DictWriter(f,list(rows[0]),lineterminator='\n');w.writeheader();w.writerows(rows)
def fmt(x):
    return display_cell(x).replace('|','\\|').replace('\n',' ')
def table(rows,cols):
    return '\n'.join(['| '+' | '.join(label for key,label in cols)+' |',
       '|'+'|'.join('---' for _ in cols)+'|']+
       ['| '+' | '.join(fmt(r[key]) for key,label in cols)+' |' for r in rows])+'\n'
def stats(x):
    n=len(x);mean=statistics.mean(x);sd=statistics.stdev(x)
    return dict(n=n,mean_pct=100*mean,std_pct=100*sd,
        paired_t=math.sqrt(n)*mean/sd if sd else math.nan,
        sharpe=math.sqrt(52)*mean/sd if sd else math.nan)

weekly=read(FIRST/'common_week/eighteen_experiment_weekly_returns.csv')
ids=[x for x in weekly[0] if x.startswith('P')]
common=[r for r in weekly if all(math.isfinite(float(r[id])) for id in ids)]
assert len(common)>1 and all(int(r['all_eighteen_common'])==1 for r in common)
series={id:[float(r[id]) for r in common] for id in ids}
own={r['experiment_id']:r for r in read(FIRST/'exact_headline_from_mat.csv')}
# The nineteenth comparator is the author's authenticated workbook, not an M0
# rerun. Keep the existing eighteen-cell mechanism support separately named.
paper_evidence=export_paper_comparison(ROOT, OUT/'paper_factor',
    {id:{int(r['year_week']):float(r[id]) for r in weekly} for id in ids})
paper_common_text=(OUT/'paper_factor/NINETEEN_WAY_COMMON_WEEK_COMPARISON_CN.md').read_text()
paper_common_text='\n'.join(paper_common_text.splitlines()[1:])
paper_common_text=re.sub(r'\]\(([^()/]+)\)',r'](paper_factor/\1)',paper_common_text)
paper_common_text=re.sub(r'^(#{2,5}) ',r'#\1 ',paper_common_text,flags=re.M)
companions=[r for id in ids for r in factor_companion(ROOT/'results/experiments',id)]
write('FACTOR_FIGURE_NUMERICAL_COMPANION.csv',companions)
contrasts=[]
def contrast(axis,a,b):
    x,y=series[a],series[b];delta=[v-u for u,v in zip(x,y)]
    sa,sb,sd=stats(x),stats(y),stats(delta)
    r=dict(axis=axis,from_experiment=a,to_experiment=b,common_n=len(x),
        from_mean_pct=sa['mean_pct'],to_mean_pct=sb['mean_pct'],difference_pp=sd['mean_pct'],
        paired_t=sd['paired_t'],from_sharpe=sa['sharpe'],to_sharpe=sb['sharpe'])
    contrasts.append(r);return r
# Build the declared P/M/D one-factor contrasts before composing prose.  The
# ordering M0, M2, M1 follows the ablation path rather than lexical order.
for m in (0,2,1):
 for d in range(3):contrast('P',f'P0_M{m}_D{d}',f'P1_M{m}_D{d}')
for p in range(2):
 for d in range(3):
  for a,b in ((0,2),(2,1),(0,1)):contrast('M',f'P{p}_M{a}_D{d}',f'P{p}_M{b}_D{d}')
for p in range(2):
 for m in (0,2,1):
  for a,b in ((0,1),(1,2),(0,2)):contrast('D',f'P{p}_M{m}_D{a}',f'P{p}_M{m}_D{b}')
write('P_M_D_KEY_CONTRASTS_ALL_COMMON.csv',contrasts)

interactions=[]
for p in range(2):
 for ma,mb in ((0,2),(2,1),(0,1)):
  for da,db in ((0,1),(1,2)):
    a=f'P{p}_M{ma}_D{da}';b=f'P{p}_M{ma}_D{db}'
    c=f'P{p}_M{mb}_D{da}';d=f'P{p}_M{mb}_D{db}'
    z=[(v-u)-(y-x) for x,y,u,v in zip(series[a],series[b],series[c],series[d])]
    st=stats(z);interactions.append(dict(p_id=f'P{p}',method_change=f'M{ma}->M{mb}',
        data_change=f'D{da}->D{db}',common_n=len(z),interaction_pp=st['mean_pct'],paired_t=st['paired_t']))
write('METHOD_DATA_INTERACTIONS_ALL_COMMON.csv',interactions)
paths=[]
for p in range(2):
 for d in (1,2):
  for label,nodes in [('method_then_data',[f'P{p}_M0_D0',f'P{p}_M2_D0',f'P{p}_M1_D0',f'P{p}_M1_D{d}']),
                      ('data_then_method',[f'P{p}_M0_D0',f'P{p}_M0_D{d}',f'P{p}_M2_D{d}',f'P{p}_M1_D{d}'])]:
    changes=[stats([y-x for x,y in zip(series[a],series[b])])['mean_pct'] for a,b in zip(nodes,nodes[1:])]
    total=stats(series[nodes[-1]])['mean_pct']-stats(series[nodes[0]])['mean_pct']
    assert abs(sum(changes)-total)<1e-10
    paths.append(dict(p_id=f'P{p}',destination=f'D{d}',path=label,nodes=' -> '.join(nodes),
        step1_pp=changes[0],step2_pp=changes[1],step3_pp=changes[2],total_pp=total,common_n=len(common)))
write('KEY_PATH_DECOMPOSITIONS_ALL_COMMON.csv',paths)

shock=[]
ix=next(i for i,r in enumerate(common) if r['year_week']=='202016')
for p in range(2):
 for m in (0,2,1):
    a=f'P{p}_M{m}_D0';b=f'P{p}_M{m}_D1';z=[y-x for x,y in zip(series[a],series[b])]
    total=100*statistics.mean(z);single=100*z[ix]/len(z)
    shock.append(dict(p_id=f'P{p}',method=f'M{m}',common_n=len(z),
        d1_minus_d0_pp=total,week202016_difference_pct=100*z[ix],
        week202016_contribution_to_mean_pp=single,share_of_total=single/total if total else math.nan,
        other_weeks_difference_mean_pp=100*statistics.mean(z[:ix]+z[ix+1:])))
write('INNBCL_WEEK_CONTRIBUTION_TO_DATA_CONTRAST.csv',shock)

cols=[('from_experiment','起点'),('to_experiment','终点'),('from_mean_pct','起点均值%'),
      ('to_mean_pct','终点均值%'),('difference_pp','变化百分点'),('paired_t','配对 t'),
      ('from_sharpe','起点 Sharpe'),('to_sharpe','终点 Sharpe')]
head='''# CTREND 的可复现性与经济含义：预处理、方法和资产范围的分解

## 摘要

本研究将原论文报告值与十八组可复现实验相对照，考察技术趋势因子的收益证据对
信息时间、估计方法、缺失值处理和资产范围的敏感性。原实现涉及多类值得审查的
问题，其中数据前视最具原则性：若形成信号或选择资产时使用当时尚不可得的信息，
回测就不能直接解释为样本外投资表现。但前视并非唯一问题；标签清洗对量价历史的
连带影响、预测支持、收益会计与论文定义之间的差异，也可能改变结论。

因此，研究目的不仅是识别错误，更是区分不同处理的实证影响。M0 基本复现论文；
M2 对指定前视通道及相关终止结算的修正并未使主要平均收益消失，但收益波动上升、
Sharpe 下降。M1 采用更全面的统计与会计修正后，保留全部资产时平均收益接近零；
排除 INNBCL 后平均收益约为每周 2.66%，进一步排除事件资产后约为 2.50%–2.51%。
这些结果表明，方法与资产暴露之间的交互比“修正错误必然降低收益”的线性解释更重要。
前视问题的原则性不因其平均收益影响有限而减弱，亦不能据此把全部收益归因于前视。

## 研究设计与阅读说明

| 维度 | 实验定义 | 比较目的 |
|---|---|---|
| P：缺失值处理 | P0 不启用统一填充；P1 使用前一有效收盘价填充区间内 OHLC 缺失，非法成交量/额置零 | 衡量输入约定对指标、样本与权重的影响 |
| M：方法 | M0 为公开实现；M2 为指定前视修复与终止结算组合；M1 为全面审计方法 | 区分时间信息问题与其他统计、会计和定义问题 |
| D：资产范围 | D0 保留原始 CMCID；D1 全历史排除 INNBCL；D2 再排除 27 个事件资产 | 衡量资产集合敏感性，不判断每笔报价真假或修补单位 |

M0→M2→M1 表示有明确边界的方法对照。三个维度交叉形成十八项实验，
使用相同数据来源；它们不是十八个独立样本。M1/M2 的机械退出日历由完整价格历史
构造，是对提前可交易性信息的研究代理假设，并无实际公告时间数据支持。其适用边界
贯穿全文，不能由“运行前冻结”推导出真实历史可知性。

本报告先展示主要结果及共同周稳健性，再讨论机制与解释边界，最后按原论文编号逐图
逐表列示证据。收益均为周百分比，Sharpe 按 √52 年化；显示值适度舍入，原始精度保留在
CSV/MAT。作者公布的 `CTREND.xlsx` 实际 H-L 序列参与十九方共同周和配对比较；
论文其他未披露的持仓、分位腿和设计单元不以 M0 的结果代替。

- [一、主要结果与共同周稳健性](#common-support)
- [二、机制分解与解释边界](#mechanisms)
- [三、原论文逐图逐表证据](#paper-evidence)

'''
first=(FIRST/'ALL_PAPER_ITEMS_NINETEEN_WAY_COMPARISON_CN.md').read_text()
first=first[first.index('## Table 1'):]
first=first.split('## 综合解释与表述边界')[0]
supplement='\n### CTREND 补充统计与 Figure 1 数值来源\n\n'
supplement+='下表的周数、均值、标准差及 Sharpe 从 baseline MAT 的自身有限 H-L 周重算，不把它们自动当作四因子共同支持统计。Figure 1 的均值与 Sharpe 则独立读取保存 FIG 的柱高；完整四因子底稿及文件哈希见 [FACTOR_FIGURE_NUMERICAL_COMPANION.csv](FACTOR_FIGURE_NUMERICAL_COMPANION.csv)。底稿的 ctrend_moments_match 记录两种口径数值是否一致，不要求未来复现必须一致。\n\n'
supplement+=table([r for r in companions if r['factor']=='CTREND'],[
    ('experiment_id','实验'),('baseline_own_weeks','基准自身周数'),
    ('baseline_own_mean_pct','基准均值%'),('baseline_own_std_pct','基准标准差%'),
    ('baseline_own_sharpe_annualized','基准 Sharpe'),('figure_mean_pct','FIG 均值%'),
    ('figure_sharpe_annualized','FIG Sharpe')])+'\n'
first=first.replace('## Table B.3',supplement+'## Table B.3',1)
# The supplied journal PDF has 38 physical pages, starting at printed p.3116.
# Derive reader navigation from printed journal pages without altering statistics.
locations=[]
def correct_location(match):
    old=match.group(0)
    printed=[int(x) for x in re.findall(r'\d+',match.group(1))]
    physical=[x-3115 for x in printed]
    assert all(1 <= x <= 38 for x in physical)
    new=('PDF p.' if len(physical)==1 else 'PDF pp.')+'–'.join(map(str,physical))+'（期刊 '+match.group(1)+'）'
    locations.append(dict(original_location=old,corrected_location=new,
                          source='Journal PDF: 38 physical pages; printed pp.3116–3153'))
    return new
first=re.sub(r'PDF pp?\.[0-9–]+（期刊 (p{1,2}\.[0-9–]+)）',correct_location,first)
first=first.replace('论文位置：Table 3 后的正文图。Figure 1 的数值底稿即 Table B.2；论文 CTREND 为 Avg 3.87、Sharpe 1.94。',
    '论文位置：PDF p.2（期刊 p.3117），引言中的 Figure 1，并非 Table 3 之后。图中未逐柱标注精确数值；作为四因子数值参照，Table B.2 披露 CTREND Avg 3.87、Sharpe 1.94，不能把这些数说成直接从柱图读出的精确值。')
first=first.replace('论文位置：Table 6 对应的研究设计分布图。',
    '论文位置：PDF p.23（期刊 p.3138），Table 6 对应的研究设计分布图。')
first=first.replace('论文位置：正文 anomaly-alpha 图及其数值底稿。',
    '论文位置：PDF p.28（期刊 p.3143），正文 anomaly-alpha 图及其数值底稿。')
locations.append(dict(original_location='Figure 1: after Table 3',
    corrected_location='Figure 1: PDF p.2 / printed p.3117, introduction',
    source='Journal PDF SHA256 f430d1ec7406d09e02e56149d5651150de59a42014c4bc8b15d4a6a5777dab84'))
write('PAPER_ITEM_LOCATIONS.csv',[dict(location=x['corrected_location'],source=x['source']) for x in locations])
commontext=(FIRST/'COMMON_WEEK_COMPARISON_CN.md').read_text()
commontext='\n'.join(commontext.splitlines()[1:])
commontext=commontext.replace('](../paper_factor/','](paper_factor/')
# The same method contrasts are presented with interpretation in Section 2;
# retain their precise numerical source without duplicating a very wide table.
commontext=re.sub(r'## 3\. 每个 P/D 内.*?(?=## 4\.)','',commontext,flags=re.S)
commontext=commontext.replace('## 4. 完整审计文件','## 数据与计算口径')
legrows=read(DIAG/'COMMON_WEEK_LEGS_AND_HL.csv')
leglookup={(x['experiment_id'],x['portfolio']):x for x in legrows}
legtable=[]
for id in ids:
    row={'experiment':id}
    for k in ['L','H','H-L']:row[k]=float(leglookup[id,k]['mean_pct'])
    legtable.append(row)
commontext+='\n## 共同周上的 L 腿、H 腿与 H-L\n\n'+table(legtable,[('experiment','实验')]+[(k,k+' 周均值%') for k in ['L','H','H-L']])
commontext+='\n这里固定同一组十八方 H-L 可观测周，再取两条腿；不会为某一腿另换样本。完整的波动、均值 t 与年化 Sharpe 见 `../diagnostics/portfolio_diagnostics/COMMON_WEEK_LEGS_AND_HL.csv`。中间分位并不保证在这些周均有限，故不混入这张固定支持表。共同周基准比较不等于所有附表 alpha/交易成本口径均已重新估计；后者仍须按各自回归/会计支持解读第一部分原表。\n'
commontext=re.sub(r'^(#{2,5}) ',r'#\1 ',commontext,flags=re.M)
parts=[head,'''\n<a id="common-support"></a>

## 一、主要结果与共同周稳健性

作者序列和十八组实验按作者每年 52 周的 YYYYWW 日期键求有限 H-L 交集。
共同周分析只解决日历样本差异；模型、训练样本、持仓与原始收益定义仍可能不同。
同一组上的 mean/Sharpe 比较也不能单独识别每一处代码修正的因果贡献。
这里的 t 值按已保存基准的普通均值 t 口径计算，配对 t 则检验逐周收益差的均值；
不是将两个独立 t 值相减，也不宣称控制了多重比较。

''',paper_common_text,'\n### 十八项实验的组合腿与机制支持\n\n',commontext,
'''\n<a id="mechanisms"></a>

## 二、机制分解与解释边界

### 2.1 比较对象与识别范围

P 是输入缺失值处理：P0 不做统一填充；P1 在首个至最后原始正收盘价之间，以严格更早
的有效 close 填 OHLC 缺失，非有限/负成交量或成交额置零。既不填最初价格，也不延长
最终价格尾部。价格延续是一种常见但有代价的选择，可能制造零变动、改变波动和窗口
支持；成交量零填也可能把“不知道”编码为“无交易”。因此设立 P0 作为对照，不把 P1
写成所有研究都必须采用的唯一正确预处理。两者仍保留原 pipeline 的市值/价格/历史
长度等筛选。

P 维度还包含成交量零值的配套语义。P0/M2 与 P0/M0 的 b02 成交量块一致：
整行零或缺失的成交量置为缺失，`volume <= 1e-6`（包括零）置为 NaN；其后仍
保留原来的零成交量/非零收益条件，但零已在前一阈值中处理。P1/M0 与 P1/M2
则保留显式零，只屏蔽 `0 < volume <= 1e-6` 的小正数。零是数值观测，NaN 是
不可用，两者会产生不同的成交量型指标和有效样本。这不是数据前视修复，不能
在固定 P 的 M0→M2 对比中额外改变。P 的效应因此是统一填充及其下游成交量
约定的联合效应，而不是单独延续价格的效果；是否更合理不能仅由收益高低判断。

M 是方法：M0 除运行必要和已验证数值等价的工程修改，保留公开代码。M2 保留 M0 的
指标、共同预测变量支持、选择/组合等定义，修复明确的未来价格读取、目标标签
自清洗、估计支持/筛选和换手时序问题，并采用约定的端点收益与终止结算路径。
M1 进一步分离统计标签和经济收益，保护量价历史，实施 predictor-own-support、固定
selected-set 平均、严格日历窗口、单位/指标/成本和持有期会计修正。

机械退出日历用完整样本的最后正 close 构造，并被当作预先可知的退出安排。
这是一项明确的公告替代假设；运行前冻结能保证可复核，却不能凭空证明真实公告在
当时已发布。因此 M1/M2 的前视修复结论应限定于该约定下的直接数值通道，不应写成
不依赖任何未来可用性假设的纯实时交易证明。D1/D2 也是事后资产集合敏感性。

D 是数据集合：D0 原始 CMC；D1 删除 CMCID 3787；D2 进一步删除事件资产。所有删除
发生在原始 panel 层，影响训练、截面 rank、权重与市场变量，必须理解为重新估计的
研究设计，不能等同于只从最终组合里扣掉一个币的贡献。

### 2.2 缺失值处理：P0 与 P1

以下九个对比均只改变 P，且保持 M/D 与共同日历一致。

''',table([r for r in contrasts if r['axis']=='P'],cols),
'''\nP 改变历史可用性与局部波动，因此会传到技术指标、训练样本和预测。但三种方法的
own-support 周数在两种 P 下分别仍为 M0=349、M2=353、M1=337；P 没有补齐这些
跨方法的形成周差异。M1 的 P 效应特别小，这与其把标签清洗和量价历史分离相符。
M0/M2 在统一填充之后仍运行原来的 outlier/synchronization 路径，后续还能再次制造
NaN，故 P1 不等于最终 X/Y 全部无缺失。不能把 M1 相对 M2 的大幅变化归给前值填充。

### 2.3 方法对照：M0、M2 与 M1

''',table([r for r in contrasts if r['axis']=='M'],cols),
'''\nM0→M2 的周均收益在 own support 上上升，但其波动更大，Sharpe 反而降低。
共同周并没有把 M2 变成“均值消失”的结果。这表明原实现不只污染信息时间，还通过
清洗、同步和收益定义改变尾部暴露；移除部分通道不保证均值必定下降。

M2→M1 一次改变多个机制：输入历史是否被标签筛选挖空、predictor 的可观测截面、
Eq.(7) 回归支持与归一权重、validation selected-set、组合 forecast 与经济 payoff
来源、成本/日历等。这里的差值是这些改动的联合影响。后面的持仓重合度和固定权重
交换可以拆开“不同持仓”与“同持仓不同 payoff”的部分差异，但仍不能给每项代码
修正分配一个唯一的贡献百分比。

### 2.4 资产范围：D0、D1 与 D2

''',table([r for r in contrasts if r['axis']=='D'],cols),
'''\nM0 与 M2 的日收益 WIN/TRUNC 操作在命中处同步把 close/OHLC/volume/市值等置为
NaN。WIN 与 TRUNC 的日收益对象不同（前者压阈值、后者置 NaN），但两者都能破坏
下游量价窗口。M2 修复历史标签清洗的时间范围，却有意保留这些 M0 特征历史定义。
M1 的 outlier 只作用于统计标签，不再用标签是否极端来删除量价历史，也不清洗真实
经济 payoff。所以某个原来因 predictor 缺失而不参与组合的资产，在 M1 中可能再次
获得预测并进入持仓。标签和量价分离揭示了原始价格跳变对收益的敏感性。

这不表示 M1 已经验证每一根原始 K 线可靠，更不证明极端收益真实可成交。D 轴的用途
正是展示：修复统计/会计实现以后，研究结论对原始数据中的特定资产与跳变集合是否
稳定。D2 不对价格进行乘除，不评价如何恢复单位切换；已确认 1:1 事件及不同 CMCID
之间的迁移也不会仅凭名称变化就纳入同一资产单位突变。冻结 D2 列表见
`../../config/exclusions/D2.csv`，包含 INNBCL 在内共 28 个 ID，新增 27 个事件资产。

### 2.5 INNBCL：单周影响与全历史重估

下表将每个方法的 D1−D0 共同周均值变化拆成 2020W16 那一周对总体均值的贡献，
以及其余共同周的平均差。删除这一周仅用于贡献解释，未修改任何主结果。

设共同周数为 N，逐周 D1−D0 差为 Δr，关注周为 τ，则
平均差 = Δrτ/N + (N−1)/N × 其余周平均差。表中“该周对均值贡献”已经除以 N；
“其余周均值差”需乘以 (N−1)/N 才能与前者相加。这区分了单周贡献与删周样本均值。

''',table(shock,[('p_id','P'),('method','M'),('d1_minus_d0_pp','D1−D0 均值差'),
('week202016_difference_pct','2020W16 收益差%'),('week202016_contribution_to_mean_pp','该周对均值贡献'),
('share_of_total','占总差比例'),('other_weeks_difference_mean_pp','其余周均值差')]),
'''\nM1 两个 P 下的 D0 都在该周出现约 −554.87% H-L。D1 的该周约 1.10%。
该周贡献 1.6498 个百分点，占 M1 的 D1−D0 总均值改善约 63.2%；其余共同周平均
差约 0.96 个百分点。一周解释了大部分，但不是全部，其余差异来自全历史样本和
模型/排序/权重的重新估计。H-L 是多空价差，理论上可低于 −100%；这不代表有限资本、
保证金和融券约束下的财富曲线可按同样规则实现。因此保留数字同时披露约束。
精确资产权重、预测及保存的 payoff 见 `../diagnostics/portfolio_diagnostics/INNBCL_2020W16_SAVED_HOLDINGS.csv`。

### 2.6 预测一致性与持仓重合度

重合度按共同日期和 CMCID 对齐；Jaccard 是同腿共同成员数除以并集成员数，权重 L1
包含只存在于一方的资产，不能先删掉不匹配资产再算相似度。下表展示 M2→M1；其余
P/D 一对一结果保存在对应 CSV，均绑定各实验的已验收基准持仓与预测。

''']
overlap=read(DIAG/'KEY_PAIR_FORECAST_HOLDINGS_OVERLAP.csv')
selected=[r for r in overlap if r['axis']=='M' and '_M2_' in r['from_experiment'] and '_M1_' in r['to_experiment']]
parts.append(table(selected,[('from_experiment','M2'),('to_experiment','M1'),('common_weeks','共同周'),
('forecast_correlation','预测相关'),('low_jaccard_mean','L 成员重合'),('high_jaccard_mean','H 成员重合'),
('weekly_return_correlation','收益相关')]))
parts.append('''\n### 2.7 固定权重收益交换：配置与收益定义的区分

共同有限预测单元上的 M2/M1 预测相关约为 0.989，但 L 腿成员 Jaccard 仅约
0.54–0.56，H 腿约 0.59–0.62。这两个现象并不矛盾：预测相关只看两边都有预测的
单元；新进入/退出预测支持的资产、边界排序和市值集中度，都能让持仓明显不同。
2020W16 两个 P 下 M1 的 INNBCL L 腿建仓权重约为 78.92%，而 M0/M2 没有该币
的有限预测；保存的 INNBCL payoff 在 M1 与 M2 中都为 +703.14%。因此这一周的
关键区别是是否持有以及持有多少，不能写成 M2 没看见同一个经济价格涨幅。

每个 P/D 对比使用 M2、M1 两套原始建仓权重与两套保存的 endpoint payoff，形成四个
角点。为保持经济恒等式成立，只使用两种方法均没有周内退出/再投资交易，且四角点
持仓收益全部可计算的共同周。周内结算会改变权重，因此静态的建仓权重×端点收益
无法代表含再投资交易的完整账本。程序验证两个原生角点与保存的原收益一致，
容差为 `1e-10`；没有把缺失币种补零或删后重加权。

''')
parts.append(table(read(DIAG/'FIXED_WEIGHT_ENDPOINT_EXCHANGE.csv'),[
('from_experiment','M2'),('to_experiment','M1'),('corner','固定权重/收益来源'),('n','共同周'),
('mean_pct','周均值%'),('std_pct','标准差%'),('t','t'),('sharpe','Sharpe')]))
parts.append('''\n这里 `WM2_RM1` 表示保留 M2 的持仓权重，只替换为 M1 的 payoff。
同一 W 下换 R 是收益定义敏感性；同一 R 下换 W 是预测、选择与权重的联合敏感性。
四个角点相等或接近，只能说明这个受限样本上 payoff 通道不主导，不能外推到被排除
的终止交易周、其它设计或不同时间区间。

六个 P/D 单元中，固定同一套 W 后，换成另一方法的 R，统计结果
均一致；变化来自换 W。例：P1/D1 的 204 个合格周上，M2 权重均值为 5.6839%，
M1 权重均值为 3.3662%，两套 endpoint 互换不改变各自结果。它支持“受限样本中
预测支持、持仓和权重是主因”，不支持把整个 M2→M1 跌幅都归因于 payoff 公式。

### 2.8 方法与资产范围的交互

下表的交互是“后一个 M 的 D 改动效果−前一个 M 的 D 改动效果”。全部仍在同一组
共同周上。交互大，说明数据敏感性依赖所用方法；它不等于确认某个币数据一定错误。

''')
parts.append(table(interactions,[('p_id','P'),('method_change','M 改动'),('data_change','D 改动'),
('interaction_pp','交互百分点'),('paired_t','配对 t')]))
parts.append('''\n### 2.9 路径分解与贡献的条件性

下面两条路径都从 M0D0 到 M1D1 或 M1D2。一条先修 M 再改 D；另一条先改 D 再修 M。
每条路径三个差值精确加总到相同终点差（已用 `1e-10` 检验）。这避免把一条路径的
单步变化当成独立于背景的“贡献”。没有选择性切换各方法 own weeks 来拼接路径。

''')
parts.append(table(paths,[('p_id','P'),('destination','终点 D'),('nodes','路径'),('step1_pp','第一步'),
('step2_pp','第二步'),('step3_pp','第三步'),('total_pp','总变化')]))
parts.append('''\n### 2.10 统计推断与经济解释

收益水平、方法差异与可交易性是三个不同问题。某方法的均值显著为正，不表示其相对
另一方法的差异显著；较大的点估计变化，也可能伴随较大的差值方差。例如 M1 的
D1−D0 均值改善约 2.61 个百分点，但普通配对 t 约为 1.32，不能仅凭变化幅度声称
获得精确估计的普遍改善。P 维度九项配对 t 的绝对值均低于 1.96，这表示该检验下
证据不足，并不是两种预处理等价的证明。

所列普通均值 t 和配对 t 未做序列相关稳健调整，也未校正多重比较。极端单周影响
意味着推断对尾部观测敏感，故这些统计量适合描述计算消融，不宜替代预先规定的
稳健推断。共同周分析控制的是报告日历，不能统一训练资产、预测支持或模型选择；
共同支持本身也可能选择较易形成组合的市场状态。

综合而言，M2 的结果不支持“前视修复足以使主要平均收益消失”，而 M1 揭示了更强的
方法—数据交互。D1/D2 中仍有正的未扣成本收益，但因子调整、成本与样本覆盖的证据
须分别评价。D 轴排除是全历史样本敏感性，不证明被排除报价错误；机械退出日历和
可做空性假设也不由结果检验自动验证。研究结论应限定在这些明确的设计与假设之内。

''')
paper_intro='''\n<a id="paper-evidence"></a>

## 三、原论文逐图逐表证据

各项保留论文列，十八项实验分为 P0、P1 两个面板。正文按论文编号排列，附录使用
其独立编号；PDF 页码按期刊文件的 38 个物理页计（首个印刷页为 3116）。全分位、
控制变量及扩展口径保留在实验 TeX/CSV 中。未明确披露的论文数值不作推测填入。
主要结果的收益单位为周百分比，t 值在对应表注下解释。单项图表与共同周分析的样本
口径可能不同，不能直接混用。图形文件提供 PNG 与可检查的 FIG 数值对象。

'''
# Numbered paper items retain their own ordering independent of analysis order.
sections=[x for x in re.split(r'(?=^## )',first,flags=re.M) if x.strip()]
def paper_order(section):
 title=section.splitlines()[0]
 match=re.match(r'## Table (B\.)?(\d+)',title)
 if match:return (0 if not match.group(1) else 1,int(match.group(2)))
 match=re.match(r'## Figures? ([BC]\.)?(\d+)',title)
 if match:return (2 if not match.group(1) else 3 if match.group(1)=='B.' else 4,int(match.group(2)))
 return (5,0)
first='\n'.join(sorted(sections,key=paper_order))
first=re.sub(r'^## ', '### ',first,flags=re.M)
first=re.sub(r'^### P([01])$',r'#### P\1 面板',first,flags=re.M)
correction_note='../../analysis/isolated_corrections/CORRECTION_COMPARISON_CN.md'
first=first.replace(
    '### Table 7：Frontier Expansion\n\n',
    '### Table 7：Frontier Expansion\n\n'
    'M1 沿 Σ⁻¹μ 的切点方向，用正比例系数缩放至目标波动率；零成本因子组合'
    '不强制权重和为 1，避免负的归一化分母反转方向。下表六组 M1 各七项'
    f'均采用这一口径，其同输入计算、共同周及来源哈希见[计算依据]({correction_note})。'
    'Table 7 使用保存的因子序列，不改变 CTREND 预测和基准收益。\n\n')
first=first.replace(
    '### Table B.5：Insignificant Anomalies（H-L）\n\n',
    '### Table B.5：Insignificant Anomalies（H-L）\n\n'
    '原作者 b02 计算 `delay` 时把扩展回归的第 4 个输出当成 R²；'
    '原函数第 4 个输出实际是残差偏度，第 5 个才是 R²。M0/M2 按其消融范围'
    '保留原公式；下表 M1 使用第 5 个输出计算 delay。'
    f'[十八组同输入对照]({correction_note})另行报告该原始源码问题的影响及 '
    'Table B.5/B.8 归类。`delay` 不是 CTREND 的 28 个技术预测量，'
    '这一单项比较不涉及 b09 模型重估。\n\n')
first=first.replace(
    '### Figure 3：Anomaly Alphas（All test assets）\n\n',
    '### Figure 3：Anomaly Alphas（All test assets）\n\n'
    'GRS 行须按方法口径阅读：原始 b11 把检验资产收益误传给 `fGRS` 的因子收益参数，'
    '因此 M0 和只修前视的 M2 保留了这一统计输入错误。M1 传入各模型实际因子收益，'
    '并在共同有限周上估计系统、仅去除完全重复的检验资产。因此下表的 M1 与 M0/M2 '
    'GRS p 值不是“其余条件不变、只替换一个参数”的单独消融；不能把差异全归因于这一行修复。\n\n')
parts.extend([paper_intro,first,'''\n## 数据、程序与复核

完整实验输出在 `../experiments/`，逐表数据在 `source_tables/`，诊断在
`../diagnostics/portfolio_diagnostics/`。统一复算入口为 `./run_all.sh b20`，
仅使用保存的基准结果，不重估模型；输入及输出成员由相应 SHA256 清单绑定。
'''])
text=''.join(parts).replace('解读第一部分原表','解读逐图逐表部分的对应原表')
text=text.replace('## 1. 各实验 own support','### 1.1 各方法的可用周样本').replace('## 2. 全 18 组共同周','### 1.2 十八组共同周样本')
text=text.replace('## 1. 各实验可用周样本','### 1.1 各方法的可用周样本')
text=text.replace('## 数据与计算口径','### 1.3 数据与计算口径').replace('## 共同周上的 L 腿、H 腿与 H-L','### 1.4 共同周上的多头、空头与多空收益')
(OUT/'NINETEEN_WAY_FULL_REPORT_CN.md').write_text(format_tables(text))
# A browsable companion exposes every saved image rather than claiming that
# hash equality or one headline statistic replaces inspection of the figures.
figure_names=sorted(p.name for p in (ROOT/'results/experiments'/ids[0]/'Figures').glob('*.png'))
fig=['# 十八组完整图形索引\n\n每项链接指向对应已验收 PNG；同目录还保留 FIG，便于核查坐标与曲线数值。图形经济口径见十九方报告的逐图逐表部分。\n']
for name in figure_names:
    fig.append('\n## '+name+'\n\n')
    fig.extend(f'- [{id}](../experiments/{id}/Figures/{name})\n' for id in ids)
(OUT/'FIGURE_INDEX_CN.md').write_text(''.join(fig))
print('MERGED_NINETEEN_WAY_REPORT_OK common=',len(common),'contrasts=',len(contrasts),
      'interactions=',len(interactions),'paths=',len(paths))
