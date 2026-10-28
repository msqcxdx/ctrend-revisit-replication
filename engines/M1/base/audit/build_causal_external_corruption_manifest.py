#!/usr/bin/env python3
"""Build the production external-error manifest using only date-t history.

Unlike the two-sided episode audit, this state machine is admissible for the
strict-OOS main dataset.  At each UTC date it uses only:

* the current CMC and independently aggregated CoinLore prices;
* the current adjacent-day return classification; and
* nonflagged CMC/CoinLore level ratios from the preceding 30 calendar days.

An episode starts only when the current CMC daily return is extreme, the
current external daily return is within [0.5, 2], and the current source-level
ratio differs from at least five preceding observations' median by >=5.
That pre-event median is frozen.  Subsequent exact-date cells remain flagged
while their level ratio differs from the frozen baseline by >=2; the first
date back within factor 2 is retained and starts a fresh trailing history.
Verified migrations, launches, exploits, and the Terra collapse reset the
state and are never mechanically corrected.
"""

from __future__ import annotations

import argparse
import csv
import datetime as dt
import gzip
import json
import math
import pathlib
import statistics

from build_external_corruption_manifest import (
    DEFAULT_OUTPUT,
    DEFAULT_RAW,
    HERE,
    VERIFIED_EVENT_WINDOWS,
    load_cmc_close,
    load_external_series,
    parse_date,
    read_csv,
    write_csv,
)


