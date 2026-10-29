#!/usr/bin/env bash
# CTREND_REVISIT_FILE_PURPOSE: Classify a b09 shard only from its atomic completion record, with a bounded final-publication grace period.

# This file is sourced by run_production.sh.  It deliberately does not change
# the caller's shell options.

ctrend_b09_record_value() {
  local file="$1" key="$2"
  [[ -f "$file" ]] || return 1
  awk -F= -v key="$key" \
    '$1 == key { print substr($0,index($0,"=")+1); exit }' "$file"
}

ctrend_b09_observed_terminal_state() {
  local shard_dir="$1" expected_run_id="$2" publication_timeout="$3" now_epoch="$4"
  local completion_file="$shard_dir/completion.env"
  local state_file="$shard_dir/state.env"
  local observed_state updated_epoch age

  [[ -n "$expected_run_id" && "$publication_timeout" =~ ^[1-9][0-9]*$ &&
     "$now_epoch" =~ ^[0-9]+$ ]] || return 2

  # completion.env is created in the shard directory and atomically renamed.
  # Its identity fields, rather than the advisory progress state, authorize
  # the orchestrator to count a shard as complete.
  if [[ -e "$completion_file" ]]; then
    if [[ -f "$completion_file" && -s "$completion_file" &&
          "$(ctrend_b09_record_value "$completion_file" complete 2>/dev/null || true)" == 1 &&
          "$(ctrend_b09_record_value "$completion_file" research_run_id 2>/dev/null || true)" == \
            "$expected_run_id" ]]; then
      printf 'COMPLETE\n'
    else
      printf 'FAILED_INVALID_COMPLETION_RECORD\n'
    fi
    return 0
  fi

  observed_state="$(ctrend_b09_record_value "$state_file" state 2>/dev/null || true)"
  [[ -n "$observed_state" ]] || observed_state=STARTING
  case "$observed_state" in
    FAILED*)
      printf '%s\n' "$observed_state"
      ;;
    STOPPING*)
      printf 'FAILED_%s\n' "$observed_state"
      ;;
    FINALIZING|COMPLETE)
      # COMPLETE without completion.env can be produced only by an older or
      # interrupted publisher.  Treat it as a bounded FINALIZING state, never
      # as success, so filesystem scheduling cannot race the merge.
      updated_epoch="$(ctrend_b09_record_value "$state_file" updated_epoch 2>/dev/null || true)"
      if [[ "$updated_epoch" =~ ^[0-9]+$ ]]; then
        age=$((now_epoch - updated_epoch))
      else
        age=$publication_timeout
      fi
      if (( age >= publication_timeout )); then
        printf 'FAILED_MISSING_COMPLETION_RECORD\n'
      else
        printf 'FINALIZING\n'
      fi
      ;;
    *)
      printf '%s\n' "$observed_state"
      ;;
  esac
}
