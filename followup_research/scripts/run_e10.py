#!/usr/bin/env python3
"""Run the isolated E10 phase experiment on all six accepted M1 inputs."""

from __future__ import annotations

import argparse
from concurrent.futures import ThreadPoolExecutor
import csv
import os
from pathlib import Path
import subprocess
from prepare_e10_audit_helpers import prepare


ROOT = Path(__file__).resolve().parents[1]
REPO = ROOT.parent
OUT = ROOT / "outputs" / "E10"


def run(eid: str, root: Path, matlab: str, force: bool = False) -> tuple[str, str]:
    output = OUT / f"{eid}_weekly_holding.csv"
    if output.is_file() and output.stat().st_size > 1000 and not force:
        return eid, "existing_output_preserved"
    expression = (f"addpath('{ROOT / 'scripts'}'); addpath('{OUT / 'reference_sort'}'); "
                  f"analyze_e10_holding('{root}','{output}');")
    log = OUT / f"{eid}.log"
    with log.open("w", encoding="utf-8") as f:
        result = subprocess.run([matlab,"-licmode","onlinelicensing",
                                 "-nodisplay","-nosplash","-batch",expression],
                                cwd=REPO, stdout=f, stderr=subprocess.STDOUT,
                                env={**os.environ,"OMP_NUM_THREADS":"1"})
    if result.returncode or not output.is_file():
        raise RuntimeError(f"E10 failed for {eid}, rc={result.returncode}, log={log}")
    return eid, "computed"


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--matlab", required=True)
    ap.add_argument("--workers", type=int, default=2)
    ap.add_argument("--force", action="store_true",help="recompute isolated E10 outputs only")
    args = ap.parse_args()
    accepted = list(csv.DictReader((ROOT / "outputs" / "E11" /
                                    "accepted_run_paths.csv").open()))
    roots = {r["experiment_id"]: Path(r["accepted_run_root"])
             for r in accepted if "_M1_" in r["experiment_id"]}
    if len(roots) != 6:
        raise RuntimeError("E10 requires all six accepted M1 roots")
    OUT.mkdir(parents=True, exist_ok=True)
    # A function-name-only copy prevents shadowing the accepted M1 helper.
    # This is the original M0 sorting algorithm, not a hand-coded proxy.
    original=REPO/'engines/M0/base/Utils/fSingleSortMulti.m'
    text=original.read_text()
    header='function rResults = fSingleSortMulti('
    if text.count(header)!=1:raise ValueError('Original sort signature differs')
    target=OUT/'reference_sort';target.mkdir(exist_ok=True)
    (target/'fE10PublishedSingleSort.m').write_text(text.replace(header,
        'function rResults = fE10PublishedSingleSort(',1))
    prepare()
    with ThreadPoolExecutor(max_workers=args.workers) as pool:
        results = list(pool.map(lambda x: run(x[0],x[1],args.matlab,args.force),
                                sorted(roots.items())))
    for eid, state in results:
        print(f"E10_RUN_OK {eid} {state}", flush=True)


if __name__ == "__main__":
    main()
