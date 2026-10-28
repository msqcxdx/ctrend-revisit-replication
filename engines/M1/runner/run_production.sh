#!/usr/bin/env bash
# CTREND_REVISIT_FILE_PURPOSE: Execute the complete M1 pipeline with immutable staging, parallel b09, validation, and atomic publication.
set -euo pipefail

RUNNER_SOURCE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SOURCE_PROJECT_DIR="$(cd "$RUNNER_SOURCE_DIR/.." && pwd)"
SOURCE_CODE_DIR_BOOTSTRAP="$(realpath -m -- \
  "${CODE_DIR:-$SOURCE_PROJECT_DIR/base}")"

# Bind the complete operational runner suite before acquiring a lock,
# changing canonical aliases, or creating a run root. Source files are
# hashed before and after the copy; the bound snapshot is the only suite
# executed for the remainder of the run.
if [[ "${CTREND_RUNNER_BOUND:-0}" != "1" ]]; then
  runner_snapshot_root="$(mktemp -d /tmp/cttrend_bound_runner_XXXXXX)"
  runner_snapshot_dir="$runner_snapshot_root/b09_parallel_runner"
  mkdir -p "$runner_snapshot_dir"
  source_inventory_before="$runner_snapshot_root/source_before.sha256"
  source_inventory_after="$runner_snapshot_root/source_after.sha256"
  snapshot_inventory="$runner_snapshot_root/snapshot.sha256"
  (
    cd "$RUNNER_SOURCE_DIR"
    find . -maxdepth 1 -type f \
      \( -name '*.sh' -o -name '*.m' \) -printf '%P\n' |
      LC_ALL=C sort | xargs -r sha256sum
    sha256sum "$SOURCE_CODE_DIR_BOOTSTRAP/run_safety.sh"
  ) > "$source_inventory_before"
  find "$RUNNER_SOURCE_DIR" -maxdepth 1 -type f \
    \( -name '*.sh' -o -name '*.m' \) -exec cp -- {} \
      "$runner_snapshot_dir/" \;
  cp -- "$SOURCE_CODE_DIR_BOOTSTRAP/run_safety.sh" \
    "$runner_snapshot_dir/run_safety.sh"
  (
    cd "$RUNNER_SOURCE_DIR"
    find . -maxdepth 1 -type f \
      \( -name '*.sh' -o -name '*.m' \) -printf '%P\n' |
      LC_ALL=C sort | xargs -r sha256sum
    sha256sum "$SOURCE_CODE_DIR_BOOTSTRAP/run_safety.sh"
  ) > "$source_inventory_after"
  cmp -s "$source_inventory_before" "$source_inventory_after" || {
    echo "Runner source changed while it was being bound" >&2
    rm -rf -- "$runner_snapshot_root"
    exit 2
  }
  (
    cd "$runner_snapshot_dir"
    find . -maxdepth 1 -type f -printf '%P\n' |
      LC_ALL=C sort | xargs -r sha256sum
  ) > "$snapshot_inventory"
  export CTREND_RUNNER_BOUND=1
  export CTREND_RUNNER_SNAPSHOT_ROOT="$runner_snapshot_root"
  export CTREND_RUNNER_SOURCE_DIR="$RUNNER_SOURCE_DIR"
  export CTREND_SOURCE_PROJECT_DIR="$SOURCE_PROJECT_DIR"
  exec "$runner_snapshot_dir/run_production.sh" "$@"
fi

RUNNER_SNAPSHOT_ROOT="$CTREND_RUNNER_SNAPSHOT_ROOT"
RUNNER_DIR="$RUNNER_SNAPSHOT_ROOT/b09_parallel_runner"
RUNNER_SOURCE_DIR="$CTREND_RUNNER_SOURCE_DIR"
PROJECT_DIR="$CTREND_SOURCE_PROJECT_DIR"
SOURCE_CODE_DIR="$(realpath -m -- \
  "${CODE_DIR:-$PROJECT_DIR/base}")"
MATLAB_BIN="${MATLAB_BIN:-$(command -v matlab 2>/dev/null || true)}"
RUNTIME_PACKAGE="${1:-${CORRECTED_PACKAGE:-}}"
INPUT_RUNTIME_PACKAGE="$RUNTIME_PACKAGE"
RUN_STAMP="$(date -u +%Y%m%d_%H%M%S_%N)_$$"
RUN_BASE="$(realpath -m -- \
  "${RUN_BASE:-$PROJECT_DIR/runtime/runs}")"
RUN_ROOT="$(realpath -m -- \
  "${RUN_ROOT:-$RUN_BASE/corrected_v2_$RUN_STAMP}")"
LOG_ROOT="$RUN_ROOT/logs"
RUNTIME_EXTRACT_ROOT="$RUN_ROOT/runtime"
CODE_DIR="$RUNTIME_EXTRACT_ROOT/cttrend_corrected_pipeline"
STAGING_DATA="$RUN_ROOT/data.staging"
PUBLISHED_DATA="$RUN_ROOT/data"
STAGING_RESULTS="$RUN_ROOT/results.staging"
PUBLISHED_RESULTS="$RUN_ROOT/results"
SHARD_RUN_ROOT="$RUN_ROOT/b09_shards"
SHARD_RESULTS_ROOT="$RUN_ROOT/b09_shard_results"
CANONICAL_ROOT="$SOURCE_CODE_DIR/.canonical"
CANONICAL_CURRENT_LINK="$CANONICAL_ROOT/current"
CANONICAL_DATA_ALIAS=".canonical/current/data"
CANONICAL_RESULTS_ALIAS=".canonical/current/results"
CANONICAL_DESIGN_ALIAS=".canonical/current/DesignChoices.mat"
RESEARCH_RUN_ID="${RESEARCH_RUN_ID:-$(</proc/sys/kernel/random/uuid)}"
JOB_STORAGE_ROOT="$(realpath -m -- \
  "${JOB_STORAGE_ROOT:-$PROJECT_DIR/runtime/job_storage/$RUN_STAMP}")"
JOB_STORAGE_ALLOWED_ROOT="$(realpath -m -- \
  "${JOB_STORAGE_ALLOWED_ROOT:-$(dirname "$JOB_STORAGE_ROOT")}")"
POOL_START_TIMEOUT_SECONDS="${POOL_START_TIMEOUT_SECONDS:-2100}"
NO_PROGRESS_TIMEOUT_SECONDS="${NO_PROGRESS_TIMEOUT_SECONDS:-5400}"
HEARTBEAT_INTERVAL_SECONDS="${HEARTBEAT_INTERVAL_SECONDS:-60}"
B09_HEARTBEAT_STALE_SECONDS="${B09_HEARTBEAT_STALE_SECONDS:-300}"
B09_STALE_CONFIRMATIONS="${B09_STALE_CONFIRMATIONS:-2}"
B09_MONITOR_INTERVAL_SECONDS="${B09_MONITOR_INTERVAL_SECONDS:-60}"
SHARD_STOP_GRACE_SECONDS="${SHARD_STOP_GRACE_SECONDS:-180}"
PHASE_STOP_GRACE_SECONDS="${PHASE_STOP_GRACE_SECONDS:-180}"
PHASE_EXIT_GRACE_SECONDS="${PHASE_EXIT_GRACE_SECONDS:-180}"
POOL_START_STAGGER_SECONDS="${POOL_START_STAGGER_SECONDS:-30}"
B09_NUM_SHARDS="${B09_NUM_SHARDS:-8}"
B09_WORKERS_PER_SHARD="${B09_WORKERS_PER_SHARD:-15}"
CORE_START_STEP="${CORE_START_STEP:-setup}"
STARTED_AT="$(date -Is)"
HOST_NPROC="$(env -u OMP_NUM_THREADS -u OMP_THREAD_LIMIT nproc)"

case "$B09_NUM_SHARDS:$B09_WORKERS_PER_SHARD" in
  4:31|8:15) ;;
  *) echo "B09 profile must be audited 4x31 or 8x15" >&2; exit 2 ;;
esac

# shellcheck source=/dev/null
source "$RUNNER_DIR/run_safety.sh"
# shellcheck source=/dev/null
source "$RUNNER_DIR/b09_heartbeat_policy.sh"

remove_bound_runner_snapshot() {
  local resolved
  resolved="$(readlink -f "$RUNNER_SNAPSHOT_ROOT" 2>/dev/null || true)"
  [[ "$resolved" == /tmp/cttrend_bound_runner_* &&
     -d "$resolved/b09_parallel_runner" ]] || {
    echo "Refusing to remove invalid runner snapshot: $RUNNER_SNAPSHOT_ROOT" >&2
    return 1
  }
  rm -rf -- "$resolved"
}

cleanup_bootstrap_only() {
  local rc=$?
  trap - EXIT INT TERM
  remove_bound_runner_snapshot || rc=1
  exit "$rc"
}
trap cleanup_bootstrap_only EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

if [[ "${CTREND_RUNNER_PREFLIGHT_ONLY:-0}" == "1" ]]; then
  preflight_snapshot_inventory="$RUNNER_SNAPSHOT_ROOT/preflight_snapshot.sha256"
  (
    cd "$RUNNER_DIR"
    find . -maxdepth 1 -type f -printf '%P\n' |
      LC_ALL=C sort | xargs -r sha256sum
  ) > "$preflight_snapshot_inventory"
  cmp -s "$RUNNER_SNAPSHOT_ROOT/snapshot.sha256" \
    "$preflight_snapshot_inventory" || {
    echo "Bound runner snapshot changed before preflight validation" >&2
    exit 2
  }
  cmp -s "$RUNNER_SNAPSHOT_ROOT/source_before.sha256" \
    "$RUNNER_SNAPSHOT_ROOT/source_after.sha256" || {
    echo "Runner source was not stable during snapshot creation" >&2
    exit 2
  }
  [[ -x "$MATLAB_BIN" ]] || {
    echo "MATLAB is not executable: $MATLAB_BIN" >&2
    exit 2
  }
  [[ -n "$RUNTIME_PACKAGE" && -f "$RUNTIME_PACKAGE" &&
     ! -L "$RUNTIME_PACKAGE" ]] || {
    echo "Preflight requires a regular runtime package" >&2
    exit 2
  }
  preflight_write_source_inventory() {
    local source_dir="$1"
    (
      cd "$source_dir"
      {
        find . -maxdepth 1 -type f \
          \( -name '*.m' -o -name '*.sh' \) \
          ! -name 'tmp_*' -printf '%P\n'
        find Utils LatexTables tests -type f \
          \( -name '*.m' -o -name '*.sh' \) \
          ! -name 'tmp_*' -printf '%p\n'
      } | LC_ALL=C sort | while IFS= read -r relative; do
        digest="$(sha256sum "$relative")"
        printf '%s  %s\n' "${digest%% *}" "$relative"
      done
    )
  }
  preflight_package_sha_before="$(sha256sum "$RUNTIME_PACKAGE" |
    awk '{print $1}')"
  preflight_extract="$RUNNER_SNAPSHOT_ROOT/preflight_extract"
  mkdir -p "$preflight_extract"
  tar -xzf "$RUNTIME_PACKAGE" -C "$preflight_extract"
  preflight_package_sha_after="$(sha256sum "$RUNTIME_PACKAGE" |
    awk '{print $1}')"
  [[ "$preflight_package_sha_before" == "$preflight_package_sha_after" ]] || {
    echo "Runtime package changed during preflight extraction" >&2
    exit 2
  }
  preflight_code="$preflight_extract/cttrend_corrected_pipeline"
  [[ -d "$preflight_code" &&
     -f "$preflight_code/DesignChoices.mat" &&
     ! -e "$preflight_code/DATA" &&
     ! -L "$preflight_code/DATA" &&
     ! -e "$preflight_code/Results" &&
     ! -L "$preflight_code/Results" ]] || {
    echo "Runtime package layout failed v2 preflight validation" >&2
    exit 2
  }
  preflight_write_source_inventory "$SOURCE_CODE_DIR" \
    > "$RUNNER_SNAPSHOT_ROOT/preflight_source.sha256"
  preflight_write_source_inventory "$preflight_code" \
    > "$RUNNER_SNAPSHOT_ROOT/preflight_runtime.sha256"
  cmp -s "$RUNNER_SNAPSHOT_ROOT/preflight_source.sha256" \
    "$RUNNER_SNAPSHOT_ROOT/preflight_runtime.sha256" || {
    diff -u "$RUNNER_SNAPSHOT_ROOT/preflight_source.sha256" \
      "$RUNNER_SNAPSHOT_ROOT/preflight_runtime.sha256" >&2 || true
    echo "Runtime package differs from v2 source during preflight" >&2
    exit 2
  }
  printf 'RUNNER_PACKAGE_PREFLIGHT_OK sha256=%s\n' \
    "$preflight_package_sha_before"
  exit 0
