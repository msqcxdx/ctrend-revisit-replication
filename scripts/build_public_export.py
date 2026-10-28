#!/usr/bin/env python3
"""Copy the audited, code-only subset of a controlled CTREND source tree.

This deliberately starts a new Git history. It never copies raw/vendor inputs,
private run trees, detailed asset holdings, or the original project's Git data.
The resulting scientific code still needs separately licensed inputs and helper
functions before a full MATLAB run is possible.
"""

from __future__ import annotations

import argparse
import csv
import hashlib
import subprocess
from pathlib import Path

EXPECTED_SOURCE_COMMIT = "58c8bad72d318eb7f17610084cc826bfbbbe9511"
SOURCE_DIRS = ("config", "engines", "environment", "p0_extension", "postprocessing", "scripts", "tests")
SOURCE_ROOT_FILES = ("run_all.sh", "run_all.m", "run_all.bat", "reproduce_everything.sh")
ANALYSIS_SUFFIXES = (".m", ".py")
SUMMARY_FILES = (
    "results/comparisons/source_tables/NINETEEN_WAY_HEADLINE.csv",
    "results/comparisons/source_tables/NINETEEN_WAY_HEADLINE_LONG.csv",
    "results/comparisons/source_tables/EIGHTEEN_EXPERIMENT_ALL_TABLE_CELLS.csv",
    "results/comparisons/source_tables/EIGHTEEN_EXPERIMENT_FIGURE_INVENTORY.csv",
    "results/comparisons/source_tables/PAPER_ITEM_COVERAGE.csv",
    "results/comparisons/source_tables/RUN_IDENTITIES_18.csv",
    "results/comparisons/source_tables/OWN_SUPPORT_ABLATION_DECOMPOSITION.csv",
    "results/comparisons/source_tables/COMMON_WEEK_ABLATION_DECOMPOSITION.csv",
    "results/comparisons/paper_factor/PAPER_WEEKLY_RETURNS.csv",
    "results/comparisons/paper_factor/PAPER_FACTOR_PROVENANCE.json",
    "reference/dataverse_files.zip",
    "cmc_acquisition/bundle.py",
    "cmc_acquisition/requirements.txt",
    "data/RAW_INPUTS.sha256",
    "followup_research/published_results.py",
)
SKIP_NAMES = {".git", "__pycache__", ".pytest_cache", "regstats2.m", "parfor_wait.m"}
SKIP_SUFFIXES = {".mat", ".xlsx", ".xls", ".zip", ".gz", ".fig", ".png", ".jpg", ".pyc", ".pyo"}


def sha256(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as handle:
        for block in iter(lambda: handle.read(1024 * 1024), b""):
            h.update(block)
    return h.hexdigest()


def copy_one(source: Path, target: Path, relative: Path, ledger: list[tuple[str, str, str, int]]) -> None:
    src = source / relative
    dst = target / relative
    if src.is_symlink() or not src.is_file():
        raise ValueError(f"refusing non-regular source: {relative}")
    source_bytes = src.read_bytes()
    public_bytes = source_bytes
    if relative.as_posix() == "scripts/preflight.sh":
        old = rb"|61\.162\.193\.19"
        if source_bytes.count(old) != 1:
            raise ValueError("expected exactly one legacy host-pattern literal")
        public_bytes = source_bytes.replace(old, b"")
    public_digest = hashlib.sha256(public_bytes).hexdigest()
    if dst.exists():
        if public_digest != sha256(dst):
            raise ValueError(f"refusing to replace changed target: {relative}")
    else:
        dst.parent.mkdir(parents=True, exist_ok=True)
        dst.write_bytes(public_bytes)
    ledger.append((relative.as_posix(), sha256(src), public_digest, len(public_bytes)))


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source", type=Path, required=True)
    parser.add_argument("--target", type=Path, required=True)
    args = parser.parse_args()
    source, target = args.source.resolve(), args.target.resolve()
    commit = subprocess.check_output(["git", "-C", str(source), "rev-parse", "HEAD"], text=True).strip()
    if commit != EXPECTED_SOURCE_COMMIT:
        raise SystemExit(f"source commit is {commit}, expected {EXPECTED_SOURCE_COMMIT}")
    if subprocess.check_output(["git", "-C", str(source), "status", "--porcelain"], text=True).strip():
        raise SystemExit("controlled source worktree is dirty")
    if source == target or source in target.parents:
        raise SystemExit("target must be independent of the controlled source")

    relatives: set[Path] = set()
    for directory in SOURCE_DIRS:
        for path in (source / directory).rglob("*"):
            if any(part in SKIP_NAMES for part in path.relative_to(source).parts):
                continue
            if path.suffix.lower() in SKIP_SUFFIXES or not path.is_file():
                continue
            relatives.add(path.relative_to(source))
    for path in (source / "analysis").iterdir():
        if path.is_file() and path.suffix in ANALYSIS_SUFFIXES:
            relatives.add(path.relative_to(source))
    for path in (source / "followup_research" / "scripts").rglob("*"):
        if path.is_file() and path.suffix in ANALYSIS_SUFFIXES and "__pycache__" not in path.parts:
            relatives.add(path.relative_to(source))
    relatives.update(Path(item) for item in SOURCE_ROOT_FILES + SUMMARY_FILES)

    ledger: list[tuple[str, str, str, int]] = []
    for relative in sorted(relatives):
        copy_one(source, target, relative, ledger)
    output = target / "provenance" / "SOURCE_FILE_MAP.csv"
    output.parent.mkdir(parents=True, exist_ok=True)
    with output.open("w", newline="", encoding="utf-8") as handle:
        writer = csv.writer(handle)
        writer.writerow(("public_path", "controlled_source_sha256", "public_sha256", "public_size_bytes"))
        writer.writerows(ledger)
    print(f"PUBLIC_EXPORT_OK source_commit={commit} files={len(ledger)} ledger={output}")


if __name__ == "__main__":
    main()
