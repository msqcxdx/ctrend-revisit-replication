#!/usr/bin/env python3
# CTREND_REVISIT_FILE_PURPOSE: Inventory the compact accepted result snapshot and generated reports with deterministic SHA256 membership.
from pathlib import Path
import hashlib
root=Path(__file__).resolve().parents[1]/'results'
out=root/'MANIFEST.sha256'
members=sorted(p for p in root.rglob('*') if p.is_file() and p!=out and '__pycache__' not in p.parts)
out.write_text(''.join(f'{hashlib.sha256(p.read_bytes()).hexdigest()}  {p.relative_to(root)}\n' for p in members))
print('RESULT_MANIFEST_OK',len(members))
