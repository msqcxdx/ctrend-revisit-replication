# CTREND_REVISIT_FILE_PURPOSE: Install and verify CMC exports with separately obtained research auxiliary inputs.
"""Install research inputs from a CMC export and separately obtained auxiliary data."""
from __future__ import annotations

import argparse
from pathlib import Path
import shutil
import sys
import tempfile

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "cmc_acquisition"))
from bundle import (CMC_FILES, MANIFEST, inventory, regular, resolve_source,
                    sha256, validate_summary, verify, write_manifest)

AUX_FILES = ("F-F_Research_Data_Factors_daily.CSV", "LTW_3factor.xlsx", "UCRY.csv")
FULL_FILES = tuple(sorted(CMC_FILES + AUX_FILES))


def preflight(root):
    root = Path(root)
    folder = verify(root / "data/raw/common", FULL_FILES)
    validate_summary(folder / "screening_summary.json")
    expected = inventory(folder, FULL_FILES)
    installed = regular(root / "data/RAW_INPUTS.sha256").read_text(encoding="utf-8")
    # The accepted historical inventory uses a different ordering.
    if sorted(installed.splitlines()) != sorted(expected.splitlines()):
        raise ValueError("RAW_INPUTS.sha256 does not cover the exact installed bundle")
    print("DATA_PREFLIGHT_OK files=11 checksums=verified screening=unscreened")


def install(source, root, aux_data_dir=None):
    if aux_data_dir is None:
        # Keep accepted legacy complete bundles installable without repacking.
        source = verify(source, FULL_FILES)
        inputs = {name: source / name for name in FULL_FILES}
    else:
        source = verify(source)
        auxiliary = resolve_source(aux_data_dir)
        inputs = {name: source / name for name in CMC_FILES}
        inputs.update({name: auxiliary / name for name in AUX_FILES})
    validate_summary(source / "screening_summary.json")
    source_hashes = {name: sha256(path) for name, path in inputs.items()}
    root = Path(root)
    target = root / "data/raw/common"
    if target.is_symlink():
        raise ValueError("Installation target must not be a symlink")
    for name, digest in source_hashes.items():
        path = target / name
        if (path.exists() or path.is_symlink()) and sha256(path) != digest:
            raise ValueError(f"Installed input differs: {name}; use an empty work checkout")
    (root / "data").mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix=".bundle-", dir=root / "data") as temporary:
        staged = Path(temporary)
        for name, path in inputs.items():
            shutil.copyfile(path, staged / name)
            if sha256(staged / name) != source_hashes[name]:
                raise ValueError(f"Input changed during installation: {name}")
        if aux_data_dir is None:
            shutil.copyfile(source / MANIFEST, staged / MANIFEST)
        else:
            write_manifest(staged, FULL_FILES)
        verify(staged, FULL_FILES)
        if (target / MANIFEST).exists() or (target / MANIFEST).is_symlink():
            if sha256(target / MANIFEST) != sha256(staged / MANIFEST):
                raise ValueError("Installed manifest differs; use an empty work checkout")
        target.mkdir(parents=True, exist_ok=True)
        for name in FULL_FILES + (MANIFEST,):
            if not (target / name).exists():
                (staged / name).replace(target / name)
    text = inventory(target, FULL_FILES)
    temporary = root / "data/RAW_INPUTS.sha256.tmp"
    temporary.write_text(text, encoding="utf-8", newline="\n")
    temporary.replace(root / "data/RAW_INPUTS.sha256")
    preflight(root)
    print("REQUIRED_DATA_INSTALLED")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest="command", required=True)
    p = sub.add_parser("install")
    p.add_argument("--source", required=True)
    p.add_argument("--aux-data-dir", help="Separately obtained auxiliary inputs; omit only for a legacy complete bundle")
    p.add_argument("--root", required=True)
    p = sub.add_parser("preflight")
    p.add_argument("--root", required=True)
    args = parser.parse_args()
    try:
        if args.command == "install":
            install(args.source, args.root, args.aux_data_dir)
        else:
            preflight(args.root)
    except (ValueError, OSError) as exc:
        parser.exit(2, f"DATA_BUNDLE_ERROR: {exc}\n")


if __name__ == "__main__":
    main()
