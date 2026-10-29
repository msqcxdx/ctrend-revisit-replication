#!/usr/bin/env python3
"""Pack, restore, and verify the immutable E01--E11 follow-up result tables.

Only large, already accepted detail tables are split for GitHub's per-file size
limit. The original tables are never edited by ``pack``. ``restore`` refuses to
overwrite a conflicting file, and ``verify`` checks every published E01--E11
artifact against its accepted SHA256 manifest without requiring the run host.
This is artifact restoration, not a model or data-acquisition pipeline.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import tarfile
import tempfile
import threading


ROOT = Path(__file__).resolve().parent
OUT = ROOT / "outputs"
PAYLOAD = ROOT / "result_payload"
CHUNK_BYTES = 64 * 1024 * 1024
PATTERNS = (
    "outputs/E07/all_week_model_support_diagnostics.csv",
    "outputs/E07/asset_week_forecast_holding_stages.csv.gz",
    "outputs/E08/asset_week_direct_contributions.csv.gz",
    "outputs/E10/P?_M1_D?_cohort_asset_weights.csv",
    "outputs/E10/P?_M1_D?_cohort_asset_weights.csv.gz",
    "outputs/E11/forecast_opportunity_grid_P?_D?.csv",
    "outputs/E11/paired_design_cells_P?_D?.csv",
)


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as source:
        for block in iter(lambda: source.read(4 * 1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def bulk_files() -> list[Path]:
    paths = sorted({p for pattern in PATTERNS for p in ROOT.glob(pattern)})
    if len(paths) != 27 or any(not p.is_file() for p in paths):
        raise RuntimeError(f"Expected 27 large detail tables, found {len(paths)}")
    return paths


def verify_published() -> None:
    total = 0
    for number in range(1, 12):
        eid = f"E{number:02d}"
        folder = OUT / eid
        manifest = json.loads((folder / "ARTIFACT_MANIFEST.json").read_text())
        if manifest["experiment_id"] != eid or manifest["artifact_validation"] != "pass":
            raise RuntimeError(f"Invalid accepted manifest: {eid}")
        for artifact in manifest["outputs"]:
            relative = Path(artifact["relative_path"])
            if relative.is_absolute() or ".." in relative.parts:
                raise RuntimeError(f"Unsafe artifact path: {eid}/{relative}")
            path = folder / relative
            if not path.is_file() or path.stat().st_size != artifact["size_bytes"]:
                raise RuntimeError(f"Missing or wrong-sized artifact: {path}")
            if sha256(path) != artifact["sha256"]:
                raise RuntimeError(f"Artifact SHA256 mismatch: {path}")
            total += 1
        print(f"PUBLISHED_ARTIFACTS_OK {eid} files={len(manifest['outputs'])}", flush=True)
    native = OUT / "E07" / "native_failure_audit"
    receipt = json.loads((native / "EXPORT_RECEIPT.json").read_text())
    for name, expected in receipt["files_sha256"].items():
        if sha256(native / name) != expected:
            raise RuntimeError(f"E07 native audit SHA256 mismatch: {name}")
    b02 = json.loads((OUT / "E05" / "receipts" / "b02_remaining_10cells_receipt.json").read_text())
    if b02["status"] != "complete" or sha256(
        OUT / "E05" / "production_b02_daily_future_perturbation_extended.csv"
    ) != b02["output_sha256"]:
        raise RuntimeError("E05 ten-cell b02 receipt mismatch")
    print(f"PUBLISHED_RESULTS_OK experiments=11 files={total} E12=excluded", flush=True)


def pack() -> None:
    if PAYLOAD.exists():
        raise RuntimeError(f"Refusing to replace existing payload: {PAYLOAD}")
    verify_published()
    paths = bulk_files()
    PAYLOAD.mkdir()
    files = [
        {"path": str(path.relative_to(ROOT)), "size_bytes": path.stat().st_size, "sha256": sha256(path)}
        for path in paths
    ]
    compressor = subprocess.Popen(
        ["zstd", "-T4", "-6", "-c"], stdin=subprocess.PIPE, stdout=subprocess.PIPE,
        stderr=subprocess.DEVNULL,
    )
    errors: list[BaseException] = []

    def write_tar() -> None:
        try:
            assert compressor.stdin is not None
            with tarfile.open(fileobj=compressor.stdin, mode="w|") as archive:
                for path in paths:
                    info = archive.gettarinfo(str(path), arcname=str(path.relative_to(ROOT)))
                    info.uid = info.gid = info.mtime = 0
                    info.uname = info.gname = ""
                    with path.open("rb") as source:
                        archive.addfile(info, source)
            compressor.stdin.close()
        except BaseException as exc:  # propagate errors from the producer thread
            errors.append(exc)
            if compressor.stdin is not None:
                compressor.stdin.close()

    producer = threading.Thread(target=write_tar, daemon=True)
    producer.start()
    parts = []
    index = 0
    try:
        assert compressor.stdout is not None
        while block := compressor.stdout.read(CHUNK_BYTES):
            name = f"large_outputs.tar.zst.part{index:03d}"
            destination = PAYLOAD / name
            with destination.open("xb") as target:
                target.write(block)
            parts.append({"name": name, "size_bytes": len(block), "sha256": sha256(destination)})
            index += 1
        producer.join()
        if compressor.wait() or errors or not parts:
            raise RuntimeError(f"Large-output pack failed: {errors}")
        manifest = {
            "format": "ctrend-followup-large-outputs-v1",
            "compression": "tar.zst",
            "chunk_bytes": CHUNK_BYTES,
            "files": files,
            "parts": parts,
            "E12": "excluded_paused_by_user",
        }
        (PAYLOAD / "MANIFEST.json").write_text(json.dumps(manifest, indent=2) + "\n")
        print(f"RESULT_PAYLOAD_PACKED files={len(files)} parts={len(parts)}", flush=True)
    except BaseException:
        compressor.kill()
        compressor.wait()
        raise


def load_payload() -> dict:
    manifest = json.loads((PAYLOAD / "MANIFEST.json").read_text())
    if manifest["format"] != "ctrend-followup-large-outputs-v1":
        raise RuntimeError("Unknown result payload format")
    for part in manifest["parts"]:
        path = PAYLOAD / part["name"]
        if not path.is_file() or path.stat().st_size != part["size_bytes"] or sha256(path) != part["sha256"]:
            raise RuntimeError(f"Split payload failed SHA256 verification: {path}")
    return manifest


def restore() -> None:
    manifest = load_payload()
    expected = {entry["path"]: entry for entry in manifest["files"]}
    for name, entry in expected.items():
        path = ROOT / name
        if path.exists() and (not path.is_file() or path.stat().st_size != entry["size_bytes"]
                              or sha256(path) != entry["sha256"]):
            raise RuntimeError(f"Refusing to overwrite a different file: {path}")
    missing = [name for name in expected if not (ROOT / name).exists()]
    if not missing:
        print("RESULT_PAYLOAD_ALREADY_RESTORED", flush=True)
        return
    with tempfile.TemporaryDirectory(prefix="result_restore_", dir=ROOT) as scratch:
        stage = Path(scratch)
        decoder = subprocess.Popen(["zstd", "-dc"], stdin=subprocess.PIPE,
                                   stdout=subprocess.PIPE, stderr=subprocess.DEVNULL)
        errors: list[BaseException] = []

        def feed_parts() -> None:
            try:
                assert decoder.stdin is not None
                for item in manifest["parts"]:
                    with (PAYLOAD / item["name"]).open("rb") as part:
                        shutil.copyfileobj(part, decoder.stdin)
                decoder.stdin.close()
            except BaseException as exc:
                errors.append(exc)
                if decoder.stdin is not None:
                    decoder.stdin.close()

        feeder = threading.Thread(target=feed_parts, daemon=True)
        feeder.start()
        seen = set()
        assert decoder.stdout is not None
        with tarfile.open(fileobj=decoder.stdout, mode="r|") as archive:
            for item in archive:
                if item.name not in expected or item.name in seen or not item.isfile():
                    raise RuntimeError(f"Unexpected archive member: {item.name}")
                entry = expected[item.name]
                if item.size != entry["size_bytes"]:
                    raise RuntimeError(f"Wrong archived size: {item.name}")
                target = stage / item.name
                target.parent.mkdir(parents=True, exist_ok=True)
                source = archive.extractfile(item)
                if source is None:
                    raise RuntimeError(f"Unreadable archive member: {item.name}")
                with target.open("xb") as output:
                    shutil.copyfileobj(source, output)
                if sha256(target) != entry["sha256"]:
                    raise RuntimeError(f"Archived SHA256 mismatch: {item.name}")
                seen.add(item.name)
        feeder.join()
        if decoder.wait() or errors or seen != set(expected):
            raise RuntimeError(f"Incomplete or corrupt result payload: {errors}")
        for name in missing:
            destination = ROOT / name
            destination.parent.mkdir(parents=True, exist_ok=True)
            os.replace(stage / name, destination)
    print(f"RESULT_PAYLOAD_RESTORED files={len(missing)}", flush=True)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("action", choices=("pack", "restore", "verify"))
    action = parser.parse_args().action
    {"pack": pack, "restore": restore, "verify": verify_published}[action]()
