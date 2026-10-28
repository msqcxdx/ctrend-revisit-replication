#!/usr/bin/env python3
"""Repeat only E05 audit probes blocked by a stale parent DATA symlink.

The accepted source and data never change. A new audit-only source view links
the exact accepted b05/Utils/DesignChoices files to the accepted weekly DATA;
the production-model perturbation and bitwise control checks are reused.
"""

from __future__ import annotations

import argparse
from concurrent.futures import ThreadPoolExecutor, as_completed
import csv
import json
import os
from pathlib import Path
import re
import shutil
import uuid

from run_e05_model_perturbation_remaining import ENGINE, run_cell
from run_e06_upstream_hybrids import ROOT, sha


def prepare_view(eid: str, identity: dict, work: Path) -> tuple[dict, dict]:
    parent = Path(identity["accepted_run_root"])
    engine = ENGINE[eid.split("_")[1]]
    source = parent / "runtime" / engine
    data = [p for folder in ("data", "data.staging")
            if (p := parent / folder).is_dir() and
            (p / "bCharacteristicsOLHC_Combo1.mat").is_file()]
    if len(data) != 1:
        raise RuntimeError(f"Exactly one accepted data directory required: {eid}")
    view = work / "audit_input_views" / eid
    code = view / "runtime" / engine
    code.mkdir(parents=True)
    (view / "RUN_COMPLETE").symlink_to(parent / "RUN_COMPLETE")
    (view / "data").symlink_to(data[0], target_is_directory=True)
    # M1's weekly provenance binds the complete MATLAB source fingerprint.
    # Copy every .m byte-for-byte, rather than making a reduced helper tree.
    source_hashes = {}
    for original in source.rglob("*.m"):
        relative = original.relative_to(source)
        if any(part in ("DATA", "Results") for part in relative.parts):
            continue
        target = code / relative
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(original, target)
        source_hashes[str(relative)] = sha(original)
        if sha(target) != source_hashes[str(relative)]:
            raise RuntimeError(f"Audit source copy differs: {eid} {relative}")
    if not source_hashes or "b05CreateCTREND.m" not in source_hashes:
        raise RuntimeError(f"Missing accepted MATLAB source: {eid}")
    links = {"DesignChoices.mat": source / "DesignChoices.mat",
             "DATA": data[0]}
    for name, target in links.items():
        if not target.exists():
            raise FileNotFoundError(target)
        (code / name).symlink_to(target, target_is_directory=target.is_dir())
    if sha(view / "RUN_COMPLETE") != identity["run_complete_sha256"]:
        raise RuntimeError(f"Accepted marker changed for {eid}")
    rerouted = {**identity, "accepted_run_root": str(view)}
    provenance = {"real_accepted_run_root": str(parent),
                  "real_accepted_source": str(source),
                  "source_view": str(code),
                  "copied_matlab_source_sha256": source_hashes,
                  "links": {name: {"target": str(target),
                                   "sha256": sha(target) if target.is_file() else None}
                            for name, target in links.items()},
                  "accepted_weekly_sha256": sha(data[0] / "bCharacteristicsOLHC_Combo1.mat")}
    return rerouted, provenance


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--previous-root", type=Path, required=True)
    parser.add_argument("--work-root", type=Path, required=True)
    parser.add_argument("--matlab", type=Path, required=True)
    parser.add_argument("--workers-per-cell", type=int, default=28)
    parser.add_argument("--concurrent-cells", type=int, default=4)
    args = parser.parse_args()
    previous = args.previous_root.resolve()
    work = args.work_root.resolve()
    if work.exists():
        raise FileExistsError(work)
    if not args.matlab.is_file() or not os.access(args.matlab, os.X_OK):
        raise FileNotFoundError(args.matlab)
    cpu = len(os.sched_getaffinity(0))
    if (args.concurrent_cells < 1 or args.workers_per_cell < 1 or
            args.concurrent_cells * (args.workers_per_cell + 1) > cpu):
        raise ValueError("MATLAB process budget exceeds CPU affinity")
    if shutil.disk_usage(work.parent).free < 10 * 2**30:
        raise RuntimeError("Insufficient scratch headroom")
    prior = json.loads((previous / "receipt.json").read_text())
    if prior["status"] != "failed" or not prior["errors"]:
        raise RuntimeError("Previous E05 audit must have finalized with failed cells")
    failed = []
    for entry in prior["errors"]:
        eid = entry["experiment_id"]
        log = (previous / eid / "pipeline.log").read_text(errors="replace")
        if not re.search(r"Unable to find file or directory '\./DATA/bCharacteristicsOLHC_Combo1\.mat'", log):
            raise RuntimeError(f"Failure is not the known stale DATA link: {eid}")
        failed.append(eid)
    identities = {r["experiment_id"]: r for r in csv.DictReader(
        (ROOT / "outputs/E11/accepted_run_paths.csv").open(newline=""))}
    work.mkdir()
    views = {eid: prepare_view(eid, identities[eid], work) for eid in failed}
    receipt = {"research_run_id": str(uuid.uuid4()), "status": "running",
               "scope": "E05_audit_source_view_repair_no_production_mutation",
               "driver_sha256": sha(Path(__file__)),
               "reused_model_probe_sha256": sha(ROOT / "scripts/test_e05_production_model_perturbation.m"),
               "previous_receipt_sha256": sha(previous / "receipt.json"),
               "workers_per_cell": args.workers_per_cell,
               "concurrent_cells": args.concurrent_cells,
               "source_views": {eid: info for eid, (_, info) in views.items()},
               "results": [], "errors": []}
    path = work / "receipt.json"
    path.write_text(json.dumps(receipt, indent=2) + "\n")
    with ThreadPoolExecutor(max_workers=args.concurrent_cells) as pool:
        futures = {pool.submit(run_cell, eid, view_identity, work,
                               args.matlab, args.workers_per_cell, 202016): eid
                   for eid, (view_identity, _) in views.items()}
        for future in as_completed(futures):
            eid = futures[future]
            try:
                receipt["results"].append(future.result())
            except BaseException as exc:
                receipt["errors"].append({"experiment_id": eid, "error": repr(exc)})
            path.write_text(json.dumps(receipt, indent=2) + "\n")
    receipt["status"] = "complete" if not receipt["errors"] else "failed"
    path.write_text(json.dumps(receipt, indent=2) + "\n")
    if receipt["errors"]:
        raise RuntimeError("Repaired E05 audit still has failed cells; preserve root")
    print(f"E05_SOURCE_VIEW_REPAIR_COMPLETE cells={len(failed)}", flush=True)


if __name__ == "__main__":
    main()