fi

[[ -x "$MATLAB_BIN" ]] || {
  echo "MATLAB is not executable: $MATLAB_BIN" >&2
  exit 2
}
[[ -n "$RUNTIME_PACKAGE" && -f "$RUNTIME_PACKAGE" ]] || {
  echo "usage: $0 /absolute/path/to/current-runtime-package.tar.gz" >&2
  exit 2
}
[[ "$RESEARCH_RUN_ID" =~ ^[0-9a-fA-F-]{36}$ ]] || {
  echo "Invalid research run ID: $RESEARCH_RUN_ID" >&2
  exit 2
}
[[ ! -e "$RUN_ROOT" && ! -L "$RUN_ROOT" ]] || {
  echo "Run root already exists: $RUN_ROOT" >&2
  exit 2
}
for timeout_name in POOL_START_TIMEOUT_SECONDS NO_PROGRESS_TIMEOUT_SECONDS \
    HEARTBEAT_INTERVAL_SECONDS B09_HEARTBEAT_STALE_SECONDS \
    B09_MONITOR_INTERVAL_SECONDS SHARD_STOP_GRACE_SECONDS \
    PHASE_STOP_GRACE_SECONDS PHASE_EXIT_GRACE_SECONDS; do
  timeout_value="${!timeout_name}"
  [[ "$timeout_value" =~ ^[1-9][0-9]*$ ]] || {
    echo "Invalid $timeout_name: $timeout_value" >&2
    exit 2
  }
done
[[ "$POOL_START_STAGGER_SECONDS" =~ ^[0-9]+$ ]] || {
  echo "Invalid POOL_START_STAGGER_SECONDS: $POOL_START_STAGGER_SECONDS" >&2
  exit 2
}
[[ "$B09_STALE_CONFIRMATIONS" =~ ^[1-9][0-9]*$ ]] &&
    (( B09_STALE_CONFIRMATIONS >= 2 )) || {
  echo "Invalid B09_STALE_CONFIRMATIONS: $B09_STALE_CONFIRMATIONS" >&2
  exit 2
}
command -v flock >/dev/null 2>&1 || {
  echo "flock is required to serialize corrected-pipeline writers" >&2
  exit 2
}
command -v setsid >/dev/null 2>&1 || {
  echo "setsid is required to isolate MATLAB phase process groups" >&2
  exit 2
}

mkdir -p "$SOURCE_CODE_DIR/logs"
PIPELINE_LOCK_FILE="$SOURCE_CODE_DIR/logs/corrected_pipeline.lock"
exec 9>"$PIPELINE_LOCK_FILE"
if ! flock -n 9; then
  echo "Another corrected-pipeline writer holds $PIPELINE_LOCK_FILE" >&2
  exit 75
fi
export CTREND_PIPELINE_LOCK_HELD=1

ensure_canonical_bundle_layout() {
  local bootstrap_dir
  local legacy_data=""
  local legacy_results=""

  mkdir -p -- "$CANONICAL_ROOT"
  if [[ -L "$CANONICAL_CURRENT_LINK" ]]; then
    [[ -d "$CANONICAL_CURRENT_LINK/data" &&
       -d "$CANONICAL_CURRENT_LINK/results" &&
       -f "$CANONICAL_CURRENT_LINK/DesignChoices.mat" ]] || {
      echo "Existing canonical bundle pointer is incomplete" >&2
      return 2
    }
  else
    [[ ! -e "$CANONICAL_CURRENT_LINK" ]] || {
      echo "Canonical current path must be a symlink" >&2
      return 2
    }
    [[ -d "$SOURCE_CODE_DIR/DATA" ]] || {
      echo "Corrected DATA directory is missing" >&2
      return 2
    }
    [[ -L "$SOURCE_CODE_DIR/DATA" ]] || {
      echo "One-time canonical migration requires legacy DATA to be a symlink" >&2
      return 2
    }
    [[ -f "$SOURCE_CODE_DIR/DesignChoices.mat" ]] || {
      echo "Corrected DesignChoices.mat is missing" >&2
      return 2
    }
    legacy_data="$(readlink -f "$SOURCE_CODE_DIR/DATA")"
    [[ -d "$legacy_data" ]] || {
      echo "Legacy DATA target is not a directory" >&2
      return 2
    }
    if [[ -d "$SOURCE_CODE_DIR/Results" ]]; then
      [[ -L "$SOURCE_CODE_DIR/Results" ]] || {
        echo "One-time canonical migration requires legacy Results to be a symlink" >&2
        return 2
      }
      legacy_results="$(readlink -f "$SOURCE_CODE_DIR/Results")"
      [[ -d "$legacy_results" ]] || {
        echo "Legacy Results target is not a directory" >&2
        return 2
      }
    fi

    bootstrap_dir="$CANONICAL_ROOT/bootstrap_$RUN_STAMP"
    [[ ! -e "$bootstrap_dir" && ! -L "$bootstrap_dir" ]] || {
      echo "Canonical bootstrap path already exists: $bootstrap_dir" >&2
      return 2
    }
    mkdir -p -- "$bootstrap_dir"
    ln -s -- "$legacy_data" "$bootstrap_dir/data"
    if [[ -n "$legacy_results" ]]; then
      ln -s -- "$legacy_results" "$bootstrap_dir/results"
    else
      mkdir -p -- "$bootstrap_dir/results"
    fi
    cp -L -- "$SOURCE_CODE_DIR/DesignChoices.mat" \
      "$bootstrap_dir/DesignChoices.mat"
    {
      printf 'format=cttrend-canonical-bootstrap-v1\n'
      printf 'created_at=%s\n' "$(date -Is)"
      printf 'legacy_data=%s\n' "$legacy_data"
      printf 'legacy_results=%s\n' "$legacy_results"
    } > "$bootstrap_dir/BOOTSTRAP.env"
    cttrend_atomic_symlink "$bootstrap_dir" "$CANONICAL_CURRENT_LINK"
  fi

  # DATA, Results, and DesignChoices are stable aliases through one
  # atomically replaceable bundle pointer.  A successful publication swaps
  # only .canonical/current, so readers can never observe a mixed vintage.
  cttrend_atomic_symlink "$CANONICAL_DATA_ALIAS" "$SOURCE_CODE_DIR/DATA"
  cttrend_atomic_symlink "$CANONICAL_RESULTS_ALIAS" \
    "$SOURCE_CODE_DIR/Results"
  cttrend_atomic_symlink "$CANONICAL_DESIGN_ALIAS" \
    "$SOURCE_CODE_DIR/DesignChoices.mat"

  [[ "$(readlink "$SOURCE_CODE_DIR/DATA")" == "$CANONICAL_DATA_ALIAS" &&
     "$(readlink "$SOURCE_CODE_DIR/Results")" == "$CANONICAL_RESULTS_ALIAS" &&
     "$(readlink "$SOURCE_CODE_DIR/DesignChoices.mat")" == \
       "$CANONICAL_DESIGN_ALIAS" &&
     -d "$SOURCE_CODE_DIR/DATA" &&
     -d "$SOURCE_CODE_DIR/Results" &&
     -f "$SOURCE_CODE_DIR/DesignChoices.mat" ]] || {
    echo "Canonical bundle aliases failed validation" >&2
    return 2
  }
}

ensure_canonical_bundle_layout
CANONICAL_START_BUNDLE="$(readlink -f "$CANONICAL_CURRENT_LINK")"
[[ -d "$CANONICAL_START_BUNDLE" ]] || {
  echo "Canonical start bundle does not resolve to a directory" >&2
  exit 2
}

mkdir -p "$RUN_ROOT" "$LOG_ROOT" "$RUNTIME_EXTRACT_ROOT" \
  "$STAGING_DATA" \
  "$STAGING_RESULTS/CTREND" "$STAGING_RESULTS/Figures" \
  "$STAGING_RESULTS/Tables"
cp -- "$RUNNER_SNAPSHOT_ROOT/source_before.sha256" \
  "$RUN_ROOT/runner_source_inventory.sha256"
cp -- "$RUNNER_SNAPSHOT_ROOT/snapshot.sha256" \
  "$RUN_ROOT/runner_snapshot_inventory.sha256"
cttrend_prepare_temp_dir "$JOB_STORAGE_ROOT" "$JOB_STORAGE_ALLOWED_ROOT" \
  "corrected_pipeline_$RUN_STAMP"
JOB_STORAGE_CLEANED=0

cleanup_runtime_only() {
  local rc=$?
  trap - EXIT INT TERM
  if (( JOB_STORAGE_CLEANED == 0 )); then
    cttrend_safe_remove_temp_dir "$JOB_STORAGE_ROOT" \
      "$JOB_STORAGE_ALLOWED_ROOT" || rc=1
  fi
  remove_bound_runner_snapshot || rc=1
  if (( rc != 0 )); then
    if [[ -f "$RUN_ROOT/RUN_COMPLETE" ]]; then
      printf 'failed_at=%s\nrc=%s\nstage=canonical_publication\n' \
        "$(date -Is)" "$rc" > "$RUN_ROOT/RUN_PUBLICATION_FAILED.env"
    else
      printf 'failed_at=%s\nrc=%s\n' "$(date -Is)" "$rc" \
        > "$RUN_ROOT/RUN_FAILED.env"
    fi
  fi
  exit "$rc"
}
trap cleanup_runtime_only EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

input_package_resolved="$(readlink -f "$INPUT_RUNTIME_PACKAGE")"
input_package_sha_before="$(sha256sum "$INPUT_RUNTIME_PACKAGE" |
  awk '{print $1}')"
package_copy_pending="$RUN_ROOT/runtime_package.tar.gz.pending.$$"
cp -- "$INPUT_RUNTIME_PACKAGE" "$package_copy_pending"
input_package_sha_after="$(sha256sum "$INPUT_RUNTIME_PACKAGE" |
  awk '{print $1}')"
package_copy_sha="$(sha256sum "$package_copy_pending" | awk '{print $1}')"
[[ "$input_package_sha_before" == "$input_package_sha_after" &&
   "$package_copy_sha" == "$input_package_sha_before" ]] || {
  echo "Runtime package changed while it was being captured" >&2
  exit 2
}
RUNTIME_PACKAGE="$RUN_ROOT/runtime_package.tar.gz"
mv -- "$package_copy_pending" "$RUNTIME_PACKAGE"
EXPECTED_RUNTIME_PACKAGE_SHA256="$input_package_sha_before"

verify_runtime_package() {
  local current_sha
  [[ -f "$RUNTIME_PACKAGE" && ! -L "$RUNTIME_PACKAGE" ]] || {
    echo "Run-local runtime package is missing or became a symlink" >&2
    return 1
  }
  current_sha="$(sha256sum "$RUNTIME_PACKAGE" | awk '{print $1}')"
  [[ "$current_sha" == "$EXPECTED_RUNTIME_PACKAGE_SHA256" ]] || {
    echo "Run-local runtime package changed during execution" >&2
    return 1
  }
}
verify_runtime_package

cttrend_atomic_write_pointer \
  "$SOURCE_CODE_DIR/logs/latest_started_run_path.txt" "$RUN_ROOT"

