#!/usr/bin/env python3
# CTREND_REVISIT_FILE_PURPOSE: Finish six parent-bound M1 delay appendix rows from existing corrected weekly delay checkpoints.
"""Only one characteristic sort per accepted parent; no b02 or b09 rerun."""

from concurrent.futures import ThreadPoolExecutor
import csv
from hashlib import sha256
import json
import os
from pathlib import Path
import subprocess
import sys


ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "followup_research/scripts"))
from accepted_run_roots import accepted_roots  # noqa: E402


RUNS = tuple(f"P{p}_M1_D{d}" for p in (0, 1) for d in (0, 1, 2))
OUT = ROOT / "analysis/isolated_corrections/delay"


def digest(path: Path) -> str:
    value = sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            value.update(block)
    return value.hexdigest()


def validate(experiment: str) -> dict:
    directory = OUT / experiment
    ports = directory / "delay_appendix_portfolios.csv"
    alphas = directory / "delay_appendix_alphas.csv"
    with ports.open(newline="", encoding="utf-8") as stream:
        port_rows = list(csv.DictReader(stream))
    with alphas.open(newline="", encoding="utf-8") as stream:
        alpha_rows = list(csv.DictReader(stream))
    if [row["portfolio"] for row in port_rows] != ["L", "2", "3", "4", "H", "H-L"]:
        raise ValueError(f"Incomplete delay portfolio row: {experiment}")
    if [row["benchmark"] for row in alpha_rows] != ["CCAPM", "LTW"]:
        raise ValueError(f"Incomplete delay alpha row: {experiment}")
    return dict(experiment_id=experiment, portfolios_sha256=digest(ports),
                alphas_sha256=digest(alphas),
                corrected_characteristic_sha256=digest(
                    directory / "delay_characteristic_weekly.mat"))


def run_one(item: tuple[str, Path], matlab: Path) -> dict:
    experiment, parent = item
    directory = OUT / experiment
    if not (directory / "delay_characteristic_weekly.mat").is_file():
        raise ValueError(f"Corrected characteristic is missing: {experiment}")
    if (directory / "delay_appendix_portfolios.csv").is_file() and \
            (directory / "delay_appendix_alphas.csv").is_file():
        print(f"DELAY_APPENDIX_EXISTING_VERIFY experiment={experiment}", flush=True)
        return validate(experiment)
    expression = ("addpath(fullfile(pwd,'analysis')); "
                  f"recompute_m1_delay_appendix_row('{parent}','{directory}'); exit(0)")
    command = [str(matlab), "-licmode", "onlinelicensing", "-nodisplay",
               "-nosplash", "-batch", expression]
    with (directory / "appendix_matlab.log").open("w", encoding="utf-8") as log:
        result = subprocess.run(command, cwd=ROOT, stdout=log,
                                stderr=subprocess.STDOUT, check=False)
    if result.returncode != 0 or "M1_DELAY_APPENDIX_ROW_OK" not in \
            (directory / "appendix_matlab.log").read_text(encoding="utf-8"):
        raise RuntimeError(f"Delay appendix sort failed: {experiment}")
    print(f"DELAY_APPENDIX_CORRECTED experiment={experiment}", flush=True)
    return validate(experiment)


def main() -> None:
    matlab = Path(os.environ.get("MATLAB_BIN", ""))
    if not matlab.is_file() or not os.access(matlab, os.X_OK):
        raise ValueError("Set MATLAB_BIN to the tested R2023b executable")
    parents = accepted_roots(RUNS)
    with ThreadPoolExecutor(max_workers=2) as pool:
        outputs = list(pool.map(lambda item: run_one(item, matlab), parents.items()))
    receipt = dict(scope="six_M1_delay_appendix_rows_from_corrected_weekly_checkpoints",
                   matlab_executable_sha256=digest(matlab),
                   function_sha256=digest(ROOT / "analysis/recompute_m1_delay_appendix_row.m"),
                   orchestrator_sha256=digest(Path(__file__)),
                   parents=[dict(experiment_id=eid,
                                 run_complete_sha256=digest(root / "RUN_COMPLETE"))
                            for eid, root in parents.items()], outputs=outputs)
    (OUT / "APPENDIX_RECEIPT.json").write_text(json.dumps(receipt, indent=2)+"\n",
                                                encoding="utf-8")
    print(f"M1_DELAY_APPENDIX_SIX_ROWS_OK experiments={len(outputs)}", flush=True)


if __name__ == "__main__":
    main()
