#!/usr/bin/env bash
# CTREND_REVISIT_FILE_PURPOSE: Build a hash-bound b09 payload for an explicitly authorized remote worker.
set -euo pipefail

if [[ "$#" -ne 2 ]]; then
  echo "usage: $0 FULL_RUN_ROOT OUTPUT_TAR_GZ" >&2
  exit 2
fi

FULL_RUN_ROOT="$(readlink -f "$1")"
OUTPUT="$(realpath -m "$2")"
RUNNER_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CODE_DIR="$FULL_RUN_ROOT/runtime/ctrend_old_v2_pipeline"
DATA_DIR="$FULL_RUN_ROOT/data.staging"
PACKAGE="$FULL_RUN_ROOT/runtime_package.tar.gz"
SHARD_ROOT="$FULL_RUN_ROOT/b09_shards"
TEMP_ROOT="$(mktemp -d /tmp/ctrend_old_v2_remote_payload_XXXXXX)"

cleanup() {
  local rc=$?
  trap - EXIT INT TERM
  rm -rf -- "$TEMP_ROOT"
  exit "$rc"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

[[ -f "$FULL_RUN_ROOT/RUN_STARTED.env" && -d "$CODE_DIR" &&
   -d "$DATA_DIR" && -f "$PACKAGE" &&
   -f "$CODE_DIR/DesignChoices.mat" &&
   -f "$DATA_DIR/b0DataOLHC.mat" &&
   -f "$DATA_DIR/bCharacteristicsOLHC_Combo1.mat" &&
   -f "$DATA_DIR/bCharacteristicsOLHC_Combo2.mat" &&
   -f "$DATA_DIR/bCharacteristicsOLHC_Combo3.mat" &&
   -f "$DATA_DIR/bCharacteristicsOLHC_Combo4.mat" ]] || {
  echo "full run has not produced the required b09 handoff inputs" >&2
  exit 2
}
research_run_id="$(awk -F= '$1=="research_run_id"{print $2;exit}' \
  "$FULL_RUN_ROOT/RUN_STARTED.env")"
package_sha="$(awk -F= '$1=="runtime_package_sha256"{print $2;exit}' \
  "$FULL_RUN_ROOT/RUN_STARTED.env")"
[[ "$research_run_id" =~ ^[0-9a-fA-F-]{36}$ &&
   "$package_sha" =~ ^[0-9a-f]{64}$ &&
   "$(sha256sum "$PACKAGE" | awk '{print $1}')" == "$package_sha" ]] || {
  echo "full-run package identity is invalid" >&2
  exit 2
}
design_sha="$(sha256sum "$CODE_DIR/DesignChoices.mat" | awk '{print $1}')"
if [[ -f "$FULL_RUN_ROOT/design_choices_after_b00.sha256" ]]; then
  expected_design_sha="$(awk '{print $1;exit}' \
    "$FULL_RUN_ROOT/design_choices_after_b00.sha256")"
  [[ "$design_sha" == "$expected_design_sha" ]] || {
    echo "DesignChoices differs from its post-b00 freeze" >&2
    exit 2
  }
fi

PAYLOAD_ROOT="$TEMP_ROOT/ctrend_old_v2_b09_remote_payload"
INPUT_DIR="$PAYLOAD_ROOT/input"
mkdir -p "$INPUT_DIR/runner" "$INPUT_DIR/DATA"
cp -- "$PACKAGE" \
  "$INPUT_DIR/ctrend_old_v2_pipeline.tar.gz"
cp -L -- "$CODE_DIR/DesignChoices.mat" "$INPUT_DIR/DesignChoices.mat"
cp -aL -- "$DATA_DIR/." "$INPUT_DIR/DATA/"
cp -- "$RUNNER_DIR/b09_two_shard_topology.tsv" "$INPUT_DIR/"
for runner_file in run_b09_shard.sh run_owned_process.sh \
    run_b09_remote_worker.sh stop_b09_remote_worker.sh \
    pack_b09_remote_return.sh; do
  cp -- "$RUNNER_DIR/$runner_file" "$INPUT_DIR/runner/"
done

write_runtime_source_inventory() {
  local source_dir="$1"
  (
    cd "$source_dir"
    {
      find . -maxdepth 1 -type f \
        \( -name '*.m' -o -name '*.sh' \) \
        ! -name 'tmp_*' -printf '%P\n'
      for source_subdir in Utils LatexTables tests; do
        if [[ -d "$source_subdir" ]]; then
          find "$source_subdir" -type f -name '*.m' \
            ! -name 'tmp_*' -printf '%p\n'
        fi
      done
    } | LC_ALL=C sort | while IFS= read -r relative; do
      digest="$(sha256sum "$relative")"
      printf '%s  %s\n' "${digest%% *}" "$relative"
    done
  )
}

write_runtime_source_inventory "$CODE_DIR" \
  > "$INPUT_DIR/canonical_matlab_sources.sha256"
(
  cd "$INPUT_DIR/DATA"
  find -L . -maxdepth 1 -type f -printf '%P\0' |
    LC_ALL=C sort -z | xargs -0 -r sha256sum
) > "$INPUT_DIR/data_inputs.sha256"
(
  cd "$INPUT_DIR/runner"
  sha256sum run_b09_shard.sh run_owned_process.sh \
    run_b09_remote_worker.sh stop_b09_remote_worker.sh
) > "$INPUT_DIR/remote_runner_inputs.sha256"
{
  printf 'format=ctrend-old-v2-b09-remote-payload-v1\n'
  printf 'research_run_id=%s\n' "$research_run_id"
  printf 'expected_package_sha256=%s\n' "$package_sha"
  printf 'expected_design_choices_sha256=%s\n' "$design_sha"
  printf 'first_combo=1537\n'
  printf 'last_combo=3072\n'
  printf 'payload_created_at=%s\n' "$(date -Is)"
  printf 'source_full_run_root=%s\n' "$FULL_RUN_ROOT"
} > "$PAYLOAD_ROOT/REMOTE_RUN.env"
(
  cd "$PAYLOAD_ROOT"
  find . -type f ! -name PAYLOAD_MANIFEST.sha256 -printf '%P\0' |
    LC_ALL=C sort -z | xargs -0 -r sha256sum
) > "$PAYLOAD_ROOT/PAYLOAD_MANIFEST.sha256"

mkdir -p "$(dirname "$OUTPUT")"
temporary_output="${OUTPUT}.tmp.$$"
tar -czf "$temporary_output" -C "$TEMP_ROOT" \
  ctrend_old_v2_b09_remote_payload
archive_sha="$(sha256sum "$temporary_output" | awk '{print $1}')"
mv -f -- "$temporary_output" "$OUTPUT"
printf '%s  %s\n' "$archive_sha" "$(basename "$OUTPUT")" \
  > "$OUTPUT.sha256"
printf 'payload=%s\nsha256=%s\nresearch_run_id=%s\n' \
  "$OUTPUT" "$archive_sha" "$research_run_id"