write_source_inventory() {
  local source_dir="$1"
  (
    cd "$source_dir"
    {
      find . -maxdepth 1 -type f \
        \( -name '*.m' -o -name '*.sh' \) ! -name 'tmp_*' -printf '%P\n'
      find Utils LatexTables tests -type f \
        \( -name '*.m' -o -name '*.sh' \) \
        ! -name 'tmp_*' -printf '%p\n'
    } | LC_ALL=C sort | while IFS= read -r relative; do
      digest="$(sha256sum "$relative")"
      printf '%s  %s\n' "${digest%% *}" "$relative"
    done
  )
}

tar -xzf "$RUNTIME_PACKAGE" -C "$RUNTIME_EXTRACT_ROOT"
[[ -d "$CODE_DIR" ]] || {
  echo "Runtime package must contain cttrend_corrected_pipeline/" >&2
  exit 2
}
write_source_inventory "$SOURCE_CODE_DIR" \
  > "$RUN_ROOT/source_code_inventory.sha256"
write_source_inventory "$CODE_DIR" \
  > "$RUN_ROOT/runtime_code_inventory.sha256"
if ! cmp -s "$RUN_ROOT/source_code_inventory.sha256" \
    "$RUN_ROOT/runtime_code_inventory.sha256"; then
  diff -u "$RUN_ROOT/source_code_inventory.sha256" \
    "$RUN_ROOT/runtime_code_inventory.sha256" >&2 || true
  echo "Runtime package differs from the current corrected source" >&2
  exit 2
fi
[[ ! -e "$CODE_DIR/DATA" && ! -L "$CODE_DIR/DATA" ]] || {
  echo "Runtime package unexpectedly contains DATA" >&2
  exit 2
}
[[ ! -e "$CODE_DIR/Results" && ! -L "$CODE_DIR/Results" ]] || {
  echo "Runtime package unexpectedly contains Results" >&2
  exit 2
}

# Capture raw inputs as immutable run-local files.  Hash the source both
# before and after each copy and verify the captured file, so a concurrent
# upstream rewrite cannot silently enter the run through an external link.
SOURCE_DATA_DIR="$(readlink -f "$SOURCE_CODE_DIR/DATA")"
raw_input_files=(
  close_cmc.csv
  low_cmc.csv
  high_cmc.csv
  open_cmc.csv
  market_cap_cmc.csv
  volume_cmc.csv
  MetaData.mat
  F-F_Research_Data_Factors_daily.CSV
  LTW_3factor.xlsx
  UCRY.csv
  screening_summary.json
)
raw_inventory_pending="$RUN_ROOT/raw_inputs.sha256.pending.$$"
raw_sources_pending="$RUN_ROOT/raw_input_sources.tsv.pending.$$"
raw_cmc_source_dir="$(dirname "$(readlink -f \
  "$SOURCE_DATA_DIR/close_cmc.csv")")"
: > "$raw_inventory_pending"
: > "$raw_sources_pending"
for raw_input in "${raw_input_files[@]}"; do
  if [[ "$raw_input" == "screening_summary.json" ]]; then
    if [[ -f "$SOURCE_DATA_DIR/$raw_input" ]]; then
      raw_source="$SOURCE_DATA_DIR/$raw_input"
    elif [[ -f "$raw_cmc_source_dir/$raw_input" ]]; then
      raw_source="$raw_cmc_source_dir/$raw_input"
    else
      raw_source="$(dirname "$raw_cmc_source_dir")/$raw_input"
    fi
  else
    raw_source="$SOURCE_DATA_DIR/$raw_input"
  fi
  [[ -f "$raw_source" ]] || {
    echo "Required raw input is missing: $raw_source" >&2
    exit 2
  }
  raw_resolved="$(readlink -f "$raw_source")"
  [[ -f "$raw_resolved" ]] || {
    echo "Raw input does not resolve to a regular file: $raw_source" >&2
    exit 2
  }
  raw_copy_pending="$STAGING_DATA/.${raw_input}.copy_pending.$$"
  raw_source_hash_before="$(sha256sum -- "$raw_resolved" |
    awk '{print $1}')"
  cp --reflink=auto -- "$raw_resolved" "$raw_copy_pending"
  raw_source_hash_after="$(sha256sum -- "$raw_resolved" |
    awk '{print $1}')"
  raw_copy_hash="$(sha256sum -- "$raw_copy_pending" | awk '{print $1}')"
  [[ "$raw_source_hash_before" == "$raw_source_hash_after" &&
     "$raw_copy_hash" == "$raw_source_hash_before" ]] || {
    echo "Raw input changed while being captured: $raw_resolved" >&2
    exit 2
  }
  mv -- "$raw_copy_pending" "$STAGING_DATA/$raw_input"
  printf '%s  %s\n' "$raw_copy_hash" "$raw_input" \
    >> "$raw_inventory_pending"
  printf '%s\t%s\t%s\n' "$raw_input" "$raw_copy_hash" "$raw_resolved" \
    >> "$raw_sources_pending"
done
mv -- "$raw_inventory_pending" "$RUN_ROOT/raw_inputs.sha256"
mv -- "$raw_sources_pending" "$RUN_ROOT/raw_input_sources.tsv"

ln -s "$STAGING_DATA" "$CODE_DIR/DATA"
ln -s "$STAGING_RESULTS" "$CODE_DIR/Results"

{
  printf 'run_stamp=%s\n' "$RUN_STAMP"
  printf 'research_run_id=%s\n' "$RESEARCH_RUN_ID"
  printf 'started_at=%s\n' "$STARTED_AT"
  printf 'run_root=%s\n' "$RUN_ROOT"
  printf 'source_code_dir=%s\n' "$(readlink -f "$SOURCE_CODE_DIR")"
  printf 'runtime_code_dir=%s\n' "$(readlink -f "$CODE_DIR")"
  printf 'source_data_dir=%s\n' "$SOURCE_DATA_DIR"
  printf 'canonical_start_bundle=%s\n' "$CANONICAL_START_BUNDLE"
  printf 'raw_input_inventory_sha256=%s\n' \
    "$(sha256sum "$RUN_ROOT/raw_inputs.sha256" | awk '{print $1}')"
  printf 'staging_data=%s\n' "$STAGING_DATA"
  printf 'staging_results=%s\n' "$STAGING_RESULTS"
  printf 'runtime_package=%s\n' "$(readlink -f "$RUNTIME_PACKAGE")"
  printf 'input_runtime_package=%s\n' "$input_package_resolved"
  printf 'runtime_package_sha256=%s\n' \
    "$EXPECTED_RUNTIME_PACKAGE_SHA256"
  printf 'orchestrator_sha256=%s\n' \
    "$(sha256sum "$RUNNER_DIR/run_production.sh" | awk '{print $1}')"
  printf 'b09_launch_runner_sha256=%s\n' \
    "$(sha256sum "$RUNNER_DIR/launch_b09_shards.sh" | awk '{print $1}')"
  printf 'b09_shard_runner_sha256=%s\n' \
    "$(sha256sum "$RUNNER_DIR/run_b09_shard.sh" | awk '{print $1}')"
  printf 'b09_merge_runner_sha256=%s\n' \
    "$(sha256sum "$RUNNER_DIR/merge_b09_shards.sh" | awk '{print $1}')"
  printf 'b09_merge_matlab_sha256=%s\n' \
    "$(sha256sum "$RUNNER_DIR/merge_b09_shards.m" | awk '{print $1}')"
  printf 'b09_source_validator_sha256=%s\n' \
    "$(sha256sum "$RUNNER_DIR/fCollectB09ValidatedSources.m" | awk '{print $1}')"
  printf 'owned_process_runner_sha256=%s\n' \
    "$(sha256sum "$RUNNER_DIR/run_owned_process.sh" | awk '{print $1}')"
  printf 'runner_source_inventory_sha256=%s\n' \
    "$(sha256sum "$RUN_ROOT/runner_source_inventory.sha256" | awk '{print $1}')"
  printf 'runner_snapshot_inventory_sha256=%s\n' \
    "$(sha256sum "$RUN_ROOT/runner_snapshot_inventory.sha256" | awk '{print $1}')"
  printf 'data_dir=%s\n' "$(readlink -f "$CODE_DIR/DATA")"
  printf 'matlab_bin=%s\n' "$MATLAB_BIN"
  printf 'host=%s\n' "$(hostname)"
  printf 'kernel=%s\n' "$(uname -srvmo)"
  printf 'nproc=%s\n' "$HOST_NPROC"
  printf 'core_workers=64\n'
  printf 'b09_shards=%s\n' "$B09_NUM_SHARDS"
  printf 'b09_workers_per_shard=%s\n' "$B09_WORKERS_PER_SHARD"
  printf 'b09_total_workers=%s\n' \
    "$((B09_NUM_SHARDS * B09_WORKERS_PER_SHARD))"
  printf 'b09_processes_plus_clients=%s\n' \
    "$((B09_NUM_SHARDS * (B09_WORKERS_PER_SHARD + 1)))"
  printf 'b09_heartbeat_stale_seconds=%s\n' \
    "$B09_HEARTBEAT_STALE_SECONDS"
  printf 'b09_stale_confirmations=%s\n' "$B09_STALE_CONFIRMATIONS"
  printf 'b09_heartbeat_policy_sha256=%s\n' \
    "$(sha256sum "$RUNNER_DIR/b09_heartbeat_policy.sh" | awk '{print $1}')"
  printf 'phase_exit_grace_seconds=%s\n' "$PHASE_EXIT_GRACE_SECONDS"
} > "$RUN_ROOT/RUN_STARTED.env"

find -L "$CODE_DIR/DATA" -maxdepth 1 -type f -print0 |
  LC_ALL=C sort -z |
  xargs -0 -r sha256sum > "$RUN_ROOT/data_before.sha256"

state_field() {
  local state_file="$1"
  local key="$2"
  [[ -f "$state_file" ]] || return 1
  awk -F '=' -v key="$key" \
    '$1 == key { print substr($0,index($0,"=")+1); exit }' "$state_file"
}

is_expected_shard_process() {
  local pid="$1"
  local shard_dir="$2"
  local command_line
  [[ "$pid" =~ ^[1-9][0-9]*$ && -r "/proc/$pid/cmdline" ]] || return 1
  command_line="$(tr '\0' ' ' < "/proc/$pid/cmdline" 2>/dev/null || true)"
  [[ "$command_line" == *"$RUNNER_DIR/run_b09_shard.sh"* &&
     "$command_line" == *"$shard_dir/"* ]]
}

terminate_one_shard() {
  local shard_dir="$1"
  local pid_file="$shard_dir/supervisor.pid"
  local state_file="$shard_dir/state.env"
  local pid=""
  local state_pid=""
  local matlab_pgid=""
  local pgid=""
  local deadline

  [[ -f "$pid_file" ]] && pid="$(<"$pid_file")"
  state_pid="$(state_field "$state_file" supervisor_pid 2>/dev/null || true)"
  if [[ -n "$state_pid" ]] &&
      is_expected_shard_process "$state_pid" "$shard_dir"; then
    pid="$state_pid"
  fi
  matlab_pgid="$(state_field "$state_file" matlab_pgid 2>/dev/null || true)"

  if [[ -n "$pid" ]] && is_expected_shard_process "$pid" "$shard_dir"; then
    pgid="$(ps -o pgid= -p "$pid" 2>/dev/null |
      tr -d '[:space:]' || true)"
    if [[ "$pgid" =~ ^[1-9][0-9]*$ ]]; then
      kill -TERM -- "-$pgid" 2>/dev/null ||
        kill -TERM "$pid" 2>/dev/null || true
    else
      kill -TERM "$pid" 2>/dev/null || true
    fi
  elif [[ "$matlab_pgid" =~ ^[1-9][0-9]*$ ]] &&
      phase_group_exists "$matlab_pgid"; then
    # The supervisor may have died before its independently grouped MATLAB
    # client. The run-local state is the persistent ownership record.
    terminate_owned_phase_group "$matlab_pgid"
  else
    return 0
  fi

  deadline=$(( $(date +%s) + SHARD_STOP_GRACE_SECONDS ))
  while [[ -n "$pid" ]] &&
      is_expected_shard_process "$pid" "$shard_dir" &&
      (( $(date +%s) < deadline )); do
    sleep 1
  done
  if [[ -n "$pid" ]] && is_expected_shard_process "$pid" "$shard_dir"; then
    if [[ "$pgid" =~ ^[1-9][0-9]*$ ]]; then
      kill -KILL -- "-$pgid" 2>/dev/null ||
        kill -KILL "$pid" 2>/dev/null || true
    else
      kill -KILL "$pid" 2>/dev/null || true
    fi
  fi
  if [[ "$matlab_pgid" =~ ^[1-9][0-9]*$ ]] &&
      phase_group_exists "$matlab_pgid"; then
    terminate_owned_phase_group "$matlab_pgid"
  fi
}

