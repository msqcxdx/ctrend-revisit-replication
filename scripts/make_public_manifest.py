#!/usr/bin/env python3
"""Write deterministic hashes for every public file except this inventory and Git internals."""

import hashlib
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
OUTPUT = ROOT / "provenance/PUBLIC_SHA256SUMS"
EXCLUDED_DIRS = {".git", "__pycache__", ".pytest_cache", ".venv", "runtime", "outputs"}


def digest(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            h.update(block)
    return h.hexdigest()


def main() -> None:
    rows = []
    for path in sorted(ROOT.rglob("*")):
        parts = path.relative_to(ROOT).parts
        if not path.is_file() or path == OUTPUT or EXCLUDED_DIRS.intersection(parts) or parts[:2] == ("data", "raw"):
            continue
        if path.is_symlink():
            raise SystemExit(f"refusing symlink: {path}")
        rows.append(f"{digest(path)}  {path.relative_to(ROOT).as_posix()}")
    OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    OUTPUT.write_text("\n".join(rows) + "\n", encoding="utf-8")
    print(f"PUBLIC_MANIFEST_OK files={len(rows)}")


if __name__ == "__main__":
    main()
