#!/usr/bin/env python3
# CTREND_REVISIT_FILE_PURPOSE: Render M1 Table 7 and the delay appendix from saved component calculations, preserving full-run references.
"""Synchronize compact TeX, source CSV and Markdown without fitting a model.

Only M1 uses the definition-consistent columns. M0/M2 retain the author delay
formula. Full-run bytes are retained separately; their identities are not
reassigned to derived tables. This renderer is for the bundled result snapshot,
not newly registered runs, whose tables are read directly from their outputs.
"""

import csv
from hashlib import sha256
import math
from pathlib import Path
import shutil

ROOT = Path(__file__).resolve().parents[1]
COMPONENTS = ROOT / "analysis/isolated_corrections"
SOURCE = ROOT / "results/comparisons/source_tables"
REFERENCE = ROOT / "provenance/accepted_18/table_reference"
MEMBERS = ROOT / "provenance/accepted_18/RESULT_MEMBER_IDENTITIES.csv"
DERIVED = ROOT / "provenance/analytical_tables/TABLE_IDENTITIES.csv"
M1_IDS = tuple(f"P{p}_M1_D{d}" for p in range(2) for d in range(3))
NULL_SETS = ("CTREND", "CMKT+CTREND", "CMKT+CSMB+CTREND", "CMKT+CSMB+CMOM")
PORTFOLIOS = ("L", "2", "3", "4", "H", "H-L")
TABLE_FILES = {"Table 7": "frontier_expansion_test.tex",
               "Table B.5": "insignificant_anomaly_strategy_returns.tex"}


def digest(path):
    return sha256(path.read_bytes()).hexdigest()


def read_csv(path):
    with path.open(newline="", encoding="utf-8") as stream:
        return list(csv.DictReader(stream))


def write_csv(path, rows):
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", newline="", encoding="utf-8") as stream:
        writer = csv.DictWriter(stream, fieldnames=list(rows[0]), lineterminator="\n")
        writer.writeheader()
        writer.writerows(rows)


def load_values():
    # Key each cell by its economic role, never by a positional CSV row number.
    values, sources = {}, {}
    path = COMPONENTS / "table7_direction/table7_direction_corrected_42_cells.csv"
    for row in read_csv(path):
        eid = row["experiment_id"]
        column = NULL_SETS.index(row["null_factor_set"]) + 1
        key = (eid, "Table 7", row["added_factor"], column)
        assert eid in M1_IDS and key not in values, key
        values[key] = (float(row["corrected_alpha_pct"]), float(row["corrected_hac_t"]))
        sources[eid, "Table 7"] = path
    for eid in M1_IDS:
        path = COMPONENTS / "delay" / eid / "delay_appendix_portfolios.csv"
        for row in read_csv(path):
            column = PORTFOLIOS.index(row["portfolio"]) + 1
            key = (eid, "Table B.5", "delay", column)
            assert key not in values, key
            values[key] = (float(row["corrected_mean_pct"]), float(row["corrected_t"]))
        sources[eid, "Table B.5"] = path
    expected = {(eid, "Table 7", added, NULL_SETS.index(null) + 1)
                for eid in M1_IDS for null, added in (
                    ("CTREND", "CMKT"), ("CTREND", "CSMB"), ("CTREND", "CMOM"),
                    ("CMKT+CTREND", "CSMB"), ("CMKT+CTREND", "CMOM"),
                    ("CMKT+CSMB+CTREND", "CMOM"), ("CMKT+CSMB+CMOM", "CTREND"))}
    expected |= {(eid, "Table B.5", "delay", i) for eid in M1_IDS for i in range(1, 7)}
    assert set(values) == expected
    assert all(math.isfinite(x) for pair in values.values() for x in pair)
    # The reported appendix location is part of the result, not a forced label.
    assert all(abs(values[eid, "Table B.5", "delay", 6][1]) < 1.96 for eid in M1_IDS)
    return values, sources


def display(pair):
    return f"{pair[0]:.2f} ({pair[1]:.2f})"


def latex(pair):
    estimate, tstat = pair
    mean = f"{estimate:.2f}"
    if abs(tstat) >= 1.96:
        mean = r"\textbf{" + mean + "}"
    return r"\makecell[c]{" + mean + r"\\ (" + f"{tstat:.2f}" + ")}"


