#!/usr/bin/env python3
"""Freeze and verify Binance's COCOSUSDT daily candles around the 2021 swap.

This is exchange-level evidence for one venue, not a repair of CMC prices or
proof that the CTREND portfolio could trade at the archived daily close.
Normal use is offline; --fetch is the one-time evidence acquisition step.
"""

from __future__ import annotations

import argparse
import csv
from datetime import date, datetime, timedelta, timezone
import gzip
from hashlib import sha256
import io
import json
from pathlib import Path
from urllib.error import HTTPError
from urllib.request import urlopen
from zipfile import ZipFile


ROOT = Path(__file__).resolve().parents[1]
REPO = ROOT.parent
OUT = ROOT / "outputs/E08"
SOURCE = OUT / "source_evidence/binance_cocos_20210114_20210124"
STATUS = SOURCE / "HTTP_STATUS.json"
START = date(2021, 1, 14)
END = date(2021, 1, 24)
URL_PREFIX = "https://data.binance.vision/data/spot/daily/klines/COCOSUSDT/1d/"
PARENT = REPO / "results/diagnostics/p0_selected_week_asset_audit/P0_KEY_WEEK_ASSET_METHOD_ROWS.csv.gz"


def digest_bytes(data: bytes) -> str:
    return sha256(data).hexdigest()


def digest_file(path: Path) -> str:
    h = sha256()
    with path.open("rb") as handle:
        for block in iter(lambda: handle.read(2**20), b""):
            h.update(block)
    return h.hexdigest()


def dates():
    day = START
    while day <= END:
        yield day
        day += timedelta(days=1)


def file_name(day: date) -> str:
    return f"COCOSUSDT-1d-{day.isoformat()}.zip"


def fetch() -> None:
    if STATUS.exists():
        raise FileExistsError(f"Refusing to replace frozen evidence: {STATUS}")
    SOURCE.mkdir(parents=True, exist_ok=True)
    responses = []
    for day in dates():
        name = file_name(day)
        url = URL_PREFIX + name
        try:
            with urlopen(url, timeout=30) as response:
                code = response.status
                payload = response.read()
        except HTTPError as exc:
            if exc.code != 404:
                raise
            code, payload = 404, b""
        if code == 200:
            path = SOURCE / name
            if path.exists():
                raise FileExistsError(path)
            path.write_bytes(payload)
        elif code != 404:
            raise RuntimeError(f"Unexpected official archive HTTP {code}: {url}")
        responses.append({"date": day.isoformat(), "url": url, "http_status": code,
                          "file": name if code == 200 else None,
                          "sha256": digest_bytes(payload) if code == 200 else None})
    STATUS.write_text(json.dumps({
        "fetched_utc": datetime.now(timezone.utc).isoformat(),
        "source": "Binance official public spot daily kline archive",
        "scope": "COCOSUSDT one venue only; HTTP 404 means archive file unavailable, not no market trade",
        "responses": responses,
    }, indent=2) + "\n", encoding="utf-8")


def parse_kline(payload: bytes, day: date) -> dict[str, object]:
    with ZipFile(io.BytesIO(payload)) as archive:
        names = archive.namelist()
        expected = file_name(day).removesuffix(".zip") + ".csv"
        if names != [expected]:
            raise ValueError(f"Unexpected ZIP member for {day}: {names}")
        lines = archive.read(expected).decode("utf-8").splitlines()
    rows = list(csv.reader(lines))
    if len(rows) != 1 or len(rows[0]) != 12:
        raise ValueError(f"Expected one 12-field daily kline for {day}")
    record = rows[0]
    open_time = datetime.fromtimestamp(int(record[0]) / 1000, timezone.utc)
    close_time = datetime.fromtimestamp(int(record[6]) / 1000, timezone.utc)
    if open_time.date() != day or close_time.date() != day:
        raise ValueError(f"Wrong UTC date in kline {day}")
    if float(record[4]) <= 0 or float(record[5]) < 0:
        raise ValueError(f"Invalid positive price/volume for {day}")
    return {
        "open_time_utc": open_time.isoformat(), "close_time_utc": close_time.isoformat(),
        "open_usdt": record[1], "high_usdt": record[2], "low_usdt": record[3],
        "close_usdt": record[4], "base_volume_cocos": record[5],
        "quote_volume_usdt": record[7], "trade_count": record[8],
    }