terminate_all_shards() {
  local shard
  local stop_pid
  local -a stop_pids=()
  [[ -d "$SHARD_RUN_ROOT" ]] || return 0
  for shard in $(seq 1 "$B09_NUM_SHARDS"); do
    [[ -d "$SHARD_RUN_ROOT/shard$shard" ]] || continue
    terminate_one_shard "$SHARD_RUN_ROOT/shard$shard" &
    stop_pids+=("$!")
  done
  for stop_pid in "${stop_pids[@]}"; do
    wait "$stop_pid" 2>/dev/null || true
  done
}

PHASE_WRAPPER_PIDS=()

phase_group_exists() {
  local pgid="$1"
  cttrend_process_group_exists "$pgid"
}

terminate_owned_phase_group() {
  local pgid="$1"
  local deadline
  [[ "$pgid" =~ ^[1-9][0-9]*$ ]] || return 0
  phase_group_exists "$pgid" || return 0

  kill -TERM -- "-$pgid" 2>/dev/null || true
  deadline=$(( $(date +%s) + PHASE_STOP_GRACE_SECONDS ))
  while phase_group_exists "$pgid" &&
      (( $(date +%s) < deadline )); do
    sleep 1
  done
  if phase_group_exists "$pgid"; then
    kill -KILL -- "-$pgid" 2>/dev/null || true
    deadline=$(( $(date +%s) + 5 ))
    while phase_group_exists "$pgid" &&
        (( $(date +%s) < deadline )); do
      sleep 1
    done
  fi
  ! phase_group_exists "$pgid"
}

terminate_one_phase() {
  local phase_dir="$1"
  local owner_file="$phase_dir/phase.owner.env"
  local complete_file="$phase_dir/phase.complete.env"
  local pgid=""
  local owner_code=""
  local owner_token=""
  local deadline
  [[ -f "$owner_file" ]] || return 0
  if [[ -f "$complete_file" ]] &&
      [[ "$(state_field "$complete_file" group_empty \
        2>/dev/null || true)" == "1" ]]; then
    return 0
  fi

  # A signal can arrive immediately after setsid. Wait briefly for the
  # child-owned record to replace the pre-launch placeholder.
  deadline=$(( $(date +%s) + 5 ))
  while true; do
    pgid="$(state_field "$owner_file" pgid 2>/dev/null || true)"
    [[ "$pgid" =~ ^[1-9][0-9]*$ ]] && break
    (( $(date +%s) < deadline )) || return 0
    sleep 1
  done
  owner_code="$(state_field "$owner_file" code_dir 2>/dev/null || true)"
  owner_token="$(state_field "$owner_file" owner_token \
    2>/dev/null || true)"
  [[ "$owner_code" == "$CODE_DIR" &&
     "$owner_token" =~ ^[0-9a-fA-F-]{36}$ ]] || {
    echo "Refusing to terminate an invalid phase ownership record: $owner_file" >&2
    return 1
  }
  terminate_owned_phase_group "$pgid"
}

terminate_all_phases() {
  local pid_file
  local stop_pid
  local wrapper_pid
  local -a stop_pids=()
  while IFS= read -r -d '' pid_file; do
    terminate_one_phase "$(dirname "$pid_file")" &
    stop_pids+=("$!")
  done < <(find "$LOG_ROOT" -mindepth 2 -maxdepth 2 \
    -type f -name phase.owner.env -print0 2>/dev/null)
  for stop_pid in "${stop_pids[@]}"; do
    wait "$stop_pid" 2>/dev/null || true
  done
  for wrapper_pid in "${PHASE_WRAPPER_PIDS[@]}"; do
    wait "$wrapper_pid" 2>/dev/null || true
  done
}

cleanup_all() {
  local rc=$?
  trap - EXIT INT TERM
  terminate_all_phases || true
  terminate_all_shards || true
  if (( JOB_STORAGE_CLEANED == 0 )); then
    cttrend_safe_remove_temp_dir "$JOB_STORAGE_ROOT" \
      "$JOB_STORAGE_ALLOWED_ROOT" || rc=1
  fi
  remove_bound_runner_snapshot || rc=1
  if (( rc != 0 )); then
    if [[ -f "$RUN_ROOT/RUN_COMPLETE" ]]; then
      printf 'failed_at=%s\nrc=%s\nstage=canonical_publication\n' \
        "$(date -Is)" "$rc" > "$RUN_ROOT/RUN_PUBLICATION_FAILED.env"
    else
      printf 'failed_at=%s\nrc=%s\n' "$(date -Is)" "$rc" \
        > "$RUN_ROOT/RUN_FAILED.env"
    fi
  fi
  exit "$rc"
}
trap cleanup_all EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

export MATLAB_BIN
export OMP_NUM_THREADS=1
export MKL_NUM_THREADS=1
export OPENBLAS_NUM_THREADS=1
export NUMEXPR_NUM_THREADS=1
export POOL_START_TIMEOUT_SECONDS
export NO_PROGRESS_TIMEOUT_SECONDS
export HEARTBEAT_INTERVAL_SECONDS
export POOL_START_STAGGER_SECONDS

log_event() {
  printf '%s\t%s\n' "$(date -Is)" "$*" |
    tee -a "$LOG_ROOT/orchestrator_events.tsv"
}

prepare_phase_owner() {
  local phase_dir="$1"
  local phase="$2"
  local owner_token="$3"
  local temporary="$phase_dir/phase.owner.env.tmp.$$"
  rm -f -- "$phase_dir/phase.complete.env"
  {
    printf 'format=cttrend-owned-process-v1\n'
    printf 'state=launching\n'
    printf 'owner_token=%s\n' "$owner_token"
    printf 'phase=%s\n' "$phase"
    printf 'pgid=\n'
    printf 'code_dir=%s\n' "$CODE_DIR"
    printf 'created_at=%s\n' "$(date -Is)"
  } > "$temporary"
  mv -f -- "$temporary" "$phase_dir/phase.owner.env"
}

seal_phase_completion() {
  local phase_dir="$1"
  local pgid="$2"
  local rc="$3"
  local group_empty="$4"
  local temporary="$phase_dir/phase.complete.env.tmp.$$"
  {
    printf 'format=cttrend-phase-complete-v1\n'
    printf 'pgid=%s\n' "$pgid"
    printf 'rc=%s\n' "$rc"
    printf 'group_empty=%s\n' "$group_empty"
    printf 'completed_at=%s\n' "$(date -Is)"
  } > "$temporary"
  mv -f -- "$temporary" "$phase_dir/phase.complete.env"
}

run_matlab_phase() {
  local phase="$1"
  local scope="$2"
  local start_step="$3"
  local end_step="$4"
  local workers="$5"
  local combo_start="${6:-}"
  local combo_end="${7:-}"
  local run_id="${8:-}"
  local phase_dir="$LOG_ROOT/$phase"
  local phase_temp="$JOB_STORAGE_ROOT/$phase"
  local phase_pid
  local phase_owner_token
  local residual_group=0
  local rc

  mkdir -p "$phase_dir" "$phase_temp/matlab_pref" \
    "$phase_temp/parallel_job_storage"
  phase_owner_token="$(</proc/sys/kernel/random/uuid)"
  prepare_phase_owner "$phase_dir" "$phase" "$phase_owner_token"
  setsid "$RUNNER_DIR/run_owned_process.sh" \
    "$phase_dir/phase.owner.env" "$phase_owner_token" "$CODE_DIR" \
    "$phase" env \
    PIPELINE_SCOPE="$scope" \
    PIPELINE_START_STEP="$start_step" \
    PIPELINE_END_STEP="$end_step" \
    PARALLEL_WORKERS="$workers" \
    PIPELINE_COMBO_START="$combo_start" \
    PIPELINE_COMBO_END="$combo_end" \
    PIPELINE_RESEARCH_RUN_ID="$run_id" \
    PIPELINE_RUN_ID="$RUN_STAMP" \
    PIPELINE_LOG_DIR="$phase_dir" \
    PIPELINE_LOG_FILE="$phase_dir/pipeline.log" \
    PIPELINE_STATUS_FILE="$phase_dir/status.tsv" \
    PIPELINE_STDOUT_REDIRECTED=1 \
    MATLAB_PREFDIR="$phase_temp/matlab_pref" \
    PIPELINE_JOB_STORAGE="$phase_temp/parallel_job_storage" \
    PIPELINE_CODE_DIR="$CODE_DIR" \
    CTREND_OUTPUT_VARIANT=main \
    "$MATLAB_BIN" -licmode onlinelicensing -nodisplay -nosplash \
      -batch "cd(getenv('PIPELINE_CODE_DIR')); run_full_pipeline_corrected" \
      >> "$phase_dir/pipeline.log" 2>&1 &
  phase_pid=$!
  cttrend_atomic_write_pointer "$phase_dir/phase.pid" "$phase_pid"
  set +e
  wait "$phase_pid"
  rc=$?
  set -e
  if (( rc == 0 )) && phase_group_exists "$phase_pid"; then
    cttrend_wait_for_process_group_exit \
      "$phase_pid" "$PHASE_EXIT_GRACE_SECONDS" || residual_group=1
  elif phase_group_exists "$phase_pid"; then
    residual_group=1
  fi
  if (( residual_group == 1 )); then
    terminate_owned_phase_group "$phase_pid"
  fi
  if phase_group_exists "$phase_pid"; then
    echo "Phase $phase retained an orphan process group" >&2
    rc=125
    seal_phase_completion "$phase_dir" "$phase_pid" "$rc" 0
    return "$rc"
  fi
  if (( residual_group == 1 && rc == 0 )); then
    echo "Phase $phase returned success with residual workers" >&2
    rc=125
  fi
  seal_phase_completion "$phase_dir" "$phase_pid" "$rc" 1
  rm -f -- "$phase_dir/phase.pid"
  return "$rc"
}

