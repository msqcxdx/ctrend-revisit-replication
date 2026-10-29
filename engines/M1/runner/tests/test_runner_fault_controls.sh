#!/usr/bin/env bash
# CTREND_REVISIT_FILE_PURPOSE: Exercise M1 phase ownership, heartbeat races, graceful pool drain, orphan cleanup, mutation rejection, and rollback.
set -euo pipefail

RUNNER_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CODE_DIR="$(cd "$RUNNER_DIR/../base" && pwd)"
TEMP_ROOT="$(mktemp -d /tmp/ctrend_runner_fault_test_XXXXXX)"

# shellcheck source=/dev/null
source "$CODE_DIR/run_safety.sh"
# shellcheck source=/dev/null
source "$RUNNER_DIR/b09_heartbeat_policy.sh"

cleanup() {
  local rc=$?
  trap - EXIT INT TERM
  while IFS= read -r -d '' owner; do
    pgid="$(awk -F= '$1=="pgid"{print $2;exit}' "$owner")"
    if [[ "$pgid" =~ ^[1-9][0-9]*$ ]]; then
      kill -KILL -- "-$pgid" 2>/dev/null || true
    fi
  done < <(find "$TEMP_ROOT" -type f -name '*.owner.env' -print0)
  rm -rf -- "$TEMP_ROOT"
  exit "$rc"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

group_exists() {
  local pgid="$1"
  ps -eo pgid= | awk -v expected="$pgid" \
    '$1 == expected { found=1; exit } END { exit !found }'
}

# A stale heartbeat is advisory until it is observed repeatedly. Even after
# confirmation, recent semantic output from a live MATLAB process must defer
# termination. A refreshed heartbeat must cancel the stale decision, while a
# confirmed stale heartbeat with no live client or no recent result must fail
# closed.
[[ "$(ctrend_b09_heartbeat_decision 301 300 1 2 121 5400 1)" == \
   "WARN_STALE" ]] || {
  echo "first stale heartbeat was not treated as a warning" >&2
  exit 1
}
[[ "$(ctrend_b09_heartbeat_decision 301 300 2 2 121 5400 1)" == \
   "DEFER_RECENT_PROGRESS" ]] || {
  echo "recent result progress did not protect a live shard" >&2
  exit 1
}
[[ "$(ctrend_b09_heartbeat_decision 0 300 2 2 121 5400 1)" == \
   "HEALTHY" ]] || {
  echo "a refreshed heartbeat remained stale" >&2
  exit 1
}
[[ "$(ctrend_b09_heartbeat_decision 301 300 2 2 121 5400 0)" == \
   "TERMINATE_CONFIRMED_STALE" ]] || {
  echo "a dead MATLAB client was not rejected after stale confirmation" >&2
  exit 1
}
[[ "$(ctrend_b09_heartbeat_decision 301 300 2 2 5401 5400 1)" == \
   "TERMINATE_CONFIRMED_STALE" ]] || {
  echo "confirmed heartbeat and result stagnation did not fail closed" >&2
  exit 1
}
heartbeat_race="$TEMP_ROOT/heartbeat_race.env"
printf 'updated_epoch=100\n' > "$heartbeat_race"
observed_epoch="$(awk -F= '$1=="updated_epoch"{print $2;exit}' \
  "$heartbeat_race")"
printf 'updated_epoch=401\n' > "$heartbeat_race.tmp"
mv -f -- "$heartbeat_race.tmp" "$heartbeat_race"
confirmed_epoch="$(awk -F= '$1=="updated_epoch"{print $2;exit}' \
  "$heartbeat_race")"
[[ "$(ctrend_b09_heartbeat_refresh_state "$observed_epoch" \
    "$confirmed_epoch" 0 300)" == "REFRESHED" ]] || {
  echo "an atomic heartbeat refresh did not cancel the stale observation" >&2
  exit 1
}
[[ "$(ctrend_b09_heartbeat_refresh_state 100 100 301 300)" == \
   "STILL_STALE" ]] || {
  echo "an unchanged stale heartbeat was falsely refreshed" >&2
  exit 1
}

write_source_inventory() {
  local source_dir="$1"
  (
    cd "$source_dir"
    {
      find . -maxdepth 1 -type f \
        \( -name '*.m' -o -name '*.sh' \) \
        ! -name 'tmp_*' -printf '%P\n'
      for source_subdir in Utils LatexTables tests; do
        if [[ -d "$source_subdir" ]]; then
          find "$source_subdir" -type f \
            \( -name '*.m' -o -name '*.sh' \) \
            ! -name 'tmp_*' -printf '%p\n'
        fi
      done
    } | LC_ALL=C sort | while IFS= read -r relative; do
      digest="$(sha256sum "$relative")"
      printf '%s  %s\n' "${digest%% *}" "$relative"
    done
  )
}

# Every supported shell entry must reject an explicitly invalid worker
# count before creating a run directory or invoking MATLAB.
for invalid_workers in 0 -1 1.5 NaN Inf twelve; do
  invalid_root="$TEMP_ROOT/invalid_workers_$invalid_workers"
  set +e
  CODE_DIR="$invalid_root" MATLAB_BIN=/bin/true \
  PARALLEL_WORKERS="$invalid_workers" \
    "$CODE_DIR/run_full_pipeline_corrected.sh" >/dev/null 2>&1
  invalid_workers_rc=$?
  set -e
  [[ "$invalid_workers_rc" == "2" && ! -e "$invalid_root" ]] || {
    echo "Invalid PARALLEL_WORKERS was not rejected: $invalid_workers" >&2
    exit 1
  }
done

# The ownership record must survive the leader so cleanup can still locate
# a child that the leader left behind.
owner="$TEMP_ROOT/leader_death.owner.env"
token="$(</proc/sys/kernel/random/uuid)"
setsid "$RUNNER_DIR/run_owned_process.sh" \
  "$owner" "$token" "$CODE_DIR" leader_death \
  bash -c 'sleep 30 & exit 0' &
leader=$!
wait "$leader"
pgid="$(awk -F= '$1=="pgid"{print $2;exit}' "$owner")"
[[ "$pgid" == "$leader" ]] || {
  echo "owned-process PGID was not persisted" >&2
  exit 1
}
group_exists "$pgid" || {
  echo "leader-death fixture did not leave its child group" >&2
  exit 1
}
kill -TERM -- "-$pgid"
for _ in $(seq 1 20); do
  group_exists "$pgid" || break
  sleep 0.1
done
group_exists "$pgid" && {
  echo "persisted PGID could not clean a leaderless child" >&2
  exit 1
}

# A successful leader may briefly leave a normally shutting-down child.
# The production grace helper must accept natural drain without sending a
# signal, while still rejecting a genuinely persistent group.
grace_owner="$TEMP_ROOT/natural_drain.owner.env"
grace_token="$(</proc/sys/kernel/random/uuid)"
setsid "$RUNNER_DIR/run_owned_process.sh" \
  "$grace_owner" "$grace_token" "$CODE_DIR" natural_drain \
  bash -c 'sleep 1 & exit 0' &
grace_leader=$!
wait "$grace_leader"
ctrend_wait_for_process_group_exit "$grace_leader" 5 || {
  echo "bounded exit grace rejected a naturally draining child" >&2
  exit 1
}

persistent_owner="$TEMP_ROOT/persistent_group.owner.env"
persistent_token="$(</proc/sys/kernel/random/uuid)"
setsid "$RUNNER_DIR/run_owned_process.sh" \
  "$persistent_owner" "$persistent_token" "$CODE_DIR" persistent_group \
  bash -c 'sleep 30 & exit 0' &
persistent_leader=$!
wait "$persistent_leader"
if ctrend_wait_for_process_group_exit "$persistent_leader" 1; then
  echo "bounded exit grace accepted a persistent child group" >&2
  exit 1
fi
kill -TERM -- "-$persistent_leader" 2>/dev/null || true
for _ in $(seq 1 20); do
  group_exists "$persistent_leader" || break
  sleep 0.1
done
group_exists "$persistent_leader" && {
  echo "persistent grace fixture could not be cleaned" >&2
  exit 1
}

# Exercise the shard-level race seen in production: a successful MATLAB
# leader can exit while a normally shutting-down pool child still owns the
# process group.  The shard must wait for natural drain and seal completion,
# while a child that outlives the bounded grace must still fail closed.
grace_code="$TEMP_ROOT/shard_grace_code"
mkdir -p "$grace_code/Utils" "$grace_code/LatexTables" \
  "$grace_code/tests" "$grace_code/Results/CTREND"
cp -- "$CODE_DIR/run_safety.sh" "$CODE_DIR/DesignChoices.mat" \
  "$grace_code/"
grace_design_sha="$(sha256sum "$grace_code/DesignChoices.mat" |
  awk '{print $1}')"
