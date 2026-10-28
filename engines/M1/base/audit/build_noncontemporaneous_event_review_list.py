#!/usr/bin/env python3
"""Build the point-level external-review list after exact event matching.

The earlier 20260727 export removed every row belonging to an asset that
had any known or discussed event.  That asset-level filter was too broad:
an event years later (or even months later) does not explain a candidate
price cell.  This builder excludes only a candidate whose AssetID and exact
target date match an already verified real-event or holder-unit-transition
target in the daily/weekly disposition ledgers.

This is an audit export only.  It is not loaded by the production pipeline
and does not change any CMC price or return.
"""

from __future__ import annotations

import csv
import hashlib
import json
import shutil
from collections import defaultdict
from datetime import datetime
from pathlib import Path


SCRIPT = Path(__file__).resolve()
CODE = SCRIPT.parents[1]
PROJECT = SCRIPT.parents[2]
OUTPUT = CODE / "audit" / "output"
SOURCE = OUTPUT / "causal_point_external_disagreement_candidates.csv"
PRIOR_KEPT = (
    OUTPUT
    / "causal_point_external_disagreement_candidates_excluding_known_event_assets_20260727.csv"
)
PRIOR_REMOVED = (
    OUTPUT
    / "causal_point_external_disagreement_candidates_excluded_known_event_assets_20260727.csv"
)
NEW_NAME = (
    "causal_point_external_disagreement_candidates_"
    "excluding_contemporaneous_known_events_20260728.csv"
)
NEW_AUDIT_OUTPUT = OUTPUT / NEW_NAME
NEW_PROJECT_OUTPUT = PROJECT / NEW_NAME
MATCH_OUTPUT = OUTPUT / "causal_point_contemporaneous_known_event_matches_20260728.csv"
REINSTATED_OUTPUT = OUTPUT / "causal_point_asset_level_overexclusion_reinstated_20260728.csv"
SUMMARY_OUTPUT = OUTPUT / "causal_point_contemporaneous_event_filter_summary_20260728.json"

EVENT_DISPOSITIONS = {
    "preserve_verified_real_event",
    "repair_holder_continuous_unit_series",
}


def read_csv(path: Path) -> tuple[list[str], list[dict[str, str]]]:
    with path.open(newline="", encoding="utf-8-sig") as handle:
        reader = csv.DictReader(handle)
        rows = list(reader)
        if reader.fieldnames is None:
            raise AssertionError(f"Missing header: {path}")
        return list(reader.fieldnames), rows


def write_csv(path: Path, fields: list[str], rows: list[dict[str, str]]) -> None:
    with path.open("w", newline="", encoding="utf-8") as handle:
        writer = csv.DictWriter(handle, fieldnames=fields, lineterminator="\n")
        writer.writeheader()
        writer.writerows(rows)


def iso_date(text: str) -> str:
    return datetime.strptime(text, "%d-%b-%Y").date().isoformat()


def digest(path: Path) -> str:
    value = hashlib.sha256()
    with path.open("rb") as handle:
        for block in iter(lambda: handle.read(1024 * 1024), b""):
            value.update(block)
    return value.hexdigest()


def row_key(row: dict[str, str]) -> tuple[str, str, str]:
    return row["EpisodeID"], row["AssetID"], row["Date"]


def prior_context(row: dict[str, str]) -> tuple[str, str]:
    asset_id = row["AssetID"]
    date = row["Date"]
    if asset_id == "184":
        return (
            "DNotes 2.0 1:1 event window: 2018-05-02/2018-05-03",
            "candidate is in 2020/2021, not the 2018 event window",
        )
    if asset_id == "638":
        return (
            "Trollcoin 10:1 holder-unit transition: 2015-12-02",
            "candidate is 2020-09-18, not the 2015 transition",
        )
    if asset_id == "2603":
        return (
            "NPXS/PUNDIX project conversion uses distinct CMCIDs",
            "2022 NPXS point remains a separate old-token series under the CMCID boundary",
        )
    if asset_id == "3787":
        relation = (
            "candidate predates the discussion"
            if date < "2020-06-01"
            else "candidate has no exact dated causal match to the discussion"
        )
        return (
            "INNBCL token swap publicly discussed in 2020-06",
            relation,
        )
    raise AssertionError(f"Unexpected prior asset-level exclusion: {asset_id}")