def in_verified_event(asset_id: int, date: dt.date) -> bool:
    return any(
        start <= date <= end
        for start, end in VERIFIED_EVENT_WINDOWS.get(asset_id, [])
    )


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--output-dir", type=pathlib.Path, default=DEFAULT_OUTPUT)
    parser.add_argument("--raw-close", type=pathlib.Path, default=DEFAULT_RAW)
    parser.add_argument("--history-days", type=int, default=30)
    parser.add_argument("--minimum-history", type=int, default=5)
    parser.add_argument("--start-deviation-factor", type=float, default=5)
    parser.add_argument("--continue-deviation-factor", type=float, default=2)
    args = parser.parse_args()
    if (
        args.history_days < 1
        or args.minimum_history < 1
        or args.start_deviation_factor <= args.continue_deviation_factor
        or args.continue_deviation_factor <= 1
    ):
        parser.error("Invalid causal external-error thresholds")

    comparison = read_csv(
        args.output_dir / "daily_extreme_return_coinlore_crosscheck.csv"
    )
    mapping = read_csv(args.output_dir / "coinlore_asset_mapping.csv")
    mapping_by_id = {int(row["AssetID"]): row for row in mapping}
    triggers_by_id: dict[int, set[dt.date]] = {}
    identity_by_id: dict[int, dict[str, str]] = {}
    for row in comparison:
        if (
            row["CrossSourceClass"] != "external_contradicts_cmc_extreme"
            or not row["CoinLoreDate0"]
            or not row["CoinLoreDate1"]
        ):
            continue
        date0 = parse_date(row["FormationDate"])
        date1 = parse_date(row["TargetDate"])
        if date0.isoformat() != row["CoinLoreDate0"] or date1.isoformat() != row[
            "CoinLoreDate1"
        ]:
            continue
        asset_id = int(float(row["AssetID"]))
        triggers_by_id.setdefault(asset_id, set()).add(date1)
        identity_by_id[asset_id] = row

    dates, cmc_by_id = load_cmc_close(args.raw_close, set(triggers_by_id))
    date_index = {date: index for index, date in enumerate(dates)}
    cells: list[dict[str, object]] = []
    episodes: list[dict[str, object]] = []

    for asset_id in sorted(triggers_by_id):
        identity = identity_by_id[asset_id]
        mapping_row = mapping_by_id[asset_id]
        external_path = HERE / mapping_row["HistoryEvidencePath"]
        external = load_external_series(external_path)
        cmc = cmc_by_id[asset_id]
        overlap: list[tuple[dt.date, float, float, float]] = []
        for date in dates:
            ext_price = external.get(date)
            if ext_price is None:
                continue
            cmc_price = cmc[date_index[date]]
            if cmc_price > 0 and math.isfinite(cmc_price):
                overlap.append(
                    (date, math.log(cmc_price / ext_price), cmc_price, ext_price)
                )

        history: list[tuple[dt.date, float]] = []
        active: dict[str, object] | None = None
        event_was_active = False
        episode_number = 0
        for date, log_ratio, cmc_price, ext_price in overlap:
            event_now = in_verified_event(asset_id, date)
            if event_now:
                if active is not None:
                    active["EndDate"] = date.isoformat()
                    active["Classification"] = "terminated_at_verified_event"
                    episodes.append(active)
                    active = None
                history.clear()
                event_was_active = True
                continue
            if event_was_active:
                # Do not combine pre- and post-conversion source scales.
                history.clear()
                event_was_active = False

            history = [
                item
                for item in history
                if item[0] >= date - dt.timedelta(days=args.history_days)
            ]

            if active is not None:
                baseline = float(active["BaselineLogRatio"])
                deviation = math.exp(abs(log_ratio - baseline))
                if deviation >= args.continue_deviation_factor:
                    active["EndDate"] = date.isoformat()
                    active["FlaggedDates"] = int(active["FlaggedDates"]) + 1
                    cells.append(
                        {
                            "EpisodeID": active["EpisodeID"],
                            "AssetID": asset_id,
                            "Name": identity["Name"],
                            "Symbol": identity["Symbol"],
                            "Date": date.isoformat(),
                            "CMCPrice": f"{cmc_price:.17g}",
                            "CoinLorePrice": f"{ext_price:.17g}",
                            "CMCToExternal": f"{math.exp(log_ratio):.17g}",
                            "TrailingBaselineCMCToExternal": (
                                f"{math.exp(baseline):.17g}"
                            ),
                            "DeviationFactor": f"{deviation:.17g}",
                            "Rule": "set_only_this_cmc_ohlc_date_missing",
                            "EvidencePolicy": (
                                "strictly causal exact-UTC external contradiction"
                            ),
                            "ExternalHistorySHA256": mapping_row[
                                "HistoryEvidenceSHA256"
                            ],
                        }
                    )
                    continue

                active["EndDate"] = date.isoformat()
                active["Classification"] = "closed_on_causal_scale_recovery"
                episodes.append(active)
                active = None
                history.clear()
                history.append((date, log_ratio))
                continue

            if date in triggers_by_id[asset_id] and len(history) >= args.minimum_history:
                baseline_values = [value for _, value in history]
                baseline = statistics.median(baseline_values)
                deviation = math.exp(abs(log_ratio - baseline))
                if deviation >= args.start_deviation_factor:
                    episode_number += 1
                    episode_id = (
                        f"external_causal_{asset_id}_{date:%Y%m%d}_"
                        f"{episode_number:03d}"
                    )
                    active = {
                        "EpisodeID": episode_id,
                        "AssetID": asset_id,
                        "Name": identity["Name"],
                        "Symbol": identity["Symbol"],
                        "StartDate": date.isoformat(),
                        "EndDate": date.isoformat(),
                        "HistoryObservationsAtStart": len(history),
                        "BaselineLogRatio": baseline,
                        "BaselineCMCToExternal": f"{math.exp(baseline):.17g}",
                        "StartDeviationFactor": f"{deviation:.17g}",
                        "FlaggedDates": 1,
                        "Classification": "open_at_sample_end",
                        "ExternalHistorySHA256": mapping_row[
                            "HistoryEvidenceSHA256"
                        ],
                    }
                    cells.append(
                        {
                            "EpisodeID": episode_id,
                            "AssetID": asset_id,
                            "Name": identity["Name"],
                            "Symbol": identity["Symbol"],
                            "Date": date.isoformat(),
                            "CMCPrice": f"{cmc_price:.17g}",
                            "CoinLorePrice": f"{ext_price:.17g}",
                            "CMCToExternal": f"{math.exp(log_ratio):.17g}",
                            "TrailingBaselineCMCToExternal": (
                                f"{math.exp(baseline):.17g}"
                            ),
                            "DeviationFactor": f"{deviation:.17g}",
                            "Rule": "set_only_this_cmc_ohlc_date_missing",
                            "EvidencePolicy": (
                                "strictly causal exact-UTC external contradiction"
                            ),
                            "ExternalHistorySHA256": mapping_row[
                                "HistoryEvidenceSHA256"
                            ],
                        }
                    )
                    continue
            history.append((date, log_ratio))

        if active is not None:
            episodes.append(active)

    write_csv(args.output_dir / "causal_external_error_episode_audit.csv", episodes)
    write_csv(args.output_dir / "causal_external_corrupt_price_cells.csv", cells)
    summary = {
        "format": "cttrend-v2-causal-external-corruption-audit-v1",
        "trigger_assets": len(triggers_by_id),
        "episodes": len(episodes),
        "cells": len(cells),
        "assets": len({int(row["AssetID"]) for row in cells}),
        "open_at_sample_end": sum(
            row["Classification"] == "open_at_sample_end" for row in episodes
        ),
        "policy": {
            "history_days": args.history_days,
            "minimum_history": args.minimum_history,
            "start_deviation_factor": args.start_deviation_factor,
            "continue_deviation_factor": args.continue_deviation_factor,
            "uses_future_observations": False,
        },
    }
    (args.output_dir / "causal_external_corruption_summary.json").write_text(
        json.dumps(summary, indent=2, sort_keys=True) + "\n", encoding="utf-8"
    )
    print(json.dumps(summary, sort_keys=True))


if __name__ == "__main__":
    main()
