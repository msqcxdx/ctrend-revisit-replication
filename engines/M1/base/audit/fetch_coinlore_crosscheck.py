#!/usr/bin/env python3
"""Fetch and cache an independent cross-check for every extreme-return asset.

The input inventory is produced by ``scan_extreme_raw_returns.m`` without
reference to any CTREND holding.  Asset matching fails closed: a CoinLore
history is used only when both symbol and normalized name identify one
unambiguous search result.  Every HTTP response used in the comparison is
retained in gzip form and its SHA256 is written to the mapping/audit files.

This script never edits CMC inputs.  It only creates evidence under
``audit/external_sources/coinlore`` and comparison CSV files under
``audit/output``.  It is restartable and reuses validated cached responses.
"""

from __future__ import annotations

import argparse
import csv
import datetime as dt
import difflib
import gzip
import hashlib
import http.client
import json
import os
import pathlib
import re
import threading
import time
import urllib.error
import urllib.parse
import urllib.request
from concurrent.futures import ThreadPoolExecutor, as_completed


HERE = pathlib.Path(__file__).resolve().parent
DEFAULT_OUTPUT = HERE / "output"
DEFAULT_CACHE = HERE / "external_sources" / "coinlore"
SEARCH_URL = "https://www.coinlore.com/searchjs/?q={query}"
HISTORY_URL = (
    "https://ajax.coinlore.com/ajax/hdatav2/"
    "?coin={coin_id}&s=undefined&e=undefined"
)
USER_AGENT = "Mozilla/5.0 (compatible; CTREND-data-audit/2.0)"
RATE_LOCK = threading.Lock()
LAST_REQUEST = 0.0


def normalized(value: str) -> str:
    return re.sub(r"[^a-z0-9]+", "", value.casefold())


def sha256_bytes(payload: bytes) -> str:
    return hashlib.sha256(payload).hexdigest()


def atomic_write(path: pathlib.Path, payload: bytes) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_name(f".{path.name}.tmp.{os.getpid()}.{threading.get_ident()}")
    temporary.write_bytes(payload)
    os.replace(temporary, path)


def atomic_write_gzip(path: pathlib.Path, payload: bytes) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_name(f".{path.name}.tmp.{os.getpid()}.{threading.get_ident()}")
    with gzip.GzipFile(
        filename=str(temporary), mode="wb", compresslevel=9, mtime=0
    ) as stream:
        stream.write(payload)
    os.replace(temporary, path)


def load_gzip(path: pathlib.Path) -> bytes:
    with gzip.open(path, "rb") as stream:
        return stream.read()


def rate_limit(requests_per_second: float) -> None:
    global LAST_REQUEST
    spacing = 1.0 / requests_per_second
    with RATE_LOCK:
        now = time.monotonic()
        delay = LAST_REQUEST + spacing - now
        if delay > 0:
            time.sleep(delay)
        LAST_REQUEST = time.monotonic()


def fetch_json(url: str, requests_per_second: float, retries: int = 5) -> bytes:
    error: Exception | None = None
    for attempt in range(retries):
        try:
            rate_limit(requests_per_second)
            request = urllib.request.Request(url, headers={"User-Agent": USER_AGENT})
            with urllib.request.urlopen(request, timeout=45) as response:
                payload = response.read()
            json.loads(payload)
            return payload
        except (
            OSError,
            urllib.error.URLError,
            http.client.IncompleteRead,
            json.JSONDecodeError,
        ) as exc:
            error = exc
            time.sleep(min(30.0, 2.0 ** attempt))
    raise RuntimeError(f"Could not retrieve valid JSON after {retries} attempts: {url}") from error


def read_inventory(output_dir: pathlib.Path) -> tuple[list[dict[str, str]], list[dict[str, str]]]:
    def read_one(name: str) -> list[dict[str, str]]:
        with (output_dir / name).open(newline="", encoding="utf-8-sig") as stream:
            return list(csv.DictReader(stream))

    return (
        read_one("weekly_extreme_return_inventory.csv"),
        read_one("daily_extreme_discontinuity_inventory.csv"),
    )


def unique_assets(*tables: list[dict[str, str]]) -> list[dict[str, str]]:
    assets: dict[int, dict[str, str]] = {}
    for table in tables:
        for row in table:
            asset_id = int(float(row["AssetID"]))
            identity = {
                "AssetID": str(asset_id),
                "Name": row["Name"],
                "Symbol": row["Symbol"],
            }
            previous = assets.setdefault(asset_id, identity)
            if previous != identity:
                raise ValueError(f"Inconsistent identity for CMC asset {asset_id}")
    return [assets[key] for key in sorted(assets)]