grace_matlab="$TEMP_ROOT/fake_success_with_draining_pool.sh"
{
  printf '%s\n' '#!/usr/bin/env bash'
  printf '%s\n' 'set -euo pipefail'
  printf '%s\n' 'printf "parallel_workers_active=1\n"'
  printf '%s\n' 'result_dir="$PIPELINE_CODE_DIR/Results/CTREND"'
  printf '%s\n' 'mkdir -p "$result_dir"'
  printf '%s\n' 'printf "fixture\n" > "$result_dir/CTREND_Combo2.mat"'
  printf '%s\n' '(cd "$result_dir" && sha256sum CTREND_Combo2.mat > CTREND_Combo2.mat.sha256)'
  printf '%s\n' 'sleep "${FAKE_POOL_DRAIN_SECONDS:-2}" &'
  printf '%s\n' 'exit 0'
} > "$grace_matlab"
chmod +x "$grace_matlab"

natural_shard="$TEMP_ROOT/natural_drain_shard"
mkdir -p "$natural_shard/logs"
printf '2 2\n' > "$natural_shard/ranges.txt"
write_source_inventory "$grace_code" \
  > "$natural_shard/package_matlab_sources.sha256"
POOL_START_RETRIES=1 \
POOL_START_TIMEOUT_SECONDS=5 \
NO_PROGRESS_TIMEOUT_SECONDS=10 \
HEARTBEAT_INTERVAL_SECONDS=1 \
MATLAB_STOP_GRACE_SECONDS=5 \
B09_JOB_STORAGE_ROOT="$TEMP_ROOT/natural_drain_jobs" \
B09_SHARD_ID=natural_drain \
B09_SHARD_STATE_FILE="$natural_shard/state.env" \
B09_SHARD_HEARTBEAT_FILE="$natural_shard/heartbeat.env" \
B09_SHARD_COMPLETION_FILE="$natural_shard/completion.env" \
EXPECTED_DESIGN_CHOICES_SHA256="$grace_design_sha" \
  "$RUNNER_DIR/run_b09_shard.sh" "$grace_code" \
  "$natural_shard/ranges.txt" natural-drain-run 1 "$grace_matlab" \
  "$natural_shard/logs" >/dev/null
