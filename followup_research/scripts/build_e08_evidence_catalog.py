#!/usr/bin/env python3
"""Convert the frozen D2 evidence appendix into a checked asset-level catalog.

This is a provenance index, not a new event decision or price adjustment.  The
source appendix states explicitly where a notice is insufficient to infer a
unique CMC OHLC or tradable-return correction.
"""

from __future__ import annotations

import csv
from pathlib import Path
import re


ROOT = Path(__file__).resolve().parents[1]
REPO = ROOT.parent
SOURCE = REPO / "docs" / "D2_ASSET_EVENT_EVIDENCE.md"
OUT = ROOT / "outputs" / "E08" / "event_evidence_catalog.csv"


def main() -> None:
    content = SOURCE.read_text(encoding="utf-8")
    summary = content.split("## Individual evidence and limits", 1)[0]
    rows = []
    for line in summary.splitlines():
        if not re.match(r"^\|\s*\d+\s*\|", line):
            continue
        cells = [cell.strip() for cell in line.strip("|").split("|")]
        if len(cells) != 6:
            raise ValueError(f"Unexpected evidence table row: {line}")
        asset, ticker, inclusion, cmc_keys, event_window, assessment = cells
        rows.append({
            "cmcid": int(asset), "frozen_d2_ticker": ticker,
            "d1_d2_decision": inclusion,
            "cmc_extreme_keys_not_necessarily_event_dates": cmc_keys,
            "external_event_date_or_window": event_window,
            "evidence_assessment": assessment,
        })
    section = content.split("## Individual evidence and limits", 1)[1]
    blocks = re.split(r"(?=^### \d+\. )", section, flags=re.MULTILINE)
    details = {}
    for block in blocks:
        match = re.match(r"### \d+\. .*?CMCID\s+(\d+)", block)
        if not match:
            continue
        asset = int(match.group(1))
        if asset in details:
            raise ValueError(f"Duplicate asset section: {asset}")
        links = re.findall(r"\[([^]]+)\]\((https?://[^)]+)\)", block)
        details[asset] = {
            "source_titles": " | ".join(title for title, _ in links),
            "source_urls": " | ".join(url for _, url in links),
            "source_count": len(links),
            "evidence_section": re.sub(r"\s+", " ", block).strip(),
        }
    expected = {int(r["asset_id"]) for r in csv.DictReader(
        (REPO / "config" / "exclusions" / "D2.csv").open(newline="", encoding="utf-8"))}
    found = {r["cmcid"] for r in rows}
    if len(rows) != 28 or found != expected or found != set(details):
        raise ValueError(f"Evidence catalog and frozen D2 disagree: table={found}, D2={expected}, details={set(details)}")
    for row in rows:
        row.update(details[row["cmcid"]])
        if row["source_count"] == 0:
            raise ValueError(f"Missing link for CMCID {row['cmcid']}")
        row["interpretation_scope"] = "retrospective_event_exposure_not_unique_price_repair"
    OUT.parent.mkdir(parents=True, exist_ok=True)
    with OUT.open("w", newline="", encoding="utf-8") as handle:
        writer = csv.DictWriter(handle, fieldnames=list(rows[0]))
        writer.writeheader()
        writer.writerows(rows)
    print(f"E08_EVIDENCE_CATALOG_OK assets={len(rows)} source_links={sum(r['source_count'] for r in rows)}")


if __name__ == "__main__":
    main()
