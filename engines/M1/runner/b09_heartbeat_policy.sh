#!/usr/bin/env bash
# CTREND_REVISIT_FILE_PURPOSE: Decide whether an M1 b09 heartbeat observation is healthy, needs confirmation, or is safe to terminate.

cttrend_b09_heartbeat_refresh_state() {
  if [[ "$#" -ne 4 ]]; then
    echo "usage: cttrend_b09_heartbeat_refresh_state OBSERVED_EPOCH CONFIRMED_EPOCH CONFIRMED_AGE STALE_LIMIT" >&2
    return 2
  fi
  local observed_epoch="$1"
  local confirmed_epoch="$2"
  local confirmed_age="$3"
  local stale_limit="$4"

  [[ "$confirmed_age" =~ ^[0-9]+$ && "$stale_limit" =~ ^[0-9]+$ ]] || {
    echo "heartbeat-refresh ages must be nonnegative integers" >&2
    return 2
  }
  if [[ "$confirmed_epoch" != "$observed_epoch" ]] ||
      (( confirmed_age <= stale_limit )); then
    printf 'REFRESHED\n'
  else
    printf 'STILL_STALE\n'
  fi
}

cttrend_b09_heartbeat_decision() {
  if [[ "$#" -ne 7 ]]; then
    echo "usage: cttrend_b09_heartbeat_decision HEARTBEAT_AGE STALE_LIMIT OBSERVATIONS REQUIRED_OBSERVATIONS PROGRESS_AGE NO_PROGRESS_LIMIT MATLAB_LIVE" >&2
    return 2
  fi

  local heartbeat_age="$1"
  local stale_limit="$2"
  local observations="$3"
  local required_observations="$4"
  local progress_age="$5"
  local no_progress_limit="$6"
  local matlab_live="$7"
  local value

  for value in "$heartbeat_age" "$stale_limit" "$observations" \
      "$required_observations" "$progress_age" "$no_progress_limit"; do
    [[ "$value" =~ ^[0-9]+$ ]] || {
      echo "heartbeat-policy inputs must be nonnegative integers" >&2
      return 2
    }
  done
  [[ "$required_observations" -ge 2 && \
     ( "$matlab_live" == "0" || "$matlab_live" == "1" ) ]] || {
    echo "heartbeat-policy confirmation count or MATLAB state is invalid" >&2
    return 2
  }

  if (( heartbeat_age <= stale_limit )); then
    printf 'HEALTHY\n'
  elif (( observations < required_observations )); then
    printf 'WARN_STALE\n'
  elif (( matlab_live == 1 && progress_age <= no_progress_limit )); then
    printf 'DEFER_RECENT_PROGRESS\n'
  else
    printf 'TERMINATE_CONFIRMED_STALE\n'
  fi
}
