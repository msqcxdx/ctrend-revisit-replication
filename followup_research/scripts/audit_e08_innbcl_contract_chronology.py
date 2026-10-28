#!/usr/bin/env python3
"""Freeze and independently recheck the two INNBCL Ethereum deployments.

Blockscout exposes the on-chain creation transaction for each verified token
contract. This dates the *identified* old/new contract pair; it does not
establish exchange execution prices or rule out every other April event.
Normal operation is offline. --fetch acquires immutable raw responses once.
"""

from __future__ import annotations

import argparse
import csv
from datetime import datetime, timezone
from hashlib import sha256
import json
from pathlib import Path
import subprocess


ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "outputs/E08"
SOURCE = OUT / "source_evidence/innbcl_contract_chronology"
BASE = "https://eth.blockscout.com/api/v2"
CONTRACTS = {
    "old": "0x8cc3e2bdc17682c622eb789eda23fbd6988c84da",
    "new": "0x0Cc9FCCFF81252F4bd8C5c6b359B14ae2Ed851cf",
}
EXPECTED_TX = {
    "old": "0x499b75c0aef25598fc305003fe0456147438af90f401c31a95ffdbdc2a2cc754",
    "new": "0xd1459e095c9b41f0b1e9353534161931cd60c0f58227c8632bc7c80a9deb42dd",
}


def digest(path: Path) -> str:
    return sha256(path.read_bytes()).hexdigest()


def get_json(url: str) -> bytes:
    # This host's proxy returns HTTP 500 to urllib but serves the same public
    # endpoint to curl. Keep acquisition explicit; offline audit uses snapshots.
    payload = subprocess.run(
        ["curl", "-LfsS", "--retry", "3", "--max-time", "40", url],
        check=True, capture_output=True).stdout
    json.loads(payload)
    return payload


def fetch() -> None:
    if SOURCE.exists() and any(SOURCE.iterdir()):
        raise FileExistsError(f"Refusing to overwrite source snapshot: {SOURCE}")
    SOURCE.mkdir(parents=True, exist_ok=True)
    for label, address in CONTRACTS.items():
        address_payload = get_json(f"{BASE}/addresses/{address}")
        address_data = json.loads(address_payload)
        tx = address_data["creation_transaction_hash"]
        if tx.lower() != EXPECTED_TX[label].lower():
            raise ValueError(f"Unexpected {label} creation transaction: {tx}")
        tx_payload = get_json(f"{BASE}/transactions/{tx}")
        (SOURCE / f"{label}_address.json").write_bytes(address_payload)
        (SOURCE / f"{label}_creation_tx.json").write_bytes(tx_payload)


def audit() -> None:
    rows = []
    source_hashes = {}
    for label, address in CONTRACTS.items():
        address_path = SOURCE / f"{label}_address.json"
        tx_path = SOURCE / f"{label}_creation_tx.json"
        info = json.loads(address_path.read_text())
        tx = json.loads(tx_path.read_text())
        txhash = EXPECTED_TX[label]
        if info["hash"].lower() != address.lower() or \
                info["creation_transaction_hash"].lower() != txhash.lower() or \
                tx["hash"].lower() != txhash.lower() or \
                tx["created_contract"]["hash"].lower() != address.lower() or \
                info["token"]["symbol"] != "INNBCL":
            raise ValueError(f"Contract/creation identity mismatch: {label}")
        timestamp = datetime.fromisoformat(tx["timestamp"].replace("Z", "+00:00"))
        if timestamp.tzinfo is None or timestamp.utcoffset() != timezone.utc.utcoffset(timestamp):
            raise ValueError(f"Creation timestamp is not UTC: {label}")
        rows.append({
            "contract_role": label,
            "cmcid": "3787",
            "symbol": "INNBCL",
            "contract_address": address,
            "token_decimals": info["token"]["decimals"],
            "creation_tx_hash": txhash,
            "created_utc": timestamp.isoformat(),
            "transaction_url": f"https://eth.blockscout.com/tx/{txhash}",
            "api_url": f"{BASE}/transactions/{txhash}",
            "before_2020_04_16": str(timestamp.date().isoformat() <= "2020-04-16").lower(),
        })
        source_hashes[address_path.name] = digest(address_path)
        source_hashes[tx_path.name] = digest(tx_path)
    if rows[0]["before_2020_04_16"] != "true" or \
            rows[1]["before_2020_04_16"] != "false" or \
            rows[1]["created_utc"][:10] != "2020-05-18":
        raise ValueError("INNBCL chronology no longer matches frozen conclusion")
    path = OUT / "innbcl_contract_creation_chronology.csv"
    with path.open("w", newline="", encoding="utf-8") as handle:
        writer = csv.DictWriter(handle, fieldnames=list(rows[0]))
        writer.writeheader()
        writer.writerows(rows)
    receipt = {
        "scope": "identified_old_new_contract_creation_only_not_venue_trade_or_april_price",
        "source_api_base": BASE,
        "source_hashes": source_hashes,
        "output_csv_sha256": digest(path),
        "rows": len(rows),
        "conclusion": "identified_new_INNBCL_contract_created_after_2020W16",
    }
    (OUT / "innbcl_contract_creation_receipt.json").write_text(
        json.dumps(receipt, indent=2) + "\n", encoding="utf-8")
    print("E08_INNBCL_CONTRACT_CHRONOLOGY_OK old=2019-02-05 new=2020-05-18")


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--fetch", action="store_true", help="Freeze raw source responses once")
    args = parser.parse_args()
    if args.fetch:
        fetch()
    audit()
