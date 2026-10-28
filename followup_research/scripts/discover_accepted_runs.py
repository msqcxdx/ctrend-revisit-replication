#!/usr/bin/env python3
"""Bind local complete-run directories to the public accepted-run index.

The search root is supplied by the operator; no machine-specific path is
embedded in the script.  Hashes are checked before any follow-up analysis.
"""

from __future__ import annotations

import argparse
import csv
from hashlib import sha256
from pathlib import Path
import subprocess


REPO = Path(__file__).resolve().parents[2]
OUT = Path(__file__).resolve().parents[1] / "outputs" / "E11" / "accepted_run_paths.csv"


def digest(path: Path) -> str:
    h = sha256()
    with path.open("rb") as f:
        for chunk in iter(lambda: f.read(1024 * 1024), b""):
            h.update(chunk)
    return h.hexdigest()


def env(path: Path) -> dict[str, str]:
    out = {}
    for line in path.read_text(encoding="utf-8").splitlines():
        if "=" in line:
            k, v = line.split("=", 1)
            out[k] = v
    return out


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("search_root", type=Path)
    args = parser.parse_args()
    index = list(csv.DictReader((REPO / "provenance" / "accepted_18" /
                                "PUBLIC_RUN_IDENTITIES.csv").open()))
    ids = {r["research_run_id"]: r for r in index}
    result = subprocess.run(["find", str(args.search_root), "-maxdepth", "9",
                             "-type", "f", "-name", "RUN_COMPLETE"],
                            capture_output=True, text=True, check=True)
    matches = {}
    for entry in result.stdout.splitlines():
        path = Path(entry)
        marker = env(path)
        run_id = marker.get("research_run_id")
        if run_id not in ids:
            continue
        root = path.parent
        data = root / "results"
        if not (data / "CTREND" / "CTREND_Combo1.mat").is_file():
            data = root / "results.staging"
        # Metadata-only mirrors carry the same completion marker but no data.
        if not (data / "CTREND" / "CTREND_Combo1.mat").is_file():
            continue
        expected = ids[run_id]
        if digest(path) != expected["run_complete_sha256"]:
            raise RuntimeError(f"RUN_COMPLETE hash mismatch: {path}")
        eid = expected["experiment_id"]
        if eid in matches:
            raise RuntimeError(f"Multiple accepted roots for {eid}")
        inv = root / expected["inventory_file"]
        if digest(inv) != expected["inventory_sha256"]:
            raise RuntimeError(f"Result inventory hash mismatch for {eid}")
        matches[eid] = dict(experiment_id=eid, research_run_id=run_id,
                            accepted_run_root=str(root), result_root=str(data),
                            run_complete_sha256=expected["run_complete_sha256"],
                            inventory_sha256=expected["inventory_sha256"])
    if set(matches) != {r["experiment_id"] for r in index}:
        raise RuntimeError(f"Accepted root coverage incomplete: {sorted(matches)}")
    OUT.parent.mkdir(parents=True, exist_ok=True)
    with OUT.open("w", newline="", encoding="utf-8") as f:
        writer = csv.DictWriter(f, fieldnames=list(next(iter(matches.values()))))
        writer.writeheader()
        writer.writerows(matches[k] for k in sorted(matches))
    print(f"FOLLOWUP_ACCEPTED_ROOTS_OK count={len(matches)} path={OUT}")


if __name__ == "__main__":
    main()