run_unit_tests_phase() {
  local phase_dir="$LOG_ROOT/unit_tests"
  local phase_temp="$JOB_STORAGE_ROOT/unit_tests"
  local phase_pid
  local phase_owner_token
  local residual_group=0
  local rc
  mkdir -p "$phase_dir" "$phase_temp/matlab_pref"
  phase_owner_token="$(</proc/sys/kernel/random/uuid)"
  prepare_phase_owner "$phase_dir" unit_tests "$phase_owner_token"
  setsid "$RUNNER_DIR/run_owned_process.sh" \
    "$phase_dir/phase.owner.env" "$phase_owner_token" "$CODE_DIR" \
    unit_tests env \
    MATLAB_PREFDIR="$phase_temp/matlab_pref" \
    PIPELINE_CODE_DIR="$CODE_DIR" \
    "$MATLAB_BIN" -licmode onlinelicensing -nodisplay -nosplash \
      -batch "try, cd(getenv('PIPELINE_CODE_DIR')); addpath('./Utils'); addpath('./tests'); run_corrected_unit_tests; exit(0); catch ME, disp(getReport(ME,'extended','hyperlinks','off')); exit(1); end" \
      > "$phase_dir/pipeline.log" 2>&1 &
  phase_pid=$!
  cttrend_atomic_write_pointer "$phase_dir/phase.pid" "$phase_pid"
  set +e
  wait "$phase_pid"
  rc=$?
  set -e
  if (( rc == 0 )) && phase_group_exists "$phase_pid"; then
    cttrend_wait_for_process_group_exit \
      "$phase_pid" "$PHASE_EXIT_GRACE_SECONDS" || residual_group=1
  elif phase_group_exists "$phase_pid"; then
    residual_group=1
  fi
  if (( residual_group == 1 )); then
    terminate_owned_phase_group "$phase_pid"
  fi
  if phase_group_exists "$phase_pid"; then
    rc=125
    seal_phase_completion "$phase_dir" "$phase_pid" "$rc" 0
    return "$rc"
  fi
  if (( residual_group == 1 && rc == 0 )); then
    rc=125
  fi
  seal_phase_completion "$phase_dir" "$phase_pid" "$rc" 1
  rm -f -- "$phase_dir/phase.pid"
  return "$rc"
}

run_external_phase() {
  local phase="$1"
  shift
  local phase_dir="$LOG_ROOT/$phase"
  local phase_pid
  local phase_owner_token
  local residual_group=0
  local rc

  mkdir -p "$phase_dir"
  phase_owner_token="$(</proc/sys/kernel/random/uuid)"
  prepare_phase_owner "$phase_dir" "$phase" "$phase_owner_token"
  setsid "$RUNNER_DIR/run_owned_process.sh" \
    "$phase_dir/phase.owner.env" "$phase_owner_token" "$CODE_DIR" \
    "$phase" env PIPELINE_CODE_DIR="$CODE_DIR" "$@" \
    > "$phase_dir/pipeline.log" 2>&1 &
  phase_pid=$!
  cttrend_atomic_write_pointer "$phase_dir/phase.pid" "$phase_pid"
  set +e
  wait "$phase_pid"
  rc=$?
  set -e
  if (( rc == 0 )) && phase_group_exists "$phase_pid"; then
    cttrend_wait_for_process_group_exit \
      "$phase_pid" "$PHASE_EXIT_GRACE_SECONDS" || residual_group=1
  elif phase_group_exists "$phase_pid"; then
    residual_group=1
  fi
  if (( residual_group == 1 )); then
    terminate_owned_phase_group "$phase_pid"
  fi
  if phase_group_exists "$phase_pid"; then
    rc=125
    seal_phase_completion "$phase_dir" "$phase_pid" "$rc" 0
    return "$rc"
  fi
  if (( residual_group == 1 && rc == 0 )); then
    rc=125
  fi
  seal_phase_completion "$phase_dir" "$phase_pid" "$rc" 1
  rm -f -- "$phase_dir/phase.pid"
  return "$rc"
}

log_event "START phase=unit_tests workers=0"
run_unit_tests_phase
log_event "END phase=unit_tests rc=0"

log_event "START phase=core_b00_b08 workers=64 start_step=$CORE_START_STEP"
run_matlab_phase core_b00_b08 full "$CORE_START_STEP" \
  b08Table5_PerformanceInSubperiodsAndDifferentMarketStates 64
log_event "END phase=core_b00_b08 rc=0"

# b00 is the sole authorized writer of the production design table. Freeze
# its exact bytes now and require every subsequent consumer and shard to
# use the same file.
EXPECTED_DESIGN_CHOICES_SHA256="$(sha256sum \
  "$CODE_DIR/DesignChoices.mat" | awk '{print $1}')"
printf '%s  DesignChoices.mat\n' "$EXPECTED_DESIGN_CHOICES_SHA256" \
  > "$RUN_ROOT/design_choices_after_b00.sha256"
verify_design_choices() {
  local current_sha
  current_sha="$(sha256sum "$CODE_DIR/DesignChoices.mat" | awk '{print $1}')"
  [[ "$current_sha" == "$EXPECTED_DESIGN_CHOICES_SHA256" ]] || {
    echo "DesignChoices.mat changed after b00" >&2
    return 1
  }
}
verify_design_choices

# These phases write disjoint files.  Their total remains below the known
# stable 128-process profile; b09 later uses the selected audited clients.
log_event "START phase=baseline_downstream workers=64"
run_matlab_phase baseline_downstream full \
  b11Figure3_AnomalyAlphas \
  b18FigureC3_C4_AverageVariableImportance 64 &
pid_baseline=$!
PHASE_WRAPPER_PIDS+=("$pid_baseline")

log_event "START phase=canonical_combo1 workers=31 run_id=$RESEARCH_RUN_ID"
run_matlab_phase canonical_combo1 table6 \
  b09RunResearchDesigns b09RunResearchDesigns \
  31 1 1 "$RESEARCH_RUN_ID" &
pid_combo1=$!
PHASE_WRAPPER_PIDS+=("$pid_combo1")

set +e
wait "$pid_baseline"
rc_baseline=$?
wait "$pid_combo1"
rc_combo1=$?
set -e
log_event "END phase=baseline_downstream rc=$rc_baseline"
log_event "END phase=canonical_combo1 rc=$rc_combo1"
if (( rc_baseline != 0 || rc_combo1 != 0 )); then
  echo "Concurrent baseline/combo1 phase failed" >&2
  exit 1
fi
verify_design_choices
verify_runtime_package

log_event "START phase=b09_shards workers=${B09_NUM_SHARDS}x${B09_WORKERS_PER_SHARD} persistent=1 combos=2:3072"
export B09_JOB_STORAGE_ROOT="$JOB_STORAGE_ROOT/b09_shards"
B09_ORCHESTRATOR_PID="$$"
B09_ORCHESTRATOR_START_TICKS="$(awk '{print $22}' \
  "/proc/$B09_ORCHESTRATOR_PID/stat")"
[[ "$B09_ORCHESTRATOR_PID" =~ ^[1-9][0-9]*$ &&
   "$B09_ORCHESTRATOR_START_TICKS" =~ ^[1-9][0-9]*$ ]] || {
  echo "Could not bind the b09 shard orchestrator lease" >&2
  exit 2
}
CORRECTED_PACKAGE="$RUNTIME_PACKAGE" \
CANONICAL_CODE_DIR="$CODE_DIR" \
MATLAB_BIN="$MATLAB_BIN" \
WORKERS_PER_SHARD="$B09_WORKERS_PER_SHARD" NUM_SHARDS="$B09_NUM_SHARDS" \
FIRST_COMBO=2 LAST_COMBO=3072 \
RUN_ROOT="$SHARD_RUN_ROOT" RESULTS_ROOT="$SHARD_RESULTS_ROOT" \
RESEARCH_RUN_ID="$RESEARCH_RUN_ID" \
B09_ORCHESTRATOR_PID="$B09_ORCHESTRATOR_PID" \
B09_ORCHESTRATOR_START_TICKS="$B09_ORCHESTRATOR_START_TICKS" \
EXPECTED_PACKAGE_SHA256="$EXPECTED_RUNTIME_PACKAGE_SHA256" \
EXPECTED_DESIGN_CHOICES_SHA256="$EXPECTED_DESIGN_CHOICES_SHA256" \
  "$RUNNER_DIR/launch_b09_shards.sh" \
  > "$LOG_ROOT/b09_launch.log" 2>&1

declare -a b09_stale_epoch_seen=()
declare -a b09_stale_observation_count=()

b09_latest_result_epoch() {
  local combo_dir="$1"
  if [[ ! -d "$combo_dir" ]]; then
    printf '0\n'
    return 0
  fi
  find -L "$combo_dir" -maxdepth 1 -type f \
    -name 'CTREND_Combo*.mat' -printf '%T@\n' 2>/dev/null | awk '
      BEGIN { latest = 0 }
      $1 > latest { latest = $1 }
      END { printf "%d\n", latest }
    '
}

while true; do
  n_running=0
  n_complete=0
  n_failed=0
  n_shard_files=0
  state_summary=""
  for shard in $(seq 1 "$B09_NUM_SHARDS"); do
    shard_dir="$SHARD_RUN_ROOT/shard$shard"
    pid="$(<"$shard_dir/supervisor.pid")"
    shard_state="$(state_field "$shard_dir/state.env" state \
      2>/dev/null || true)"
    [[ -n "$shard_state" ]] || shard_state="LAUNCHING"
    heartbeat_epoch="$(state_field "$shard_dir/heartbeat.env" \
      updated_epoch 2>/dev/null || true)"
    started_epoch="$(<"$shard_dir/supervisor.started_epoch")"
    now_epoch="$(date +%s)"
    combo_dir="$shard_dir/extract/cttrend_corrected_pipeline/Results/CTREND"

    if is_expected_shard_process "$pid" "$shard_dir"; then
      heartbeat_stale=0
      heartbeat_age=$((now_epoch - started_epoch))
      if [[ "$heartbeat_epoch" =~ ^[0-9]+$ ]]; then
        heartbeat_age=$((now_epoch - heartbeat_epoch))
        if (( heartbeat_age >
            B09_HEARTBEAT_STALE_SECONDS )); then
          heartbeat_stale=1
        fi
      elif (( now_epoch - started_epoch >
          B09_HEARTBEAT_STALE_SECONDS )); then
        heartbeat_stale=1
      fi
      if (( heartbeat_stale == 1 )); then
        observed_epoch="${heartbeat_epoch:-missing}"
        if [[ "${b09_stale_epoch_seen[$shard]:-}" == "$observed_epoch" ]]; then
          b09_stale_observation_count[$shard]=$((${b09_stale_observation_count[$shard]:-0} + 1))
        else
          b09_stale_epoch_seen[$shard]="$observed_epoch"
          b09_stale_observation_count[$shard]=1
        fi

        # Re-read the atomically replaced heartbeat immediately before any
        # termination decision. A refresh racing the first read must cancel
        # the stale observation instead of killing a healthy MATLAB group.
        confirmed_now_epoch="$(date +%s)"
        confirmed_heartbeat_epoch="$(state_field \
          "$shard_dir/heartbeat.env" updated_epoch 2>/dev/null || true)"
        if [[ "$confirmed_heartbeat_epoch" =~ ^[0-9]+$ ]]; then
          confirmed_heartbeat_age=$((confirmed_now_epoch - confirmed_heartbeat_epoch))
        else
          confirmed_heartbeat_age=$((confirmed_now_epoch - started_epoch))
        fi

        refresh_state="$(cttrend_b09_heartbeat_refresh_state \
          "$observed_epoch" "${confirmed_heartbeat_epoch:-missing}" \
          "$confirmed_heartbeat_age" "$B09_HEARTBEAT_STALE_SECONDS")"
        if [[ "$refresh_state" == "REFRESHED" ]]; then
          log_event \
            "RECOVERED phase=b09_shards shard=$shard reason=heartbeat_refreshed observed_epoch=$observed_epoch confirmed_epoch=${confirmed_heartbeat_epoch:-missing} confirmed_age=$confirmed_heartbeat_age"
          b09_stale_epoch_seen[$shard]=""
          b09_stale_observation_count[$shard]=0
          n_running=$((n_running + 1))
        else
          last_progress_epoch="$(state_field "$shard_dir/heartbeat.env" \
            last_progress_epoch 2>/dev/null || true)"
          [[ "$last_progress_epoch" =~ ^[0-9]+$ ]] || \
            last_progress_epoch="$started_epoch"
          latest_result_epoch="$(b09_latest_result_epoch "$combo_dir")"
          if [[ "$latest_result_epoch" =~ ^[0-9]+$ ]] &&
              (( latest_result_epoch > last_progress_epoch )); then
            last_progress_epoch="$latest_result_epoch"
          fi
          progress_age=$((confirmed_now_epoch - last_progress_epoch))
          (( progress_age >= 0 )) || progress_age=0
          matlab_pid="$(state_field "$shard_dir/state.env" matlab_pid \
            2>/dev/null || true)"
          matlab_live=0
          if [[ "$matlab_pid" =~ ^[1-9][0-9]*$ ]] &&
              kill -0 "$matlab_pid" 2>/dev/null; then
            matlab_live=1
          fi
          stale_decision="$(cttrend_b09_heartbeat_decision \
            "$confirmed_heartbeat_age" "$B09_HEARTBEAT_STALE_SECONDS" \
            "${b09_stale_observation_count[$shard]}" \
            "$B09_STALE_CONFIRMATIONS" "$progress_age" \
            "$NO_PROGRESS_TIMEOUT_SECONDS" "$matlab_live")"

          case "$stale_decision" in
            WARN_STALE|DEFER_RECENT_PROGRESS)
              log_event \
                "WARNING phase=b09_shards shard=$shard reason=$stale_decision heartbeat_epoch=$observed_epoch heartbeat_age=$confirmed_heartbeat_age observations=${b09_stale_observation_count[$shard]}/$B09_STALE_CONFIRMATIONS progress_age=$progress_age matlab_live=$matlab_live"
              n_running=$((n_running + 1))
              ;;
            TERMINATE_CONFIRMED_STALE)
              log_event \
                "TIMEOUT phase=b09_shards shard=$shard reason=confirmed_stale_heartbeat heartbeat_epoch=$observed_epoch heartbeat_age=$confirmed_heartbeat_age observations=${b09_stale_observation_count[$shard]}/$B09_STALE_CONFIRMATIONS progress_age=$progress_age matlab_live=$matlab_live state=$shard_state"
              terminate_one_shard "$shard_dir"
              shard_state="FAILED_STALE_HEARTBEAT"
              n_failed=$((n_failed + 1))
              ;;
            *)
              echo "Unexpected heartbeat policy decision: $stale_decision" >&2
              exit 2
              ;;
          esac
        fi
      else
        b09_stale_epoch_seen[$shard]=""
        b09_stale_observation_count[$shard]=0
        n_running=$((n_running + 1))
      fi
    elif [[ -f "$shard_dir/completion.env" ]] &&
        [[ "$(state_field "$shard_dir/completion.env" complete \
          2>/dev/null || true)" == "1" ]] &&
        [[ "$(state_field "$shard_dir/completion.env" research_run_id \
          2>/dev/null || true)" == "$RESEARCH_RUN_ID" ]]; then
      n_complete=$((n_complete + 1))
    else
      n_failed=$((n_failed + 1))
    fi
    combo_files=0
    if [[ -d "$combo_dir" ]]; then
      combo_files="$(find -L "$combo_dir" -maxdepth 1 -type f \
        -name 'CTREND_Combo*.mat' -printf '.\n' | awk 'END { print NR+0 }')"
    fi
    n_shard_files=$((n_shard_files + combo_files))
    state_summary="${state_summary} shard${shard}=${shard_state}:files=${combo_files}"
  done
  n_total_completed=$((n_shard_files + 1))
  progress_percent="$(awk -v done="$n_total_completed" \
    'BEGIN { printf "%.2f", 100 * done / 3072 }')"
  log_event \
    "PROGRESS phase=b09_shards completed=$n_total_completed/3072 percent=${progress_percent}% running=$n_running complete=$n_complete failed=$n_failed${state_summary}"
  if (( n_failed > 0 && n_running > 0 )); then
    log_event \
      "WAIT phase=b09_shards reason=failed_shard_preserve_healthy_siblings"
  elif (( n_failed > 0 )); then
    echo "A b09 shard failed after all healthy siblings stopped" >&2
    exit 1
  fi
  (( n_complete < B09_NUM_SHARDS )) || break
  sleep "$B09_MONITOR_INTERVAL_SECONDS"
