#!/usr/bin/env python3
"""Audit local prerequisites for the prospective 2023–2025 external test.

The script is read-only outside followup_research/outputs/E12.  It cannot
mistake a proposed download command for observed post-2022 research data.
"""

from __future__ import annotations

import csv
from datetime import date
import hashlib
import json
from pathlib import Path
import shutil


ROOT = Path(__file__).resolve().parents[1]
REPO = ROOT.parent
OUT = ROOT / "outputs" / "E12"


def last_row_date(path: Path) -> date:
    last = None
    with path.open(newline="", encoding="utf-8") as handle:
        reader = csv.reader(handle)
        next(reader)
        for row in reader:
            if row:
                last = row[0]
    if last is None:
        raise ValueError(f"No rows in {path}")
    return date.fromisoformat(last)


def main() -> None:
    input_dir = REPO / "data" / "raw" / "common"
    required_cmc = ("open_cmc.csv", "high_cmc.csv", "low_cmc.csv",
                    "close_cmc.csv", "volume_cmc.csv", "market_cap_cmc.csv")
    endpoints = {name: last_row_date(input_dir / name) for name in required_cmc}
    target_start, target_end = date(2023, 1, 1), date(2025, 12, 31)
    rows = [{"input": name, "local_path": str(input_dir / name),
             "latest_observed_date": endpoint.isoformat(),
             "covers_new_period_start": int(endpoint >= target_start),
             "covers_new_period_end": int(endpoint >= target_end)}
            for name, endpoint in endpoints.items()]
    if len(set(endpoints.values())) != 1:
        raise ValueError(f"Existing frozen six-field panel ends at different dates: {endpoints}")
    OUT.mkdir(parents=True, exist_ok=True)
    with (OUT / "local_input_readiness.csv").open("w", newline="", encoding="utf-8") as handle:
        writer = csv.DictWriter(handle, fieldnames=list(rows[0]))
        writer.writeheader()
        writer.writerows(rows)
    home_free = shutil.disk_usage(ROOT).free
    data2_free = shutil.disk_usage("/data2").free
    pilot_root = OUT / "pilot_cmc_2023_2assets_3days"
    pilot_complete = pilot_root / "ACQUISITION_COMPLETE.json"
    pilot_text = "尚无通过完整导出阶段的网络获取试验。\n\n"
    if pilot_complete.is_file():
        pilot = json.loads(pilot_complete.read_text(encoding="utf-8"))
        if (pilot.get("installed_research_data") is not False
                or pilot.get("matlab_executed") is not False
                or pilot["rounds"][0]["new_asset_days"]["pure_1d"] != 6
                or pilot["rounds"][-1]["changed"] is not False):
            raise ValueError("Two-asset three-day pilot receipt is inconsistent")
        checksum = hashlib.sha256(pilot_complete.read_bytes()).hexdigest()
        pilot_text = (
            "隔离目录中的 BTC(CMCID 1) 与 ETH(CMCID 1027) 2023-01-01 至 2023-01-03 "
            "小试验已经完成：6 个资产日、一次初采加一次稳定复核、无合并冲突，"
            "并生成 CMC-only MATLAB 数据包。"
            f"`ACQUISITION_COMPLETE.json` SHA256 为 `{checksum}`。"
            "这只证明这些 ID/日期及当前网络路径可走通，**不**证明 2023–2025 全市场"
            "覆盖、独立供应商一致或任何新时期因子结果。试验数据没有安装到研究输入。\n\n"
        )
    report = (
        "# E12 新时期试验输入就绪性\n\n"
        f"审计时，已冻结的六个 CMC 日度量价字段均止于 **{next(iter(endpoints.values()))}**；"
        "2023–2025 年新时期在当前研究包中没有 CMC 原始价格输入。"
        "因此尚不能估计新时期的预测、因子定价或实施结果。\n\n"
        f"当前仓库分区可用 {home_free/2**30:.1f} GiB，/data2 可用 "
        f"{data2_free/2**30:.1f} GiB。现有 acquisition 代码支持另建隔离工作区和断点续采，"
        "但完整新时期、全资产、多频回退与反复覆盖审计的存储需求未估算；"
        "不应在接近满载的 /data2 上未经容量预算直接发起全量下载。\n\n"
        + pilot_text +
        "启动 E12 前还必须冻结：新时期 CMCID/名称映射、2023–2025 样本与交易可得性规则、"
        "所用外部风险因子覆盖日期、第二供应商的历史资产日价格及许可/身份对应、"
        "下载失败/冲突处理标准，以及预先定义的主要检验。第二供应商缺失时，"
        "只能先完成单来源新时期验证，不能标为‘独立数据源复核’。\n\n"
        "本文件是就绪性审计，不包含虚构的新时期实证结论。"
        "旧 18 组输入与结果未改动。\n"
    )
    (OUT / "E12_DATA_READINESS_CN.md").write_text(report, encoding="utf-8")
    print(f"E12_INPUT_AUDIT_OK existing_cmc_end={next(iter(endpoints.values()))} "
          "new_period_covered=0")


if __name__ == "__main__":
    main()