def search_asset(
    asset: dict[str, str],
    cache_dir: pathlib.Path,
    requests_per_second: float,
) -> dict[str, str]:
    asset_id = asset["AssetID"]
    cache_path = cache_dir / "search" / f"{asset_id}.json.gz"
    if cache_path.exists():
        payload = load_gzip(cache_path)
    else:
        queries = [asset["Symbol"], asset["Name"]]
        combined: dict[str, dict] = {}
        raw_queries = []
        for query in queries:
            url = SEARCH_URL.format(query=urllib.parse.quote(query))
            response = fetch_json(url, requests_per_second)
            values = json.loads(response)
            raw_queries.append({"query": query, "url": url, "response": values})
            for value in values:
                if isinstance(value, dict) and "id" in value:
                    combined[str(value["id"])] = value
        payload = json.dumps(
            {"queries": raw_queries, "results": list(combined.values())},
            sort_keys=True,
            ensure_ascii=False,
            separators=(",", ":"),
        ).encode("utf-8")
        atomic_write_gzip(cache_path, payload)

    parsed = json.loads(payload)
    candidates = parsed.get("results", [])
    exact_symbol = [
        value
        for value in candidates
        if str(value.get("symbol", "")).casefold() == asset["Symbol"].casefold()
    ]
    wanted_name = normalized(asset["Name"])
    ranked = []
    for value in exact_symbol:
        candidate_names = [
            str(value.get("name", "")),
            str(value.get("slug", "")),
            *[str(item) for item in value.get("names", [])],
        ]
        similarities = [
            difflib.SequenceMatcher(None, wanted_name, normalized(item)).ratio()
            for item in candidate_names
            if normalized(item)
        ]
        ranked.append((max(similarities, default=0.0), value))
    ranked.sort(key=lambda item: (-item[0], str(item[1].get("id", ""))))

    status = "unresolved_no_exact_symbol"
    chosen: dict | None = None
    similarity = 0.0
    if ranked:
        similarity, best = ranked[0]
        runner_up = ranked[1][0] if len(ranked) > 1 else -1.0
        if similarity == 1.0 and (len(ranked) == 1 or runner_up < 1.0):
            status = "matched_exact_name_symbol"
            chosen = best
        elif similarity >= 0.75 and similarity - runner_up >= 0.10:
            status = "matched_unique_name_symbol"
            chosen = best
        else:
            status = "unresolved_ambiguous_name_symbol"

    return {
        **asset,
        "MatchStatus": status,
        "CoinLoreID": "" if chosen is None else str(chosen["id"]),
        "CoinLoreName": "" if chosen is None else str(chosen.get("name", "")),
        "CoinLoreSymbol": "" if chosen is None else str(chosen.get("symbol", "")),
        "CoinLoreSlug": "" if chosen is None else str(chosen.get("slug", "")),
        "NameSimilarity": f"{similarity:.12g}",
        "SearchEvidencePath": str(cache_path.relative_to(HERE)),
        "SearchEvidenceSHA256": sha256_bytes(payload),
    }


def fetch_history(
    mapping: dict[str, str],
    cache_dir: pathlib.Path,
    requests_per_second: float,
) -> tuple[dict[str, str], dict[str, dict[str, float]]]:
    if not mapping["CoinLoreID"]:
        return mapping, {}
    asset_id = mapping["AssetID"]
    coin_id = mapping["CoinLoreID"]
    cache_path = cache_dir / "history" / f"{asset_id}_{coin_id}.json.gz"
    if cache_path.exists():
        payload = load_gzip(cache_path)
    else:
        payload = fetch_json(
            HISTORY_URL.format(coin_id=urllib.parse.quote(coin_id)),
            requests_per_second,
        )
        atomic_write_gzip(cache_path, payload)
    parsed = json.loads(payload)
    if not isinstance(parsed, dict) or "price" not in parsed:
        mapping = {
            **mapping,
            "HistoryStatus": "unavailable_or_malformed",
            "HistoryEvidencePath": str(cache_path.relative_to(HERE)),
            "HistoryEvidenceSHA256": sha256_bytes(payload),
            "HistoryObservations": "0",
        }
        return mapping, {}

    series: dict[str, dict[str, float]] = {}
    keys = {"price": "Price", "mcap": "MarketCap", "volume": "Volume"}
    for source_key, output_key in keys.items():
        for item in parsed.get(source_key, []):
            if not isinstance(item, list) or len(item) < 2:
                continue
            date = dt.datetime.fromtimestamp(float(item[0]) / 1000.0, dt.timezone.utc).date()
            series.setdefault(date.isoformat(), {})[output_key] = float(item[1])
    mapping = {
        **mapping,
        "HistoryStatus": "available" if series else "empty",
        "HistoryEvidencePath": str(cache_path.relative_to(HERE)),
        "HistoryEvidenceSHA256": sha256_bytes(payload),
        "HistoryObservations": str(len(series)),
    }
    return mapping, series


