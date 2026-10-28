#!/usr/bin/env bash
# CTREND_REVISIT_FILE_PURPOSE: Independently check the saved compact results, identities, week support, and paper/report evidence on request.
# This optional audit is separate from code/data preflight and release creation.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
for test_file in test_curated_result_snapshot.py test_result_identity_links.py \
    test_revised_week_support_snapshot.py test_publication_evidence.py \
    test_analytical_publication_tables.py; do
  "${PYTHON_BIN:-python3}" "$ROOT/tests/result_checks/$test_file"
done
echo 'SAVED_RESULT_AUDIT_OK'
