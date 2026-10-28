#!/usr/bin/env python3
# CTREND_REVISIT_FILE_PURPOSE: Independently compare published M1 cells with saved component estimates and unchanged full-run reference tables.
"""Optional saved-result audit; not a precondition for release or production.

Inspect the rendered numbers and source/run identities, not just file hashes.
M0/M2 and unrelated M1 rows must remain full-run copies. No MATLAB is started.
"""

import csv
from hashlib import sha256
from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[2]
COMPONENTS = ROOT / "analysis/isolated_corrections"
SOURCE = ROOT / "results/comparisons/source_tables"


def rows(path):
    with path.open(newline="", encoding="utf-8") as stream:
        return list(csv.DictReader(stream))


def digest(path):
    return sha256(path.read_bytes()).hexdigest()


def printed(mean, tstat):
    return f"{float(mean):.2f} ({float(tstat):.2f})"


def tex_cells(path):
    result = {}
    for line in path.read_text().splitlines():
        if " & " not in line or not line.endswith(r"\\"):
            continue
        cells = line[:-2].split(" & ")
        for column, cell in enumerate(cells[1:], 1):
            # Extract numeric content independently of the publication renderer.
            numbers = re.findall(r"[+-]?\d+\.\d+", cell)
            if numbers:
                assert len(numbers) == 2, (path, line)
                result[cells[0], column] = f"{numbers[0]} ({numbers[1]})"
    return result


all_csv = {(r["paper_item"], r["row_label"], int(r["column_index"])): r
           for r in rows(SOURCE / "EIGHTEEN_EXPERIMENT_ALL_TABLE_CELLS.csv")}
table7 = rows(COMPONENTS / "table7_direction/table7_direction_corrected_42_cells.csv")
null_columns = {"CTREND": 1, "CMKT+CTREND": 2,
                "CMKT+CSMB+CTREND": 3, "CMKT+CSMB+CMOM": 4}
expected = {}
for r in table7:
    key = (r["experiment_id"], "Table 7", r["added_factor"], null_columns[r["null_factor_set"]])
    expected[key] = printed(r["corrected_alpha_pct"], r["corrected_hac_t"])
for eid in {r["experiment_id"] for r in table7}:
    portfolios = rows(COMPONENTS / "delay" / eid / "delay_appendix_portfolios.csv")
    for r in portfolios:
        column = ["L", "2", "3", "4", "H", "H-L"].index(r["portfolio"]) + 1
        expected[eid, "Table B.5", "delay", column] = printed(r["corrected_mean_pct"], r["corrected_t"])

identities = {r["experiment_id"]: r for r in rows(ROOT / "provenance/accepted_18/PUBLIC_RUN_IDENTITIES.csv")}
ledger = rows(ROOT / "provenance/analytical_tables/TABLE_IDENTITIES.csv")
assert {(r["experiment_id"], r["paper_item"]) for r in ledger} == {key[:2] for key in expected}
checked = set()
for r in ledger:
    eid, item = r["experiment_id"], r["paper_item"]
    assert r["research_run_id"] == identities[eid]["research_run_id"]
    for name, hash_name in [("publication_path", "publication_sha256"),
                            ("component_source", "component_sha256"),
                            ("full_run_reference", "full_run_reference_sha256")]:
        assert digest(ROOT / r[name]) == r[hash_name], (eid, name)
    assert digest(ROOT / "analysis/render_m1_publication_tables.py") == r["renderer_sha256"]
    current = tex_cells(ROOT / r["publication_path"])
    reference = tex_cells(ROOT / r["full_run_reference"])
    assert current.keys() == reference.keys()
    for (label, column), value in current.items():
        key = (eid, item, label, column)
        if key in expected:
            assert value == expected[key], key
            assert all_csv[item, label, column][eid] == expected[key], key
            checked.add(key)
        else:
            assert value == reference[label, column], (eid, item, label, column)
    # Every untouched line, including titles, notes and all other rows, is identical.
    labels = {key[2] for key in expected if key[:2] == (eid, item)}
    def unrelated(path):
        return [line for line in path.read_text().splitlines() if line.split(" & ")[0] not in labels]
    assert unrelated(ROOT / r["publication_path"]) == unrelated(ROOT / r["full_run_reference"])
assert checked == set(expected)

# Independently follow the Markdown headers to prevent a correct cell landing
# under the wrong experiment, or the main report retaining an outdated value.
for path in [SOURCE / "ALL_PAPER_ITEMS_NINETEEN_WAY_COMPARISON_CN.md",
             ROOT / "results/comparisons/NINETEEN_WAY_FULL_REPORT_CN.md"]:
    item, header, seen = None, [], set()
    for line in path.read_text().splitlines():
        match = re.match(r"#{2,3} (Table [^：]+)：", line)
        if match:
            item, header = match[1], []
        if line.startswith("| 指标 |"):
            header = [c.strip() for c in line.strip("|").split("|")]
        if not header or not line.startswith("| ") or item not in ("Table 7", "Table B.5"):
            continue
        cells = [c.strip() for c in line.strip("|").split("|")]
        if item == "Table 7" and " / " in cells[0]:
            label, null = cells[0].split(" / ")
            column = 4 if null == "LTW" else null_columns[null]
        elif item == "Table B.5" and cells[0] == "delay":
            label, column = "delay", 6
        else:
            continue
        for eid, value in zip(header, cells):
            key = (eid, item, label, column)
            if key in expected:
                assert value == expected[key], (path, key)
                assert key not in seen, (path, key)
                seen.add(key)
    assert seen == {key for key in expected if key[1] == "Table 7" or key[3] == 6}, path
print(f"ANALYTICAL_PUBLICATION_TABLES_OK tables={len(ledger)} cells={len(checked)} full_run_references_intact=1")