def parse_cmc_date(value: str) -> dt.date:
    for form in ("%d-%b-%Y", "%Y-%m-%d", "%d-%b-%y"):
        try:
            return dt.datetime.strptime(value, form).date()
        except ValueError:
            pass
    raise ValueError(f"Unrecognized inventory date: {value}")


def exact_observation(
    series: dict[str, dict[str, float]], date: dt.date
) -> tuple[str, dict[str, float]] | tuple[None, None]:
    # Both vendors define daily history on UTC calendar days.  Do not match
    # either endpoint independently to an adjacent date: doing so could
    # silently compare a different holding interval or even collapse a
    # one-day event to one observation.
    candidate = date.isoformat()
    observation = series.get(candidate)
    if observation is not None and "Price" in observation:
        return candidate, observation
    return None, None


def finite_float(value: str) -> float:
    try:
        result = float(value)
    except (TypeError, ValueError):
        return float("nan")
    return result


def classify_ratio(cmc_ratio: float, external_ratio: float) -> str:
    if not (external_ratio > 0):
        return "external_window_unavailable"
    cmc_direction = 1 if cmc_ratio >= 1 else -1
    external_direction = 1 if external_ratio >= 1 else -1
    external_extreme = external_ratio >= 3 or external_ratio <= 1 / 3
    if external_extreme and cmc_direction == external_direction:
        return "external_corroborates_extreme_direction"
    if 0.5 <= external_ratio <= 2:
        return "external_contradicts_cmc_extreme"
    if cmc_direction != external_direction:
        return "external_opposite_direction"
    return "external_partial_corroboration"


def compare_table(
    table: list[dict[str, str]],
    mapping_by_id: dict[str, dict[str, str]],
    series_by_id: dict[str, dict[str, dict[str, float]]],
) -> list[dict[str, str]]:
    output = []
    for row in table:
        asset_id = str(int(float(row["AssetID"])))
        mapping = mapping_by_id[asset_id]
        date0 = parse_cmc_date(row["FormationDate"])
        date1 = parse_cmc_date(row["TargetDate"])
        ext_date0, ext0 = exact_observation(series_by_id.get(asset_id, {}), date0)
        ext_date1, ext1 = exact_observation(series_by_id.get(asset_id, {}), date1)
        price0 = float("nan") if ext0 is None else ext0.get("Price", float("nan"))
        price1 = float("nan") if ext1 is None else ext1.get("Price", float("nan"))
        external_ratio = price1 / price0 if price0 > 0 and price1 > 0 else float("nan")
        cmc_ratio = finite_float(row["GrossRatio"])
        output.append(
            {
                **row,
                "CoinLoreMatchStatus": mapping["MatchStatus"],
                "CoinLoreID": mapping["CoinLoreID"],
                "CoinLoreName": mapping["CoinLoreName"],
                "CoinLoreDate0": "" if ext_date0 is None else ext_date0,
                "CoinLoreDate1": "" if ext_date1 is None else ext_date1,
                "CoinLorePrice0": "" if not (price0 > 0) else f"{price0:.17g}",
                "CoinLorePrice1": "" if not (price1 > 0) else f"{price1:.17g}",
                "CoinLoreGrossRatio": ""
                if not (external_ratio > 0)
                else f"{external_ratio:.17g}",
                "CrossSourceClass": classify_ratio(cmc_ratio, external_ratio),
                "CoinLoreHistorySHA256": mapping.get("HistoryEvidenceSHA256", ""),
            }
        )
    return output


