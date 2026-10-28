#!/usr/bin/env python3
# CTREND_REVISIT_FILE_PURPOSE: Check that follow-up scripts bind local accepted runs by digest, without host-specific source paths.
"""Offline fixture for accepted-run lookup and public-source portability."""

import csv
from pathlib import Path
import sys
import tempfile


ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "followup_research/scripts"))
from accepted_run_roots import accepted_roots, digest  # noqa: E402


with tempfile.TemporaryDirectory() as tmp:
    base = Path(tmp)
    run = base / "run"
    result = run / "results"
    result.mkdir(parents=True)
    (run / "RUN_COMPLETE").write_text("research_run_id=test\n", encoding="utf-8")
    index = base / "accepted.csv"
    with index.open("w", newline="", encoding="utf-8") as stream:
        writer = csv.DictWriter(stream, fieldnames=("experiment_id", "accepted_run_root",
                                                  "result_root", "run_complete_sha256"))
        writer.writeheader()
        writer.writerow(dict(experiment_id="P0_M0_D0", accepted_run_root=str(run),
                             result_root=str(result),
                             run_complete_sha256=digest(run / "RUN_COMPLETE")))
    assert accepted_roots(("P0_M0_D0",), index) == {"P0_M0_D0": run}
    (run / "RUN_COMPLETE").write_text("research_run_id=altered\n", encoding="utf-8")
    try:
        accepted_roots(("P0_M0_D0",), index)
    except ValueError as exc:
        assert "identity mismatch" in str(exc)
    else:
        raise AssertionError("Altered parent completion marker was accepted")
print("FOLLOWUP_PORTABILITY_OK hash_bound_runs=1")
