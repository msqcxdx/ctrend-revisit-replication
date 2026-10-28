#!/usr/bin/env python3
# CTREND_REVISIT_FILE_PURPOSE: Seal deliberately prepared publication source tables without changing experiments or their original member identities.
"""Maintainer action after reviewing source-table edits; never run in preflight."""
from pathlib import Path
import hashlib

root = Path(__file__).resolve().parents[1]
source = root / 'results/comparisons/source_tables'
ledger = root / 'provenance/accepted_18/source_table_export.sha256.txt'
members = sorted(p for p in source.rglob('*') if p.is_file())
ledger.write_text(''.join(f'{hashlib.sha256(p.read_bytes()).hexdigest()}  {p.relative_to(source)}\n' for p in members))
print(f'SOURCE_TABLE_MANIFEST_READY files={len(members)}')
