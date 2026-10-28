#!/usr/bin/env python3
# CTREND_REVISIT_FILE_PURPOSE: Assemble machine-readable release identity and acceptance metadata from verified package inputs.
import csv
import hashlib
import pathlib
import sys

root = pathlib.Path(sys.argv[1]).resolve()
release = root / "release"
release.mkdir(exist_ok=True)
file_manifest = release / "FILE_MANIFEST.csv"
sha_manifest = release / "SHA256SUMS"
excluded = {file_manifest, sha_manifest}
records = []
for path in sorted(root.rglob("*")):
    if path.is_symlink():
        raise SystemExit(f"release contains symlink: {path}")
    if not path.is_file() or path in excluded:
        continue
    digest = hashlib.sha256(path.read_bytes()).hexdigest()
    records.append((path.relative_to(root).as_posix(), path.stat().st_size, digest))

temporary = file_manifest.with_name(file_manifest.name + ".tmp")
with temporary.open("w", newline="", encoding="utf-8") as handle:
    writer = csv.writer(handle)
    writer.writerow(["relative_path", "size_bytes", "sha256"])
    writer.writerows(records)
temporary.replace(file_manifest)

temporary = sha_manifest.with_name(sha_manifest.name + ".tmp")
with temporary.open("w", encoding="utf-8", newline="\n") as handle:
    for relative, _, digest in records:
        handle.write(f"{digest}  {relative}\n")
temporary.replace(sha_manifest)
print(f"RELEASE_METADATA_OK files={len(records)}")
