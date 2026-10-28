#!/usr/bin/env python3
"""Join frozen held-gap rows to an independent quote audit without filling gaps."""

from __future__ import annotations

import argparse
import csv
from datetime import date, timedelta
from hashlib import sha256
import json
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "outputs/E05"
EXPECTED_SUMMARY = "cfc560621579ad009adebbb637039c5081a80577a55fd4d54426da9afc252d9e"
EXPECTED_DAILY = "4e8a754729a585fa2919354b9b8c3c7fe35b49fe9f175383b220e8d4bbfec5f8"
EXPECTED_RESPONSES = {
    "1037_33451.json.gz": "ec3a4f6d15afdfb228570a9c83f01b0b2b576394df259f73445b6ae77273361d",
    "1037_page.html.gz": "0c72f6253333fb476a4f02d94c24f68d33481eeb57e0b1c5daca80a14e1ef956",
    "1454_2728.json.gz": "25d5190848e9654d6b5241916c49c6e96436e28925ad209087745b109e9edb5c",
    "1454_page.html.gz": "95e28b6668d66d7f26daceb4a94649c03d9681ec97d81e2f9956ff989ef33d3c",
    "3949_33324.json.gz": "b3ef16ddc87cde5a6a1da91046d462b977ae55d5de1cf59414a24a5b9f39199c",
    "3949_page.html.gz": "b63d54158fad39f458574b9f326d4403a93ed6aa46540f47071c84b3a814ac99",
}


def digest(path: Path) -> str:
    h = sha256()
    with path.open("rb") as handle:
        for block in iter(lambda: handle.read(2**20), b""):
            h.update(block)
    return h.hexdigest()


def read_csv(path: Path) -> list[dict[str, str]]:
    with path.open(newline="", encoding="utf-8-sig") as handle:
        return list(csv.DictReader(handle))


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--audit-dir", type=Path, default=OUT / "source_evidence",
                        help="Directory with the frozen CoinLore gap summary and daily quotes")
    args = parser.parse_args()
    summary_path = args.audit_dir / "priority_coinlore_live_gap_comparison.csv"
    daily_path = args.audit_dir / "priority_coinlore_live_daily_quotes_inside_gaps.csv"
    held_path = OUT / "raw_internal_gap_held_week_details.csv"
    for path, expected in ((summary_path, EXPECTED_SUMMARY), (daily_path, EXPECTED_DAILY)):
        if digest(path) != expected:
            raise ValueError(f"External evidence hash differs from the frozen audit: {path}")
    for name, expected in EXPECTED_RESPONSES.items():
        if digest(args.audit_dir / name) != expected:
            raise ValueError(f"CoinLore response differs from the frozen audit: {name}")

    summary = {row["gap_id"]: row for row in read_csv(summary_path)}
    daily: dict[str, list[dict[str, str]]] = {}
    for row in read_csv(daily_path):
        daily.setdefault(row["gap_id"], []).append(row)
    output: list[dict[str, object]] = []
    held = read_csv(held_path)
    if len(held) != 6 or len({row["cmcid"] for row in held}) != 6:
        raise ValueError("Expected exactly six unique held raw-gap assets")
    for row in held:
        cmcid = row["cmcid"]
        candidates = [z for z in summary.values()
                      if z["cmc_id"] == cmcid
                      and z["gap_start"] <= row["week_last_date"]
                      and z["gap_end"] >= row["week_first_date"]]
        if len(candidates) > 1:
            raise ValueError(f"More than one external audit gap overlaps held week: {cmcid}")
        z = candidates[0] if candidates else None
        observations = daily.get(z["gap_id"], []) if z else []
        held_quotes = [x for x in observations
                       if row["week_first_date"] <= x["date"] <= row["week_last_date"]]
        if z and len(observations) != int(z["quote_days"]):
            raise ValueError(f"External daily/summary count mismatch: {cmcid}")
        output.append({
            "cmcid": cmcid,
            "year_week": row["year_week"],
            "week_first_date": row["week_first_date"],
            "week_last_date": row["week_last_date"],
            "cmc_gap_start": z["gap_start"] if z else (
                date.fromisoformat(row["last_pre_gap_quote"]) + timedelta(days=1)).isoformat(),
            "cmc_gap_end": z["gap_end"] if z else (
                date.fromisoformat(row["first_post_gap_quote"]) - timedelta(days=1)).isoformat(),
            "audit_status": "identity_matched_audit" if z else "not_in_frozen_external_audit",
            "external_gap_quote_days": z["quote_days"] if z else "",
            "external_gap_positive_volume_days": z["positive_volume_days"] if z else "",
            "external_held_week_quote_days": len(held_quotes) if z else "",
            "external_held_week_positive_volume_days":
                sum(float(x["coinlore_volume"]) > 0 for x in held_quotes) if z else "",
            "external_first_quote_in_gap": z["first_quote_in_gap"] if z else "",
            "external_history_url": z["page_url"] if z else "",
            "external_response_sha256": z["history_gzip_sha256"] if z else "",
            "interpretation": (
                "other_aggregator_quote_not_executable_price" if z and int(z["quote_days"]) > 0
                else "external_audit_no_coverage_not_no_trading" if z
                else "not_collected_not_a_zero_quote_or_no_trading_finding"),
        })
    target = OUT / "held_gap_external_quote_evidence.csv"
    with target.open("w", newline="", encoding="utf-8") as handle:
        writer = csv.DictWriter(handle, fieldnames=list(output[0]))
        writer.writeheader()
        writer.writerows(output)
    receipt = {
        "scope": "six_held_asset_week_intersections_not_market_level_tradability",
        "held_parent": {"path": held_path.relative_to(ROOT).as_posix(), "sha256": digest(held_path)},
        "external_parents": {
            summary_path.name: EXPECTED_SUMMARY, daily_path.name: EXPECTED_DAILY,
            **EXPECTED_RESPONSES},
        "rows": len(output),
        "matched_external_audit_rows": sum(x["audit_status"] == "identity_matched_audit" for x in output),
        "output": {target.name: digest(target)},
    }
    (OUT / "held_gap_external_quote_receipt.json").write_text(
        json.dumps(receipt, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    print(f"E05_HELD_GAP_EXTERNAL_QUOTES_OK rows={len(output)} matched={receipt['matched_external_audit_rows']}")


if __name__ == "__main__":
    main()
