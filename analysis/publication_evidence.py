#!/usr/bin/env python3
# CTREND_REVISIT_FILE_PURPOSE: Read paper benchmarks and numerical Figure 1 companions from saved results without estimating models.
# Readers receive validated numeric evidence, never values scraped from an
# image. Every helper requires unique rows, expected shapes, and content hashes
# before returning a publication-facing value.
"""Publication evidence only; never change scientific source or saved results."""
import csv
import hashlib
import re

import numpy as np
from scipy.io import loadmat


def paper_baseline(root):
    # Return the unique paper Table 3 benchmark cells used in comparisons.
    with (root / 'results/comparisons/source_tables/CURATED_PAPER_BENCHMARKS.csv').open() as f:
        rows = [r for r in csv.DictReader(f) if r['paper_item'] == 'Table 3']
    values = {}
    for metric in ('Avg (t)', 'Std', 'Annualized Sharpe'):
        found = [r['paper_value'] for r in rows if r['metric'] == metric]
        if len(found) != 1:
            raise ValueError(f'Paper Table 3 benchmark is not unique: {metric}')
        values[metric] = found[0]
    match = re.fullmatch(r'([+-]?\d+(?:\.\d+)?)\s*\(([+-]?\d+(?:\.\d+)?)\)', values['Avg (t)'])
    if not match:
        raise ValueError('Invalid paper mean/t benchmark')
    return dict(mean=float(match[1]), t=float(match[2]),
                std=float(values['Std']), sharpe=float(values['Annualized Sharpe']))


def figure_bars(path):
    # Load the numerical bar companion and reject malformed figure payloads.
    """Read MATLAB bar data, not pixels or automatic axis labels."""
    values = {}

    def walk(node):
        if isinstance(node, dict):
            if node.get('type') == 'specgraph.barseries':
                props = node['properties']
                x, y = (np.atleast_1d(props[k]).reshape(-1) for k in ('XData', 'YData'))
                if len(x) != len(y):
                    raise ValueError(f'Inconsistent bar dimensions: {path}')
                for a, b in zip(x, y):
                    if not np.isfinite(a) or a != int(a) or int(a) in values:
                        raise ValueError(f'Invalid/duplicate bar position: {path}')
                    values[int(a)] = float(b)
            for key, value in node.items():
                if key != 'properties':
                    walk(value)
        elif isinstance(node, (list, np.ndarray)):
            for value in node:
                walk(value)

    walk(loadmat(path, simplify_cells=True))
    if set(values) != {1, 2, 3, 4}:
        raise ValueError(f'Expected CTREND/CMKT/CSMB/CMOM bars: {path}')
    return values


def factor_companion(experiments_root, experiment_id):
    # Read one experiment's authenticated Figure 1 numerical companion.
    """Separate joint-factor Figure 1 values from own-support baseline moments.

    A baseline standard deviation is not attributed to the joint-factor sample.
    Agreement of CTREND mean/Sharpe is reported, never imposed on future runs.
    """
    folder = experiments_root / experiment_id
    paths = [folder / f'Figures/b06Table3_UnivariatePortfolioSorts_figure0{i}.fig' for i in (1, 2)]
    avg, shp = [figure_bars(p) for p in paths]
    baseline = folder / 'CTREND/CTREND_Base.mat'
    mat = loadmat(baseline, simplify_cells=True, variable_names=['cResults', 'vDates'])
    returns = np.asarray(mat['cResults']['VW']['mPortRet'], dtype=float)
    if returns.shape != (6, np.size(mat['vDates'])):
        raise ValueError(f'Invalid baseline dimensions: {baseline}')
    z = returns[-1, np.isfinite(returns[-1])]
    mean = z.mean() * 100 if len(z) else float('nan')
    std = z.std(ddof=1) * 100 if len(z) > 1 else float('nan')
    sr = mean / std * np.sqrt(52) if std > 0 else float('nan')
    sha = lambda p: hashlib.sha256(p.read_bytes()).hexdigest()
    rows = []
    for pos, factor in enumerate(('CTREND', 'CMKT', 'CSMB', 'CMOM'), 1):
        rows.append(dict(experiment_id=experiment_id, factor=factor,
                         figure_mean_pct=avg[pos], figure_sharpe_annualized=shp[pos],
                         baseline_own_weeks=len(z) if pos == 1 else '',
                         baseline_own_mean_pct=mean if pos == 1 else '',
                         baseline_own_std_pct=std if pos == 1 else '',
                         baseline_own_sharpe_annualized=sr if pos == 1 else '',
                         ctrend_moments_match=int(np.isclose(mean, avg[1], rtol=1e-10, atol=1e-10) and
                                                 np.isclose(sr, shp[1], rtol=1e-10, atol=1e-10)) if pos == 1 else '',
                         figure_mean_sha256=sha(paths[0]), figure_sharpe_sha256=sha(paths[1]),
                         baseline_sha256=sha(baseline)))
    return rows