def main() -> None:
    fields, candidates = read_csv(SOURCE)
    _, prior_kept = read_csv(PRIOR_KEPT)
    _, prior_removed = read_csv(PRIOR_REMOVED)

    candidate_keys = {row_key(row) for row in candidates}
    kept_keys = {row_key(row) for row in prior_kept}
    removed_keys = {row_key(row) for row in prior_removed}
    assert len(candidates) == 2600 and len(candidate_keys) == 2600
    assert len(prior_kept) == 2567 and len(prior_removed) == 33
    assert not kept_keys & removed_keys
    assert kept_keys | removed_keys == candidate_keys

    exact_events: dict[tuple[str, str], list[dict[str, str]]] = defaultdict(list)
    for ledger_name in (
        "daily_extreme_event_disposition.csv",
        "weekly_extreme_event_disposition.csv",
    ):
        _, ledger = read_csv(OUTPUT / ledger_name)
        for row in ledger:
            if row["V2Disposition"] not in EVENT_DISPOSITIONS:
                continue
            exact_events[(row["AssetID"], iso_date(row["TargetDate"]))].append(
                {
                    "Ledger": ledger_name,
                    "FormationDate": row["FormationDate"],
                    "TargetDate": row["TargetDate"],
                    "V2Disposition": row["V2Disposition"],
                    "DispositionBasis": row["DispositionBasis"],
                }
            )

    matched: list[dict[str, str]] = []
    retained: list[dict[str, str]] = []
    for row in candidates:
        events = exact_events.get((row["AssetID"], row["Date"]), [])
        if events:
            for event in events:
                matched.append(
                    row
                    | event
                    | {
                        "FilterDecision": "exclude_exact_contemporaneous_known_event"
                    }
                )
        else:
            retained.append(row)

    # In the certified v2 audit, none of the 2,600 causal disagreement
    # candidates is an exact target-date match to a verified event.  Preserve
    # the source bytes to make that identity independently checkable.
    assert not matched
    assert len(retained) == 2600
    shutil.copyfile(SOURCE, NEW_AUDIT_OUTPUT)
    shutil.copyfile(SOURCE, NEW_PROJECT_OUTPUT)

    match_fields = fields + [
        "Ledger",
        "FormationDate",
        "TargetDate",
        "V2Disposition",
        "DispositionBasis",
        "FilterDecision",
    ]
    write_csv(MATCH_OUTPUT, match_fields, matched)

    reinstated_fields = fields + [
        "PriorFilter",
        "KnownEventContext",
        "PointLevelAssessment",
        "ContemporaneousKnownEvent",
        "FinalDecision",
    ]
    reinstated: list[dict[str, str]] = []
    for row in prior_removed:
        context, assessment = prior_context(row)
        reinstated.append(
            row
            | {
                "PriorFilter": "excluded_whole_asset_20260727",
                "KnownEventContext": context,
                "PointLevelAssessment": assessment,
                "ContemporaneousKnownEvent": "0",
                "FinalDecision": "reinstate_for_external_review",
            }
        )
    write_csv(REINSTATED_OUTPUT, reinstated_fields, reinstated)

    innbcl = [row for row in retained if row["AssetID"] == "3787"]
    assert len(innbcl) == 24
    assert {row["Date"] for row in innbcl} >= {"2020-04-16", "2020-04-21"}
    assert digest(NEW_AUDIT_OUTPUT) == digest(SOURCE)
    assert digest(NEW_PROJECT_OUTPUT) == digest(SOURCE)

    summary = {
        "format": "cttrend-v2-point-level-contemporaneous-event-filter-v1",
        "source": str(SOURCE.relative_to(PROJECT)),
        "source_rows": len(candidates),
        "prior_asset_level_kept_rows": len(prior_kept),
        "prior_asset_level_removed_rows": len(prior_removed),
        "exact_contemporaneous_known_event_matches": len(matched),
        "final_external_review_rows": len(retained),
        "reinstated_asset_level_overexclusions": len(reinstated),
        "reinstated_innbcl_rows": len(innbcl),
        "innbcl_2020_04_16_present": True,
        "innbcl_2020_04_21_present": True,
        "production_pipeline_consumes_export": False,
        "new_export": str(NEW_PROJECT_OUTPUT.relative_to(PROJECT)),
        "new_export_sha256": digest(NEW_PROJECT_OUTPUT),
        "matched_event_rows": str(MATCH_OUTPUT.relative_to(PROJECT)),
        "reinstated_audit": str(REINSTATED_OUTPUT.relative_to(PROJECT)),
    }
    SUMMARY_OUTPUT.write_text(
        json.dumps(summary, indent=2, sort_keys=True) + "\n", encoding="utf-8"
    )
    print(
        "POINT_LEVEL_EVENT_FILTER_OK "
        f"source={len(candidates)} exact_event_matches={len(matched)} "
        f"final={len(retained)} reinstated={len(reinstated)} "
        f"innbcl={len(innbcl)} sha256={summary['new_export_sha256']}"
    )


if __name__ == "__main__":
    main()