[[ "$(awk -F= '$1=="complete"{print $2;exit}' \
    "$natural_shard/completion.env")" == "1" ]] || {
  echo "naturally draining successful shard was falsely rejected" >&2
  exit 1
}
rg -q 'rc=0 .*timeout_reason=$' "$natural_shard/logs/pipeline.log" || {
  echo "naturally draining shard did not retain MATLAB rc=0" >&2
  exit 1
}

persistent_shard="$TEMP_ROOT/persistent_pool_shard"
mkdir -p "$persistent_shard/logs"
printf '2 2\n' > "$persistent_shard/ranges.txt"
write_source_inventory "$grace_code" \
  > "$persistent_shard/package_matlab_sources.sha256"
set +e
FAKE_POOL_DRAIN_SECONDS=30 \
POOL_START_RETRIES=1 \
POOL_START_TIMEOUT_SECONDS=5 \
NO_PROGRESS_TIMEOUT_SECONDS=10 \
HEARTBEAT_INTERVAL_SECONDS=1 \
MATLAB_STOP_GRACE_SECONDS=1 \
B09_JOB_STORAGE_ROOT="$TEMP_ROOT/persistent_pool_jobs" \
B09_SHARD_ID=persistent_pool \
B09_SHARD_STATE_FILE="$persistent_shard/state.env" \
B09_SHARD_HEARTBEAT_FILE="$persistent_shard/heartbeat.env" \
B09_SHARD_COMPLETION_FILE="$persistent_shard/completion.env" \
EXPECTED_DESIGN_CHOICES_SHA256="$grace_design_sha" \
  "$RUNNER_DIR/run_b09_shard.sh" "$grace_code" \
  "$persistent_shard/ranges.txt" persistent-pool-run 1 "$grace_matlab" \
  "$persistent_shard/logs" >/dev/null 2>&1
