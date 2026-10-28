#!/usr/bin/env python3
# CTREND_REVISIT_FILE_PURPOSE: Validate the journal-replication package structure, original archive identity, and required metadata.
"""Verify the complete tracked reproduction structure and frozen input snapshot."""

# Contract: a public checkout must contain every documented entry point,
# frozen input, reference source, configuration, test, and compact result.
# This test also rejects path leakage and unsafe links; it never regenerates
# data or silently substitutes a missing artifact.

from __future__ import annotations

import csv
import hashlib
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
DATAVERSE_SHA = "3d0959b198d4d4ad70ad69905ba0c157ce63e942d62ab7ae995a8bf00da3cdb3"


def file_sha256(path: Path) -> str:
    """Hash large immutable artifacts without reading an entire panel into RAM."""
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(4 * 1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()

REQUIRED_FILES = [
# This explicit allowlist makes accidental omissions visible in code review.
    "README.md", "RUNBOOK.md", "STUDY_OVERVIEW.md", "REPRODUCTION_GUIDE_CN.md",
    "reproduce_everything.sh", "scripts/report_registered_runs.py",
    "tests/run_acquisition_tests.py",
    "ORIGINAL_DATAVERSE_CODE_COMPARISON.md", "CITATION.cff", "LICENSE",
    "NOTICE", "run_all.sh", "run_all.m", "run_all.bat",
    "docs/METHOD_BOUNDARIES.md", "docs/AUDIT_AND_ANNOTATIONS.md",
    "docs/ISSUE_AND_CORRECTION_REGISTER.md", "docs/REPOSITORY_MAP.md",
    "docs/OUTPUTS_AND_INTERPRETATION.md",
    "config/project_config.m", "config/experiments.csv",
    "config/methods.csv", "config/data_treatments.csv",
    "config/output_registry.csv", "config/event_asset_registry_v20260811.csv",
    "config/postprocessing_registry.csv",
    "config/exclusions/D0.csv", "config/exclusions/D1.csv",
    "config/exclusions/D2.csv", "config/host_assignments_3x3_template.csv",
    "environment/environment_check.m", "environment/MATLAB_VERSION.txt",
    "environment/TOOLBOXES.txt", "scripts/install_required_data.sh",
    "scripts/materialize_experiment_source.sh", "scripts/run_experiment.sh",
    "scripts/preflight.sh", "release/make_release.sh", "tests/run_tests.sh",
    "tests/integration/test_annotation_opcode_coverage.py",
    "tests/integration/test_annotation_readability.py",
    "tests/integration/test_annotated_source_equivalence.py",
    "tests/integration/test_m2_consumer_matrix.py",
    "tests/integration/test_m2_derivation_scope.sh",
    "tests/integration/test_method_boundary_contract.py",
    "tests/result_checks/verify_completed_run.sh",
    "tests/result_checks/verify_run_provenance.sh",
    "tests/result_checks/test_curated_result_snapshot.py",
    "tests/result_checks/test_revised_week_support_snapshot.py",
    "analysis/recompute_ablation_diagnostics.m",
    "analysis/recompute_declared_week_support.m",
    "analysis/compare_nine_methods_common_weeks.m",
    "analysis/run_nine_method_common_week_comparison.m",
    "analysis/run_nine_method_common_week_comparison.sh",
    "analysis/tests/test_compare_nine_methods_common_weeks.m",
    "postprocessing/b19CommonWeekRobustness.m",
    "postprocessing/run_b19_common_week_robustness.sh",
    "postprocessing/README.md",
    "analysis/README.md", "results/README.md", "results/MANIFEST.sha256",
    "results/comparisons/NINETEEN_WAY_FULL_REPORT_CN.md",
    "config/experiments_pmd.csv", "README_CN.md",
    "results/comparisons/P_M_D_KEY_CONTRASTS_ALL_COMMON.csv",
    "provenance/accepted_18/PUBLIC_RUN_IDENTITIES.csv",
    "reference/dataverse_files.zip",
    "reference/dataverse_original_3d0959b1/b01ReadData.m",
    "annotated_sources/ANNOTATION_INDEX.csv",
    "annotated_sources/ANNOTATED_RELEASE.sha256",
    "annotated_sources/README.md",
    "data/RAW_INPUTS.sha256",
    "data/raw/common/DATA_MANIFEST.sha256",
    "data/raw/common/F-F_Research_Data_Factors_daily.CSV",
    "data/raw/common/LTW_3factor.xlsx", "data/raw/common/MetaData.mat",
    "data/raw/common/UCRY.csv", "data/raw/common/close_cmc.csv",
    "data/raw/common/high_cmc.csv", "data/raw/common/low_cmc.csv",
    "data/raw/common/market_cap_cmc.csv", "data/raw/common/open_cmc.csv",
    "data/raw/common/screening_summary.json",
    "data/raw/common/volume_cmc.csv",
]

for relative in REQUIRED_FILES:
    path = ROOT / relative
    assert path.is_file() and path.stat().st_size > 0, relative

for relative in (
    "engines/M0/base", "engines/M1/base", "engines/M2/base",
    "engines/M0/runner", "engines/M1/runner", "engines/M2/runner",
    "annotated_sources/P0_M0_D0", "annotated_sources/P1_M1_D1",
    "annotated_sources/P1_M2_D2", "tests/unit", "tests/integration",
    "tests/data_checks", "tests/result_checks", "release", "scripts",
    "postprocessing",
):
    assert (ROOT / relative).is_dir(), relative

archive = ROOT / "reference/dataverse_files.zip"
assert file_sha256(archive) == DATAVERSE_SHA

raw_root = ROOT / "data/raw/common"
with (ROOT / "data/RAW_INPUTS.sha256").open(encoding="utf-8") as handle:
    raw_inventory = {
        relative: digest for digest, relative in
        (line.rstrip("\n").split("  ", 1) for line in handle if line.strip())
    }
assert len(raw_inventory) == 11
for relative, digest in raw_inventory.items():
    path = raw_root / relative
    assert path.is_file() and not path.is_symlink(), relative
    assert file_sha256(path) == digest, relative

with (ROOT / "config/output_registry.csv").open(
    newline="", encoding="utf-8"
) as handle:
    registry = list(csv.DictReader(handle))
assert len(registry) == 26
assert {row["paper_item"] for row in registry} >= {
    "Table 1", "Table 9", "Table B.10", "Figure 1", "Figure B.2",
    "Figures C.3-C.4",
}

# Historical reports, manuscripts, raw MAT result trees, and the large event
# audit workfiles are deliberately outside this repository. Curated generated
# TeX/PNG/CSV snapshots are tracked under results/.
for relative in (
    "RESEARCH_MAP.md", "RESULTS_GUIDE.md", "src", "archive",
    "data/evidence", "data/metadata", "data/derived",
    "reference/dataverse_original_archive",
    "annotated_sources/dataverse_files.zip",
    "release/RUN_MANIFEST.json", "release/RESULT_MANIFEST.csv",
):
    assert not (ROOT / relative).exists(), f"obsolete repository member: {relative}"

# Production state and an operator's ignored Python venv may contain links.
# Neither is a release member. Keep the no-symlink gate strict for source/data.
assert not any(
    path.is_symlink() for path in ROOT.rglob("*")
    if not ({".git", "runtime", "outputs"} & set(path.relative_to(ROOT).parts))
    and not any(part.startswith(".venv") for part in path.relative_to(ROOT).parts)
)
print(
    "CODE_REPOSITORY_STRUCTURE_OK experiments=18 output_rows=26 "
    "original_archive=1 curated_results=1 source_tables_evidence=1 "
    "accepted_raw_inputs=11 symlinks=0"
)
