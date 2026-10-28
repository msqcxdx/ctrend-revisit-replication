#!/usr/bin/env python3
"""Exercise the real public quick-replication command in a fresh directory."""

import csv
import hashlib
from pathlib import Path
import subprocess
import tempfile
from xml.etree import ElementTree as ET

ROOT = Path(__file__).resolve().parents[1]


def sha(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


with tempfile.TemporaryDirectory(prefix="cttrend_public_tables_") as temporary:
    output = Path(temporary) / "tables"
    command = [str(ROOT / "reproduce_tables.sh"), str(output)]
    completed = subprocess.run(command, cwd=ROOT, text=True, capture_output=True, check=True)
    assert "PUBLIC_TABLES_REPRODUCED" in completed.stdout
    assert "experimental_models_reestimated=0" in completed.stdout
    with (output / "AUTHOR_FACTOR_RECALCULATED.csv").open(newline="") as stream:
        moment_rows = list(csv.DictReader(stream))
    assert len(moment_rows) == 1
    moment = moment_rows[0]
    assert moment["series"] == "Paper" and int(moment["weeks"]) == 371
    assert round(float(moment["mean_weekly_pct"]), 2) == 3.87
    assert round(float(moment["t"]), 2) == 5.19
    assert round(float(moment["sharpe_annualized"]), 2) == 1.94
    with (output / "SAVED_NINETEEN_WAY_HEADLINE.csv").open(newline="") as stream:
        headline = list(csv.DictReader(stream))
    assert len(headline) > 5 and len(headline[0]) == 20
    with (output / "SAVED_MAIN_TABLE_CELLS.csv").open(newline="") as stream:
        main = list(csv.DictReader(stream))
    assert {f"Table {n}" for n in range(1, 10)} <= {row["paper_item"] for row in main}
    assert sum(bool(row["paper_value"]) for row in main) > 100
    hl = next(row for row in main if (row["paper_item"], row["row_label"],
            row["row_occurrence"], row["column_index"]) == ("Table 3", "H-L", "1", "1"))
    assert hl["paper_value"] == "3.87 (5.19)"
    for name in ("AUTHOR_FACTOR_WEALTH_DIAGNOSTIC.svg", "SAVED_MEAN_COMPARISON.svg"):
        ET.parse(output / name)
    for line in (output / "OUTPUTS.sha256").read_text().splitlines():
        expected, relative = line.split("  ", 1)
        assert sha(output / relative) == expected
    for line in (output / "INPUTS.sha256").read_text().splitlines():
        expected, relative = line.split("  ", 1)
        assert sha(ROOT / relative) == expected
    refused = subprocess.run(command, cwd=ROOT, text=True, capture_output=True)
    assert refused.returncode != 0 and "must be fresh" in refused.stderr
print("PUBLIC_TABLE_REPRODUCTION_TEST_OK author_recomputed=1 saved_main_tables=9 svg=2 reestimation=0")
