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
import re
import subprocess
import sys
from pathlib import Path

EXPECTED_SOURCE_COMMIT = "7bdad8d53b622cb97850fc6710cc67bf48b32c57"
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
    "results/comparisons/source_tables/CURATED_PAPER_BENCHMARKS.csv",
    "reference/dataverse_files.zip",
    "cmc_acquisition/bundle.py",
    "cmc_acquisition/requirements.txt",
    "data/RAW_INPUTS.sha256",
    "followup_research/published_results.py",
    "docs/METHOD_BOUNDARIES.md",
    "analysis/tests/test_compare_nine_methods_common_weeks.m",
    "engines/M1/base/DesignChoices.mat",
)
# The export applies the published project namespace consistently while
# retaining a byte-level source/public mapping for the controlled archive.
OLD_NAMESPACE = "ct" + "trend"
NEW_NAMESPACE = "ctrend"
OBSOLETE_ARCHIVE_LIST = OLD_NAMESPACE + "_package_sha256sums.txt"
SKIP_NAMES = {
    ".git", "__pycache__", ".pytest_cache", "regstats2.m", "parfor_wait.m",
    OBSOLETE_ARCHIVE_LIST,
}
SKIP_SUFFIXES = {".mat", ".xlsx", ".xls", ".zip", ".gz", ".fig", ".png", ".jpg", ".pyc", ".pyo"}
PUBLIC_OVERRIDES = {
    Path("scripts/preflight.sh"),
    Path("tests/run_tests.sh"),
    Path("tests/README.md"),
    Path("postprocessing/README.md"),
}
PUBLIC_ROOT_FILES = (
    ".gitignore", "CITATION.cff", "DATA_AVAILABILITY.md", "KNOWN_LIMITATIONS.md",
    "LICENSE", "NOTICE", "PAPER_REPLICATION.md", "PUBLIC_EXPORT_DECISIONS.md",
    "QUICKSTART.md", "README.md", "README_CN.md", "SECURITY_REVIEW.md",
    "TABLE_FIGURE_MAP.csv", "THIRD_PARTY_MATERIALS.csv", "reproduce_tables.sh",
)
PUBLIC_DIR_FILES = (
    ".github/workflows/public-check.yml",
    "docs/PUBLIC_VALIDATION.md",
    "scripts/audit_controlled_history.py", "scripts/build_public_export.py",
    "scripts/build_table_figure_map.py",
    "scripts/make_public_manifest.py", "scripts/public_quickcheck.py",
    "scripts/reproduce_public_tables.py", "tests/public_test_bundle.py",
    "tests/public_test_installed_inputs.py",
    "tests/public_test_tables.py",
)