done

# Completion is accepted only with an atomic record and an executable-tree
# inventory that still equals the pre-launch package inventory.
for shard in $(seq 1 "$B09_NUM_SHARDS"); do
  shard_dir="$SHARD_RUN_ROOT/shard$shard"
  [[ -f "$shard_dir/completion.env" &&
     "$(state_field "$shard_dir/completion.env" complete)" == "1" &&
     "$(state_field "$shard_dir/completion.env" research_run_id)" == \
       "$RESEARCH_RUN_ID" &&
     "$(state_field "$shard_dir/completion.env" design_choices_sha256)" == \
       "$EXPECTED_DESIGN_CHOICES_SHA256" &&
     -f "$shard_dir/runtime_matlab_sources_after.sha256" ]] || {
    echo "Shard $shard lacks a sealed completion/source record" >&2
    exit 1
  }
  cmp -s "$shard_dir/package_matlab_sources.sha256" \
    "$shard_dir/runtime_matlab_sources_after.sha256" || {
    echo "Shard $shard executable source changed during execution" >&2
    exit 1
  }
  shard_inventory_sha="$(sha256sum \
    "$shard_dir/runtime_matlab_sources_after.sha256" | awk '{print $1}')"
  [[ "$shard_inventory_sha" == \
    "$(state_field "$shard_dir/completion.env" source_inventory_sha256)" ]] || {
    echo "Shard $shard completion inventory digest is invalid" >&2
    exit 1
  }
done

verify_design_choices
verify_runtime_package
log_event "START phase=b09_merge"
run_external_phase b09_merge env \
  MATLAB_BIN="$MATLAB_BIN" \
  CANONICAL_CODE_DIR="$CODE_DIR" \
  B09_MERGE_TEMP_ROOT="$JOB_STORAGE_ROOT/b09_merge" \
  "$RUNNER_DIR/merge_b09_shards.sh" "$SHARD_RUN_ROOT"
log_event "END phase=b09_merge rc=0"

verify_design_choices
log_event "START phase=result_invariants workers=0"
result_invariants_temp="$JOB_STORAGE_ROOT/result_invariants"
mkdir -p "$result_invariants_temp/matlab_pref"
run_external_phase result_invariants env \
  MATLAB_PREFDIR="$result_invariants_temp/matlab_pref" \
  PIPELINE_CODE_DIR="$CODE_DIR" \
  "$MATLAB_BIN" -licmode onlinelicensing -nodisplay -nosplash \
  -batch "try, cd(getenv('PIPELINE_CODE_DIR')); addpath('./Utils'); addpath('./tests'); test_b05_b09_baseline_results; test_figure_b2_results; exit(0); catch ME, disp(getReport(ME,'extended','hyperlinks','off')); exit(1); end"
log_event "END phase=result_invariants rc=0"

verify_design_choices
log_event "START phase=b10 workers=64"
run_matlab_phase b10 table6 \
  b10Table6_FactorPerformanceAcrossResearchDesignChoices \
  b10Table6_FactorPerformanceAcrossResearchDesignChoices 64
log_event "END phase=b10 rc=0"

verify_design_choices
log_event "START phase=table6_result_invariants workers=0"
table6_invariants_temp="$JOB_STORAGE_ROOT/table6_result_invariants"
mkdir -p "$table6_invariants_temp/matlab_pref"
run_external_phase table6_result_invariants env \
  MATLAB_PREFDIR="$table6_invariants_temp/matlab_pref" \
  PIPELINE_CODE_DIR="$CODE_DIR" \
  "$MATLAB_BIN" -licmode onlinelicensing -nodisplay -nosplash \
  -batch "try, cd(getenv('PIPELINE_CODE_DIR')); addpath('./Utils'); addpath('./tests'); test_table6_results; exit(0); catch ME, disp(getReport(ME,'extended','hyperlinks','off')); exit(1); end"
log_event "END phase=table6_result_invariants rc=0"

verify_design_choices
log_event "START phase=supplementary workers=64"
supp_temp="$JOB_STORAGE_ROOT/supplementary"
run_external_phase supplementary env \
  PARALLEL_WORKERS=64 \
  MATLAB_BIN="$MATLAB_BIN" \
  CODE_DIR="$CODE_DIR" \
  CTREND_SUPPLEMENTARY_TEMP_ROOT="$supp_temp" \
  MATLAB_PREFDIR="$supp_temp/matlab_pref" \
  PIPELINE_JOB_STORAGE="$supp_temp/parallel_job_storage" \
  "$CODE_DIR/run_supplementary_outputs.sh"
log_event "END phase=supplementary rc=0"
verify_design_choices
verify_runtime_package

required_outputs=(
  "$STAGING_RESULTS/CTREND/CTREND_Base.mat"
  "$STAGING_RESULTS/CTREND/ResearchDesignRunManifest.mat"
  "$STAGING_RESULTS/HedgePorts.mat"
  "$STAGING_RESULTS/Figure3_SystemAudit.mat"
  "$STAGING_RESULTS/Table7_FrontierExpansionDiagnostics.mat"
  "$STAGING_RESULTS/FigureC3_C4_Diagnostics.mat"
  "$STAGING_RESULTS/Tables/research_sample.tex"
  "$STAGING_RESULTS/Tables/technical_indicator_strategy_returns.tex"
  "$STAGING_RESULTS/Tables/univariate_portfolio_sorts.tex"
  "$STAGING_RESULTS/Tables/descriptive_statistics_of_asset_pricing_factor_returns.tex"
  "$STAGING_RESULTS/Tables/cross_sectional_regressions.tex"
  "$STAGING_RESULTS/Tables/performance_in_subperiods_and_different_market_states.tex"
  "$STAGING_RESULTS/Tables/factor_performance_across_research_design_choices_paper_method_specific_available_case.tex"
  "$STAGING_RESULTS/Tables/median_method_specific_weekly_observation_counts_underlying_table_6.tex"
  "$STAGING_RESULTS/Tables/table6_method_specific_week_counts.csv"
  "$STAGING_RESULTS/Tables/table6_method_specific_week_counts.mat"
  "$STAGING_RESULTS/Tables/table6_method_specific_week_counts_available_case_cells.csv"
  "$STAGING_RESULTS/Tables/table6_strict_common_week_comparison.mat"
  "$STAGING_RESULTS/Tables/table6_strict_common_week_comparison_cells.csv"
  "$STAGING_RESULTS/Tables/table6_strict_common_week_comparison_pairwise.csv"
  "$STAGING_RESULTS/Tables/table6_strict_common_week_comparison_pairwise_summary.csv"
  "$STAGING_RESULTS/Tables/table6_strict_common_week_comparison_coverage_audit.csv"
  "$STAGING_RESULTS/Tables/table6_strict_common_week_comparison_coverage_summary.csv"
  "$STAGING_RESULTS/Tables/table_6_panel_b_pairwise_common_week_estimator_comparisons.tex"
  "$STAGING_RESULTS/Tables/table_6_panel_d_estimator_coverage_and_failure_audit.tex"
  "$STAGING_RESULTS/Tables/anomaly_alphas.tex"
  "$STAGING_RESULTS/Tables/anomaly_strategy_returns.tex"
  "$STAGING_RESULTS/Tables/insignificant_anomaly_strategy_returns.tex"
  "$STAGING_RESULTS/Tables/trend_model_alphas.tex"
  "$STAGING_RESULTS/Tables/frontier_expansion_test.tex"
  "$STAGING_RESULTS/Tables/the_ctrend_factor_performance_in_big_and_liquid_cryptocurrencies.tex"
  "$STAGING_RESULTS/Tables/ctrend_portfolios_and_transaction_costs.tex"
  "$STAGING_RESULTS/Tables/table9_transaction_cost_accounting.mat"
  "$STAGING_RESULTS/Tables/bivariate_portfolio_sorts.tex"
  "$STAGING_RESULTS/Tables/ctrend_performance_depending_on_cryptocurrency_type.tex"
  "$STAGING_RESULTS/Tables/extended_portfolio_holding_periods.tex"
  "$STAGING_RESULTS/Tables/table_b10_holding_coverage.mat"
  "$STAGING_RESULTS/Tables/univariate_portfolio_sorts_alternative_factor_data.tex"
  "$STAGING_RESULTS/Tables/factor_performance_across_research_design_choices_value_weighted_only_paper_method_specific_available_case.tex"
  "$STAGING_RESULTS/Tables/median_method_specific_weekly_observation_counts_underlying_table_b_6.tex"
  "$STAGING_RESULTS/Tables/table_6_panel_b_pairwise_common_week_estimator_comparisons_value_weighted_only.tex"
  "$STAGING_RESULTS/Tables/table_6_panel_d_estimator_coverage_and_failure_audit_value_weighted_only.tex"
  "$STAGING_RESULTS/Figures/b06Table3_UnivariatePortfolioSorts_figure01.png"
  "$STAGING_RESULTS/Figures/b06Table3_UnivariatePortfolioSorts_figure02.png"
  "$STAGING_RESULTS/Figures/b06Table3_UnivariatePortfolioSorts_figure03.png"
  "$STAGING_RESULTS/Figures/b11Figure3_AnomalyAlphas_figure01.png"
  "$STAGING_RESULTS/Figures/b11Figure3_AnomalyAlphas_figure02.png"
  "$STAGING_RESULTS/Figures/b11Figure3_AnomalyAlphas_figure03.png"
  "$STAGING_RESULTS/Figures/b18FigureC3_C4_AverageVariableImportance_figure01.png"
  "$STAGING_RESULTS/Figures/b18FigureC3_C4_AverageVariableImportance_figure02.png"
  "$STAGING_RESULTS/Figures/b10Table6_FactorPerformanceAcrossResearchDesignChoices_figure01.png"
  "$STAGING_RESULTS/Figures/b10Table6_FactorPerformanceAcrossResearchDesignChoices_figure02.png"
  "$STAGING_RESULTS/Figures/b10Table6_FactorPerformanceAcrossResearchDesignChoices_figure03.png"
  "$STAGING_RESULTS/Figures/b10Table6_FactorPerformanceAcrossResearchDesignChoices_figure04.png"
  "$STAGING_RESULTS/Figures/b10FigureB1_ValueWeightedResearchDesigns_figure01.png"
  "$STAGING_RESULTS/Figures/b10FigureB1_ValueWeightedResearchDesigns_figure02.png"
  "$STAGING_RESULTS/Figures/b10FigureB1_ValueWeightedResearchDesigns_figure03.png"
  "$STAGING_RESULTS/Figures/b10FigureB1_ValueWeightedResearchDesigns_figure04.png"
)
for output in "${required_outputs[@]}"; do
  [[ -s "$output" ]] || {
    echo "Required final output is missing: $output" >&2
    exit 1
  }
