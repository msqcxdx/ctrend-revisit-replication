#!/usr/bin/env python3
"""Collect six independently refitted E06 baseline cells on local common weeks.

This script does not rerun MATLAB or pool non-independent design combinations.
Each P/D cell has its own whole-path common calendar.  Cross-cell rows are
descriptive: their week sets need not be identical.
"""

from __future__ import annotations

import csv
from hashlib import sha256
import json
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "outputs/E06"
VARIANTS = {"control", "A", "B", "AB", "CD", "ABCD", "accepted_M1"}


def digest(path: Path) -> str:
    h = sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(2**20), b""):
            h.update(block)
    return h.hexdigest()


def read(path: Path) -> list[dict[str, str]]:
    with path.open(newline="", encoding="utf-8") as stream:
        return list(csv.DictReader(stream))


def write(path: Path, rows: list[dict[str, str]]) -> None:
    if not rows:
        raise ValueError("Refuse empty E06 grid output")
    with path.open("w", newline="", encoding="utf-8") as stream:
        writer = csv.DictWriter(stream, fieldnames=list(rows[0]))
        writer.writeheader()
        writer.writerows(rows)


def main() -> None:
    common: list[dict[str, str]] = []
    effects: list[dict[str, str]] = []
    sources = []
    for p in (0, 1):
        for d in (0, 1, 2):
            eid = f"P{p}_M2_D{d}"
            folder = OUT if eid == "P0_M2_D1" else OUT / "sensitivities" / eid
            receipt = folder / "HYBRID_RECEIPT.json"
            if not receipt.is_file():
                raise FileNotFoundError(f"E06 module refit incomplete: {eid}")
            summary = folder / "hybrid_baseline_summary.csv"
            paired = folder / "hybrid_paired_effects.csv"
            lines = [row for row in read(summary) if row["support"] == "whole_path_common"]
            if {row["variant"] for row in lines} != VARIANTS:
                raise ValueError(f"Incomplete E06 common-week variants: {eid}")
            week_counts = {int(row["weeks"]) for row in lines}
            if len(week_counts) != 1:
                raise ValueError(f"Variants use different common-week counts: {eid}")
            common.extend({"experiment_id": eid, **row} for row in lines)
            effects.extend({"experiment_id": eid, **row} for row in read(paired)
                           if row["support"] == "whole_path_common")
            sources.append({"experiment_id": eid,
                            "receipt_sha256": digest(receipt),
                            "summary_sha256": digest(summary),
                            "paired_sha256": digest(paired),
                            "whole_path_common_weeks": week_counts.pop()})
    if len(common) != 42 or len(effects) != 54:
        raise ValueError("E06 grid axes incomplete")
    a = OUT / "sensitivity_grid_common_week.csv"
    b = OUT / "sensitivity_grid_module_effects.csv"
    report = OUT / "E06_SENSITIVITY_GRID_CN.md"
    write(a, common)
    write(b, effects)
    report_lines = [
        "# E06 六个 P/D 单元的基准模块重估",
        "",
        "每格独立重估 control、A、B、AB、CD、ABCD，并以已验收 M1 作参照。",
        "以下数字在**各格自身**七路径共同可核算周上计算；不同 P/D 行的周集合",
        "不一定相同，不应直接当作配对因果差。均值和 LTW alpha 单位均为%/周，",
        "Sharpe 为年化。完整同周差及 HAC 区间见下方 CSV。",
        "",
        "| 实验格 | 路径 | 共同周 | 均值 | 年化 Sharpe | 外部 LTW alpha |",
        "|---|---|---:|---:|---:|---:|",
    ]
    for row in common:
        report_lines.append("| {experiment_id} | {variant} | {weeks} | {mean:.3f} | {sharpe:.3f} | {alpha:.3f} |".format(
            experiment_id=row["experiment_id"], variant=row["variant"],
            weeks=row["weeks"], mean=float(row["mean_pct"]),
            sharpe=float(row["annual_sharpe"]), alpha=float(row["ltw_alpha_pct"])))
    report_lines += [
        "",
        "A 撤销日度标签导致的 close 挖洞及其同步支持后果；B 换用 M1 指标定义；",
        "CD 合并实施 M1 逐指标支持、估计与已选组件组合。ABCD 仍保留 M2 的标签",
        "和组合会计，**不是完整 M1**。不能把这几条有交互的路径当作自然随机处理，",
        "也不能由某个点估计直接断言独立显著的经济因果效应。",
        "",
        "- [完整数值表](sensitivity_grid_common_week.csv)",
        "- [同周模块差异与 HAC 区间](sensitivity_grid_module_effects.csv)",
        "- [INNBCL 2020W16 的 D0 两格保存预测/权重/收益路径](sensitivity_innbcl_2020W16.csv)",
        "- 各格源结果与运行收据：`sensitivities/<experiment_id>/`；P0_M2_D1 为同目录基准文件。",
        "",
        "这里只重估每格的基准设计，**没有**重新运行 3,072 个研究设计。",
        "模型验证窗口的专门设计也不在该基准中，不能据此估计该修正的独立作用。",
    ]
    report.write_text("\n".join(report_lines)+"\n")
    receipt = {"scope": "six_P_D_baseline_cells_each_on_own_whole_path_common_weeks_not_full_design_grid",
               "sources": sources, "outputs": {a.name: digest(a), b.name: digest(b),
                                        report.name: digest(report)},
               "rows": {a.name: len(common), b.name: len(effects)}}
    (OUT / "SENSITIVITY_GRID_RECEIPT.json").write_text(json.dumps(receipt, indent=2) + "\n")
    print("E06_SENSITIVITY_GRID_OK cells=6 variants=7 effects=9")


if __name__ == "__main__":
    main()
