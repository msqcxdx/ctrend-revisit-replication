"""CMC-only export manifest and reusable checksum validation utilities."""
from __future__ import annotations

import hashlib
import json
import math
from pathlib import Path
import re

CMC_FILES = ("MetaData.mat", "close_cmc.csv", "high_cmc.csv", "low_cmc.csv",
             "market_cap_cmc.csv", "open_cmc.csv", "volume_cmc.csv", "screening_summary.json")
MANIFEST = "DATA_MANIFEST.sha256"


def regular(path):
    """Require a nonempty regular file and reject symlink substitution."""
    if path.is_symlink() or not path.is_file() or path.stat().st_size == 0:
        raise ValueError(f"Missing, empty or non-regular bundle file: {path}")
    return path


def sha256(path):
    """Hash one validated bundle member in bounded memory."""
    digest = hashlib.sha256()
    with regular(path).open("rb") as handle:
        for chunk in iter(lambda: handle.read(4 * 1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def resolve_source(source):
    """Resolve the three supported bundle layouts without guessing a file."""
    source = Path(source)
    for candidate in (source / "DATA", source / "data/raw/common", source):
        if candidate.is_dir():
            return candidate
    raise ValueError(f"Missing bundle directory: {source}")


def inventory(folder, names):
    """Render a deterministic GNU sha256sum-compatible member inventory."""
    return "".join(f"{sha256(folder / name)}  {name}\n" for name in sorted(names))


def write_manifest(folder, names=CMC_FILES):
    """Seal the declared MATLAB installation members, excluding incidental files."""
    folder = Path(folder)
    text = inventory(folder, names)
    (folder / MANIFEST).write_text(text, encoding="utf-8", newline="\n")


def validate_summary(path):
    """Reject screened/debug exports that cannot represent the research universe."""
    summary = json.loads(regular(path).read_text(encoding="utf-8-sig"))
    if summary.get("bundle_format") == "cmc-only-v1":
        if summary.get("keep_all_assets") is not True or summary.get("max_assets", 0) != 0:
            raise ValueError("Research installation requires a full-universe export without debug limits")
        counts = [summary.get(k) for k in ("input_asset_files_seen", "kept_assets", "dropped_assets")]
        if not (all(type(v) is int and v >= 0 for v in counts) and counts[0] == counts[1] and counts[2] == 0):
            raise ValueError("Research installation requires all input assets to be retained")
    for field in ("exclude_stablecoins", "strict_contiguous"):
        if summary.get(field) is not False:
            raise ValueError(f"Full research inputs require {field}=false")
    threshold = summary.get("min_marketcap")
    if isinstance(threshold, bool) or not isinstance(threshold, (int, float)) or not math.isfinite(threshold) or threshold < 0:
        raise ValueError("Missing or invalid min_marketcap in screening summary")
    if threshold > 0:
        counts = [summary.get(k) for k in ("input_asset_files_seen", "kept_assets", "dropped_assets")]
        if not (summary.get("keep_all_assets") is True and all(type(v) is int and v >= 0 for v in counts)
                and counts[0] == counts[1] and counts[2] == 0):
            raise ValueError("A configured market-cap threshold requires proof that all assets were kept")
    return summary


def verify(source, names=CMC_FILES):
    """Validate manifest syntax, exact membership, hashes and screening policy."""
    folder = resolve_source(source)
    expected = set(names)
    entries = {}
    for line in regular(folder / MANIFEST).read_text(encoding="utf-8").splitlines():
        match = re.fullmatch(r"([0-9a-fA-F]{64})  ([^/\\]+)", line)
        if not match or match[2] not in expected or match[2] in entries:
            raise ValueError("Invalid, duplicate or unexpected manifest entry")
        entries[match[2]] = match[1].lower()
    if set(entries) != expected:
        raise ValueError(f"Incomplete bundle manifest; missing: {sorted(expected - set(entries))}")
    for name, digest in entries.items():
        if sha256(folder / name) != digest:
            raise ValueError(f"Bundle checksum mismatch: {name}")
    return folder