persistent_shard_rc=$?
set -e
[[ "$persistent_shard_rc" -ne 0 &&
   ! -f "$persistent_shard/completion.env" ]] || {
  echo "persistent post-success process group was falsely accepted" >&2
  exit 1
}
rg -q 'timeout_reason=residual_matlab_process_group' \
  "$persistent_shard/logs/pipeline.log" || {
  echo "persistent post-success process group lacked failure evidence" >&2
  exit 1
}

# A no-range shard exercises the atomic completion record without starting
# MATLAB or a pool.
shard_root="$TEMP_ROOT/shard"
mkdir -p "$shard_root/logs"
: > "$shard_root/ranges.txt"
write_source_inventory "$CODE_DIR" \
  > "$shard_root/package_matlab_sources.sha256"
design_sha="$(sha256sum "$CODE_DIR/DesignChoices.mat" | awk '{print $1}')"
B09_SHARD_ID=test \
B09_SHARD_STATE_FILE="$shard_root/state.env" \
B09_SHARD_HEARTBEAT_FILE="$shard_root/heartbeat.env" \
B09_SHARD_COMPLETION_FILE="$shard_root/completion.env" \
EXPECTED_DESIGN_CHOICES_SHA256="$design_sha" \
  "$RUNNER_DIR/run_b09_shard.sh" "$CODE_DIR" \
  "$shard_root/ranges.txt" test-run-id 1 /bin/true \
  "$shard_root/logs" >/dev/null
[[ "$(awk -F= '$1=="complete"{print $2;exit}' \
    "$shard_root/completion.env")" == "1" ]] || {
  echo "atomic shard completion record was not published" >&2
  exit 1
}

# A noisy client that reports an active pool but never writes a combo must
# trip the semantic no-progress timeout. Log-byte growth is not progress.
no_progress_root="$TEMP_ROOT/no_progress"
mkdir -p "$no_progress_root/logs"
printf '2 2\n' > "$no_progress_root/ranges.txt"
write_source_inventory "$CODE_DIR" \
  > "$no_progress_root/package_matlab_sources.sha256"
fake_matlab="$TEMP_ROOT/fake_matlab.sh"
{
  printf '%s\n' '#!/usr/bin/env bash'
  printf '%s\n' 'trap "exit 143" TERM INT'
  printf '%s\n' 'printf "parallel_workers_active=1\n"'
  printf '%s\n' 'while true; do printf "noisy_nonsemantic_output\n"; sleep 0.1; done'
} > "$fake_matlab"
chmod +x "$fake_matlab"
set +e
POOL_START_RETRIES=1 \
POOL_START_TIMEOUT_SECONDS=5 \
NO_PROGRESS_TIMEOUT_SECONDS=2 \
HEARTBEAT_INTERVAL_SECONDS=1 \
MATLAB_STOP_GRACE_SECONDS=2 \
B09_JOB_STORAGE_ROOT="$TEMP_ROOT/job_storage" \
B09_SHARD_ID=no_progress \
B09_SHARD_STATE_FILE="$no_progress_root/state.env" \
B09_SHARD_HEARTBEAT_FILE="$no_progress_root/heartbeat.env" \
B09_SHARD_COMPLETION_FILE="$no_progress_root/completion.env" \
EXPECTED_DESIGN_CHOICES_SHA256="$design_sha" \
  "$RUNNER_DIR/run_b09_shard.sh" "$CODE_DIR" \
  "$no_progress_root/ranges.txt" no-progress-run 1 "$fake_matlab" \
  "$no_progress_root/logs" >/dev/null 2>&1