done
required_data_outputs=(
  "$STAGING_DATA/LTW_3factor.mat"
  "$STAGING_DATA/b0DataOLHC.mat"
  "$STAGING_DATA/bCharacteristicsOLHC_Combo1.mat"
  "$STAGING_DATA/bCharacteristicsOLHC_Combo2.mat"
  "$STAGING_DATA/bCharacteristicsOLHC_Combo3.mat"
  "$STAGING_DATA/bCharacteristicsOLHC_Combo4.mat"
  "$STAGING_DATA/WeeklyDataBuildManifest.mat"
)
for output in "${required_data_outputs[@]}"; do
  [[ -s "$output" ]] || {
    echo "Required run-local data output is missing: $output" >&2
    exit 1
  }
done
combo_count="$(find "$STAGING_RESULTS/CTREND" -maxdepth 1 -type f \
  -name 'CTREND_Combo*.mat' -printf '.\n' | awk 'END { print NR }')"
[[ "$combo_count" -eq 3072 ]] || {
  echo "Expected 3072 b09 combo files, found $combo_count" >&2
  exit 1
}
combo_digest_count="$(find "$STAGING_RESULTS/CTREND" -maxdepth 1 -type f \
  -name 'CTREND_Combo*.mat.sha256' -printf '.\n' |
  awk 'END { print NR }')"
[[ "$combo_digest_count" -eq 3072 ]] || {
  echo "Expected 3072 b09 payload digests, found $combo_digest_count" >&2
  exit 1
}
if find "$STAGING_RESULTS" -type f \
    \( -name '*.tmp' -o -name '*.merge_tmp' -o -name '*.runner_tmp.*' \) \
    -print -quit | grep -q .; then
  echo "Uncommitted temporary output remains in staging results" >&2
  exit 1
fi
if find "$RUN_ROOT" -type f \
    \( -name '*.pem' -o -name '*.p12' -o -name '*.key' \) \
    -print -quit | grep -q .; then
  echo "Credential-like artifact found in persistent run state" >&2
  exit 1
fi

write_source_inventory "$SOURCE_CODE_DIR" \
  > "$RUN_ROOT/source_code_inventory_at_publish.sha256"
if ! cmp -s "$RUN_ROOT/source_code_inventory.sha256" \
    "$RUN_ROOT/source_code_inventory_at_publish.sha256"; then
  diff -u "$RUN_ROOT/source_code_inventory.sha256" \
    "$RUN_ROOT/source_code_inventory_at_publish.sha256" >&2 || true
  echo "Corrected source changed during the run; refusing publication" >&2
  exit 1
fi
write_source_inventory "$CODE_DIR" \
  > "$RUN_ROOT/runtime_code_inventory_at_publish.sha256"
if ! cmp -s "$RUN_ROOT/runtime_code_inventory.sha256" \
    "$RUN_ROOT/runtime_code_inventory_at_publish.sha256"; then
  diff -u "$RUN_ROOT/runtime_code_inventory.sha256" \
    "$RUN_ROOT/runtime_code_inventory_at_publish.sha256" >&2 || true
  echo "Executed runtime source changed during the run; refusing publication" >&2
  exit 1
fi
for runner_field in \
    "orchestrator_sha256:$RUNNER_DIR/run_production.sh" \
    "b09_launch_runner_sha256:$RUNNER_DIR/launch_b09_shards.sh" \
    "b09_shard_runner_sha256:$RUNNER_DIR/run_b09_shard.sh" \
    "b09_merge_runner_sha256:$RUNNER_DIR/merge_b09_shards.sh" \
    "b09_merge_matlab_sha256:$RUNNER_DIR/merge_b09_shards.m" \
    "b09_source_validator_sha256:$RUNNER_DIR/fCollectB09ValidatedSources.m" \
    "owned_process_runner_sha256:$RUNNER_DIR/run_owned_process.sh"; do
  runner_key="${runner_field%%:*}"
  runner_file="${runner_field#*:}"
  runner_start_sha="$(awk -F= -v key="$runner_key" \
    '$1 == key { print $2; exit }' "$RUN_ROOT/RUN_STARTED.env")"
  runner_current_sha="$(sha256sum "$runner_file" | awk '{print $1}')"
  [[ -n "$runner_start_sha" &&
     "$runner_current_sha" == "$runner_start_sha" ]] || {
    echo "Runner changed during execution: $runner_file" >&2
    exit 1
  }
done

# The run executes only the bound snapshot, but source provenance must also
# prove that the operator-visible runner suite was not changed before
# publication.
(
  cd "$RUNNER_SOURCE_DIR"
  find . -maxdepth 1 -type f \
    \( -name '*.sh' -o -name '*.m' \) -printf '%P\n' |
    LC_ALL=C sort | xargs -r sha256sum
  sha256sum "$SOURCE_CODE_DIR/run_safety.sh"
) > "$RUN_ROOT/runner_source_inventory_at_publish.sha256"
if ! cmp -s "$RUN_ROOT/runner_source_inventory.sha256" \
    "$RUN_ROOT/runner_source_inventory_at_publish.sha256"; then
  echo "Operator-visible runner source changed during execution" >&2
  exit 1
fi

raw_inventory_at_publish="$RUN_ROOT/raw_inputs_at_publish.sha256"
(
  cd "$STAGING_DATA"
  for raw_input in "${raw_input_files[@]}"; do
    [[ -f "$raw_input" && ! -L "$raw_input" ]] || {
      echo "Captured raw input is missing or became a symlink: $raw_input" >&2
      exit 1
    }
    sha256sum -- "$raw_input"
  done
) > "$raw_inventory_at_publish"
if ! cmp -s "$RUN_ROOT/raw_inputs.sha256" "$raw_inventory_at_publish"; then
  diff -u "$RUN_ROOT/raw_inputs.sha256" \
    "$raw_inventory_at_publish" >&2 || true
  echo "A captured raw input changed during execution" >&2
  exit 1
fi

# Reopen and hash the sealed original source paths as well as the run-local
# snapshots. A stable snapshot alone cannot establish the required
# publication-time state of the source files.
raw_sources_at_publish="$RUN_ROOT/raw_input_sources_at_publish.sha256"
cttrend_verify_source_map "$RUN_ROOT/raw_input_sources.tsv" \
  "$raw_sources_at_publish" "${#raw_input_files[@]}"

find -L "$CODE_DIR/DATA" -maxdepth 1 -type f -print0 |
  LC_ALL=C sort -z |
  xargs -0 -r sha256sum > "$RUN_ROOT/data_after.sha256"
(
  cd "$STAGING_RESULTS"
  find . -type f -print0 |
    LC_ALL=C sort -z |
    xargs -0 -r sha256sum
) > "$RUN_ROOT/results.sha256"
log_event \
  "READY_TO_SEAL run_id=$RESEARCH_RUN_ID run_root=$RUN_ROOT"
(
  cd "$RUN_ROOT"
  {
    find logs b09_shards b09_shard_results -type f -print0
    printf '%s\0' RUN_STARTED.env raw_input_sources.tsv \
      raw_inputs.sha256 raw_inputs_at_publish.sha256 \
      raw_input_sources_at_publish.sha256 \
      source_code_inventory.sha256 runtime_code_inventory.sha256 \
      source_code_inventory_at_publish.sha256 \
      runtime_code_inventory_at_publish.sha256 \
      design_choices_after_b00.sha256 \
      runner_source_inventory.sha256 \
      runner_snapshot_inventory.sha256 \
      runner_source_inventory_at_publish.sha256
  } | LC_ALL=C sort -z | xargs -0 -r sha256sum
) > "$RUN_ROOT/status_inventory.sha256"
verify_design_choices
cp -- "$CODE_DIR/DesignChoices.mat" "$RUN_ROOT/DesignChoices.mat"
[[ "$(sha256sum "$RUN_ROOT/DesignChoices.mat" | awk '{print $1}')" == \
   "$EXPECTED_DESIGN_CHOICES_SHA256" ]] || {
  echo "Published DesignChoices copy differs from the b00-frozen file" >&2
  exit 1
}

DATA_BUILD_ID="$(awk -F= '$1 == "table6_data_build_id" {
  print substr($0,index($0,"=")+1)
}' "$LOG_ROOT/b10/pipeline.log" | tail -1)"
CODE_FINGERPRINT="$(awk -F= '$1 == "table6_code_fingerprint" {
  print substr($0,index($0,"=")+1)
}' "$LOG_ROOT/b10/pipeline.log" | tail -1)"
[[ -n "$DATA_BUILD_ID" && -n "$CODE_FINGERPRINT" ]] || {
  echo "Could not recover final data/code IDs from the validated b10 log" >&2
  exit 1
}
SUPPLEMENT_DATA_BUILD_ID="$(awk -F= '$1 == "table6_data_build_id" {
  print substr($0,index($0,"=")+1)
}' "$LOG_ROOT/supplementary/pipeline.log" | tail -1)"
SUPPLEMENT_CODE_FINGERPRINT="$(awk -F= \
  '$1 == "table6_code_fingerprint" {
    print substr($0,index($0,"=")+1)
  }' "$LOG_ROOT/supplementary/pipeline.log" | tail -1)"
