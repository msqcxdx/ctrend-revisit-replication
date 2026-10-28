#!/usr/bin/env python3
"""Recalculate author-factor statistics and redraw saved aggregate comparisons.

No CMC observation or 18-run weekly return is included in this public task.
The original author workbook is decoded independently from the saved CSV;
18 experimental values are *transcribed/reshaped*, never re-estimated here.
"""

from __future__ import annotations

import argparse
import csv
import hashlib
import io
import json
import math
from pathlib import Path
import re
import statistics
import zipfile
from xml.etree import ElementTree as ET

ROOT = Path(__file__).resolve().parents[1]
S = "http://schemas.openxmlformats.org/spreadsheetml/2006/main"
R = "http://schemas.openxmlformats.org/package/2006/relationships"
DOC_R = "http://schemas.openxmlformats.org/officeDocument/2006/relationships"
WORKBOOK = "Results/CTREND/CTREND.xlsx"
IDS = tuple(f"P{p}_M{m}_D{d}" for p in range(2) for m in (0, 2, 1) for d in range(3))


def sha(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def csv_rows(path: Path) -> list[dict[str, str]]:
    with path.open(newline="", encoding="utf-8-sig") as handle:
        return list(csv.DictReader(handle))


def write_csv(path: Path, rows: list[dict[str, object]]) -> None:
    if not rows:
        raise ValueError(f"empty generated table: {path.name}")
    with path.open("w", newline="", encoding="utf-8") as handle:
        writer = csv.DictWriter(handle, fieldnames=list(rows[0]), lineterminator="\n")
        writer.writeheader()
        writer.writerows(rows)


def decode_author_workbook() -> tuple[list[tuple[int, float]], str]:
    """Read the named sheet from the immutable Dataverse ZIP, not a saved CSV."""
    archive_path = ROOT / "reference/dataverse_files.zip"
    expected = json.loads((ROOT / "results/comparisons/paper_factor/PAPER_FACTOR_PROVENANCE.json").read_text())
    if sha(archive_path) != expected["archive_sha256"]:
        raise ValueError("original author archive differs from recorded source")
    with zipfile.ZipFile(archive_path) as archive:
        if archive.namelist().count(WORKBOOK) != 1:
            raise ValueError("author factor workbook must occur exactly once")
        payload = archive.read(WORKBOOK)
    payload_sha = hashlib.sha256(payload).hexdigest()
    if payload_sha != expected["workbook_sha256"]:
        raise ValueError("author factor workbook hash mismatch")
    with zipfile.ZipFile(io.BytesIO(payload)) as book:
        names = book.namelist()
        if len(names) != len(set(names)):
            raise ValueError("ambiguous OOXML members")
        strings: list[str] = []
        if "xl/sharedStrings.xml" in names:
            tree = ET.fromstring(book.read("xl/sharedStrings.xml"))
            strings = ["".join(node.itertext()) for node in tree.findall(f"{{{S}}}si")]
        workbook = ET.fromstring(book.read("xl/workbook.xml"))
        sheets = [node for node in workbook.findall(f"{{{S}}}sheets/{{{S}}}sheet")
                  if node.get("name") == "Data from Study"]
        if len(sheets) != 1:
            raise ValueError("author data worksheet is not unique")
        rel_id = sheets[0].get(f"{{{DOC_R}}}id")
        rels = ET.fromstring(book.read("xl/_rels/workbook.xml.rels"))
        targets = [node.get("Target") for node in rels.findall(f"{{{R}}}Relationship")
                   if node.get("Id") == rel_id and node.get("TargetMode") != "External"]
        if len(targets) != 1 or not targets[0]:
            raise ValueError("invalid author worksheet relationship")
        sheet_path = targets[0].lstrip("/") if targets[0].startswith("/") else "xl/" + targets[0]
        sheet = ET.fromstring(book.read(sheet_path))
        cells: dict[str, str | None] = {}
        for cell in sheet.findall(f"{{{S}}}sheetData/{{{S}}}row/{{{S}}}c"):
            address = cell.get("r")
            if not address or address in cells:
                raise ValueError("missing or duplicate worksheet cell")
            value = cell.find(f"{{{S}}}v")
            raw = value.text if value is not None else None
            if cell.get("t") == "s":
                raw = strings[int(raw)]
            elif cell.get("t") == "inlineStr":
                raw = "".join(cell.find(f"{{{S}}}is").itertext())
            elif cell.get("t") in ("e", "b"):
                raise ValueError("nonnumeric author factor cell")
            cells[address] = raw
        if cells.get("A1") != "YYYYWW" or cells.get("B1") != "CTREND":
            raise ValueError("author factor column labels changed")
        indices = sorted({int(m.group(1)) for address in cells
                          if (m := re.fullmatch(r"[AB](\d+)", address))} - {1})
        series: list[tuple[int, float]] = []
        for row in indices:
            date, value = cells.get(f"A{row}"), cells.get(f"B{row}")
            if date is None and value is None:
                continue
            week = int(date)
            if not re.fullmatch(r"\d{6}", date) or not 1 <= week % 100 <= 52:
                raise ValueError("invalid author YYYYWW key")
            if series and week <= series[-1][0]:
                raise ValueError("author weeks are duplicated or unsorted")
            series.append((week, float(value) if value is not None else math.nan))
    if not series:
        raise ValueError("author workbook has no observations")
    saved = csv_rows(ROOT / "results/comparisons/paper_factor/PAPER_WEEKLY_RETURNS.csv")
    if len(saved) != len(series):
        raise ValueError("saved author series length differs from workbook")
    for (week, value), row in zip(series, saved):
        observed = float(row["paper_hl_return"]) if row["paper_hl_return"] else math.nan
        if week != int(row["year_week"]) or not (value == observed or math.isnan(value) and math.isnan(observed)):
            raise ValueError(f"saved author return differs from workbook at {week}")
    return series, payload_sha


def moments(series: list[tuple[int, float]]) -> dict[str, object]:
    finite = [(week, value) for week, value in series if math.isfinite(value)]
    values = [value for _, value in finite]
    n = len(values)
    if n < 2:
        raise ValueError("insufficient author factor observations")
    mean = statistics.mean(values)
    sd = statistics.stdev(values)
    if sd <= 0:
        raise ValueError("author factor has no finite dispersion")
    return dict(series="Paper", weeks=n, first_week=finite[0][0], last_week=finite[-1][0],
                mean_weekly_pct=mean * 100, std_weekly_pct=sd * 100,
                t=mean / sd * math.sqrt(n), sharpe_annualized=mean / sd * math.sqrt(52))


def verify_saved_aggregates() -> tuple[list[dict[str, str]], list[dict[str, str]]]:
    registry = csv_rows(ROOT / "config/experiments_pmd.csv")
    if {row["experiment_id"] for row in registry} != set(IDS) or len(registry) != 18:
        raise ValueError("experiment registry differs from the 18-cell design")
    wide = csv_rows(ROOT / "results/comparisons/source_tables/NINETEEN_WAY_HEADLINE.csv")
    long = csv_rows(ROOT / "results/comparisons/source_tables/NINETEEN_WAY_HEADLINE_LONG.csv")
    if not wide or len(long) != len(wide) * 19:
        raise ValueError("incomplete saved headline evidence")
    values = {(row["metric"], row["series"]): row["value"] for row in long}
    if len(values) != len(long):
        raise ValueError("duplicate saved headline key")
    for row in wide:
        if set(row) != {"metric", "paper", *IDS}:
            raise ValueError("headline columns differ from experiment registry")
        for series in ("paper", *IDS):
            if row[series] != values[(row["metric"], series)]:
                raise ValueError("headline wide/long inconsistency")
    cells = csv_rows(ROOT / "results/comparisons/source_tables/EIGHTEEN_EXPERIMENT_ALL_TABLE_CELLS.csv")
    if not cells or set(cells[0]) != {"paper_item", "row_label", "row_occurrence", "column_index", "column_label", *IDS}:
        raise ValueError("saved paper table cells do not match declared schema")
    keys = [(row["paper_item"], row["row_label"], row["row_occurrence"], row["column_index"]) for row in cells]
    if len(keys) != len(set(keys)) or not {f"Table {n}" for n in range(1, 10)} <= {row["paper_item"] for row in cells}:
        raise ValueError("saved main table cells are duplicate or incomplete")
    return wide, cells


def attach_published_cells(cells: list[dict[str, str]]) -> list[dict[str, str]]:
    benchmarks = csv_rows(ROOT / "results/comparisons/source_tables/CURATED_PAPER_BENCHMARKS.csv")
    keyed: dict[tuple[str, str, str, str], dict[str, str]] = {}
    for row in benchmarks:
        if row["paper_item"] == "Table B.1":
            # Definition-only appendix item, not a numerical table cell.
            continue
        key = (row["paper_item"], row["experiment_row_label"],
               row["experiment_row_occurrence"], row["experiment_column_index"])
        if key in keyed:
            raise ValueError("duplicate published paper benchmark key")
        keyed[key] = row
    all_keys = {(row["paper_item"], row["row_label"], row["row_occurrence"], row["column_index"])
                for row in cells}
    if not set(keyed) <= all_keys:
        raise ValueError("published paper benchmark does not map to saved experiment cells")
    output: list[dict[str, str]] = []
    for row in cells:
        if not re.fullmatch(r"Table [1-9]", row["paper_item"]):
            continue
        benchmark = keyed.get((row["paper_item"], row["row_label"],
                               row["row_occurrence"], row["column_index"]))
        output.append({**{name: row[name] for name in ("paper_item", "row_label", "row_occurrence", "column_index", "column_label")},
                       "paper_metric": benchmark["metric"] if benchmark else "",
                       "paper_value": benchmark["paper_value"] if benchmark else "",
                       "paper_disclosure_scope": benchmark["disclosure_scope"] if benchmark else "",
                       **{id: row[id] for id in IDS}})
    return output


def svg_line(series: list[tuple[int, float]]) -> str:
    # This is a new wealth diagnostic, not the published Figure B.2.
    wealth = 1.0
    points: list[tuple[int, float]] = []
    for week, ret in series:
        if math.isfinite(ret):
            wealth *= 1.0 + ret
            points.append((week, wealth))
    lo, hi = min(v for _, v in points), max(v for _, v in points)
    x0, x1, y0, y1 = 76, 940, 430, 64
    coords = " ".join(f"{x0+(x1-x0)*i/(len(points)-1):.2f},{y0-(y0-y1)*(v-lo)/(hi-lo):.2f}"
                      for i, (_, v) in enumerate(points))
    return (f'<svg xmlns="http://www.w3.org/2000/svg" width="1020" height="510" viewBox="0 0 1020 510">\n'
            f'<rect width="1020" height="510" fill="white"/>\n'
            f'<text x="76" y="31" font-family="sans-serif" font-size="20">Author-published CTREND factor: cumulative wealth diagnostic</text>\n'
            f'<text x="76" y="490" font-family="sans-serif" font-size="13">New diagnostic, not a reproduction of published Figure B.2; weekly H-L returns from the author workbook.</text>\n'
            f'<path d="M{x0},{y1} V{y0} H{x1}" fill="none" stroke="#777"/>\n'
            f'<polyline points="{coords}" fill="none" stroke="#1f4e79" stroke-width="2"/>\n'
            f'<text x="5" y="{y1+5}" font-family="sans-serif" font-size="12">{hi:.2f}</text>\n'
            f'<text x="5" y="{y0+5}" font-family="sans-serif" font-size="12">{lo:.2f}</text>\n'
            f'<text x="{x0}" y="{y0+20}" font-family="sans-serif" font-size="12">{points[0][0]}</text>\n'
            f'<text x="{x1-50}" y="{y0+20}" font-family="sans-serif" font-size="12">{points[-1][0]}</text>\n'
            '</svg>\n')


def svg_bars(m: dict[str, object], wide: list[dict[str, str]]) -> str:
    row = next(row for row in wide if row["metric"] == "CTREND H-L weekly mean (t)")
    values = [("Paper", float(m["mean_weekly_pct"]))]
    for id in IDS:
        match = re.fullmatch(r"([-+]?\d+(?:\.\d+)?)\s*\([^)]*\)", row[id])
        if not match:
            raise ValueError(f"unparseable saved weekly mean: {id}")
        values.append((id, float(match.group(1))))
    lower, upper = min(0, *(v for _, v in values)), max(0, *(v for _, v in values))
    if upper <= lower:
        raise ValueError("no mean-return contrast")
    scale = lambda v: 72 + (upper - v) * 310 / (upper - lower)
    bars = []
    for i, (label, value) in enumerate(values):
        x = 62 + i * 49
        y = min(scale(value), scale(0))
        h = abs(scale(value) - scale(0))
        color = "#1f4e79" if label == "Paper" else "#c26b30"
        bars.append(f'<rect x="{x}" y="{y:.2f}" width="30" height="{h:.2f}" fill="{color}"/>')
        bars.append(f'<text transform="translate({x+23},425) rotate(-65)" font-family="sans-serif" font-size="10">{label}</text>')
    return ('<svg xmlns="http://www.w3.org/2000/svg" width="1040" height="560" viewBox="0 0 1040 560">\n'
            '<rect width="1040" height="560" fill="white"/>\n'
            '<text x="50" y="30" font-family="sans-serif" font-size="19">Weekly H-L mean (%): author workbook versus saved 18-cell summaries</text>\n'
            '<text x="50" y="535" font-family="sans-serif" font-size="12">Paper is recalculated from the author workbook; experiment bars redraw saved rounded cells, not model re-estimates.</text>\n'
            f'<path d="M50,{scale(0):.2f} H1010" stroke="#555"/>\n' + "\n".join(bars) + '\n</svg>\n')


def build(output: Path) -> None:
    output = output.expanduser().resolve()
    if output.exists():
        raise ValueError(f"output directory must be fresh: {output}")
    series, workbook_sha = decode_author_workbook()
    m = moments(series)
    expected = json.loads((ROOT / "results/comparisons/paper_factor/PAPER_FACTOR_PROVENANCE.json").read_text())["full_support"]
    for key in ("weeks", "first_week", "last_week", "mean_weekly_pct", "std_weekly_pct", "t", "sharpe_annualized"):
        if isinstance(m[key], float):
            if not math.isclose(m[key], expected[key], rel_tol=1e-12, abs_tol=1e-12):
                raise ValueError(f"author workbook moment differs: {key}")
        elif m[key] != expected[key]:
            raise ValueError(f"author workbook support differs: {key}")
    wide, cells = verify_saved_aggregates()
    main = attach_published_cells(cells)
    output.mkdir(parents=True)
    write_csv(output / "AUTHOR_FACTOR_RECALCULATED.csv", [m])
    write_csv(output / "SAVED_NINETEEN_WAY_HEADLINE.csv", wide)
    write_csv(output / "SAVED_MAIN_TABLE_CELLS.csv", main)
    (output / "AUTHOR_FACTOR_WEALTH_DIAGNOSTIC.svg").write_text(svg_line(series), encoding="utf-8")
    (output / "SAVED_MEAN_COMPARISON.svg").write_text(svg_bars(m, wide), encoding="utf-8")
    (output / "SCOPE.md").write_text(
        "# Scope of this public quick replication\n\n"
        "The author CTREND H-L return series was read anew from the CC0 Dataverse workbook, "
        "checked week by week against the saved public CSV, and used to recalculate "
        "371 finite-week moments. `AUTHOR_FACTOR_RECALCULATED.csv` is a new statistical calculation.\n\n"
        "The 18 experiment headline cells and main-table cells were checked for schema and "
        "wide/long consistency, then reshaped from existing *saved aggregate results*. "
        "Where the published article discloses an exact comparison cell, that cell was "
        "joined by table, row occurrence and column, with disclosure scope retained. "
        "Their values were **not** re-estimated from CMC data. The two SVGs are new "
        "diagnostic redraws, not the published paper figures. The public repository "
        "cannot regenerate the 18 model fits or paper figures without the separately "
        "licensed raw inputs and MATLAB environment.\n",
        encoding="utf-8")
    inputs = [ROOT / "reference/dataverse_files.zip",
              ROOT / "results/comparisons/paper_factor/PAPER_FACTOR_PROVENANCE.json",
              ROOT / "results/comparisons/source_tables/NINETEEN_WAY_HEADLINE.csv",
              ROOT / "results/comparisons/source_tables/NINETEEN_WAY_HEADLINE_LONG.csv",
              ROOT / "results/comparisons/source_tables/CURATED_PAPER_BENCHMARKS.csv",
              ROOT / "results/comparisons/source_tables/EIGHTEEN_EXPERIMENT_ALL_TABLE_CELLS.csv"]
    (output / "INPUTS.sha256").write_text("".join(f"{sha(p)}  {p.relative_to(ROOT)}\n" for p in inputs), encoding="utf-8")
    files = sorted(p for p in output.iterdir() if p.name != "OUTPUTS.sha256")
    (output / "OUTPUTS.sha256").write_text("".join(f"{sha(p)}  {p.name}\n" for p in files), encoding="utf-8")
    print(f"PUBLIC_TABLES_REPRODUCED output={output} author_finite_weeks={m['weeks']} "
          f"author_workbook_sha256={workbook_sha} main_saved_cells={len(main)} "
          "experimental_models_reestimated=0")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("output", type=Path, help="fresh output directory; existing paths are refused")
    args = parser.parse_args()
    build(args.output)


if __name__ == "__main__":
    main()