def sha256(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as handle:
        for block in iter(lambda: handle.read(1024 * 1024), b""):
            h.update(block)
    return h.hexdigest()


def public_spelling(data: bytes, relative: Path) -> bytes:
    """Change our namespace spelling, leaving the original ZIP/MAT intact."""
    if relative.suffix.lower() in {".zip", ".mat"}:
        return data
    return (data.replace(OLD_NAMESPACE.upper().encode(), NEW_NAMESPACE.upper().encode())
                .replace(OLD_NAMESPACE.encode(), NEW_NAMESPACE.encode()))


def copy_one(source: Path, target: Path, relative: Path, ledger: list[tuple[str, str, str, int]]) -> None:
    src = source / relative
    dst = target / relative
    if src.is_symlink() or not src.is_file():
        raise ValueError(f"refusing non-regular source: {relative}")
    source_bytes = src.read_bytes()
    public_bytes = public_spelling(source_bytes, relative)
    if relative.as_posix() == "scripts/preflight.sh":
        # The controlled scanner once embedded an internal host address. The
        # public override replaces the whole preflight; never copy that literal.
        if not re.search(rb"\|(?:[0-9]{1,3}\\\.){3}[0-9]{1,3}", source_bytes):
            raise ValueError("expected controlled preflight host-pattern literal")
    if relative in PUBLIC_OVERRIDES:
        overlay = Path(__file__).resolve().parents[1] / "public_overrides" / relative
        if not overlay.is_file():
            raise ValueError(f"missing public override: {relative}")
        public_bytes = public_spelling(overlay.read_bytes(), relative)
    public_digest = hashlib.sha256(public_bytes).hexdigest()
    if dst.exists():
        if public_digest != sha256(dst):
            previous = target / "provenance/SOURCE_FILE_MAP.csv"
            previously_exported = set()
            if previous.is_file():
                with previous.open(newline="", encoding="utf-8") as handle:
                    previously_exported = {
                        row["public_sha256"] for row in csv.DictReader(handle)
                        if row["public_path"] == relative.as_posix()
                    }
            if sha256(dst) not in previously_exported | {sha256(src)}:
                raise ValueError(f"refusing to replace changed target: {relative}")
            dst.write_bytes(public_bytes)
    else:
        dst.parent.mkdir(parents=True, exist_ok=True)
        dst.write_bytes(public_bytes)
    # A fresh export must preserve executable entry points. Without this,
    # './run_all.sh' fails before even entering the documented preflight.
    dst.chmod(src.stat().st_mode & 0o777)
    ledger.append((relative.as_posix(), sha256(src), public_digest, len(public_bytes)))


def refresh_base_inventories(source: Path, target: Path,
                             ledger: list[tuple[str, str, str, int]]) -> None:
    """Match the distributed base-file hashes to their renamed public bytes."""
    for variant in ("M0", "M2", "P0_M0"):
        relative = Path("engines") / variant / "base" / "PACKAGE_FILES.sha256"
        src = source / relative
        dst = target / relative
        base = dst.parent
        rows = []
        for line in src.read_text(encoding="utf-8").splitlines():
            old_digest, old_path = line.split("  ", 1)
            if old_path == OBSOLETE_ARCHIVE_LIST:
                continue
            new_path = public_spelling(old_path.encode(), Path(old_path)).decode()
            public_file = base / new_path
            if public_file.is_file():
                digest = sha256(public_file)
            elif new_path in {"Utils/regstats2.m", "Utils/parfor_wait.m"}:
                # These two exact third-party copies are withheld. Their
                # published checksums still identify the required helpers.
                digest = old_digest
            else:
                raise ValueError(f"missing inventoried base file: {relative} -> {new_path}")
            rows.append(f"{digest}  {new_path}")
        dst.write_text("\n".join(rows) + "\n", encoding="utf-8")
        for index, row in enumerate(ledger):
            if row[0] == relative.as_posix():
                ledger[index] = (row[0], row[1], sha256(dst), dst.stat().st_size)
                break
        else:
            raise ValueError(f"base inventory not exported: {relative}")


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
            # The public export has one complete root inventory, not separate
            # top-level extension inventories.
            if path.parent == source / "p0_extension" and path.suffix.lower() == ".sha256":
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
    # Export only the direct-comparison source, guides and aggregate tables.
    # Isolated NPZ inputs, parent paths and all raw factor/test-asset panels
    # remain private, even if another file type is added there later.
    direct = source / "followup_research/model_advantage_direct"
    for path in direct.iterdir():
        if path.is_file() and path.suffix in {".py", ".md"}:
            relatives.add(path.relative_to(source))
    for path in (direct / "results").iterdir():
        if path.is_file() and path.suffix in {".csv", ".json"}:
            relatives.add(path.relative_to(source))
    relatives.update(Path(item) for item in SOURCE_ROOT_FILES + SUMMARY_FILES)

    ledger: list[tuple[str, str, str, int]] = []
    for relative in sorted(relatives):
        copy_one(source, target, relative, ledger)
    refresh_base_inventories(source, target, ledger)
    output = target / "provenance" / "SOURCE_FILE_MAP.csv"
    output.parent.mkdir(parents=True, exist_ok=True)
    with output.open("w", newline="", encoding="utf-8") as handle:
        writer = csv.writer(handle, lineterminator="\n")
        writer.writerow(("public_path", "controlled_source_sha256", "public_sha256", "public_size_bytes"))
        writer.writerows(ledger)
    # Public-owned guides and adapters live beside this builder, not in the
    # controlled scientific commit. Include them in a clean export verbatim.
    public_root = Path(__file__).resolve().parents[1]
    owned = [Path(name) for name in PUBLIC_ROOT_FILES + PUBLIC_DIR_FILES]
    owned.extend(path.relative_to(public_root) for path in (public_root / "public_overrides").rglob("*") if path.is_file())
    for relative in sorted(set(owned)):
        src = public_root / relative
        dst = target / relative
        if src.is_symlink() or not src.is_file():
            raise ValueError(f"refusing non-regular public file: {relative}")
        if dst.exists():
            if sha256(src) != sha256(dst):
                raise ValueError(f"refusing to replace changed public-owned target: {relative}")
        else:
            dst.parent.mkdir(parents=True, exist_ok=True)
            dst.write_bytes(src.read_bytes())
        dst.chmod(src.stat().st_mode & 0o777)
    subprocess.run([sys.executable, str(target / "scripts/make_public_manifest.py")], check=True)
    print(f"PUBLIC_EXPORT_OK source_commit={commit} copied={len(ledger)} public_owned={len(owned)} ledger={output}")


if __name__ == "__main__":
    main()
