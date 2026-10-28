#!/usr/bin/env python3
"""Verify that the coauthor's published LTW workbook equals the frozen input.

The online request is opt-in. Offline mode checks the saved distribution
receipt against the unchanged local workbook, without claiming any disclosed
constituent weights or transaction endpoints.
"""

from __future__ import annotations

import argparse
from datetime import datetime, timezone
from hashlib import sha256
import json
from pathlib import Path
import subprocess


ROOT = Path(__file__).resolve().parents[2]
WORKBOOK = ROOT / "data/raw/common/LTW_3factor.xlsx"
RECEIPT = ROOT / "followup_research/outputs/E01/coauthor_workbook_distribution_receipt.json"
PUBLISHER_PAGE = "https://xiwuacademic.com/data-and-code/"
DOWNLOAD_URL = "https://www.dropbox.com/s/ziyh9pjooroxali/LTW_3factor.xlsx?dl=1"


def digest(data: bytes) -> str:
    return sha256(data).hexdigest()


def audit(fetch: bool) -> None:
    local = WORKBOOK.read_bytes()
    local_sha = digest(local)
    if fetch:
        if RECEIPT.exists():
            raise FileExistsError(f"Refusing to overwrite source receipt: {RECEIPT}")
        external = subprocess.run(
            ["curl", "-LfsS", "--retry", "3", "--max-time", "40", DOWNLOAD_URL],
            check=True, capture_output=True).stdout
        if not external.startswith(b"PK\x03\x04") or external != local:
            raise ValueError("Coauthor-published workbook differs from frozen input")
        payload = {
            "publisher": "Xi (Sissi) Wu, paper coauthor",
            "publisher_page": PUBLISHER_PAGE,
            "published_data_link": DOWNLOAD_URL,
            "checked_utc": datetime.now(timezone.utc).isoformat(),
            "local_input": str(WORKBOOK.relative_to(ROOT)),
            "local_input_sha256": local_sha,
            "downloaded_workbook_sha256": digest(external),
            "downloaded_size_bytes": len(external),
            "byte_identical": True,
            "scope": "published_workbook_identity_only_not_factor_constituents_or_endpoints",
        }
        RECEIPT.write_text(json.dumps(payload, indent=2) + "\n")
    saved = json.loads(RECEIPT.read_text())
    if saved["local_input_sha256"] != local_sha or \
            saved["downloaded_workbook_sha256"] != local_sha or \
            saved["downloaded_size_bytes"] != len(local) or \
            saved["publisher_page"] != PUBLISHER_PAGE or \
            saved["published_data_link"] != DOWNLOAD_URL or \
            saved["byte_identical"] is not True:
        raise ValueError("Coauthor distribution receipt does not match frozen workbook")
    print(f"E01_COAUTHOR_DISTRIBUTION_OK sha256={local_sha}")


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--fetch", action="store_true", help="Verify online once, then freeze a receipt")
    args = parser.parse_args()
    audit(args.fetch)
