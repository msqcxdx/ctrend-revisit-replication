#!/usr/bin/env python3
"""Check public source and saved summaries without estimating any model."""

import argparse
import csv
import hashlib
import json
import math
import re
import statistics
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def rows(relative: str) -> list[dict[str, str]]:
    with (ROOT / relative).open(newline="", encoding="utf-8") as stream:
        return list(csv.DictReader(stream))


def digest(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            h.update(block)
    return h.hexdigest()


def check_manifest(installed_inputs: bool = False) -> None:
    manifest = ROOT / "provenance/PUBLIC_SHA256SUMS"
    lines = manifest.read_text(encoding="utf-8").splitlines()
    assert lines and len(lines) == len(set(lines)), "duplicate/empty public manifest"
    for line in lines:
        expected, relative = line.split("  ", 1)
        if installed_inputs and relative == "data/RAW_INPUTS.sha256":
            # Lawful installation writes a local manifest for the actual
            # vendor snapshot; data_bundle.py checks that snapshot separately.
            continue
        path = ROOT / relative
        assert path.is_file() and not path.is_symlink(), relative
        assert digest(path) == expected, f"changed public file: {relative}"
    assert all("data/raw/common" not in line for line in lines)
    listed = {line.split("  ", 1)[1] for line in lines}
    excluded = {".git", "outputs", "runtime", "__pycache__", ".pytest_cache", ".venv"}
    actual = {path.relative_to(ROOT).as_posix() for path in ROOT.rglob("*")
              if path.is_file() and not excluded.intersection(path.relative_to(ROOT).parts)
              and path.relative_to(ROOT).parts[:2] != ("data", "raw")
              and path != manifest}
    assert listed == actual, f"public manifest coverage mismatch missing={sorted(actual-listed)} extra={sorted(listed-actual)}"


def check_source_ledger(installed_inputs: bool = False) -> None:
    source = rows("provenance/SOURCE_FILE_MAP.csv")
    assert len(source) > 600
    assert len(source) == len({item["public_path"] for item in source})
    for item in source:
        if installed_inputs and item["public_path"] == "data/RAW_INPUTS.sha256":
            continue
        path = ROOT / item["public_path"]
        assert digest(path) == item["public_sha256"]
        assert path.stat().st_size == int(item["public_size_bytes"])
    if not installed_inputs:
        assert not list(ROOT.rglob("regstats2.m"))
        assert not list(ROOT.rglob("parfor_wait.m"))
        assert not (ROOT / "data/raw/common").exists()


def check_public_results() -> None:
    registry = rows("config/experiments_pmd.csv")
    expected_ids = {f"P{p}_M{m}_D{d}" for p in range(2) for m in range(3) for d in range(3)}
    assert {row["experiment_id"] for row in registry} == expected_ids
    accepted = rows("results/comparisons/source_tables/RUN_IDENTITIES_18.csv")
    assert {row["experiment_id"] for row in accepted} == expected_ids
    assert all(row["acceptance_status"] == "PASS" and int(row["combo_mat_count"]) == 3072 for row in accepted)

    headline = rows("results/comparisons/source_tables/NINETEEN_WAY_HEADLINE.csv")
    long = rows("results/comparisons/source_tables/NINETEEN_WAY_HEADLINE_LONG.csv")
    assert {row["metric"] for row in headline} == {row["metric"] for row in long}
    long_map = {(row["metric"], row["series"]): row["value"] for row in long}
    for row in headline:
        for series in ("paper", *sorted(expected_ids)):
            assert row[series] == long_map[(row["metric"], series)]

    coverage = rows("results/comparisons/source_tables/PAPER_ITEM_COVERAGE.csv")
    mapping = rows("TABLE_FIGURE_MAP.csv")
    assert len(coverage) == len(mapping) == 26
    assert {row["paper_item"] for row in coverage} == {row["paper_item"] for row in mapping}
    assert all((ROOT / row["public_evidence"]).is_file() for row in mapping)
    assert len([row for row in mapping if row["paper_item"].startswith("Figure")]) == 7
    print("PUBLIC_SUMMARY_OK experiments=18 paper_items=26")


def check_author_factor() -> None:
    provenance = json.loads((ROOT / "results/comparisons/paper_factor/PAPER_FACTOR_PROVENANCE.json").read_text(encoding="utf-8"))
    with zipfile.ZipFile(ROOT / "reference/dataverse_files.zip") as archive:
        workbook = archive.read(provenance["workbook_member"])
    assert hashlib.sha256(workbook).hexdigest() == provenance["workbook_sha256"]
    series = [float(row["paper_hl_return"]) for row in rows("results/comparisons/paper_factor/PAPER_WEEKLY_RETURNS.csv") if row["paper_hl_return"]]
    n = len(series)
    mean, std = statistics.mean(series), statistics.stdev(series)
    observed = (n, mean * 100, std * 100, mean / std * math.sqrt(n), mean / std * math.sqrt(52))
    expected = (
        provenance["full_support"]["weeks"],
        provenance["full_support"]["mean_weekly_pct"],
        provenance["full_support"]["std_weekly_pct"],
        provenance["full_support"]["t"],
        provenance["full_support"]["sharpe_annualized"],
    )
    assert all(math.isclose(a, b, rel_tol=1e-12, abs_tol=1e-12) for a, b in zip(observed, expected))
    print(f"AUTHOR_FACTOR_OK weeks={n} mean_pct={mean*100:.6f} t={observed[3]:.6f} sharpe={observed[4]:.6f}")


def check_rights() -> None:
    ledger = rows("THIRD_PARTY_MATERIALS.csv")
    assert len(ledger) >= 10
    assert any("CMC OHLCV" in row["category"] and "exclude" in row["public_action"] for row in ledger)
    assert any("Dataverse" in row["acquisition_route"] and "CC0" in row["redistribution_decision"] for row in ledger)
    print(f"PUBLIC_RIGHTS_LEDGER_OK classes={len(ledger)}")


def check_public_hygiene() -> None:
    for relative in ("run_all.sh", "reproduce_everything.sh", "reproduce_tables.sh",
                     "scripts/preflight.sh", "tests/run_tests.sh"):
        assert (ROOT / relative).stat().st_mode & 0o111, f"entry point lacks execute permission: {relative}"
    assert (ROOT / "engines/M1/base/DesignChoices.mat").stat().st_size > 0, "M1 design configuration missing"
    sensitive = (
        re.compile(rb"/home/[A-Za-z0-9_-]+/"),
        re.compile(rb"/(?:data[0-9]+|mnt)/[A-Za-z0-9_-]+/"),
        re.compile(rb"(?<![0-9])(?:[0-9]{1,3}\.){3}[0-9]{1,3}(?![0-9])"),
        re.compile(rb"ghp_[A-Za-z0-9]{20,}"),
        re.compile(rb"-----BEGIN (?:RSA |OPENSSH |EC |DSA )?PRIVATE KEY-----"),
    )
    for path in ROOT.rglob("*"):
        if not path.is_file() or path.suffix.lower() not in {".sh", ".py", ".md", ".txt", ".csv", ".json", ".yml", ".cff"}:
            continue
        if {".git", "outputs", "runtime", "__pycache__"}.intersection(path.relative_to(ROOT).parts):
            continue
        if path.relative_to(ROOT).parts[:2] == ("data", "raw"):
            continue
        if any(pattern.search(path.read_bytes()) for pattern in sensitive):
            raise AssertionError(f"public text has a sensitive path/address/key shape: {path.relative_to(ROOT)}")
    print("PUBLIC_HYGIENE_OK executable_entries=5 current_text_sensitive_shapes=0")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--installed-inputs", action="store_true",
                        help="Allow only the local raw-input inventory to differ; the data gate must run separately")
    args = parser.parse_args()
    check_manifest(args.installed_inputs)
    check_source_ledger(args.installed_inputs)
    check_public_results()
    check_author_factor()
    check_rights()
    check_public_hygiene()
    print("PUBLIC_QUICKCHECK_OK scope=export_integrity_and_saved_summaries_not_full_matlab"
          f" installed_inputs_mode={int(args.installed_inputs)}")


if __name__ == "__main__":
    main()
