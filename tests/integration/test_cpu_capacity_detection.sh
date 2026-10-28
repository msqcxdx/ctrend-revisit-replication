#!/usr/bin/env bash
# CTREND_REVISIT_FILE_PURPOSE: Verify CPU detection remains correct under production OpenMP limits and affinity constraints.
# MATLAB/BLAS thread caps must not reduce the outer CPU probe to one, while a
# real scheduler affinity limit must still be honored. No scientific work runs.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

BASELINE="$(env -u OMP_NUM_THREADS -u OMP_THREAD_LIMIT nproc)"
[[ "$BASELINE" =~ ^[1-9][0-9]*$ ]]

# This is the exact environment inherited by the production runner after the
# launcher constrains every MATLAB/BLAS process to a single native thread.
RESTORED="$(OMP_NUM_THREADS=1 OMP_THREAD_LIMIT=1 \
  env -u OMP_NUM_THREADS -u OMP_THREAD_LIMIT nproc)"
[[ "$RESTORED" == "$BASELINE" ]] || {
  echo "OpenMP-safe CPU probe returned $RESTORED instead of $BASELINE" >&2
  exit 1
}

# The repair must not use nproc --all: a one-CPU affinity must remain one.
AFFINITY_CHECK=unavailable
if command -v taskset >/dev/null 2>&1; then
  FIRST_CPU="$(awk -F '[-,]' '/Cpus_allowed_list/{gsub(/[[:space:]]/,"",$2); print $2; exit}' \
    /proc/self/status)"
  [[ "$FIRST_CPU" =~ ^[0-9]+$ ]]
  RESTRICTED="$(OMP_NUM_THREADS=1 OMP_THREAD_LIMIT=1 \
    taskset -c "$FIRST_CPU" env -u OMP_NUM_THREADS -u OMP_THREAD_LIMIT nproc)"
  [[ "$RESTRICTED" == 1 ]] || {
    echo "CPU probe ignored a one-CPU affinity: $RESTRICTED" >&2
    exit 1
  }
  AFFINITY_CHECK=passed
fi

# Execute the real M0 runner through its capacity gate under the inherited
# production environment.  A deliberately absent package must be the first
# failure; the historical regression instead failed one line earlier with
# OLD_B02_PARALLEL_WORKERS ... 1..nproc.
TMP="$(mktemp -d /tmp/cttrend_cpu_capacity_test_XXXXXX)"
cleanup() { rm -rf -- "$TMP"; }
trap cleanup EXIT
if (( BASELINE > 1 )); then
  M0_WORKERS=$((BASELINE - 1))
else
  M0_WORKERS=1
fi
set +e
OMP_NUM_THREADS=1 OMP_THREAD_LIMIT=1 \
OLD_B02_PARALLEL_WORKERS="$M0_WORKERS" \
MATLAB_BIN=/bin/true \
SOURCE_DIR="$ROOT/engines/M0/base" \
RUN_BASE="$TMP/runs" JOB_STORAGE_ROOT="$TMP/jobs" \
  "$ROOT/engines/M0/runner/run_production.sh" \
    "$TMP/intentionally_absent_runtime_package.tar.gz" \
    > "$TMP/m0_probe.log" 2>&1
M0_PROBE_RC=$?
set -e
[[ "$M0_PROBE_RC" -eq 2 ]]
grep -Fq 'old v2 package, raw seed, or MATLAB is missing' "$TMP/m0_probe.log"
if grep -Fq 'OLD_B02_PARALLEL_WORKERS must be an integer in 1..nproc' \
    "$TMP/m0_probe.log"; then
  echo 'Real M0 runner still misread OpenMP thread count as host capacity' >&2
  exit 1
fi

grep -Fq 'HOST_NPROC="$(env -u OMP_NUM_THREADS -u OMP_THREAD_LIMIT nproc)"' \
  "$ROOT/scripts/run_experiment.sh"
grep -Fq 'HOST_NPROC="$(env -u OMP_NUM_THREADS -u OMP_THREAD_LIMIT nproc)"' \
  "$ROOT/engines/M0/runner/run_production.sh"
grep -Fq 'HOST_NPROC="$(env -u OMP_NUM_THREADS -u OMP_THREAD_LIMIT nproc)"' \
  "$ROOT/engines/M1/runner/run_production.sh"
grep -Fq 'HOST_NPROC="$(env -u OMP_NUM_THREADS -u OMP_THREAD_LIMIT nproc)"' \
  "$ROOT/engines/M2/runner/run_production.sh"
grep -Fq 'PARALLEL_WORKERS="${PARALLEL_WORKERS:-$(env -u OMP_NUM_THREADS -u OMP_THREAD_LIMIT nproc)}"' \
  "$ROOT/engines/M1/base/run_full_pipeline_corrected.sh"
grep -Fq 'echo "nproc=$HOST_NPROC"' \
  "$ROOT/engines/M0/runner/run_production.sh"
grep -Fq "printf 'nproc=%s\\n' \"\$HOST_NPROC\"" \
  "$ROOT/engines/M1/runner/run_production.sh"

for file in \
    "$ROOT/scripts/run_experiment.sh" \
    "$ROOT/engines/M0/runner/run_production.sh" \
    "$ROOT/engines/M1/runner/run_production.sh" \
    "$ROOT/engines/M2/runner/run_production.sh" \
    "$ROOT/engines/M1/base/run_full_pipeline_corrected.sh"; do
  if rg -n '\$\(nproc\)' "$file"; then
    echo "production CPU consumer still uses an OpenMP-sensitive bare nproc: $file" >&2
    exit 1
  fi
done

echo "CPU_CAPACITY_DETECTION_TEST_OK baseline=$BASELINE omp_restored=$RESTORED affinity=$AFFINITY_CHECK real_m0_gate=passed nproc_all_forbidden=1 consumers=5"
