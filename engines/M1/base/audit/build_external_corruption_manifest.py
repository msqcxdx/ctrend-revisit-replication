#!/usr/bin/env python3
"""Identify only closed, externally contradicted CMC data-error episodes.

An extreme CMC return is never sufficient for a correction.  This audit
uses the exact-UTC CoinLore comparison and requires a closed episode:

* every trigger edge is an adjacent-day CMC gross ratio >=5 or <=0.2 while
  the independently aggregated CoinLore gross ratio is within [0.5, 2];
* at least three exact-date CMC/CoinLore level ratios are observed in each
  of the 30 calendar days before and after the candidate episode;
* the pre- and post-episode median level ratios agree within a factor of 2;
* a cell is marked only when its CMC/CoinLore level ratio deviates from that
  bracketed baseline by at least a factor of 5.

The output is evidence, not an in-place edit.  A later MATLAB registry may
make only the listed asset-date OHLC cell unavailable; it must not delete an
asset, substitute zero, or condition on a CTREND holding.
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


HERE = pathlib.Path(__file__).resolve().parent
DEFAULT_OUTPUT = HERE / "output"
DEFAULT_RAW = HERE.parent / "DATA" / "close_cmc.csv"

# Dated project/exchange/chain evidence takes precedence over a mechanical
# cross-source disagreement.  The intervals include the adjacent bar needed
# to audit a holder-continuous return.  Other episodes of the same asset are
# still eligible for the universal closed-episode test.
VERIFIED_EVENT_WINDOWS = {
    184: [(dt.date(2018, 5, 1), dt.date(2018, 5, 6))],  # DNotes 2.0, 1:1
    638: [(dt.date(2015, 12, 1), dt.date(2015, 12, 5))],  # 10 old : 1 new
    895: [(dt.date(2016, 8, 21), dt.date(2016, 8, 23))],  # 1 old : 8000 new
    1902: [(dt.date(2018, 6, 6), dt.date(2018, 6, 8))],  # 1 old : 36 new
    3468: [(dt.date(2019, 4, 17), dt.date(2019, 4, 26))],  # 50 old : 1 new
    4069: [(dt.date(2020, 3, 5), dt.date(2020, 3, 9))],  # 1 old : 100 new
    4172: [(dt.date(2022, 5, 9), dt.date(2022, 5, 14))],  # Terra collapse
    4275: [(dt.date(2021, 1, 19), dt.date(2021, 1, 21))],  # CMC unit repair
    5834: [(dt.date(2021, 3, 8), dt.date(2021, 3, 10))],  # 10 PLT : 1 ADD
    7189: [
        (dt.date(2020, 11, 16), dt.date(2020, 11, 18)),  # OUSD exploit
        (dt.date(2021, 1, 6), dt.date(2021, 1, 8)),  # OUSD relaunch
    ],
    7497: [(dt.date(2020, 12, 21), dt.date(2020, 12, 22))],  # POND launch
}


def parse_date(value: str) -> dt.date:
    for form in ("%d-%b-%Y", "%Y-%m-%d"):
        try:
            return dt.datetime.strptime(value, form).date()
        except ValueError:
            pass
    raise ValueError(f"Unrecognized date {value!r}")


def read_csv(path: pathlib.Path) -> list[dict[str, str]]:
    with path.open(newline="", encoding="utf-8-sig") as stream:
        return list(csv.DictReader(stream))


def write_csv(path: pathlib.Path, rows: list[dict[str, object]]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    if not rows:
        raise ValueError(f"Refusing to write empty audit table: {path}")
    temporary = path.with_name(f".{path.name}.tmp")
    with temporary.open("w", newline="", encoding="utf-8") as stream:
        writer = csv.DictWriter(stream, fieldnames=list(rows[0]))
        writer.writeheader()
        writer.writerows(rows)
    temporary.replace(path)


def load_cmc_close(
    path: pathlib.Path, wanted_ids: set[int]
) -> tuple[list[dt.date], dict[int, list[float]]]:
    with path.open(newline="", encoding="utf-8-sig") as stream:
        reader = csv.reader(stream)
        header = next(reader)
        positions = {
            int(float(value)): index
            for index, value in enumerate(header[1:], 1)
            if value and int(float(value)) in wanted_ids
        }
        if set(positions) != wanted_ids:
            missing = sorted(wanted_ids - set(positions))
            raise ValueError(f"CMC close panel lacks mapped asset IDs: {missing[:20]}")
        dates: list[dt.date] = []
        values = {asset_id: [] for asset_id in wanted_ids}
        for row in reader:
            dates.append(dt.date.fromisoformat(row[0]))
            for asset_id, index in positions.items():
                try:
                    value = float(row[index])
                except (ValueError, IndexError):
                    value = float("nan")
                values[asset_id].append(value)
    return dates, values


def load_external_series(path: pathlib.Path) -> dict[dt.date, float]:
    with gzip.open(path, "rt", encoding="utf-8") as stream:
        parsed = json.load(stream)
    output: dict[dt.date, float] = {}
    for item in parsed.get("price", []):
        if not isinstance(item, list) or len(item) < 2:
            continue
        date = dt.datetime.fromtimestamp(
            float(item[0]) / 1000.0, dt.timezone.utc
        ).date()
        value = float(item[1])
        if value > 0 and math.isfinite(value):
            output[date] = value
    return output


def group_edges(
    rows: list[dict[str, str]], maximum_gap_days: int
) -> list[list[dict[str, str]]]:
    rows = sorted(rows, key=lambda row: parse_date(row["FormationDate"]))
    groups: list[list[dict[str, str]]] = []
    for row in rows:
        if not groups:
            groups.append([row])
            continue
        previous_end = parse_date(groups[-1][-1]["TargetDate"])
        current_start = parse_date(row["FormationDate"])
        if (current_start - previous_end).days <= maximum_gap_days:
            groups[-1].append(row)
        else:
            groups.append([row])
    return groups


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--output-dir", type=pathlib.Path, default=DEFAULT_OUTPUT)
    parser.add_argument("--raw-close", type=pathlib.Path, default=DEFAULT_RAW)
    parser.add_argument("--maximum-edge-gap-days", type=int, default=7)
    parser.add_argument("--baseline-window-days", type=int, default=30)
    parser.add_argument("--minimum-side-observations", type=int, default=3)
    parser.add_argument("--baseline-agreement-factor", type=float, default=2)
    parser.add_argument("--cell-deviation-factor", type=float, default=5)
    args = parser.parse_args()
    if (
        args.maximum_edge_gap_days < 0
        or args.baseline_window_days < 1
        or args.minimum_side_observations < 1
        or args.baseline_agreement_factor <= 1
        or args.cell_deviation_factor <= 1
    ):
        parser.error("Invalid closed-episode audit thresholds")

    comparison = read_csv(
        args.output_dir / "daily_extreme_return_coinlore_crosscheck.csv"
    )
    mapping = read_csv(args.output_dir / "coinlore_asset_mapping.csv")
    mapping_by_id = {int(row["AssetID"]): row for row in mapping}
    triggers = [
        row
        for row in comparison
        if row["CrossSourceClass"] == "external_contradicts_cmc_extreme"
        and row["CoinLoreDate0"]
        and row["CoinLoreDate1"]
        and parse_date(row["FormationDate"]).isoformat() == row["CoinLoreDate0"]
        and parse_date(row["TargetDate"]).isoformat() == row["CoinLoreDate1"]
    ]
    rows_by_id: dict[int, list[dict[str, str]]] = {}
    for row in triggers:
        rows_by_id.setdefault(int(float(row["AssetID"])), []).append(row)

    dates, cmc_by_id = load_cmc_close(args.raw_close, set(rows_by_id))
    date_index = {date: index for index, date in enumerate(dates)}
    confirmed: list[dict[str, object]] = []
    episodes: list[dict[str, object]] = []

    for asset_id in sorted(rows_by_id):
        identity = mapping_by_id[asset_id]
        evidence_path = HERE / identity["HistoryEvidencePath"]
        external = load_external_series(evidence_path)
        cmc = cmc_by_id[asset_id]
        log_level_ratio: dict[dt.date, float] = {}
        for date, ext_price in external.items():
            index = date_index.get(date)
            if index is None:
                continue
            cmc_price = cmc[index]
            if cmc_price > 0 and math.isfinite(cmc_price):
                log_level_ratio[date] = math.log(cmc_price / ext_price)

        for group_number, group in enumerate(
            group_edges(rows_by_id[asset_id], args.maximum_edge_gap_days), 1
        ):
            start = min(parse_date(row["FormationDate"]) for row in group)
            end = max(parse_date(row["TargetDate"]) for row in group)
            before = [
                value
                for date, value in log_level_ratio.items()
                if start - dt.timedelta(days=args.baseline_window_days)
                <= date
                < start
            ]
            after = [
                value
                for date, value in log_level_ratio.items()
                if end
                < date
                <= end + dt.timedelta(days=args.baseline_window_days)
            ]
            before.sort()
            after.sort()
            reason = "confirmed_closed_external_contradiction"
            if any(
                start <= event_end and end >= event_start
                for event_start, event_end in VERIFIED_EVENT_WINDOWS.get(
                    asset_id, []
                )
            ):
                reason = "excluded_verified_event_window"
            elif len(before) < args.minimum_side_observations:
                reason = "unresolved_insufficient_pre_episode_overlap"
            elif len(after) < args.minimum_side_observations:
                reason = "unresolved_insufficient_post_episode_overlap"

            pre_median = statistics.median(before) if before else float("nan")
            post_median = statistics.median(after) if after else float("nan")
            if (
                reason == "confirmed_closed_external_contradiction"
                and abs(pre_median - post_median)
                > math.log(args.baseline_agreement_factor)
            ):
                reason = "unresolved_pre_post_scale_disagreement"
            baseline = (
                (pre_median + post_median) / 2
                if math.isfinite(pre_median) and math.isfinite(post_median)
                else float("nan")
            )
            marked = []
            if reason == "confirmed_closed_external_contradiction":
                for date, value in sorted(log_level_ratio.items()):
                    if start <= date <= end and abs(value - baseline) >= math.log(
                        args.cell_deviation_factor
                    ):
                        marked.append((date, value))
                if not marked:
                    reason = "unresolved_no_bracketed_deviant_cell"

            episode_id = f"external_closed_{asset_id}_{start:%Y%m%d}_{group_number:03d}"
            episodes.append(
                {
                    "EpisodeID": episode_id,
                    "AssetID": asset_id,
                    "Name": group[0]["Name"],
                    "Symbol": group[0]["Symbol"],
                    "StartDate": start.isoformat(),
                    "EndDate": end.isoformat(),
                    "TriggerEdges": len(group),
                    "PreObservations": len(before),
                    "PostObservations": len(after),
                    "PreMedianCMCToExternal": ""
                    if not math.isfinite(pre_median)
                    else f"{math.exp(pre_median):.17g}",
                    "PostMedianCMCToExternal": ""
                    if not math.isfinite(post_median)
                    else f"{math.exp(post_median):.17g}",
                    "MarkedDates": len(marked),
                    "Classification": reason,
                    "ExternalHistorySHA256": identity["HistoryEvidenceSHA256"],
                }
            )
            if reason != "confirmed_closed_external_contradiction":
                continue
            for date, value in marked:
                index = date_index[date]
                confirmed.append(
                    {
                        "EpisodeID": episode_id,
                        "AssetID": asset_id,
                        "Name": group[0]["Name"],
                        "Symbol": group[0]["Symbol"],
                        "Date": date.isoformat(),
                        "CMCPrice": f"{cmc[index]:.17g}",
                        "CoinLorePrice": f"{external[date]:.17g}",
                        "CMCToExternal": f"{math.exp(value):.17g}",
                        "BaselineCMCToExternal": f"{math.exp(baseline):.17g}",
                        "DeviationFactor": f"{math.exp(abs(value-baseline)):.17g}",
                        "Rule": "set_only_this_cmc_ohlc_date_missing",
                        "EvidencePolicy": (
                            "two-sided closed episode; exact UTC dates; "
                            "independent return non-extreme"
                        ),
                        "ExternalHistorySHA256": identity["HistoryEvidenceSHA256"],
                    }
                )

    write_csv(args.output_dir / "external_contradiction_episode_audit.csv", episodes)
    write_csv(
        args.output_dir / "confirmed_external_corrupt_price_cells.csv", confirmed
    )
    summary = {
        "format": "ctrend-v2-closed-external-corruption-audit-v1",
        "trigger_edges": len(triggers),
        "candidate_episodes": len(episodes),
        "confirmed_episodes": sum(
            row["Classification"] == "confirmed_closed_external_contradiction"
            for row in episodes
        ),
        "confirmed_cells": len(confirmed),
        "confirmed_assets": len({int(row["AssetID"]) for row in confirmed}),
        "policy": {
            "maximum_edge_gap_days": args.maximum_edge_gap_days,
            "baseline_window_days": args.baseline_window_days,
            "minimum_side_observations": args.minimum_side_observations,
            "baseline_agreement_factor": args.baseline_agreement_factor,
            "cell_deviation_factor": args.cell_deviation_factor,
        },
    }
    summary_path = args.output_dir / "external_corruption_manifest_summary.json"
    summary_path.write_text(
        json.dumps(summary, indent=2, sort_keys=True) + "\n", encoding="utf-8"
    )
    print(json.dumps(summary, sort_keys=True))


if __name__ == "__main__":
    main()