no_progress_rc=$?
set -e
[[ "$no_progress_rc" -ne 0 &&
   ! -f "$no_progress_root/completion.env" ]] || {
  echo "noisy no-progress client was falsely accepted" >&2
  exit 1
}
rg -q 'timeout_reason=no_progress_timeout' \
  "$no_progress_root/logs/pipeline.log" || {
  echo "semantic no-progress timeout was not recorded" >&2
  exit 1
}

# A production shard must stop its own MATLAB process group when its bound
# orchestrator disappears, including an untrappable orchestrator SIGKILL.
orchestrator_loss_root="$TEMP_ROOT/orchestrator_loss"
mkdir -p "$orchestrator_loss_root/logs"
printf '2 2\n' > "$orchestrator_loss_root/ranges.txt"
write_source_inventory "$CODE_DIR" \
  > "$orchestrator_loss_root/package_matlab_sources.sha256"
bash -c 'sleep 2' &
lease_pid=$!
lease_start_ticks="$(awk '{print $22}' "/proc/$lease_pid/stat")"
set +e
POOL_START_RETRIES=1 \
POOL_START_TIMEOUT_SECONDS=10 \
NO_PROGRESS_TIMEOUT_SECONDS=30 \
HEARTBEAT_INTERVAL_SECONDS=1 \
MATLAB_STOP_GRACE_SECONDS=2 \
B09_JOB_STORAGE_ROOT="$TEMP_ROOT/job_storage" \
B09_SHARD_ID=orchestrator_loss \
B09_SHARD_STATE_FILE="$orchestrator_loss_root/state.env" \
B09_SHARD_HEARTBEAT_FILE="$orchestrator_loss_root/heartbeat.env" \
B09_SHARD_COMPLETION_FILE="$orchestrator_loss_root/completion.env" \
B09_ORCHESTRATOR_PID="$lease_pid" \
B09_ORCHESTRATOR_START_TICKS="$lease_start_ticks" \
EXPECTED_DESIGN_CHOICES_SHA256="$design_sha" \
  "$RUNNER_DIR/run_b09_shard.sh" "$CODE_DIR" \
  "$orchestrator_loss_root/ranges.txt" orchestrator-loss-run 1 \
  "$fake_matlab" "$orchestrator_loss_root/logs" >/dev/null 2>&1
orchestrator_loss_rc=$?
set -e
wait "$lease_pid" 2>/dev/null || true
[[ "$orchestrator_loss_rc" -ne 0 &&
   ! -f "$orchestrator_loss_root/completion.env" &&
   "$(awk -F= '$1=="reason"{print $2;exit}' \
      "$orchestrator_loss_root/state.env")" == "orchestrator_lost" ]] || {
  echo "orchestrator loss did not fail closed and stop the shard" >&2
  exit 1
}
lease_matlab_pgid="$(awk -F= '$1=="pgid"{print $2;exit}' \
  "$orchestrator_loss_root/logs/matlab_attempt_1.owner.env")"
if [[ "$lease_matlab_pgid" =~ ^[1-9][0-9]*$ ]] &&
    group_exists "$lease_matlab_pgid"; then
  echo "orchestrator-loss shard retained an orphan MATLAB group" >&2
  exit 1
fi

# A mismatched frozen DesignChoices hash must fail before any shard work.
bad_design_root="$TEMP_ROOT/bad_design"
mkdir -p "$bad_design_root/logs"
: > "$bad_design_root/ranges.txt"
write_source_inventory "$CODE_DIR" \
  > "$bad_design_root/package_matlab_sources.sha256"
set +e
B09_SHARD_ID=bad_design \
B09_SHARD_STATE_FILE="$bad_design_root/state.env" \
B09_SHARD_HEARTBEAT_FILE="$bad_design_root/heartbeat.env" \
B09_SHARD_COMPLETION_FILE="$bad_design_root/completion.env" \
EXPECTED_DESIGN_CHOICES_SHA256="$(printf '0%.0s' {1..64})" \
  "$RUNNER_DIR/run_b09_shard.sh" "$CODE_DIR" \
  "$bad_design_root/ranges.txt" bad-design-run 1 /bin/true \
  "$bad_design_root/logs" >/dev/null 2>&1