[[ "$SUPPLEMENT_DATA_BUILD_ID" == "$DATA_BUILD_ID" &&
   "$SUPPLEMENT_CODE_FINGERPRINT" == "$CODE_FINGERPRINT" ]] || {
  echo "Main and supplementary Table 6 provenance disagree" >&2
  exit 1
}
MATLAB_VERSION="$(awk -F= '$1 == "matlab_version" {
  print substr($0,index($0,"=")+1)
}' "$LOG_ROOT/core_b00_b08/pipeline.log" | head -1)"
MATLAB_RELEASE="$(awk -F= '$1 == "matlab_release" {
  print substr($0,index($0,"=")+1)
}' "$LOG_ROOT/core_b00_b08/pipeline.log" | head -1)"
[[ -n "$MATLAB_VERSION" && -n "$MATLAB_RELEASE" ]] || {
  echo "MATLAB version metadata is missing from the core log" >&2
  exit 1
}
awk '$0 ~ /^matlab_(version|release|product)=/' \
  "$LOG_ROOT/core_b00_b08/pipeline.log" \
  > "$RUN_ROOT/MATLAB_ENVIRONMENT.txt"
[[ -s "$RUN_ROOT/MATLAB_ENVIRONMENT.txt" ]] || {
  echo "MATLAB product inventory is missing from the core log" >&2
  exit 1
}

completed_at="$(date -Is)"
verify_runtime_package
verify_design_choices
cttrend_verify_sha256_inventory \
  "$RUN_ROOT/status_inventory.sha256" "$RUN_ROOT"
run_complete_pending="$RUN_ROOT/RUN_COMPLETE.pending.$$"
{
  printf 'format=cttrend-run-complete-v1\n'
  printf 'run_stamp=%s\n' "$RUN_STAMP"
  printf 'research_run_id=%s\n' "$RESEARCH_RUN_ID"
  printf 'data_build_id=%s\n' "$DATA_BUILD_ID"
  printf 'code_fingerprint=%s\n' "$CODE_FINGERPRINT"
  printf 'started_at=%s\n' "$STARTED_AT"
  printf 'completed_at=%s\n' "$completed_at"
  printf 'runtime_package_sha256=%s\n' \
    "$EXPECTED_RUNTIME_PACKAGE_SHA256"
  printf 'orchestrator_sha256=%s\n' \
    "$(sha256sum "$RUNNER_DIR/run_production.sh" | awk '{print $1}')"
  printf 'b09_launch_runner_sha256=%s\n' \
    "$(sha256sum "$RUNNER_DIR/launch_b09_shards.sh" | awk '{print $1}')"
  printf 'b09_shard_runner_sha256=%s\n' \
    "$(sha256sum "$RUNNER_DIR/run_b09_shard.sh" | awk '{print $1}')"
  printf 'b09_merge_runner_sha256=%s\n' \
    "$(sha256sum "$RUNNER_DIR/merge_b09_shards.sh" | awk '{print $1}')"
  printf 'b09_merge_matlab_sha256=%s\n' \
    "$(sha256sum "$RUNNER_DIR/merge_b09_shards.m" | awk '{print $1}')"
  printf 'b09_source_validator_sha256=%s\n' \
    "$(sha256sum "$RUNNER_DIR/fCollectB09ValidatedSources.m" | awk '{print $1}')"
  printf 'owned_process_runner_sha256=%s\n' \
    "$(sha256sum "$RUNNER_DIR/run_owned_process.sh" | awk '{print $1}')"
  printf 'runner_source_inventory_sha256=%s\n' \
    "$(sha256sum "$RUN_ROOT/runner_source_inventory.sha256" | awk '{print $1}')"
  printf 'runner_snapshot_inventory_sha256=%s\n' \
    "$(sha256sum "$RUN_ROOT/runner_snapshot_inventory.sha256" | awk '{print $1}')"
  printf 'source_inventory_sha256=%s\n' \
    "$(sha256sum "$RUN_ROOT/source_code_inventory.sha256" | awk '{print $1}')"
  printf 'runtime_inventory_sha256=%s\n' \
    "$(sha256sum "$RUN_ROOT/runtime_code_inventory.sha256" | awk '{print $1}')"
  printf 'raw_input_inventory_sha256=%s\n' \
    "$(sha256sum "$RUN_ROOT/raw_inputs.sha256" | awk '{print $1}')"
  printf 'raw_input_sources_sha256=%s\n' \
    "$(sha256sum "$RUN_ROOT/raw_input_sources.tsv" | awk '{print $1}')"
  printf 'raw_source_publish_inventory_sha256=%s\n' \
    "$(sha256sum "$RUN_ROOT/raw_input_sources_at_publish.sha256" | awk '{print $1}')"
  printf 'data_before_inventory_sha256=%s\n' \
    "$(sha256sum "$RUN_ROOT/data_before.sha256" | awk '{print $1}')"
  printf 'data_after_inventory_sha256=%s\n' \
    "$(sha256sum "$RUN_ROOT/data_after.sha256" | awk '{print $1}')"
  printf 'results_inventory_sha256=%s\n' \
    "$(sha256sum "$RUN_ROOT/results.sha256" | awk '{print $1}')"
  printf 'status_inventory_sha256=%s\n' \
    "$(sha256sum "$RUN_ROOT/status_inventory.sha256" | awk '{print $1}')"
  printf 'design_choices_sha256=%s\n' \
    "$EXPECTED_DESIGN_CHOICES_SHA256"
  printf 'matlab_environment_sha256=%s\n' \
    "$(sha256sum "$RUN_ROOT/MATLAB_ENVIRONMENT.txt" | awk '{print $1}')"
  printf 'result_file_count=%s\n' \
    "$(wc -l < "$RUN_ROOT/results.sha256")"
  printf 'b09_combo_count=%s\n' "$combo_count"
  printf 'core_workers=64\n'
  printf 'b09_shards=%s\n' "$B09_NUM_SHARDS"
  printf 'b09_workers_per_shard=%s\n' "$B09_WORKERS_PER_SHARD"
  printf 'b09_total_workers=%s\n' \
    "$((B09_NUM_SHARDS * B09_WORKERS_PER_SHARD))"
  printf 'b09_processes_plus_clients=%s\n' \
    "$((B09_NUM_SHARDS * (B09_WORKERS_PER_SHARD + 1)))"
  printf 'phase_exit_grace_seconds=%s\n' "$PHASE_EXIT_GRACE_SECONDS"
  printf 'unit_tests_rc=0\n'
  printf 'core_phase_rc=0\n'
  printf 'baseline_downstream_rc=0\n'
  printf 'canonical_combo1_rc=0\n'
  printf 'b09_shards_rc=0\n'
  printf 'b09_merge_rc=0\n'
  printf 'b10_rc=0\n'
  printf 'supplementary_rc=0\n'
  printf 'matlab_bin=%s\n' "$MATLAB_BIN"
  printf 'matlab_version=%s\n' "$MATLAB_VERSION"
  printf 'matlab_release=%s\n' "$MATLAB_RELEASE"
  printf 'published_data=%s\n' "$PUBLISHED_DATA"
  printf 'published_results=%s\n' "$PUBLISHED_RESULTS"
  printf 'canonical_bundle_pointer=%s\n' "$CANONICAL_CURRENT_LINK"
  printf 'publication_protocol=complete-marker-then-atomic-bundle-swap-v1\n'
  printf 'host=%s\n' "$(hostname)"
  printf 'kernel=%s\n' "$(uname -srvmo)"
} > "$run_complete_pending"

[[ -L "$CANONICAL_CURRENT_LINK" &&
   "$(readlink -f "$CANONICAL_CURRENT_LINK")" == \
     "$CANONICAL_START_BUNDLE" &&
   "$(readlink "$SOURCE_CODE_DIR/DATA")" == "$CANONICAL_DATA_ALIAS" &&
   "$(readlink "$SOURCE_CODE_DIR/Results")" == "$CANONICAL_RESULTS_ALIAS" &&
   "$(readlink "$SOURCE_CODE_DIR/DesignChoices.mat")" == \
     "$CANONICAL_DESIGN_ALIAS" ]] || {
  echo "Canonical bundle aliases changed during execution" >&2
  exit 1
}
[[ -w "$CANONICAL_ROOT" ]] || {
  echo "Canonical source directory is not writable for atomic publication" >&2
  exit 1
}
mv -- "$STAGING_DATA" "$PUBLISHED_DATA"
mv -- "$STAGING_RESULTS" "$PUBLISHED_RESULTS"
cttrend_atomic_symlink "$PUBLISHED_DATA" "$CODE_DIR/DATA"
cttrend_atomic_symlink "$PUBLISHED_RESULTS" "$CODE_DIR/Results"

# Remove all preference/job-storage credentials before publishing a success
# marker.  A cleanup failure leaves the prior canonical bundle untouched.
cttrend_safe_remove_temp_dir "$JOB_STORAGE_ROOT" \
  "$JOB_STORAGE_ALLOWED_ROOT"
JOB_STORAGE_CLEANED=1

# Seal the fully validated run before it becomes reachable from the
# canonical pointer.  If activation fails, the run remains a coherent
# completed-but-unpublished bundle and receives RUN_PUBLICATION_FAILED;
# the prior canonical bundle remains active.
mv -f -- "$run_complete_pending" "$RUN_ROOT/RUN_COMPLETE"
cttrend_verify_sha256_inventory \
  "$RUN_ROOT/status_inventory.sha256" "$RUN_ROOT"

# DATA, Results, and DesignChoices all live under the already sealed
# RUN_ROOT.  Swapping this one pointer publishes the complete triple
# atomically; canonical can never point at a bundle lacking RUN_COMPLETE.
cttrend_atomic_symlink "$RUN_ROOT" "$CANONICAL_CURRENT_LINK"
if [[ "$(readlink -f "$SOURCE_CODE_DIR/DATA")" != "$PUBLISHED_DATA" ||
      "$(readlink -f "$SOURCE_CODE_DIR/Results")" != "$PUBLISHED_RESULTS" ||
      "$(readlink -f "$SOURCE_CODE_DIR/DesignChoices.mat")" != \
        "$RUN_ROOT/DesignChoices.mat" ]]; then
  # Activation is the only post-seal mutation of canonical state. Restore
  # the exact previous bundle atomically if its resolution check fails.
  cttrend_atomic_symlink "$CANONICAL_START_BUNDLE" \
    "$CANONICAL_CURRENT_LINK" || true
  [[ "$(readlink -f "$CANONICAL_CURRENT_LINK")" == \
      "$CANONICAL_START_BUNDLE" ]] || {
    echo "Canonical activation failed and rollback also failed" >&2
    exit 1
  }
  echo "Published canonical bundle failed resolution checks" >&2
  exit 1
fi

# Latest-successful pointers are conveniences layered on the atomic
# canonical pointer and are advanced only after activation succeeds.
pointer_update_failed=0
cttrend_atomic_write_pointer \
  "$SOURCE_CODE_DIR/logs/latest_successful_run_path.txt" "$RUN_ROOT" ||
  pointer_update_failed=1
cttrend_atomic_write_pointer \
  "$SOURCE_CODE_DIR/logs/latest_successful_data_path.txt" \
  "$PUBLISHED_DATA" || pointer_update_failed=1
cttrend_atomic_write_pointer \
  "$SOURCE_CODE_DIR/logs/latest_successful_results_path.txt" \
  "$PUBLISHED_RESULTS" || pointer_update_failed=1
cttrend_atomic_write_pointer \
  "$SOURCE_CODE_DIR/logs/latest_corrected_recompute_path.txt" "$RUN_ROOT" ||
  pointer_update_failed=1
if (( pointer_update_failed != 0 )); then
  printf 'warning: canonical bundle is complete but a convenience pointer failed\n' \
    >&2
fi

{
  printf 'activated_at=%s\n' "$(date -Is)"
  printf 'run_id=%s\n' "$RESEARCH_RUN_ID"
  printf 'data_build_id=%s\n' "$DATA_BUILD_ID"
  printf 'run_root=%s\n' "$RUN_ROOT"
  printf 'previous_bundle=%s\n' "$CANONICAL_START_BUNDLE"
} > "$RUN_ROOT/ACTIVATION.env"
