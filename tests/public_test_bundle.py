#!/usr/bin/env python3
"""Exercise the rights-cleared CMC bundle interface with synthetic bytes only."""

import json
from pathlib import Path
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "cmc_acquisition"))
from bundle import CMC_FILES, validate_summary, verify, write_manifest


with tempfile.TemporaryDirectory(prefix="ctrend_public_bundle_") as temporary:
    folder = Path(temporary)
    for name in CMC_FILES:
        if name == "screening_summary.json":
            continue
        (folder / name).write_bytes(f"synthetic fixture for {name}\n".encode())
    summary = dict(bundle_format="cmc-only-v1", keep_all_assets=True, max_assets=0,
                   input_asset_files_seen=2, kept_assets=2, dropped_assets=0,
                   exclude_stablecoins=False, strict_contiguous=False, min_marketcap=0)
    screening = folder / "screening_summary.json"
    screening.write_text(json.dumps(summary), encoding="utf-8")
    write_manifest(folder)
    assert verify(folder) == folder
    original = (folder / "close_cmc.csv").read_bytes()
    (folder / "close_cmc.csv").write_bytes(b"tampered\n")
    try:
        verify(folder)
    except ValueError as exc:
        assert "checksum mismatch" in str(exc)
    else:
        raise AssertionError("modified synthetic quote escaped bundle checksum")
    (folder / "close_cmc.csv").write_bytes(original)
    summary["keep_all_assets"] = False
    screening.write_text(json.dumps(summary), encoding="utf-8")
    try:
        validate_summary(screening)
    except ValueError as exc:
        assert "full-universe" in str(exc)
    else:
        raise AssertionError("screened synthetic bundle escaped full-universe gate")
print("PUBLIC_BUNDLE_INTERFACE_TEST_OK fixture=synthetic provider_download_not_tested=1")