bad_design_rc=$?
set -e
[[ "$bad_design_rc" -ne 0 && ! -f "$bad_design_root/completion.env" ]] || {
  echo "DesignChoices hash mutation was not rejected" >&2
  exit 1
}

# Build a clean temporary package, then mutate one extracted executable after
# its inventory was frozen. The shard start gate must reject it.
fixture_package="$TEMP_ROOT/fixture_pipeline.tar.gz"
"$RUNNER_DIR/build_runtime_package.sh" \
  "$fixture_package" >/dev/null
fixture_extract="$TEMP_ROOT/fixture_extract"
mkdir -p "$fixture_extract"
tar -xzf "$fixture_package" -C "$fixture_extract"
fixture_code="$fixture_extract/ctrend_corrected_pipeline"
source_mutation_root="$TEMP_ROOT/source_mutation"
mkdir -p "$source_mutation_root/logs"
: > "$source_mutation_root/ranges.txt"
write_source_inventory "$fixture_code" \
  > "$source_mutation_root/package_matlab_sources.sha256"
printf '\n%% deterministic source mutation\n' >> "$fixture_code/setup.m"
fixture_design_sha="$(sha256sum "$fixture_code/DesignChoices.mat" |
  awk '{print $1}')"
set +e
B09_SHARD_ID=source_mutation \
B09_SHARD_STATE_FILE="$source_mutation_root/state.env" \
B09_SHARD_HEARTBEAT_FILE="$source_mutation_root/heartbeat.env" \
B09_SHARD_COMPLETION_FILE="$source_mutation_root/completion.env" \
EXPECTED_DESIGN_CHOICES_SHA256="$fixture_design_sha" \
  "$RUNNER_DIR/run_b09_shard.sh" "$fixture_code" \
  "$source_mutation_root/ranges.txt" source-mutation-run 1 /bin/true \
  "$source_mutation_root/logs" >/dev/null 2>&1
source_mutation_rc=$?
set -e
[[ "$source_mutation_rc" -ne 0 &&
   ! -f "$source_mutation_root/completion.env" ]] || {
  echo "extracted shard source mutation was not rejected" >&2
  exit 1
}

# A runtime package changed after its SHA was frozen must be rejected before
# launch creates shard state or starts any client.
fixture_package_sha="$(sha256sum "$fixture_package" | awk '{print $1}')"
printf 'mutation' >> "$fixture_package"
set +e
CORRECTED_PACKAGE="$fixture_package" \
CANONICAL_CODE_DIR="$CODE_DIR" \
MATLAB_BIN=/bin/true \
RUN_ROOT="$TEMP_ROOT/package_mutation_run" \
RESULTS_ROOT="$TEMP_ROOT/package_mutation_results" \
EXPECTED_PACKAGE_SHA256="$fixture_package_sha" \
EXPECTED_DESIGN_CHOICES_SHA256="$design_sha" \
FIRST_COMBO=2 LAST_COMBO=5 \
POOL_START_STAGGER_SECONDS=0 \
  "$RUNNER_DIR/launch_b09_shards.sh" >/dev/null 2>&1
package_mutation_rc=$?
set -e
[[ "$package_mutation_rc" -ne 0 &&
   ! -e "$TEMP_ROOT/package_mutation_run" ]] || {
  echo "runtime package mutation was not rejected before shard launch" >&2
  exit 1
}

# The production publication helpers must reject both an original sealed
# source mutation and a post-inventory log mutation.
sealed_source="$TEMP_ROOT/original_source.csv"
printf 'sealed\n' > "$sealed_source"
sealed_sha="$(sha256sum "$sealed_source" | awk '{print $1}')"
source_map="$TEMP_ROOT/source_map.tsv"
printf 'original_source.csv\t%s\t%s\n' "$sealed_sha" "$sealed_source" \
  > "$source_map"
ctrend_verify_source_map "$source_map" \
  "$TEMP_ROOT/source_publish.sha256" 1
printf 'mutation\n' >> "$sealed_source"
if ctrend_verify_source_map "$source_map" \
    "$TEMP_ROOT/source_publish_bad.sha256" 1 >/dev/null 2>&1; then
  echo "original sealed source mutation was not rejected" >&2
  exit 1
