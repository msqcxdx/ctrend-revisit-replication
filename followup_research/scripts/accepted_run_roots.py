#!/usr/bin/env python3
# CTREND_REVISIT_FILE_PURPOSE: Resolve accepted full-run inputs from the portable, hash-bound run index.
"""Use a locally regenerated E11 run index, never a developer's host path."""

import csv
from hashlib import sha256
from pathlib import Path


INDEX = Path(__file__).resolve().parents[1] / "outputs/E11/accepted_run_paths.csv"


def digest(path: Path) -> str:
    value = sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            value.update(chunk)
    return value.hexdigest()


def accepted_roots(experiments: tuple[str, ...],
                   index_path: Path = INDEX) -> dict[str, Path]:
    """Resolve and verify the requested complete runs before scientific reads."""
    with index_path.open(newline="", encoding="utf-8") as stream:
        rows = {row["experiment_id"]: row for row in csv.DictReader(stream)}
    if not set(experiments).issubset(rows):
        raise ValueError("Accepted-run index does not cover requested experiments")
    roots = {}
    for experiment in experiments:
        row = rows[experiment]
        root = Path(row["accepted_run_root"]).resolve()
        if digest(root / "RUN_COMPLETE") != row["run_complete_sha256"]:
            raise ValueError(f"Accepted-run completion identity mismatch: {experiment}")
        results = Path(row["result_root"]).resolve()
        if not results.is_dir() or not results.is_relative_to(root):
            raise ValueError(f"Accepted result root is outside its run: {experiment}")
        roots[experiment] = root
    return roots
