#!/usr/bin/env python3
"""Read the published LTW workbook's own notes and factor-row coverage.

This is a metadata/provenance audit, not a reconstruction of factor constituents
or a claim that the workbook discloses each factor's exact transaction endpoints.
Only Python's standard library is needed; the input workbook is never modified.
"""

from __future__ import annotations

from collections import Counter
from hashlib import sha256
import json
from pathlib import Path
from xml.etree import ElementTree as ET
from zipfile import ZipFile


ROOT = Path(__file__).resolve().parents[2]
SOURCE = ROOT / "data/raw/common/LTW_3factor.xlsx"
OUTPUT = ROOT / "followup_research/outputs/E01/external_workbook_metadata_audit.json"
NS = {"x": "http://schemas.openxmlformats.org/spreadsheetml/2006/main"}


def main() -> None:
    with ZipFile(SOURCE) as book:
        shared_root = ET.fromstring(book.read("xl/sharedStrings.xml"))
        strings = [
            "".join(t.text or "" for t in item.findall(".//x:t", NS))
            for item in shared_root.findall("x:si", NS)
        ]
        sheet = ET.fromstring(book.read("xl/worksheets/sheet1.xml"))
        cells: dict[str, str] = {}
        for cell in sheet.findall(".//x:sheetData/x:row/x:c", NS):
            value = cell.find("x:v", NS)
            if value is None:
                continue
            text = value.text or ""
            cells[cell.attrib["r"]] = (
                strings[int(text)] if cell.attrib.get("t") == "s" else text
            )
    header = [cells.get(f"{col}6", "") for col in "ABCD"]
    if header != ["yyww", "cmkt", "csize", "cmom"]:
        raise RuntimeError(f"Unexpected LTW workbook columns: {header}")
    records: list[tuple[int, float, float, float]] = []
    for row in range(7, 10000):
        key = cells.get(f"A{row}")
        if key is None:
            break
        records.append((int(key), *(float(cells[f"{col}{row}"]) for col in "BCD")))
    if len({r[0] for r in records}) != len(records):
        raise RuntimeError("Duplicate LTW week keys")
    if records != sorted(records):
        raise RuntimeError("LTW week keys are not sorted")
    years = Counter(str(r[0])[:4] for r in records)
    payload = {
        "input": str(SOURCE.relative_to(ROOT)),
        "input_sha256": sha256(SOURCE.read_bytes()).hexdigest(),
        "workbook_notes": [cells.get(f"A{row}", "") for row in (1, 2, 3)],
        "factor_columns": header,
        "factor_rows_with_all_three_numeric": len(records),
        "first_week": records[0][0],
        "last_week": records[-1][0],
        "rows_by_year": dict(sorted(years.items())),
        "scope": "workbook_notes_and_numeric_coverage_only_not_rowwise_constituents_or_endpoints",
    }
    OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    OUTPUT.write_text(json.dumps(payload, ensure_ascii=False, indent=2) + "\n")
    print(json.dumps({k: payload[k] for k in
                      ("input_sha256", "factor_rows_with_all_three_numeric",
                       "first_week", "last_week")}, indent=2))


if __name__ == "__main__":
    main()
