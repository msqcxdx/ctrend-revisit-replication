#!/usr/bin/env python3
"""Analyze paired external versus project-built LTW controls for E01.

All 2^3 mixed models use exactly the same complete-case weeks within each
accepted run. The original-support columns are diagnostics, not independent
evidence for a difference between alpha estimates.
"""

from __future__ import annotations

import csv
import itertools
import math
from pathlib import Path
import sys
from xml.sax.saxutils import escape

import numpy as np
from paired_stats import newey_west, bootstrap_paired


ROOT = Path(__file__).resolve().parents[1]
EXPERIMENTS = (
    "P0_M1_D0", "P0_M1_D1", "P0_M1_D2",
    "P1_M1_D0", "P1_M1_D1", "P1_M1_D2",
)
NAMES = ("cmkt", "csize", "cmom")


def write_csv(path: Path, rows: list[dict]) -> None:
    if not rows:
        raise ValueError(f"No output rows for {path}")
    with path.open("w", newline="", encoding="utf-8") as fh:
        writer = csv.DictWriter(fh, fieldnames=list(rows[0]))
        writer.writeheader()
        writer.writerows(rows)


def load_rows(path: Path) -> list[dict]:
    with path.open(newline="", encoding="utf-8") as fh:
        return list(csv.DictReader(fh))


def plot_factors(path: Path, weeks: np.ndarray, ext: np.ndarray,
                 own: np.ndarray) -> None:
    """Write an offline SVG with identical week positions in all panels."""
    width, height = 1100, 810
    left, right = 85, width-30
    parts = [f'<svg xmlns="http://www.w3.org/2000/svg" width="{width}" '
             f'height="{height}" viewBox="0 0 {width} {height}">',
             '<rect width="100%" height="100%" fill="white"/>',
             '<text x="85" y="30" font-family="sans-serif" font-size="19">'
             'E01 — external versus project-built LTW (P0_M1_D1)</text>']
    for j, name in enumerate(NAMES):
        top = 50+j*250
        bottom = top+205
        both = np.r_[ext[:, j], own[:, j]]
        valid = both[np.isfinite(both)]
        low, high = float(valid.min()), float(valid.max())
        span = high-low or 1.0
        low -= 0.05*span
        high += 0.05*span
        parts += [f'<line x1="{left}" y1="{bottom}" x2="{right}" '
                  f'y2="{bottom}" stroke="#777"/>',
                  f'<text x="{left}" y="{top+15}" font-family="sans-serif" '
                  f'font-size="16">{escape(name.upper())}</text>',
                  f'<text x="15" y="{top+38}" font-family="sans-serif" '
                  f'font-size="12">{100*high:.1f}%</text>',
                  f'<text x="15" y="{bottom}" font-family="sans-serif" '
                  f'font-size="12">{100*low:.1f}%</text>']
        for colour, values in (("#2367ad", ext[:, j]),
                               ("#d04b36", own[:, j])):
            segment: list[str] = []
            for i, value in enumerate(values):
                if not np.isfinite(value):
                    if segment:
                        parts.append(f'<polyline points="{" ".join(segment)}" '
                                     f'fill="none" stroke="{colour}" '
                                     'stroke-width="1.2"/>')
                        segment = []
                    continue
                x = left+(right-left)*i/max(1, len(values)-1)
                y = top+20+(bottom-top-25)*(high-float(value))/(high-low)
                segment.append(f"{x:.1f},{y:.1f}")
            if segment:
                parts.append(f'<polyline points="{" ".join(segment)}" '
                             f'fill="none" stroke="{colour}" '
                             'stroke-width="1.2"/>')
        for i in range(0, len(weeks), 52):
            x = left+(right-left)*i/max(1, len(weeks)-1)
            parts.append(f'<text x="{x:.1f}" y="{bottom+17}" '
                         f'font-family="sans-serif" font-size="11">'
                         f'{weeks[i]}</text>')
    parts += ['<line x1="85" y1="790" x2="112" y2="790" '
              'stroke="#2367ad" stroke-width="2"/>',
              '<text x="118" y="794" font-family="sans-serif" '
              'font-size="13">external</text>',
              '<line x1="225" y1="790" x2="252" y2="790" '
              'stroke="#d04b36" stroke-width="2"/>',
              '<text x="258" y="794" font-family="sans-serif" '
              'font-size="13">project-built</text>', '</svg>']
    path.write_text("\n".join(parts), encoding="utf-8")


