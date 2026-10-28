#!/usr/bin/env python3
# CTREND_REVISIT_FILE_PURPOSE: Format research prose and displayed table cells without changing machine-readable statistical outputs.
# Inputs are strings already produced by analysis code. Formatting rounds only
# display cells and translates known headers; source CSVs retain full precision.
# The helper deliberately contains no sample selection or statistical formula.
"""Presentation conventions shared by the research report and reading tables."""
import re

LABELS = {
    'experiment':'实验', 'experiment_id':'实验', 'support':'样本口径', 'n':'周数',
    'start_year_week':'起始周', 'end_year_week':'结束周', 'mean_pct':'均值（%）',
    'std_pct':'标准差（%）', 't_stat':'均值 t', 'annualized_sharpe':'年化 Sharpe',
    'own_support':'可用周样本', 'all_eighteen_common':'十八组共同周',
    'p_id':'P', 'd_id':'D', 'common_n':'共同周数',
}

def display_cell(value):
    # Format one display value while preserving nonnumeric text verbatim.
    text=str(value).strip()
    if re.fullmatch(r'[+-]?\d*\.\d+(?:[eE][+-]?\d+)?',text):
        number=float(text)
        return f'{0.0 if abs(number)<0.00005 else number:.4f}'
    return LABELS.get(text,text)

def format_tables(text):
    # Apply display formatting only inside Markdown table rows.
    """Round display only; preserve identifiers, integer counts and raw CSVs."""
    result=[];headers=[]
    for line in text.splitlines():
        if line.startswith('|') and line.endswith('|'):
            cells=re.split(r'(?<!\\)\|',line[1:-1])
            if any(x.strip() in ('start_year_week','end_year_week') for x in cells):
                headers=[x.strip() for x in cells]
            out=[]
            for i,cell in enumerate(cells):
                raw=cell.strip()
                if i<len(headers) and headers[i] in ('start_year_week','end_year_week') and re.fullmatch(r'\d{6}',raw):
                    out.append(raw[:4]+'W'+raw[4:])
                else:
                    out.append(display_cell(raw))
            line='| '+' | '.join(out)+' |'
        elif line.strip():
            headers=[]
        result.append(line)
    return '\n'.join(result)+'\n'