fi

inventory_root="$TEMP_ROOT/inventory_root"
mkdir -p "$inventory_root/logs"
printf 'sealed log\n' > "$inventory_root/logs/phase.log"
(
  cd "$inventory_root"
  sha256sum logs/phase.log
) > "$inventory_root/status_inventory.sha256"
ctrend_verify_sha256_inventory \
  "$inventory_root/status_inventory.sha256" "$inventory_root"
printf 'post-seal mutation\n' >> "$inventory_root/logs/phase.log"
if ctrend_verify_sha256_inventory \
    "$inventory_root/status_inventory.sha256" \
    "$inventory_root" >/dev/null 2>&1; then
  echo "post-inventory log mutation was not rejected" >&2
  exit 1
fi

# Exercise the exact atomic rollback primitive used after a failed canonical
# activation resolution check.
canonical_root="$TEMP_ROOT/canonical"
mkdir -p "$canonical_root/old" "$canonical_root/new"
ctrend_atomic_symlink "$canonical_root/old" "$canonical_root/current"
ctrend_atomic_symlink "$canonical_root/new" "$canonical_root/current"
ctrend_atomic_symlink "$canonical_root/old" "$canonical_root/current"
[[ "$(readlink -f "$canonical_root/current")" == \
   "$canonical_root/old" ]] || {
  echo "atomic canonical rollback did not restore the old bundle" >&2
  exit 1
}

# Structural guards lock the remaining failure-window fixes.
rg -q 'current_signature.*!=.*last_signature' \
  "$RUNNER_DIR/run_b09_shard.sh"
if rg -Uq 'current_signature.*!=.*last_signature.*current_log_bytes.*!=' \
    "$RUNNER_DIR/run_b09_shard.sh"; then
  echo "log-byte growth still resets semantic no-progress timeout" >&2
  exit 1
fi
rg -q 'runtime_matlab_sources_after.sha256' \
  "$RUNNER_DIR/run_b09_shard.sh"
rg -q 'orchestrator_lease_is_live' \
  "$RUNNER_DIR/run_b09_shard.sh"
rg -q 'B09_ORCHESTRATOR_START_TICKS' \
  "$RUNNER_DIR/launch_b09_shards.sh"
rg -q 'completion.env' \
  "$RUNNER_DIR/run_production.sh"
rg -q 'B09_STALE_CONFIRMATIONS' \
  "$RUNNER_DIR/run_production.sh"
rg -q 'confirmed_heartbeat_epoch' \
  "$RUNNER_DIR/run_production.sh"
rg -q 'DEFER_RECENT_PROGRESS' \
  "$RUNNER_DIR/run_production.sh"
rg -q 'CANONICAL_START_BUNDLE.*CANONICAL_CURRENT_LINK' \
  "$RUNNER_DIR/run_production.sh"
rg -q 'raw_input_sources_at_publish.sha256' \
  "$RUNNER_DIR/run_production.sh"
rg -q 'runner_source_inventory_at_publish.sha256' \
  "$RUNNER_DIR/run_production.sh"
rg -q 'ctrend_verify_sha256_inventory' \
  "$RUNNER_DIR/run_production.sh"
rg -q 'ctrend_wait_for_process_group_exit' \
  "$RUNNER_DIR/run_production.sh"
rg -q 'PHASE_EXIT_GRACE_SECONDS' \
  "$RUNNER_DIR/run_production.sh"
rg -q 'test_b05_b09_baseline_results; test_figure_b2_results' \
  "$RUNNER_DIR/run_production.sh"
rg -q 'test_table6_results' \
  "$RUNNER_DIR/run_production.sh"
rg -q 'table6_strict_common_week_comparison_pairwise_summary.csv' \
  "$RUNNER_DIR/run_production.sh"
rg -q 'completed=.*3072 percent=.*n_shard_files' \
  "$RUNNER_DIR/run_production.sh" || \
  rg -q 'n_total_completed=.*n_shard_files' \
    "$RUNNER_DIR/run_production.sh"

printf 'RUNNER_FAULT_CONTROL_TESTS_OK\n'