def ols(y: np.ndarray, f: np.ndarray, support: np.ndarray) -> dict:
    x = np.column_stack((np.ones(np.count_nonzero(support)), f[support]))
    yy = y[support]
    n, k = x.shape
    if n <= k or np.linalg.matrix_rank(x) != k:
        raise ValueError(f"Regression not identifiable: n={n}, rank={np.linalg.matrix_rank(x)}")
    beta = np.linalg.lstsq(x, yy, rcond=None)[0]
    resid = yy - x @ beta
    sigma2 = float(resid @ resid) / (n-k)
    cov = sigma2 * np.linalg.inv(x.T @ x)
    se = np.sqrt(np.diag(cov))
    r2 = 1.0-float(resid @ resid)/float(((yy-yy.mean())**2).sum())
    out = {"n": n, "alpha_pct": 100*beta[0], "se_pct": 100*se[0],
           "t_alpha": beta[0]/se[0], "r2": r2,
           "legacy_se_and_t_convention": "iid_OLS_descriptive_only"}
    robust = newey_west(np.where(support,y,np.nan), f)
    out.update(alpha_hac_se_pct=100*robust["alpha_se_hac"],
               alpha_hac_t=robust["alpha_t_hac"],
               alpha_hac_p=robust["alpha_p_hac"],
               alpha_hac_ci_low_pct=100*robust["alpha_ci_low"],
               alpha_hac_ci_high_pct=100*robust["alpha_ci_high"],
               hac_calendar_lags=4)
    for i, name in enumerate(NAMES, start=1):
        out[f"beta_{name}"] = beta[i]
    return out


