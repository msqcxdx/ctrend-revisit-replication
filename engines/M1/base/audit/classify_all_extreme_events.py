#!/usr/bin/env python3
"""Assign a documented v2 disposition to every inventoried extreme return."""

from __future__ import annotations

import csv
import json
import pathlib
from collections import Counter

from build_external_corruption_manifest import (
    DEFAULT_OUTPUT,
    VERIFIED_EVENT_WINDOWS,
    parse_date,
    read_csv,
    write_csv,
)


UNIT_TRANSITIONS = {
    638: ("2015-12-02", "10 old TROLL to 1 new TROLL"),
    895: ("2016-08-22", "1 old XAU to 8000 XAUR"),
    1902: ("2018-06-07", "1 old MYB to 36 new MYB"),
    3468: ("2019-04-18", "50 old FBN to 1 new FBN"),
    4069: ("2020-03-06", "1 old BURN to 100 new BURN"),
    4275: ("2021-01-20", "CMC COMBO pre-launch price-unit error x1000"),
    5834: ("2021-03-10", "10 PLT to 1 ADD"),
}
def event_overlaps_verified(asset_id: int, date0, date1) -> bool:
    return any(
        date0 <= end and date1 >= start
        for start, end in VERIFIED_EVENT_WINDOWS.get(asset_id, [])
    )


def classify(
    row: dict[str, str],
    causal_cells: set[tuple[int, str]],
) -> tuple[str, str]:
    asset_id = int(float(row["AssetID"]))
    date0 = parse_date(row["FormationDate"])
    date1 = parse_date(row["TargetDate"])
    iso0, iso1 = date0.isoformat(), date1.isoformat()
    if (asset_id, iso0) in causal_cells or (asset_id, iso1) in causal_cells:
        return (
            "preserve_cross_source_disagreement_audit_only",
            "one-source disagreement is insufficient to modify production CMC",
        )
    if asset_id in UNIT_TRANSITIONS:
        transition_text, evidence = UNIT_TRANSITIONS[asset_id]
        transition = parse_date(transition_text)
        if date0 < transition <= date1:
            return (
                "repair_holder_continuous_unit_series",
                evidence,
            )
    if event_overlaps_verified(asset_id, date0, date1):
        return (
            "preserve_verified_real_event",
            "dated project/exchange/chain event; no magnitude-only deletion",
        )
    source_class = row.get("CrossSourceClass", "")
    if source_class == "external_corroborates_extreme_direction":
        return (
            "preserve_independent_source_corroborates",
            "exact-UTC external series confirms the extreme direction",
        )
    if source_class == "external_contradicts_cmc_extreme":
        return (
            "preserve_unresolved_causal_gate_not_met",
            "cross-source disagreement exists but the preregistered causal level gate failed",
        )
    if source_class:
        return (
            "preserve_unresolved_external_evidence",
            source_class,
        )
    return (
        "preserve_unresolved_no_external_window",
        "no exact-UTC unambiguous external history",
    )


def main() -> None:
    output = DEFAULT_OUTPUT
    causal = read_csv(
        output / "causal_point_external_disagreement_candidates.csv"
    )
    causal_cells = {(int(row["AssetID"]), row["Date"]) for row in causal}
    summary: dict[str, object] = {}
    for frequency in ("daily", "weekly"):
        rows = read_csv(
            output / f"{frequency}_extreme_return_coinlore_crosscheck.csv"
        )
        classified = []
        for row in rows:
            disposition, basis = classify(row, causal_cells)
            classified.append(
                {
                    **row,
                    "V2Disposition": disposition,
                    "DispositionBasis": basis,
                }
            )
        write_csv(output / f"{frequency}_extreme_event_disposition.csv", classified)
        counts = Counter(row["V2Disposition"] for row in classified)
        summary[frequency] = {
            "events": len(classified),
            "disposition_counts": dict(sorted(counts.items())),
        }
    summary["format"] = "ctrend-v2-extreme-event-disposition-v1"
    summary["policy"] = (
        "magnitude triggers investigation only; unconfirmed events are preserved"
    )
    (output / "extreme_event_disposition_summary.json").write_text(
        json.dumps(summary, indent=2, sort_keys=True) + "\n", encoding="utf-8"
    )
    print(json.dumps(summary, sort_keys=True))


if __name__ == "__main__":
    main()
