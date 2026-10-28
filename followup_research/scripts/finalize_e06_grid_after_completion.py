#!/usr/bin/env python3
"""Wait for the isolated E06 grid, then summarize and validate E01--E11.

This is a follow-up-study postprocessor, not a production-pipeline runner.
It never edits an accepted parent experiment and never treats a failed or
incomplete grid as a success.  Each command and its return code are logged.
"""

from __future__ import annotations

import argparse
from datetime import datetime, timezone
from hashlib import sha256
import json
import os
from pathlib import Path
import subprocess
import sys
import time


ROOT = Path(__file__).resolve().parents[1]
SCRIPTS = ROOT / "scripts"


def digest(path: Path) -> str:
    h = sha256()
    with path.open("rb") as f:
        for block in iter(lambda: f.read(2**20), b""):
            h.update(block)
    return h.hexdigest()


def utcnow() -> str:
    return datetime.now(timezone.utc).isoformat()


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--grid-receipt", type=Path, required=True)
    parser.add_argument("--status-file", type=Path, required=True)
    parser.add_argument("--poll-seconds", type=int, default=30)
    parser.add_argument("--timeout-seconds", type=int, default=6*3600)
    args = parser.parse_args()
    receipt = args.grid_receipt.resolve(strict=True)
    status = args.status_file.resolve()
    if status.exists() or not 1 <= args.poll_seconds <= 60:
        raise ValueError("Fresh status path and a 1..60 second polling interval required")
    if args.timeout_seconds < args.poll_seconds:
        raise ValueError("Timeout shorter than poll interval")
    work = status.parent
    work.mkdir(parents=True, exist_ok=True)
    record = {"scope": "isolated_E06_grid_postprocess_then_followup_artifact_acceptance",
              "started_utc": utcnow(), "grid_receipt": str(receipt),
              "status": "waiting", "commands": []}
    start = time.monotonic()
    try:
        while True:
            grid = json.loads(receipt.read_text())
            if grid["status"] == "failed":
                raise RuntimeError(f"Grid itself failed: {grid.get('error')}")
            if grid["status"] == "complete":
                break
            if grid["status"] != "running":
                raise RuntimeError(f"Unknown grid state: {grid['status']}")
            if time.monotonic()-start > args.timeout_seconds:
                raise TimeoutError("E06 grid did not finish within the declared wait")
            time.sleep(args.poll_seconds)
        record["grid_receipt_sha256"] = digest(receipt)
        record["status"] = "postprocessing"
        status.write_text(json.dumps(record, indent=2)+"\n")
        env = {**os.environ, "OPENBLAS_NUM_THREADS": "1"}
        for name in ("summarize_e06_sensitivity_grid.py",
                     "trace_e06_innbcl_key_week.py",
                     "validate_followup_artifacts.py",
                     "test_followup_documentation.py"):
            log = work / ("finalize_"+name+".log")
            with log.open("w") as stream:
                rc = subprocess.run([sys.executable, str(SCRIPTS/name)],
                                    cwd=ROOT.parent, env=env,
                                    stdout=stream, stderr=subprocess.STDOUT).returncode
            record["commands"].append({"script": name, "rc": rc,
                                       "log": str(log), "log_sha256": digest(log)})
            status.write_text(json.dumps(record, indent=2)+"\n")
            if rc:
                raise RuntimeError(f"Follow-up postprocess failed: {name}; log={log}")
        record["status"] = "complete"
        record["completed_utc"] = utcnow()
    except BaseException as exc:
        record["status"] = "failed"
        record["error"] = repr(exc)
        record["stopped_utc"] = utcnow()
        raise
    finally:
        status.write_text(json.dumps(record, indent=2)+"\n")
    print("E06_GRID_AND_FOLLOWUP_ACCEPTANCE_OK", flush=True)


if __name__ == "__main__":
    main()