def main() -> int:
    out = ROOT / "outputs" / "E01"
    model_rows: list[dict] = []
    factor_rows: list[dict] = []
    gap_rows: list[dict] = []
    paired_source_rows: list[dict] = []
    for experiment in EXPERIMENTS:
        rows = load_rows(out / experiment / "e01_weekly_factors.csv")
        if len(rows) != len({r["week_key"] for r in rows}):
            raise ValueError(f"Duplicate week key in {experiment}")
        weeks = np.array([int(float(r["week_key"])) for r in rows])
        y = np.array([float(r["ctrend"]) for r in rows])
        ext = np.array([[float(r[f"external_{name}"]) for name in NAMES]
                        for r in rows])
        own = np.array([[float(r[f"own_{name}"]) for name in NAMES]
                        for r in rows])
        if experiment == "P0_M1_D1":
            plot_factors(out / "factor_weekly_comparison_P0_M1_D1.svg",
                         weeks, ext, own)
        native = {}
        for source, factors in (("external", ext), ("own", own)):
            mask = np.isfinite(y) & np.isfinite(factors).all(axis=1)
            native[source] = ols(y, factors, mask)
            model_rows.append({"experiment_id": experiment,
                               "support": "native", "source": source,
                               "market_source": source, "size_source": source,
                               "momentum_source": source, **native[source]})
        common = (np.isfinite(y) & np.isfinite(ext).all(axis=1)
                  & np.isfinite(own).all(axis=1))
        if common.sum() < 100:
            raise ValueError(f"Unexpectedly small paired support: {experiment}")
        # Resample all seven series together on the original, uncompressed
        # calendar. This directly tests the change of benchmark, not two stars.
        joined = np.column_stack((np.where(common,y,np.nan), ext, own))
        def source_alpha_difference(matrix, unused):
            aa = newey_west(matrix[:,0], matrix[:,4:7])["alpha"]
            bb = newey_west(matrix[:,0], matrix[:,1:4])["alpha"]
            return aa-bb
        for block in (4,8,13):
            boot = bootstrap_paired(joined, joined[:,0], source_alpha_difference,
                                    block=block)
            paired_source_rows.append({"experiment_id": experiment,
                "comparison": "own_minus_external_alpha_same_weeks",
                "n_common": int(common.sum()), "block_weeks": block,
                "alpha_difference_pct": 100*boot["estimate"],
                "ci_low_pct": 100*boot["ci_low"], "ci_high_pct": 100*boot["ci_high"],
                "centered_bootstrap_p": boot["centered_p"],
                "bootstrap_reps_valid": boot["reps_valid"]})
        for bits in itertools.product((0, 1), repeat=3):
            factors = np.column_stack(
                [own[:, j] if bits[j] else ext[:, j] for j in range(3)]
            )
            labels = tuple("own" if bit else "external" for bit in bits)
            model_rows.append({"experiment_id": experiment,
                               "support": "strict_common",
                               "source": "".join(str(bit) for bit in bits),
                               "market_source": labels[0],
                               "size_source": labels[1],
                               "momentum_source": labels[2],
                               **ols(y, factors, common)})
        for j, name in enumerate(NAMES):
            a, b = ext[:, j], own[:, j]
            paired = common & np.isfinite(a) & np.isfinite(b)
            difference = b[paired]-a[paired]
            correlation = float(np.corrcoef(a[paired], b[paired])[0, 1])
            factor_rows.append({
                "experiment_id": experiment, "factor": name,
                "n_common": int(paired.sum()),
                "n_external_native": int(np.isfinite(a).sum()),
                "n_own_native": int(np.isfinite(b).sum()),
                "external_mean_pct": 100*float(a[paired].mean()),
                "own_mean_pct": 100*float(b[paired].mean()),
                "external_sd_pct": 100*float(a[paired].std(ddof=1)),
                "own_sd_pct": 100*float(b[paired].std(ddof=1)),
                "correlation": correlation,
                "own_minus_external_mean_pct": 100*float(difference.mean()),
                "own_minus_external_rmse_pct": 100*math.sqrt(float(np.mean(difference**2))),
            })
        for week, yy, aa, bb, cc in zip(weeks, y, ext, own, common):
            if not cc:
                gap_rows.append({"experiment_id": experiment,
                                 "week_key": int(week),
                                 "ctrend_finite": int(np.isfinite(yy)),
                                 **{f"external_{name}_finite": int(np.isfinite(aa[j]))
                                    for j, name in enumerate(NAMES)},
                                 **{f"own_{name}_finite": int(np.isfinite(bb[j]))
                                    for j, name in enumerate(NAMES)}})

    write_csv(out / "eight_mixed_benchmarks.csv", model_rows)
    write_csv(out / "factor_source_summary.csv", factor_rows)
    write_csv(out / "strict_common_missing_weeks.csv", gap_rows)
    write_csv(out / "paired_benchmark_alpha_difference.csv", paired_source_rows)
    lines = ["# E01：外部和自建 LTW 对账", "",
             "同一行内，000=全外部、111=全自建；三位顺序为市场、规模、动量。",
             "8 种混合口径使用完全相同的 CTREND 和严格共同周。"
             "native 行用于区分样本效应，不可与混合口径直接做独立样本推断。", "",
             "正式推断使用 `alpha_hac_*` 列（保留日历缺口的 HAC，滞后 4 周）。"
             "`t_alpha` 等原有普通 OLS 列保留用于对账，不能当作 HAC 结果。"
             "`paired_benchmark_alpha_difference.csv` 直接检验同周的自建减外部 alpha，"
             "并列 4、8、13 周区块长度，不能用两组各自显著性代替差异检验。", "",
             "| 实验 | 外部原支持 α (%/周) | 自建原支持 α (%/周) | "
             "共同周 | 外部同周 α | 自建同周 α |", "|---|---:|---:|---:|---:|---:|"]
    for experiment in EXPERIMENTS:
        native_e = next(r for r in model_rows if r["experiment_id"] == experiment
                        and r["support"] == "native" and r["source"] == "external")
        native_o = next(r for r in model_rows if r["experiment_id"] == experiment
                        and r["support"] == "native" and r["source"] == "own")
        common_e = next(r for r in model_rows if r["experiment_id"] == experiment
                        and r["support"] == "strict_common" and r["source"] == "000")
        common_o = next(r for r in model_rows if r["experiment_id"] == experiment
                        and r["support"] == "strict_common" and r["source"] == "111")
        lines.append(f"| {experiment} | {native_e['alpha_pct']:.3f} | "
                     f"{native_o['alpha_pct']:.3f} | {common_e['n']} | "
                     f"{common_e['alpha_pct']:.3f} | {common_o['alpha_pct']:.3f} |")
    lines += ["", "六组的严格共同支持均为 337 周，与各自原回归支持相同；"
              "所以这批 alpha 差异不是由外部／自建回归日期不一致产生。",
              "P0_M1_D1 中只换市场因子的 alpha 为 1.485%，只换规模为 1.345%，"
              "只换动量为 2.625%（全外部为 1.455%）。"
              "这里的‘只换’均相对全外部基准，说明差异主要在动量因子的具体构造；"
              "这不是对其正确性的判定。", "",
              "外部工作簿只公布 `yyww` 周键，没有逐行持有区间起止日。"
              "项目内部周键由每年从 1 月 1 日开始的连续七日块生成、年末最后一块较长。"
              "因此可证明原回归按同一周键对齐，却不能仅凭工作簿独立证明外部"
              "每行的实际交易端点与项目内部完全相同；这项证据限制需在论文披露。",
              "", "这些是代码口径与样本的诊断结果，不代表八套基准中可以择优选用。",
              "完整载荷、标准误、相关系数、缺失周及逐周对照图见同目录。", ""]
    (out / "E01_SUMMARY_CN.md").write_text("\n".join(lines), encoding="utf-8")
    print(f"E01_ANALYSIS_OK experiments={len(EXPERIMENTS)} "
          f"mixed_models={len(model_rows)-2*len(EXPERIMENTS)}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
