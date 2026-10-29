#!/usr/bin/env python3
"""Exercise public-file validation before and after documented local setup.

Synthetic helper bytes keep this test independent of third-party material.
The fixture supplies matching helper checksums, then tests incorrect versions,
changed source, and additional files independently.
"""

import hashlib
import importlib.util
from pathlib import Path
import tempfile

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location("public_quickcheck", ROOT / "scripts/public_quickcheck.py")
checks = importlib.util.module_from_spec(spec)
spec.loader.exec_module(checks)


def sha(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def must_reject(expected: str, installed: bool = True) -> None:
    try:
        checks.check_manifest(installed)
    except AssertionError as exc:
        assert expected in str(exc), str(exc)
    else:
        raise AssertionError(f"expected rejection: {expected}")


with tempfile.TemporaryDirectory(prefix="ctrend_installed_inputs_") as temporary:
    root = Path(temporary)
    checks.ROOT = root
    helpers = {
        "regstats2.m": b"% synthetic regression helper\n",
        "parfor_wait.m": b"% synthetic progress helper\n",
    }
    engine_inventory = "".join(f"{sha(data)}  Utils/{name}\n" for name, data in helpers.items()).encode()
    public = {
        "run_all.sh": b"#!/usr/bin/env bash\nexit 0\n",
        "data/RAW_INPUTS.sha256": b"historical input inventory\n",
        "engines/P0_M0/base/PACKAGE_FILES.sha256": engine_inventory,
    }
    for relative, data in public.items():
        path = root / relative
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(data)
    manifest = root / "provenance/PUBLIC_SHA256SUMS"
    manifest.parent.mkdir()
    manifest.write_text("".join(f"{sha(data)}  {relative}\n" for relative, data in public.items()))
    checks.check_manifest(False)

    # Helpers may be installed before or after the local input bundle.
    # Both orders use the eight locations specified by the quickstart.
    for method in ("M0", "M1", "M2", "P0_M0"):
        folder = root / "engines" / method / "base/Utils"
        folder.mkdir(parents=True, exist_ok=True)
        for name, data in helpers.items():
            (folder / name).write_bytes(data)
    checks.check_manifest(True)
    must_reject("public manifest coverage mismatch", installed=False)

    # A local bundle has its own current inventory.
    (root / "data/RAW_INPUTS.sha256").write_bytes(b"installed input inventory\n")
    raw = root / "data/raw/common"
    raw.mkdir(parents=True)
    (raw / "fixture.csv").write_bytes(b"synthetic input\n")
    checks.check_manifest(True)
    must_reject("changed public file: data/RAW_INPUTS.sha256", installed=False)

    helper = root / "engines/M1/base/Utils/regstats2.m"
    helper.write_bytes(b"different helper version\n")
    must_reject("installed helper version differs")
    helper.write_bytes(helpers["regstats2.m"])

    original = root / "engines/M0/base/Utils/regstats2.m"
    helper.unlink()
    helper.symlink_to(original)
    must_reject("invalid installed helper")
    helper.unlink()
    helper.write_bytes(helpers["regstats2.m"])

    (root / "run_all.sh").write_bytes(b"changed source\n")
    must_reject("changed public file: run_all.sh")
    (root / "run_all.sh").write_bytes(public["run_all.sh"])

    extra = root / "engines/M1/base/Utils/unlisted.m"
    extra.write_bytes(b"additional source\n")
    must_reject("public manifest coverage mismatch")
    extra.unlink()
    checks.check_manifest(True)

print("PUBLIC_INSTALLED_INPUTS_TEST_OK required_helpers=8 wrong_version_rejected=1 changed_source_rejected=1")