def render_tex(text, eid, item, values):
    lines, touched = [], set()
    for line in text.splitlines(keepends=True):
        label = line.split(" & ", 1)[0]
        keys = [key for key in values if key[:3] == (eid, item, label)]
        if keys:
            assert line.endswith("\\\\\n"), (eid, item, label)
            cells = line[:-3].split(" & ")
            for key in keys:
                assert key not in touched and key[3] < len(cells), key
                cells[key[3]] = latex(values[key])
                touched.add(key)
            line = " & ".join(cells) + "\\\\\n"
        lines.append(line)
    assert touched == {key for key in values if key[:2] == (eid, item)}
    return "".join(lines)


def render_markdown(text, values):
    # Preserve the paper and M0/M2 columns, all unrelated sections and wording.
    lines, item, header, touched = [], None, [], set()
    for line in text.splitlines(keepends=True):
        if line.startswith("## "):
            item = line[3:].split("：", 1)[0]
            header = []
        if line.startswith("| 指标 |"):
            header = [cell.strip() for cell in line.strip().strip("|").split("|")]
        if item in TABLE_FILES and line.startswith("| ") and header:
            cells = [cell.strip() for cell in line.strip().strip("|").split("|")]
            if item == "Table 7" and " / " in cells[0]:
                label, null = cells[0].split(" / ")
                null = "CMKT+CSMB+CMOM" if null == "LTW" else null
                column = NULL_SETS.index(null) + 1
            elif item == "Table B.5" and cells[0] == "delay":
                label, column = "delay", 6
            else:
                lines.append(line)
                continue
            for i, eid in enumerate(header):
                key = (eid, item, label, column)
                if key in values:
                    assert key not in touched, key
                    cells[i] = display(values[key])
                    touched.add(key)
            line = "| " + " | ".join(cells) + " |\n"
        lines.append(line)
    expected = {key for key in values if key[1] == "Table 7" or key[3] == 6}
    assert touched == expected, (touched, expected)
    return "".join(lines)


def main():
    values, sources = load_values()
    members = read_csv(MEMBERS)
    identities = {row["experiment_id"]: row for row in read_csv(
        ROOT / "provenance/accepted_18/PUBLIC_RUN_IDENTITIES.csv")}
    derivatives = []
    for eid in M1_IDS:
        for item, filename in TABLE_FILES.items():
            target = ROOT / "results/experiments" / eid / "Tables" / filename
            reference = REFERENCE / eid / filename
            member, = [row for row in members if row["experiment_id"] == eid
                       and row["source_result_member"] == "Tables/" + filename]
            if not reference.exists():
                # Keep the original full-run bytes before rendering. Never
                # associate the full-run hash with a derived table's bytes.
                assert digest(target) == member["sha256"], target
                reference.parent.mkdir(parents=True, exist_ok=True)
                shutil.copyfile(target, reference)
            assert digest(reference) == member["sha256"], reference
            member["relative_path"] = str(reference.relative_to(ROOT))
            target.write_text(render_tex(reference.read_text(), eid, item, values))
            source = sources[eid, item]
            derivatives.append(dict(experiment_id=eid, paper_item=item,
                research_run_id=identities[eid]["research_run_id"],
                publication_path=str(target.relative_to(ROOT)), publication_sha256=digest(target),
                component_source=str(source.relative_to(ROOT)), component_sha256=digest(source),
                full_run_reference=str(reference.relative_to(ROOT)),
                full_run_reference_sha256=digest(reference), renderer_sha256=digest(Path(__file__))))
    write_csv(MEMBERS, members)
    write_csv(DERIVED, derivatives)

    csv_path = SOURCE / "EIGHTEEN_EXPERIMENT_ALL_TABLE_CELLS.csv"
    rows = read_csv(csv_path)
    touched = set()
    for row in rows:
        for eid in M1_IDS:
            key = (eid, row["paper_item"], row["row_label"], int(row["column_index"]))
            if key in values:
                assert key not in touched, key
                row[eid] = display(values[key])
                touched.add(key)
    assert touched == set(values)
    write_csv(csv_path, rows)
    md_path = SOURCE / "ALL_PAPER_ITEMS_NINETEEN_WAY_COMPARISON_CN.md"
    md_path.write_text(render_markdown(md_path.read_text(), values))
    print(f"M1_PUBLICATION_TABLES_OK tables={len(derivatives)} cells={len(values)} model_reruns=0")


if __name__ == "__main__":
    main()
