#!/usr/bin/env python3
"""Freeze Ardor on-chain BITSWIFT/ARDR matches in the held 2018W02 week.

The public node's matched coin-exchange records prove venue-level trades, not
USD execution prices, market-wide liquidity, or CTREND portfolio fills.
Normal use is offline; --fetch performs one-time acquisition without overwrite.
"""

from __future__ import annotations

import argparse
import csv
from datetime import datetime, timedelta, timezone
from hashlib import sha256
import json
from pathlib import Path
from urllib.parse import urlencode
from urllib.request import urlopen


ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "outputs/E05"
SOURCE = OUT / "source_evidence/ardor_bitswift_2018W02"
TRADE_FILE = SOURCE / "coin_exchange_trades_chain1_exchange4_1170_1210.json"
BLOCK_FILE = SOURCE / "matching_block_responses.json"
GENESIS = datetime(2018, 1, 1, tzinfo=timezone.utc)
START = datetime(2018, 1, 8, tzinfo=timezone.utc)
END_EXCLUSIVE = datetime(2018, 1, 15, tzinfo=timezone.utc)
API = "https://ardor.jelurida.com/nxt"
TRADE_QUERY = {"requestType": "getCoinExchangeTrades", "chain": "1", "exchange": "4",
               "firstIndex": "1170", "lastIndex": "1210"}


def digest(path: Path) -> str:
    return sha256(path.read_bytes()).hexdigest()


def api_call(query: dict[str, str]) -> dict:
    with urlopen(API + "?" + urlencode(query), timeout=30) as response:
        if response.status != 200:
            raise RuntimeError(f"Ardor HTTP {response.status}")
        data = json.loads(response.read())
    if "errorDescription" in data:
        raise RuntimeError(data["errorDescription"])
    return data


def event_time(trade: dict) -> datetime:
    return GENESIS + timedelta(seconds=int(trade["timestamp"]))


def fetch() -> None:
    if TRADE_FILE.exists() or BLOCK_FILE.exists():
        raise FileExistsError("Refusing to replace archived Ardor node responses")
    SOURCE.mkdir(parents=True, exist_ok=True)
    response = api_call(TRADE_QUERY)
    trades = response.get("trades", [])
    if not trades:
        raise ValueError("Empty Ardor coin-exchange API response")
    selected = [item for item in trades if START <= event_time(item) < END_EXCLUSIVE]
    blocks = {}
    for item in selected:
        block = item["block"]
        blocks[block] = api_call({"requestType": "getBlock", "block": block})
    TRADE_FILE.write_text(json.dumps(response, sort_keys=True, indent=2) + "\n", encoding="utf-8")
    BLOCK_FILE.write_text(json.dumps(blocks, sort_keys=True, indent=2) + "\n", encoding="utf-8")


def audit() -> None:
    response = json.loads(TRADE_FILE.read_text(encoding="utf-8"))
    blocks = json.loads(BLOCK_FILE.read_text(encoding="utf-8"))
    trades = response["trades"]
    if not trades or any(int(item["chain"]) != 1 or int(item["exchange"]) != 4 for item in trades):
        raise ValueError("Ardor pair identity mismatch")
    if not (event_time(trades[0]) >= END_EXCLUSIVE and event_time(trades[-1]) < START):
        raise ValueError("Archived paginated response does not bracket held week")
    selected = [item for item in trades if START <= event_time(item) < END_EXCLUSIVE]
    missing_cmc_day = [item for item in selected if event_time(item).date().isoformat() == "2018-01-14"]
    if len(selected) != 8 or len(missing_cmc_day) != 2:
        raise ValueError("Held-week BITSWIFT matches differ from archived result")
    rows = []
    for item in selected:
        block = blocks[item["block"]]
        if block.get("block") != item["block"] or int(block["timestamp"]) != int(item["timestamp"]):
            raise ValueError("Ardor block and matched trade timestamp differ")
        rows.append({
            "utc": event_time(item).isoformat(), "cmcid": "659", "cmc_week": "201802",
            "source": "Ardor mainnet public node", "chain": item["chain"],
            "exchange": item["exchange"], "pair": "ARDR/BITSWIFT coin exchange",
            "block_height": block["height"], "block_id": item["block"],
            "order_full_hash": item["orderFullHash"], "match_full_hash": item["matchFullHash"],
            "exchange_rate_as_reported": item["exchangeRate"],
            "quantity_QNT_as_reported": item["quantityQNT"],
            "usd_price": "", "scope": "matched_onchain_trade_not_usd_exit_price_or_marketwide_fill",
        })
    rows.sort(key=lambda item: item["utc"])
    path = OUT / "ardor_bitswift_2018W02_held_week_trades.csv"
    with path.open("w", newline="", encoding="utf-8") as handle:
        writer = csv.DictWriter(handle, fieldnames=list(rows[0]))
        writer.writeheader()
        writer.writerows(rows)
    receipt = {
        "scope": "Bitswift CMCID 659, 2018W02, Ardor matched coin-exchange trades only",
        "public_node_query": API + "?" + urlencode(TRADE_QUERY),
        "official_api_docs": "https://ardordocs.jelurida.com/Coin_Exchange",
        "official_chain_id_source": "https://ardordocs.jelurida.com/Ardor_Software_Change_Log",
        "official_genesis_source": "https://www.jelurida.com/ico",
        "raw_response_sha256": digest(TRADE_FILE), "block_response_sha256": digest(BLOCK_FILE),
        "returned_trade_rows": len(trades), "held_week_matches": len(rows),
        "matches_on_cmc_missing_day_2018_01_14": len(missing_cmc_day),
        "output": {path.name: digest(path), "rows": len(rows)},
    }
    (OUT / "ardor_bitswift_2018W02_receipt.json").write_text(
        json.dumps(receipt, indent=2) + "\n", encoding="utf-8")
    print(f"E05_ARDOR_BITSWIFT_HELD_WEEK_OK matches={len(rows)} missing_day_matches={len(missing_cmc_day)}")


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--fetch", action="store_true", help="One-time freeze of public node responses")
    args = parser.parse_args()
    if args.fetch:
        fetch()
    audit()