def saved_cmc_endpoint() -> dict[str, str]:
    with gzip.open(PARENT, "rt", encoding="utf-8", newline="") as handle:
        found = [row for row in csv.DictReader(handle)
                 if row["experiment_id"] == "P0_M1_D0" and
                 row["year_week"] == "202103" and row["cmcid"] == "4275"]
    if len(found) != 1:
        raise ValueError("Expected unique accepted P0_M1_D0 CMCID 4275 row")
    row = found[0]
    if (row["formation_date"], row["scheduled_settlement_date"]) != ("20210114", "20210121"):
        raise ValueError("Frozen CTREND formation/settlement endpoint changed")
    return {key: row[key] for key in (
        "research_run_id", "formation_date", "scheduled_settlement_date",
        "raw_cmc_formation_close", "raw_cmc_settlement_close", "raw_cmc_endpoint_return",
        "economic_payoff_return", "vw_high_weight", "vw_direct_opening_contribution")}


def audit() -> None:
    source = json.loads(STATUS.read_text(encoding="utf-8"))
    responses = source["responses"]
    if [item["date"] for item in responses] != [day.isoformat() for day in dates()]:
        raise ValueError("Incomplete or reordered official date window")
    output = []
    for item in responses:
        day = date.fromisoformat(item["date"])
        if item["url"] != URL_PREFIX + file_name(day):
            raise ValueError(f"Wrong source URL: {day}")
        record = {"date_utc": day.isoformat(), "venue": "Binance spot",
                  "pair": "COCOSUSDT", "archive_http_status": item["http_status"],
                  "source_url": item["url"], "source_zip_sha256": item["sha256"] or ""}
        if item["http_status"] == 200:
            path = SOURCE / file_name(day)
            payload = path.read_bytes()
            if item["file"] != path.name or digest_bytes(payload) != item["sha256"]:
                raise ValueError(f"Archived official candle SHA mismatch: {day}")
            record.update(parse_kline(payload, day))
        elif item["http_status"] != 404 or item["file"] is not None or item["sha256"] is not None:
            raise ValueError(f"Invalid missing-file receipt: {day}")
        output.append(record)
    by_day = {row["date_utc"]: row for row in output}
    if [by_day[f"2021-01-{d:02}"]["archive_http_status"] for d in range(19, 24)] != [200, 404, 404, 404, 200]:
        raise ValueError("Archived trading-pause window differs from announcement")
    prior = float(by_day["2021-01-19"]["close_usdt"])
    resumed = float(by_day["2021-01-23"]["open_usdt"])
    if abs(resumed / prior - 1000) > 1e-9:
        raise ValueError("Archived Binance old-close/new-open is not exactly 1000:1")
    endpoint = saved_cmc_endpoint()
    path = OUT / "binance_cocos_exchange_window_20210114_20210124.csv"
    fields = ("date_utc", "venue", "pair", "archive_http_status", "open_time_utc",
              "close_time_utc", "open_usdt", "high_usdt", "low_usdt", "close_usdt",
              "base_volume_cocos", "quote_volume_usdt", "trade_count", "source_url",
              "source_zip_sha256")
    with path.open("w", newline="", encoding="utf-8") as handle:
        writer = csv.DictWriter(handle, fieldnames=fields)
        writer.writeheader()
        writer.writerows(output)
    receipt = {
        "scope": "one_exchange_one_pair_not_CMC_repair_or_executable_CTRENDPnL",
        "source_status_sha256": digest_file(STATUS),
        "source_zip_count": sum(item["http_status"] == 200 for item in responses),
        "official_archive_missing_dates": [item["date"] for item in responses if item["http_status"] == 404],
        "official_announcement_url": "https://www.binance.com/en/support/announcement/detail/f555f8013eff42bc9c91eaa48b9da24b",
        "independent_venue_schedule_url": "https://www.gate.com/zh/announcements/article/19040",
        "binance_last_old_close_usdt": prior,
        "binance_first_new_open_usdt": resumed,
        "observed_old_close_to_new_open_ratio": resumed / prior,
        "accepted_cmc_asset_week_parent_sha256": digest_file(PARENT),
        "accepted_cmc_endpoint": endpoint,
        "output": {path.name: digest_file(path), "rows": len(output)},
    }
    (OUT / "binance_cocos_exchange_window_receipt.json").write_text(
        json.dumps(receipt, indent=2) + "\n", encoding="utf-8")
    print(f"E08_BINANCE_COCOS_WINDOW_OK days={len(output)} source_zips={receipt['source_zip_count']} ratio={resumed/prior:.9f}")


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--fetch", action="store_true", help="One-time freeze of official Binance ZIPs; never replaces a receipt")
    args = parser.parse_args()
    if args.fetch:
        fetch()
    audit()
