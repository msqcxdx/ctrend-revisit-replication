#!/usr/bin/env python3
# CTREND_REVISIT_FILE_PURPOSE: Run isolated M1 delay/characteristic-sort corrections against six accepted parents without b09 recomputation.
"""Two independent MATLAB clients at a time; each result keeps parent hashes."""

from concurrent.futures import ThreadPoolExecutor
import csv
from hashlib import sha256
import json
import os
from pathlib import Path
import subprocess
import sys


REPO = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(REPO / "followup_research/scripts"))
from accepted_run_roots import accepted_roots  # noqa: E402


RUNS = tuple(f"P{p}_M1_D{d}" for p in (0, 1) for d in (0, 1, 2))
OUT = REPO / "analysis/isolated_corrections/delay"


def digest(path: Path) -> str:
    h = sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            h.update(chunk)
    return h.hexdigest()


def validate_output(experiment: str) -> dict:
    directory = OUT / experiment
    weekly = directory / "delay_hedge_weekly.csv"
    characteristic = directory / "delay_characteristic_weekly.mat"
    with weekly.open(newline="", encoding="utf-8") as stream:
        rows = list(csv.DictReader(stream))
    if not rows or set(rows[0]) != {"year_week", "legacy_delay_hedge",
                                    "corrected_delay_hedge"}:
        raise ValueError(f"Incomplete delay-hedge output: {experiment}")
    if len({row["year_week"] for row in rows}) != len(rows):
        raise ValueError(f"Repeated delay-hedge calendar: {experiment}")
    if characteristic.stat().st_size < 1024:
        raise ValueError(f"Missing delay-characteristic payload: {experiment}")
    return dict(experiment_id=experiment, weekly_rows=len(rows),
                weekly_sha256=digest(weekly), characteristic_sha256=digest(characteristic))


def run_one(item: tuple[str, Path], matlab: Path) -> dict:
    experiment, parent = item
    directory = OUT / experiment
    directory.mkdir(parents=True, exist_ok=True)
    if (directory / "delay_hedge_weekly.csv").is_file() and \
            (directory / "delay_characteristic_weekly.mat").is_file():
        print(f"DELAY_EXISTING_OUTPUT_VERIFY experiment={experiment}", flush=True)
        return validate_output(experiment)
    expression = (f"addpath(fullfile(pwd,'analysis')); "
                  f"recompute_m1_delay('{parent}','{directory}'); exit(0)")
    command = [str(matlab), "-licmode", "onlinelicensing", "-nodisplay",
               "-nosplash", "-batch", expression]
    with (directory / "matlab.log").open("w", encoding="utf-8") as log:
        result = subprocess.run(command, cwd=REPO, stdout=log,
                                stderr=subprocess.STDOUT, check=False)
    if result.returncode != 0 or "M1_DELAY_CORRECTION_OK" not in \
            (directory / "matlab.log").read_text(encoding="utf-8"):
        raise RuntimeError(f"M1 delay correction failed {experiment}; see {directory}/matlab.log")
    print(f"DELAY_CORRECTED experiment={experiment}", flush=True)
    return validate_output(experiment)


def main() -> None:
    matlab = Path(os.environ.get("MATLAB_BIN", ""))
    if not matlab.is_file() or not os.access(matlab, os.X_OK):
        raise ValueError("Set MATLAB_BIN to the tested R2023b executable")
    parents = accepted_roots(RUNS)
    OUT.mkdir(parents=True, exist_ok=True)
    with ThreadPoolExecutor(max_workers=2) as pool:
        outputs = list(pool.map(lambda item: run_one(item, matlab), parents.items()))
    receipt = dict(scope="six_M1_delay_and_delay_only_appendix_sort_no_b09_reestimation",
                   matlab_executable_sha256=digest(matlab),
                   matlab_function_sha256=digest(REPO / "analysis/recompute_m1_delay.m"),
                   orchestrator_sha256=digest(Path(__file__)),
                   parents=[dict(experiment_id=eid,
                                 run_complete_sha256=digest(root / "RUN_COMPLETE"),
                                 b01_sha256=digest(root / "data/b0DataOLHC.mat"),
                                 b02_weekly_sha256=digest(root / "data/bCharacteristicsOLHC_Combo1.mat"),
                                 hedgeports_sha256=digest((root / "results" if
                                     (root / "results").is_dir() else
                                     root / "results.staging") / "HedgePorts.mat"))
                            for eid, root in parents.items()],
                   outputs=outputs)
    (OUT / "RECEIPT.json").write_text(json.dumps(receipt, indent=2)+"\n",
                                      encoding="utf-8")
    print(f"M1_DELAY_SIX_CORRECTIONS_OK experiments={len(outputs)}", flush=True)


if __name__ == "__main__":
    main()
