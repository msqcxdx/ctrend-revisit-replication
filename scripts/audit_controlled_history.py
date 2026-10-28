#!/usr/bin/env python3
"""Read-only scan of all local Git objects; print counts, never matched secrets.

Use against the controlled source before public export. The public repository
has a new history, so this is a risk record, not a history-rewrite tool.
"""

import argparse
import re
import subprocess
from pathlib import Path

SECRET_PATTERNS = {
    "github_classic_token": re.compile(rb"ghp_[A-Za-z0-9]{20,}"),
    "github_fine_grained_token": re.compile(rb"github_pat_[A-Za-z0-9_]{20,}"),
    "aws_access_key": re.compile(rb"AKIA[0-9A-Z]{16}"),
    "openai_style_key": re.compile(rb"sk-[A-Za-z0-9_-]{20,}"),
    "private_key_pem": re.compile(rb"-----BEGIN (?:RSA |OPENSSH |EC |DSA )?PRIVATE KEY-----"),
}
PATH_PATTERN = re.compile(rb"/(?:home|data[0-9]+|mnt)/[A-Za-z0-9_./-]+")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("source", type=Path)
    args = parser.parse_args()
    source = args.source.resolve()
    names = subprocess.check_output(["git", "-C", str(source), "rev-list", "--objects", "--all"], text=True)
    known = {row.split(" ", 1)[0]: row.split(" ", 1)[1] if " " in row else "" for row in names.splitlines()}
    command = ["git", "-C", str(source), "cat-file", "--batch-all-objects", "--batch"]
    proc = subprocess.Popen(command, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    assert proc.stdout is not None
    objects = blobs = bytes_scanned = path_blob_count = 0
    hits: dict[str, list[tuple[str, str]]] = {name: [] for name in SECRET_PATTERNS}
    while header := proc.stdout.readline():
        oid, kind, size_text = header.decode("ascii").strip().split()
        size = int(size_text)
        objects += 1
        if kind == "blob":
            blobs += 1
        tail = b""
        path_hit = False
        remaining = size
        while remaining:
            chunk = proc.stdout.read(min(1024 * 1024, remaining))
            if not chunk:
                raise RuntimeError("truncated cat-file stream")
            remaining -= len(chunk)
            if kind == "blob":
                data = tail + chunk
                bytes_scanned += len(chunk)
                if PATH_PATTERN.search(data):
                    path_hit = True
                for label, pattern in SECRET_PATTERNS.items():
                    if pattern.search(data) and not any(item[0] == oid for item in hits[label]):
                        hits[label].append((oid, known.get(oid, "<unmapped>")))
                tail = data[-256:]
        if proc.stdout.read(1) != b"\n":
            raise RuntimeError("invalid cat-file separator")
        path_blob_count += int(kind == "blob" and path_hit)
    error = proc.stderr.read().decode("utf-8", errors="replace") if proc.stderr else ""
    if proc.wait() != 0:
        raise RuntimeError(f"git cat-file failed: {error}")
    print(f"HISTORY_SCAN objects={objects} blobs={blobs} blob_bytes={bytes_scanned} path_marker_blobs={path_blob_count}")
    for label, matches in hits.items():
        print(f"CANDIDATE_CLASS {label} count={len(matches)}")
        for oid, path in matches[:10]:
            print(f"CANDIDATE_OBJECT {label} oid={oid} path={path}")
    print("HISTORY_SCAN_NOTE only high-confidence token patterns; human review and prior external copies remain separate")


if __name__ == "__main__":
    main()
