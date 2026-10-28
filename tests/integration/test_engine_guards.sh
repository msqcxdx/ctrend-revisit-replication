#!/usr/bin/env bash
# CTREND_REVISIT_FILE_PURPOSE: Run every method-specific static, topology, inventory, and fault-control guard.
# Suite-level fan-in for guards owned by all three engines. Any child failure
# blocks release; this file does not start a MATLAB production pipeline.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

# M0/M2 cover 8×15 topology; M1 also covers profiles and fault controls.
"$ROOT/engines/M0/runner/tests/test_topology.sh"
"$ROOT/engines/M0/runner/tests/test_result_inventory_working_directory.sh"
"$ROOT/engines/M1/base/tests/test_v2_static_guards.sh"
"$ROOT/engines/M1/runner/tests/test_b09_profiles.sh"
"$ROOT/engines/M1/runner/tests/test_runner_fault_controls.sh"
"$ROOT/engines/M2/runner/tests/test_topology.sh"
"$ROOT/engines/M2/runner/tests/test_m2_static_guards.sh" \
  "$ROOT/engines/M2/base"

echo 'ENGINE_GUARD_TESTS_OK m0_topology=8x15 m0_inventory=1 m1_static=1 m1_profiles=1 m1_fault_controls=1 m2_static=1 m2_topology=8x15'
