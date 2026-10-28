#!/usr/bin/env python3
"""Publish an isolated E05 replay receipt without altering its original run.

The MATLAB replay writes its immutable receipt inside the work root.  This
small publication step adds the root's absolute location so artifact
acceptance can rehash the generated checkpoints.  A scientific finding of
past sensitivity is retained verbatim; it is never rewritten to a pass.
"""

from __future__ import annotations

import argparse
from hashlib import sha256
import json
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
OUTPUT = ROOT / "outputs/E05/raw_to_baseline_future_terminal_receipt.json"


def digest(path: Path) -> str:
    h = sha256()
    with path.open("rb") as f:
        for block in iter(lambda: f.read(2**20), b""):
            h.update(block)
    return h.hexdigest()


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--work-root", type=Path, required=True)
    args = parser.parse_args()
    work = args.work_root.resolve(strict=True)
    original = work / "receipt.json"
    record = json.loads(original.read_text())
    if record["status"] in ("failed", "running"):
        raise RuntimeError(f"Do not publish unfinished E05 replay: {record['status']}")
    for variant in ("control", "future_terminal"):
        if variant not in record:
            raise ValueError(f"Missing E05 replay variant: {variant}")
        result = work / variant / "source/Results/CTREND/CTREND_Base.mat"
        if digest(result) != record[variant]["result_sha256"]:
            raise ValueError(f"Result identity differs: {variant}")
    record["work_root"] = str(work)
    record["source_receipt_sha256"] = digest(original)
    if OUTPUT.exists():
        raise FileExistsError(OUTPUT)
    OUTPUT.write_text(json.dumps(record, indent=2) + "\n")
    print(f"E05_RAW_CHAIN_RECEIPT_PUBLISHED status={record['status']}")


if __name__ == "__main__":
    main()
