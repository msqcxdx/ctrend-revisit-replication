#!/usr/bin/env python3
# CTREND_REVISIT_FILE_PURPOSE: Add design-specific OOS denominators to frozen E11 paired-coverage results without rescanning b09 MAT files.
"""Derive a small coverage clarification; leave accepted E11 CSVs unchanged."""

import csv
from collections import defaultdict
from hashlib import sha256
import json
from pathlib import Path

import numpy as np


ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "followup_research/outputs/E11"
OUT = ROOT / "analysis/isolated_corrections/e11_coverage"


def digest(path: Path) -> str:
    value = sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            value.update(block)
    return value.hexdigest()


def main() -> None:
    with (SOURCE / "design_choices_M1.csv").open(newline="", encoding="utf-8") as stream:
        designs = list(csv.DictReader(stream))
    if len(designs) != 3072:
        raise ValueError("Expected all 3,072 design choices")
    training = {int(row["b09_combo_id"]): int(row["vNumIn"]) for row in designs}
    grouped = defaultdict(lambda: [[], []])
    parents = {}
    n_rows = 0
    for p in (0, 1):
        for d in (0, 1, 2):
            path = SOURCE / f"paired_design_cells_P{p}_D{d}.csv"
            parents[path.name] = digest(path)
            with path.open(newline="", encoding="utf-8") as stream:
                for row in csv.DictReader(stream):
                    calendar = int(row["scheduled_weeks"])
                    pair = int(row["pair_n"])
                    oos = calendar-training[int(row["b09_combo_id"])]
                    if (oos <= 0 or pair > oos or
                            abs(float(row["pair_common_coverage"])-pair/calendar) > 1e-12):
                        raise ValueError(f"Coverage input inconsistency: {path.name} row={n_rows}")
                    key = (p, d, row["method"], row["from_method"], row["to_method"])
                    grouped[key][0].append(pair/calendar)
                    grouped[key][1].append(pair/oos)
                    n_rows += 1
    if n_rows != 6*3072*9*3:
        raise ValueError("Incomplete E11 paired design grid")
    rows = []
    for key, (full, oos) in sorted(grouped.items()):
        rows.append(dict(p=key[0], d=key[1], method=key[2],
                         from_method=key[3], to_method=key[4],
                         design_count=len(full),
                         median_full_calendar_coverage=float(np.median(full)),
                         median_scheduled_oos_coverage=float(np.median(oos)),
                         full_calendar_denominator="all_stored_calendar_weeks",
                         scheduled_oos_denominator="calendar_weeks_after_design_training"))
    OUT.mkdir(parents=True, exist_ok=True)
    summary = OUT / "paired_coverage_denominators_summary.csv"
    with summary.open("w", newline="", encoding="utf-8") as stream:
        writer = csv.DictWriter(stream, fieldnames=list(rows[0]))
        writer.writeheader()
        writer.writerows(rows)
    receipt = dict(scope="E11_paired_coverage_denominator_clarification_only",
                   rows_read=n_rows, groups=len(rows),
                   design_choices_sha256=digest(SOURCE / "design_choices_M1.csv"),
                   parent_csv_sha256=parents,
                   script_sha256=digest(Path(__file__)),
                   summary_sha256=digest(summary))
    (OUT / "RECEIPT.json").write_text(json.dumps(receipt, indent=2)+"\n",
                                      encoding="utf-8")
    print(f"E11_COVERAGE_CLARIFIED_OK rows={n_rows} groups={len(rows)}")


if __name__ == "__main__":
    main()
