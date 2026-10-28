#!/usr/bin/env python3
"""Sequentially refit E06 baseline modules on specified accepted P/D cells.

Each cell gets new, isolated A/B and C+D work roots.  This orchestrates only
the baseline design, never a production 3,072-design run.  A failure stops
the sequence and preserves all completed/failed roots for inspection.
"""

from __future__ import annotations

import argparse
from datetime import datetime, timezone
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import uuid


ROOT = Path(__file__).resolve().parents[1]
SCRIPTS = ROOT / "scripts"


def invoke(args: list[str], log: Path) -> None:
    with log.open("w", encoding="utf-8") as stream:
        result = subprocess.run(args, stdout=stream, stderr=subprocess.STDOUT,
                                env={**os.environ, "OPENBLAS_NUM_THREADS": "1"})
    if result.returncode:
        raise RuntimeError(f"Command failed rc={result.returncode}: {' '.join(args)}; log={log}")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--scratch", type=Path, required=True)
    parser.add_argument("--matlab", type=Path, required=True)
    parser.add_argument("--workers", type=int, default=96)
    parser.add_argument("--experiment", action="append", required=True)
    args = parser.parse_args()
    if len(set(args.experiment)) != len(args.experiment):
        raise ValueError("Repeated P/D experiment")
    if any(re.fullmatch(r"P[01]_M2_D[012]", x) is None for x in args.experiment):
        raise ValueError("Only accepted M2 baseline P/D cells are supported")
    if not args.matlab.is_file() or not os.access(args.matlab, os.X_OK):
        raise FileNotFoundError(args.matlab)
    if not 1 <= args.workers < len(os.sched_getaffinity(0)):
        raise ValueError("Workers exceed observed CPU affinity")
    scratch = args.scratch.resolve()
    if not scratch.is_dir():
        raise FileNotFoundError(scratch)
    if shutil.disk_usage(scratch).free < 25 * 2**30:
        raise RuntimeError("Reserve at least 25 GiB before grid refits")
    stamp = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ")
    identity = str(uuid.uuid4())
    receipt_path = scratch / f"e06_remaining_grid_{stamp}_{identity[:8]}.json"
    receipt = dict(research_run_id=identity, started_utc=stamp,
                   scope="sequential_baseline_sensitivity_not_3072_design_grid",
                   experiments=args.experiment, workers=args.workers, status="running", runs=[])
    receipt_path.write_text(json.dumps(receipt, indent=2) + "\n")
    try:
        for eid in args.experiment:
            ab = scratch / "runs" / f"e06_AB_{eid}_{stamp}_{identity[:8]}"
            cd = scratch / "runs" / f"e06_CD_{eid}_{stamp}_{identity[:8]}"
            output = ROOT / "outputs" / "E06" / "sensitivities" / eid
            if ab.exists() or cd.exists() or output.exists():
                raise FileExistsError(f"One target already exists: {eid}")
            print(f"E06_GRID_START {eid}", flush=True)
            invoke([sys.executable, str(SCRIPTS / "run_e06_upstream_hybrids.py"),
                    "--experiment", eid, "--work-root", str(ab),
                    "--matlab", str(args.matlab), "--workers", str(args.workers)],
                   scratch / f"e06_AB_{eid}_{stamp}.log")
            if json.loads((ab / "manifest.json").read_text())["status"] != "AB_factorial_complete_CDE_not_yet_run":
                raise RuntimeError(f"A/B manifest not complete: {eid}")
            invoke([sys.executable, str(SCRIPTS / "run_e06_support_selection_hybrids.py"),
                    "--ab-root", str(ab), "--work-root", str(cd),
                    "--matlab", str(args.matlab), "--workers", str(args.workers)],
                   scratch / f"e06_CD_{eid}_{stamp}.log")
            if json.loads((cd / "manifest.json").read_text())["status"] != "CD_and_ABCD_complete_not_full_M1":
                raise RuntimeError(f"C/D manifest not complete: {eid}")
            output.mkdir(parents=True)
            invoke([sys.executable, str(SCRIPTS / "summarize_e06_hybrids.py"),
                    "--ab-root", str(ab), "--cd-root", str(cd),
                    "--experiment", eid, "--out-dir", str(output)],
                   scratch / f"e06_summary_{eid}_{stamp}.log")
            invoke([sys.executable, str(SCRIPTS / "summarize_e06_transmission.py"),
                    "--out-dir", str(output)],
                   scratch / f"e06_transmission_{eid}_{stamp}.log")
            receipt["runs"].append(dict(experiment_id=eid, ab_root=str(ab),
                                        cd_root=str(cd), output_dir=str(output)))
            receipt_path.write_text(json.dumps(receipt, indent=2) + "\n")
            print(f"E06_GRID_DONE {eid}", flush=True)
        receipt["status"] = "complete"
    except BaseException as exc:
        receipt["status"] = "failed"
        receipt["error"] = repr(exc)
        raise
    finally:
        receipt_path.write_text(json.dumps(receipt, indent=2) + "\n")


if __name__ == "__main__":
    main()
