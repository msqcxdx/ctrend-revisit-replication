#!/usr/bin/env python3
"""Render auditable SVGs from final CSV tables, without image-generation tools.

Interval labels distinguish HAC confidence intervals from correlated-design
percentiles. All holding phases are plotted; no favorable phase is selected.
The table index points to full CSVs rather than copying rounded plot values.
"""
import csv
from html import escape
import math
from pathlib import Path
import xml.etree.ElementTree as ET

ROOT=Path(__file__).resolve().parents[1];OUT=ROOT/'outputs'


def read(name):
    with (OUT/name).open(newline='') as f:return list(csv.DictReader(f))


def svg_interval(path,title,note,items,footer):
    """items=(label,estimate,lower,upper); interval type is required in note."""
    vals=[v for _,a,b,c in items for v in (a,b,c) if math.isfinite(v)]
    lo=min(0,min(vals));hi=max(0,max(vals));width=max(hi-lo,.01)
    lo-=width*.08;hi+=width*.08
    left,right=270,960;bottom=130+30*len(items)
    x=lambda v:left+(v-lo)/(hi-lo)*(right-left)
    out=[f'<svg xmlns="http://www.w3.org/2000/svg" width="1040" height="{bottom+100}" viewBox="0 0 1040 {bottom+100}">',
         '<rect width="100%" height="100%" fill="white"/>',
         '<g font-family="Arial,sans-serif" fill="#18283c">',
         f'<text x="30" y="36" font-size="22">{escape(title)}</text>',
         f'<text x="30" y="65" font-size="13">{escape(note)}</text>',
         f'<line x1="{x(0):.3f}" x2="{x(0):.3f}" y1="90" y2="{bottom}" stroke="#8d99a6" stroke-dasharray="5,4"/>']
    for i,(label,a,b,c) in enumerate(items):
        y=112+30*i
        out.append(f'<text x="30" y="{y+5}" font-size="13">{escape(label)}</text>')
        if not all(math.isfinite(v) for v in (a,b,c)):
            out.append(f'<text x="{left}" y="{y+5}">unidentified</text>');continue
        if not b<=a<=c:raise ValueError('Invalid plotted interval')
        out.extend([f'<line x1="{x(b):.3f}" x2="{x(c):.3f}" y1="{y}" y2="{y}" stroke="#26669a" stroke-width="3"/>',
                    f'<circle cx="{x(a):.3f}" cy="{y}" r="4.5" fill="#183c5e"/>'])
    for j in range(6):
        v=lo+(hi-lo)*j/5
        out.append(f'<text x="{x(v):.3f}" y="{bottom+24}" font-size="12" text-anchor="middle">{v:.2f}</text>')
    out.append(f'<text x="30" y="{bottom+70}" font-size="12">{escape(footer)}</text></g></svg>')
    text='\n'.join(out);ET.fromstring(text);path.write_text(text+'\n')


def main():
    holding=read('E10/published_ledger_vs_fixed_cohort.csv')
    for eid in sorted({r['experiment_id'] for r in holding}):
        group=[r for r in holding if r['experiment_id']==eid]
        items=[(f'H={r["holding_weeks"]}, phase={r["phase"]}; n={r["n_pair"]}',
            float(r['fixed_external_ltw_alpha_pct']),float(r['fixed_alpha_hac_ci_low_pct']),
            float(r['fixed_alpha_hac_ci_high_pct'])) for r in group]
        svg_interval(OUT/'E10'/f'holding_effect_precision_{eid}.svg',f'{eid}: fixed-cohort alpha, all phases',
            'Points: weekly alpha (%); lines: 95% HAC CI; external LTW; common fixed/original-sort weeks.',items,
            'Phases are dependent timing conventions, not independent replications. Statistical factor, not a margin account.')
    grid=read('E11/paired_design_summary.csv')
    for p in ('0','1'):
        for d in ('0','1','2'):
            group=[r for r in grid if r['p']==p and r['d']==d and r['from_method']=='M0' and r['to_method']=='M1']
            items=[(f'{r["method"]}; designs={r["valid_paired_design_count"]}',
                float(r['median_delta_sharpe']),float(r['p10_delta_sharpe']),float(r['p90_delta_sharpe'])) for r in group]
            svg_interval(OUT/'E11'/f'design_paired_distribution_P{p}_D{d}.svg',f'P{p} D{d}: annual Sharpe difference M1 - M0',
                'Points: median; lines: 10th-90th design percentiles (NOT confidence intervals).',items,
                'Each design uses paired weeks. Designs overlap and are not independent statistical trials.')
    tails=read('E08/tail_and_concentration_summary.csv')
    items=[(r['experiment_id'],float(r['mean_return_pct']),float(r['p01_return_pct']),float(r['p99_return_pct'])) for r in tails]
    # Means need not fall inside 1--99% quantiles for a heavy-tailed sample.
    # Plot the quantile midpoint instead; label it precisely rather than
    # pretending the interval is a confidence interval around the mean.
    items=[(label,(b+c)/2,b,c) for label,a,b,c in items]
    svg_interval(OUT/'E08/tail_quantile_ranges.svg','Weekly H-L tail ranges: all 18 experiments',
        'Lines: 1st-99th return percentiles (%); dot: interval midpoint, NOT mean or median.',items,
        'No tails deleted. Separate CSV reports mean, concentration and returns below -100%. Not a funded-account NAV.')
    flow='''<svg xmlns="http://www.w3.org/2000/svg" width="1100" height="230" viewBox="0 0 1100 230">
<rect width="1100" height="230" fill="white"/><g font-family="Arial,sans-serif" fill="#183c5e">
<text x="25" y="32" font-size="21">E07: from saved forecasts to returns</text>
<text x="25" y="58" font-size="13">Change one stated layer; compare all four portfolios on the SAME calendar.</text>
<rect x="25" y="85" width="220" height="65" fill="#eaf1f6"/><text x="40" y="111">Own / shared forecasts</text><text x="40" y="135" font-size="13">Formation cap and price</text>
<text x="254" y="123">→</text><rect x="280" y="85" width="220" height="65" fill="#eaf1f6"/><text x="295" y="111">Quintile membership</text><text x="295" y="135" font-size="13">Same M1 cap / payoff</text>
<text x="509" y="123">→</text><rect x="535" y="85" width="220" height="65" fill="#eaf1f6"/><text x="550" y="111">VW / EW / 10% cap</text><text x="550" y="135" font-size="13">No unpriced asset deletion</text>
<text x="764" y="123">→</text><rect x="790" y="85" width="280" height="65" fill="#eaf1f6"/><text x="805" y="111">Paired direct H-L / rank IC</text><text x="805" y="135" font-size="13">Exclude unresolved exit paths</text>
<text x="25" y="192" font-size="13">Conditional re-sorts of saved predictions, not retrained strategies or proof of real-world tradability.</text>
</g></svg>'''
    ET.fromstring(flow);(OUT/'E07/forecast_to_portfolio_path.svg').write_text(flow+'\n')
    print('FOLLOWUP_FIGURES_OK E07=1 E08=1 E10=6 E11=6')


if __name__=='__main__':main()
