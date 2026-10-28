#!/usr/bin/env python3
"""Archive contemporaneous project statements about INNBC versus INNBCL swaps.

This chronology constrains event attribution but does not certify an exact
INNBCL conversion day, ratio, venue price, or cause of the April CMC anomaly.
Normal use is offline; --fetch is a one-time acquisition and never overwrites.
"""

from __future__ import annotations

import argparse
import csv
from datetime import datetime
from hashlib import sha256
import json
from pathlib import Path
from urllib.request import Request, urlopen


ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "outputs/E08"
SOURCE = OUT / "source_evidence/innbcl_project_2020"
HTML = SOURCE / "bitcointalk_topic_5242368_page1.html"
URL = "https://bitcointalk.org/index.php?topic=5242368.0"
POSTS = (
    ("54369970", "2020-05-05 22:58:29", "INNBC completed; INNBCL still planned",
     "INNBC has been swapped to a very low supply",
     "INNBCL we plan a swap as well to reduce supply and upgrade smart contract"),
    ("54617317", "2020-06-14 09:37:41", "INNBCL reported completed only recently",
     "INNBCL swap has been completed only recently", ""),
)


def digest(path: Path) -> str:
    return sha256(path.read_bytes()).hexdigest()


def fetch() -> None:
    if HTML.exists():
        raise FileExistsError(f"Refusing to overwrite source snapshot: {HTML}")
    SOURCE.mkdir(parents=True, exist_ok=True)
    request = Request(URL, headers={"User-Agent": "Mozilla/5.0"})
    with urlopen(request, timeout=30) as response:
        if response.status != 200:
            raise RuntimeError(f"Project forum HTTP {response.status}")
        payload = response.read()
    if len(payload) < 50_000:
        raise ValueError("Unexpectedly short project forum page")
    HTML.write_bytes(payload)


def audit() -> None:
    page = HTML.read_text(encoding="utf-8", errors="replace")
    rows = []
    for post_id, posted, claim, first, second in POSTS:
        marker = f'id="subject_{post_id}"'
        start = page.find(marker)
        if start < 0 or page.find(marker, start + 1) >= 0:
            raise ValueError(f"Missing or duplicate post marker: {post_id}")
        following = page.find('id="subject_', start + len(marker))
        section = page[start:following if following >= 0 else None]
        forum_time = datetime.strptime(posted, "%Y-%m-%d %H:%M:%S").strftime("%B %d, %Y, %I:%M:%S %p")
        if forum_time not in section:
            raise ValueError(f"Project post timestamp mismatch: {post_id}")
        if "INNOVATIVE BIORESEARCH" not in page[max(0, start-3500):start]:
            raise ValueError(f"Project post author mismatch: {post_id}")
        if first not in section or (second and second not in section):
            raise ValueError(f"Project statement mismatch: {post_id}")
        rows.append({
            "post_id": post_id, "post_date_forum_display": posted,
            "author_role": "INNOVATIVE BIORESEARCH original poster",
            "statement_summary": claim,
            "post_url": f"https://bitcointalk.org/index.php?topic=5242368.msg{post_id}#msg{post_id}",
            "event_day_in_april_proven": "no",
            "exact_innbcl_ratio_proven": "no",
        })
    path = OUT / "innbcl_project_swap_chronology_2020.csv"
    with path.open("w", newline="", encoding="utf-8") as handle:
        writer = csv.DictWriter(handle, fieldnames=list(rows[0]))
        writer.writeheader()
        writer.writerows(rows)
    receipt = {
        "scope": "project_statements_not_same_day_trade_or_exact_event_date",
        "source_url": URL,
        "raw_html_sha256": digest(HTML),
        "post_ids": [row["post_id"] for row in rows],
        "output_csv_sha256": digest(path),
        "rows": len(rows),
    }
    (OUT / "innbcl_project_swap_chronology_receipt.json").write_text(
        json.dumps(receipt, indent=2) + "\n", encoding="utf-8")
    print(f"E08_INNBCL_PROJECT_TIMELINE_OK posts={len(rows)} april_swap_proven=0")


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--fetch", action="store_true", help="Freeze source forum page once")
    args = parser.parse_args()
    if args.fetch:
        fetch()
    audit()
