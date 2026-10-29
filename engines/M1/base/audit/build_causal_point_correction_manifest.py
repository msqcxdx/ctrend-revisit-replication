#!/usr/bin/env python3
"""Build a strict-OOS pointwise external-disagreement audit.

For date t, this rule uses no observation after t.  It marks a CMC target
cell only when:

1. an adjacent-day or Tuesday-to-Tuesday CMC gross return ending at t is
   >=5 or <=0.2;
2. the exact same CoinLore UTC interval has a gross return in [0.5, 2];
3. at least five non-suspect exact-date CMC/CoinLore level ratios exist in
   the preceding 30 calendar days; and
4. the date-t level ratio differs from their median by >=5.

Ratios that differ from the trailing median by more than 2 are not admitted
to future baselines, even when no correction is made.  This prevents a bad
price regime from teaching the gate that its own scale is normal.  Verified
event windows reset the history and are excluded.  The resulting rows are
audit/sensitivity candidates only.  Production CMC prices remain observed:
one external comparator cannot by itself authorize a missing price, asset
removal, zero substitution, or any change conditional on a CTREND portfolio.
"""

from __future__ import annotations

import argparse
import datetime as dt
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
    parser.add_argument("--correction-deviation-factor", type=float, default=5)
    parser.add_argument("--baseline-admission-factor", type=float, default=2)
    args = parser.parse_args()
    if (
        args.history_days < 1
        or args.minimum_history < 1
        or args.correction_deviation_factor <= args.baseline_admission_factor
        or args.baseline_admission_factor <= 1
    ):
        parser.error("Invalid pointwise causal correction thresholds")

    comparisons = []
    for filename, frequency in (
        ("daily_extreme_return_coinlore_crosscheck.csv", "daily"),
        ("weekly_extreme_return_coinlore_crosscheck.csv", "weekly"),
    ):
        for row in read_csv(args.output_dir / filename):
            row = {**row, "TriggerFrequency": frequency}
            comparisons.append(row)

    mapping = read_csv(args.output_dir / "coinlore_asset_mapping.csv")
    mapping_by_id = {int(row["AssetID"]): row for row in mapping}
    triggers_by_id: dict[int, dict[dt.date, list[dict[str, str]]]] = {}
    identity_by_id: dict[int, dict[str, str]] = {}
    for row in comparisons:
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
        triggers_by_id.setdefault(asset_id, {}).setdefault(date1, []).append(row)
        identity_by_id[asset_id] = row

    dates, cmc_by_id = load_cmc_close(args.raw_close, set(triggers_by_id))
    date_index = {date: index for index, date in enumerate(dates)}
    cells: list[dict[str, object]] = []
    audit: list[dict[str, object]] = []

    for asset_id in sorted(triggers_by_id):
        identity = identity_by_id[asset_id]
        mapping_row = mapping_by_id[asset_id]
        external = load_external_series(HERE / mapping_row["HistoryEvidencePath"])
        cmc = cmc_by_id[asset_id]
        history: list[tuple[dt.date, float]] = []
        event_was_active = False

        for date in dates:
            ext_price = external.get(date)
            index = date_index[date]
            cmc_price = cmc[index]
            if (
                ext_price is None
                or not (cmc_price > 0)
                or not math.isfinite(cmc_price)
            ):
                continue
            log_ratio = math.log(cmc_price / ext_price)

            event_now = in_verified_event(asset_id, date)
            if event_now:
                history.clear()
                event_was_active = True
                if date in triggers_by_id[asset_id]:
                    audit.append(
                        {
                            "AssetID": asset_id,
                            "Name": identity["Name"],
                            "Symbol": identity["Symbol"],
                            "Date": date.isoformat(),
                            "Classification": "excluded_verified_event_window",
                            "HistoryObservations": 0,
                            "DeviationFactor": "",
                            "TriggerFrequencies": "|".join(
                                sorted(
                                    {
                                        row["TriggerFrequency"]
                                        for row in triggers_by_id[asset_id][date]
                                    }
                                )
                            ),
                            "ExternalHistorySHA256": mapping_row[
                                "HistoryEvidenceSHA256"
                            ],
                        }
                    )
                continue
            if event_was_active:
                history.clear()
                event_was_active = False

            history = [
                item
                for item in history
                if item[0] >= date - dt.timedelta(days=args.history_days)
            ]
            baseline = (
                statistics.median(value for _, value in history)
                if len(history) >= args.minimum_history
                else float("nan")
            )
            deviation = (
                math.exp(abs(log_ratio - baseline))
                if math.isfinite(baseline)
                else float("nan")
            )

            if date in triggers_by_id[asset_id]:
                frequencies = "|".join(
                    sorted(
                        {
                            row["TriggerFrequency"]
                            for row in triggers_by_id[asset_id][date]
                        }
                    )
                )
                if len(history) < args.minimum_history:
                    classification = "unresolved_insufficient_trailing_overlap"
                elif deviation < args.correction_deviation_factor:
                    classification = "unresolved_level_not_deviant"
                else:
                    classification = "candidate_strictly_causal_external_disagreement"
                    episode_id = f"external_causal_point_{asset_id}_{date:%Y%m%d}"
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
                            "HistoryObservations": len(history),
                            "TriggerFrequencies": frequencies,
                            "Rule": "audit_only_preserve_cmc_in_production",
                            "EvidencePolicy": (
                                "strictly causal exact-UTC external contradiction"
                            ),
                            "ExternalHistorySHA256": mapping_row[
                                "HistoryEvidenceSHA256"
                            ],
                        }
                    )
                audit.append(
                    {
                        "AssetID": asset_id,
                        "Name": identity["Name"],
                        "Symbol": identity["Symbol"],
                        "Date": date.isoformat(),
                        "Classification": classification,
                        "HistoryObservations": len(history),
                        "DeviationFactor": ""
                        if not math.isfinite(deviation)
                        else f"{deviation:.17g}",
                        "TriggerFrequencies": frequencies,
                        "ExternalHistorySHA256": mapping_row[
                            "HistoryEvidenceSHA256"
                        ],
                    }
                )
                if classification == "candidate_strictly_causal_external_disagreement":
                    # Never allow a disputed cell to redefine the future
                    # cross-source baseline.
                    continue

            if (
                not math.isfinite(deviation)
                or deviation <= args.baseline_admission_factor
            ):
                history.append((date, log_ratio))

    # The audit should remain nonempty even if a future input revision removes
    # all candidate cells; the audit output must not be silently empty.
    write_csv(args.output_dir / "causal_point_external_error_audit.csv", audit)
    write_csv(
        args.output_dir / "causal_point_external_disagreement_candidates.csv",
        cells,
    )
    summary = {
        "format": "ctrend-v2-causal-point-external-disagreement-audit-v1",
        "trigger_assets": len(triggers_by_id),
        "audited_target_cells": len(audit),
        "candidate_cells": len(cells),
        "candidate_assets": len({int(row["AssetID"]) for row in cells}),
        "policy": {
            "history_days": args.history_days,
            "minimum_history": args.minimum_history,
            "correction_deviation_factor": args.correction_deviation_factor,
            "baseline_admission_factor": args.baseline_admission_factor,
            "uses_future_observations": False,
        },
    }
    (args.output_dir / "causal_point_external_disagreement_summary.json").write_text(
        json.dumps(summary, indent=2, sort_keys=True) + "\n", encoding="utf-8"
    )
    print(json.dumps(summary, sort_keys=True))


if __name__ == "__main__":
    main()
