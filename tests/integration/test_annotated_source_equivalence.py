#!/usr/bin/env python3
# CTREND_REVISIT_FILE_PURPOSE: Verify exact canonical bodies of all eighteen comment-only mirrors.
# Thin entry point by design: the shared verifier compares every executable
# mirror byte-for-byte after removing only its generated comment header.
from pmd_annotation_contract import check
check('bodies')
