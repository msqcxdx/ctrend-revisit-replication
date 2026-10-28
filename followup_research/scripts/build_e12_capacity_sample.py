#!/usr/bin/env python3
"""Freeze a small, stratified CMC ID sample for an E12 storage/throughput pilot.

This is an engineering capacity sample, not the new-period research universe.
The IDs and 2022-06-11 ranks come only from the already frozen market-cap input.
"""

from __future__ import annotations

import argparse
import csv
import hashlib
import json
import math
from pathlib import Path
import random


HERE = Path(__file__).resolve()
REPO = HERE.parents[2]
SOURCE = REPO / "data/raw/common/market_cap_cmc.csv"
SEED = 20261026


def digest(path: Path) -> str:
    result = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(2**20), b""):
            result.update(chunk)
    return result.hexdigest()


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--out", type=Path, required=True,
                        help="New CSV path on the isolated data disk")
    args = parser.parse_args()
    target = args.out.resolve()
    if target.exists():
        raise FileExistsError(f"Capacity-sample identity is already frozen: {target}")
    receipt_path = target.with_suffix(".identity.json")
    if receipt_path.exists():
        raise FileExistsError(f"Capacity-sample receipt exists: {receipt_path}")

    with SOURCE.open(newline="", encoding="utf-8") as handle:
        reader = csv.reader(handle)
        header = next(reader)
        if not header or any(not value.isdecimal() for value in header[1:]):
            raise ValueError("Unexpected CMC market-cap column identity")
        last = None
        for row in reader:
            if row:
                last = row
    if last is None or last[0] != "2022-06-11":
        raise ValueError("Frozen market-cap input endpoint changed")

    ranked = []
    for asset_id, raw_value in zip(header[1:], last[1:], strict=True):
        try:
            market_cap = float(raw_value)
        except ValueError:
            continue
        if math.isfinite(market_cap) and market_cap > 0:
            ranked.append((int(asset_id), market_cap))
    ranked.sort(key=lambda value: (-value[1], value[0]))
    if len(ranked) < 500:
        raise ValueError("Not enough finite assets for stratified sample")

    rng = random.Random(SEED)
    bins = (("rank_1_10", 0, 10, 10),
            ("rank_11_100", 10, 100, 10),
            ("rank_101_500", 100, 500, 10),
            ("rank_501_plus", 500, len(ranked), 10))
    rows = []
    for stratum, first, last_index, count in bins:
        positions = list(range(first, last_index))
        chosen = positions if len(positions) == count else rng.sample(positions, count)
        for position in chosen:
            asset_id, market_cap = ranked[position]
            rows.append({"id": asset_id, "stratum": stratum,
                         "cap_rank_20220611": position + 1,
                         "cap_usd_20220611": format(market_cap, ".17g")})
    rows.sort(key=lambda row: row["id"])
    if len(rows) != 40 or len({row["id"] for row in rows}) != 40:
        raise ValueError("Capacity sample is not 40 distinct CMC IDs")

    target.parent.mkdir(parents=True, exist_ok=True)
    with target.open("w", newline="", encoding="utf-8") as handle:
        writer = csv.DictWriter(handle, fieldnames=list(rows[0]))
        writer.writeheader()
        writer.writerows(rows)
    receipt = {
        "purpose": "E12 engineering storage/throughput pilot only",
        "not_research_universe": True,
        "selection_date": "2022-06-11", "seed": SEED,
        "asset_count": len(rows), "input_sha256": digest(SOURCE),
        "ids_csv_sha256": digest(target), "ranked_finite_asset_count": len(ranked),
        "strata": {name: count for name, _, _, count in bins},
    }
    receipt_path.write_text(json.dumps(receipt, indent=2) + "\n", encoding="utf-8")
    print(f"E12_CAPACITY_SAMPLE_READY path={target} ids=40 sha256={digest(target)}")


if __name__ == "__main__":
    main()
