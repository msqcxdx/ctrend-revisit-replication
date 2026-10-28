#!/usr/bin/env python3
"""Consolidate the twelve accepted M1/M2 baseline E05 b05 audit probes.

Seven new cells passed in the initial extension, three passed after repairing
only stale audit DATA paths, and two pre-existing P0/D1 cells are retained.
The failed path-discovery attempts are disclosed, not called scientific runs.
"""

from __future__ import annotations

import argparse
import csv
import json
from pathlib import Path

from run_e06_upstream_hybrids import ROOT, sha


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--initial-root", type=Path, required=True)
    parser.add_argument("--repair-root", type=Path, required=True)
    parser.add_argument("--prior-root", type=Path, required=True)
    args = parser.parse_args()
    first_path = args.initial_root.resolve() / "receipt.json"
    repair_path = args.repair_root.resolve() / "receipt.json"
    first = json.loads(first_path.read_text())
    repair = json.loads(repair_path.read_text())
    if first["status"] != "failed" or repair["status"] != "complete":
        raise RuntimeError("Expected completed E05 path-repair audit identity")
    if {e["experiment_id"] for e in first["errors"]} != {
            r["experiment_id"] for r in repair["results"]}:
        raise RuntimeError("The repair must cover exactly the stale-path failures")
    result = {}
    parent_hashes = {}
    for receipt in (first, repair):
        for item in receipt["results"]:
            eid = item["experiment_id"]
            if eid in result:
                raise RuntimeError(f"Duplicate E05 audit: {eid}")
            path = Path(item["result"])
            if sha(path) != item["result_sha256"]:
                raise RuntimeError(f"E05 result changed: {eid}")
            result[eid] = list(csv.DictReader(path.open(newline="")))
            parent_hashes[eid] = item["accepted_input_hashes"]
    old_receipt = args.prior_root.resolve() / "receipt.json"
    previous = json.loads(old_receipt.read_text())
    if previous["status"] != "production_model_stage_passed_raw_preprocessing_not_tested":
        raise RuntimeError("The pre-existing P0/D1 b05 audit is not accepted")
    for item in previous["inputs"]:
        eid = item["experiment_id"]
        path = ROOT / "outputs/E05" / f"{eid}_production_b05_future_perturbation.csv"
        if eid in result or eid not in {"P0_M1_D1", "P0_M2_D1"}:
            raise RuntimeError("Unexpected pre-existing E05 identity")
        result[eid] = list(csv.DictReader(path.open(newline="")))
        parent_hashes[eid] = item["sha256"]
    expected = {f"P{p}_M{m}_D{d}" for p in (0, 1)
                for m in (1, 2) for d in (0, 1, 2)}
    if set(result) != expected:
        raise RuntimeError(f"E05 twelve-cell identity gap: {sorted(expected - set(result))}")
    rows = []
    for eid in sorted(result):
        variants = result[eid]
        if len(variants) != 3 or {r["variant"] for r in variants} != {
                "control", "future_values", "future_missingness"}:
            raise RuntimeError(f"E05 variant mismatch: {eid}")
        for row in variants:
            if any(int(row[k]) != 0 for k in (
                    "changed_past_predictions", "changed_past_beta_cells",
                    "changed_past_selection_cells")):
                raise RuntimeError(f"E05 past model changed: {eid}")
            if row["variant"] != "control" and int(row["changed_later_predictions"]) <= 0:
                raise RuntimeError(f"E05 future intervention ineffective: {eid}")
            rows.append({"experiment_id": eid, **row})
    out = ROOT / "outputs/E05/production_b05_12cell_future_perturbation.csv"
    manifest = ROOT / "outputs/E05/production_b05_12cell_receipt.json"
    if out.exists() or manifest.exists():
        raise FileExistsError("Refuse to overwrite the E05 consolidated audit")
    with out.open("w", newline="") as f:
        writer = csv.DictWriter(f, fieldnames=list(rows[0]))
        writer.writeheader()
        writer.writerows(rows)
    manifest.write_text(json.dumps({
        "scope": "twelve_accepted_M1_M2_baseline_b05_future_only_input_shocks_not_raw_to_trade",
        "rows": len(rows), "cells": len(result),
        "all_control_equal_accepted_and_all_past_model_outputs_unchanged": True,
        "initial_audit_receipt": {"path": str(first_path), "sha256": sha(first_path),
                                  "stale_DATA_path_failures": sorted(e["experiment_id"]
                                                               for e in first["errors"])},
        "isolated_source_view_repair_receipt": {"path": str(repair_path),
                                                "sha256": sha(repair_path)},
        "pre_existing_P0_D1_receipt": {"path": str(old_receipt),
                                       "sha256": sha(old_receipt)},
        "accepted_input_hashes": parent_hashes,
        "output_sha256": sha(out)}, indent=2) + "\n")
    print(f"E05_B05_12CELL_COVERAGE_OK cells={len(result)} rows={len(rows)}")


if __name__ == "__main__":
    main()
