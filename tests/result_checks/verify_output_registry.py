#!/usr/bin/env python3
# CTREND_REVISIT_FILE_PURPOSE: Verify that one completed experiment produced every required paper table and figure artifact.
"""Verify every required paper artifact for one completed experiment."""

# Arguments identify the package registry and one run-specific result root.
# Only artifacts applicable to that experiment/method are required; common
# documentation is intentionally checked at package preflight instead.

import csv
import json
import pathlib
import sys

if len(sys.argv) != 4:
    raise SystemExit("usage: verify_output_registry.py PACKAGE_ROOT EXPERIMENT_ID RESULTS_ROOT")

root = pathlib.Path(sys.argv[1]).resolve()
experiment_id = sys.argv[2]
results = pathlib.Path(sys.argv[3]).resolve()
method = experiment_id.split("_", 1)[0]
valid = {
    "M0_D0", "M0_D1", "M0_D2", "M1_D0", "M1_D1", "M1_D2",
    "M2_D0", "M2_D1", "M2_D2",
}
assert experiment_id in valid
assert results.is_dir()

checked = []
# Resolve each registry glob inside the supplied result root and fail on empty files.
with (root / "config" / "output_registry.csv").open(newline="", encoding="utf-8") as handle:
    for row in csv.DictReader(handle):
        scope = row["experiments"]
        applies = scope == "all" or experiment_id in scope.split("|") or method in scope.split("|")
        if not applies:
            continue
        if row["producer_step"] == "documentation":
            # Common documentation is verified by package preflight, not in a
            # run-specific result tree.
            continue
        matches = []
        for pattern in row["required_output_pattern"].split("|"):
            matches.extend(path for path in results.glob(pattern) if path.is_file())
        unique = sorted(set(matches))
        minimum = int(row["minimum_matches"])
        assert len(unique) >= minimum, (
            f"{experiment_id} missing {row['paper_item']}: "
            f"found {len(unique)}, need {minimum}, patterns={row['required_output_pattern']}"
        )
        assert all(path.stat().st_size > 0 for path in unique)
        checked.append({
            "paper_item": row["paper_item"],
            "matches": len(unique),
            "minimum": minimum,
        })

expected_items = 25 if method == "M1" else 24
assert len(checked) == expected_items, (
    f"{experiment_id} output-registry coverage changed: "
    f"checked {len(checked)}, expected {expected_items}"
)
print(json.dumps({
    "format": "ctrend-output-registry-verification-v1",
    "experiment_id": experiment_id,
    "checked_items": len(checked),
    "status": "PASS",
}, sort_keys=True))
