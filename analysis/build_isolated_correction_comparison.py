#!/usr/bin/env python3
# CTREND_REVISIT_FILE_PURPOSE: Render the source-error and M1-implementation corrections beside their immutable parent results.
"""Format only parent-bound, single-component corrections; never alter a run."""

import csv
from hashlib import sha256
import json
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
BASE = ROOT / "analysis/isolated_corrections"
TABLE7 = BASE / "table7_direction/table7_direction_corrected_42_cells.csv"
DELAY = BASE / "delay/delay_appendix_summary.csv"


def digest(path: Path) -> str:
    value = sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            value.update(block)
    return value.hexdigest()


def read(path: Path) -> list[dict]:
    with path.open(newline="", encoding="utf-8") as stream:
        return list(csv.DictReader(stream))


def cell(mean: str, tstat: str) -> str:
    return f"{float(mean):+.2f} ({float(tstat):+.2f})"


def main() -> None:
    t7 = read(TABLE7)
    delay = read(DELAY)
    expected = {f"P{p}_M{m}_D{d}" for p in range(2)
                for m in range(3) for d in range(3)}
    if len(t7) != 42 or len(delay) != 18 or \
            {row["experiment_id"] for row in delay} != expected or \
            {row["experiment_id"] for row in t7} != \
            {item for item in expected if "_M1_" in item}:
        raise ValueError("Correction inputs do not cover the declared parent runs")
    corrected_t7 = sum(abs(float(row["corrected_hac_t"])) >= 1.96 for row in t7)
    legacy_t7 = sum(abs(float(row["legacy_hac_t"])) >= 1.96 for row in t7)
    placement_changes = [row for row in delay if
                         row["legacy_appendix"] != row["corrected_appendix"]]
    text = [
        "# 源码与实现口径的单项比较",
        "",
        "本页区分原作者源码中的 `delay` 输出序号问题和本研究 M1 Table 7 实现中的"
        "切点方向问题。表格并列完整运行记录与基于相同保存输入、只替换指定计算步骤的"
        "定义一致数值。18 套运行的 `RUN_COMPLETE` 及输入、输出哈希不变；"
        "单项计算不是另一套完整流程结果。",
        "",
        "## 原作者源码中的 `delay` 输出序号",
        "",
        "未修改的 Dataverse 源码中，`b02CalculateIndicators.m` 将扩展市场回归的第 4 个"
        "输出命名为 `mR2lag`；同一原始包的 `Utils/characteristics.m` 明确定义"
        "第 4 个为残差偏度 `mISkew`、第 5 个才是 `mR2`。因此 `1 - R²_base/R²_lag` "
        "在原实现中实际混入了偏度。M0 为复现原实现、M2 为限定范围的前视消融，"
        "均保留此算式；M1 源码已读第 5 个输出。",
        "",
        "每组比较均先从保存的 b01 输入还原父运行参考的周度 `delay`，并核对保存的 "
        "H–L 周收益；定义一致口径仅将扩展回归第 5 个输出代入同一变量。"
        "组合排序、经济收益、样本时间及基准因子保持各自 M 方法原状。"
        "这不是 M0→M1 的单因素分解，也不影响 CTREND 的 28 个技术预测量。",
        "",
        "| 实验 | 第 4 输出参考 `delay` H–L 周均值% (t) | 第 5 输出 R² 口径% (t) | 两口径有限周 | 变化的共同周数 | 附录归类 第4→第5输出 |",
        "| --- | ---: | ---: | ---: | ---: | --- |",
    ]
    for row in sorted(delay, key=lambda x: x["experiment_id"]):
        old = cell(row["legacy_hl_mean_pct"], row["legacy_hl_t"])
        new = cell(row["corrected_hl_mean_pct"], row["corrected_hl_t"])
        weeks = (f"{row['legacy_finite_weeks']}/"
                 f"{row['corrected_finite_weeks']}")
        placement = (f"{row['legacy_appendix']} → "
                     f"{row['corrected_appendix']}")
        text.append(f"| {row['experiment_id']} | {old} | {new} | {weeks} | "
                    f"{row['changed_shared_weeks']} | {placement} |")
    text += [
        "",
        f"两口径之间有 {len(placement_changes)}/18 组的 B.5/B.8 归类发生变化。"
        "t 值是该单变量 H–L 周均值的普通 t 统计量；若某原行是 NA，仍按其"
        "有限支持比较，不把缺失填零。逐周收益、五组分位和因子调整收益在 "
        "[`delay/`](delay/)；父运行身份、源文件及派生文件哈希在同目录收据中。",
        "",
        "## 本研究 M1 的 Table 7 零成本切点方向",
        "",
        "原作者 `Utils/fEstEvalTangPort.m` 会在估计方向的预期收益为负时翻转权重。"
        "完整运行中的 M1 计算先把 `Σ⁻¹μ` 除以权重和；当该和为负时，即使之后按"
        "正的目标波动率缩放，也会把方向反过来。零成本因子组合没有权重和等于 1"
        " 的预算约束；定义一致口径沿 `Σ⁻¹μ` 方向，用正比例系数缩放至目标波动率。"
        "这一偏差属于本研究实现，不列为原论文的源码缺陷。",
        "",
        "| 实验 | 原因子集 → 新增因子 | 完整运行 alpha% (HAC t) | 定义一致口径% (HAC t) | 同一 OOS 周 |",
        "| --- | --- | ---: | ---: | ---: |",
    ]
    for row in sorted(t7, key=lambda x: (x["experiment_id"],
                                             x["null_factor_set"],
                                             x["added_factor"])):
        label = f"{row['null_factor_set']} → {row['added_factor']}"
        old = cell(row["legacy_alpha_pct"], row["legacy_hac_t"])
        new = cell(row["corrected_alpha_pct"], row["corrected_hac_t"])
        text.append(f"| {row['experiment_id']} | {label} | {old} | {new} | "
                    f"{row['common_oos_weeks']} |")
    text += [
        "",
        f"按 |HAC t| ≥ 1.96 粗略计数，42 个单元中完整运行口径为 {legacy_t7} 个、"
        f"定义一致口径为 {corrected_t7} 个；不能只凭这一计数判断经济显著性。"
        "前一口径由保存的 Table 7 MATLAB 诊断和因子序列重建核对；后一口径"
        "使用相同窗口和正向缩放。完整精度、方向翻转周数和父运行哈希见"
        "[`table7_direction/`](table7_direction/)。",
        "",
        "十九方主报告及各实验的出版表使用本页定义一致的 M1 Table 7 与 delay 数值；"
        "M0/M2 的 delay 保留第 4 输出公式，以维持消融边界。"
        "这些单项计算不是 CTREND 主因子重新训练得到的收益；"
        "其它表图仍按其完整运行记录阅读。",
        "",
    ]
    output = BASE / "CORRECTION_COMPARISON_CN.md"
    output.write_text("\n".join(text), encoding="utf-8")
    receipt = dict(inputs={str(DELAY.relative_to(BASE)): digest(DELAY),
                           str(TABLE7.relative_to(BASE)): digest(TABLE7)},
                   script_sha256=digest(Path(__file__)),
                   comparison_sha256=digest(output))
    (BASE / "COMPARISON_RECEIPT.json").write_text(
        json.dumps(receipt, indent=2) + "\n", encoding="utf-8")
    print(f"ISOLATED_CORRECTION_COMPARISON_OK delay=18 table7=42 "
          f"delay_placement_changes={len(placement_changes)}")


if __name__ == "__main__":
    main()
