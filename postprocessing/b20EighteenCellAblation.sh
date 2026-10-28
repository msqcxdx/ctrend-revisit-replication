#!/usr/bin/env bash
# CTREND_REVISIT_FILE_PURPOSE: Rebuild the eighteen-cell saved-result diagnostics and nineteen-way report without a model rerun.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
python3 "$ROOT/analysis/diagnose_eighteen_accepted_runs.py"
python3 "$ROOT/analysis/compare_eighteen_common_legs.py"
python3 "$ROOT/analysis/render_m1_publication_tables.py"
python3 "$ROOT/analysis/build_nineteen_way_report.py"
python3 "$ROOT/scripts/build_publication_guides.py"
python3 "$ROOT/scripts/build_source_table_manifest.py"
python3 "$ROOT/scripts/build_result_manifest.py"
echo 'B20_SAVED_RESULT_ANALYSIS_OK production_reruns=0'