def write_csv(path: pathlib.Path, rows: list[dict[str, str]]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    if not rows:
        raise ValueError(f"Refusing to write empty audit table: {path}")
    temporary = path.with_name(f".{path.name}.tmp.{os.getpid()}")
    with temporary.open("w", newline="", encoding="utf-8") as stream:
        writer = csv.DictWriter(stream, fieldnames=list(rows[0]))
        writer.writeheader()
        writer.writerows(rows)
    os.replace(temporary, path)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--output-dir", type=pathlib.Path, default=DEFAULT_OUTPUT)
    parser.add_argument("--cache-dir", type=pathlib.Path, default=DEFAULT_CACHE)
    parser.add_argument("--workers", type=int, default=4)
    parser.add_argument("--requests-per-second", type=float, default=3.0)
    args = parser.parse_args()
    if args.workers < 1 or args.requests_per_second <= 0:
        parser.error("workers and requests-per-second must be positive")

    weekly, daily = read_inventory(args.output_dir)
    assets = unique_assets(weekly, daily)
    print(f"crosscheck_unique_assets={len(assets)}", flush=True)

    mappings: list[dict[str, str]] = []
    with ThreadPoolExecutor(max_workers=args.workers) as pool:
        futures = {
            pool.submit(search_asset, asset, args.cache_dir, args.requests_per_second): asset
            for asset in assets
        }
        for number, future in enumerate(as_completed(futures), 1):
            mappings.append(future.result())
            if number % 100 == 0 or number == len(assets):
                print(f"search_progress={number}/{len(assets)}", flush=True)
    mappings.sort(key=lambda row: int(row["AssetID"]))

    series_by_id: dict[str, dict[str, dict[str, float]]] = {}
    completed_mappings: list[dict[str, str]] = []
    matched = [mapping for mapping in mappings if mapping["CoinLoreID"]]
    with ThreadPoolExecutor(max_workers=args.workers) as pool:
        futures = {
            pool.submit(
                fetch_history, mapping, args.cache_dir, args.requests_per_second
            ): mapping
            for mapping in matched
        }
        for number, future in enumerate(as_completed(futures), 1):
            mapping, series = future.result()
            completed_mappings.append(mapping)
            series_by_id[mapping["AssetID"]] = series
            if number % 100 == 0 or number == len(matched):
                print(f"history_progress={number}/{len(matched)}", flush=True)
    completed_by_id = {row["AssetID"]: row for row in completed_mappings}
    final_mappings = []
    for mapping in mappings:
        if mapping["AssetID"] in completed_by_id:
            final_mappings.append(completed_by_id[mapping["AssetID"]])
        else:
            final_mappings.append(
                {
                    **mapping,
                    "HistoryStatus": "not_requested_unresolved_mapping",
                    "HistoryEvidencePath": "",
                    "HistoryEvidenceSHA256": "",
                    "HistoryObservations": "0",
                }
            )

    mapping_by_id = {row["AssetID"]: row for row in final_mappings}
    weekly_comparison = compare_table(weekly, mapping_by_id, series_by_id)
    daily_comparison = compare_table(daily, mapping_by_id, series_by_id)
    write_csv(args.output_dir / "coinlore_asset_mapping.csv", final_mappings)
    write_csv(
        args.output_dir / "weekly_extreme_return_coinlore_crosscheck.csv",
        weekly_comparison,
    )
    write_csv(
        args.output_dir / "daily_extreme_return_coinlore_crosscheck.csv",
        daily_comparison,
    )

    summary = {
        "format": "ctrend-v2-coinlore-crosscheck-v1",
        "generated_at_utc": dt.datetime.now(dt.timezone.utc).isoformat(),
        "source_search_url": SEARCH_URL,
        "source_history_url": HISTORY_URL,
        "unique_cmc_assets": len(assets),
        "mapped_assets": sum(bool(row["CoinLoreID"]) for row in final_mappings),
        "history_assets": sum(row["HistoryStatus"] == "available" for row in final_mappings),
        "weekly_events": len(weekly_comparison),
        "weekly_external_windows": sum(
            row["CrossSourceClass"] != "external_window_unavailable"
            for row in weekly_comparison
        ),
        "daily_events": len(daily_comparison),
        "daily_external_windows": sum(
            row["CrossSourceClass"] != "external_window_unavailable"
            for row in daily_comparison
        ),
    }
    atomic_write(
        args.output_dir / "coinlore_crosscheck_summary.json",
        (json.dumps(summary, indent=2, sort_keys=True) + "\n").encode("utf-8"),
    )
    print(json.dumps(summary, sort_keys=True), flush=True)


if __name__ == "__main__":
    main()
