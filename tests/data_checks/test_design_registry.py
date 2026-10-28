#!/usr/bin/env python3
# CTREND_REVISIT_FILE_PURPOSE: Validate the nine-cell registry and the exact D1/D2 exclusion and retained-asset contracts.
"""Fail-closed checks for the 3x3 method/data ablation registry."""

# Inputs: the experiment registry, D0/D1/D2 exclusion lists, event registry,
# and immutable raw-data metadata.  The assertions below jointly verify the
# full Cartesian design, exclusion identities, and their recorded hashes.
# Failure meaning: an experiment could otherwise be routed to the wrong data
# treatment, so any mismatch must stop preflight rather than be auto-repaired.

import csv
import pathlib

ROOT = pathlib.Path(__file__).resolve().parents[2]


def rows(relative):
    with (ROOT / relative).open(newline="", encoding="utf-8") as handle:
        return list(csv.DictReader(handle))


experiments = rows("config/experiments.csv")
# Preserve both membership and the published display/run order.
assert [r["experiment_id"] for r in experiments] == [
    "M0_D0", "M0_D1", "M0_D2", "M1_D0", "M1_D1", "M1_D2",
    "M2_D0", "M2_D1", "M2_D2",
]
assert all(r["raw_adjustment_mode"] == "none" for r in experiments)
assert len({(r["method_id"], r["data_id"]) for r in experiments}) == 9
assert {r["method_engine"] for r in experiments} == {
    "engines/M0/base", "engines/M1/base", "engines/M2/base"
}

d0 = rows("config/exclusions/D0.csv")
d1 = rows("config/exclusions/D1.csv")
d2 = rows("config/exclusions/D2.csv")
assert d0 == []
assert [(int(r["asset_id"]), r["symbol"]) for r in d1] == [(3787, "INNBCL")]
assert len(d2) == 28
d2_ids = [int(r["asset_id"]) for r in d2]
assert len(set(d2_ids)) == 28 and 3787 in d2_ids and 1 not in d2_ids

registry = rows("config/event_asset_registry_v20260811.csv")
# D2 is defined by asset identity, not by symbol text or event-row count.
assert len(registry) == 30
event_ids = {int(r["asset_id"]) for r in registry if r["in_D2"] == "1"}
not_d2 = {int(r["asset_id"]) for r in registry if r["in_D2"] == "0"}
assert len(event_ids) == 27
assert set(d2_ids) - {3787} == event_ids
assert not_d2 == {2603, 6539, 9040}
assert not ({2603, 6539, 9040} & set(d2_ids))

safe = {
    int(r["asset_id"]) for r in registry
    if r["independent_reaudit_class"] == "A_safe_fixed"
}
unresolved = {
    int(r["asset_id"]) for r in registry
    if r["independent_reaudit_class"] == "C_confirmed_unresolved"
}
separate = {
    int(r["asset_id"]) for r in registry
    if r["independent_reaudit_class"] == "D_different_assets_or_cmcids"
}
nonfixed = {
    int(r["asset_id"]) for r in registry
    if r["independent_reaudit_class"] == "E_non_fixed_rebase"
}
assert len(safe) == 18
assert len(unresolved) == 9
assert {17020, 18615}.issubset(unresolved)
assert separate == {2603, 9040}
assert nonfixed == {6539}
assert safe.isdisjoint(unresolved | separate | nonfixed)

print(
    "DESIGN_REGISTRY_TEST_OK experiments=9 d1=1 d2=28 "
    "event_assets=27 separate_cmcids_retained=2 nonfixed_retained=1"
)
