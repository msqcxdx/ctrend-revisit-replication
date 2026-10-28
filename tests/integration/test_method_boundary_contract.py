#!/usr/bin/env python3
# CTREND_REVISIT_FILE_PURPOSE: Fail closed when M0, M1, or M2 escapes its declared scientific-change boundary.
"""Fail closed when M0/M1/M2 escape their declared scientific boundaries."""

# The allowlists below are the executable definition of the ablation: M0 may
# contain runability/bit-exact engineering only, M2 may add direct look-ahead
# repairs, and M1 may add the full audited corrections.  File additions or
# byte changes outside the declared sets require explicit review.

from __future__ import annotations

import csv
import hashlib
from pathlib import Path


TEXT_SUFFIXES = {".m", ".sh", ".py", ".bat"}
DATAVERSE_SHA256 = "3d0959b198d4d4ad70ad69905ba0c157ce63e942d62ab7ae995a8bf00da3cdb3"

M0_ALLOWED_DELTAS = {
    "LatexTables/fCreateLatexTable.m": "reporting-engineering",
    "Utils/fComputeOldFeaturesParallel.m": "bit-exact-parallel-engineering",
    "Utils/parfor_wait.m": "missing-runtime-dependency",
    "Utils/regstats2.m": "missing-runtime-dependency",
    "b00SelectBaselineOnlyForOldRun.m": "supplementary-run-engineering",
    "Utils/fApplyUnifiedMissingDataPreprocessing.m":
        "shared-missing-data-preprocessing",
    "Utils/fBuildAndFreezeMechanicalExitCalendar.m":
        "shared-exit-calendar-provenance",
    "Utils/fFileSHA256.m": "provenance-engineering",
    "b01ReadData.m": "shared-input-preprocessing-and-portability",
    "b02CalculateIndicators.m": "shared-volume-rule-and-parallel-engineering",
    "b03Table1_ResearchSample.m": "reporting-engineering",
    "b09RunResearchDesigns.m": "bit-exact-sharding-engineering",
    "b10Table6_FactorPerformanceAcrossResearchDesignChoices.m":
        "necessary-runability-repair",
    "b12Table7_FrontierExpansionTest.m": "necessary-runability-repair",
    "fSaveOpenFigures.m": "headless-publication-engineering",
    "run_full_pipeline_old.sh": "pipeline-orchestration-engineering",
    "run_safety.sh": "process-safety-engineering",
    "run_supplementary_outputs.sh": "supplementary-publication-engineering",
}


def digest(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def text_files(base: Path) -> dict[str, bytes]:
    return {
        path.relative_to(base).as_posix(): path.read_bytes()
        for path in base.rglob("*")
        if path.is_file() and path.suffix in TEXT_SUFFIXES
    }


def changed(reference: dict[str, bytes], target: dict[str, bytes]) -> set[str]:
    return {
        rel for rel in set(reference) | set(target)
        if reference.get(rel) != target.get(rel)
    }


def main() -> int:
    # Recompute hashes and changed-path sets from source; do not trust manifests alone.
    root = Path(__file__).resolve().parents[2]
    reference = root / "reference" / "dataverse_original_3d0959b1"
    archive = root / "reference" / "dataverse_files.zip"
    assert digest(archive) == DATAVERSE_SHA256, "Dataverse source ZIP identity changed"

    original = text_files(reference)
    m0 = text_files(root / "engines" / "M0" / "base")
    m1 = text_files(root / "engines" / "M1" / "base")
    m2 = text_files(root / "engines" / "M2" / "base")

    m0_delta = changed(original, m0)
    assert m0_delta == set(M0_ALLOWED_DELTAS), (
        "M0 escaped the exact runability/number-preserving engineering allowlist: "
        f"missing={sorted(set(M0_ALLOWED_DELTAS)-m0_delta)} "
        f"extra={sorted(m0_delta-set(M0_ALLOWED_DELTAS))}"
    )

    index_path = root / "annotated_sources" / "ANNOTATION_INDEX.csv"
    with index_path.open(newline="", encoding="utf-8") as handle:
        rows = list(csv.DictReader(handle))
    assert rows, "annotation index is empty"
    for row in rows:
        assert row["why"].strip(), f"empty rationale: {row}"
        assert row["scientific_effect"].strip(), f"empty scientific effect: {row}"

    # Publication lineage now separates P from M; preserve the prior exact
    # scientific delta allowlists and independently require full index coverage.
    for method, target in (("M0", m0), ("M1", m1), ("M2", m2)):
        expected = changed(original, target) if method == "M0" else changed(m0, target)
        selected = [r for r in rows if r["experiment_id"] == f"P1_{method}_D0"
                    and (r["owner"] in {"M0", "P"} if method == "M0" else
                         r["from_id"] == "P1_M0_D0" and r["to_id"] == f"P1_{method}_D0")]
        indexed = {r["relative_path"] for r in selected}
        assert indexed == expected, (method, expected-indexed, indexed-expected)
    m1_delta = changed(m0,m1)
    m2_delta = changed(m0,m2)
    import importlib.util
    spec=importlib.util.spec_from_file_location("annotation_reasons",root/"scripts/build_annotated_source_mirrors.py")
    reasons=importlib.util.module_from_spec(spec);spec.loader.exec_module(reasons)
    assert m2_delta == set(reasons.M2_REASONS), "M2 exact scientific allowlist changed"
    for rel in m2_delta:
        category=reasons.M2_REASONS[rel][0]
        assert category.startswith(("look-ahead-","shared-economic-")) or category == "deterministic-future-data-fix", (rel,category)

    print(
        "METHOD_BOUNDARY_CONTRACT_OK "
        f"dataverse_sha={DATAVERSE_SHA256[:8]} "
        f"m0_exact_deltas={len(m0_delta)} "
        f"m1_beyond_m0_deltas={len(m1_delta)} "
        f"m2_causal_and_settlement_deltas={len(m2_delta)} "
        "shared_v2_input_amendment=1 number_preserving_engineering_allowed=1"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
