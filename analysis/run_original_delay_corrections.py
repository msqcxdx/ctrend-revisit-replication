#!/usr/bin/env python3
# CTREND_REVISIT_FILE_PURPOSE: Compare the inherited original-code delay error across the accepted M0/M2 experiments.
"""Recompute only one daily characteristic, with parent identity checks."""

from concurrent.futures import ThreadPoolExecutor
from hashlib import sha256
import json
import os
from pathlib import Path
import subprocess
import sys


ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "followup_research/scripts"))
from accepted_run_roots import accepted_roots  # noqa: E402


RUNS = tuple(f"P{p}_M{m}_D{d}" for p in (0, 1) for m in (0, 2) for d in (0, 1, 2))
OUT = ROOT / "analysis/isolated_corrections/delay"


def digest(path: Path) -> str:
    value = sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            value.update(block)
    return value.hexdigest()


def data_root(run: Path) -> Path:
    directory = run / "data"
    return directory if directory.is_dir() else run / "data.staging"


def run_one(item: tuple[str, Path], matlab: Path) -> dict:
    experiment, parent = item
    preprocess, method, _ = experiment.split("_")
    directory = OUT / experiment
    directory.mkdir(parents=True, exist_ok=True)
    payload = directory / "delay_characteristic_weekly.mat"
    if not payload.is_file():
        expression = ("maxNumCompThreads(28); addpath(fullfile(pwd,'analysis')); "
                      f"recompute_original_delay_weekly('{parent}','{method}',"
                      f"'{preprocess}',"
                      f"'{directory}'); exit(0)")
        command = [str(matlab), "-licmode", "onlinelicensing", "-nodisplay",
                   "-nosplash", "-batch", expression]
        with (directory / "matlab.log").open("w", encoding="utf-8") as log:
            result = subprocess.run(command, cwd=ROOT, stdout=log,
                                    stderr=subprocess.STDOUT, check=False)
        if result.returncode != 0 or "ORIGINAL_DELAY_WEEKLY_CORRECTION_OK" not in \
                (directory / "matlab.log").read_text(encoding="utf-8"):
            raise RuntimeError(f"Original delay comparison failed: {experiment}")
        print(f"ORIGINAL_DELAY_CORRECTED experiment={experiment}", flush=True)
    else:
        print(f"ORIGINAL_DELAY_EXISTING_VERIFY experiment={experiment}", flush=True)
    if payload.stat().st_size < 1024:
        raise ValueError(f"Incomplete corrected delay: {experiment}")
    data = data_root(parent)
    return dict(experiment_id=experiment,
                run_complete_sha256=digest(parent / "RUN_COMPLETE"),
                b01_sha256=digest(data / "b0DataOLHC.mat"),
                b02_weekly_sha256=digest(data / "bCharacteristicsOLHC_Combo1.mat"),
                corrected_delay_sha256=digest(payload))


def main() -> None:
    matlab = Path(os.environ.get("MATLAB_BIN", ""))
    if not matlab.is_file() or not os.access(matlab, os.X_OK):
        raise ValueError("Set MATLAB_BIN to the tested R2023b executable")
    parents = accepted_roots(RUNS)
    with ThreadPoolExecutor(max_workers=4) as pool:
        outputs = list(pool.map(lambda item: run_one(item, matlab), parents.items()))
    receipt = dict(scope="inherited_original_delay_error_M0_M2_weekly_only",
                   matlab_executable_sha256=digest(matlab),
                   function_sha256=digest(ROOT / "analysis/recompute_original_delay_weekly.m"),
                   orchestrator_sha256=digest(Path(__file__)), outputs=outputs)
    (OUT / "ORIGINAL_METHODS_RECEIPT.json").write_text(
        json.dumps(receipt, indent=2)+"\n", encoding="utf-8")
    print(f"ORIGINAL_DELAY_TWELVE_CORRECTIONS_OK experiments={len(outputs)}", flush=True)


if __name__ == "__main__":
    main()
