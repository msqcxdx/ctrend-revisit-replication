#!/usr/bin/env python3
# CTREND_REVISIT_FILE_PURPOSE: Recompute every diff opcode independently and require exhaustive lineage coverage.
# Thin entry point by design: ``coverage`` mode independently recomputes all
# Dataverse→M0, M0→M2/M1, P0/P1, and D-overlay changed blocks.
from pmd_annotation_contract import check
check('coverage')
