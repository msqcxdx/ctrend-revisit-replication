#!/usr/bin/env bash
# Shared safety helpers for corrected-pipeline launch scripts.
#
# This file intentionally contains no empirical or numerical choices.

cttrend_prepare_temp_dir() {
  local target="$1"
  local allowed_root="$2"
  local purpose="${3:-runtime}"
  local target_resolved
  local root_resolved
  local marker

  [[ -n "$target" && -n "$allowed_root" ]] || {
    echo "temporary directory and allowed root must be non-empty" >&2
    return 2
  }
  [[ ! -L "$target" ]] || {
    echo "refusing a symlink as a temporary directory: $target" >&2
    return 2
  }
  target_resolved="$(realpath -m -- "$target")"
  root_resolved="$(realpath -m -- "$allowed_root")"
  [[ "$target_resolved" == "$root_resolved/"* ]] || {
    echo "temporary directory escapes allowed root: $target_resolved" >&2
    return 2
  }
  [[ "$target_resolved" != "$root_resolved" ]] || {
    echo "temporary directory may not equal its allowed root" >&2
    return 2
  }

  marker="$target_resolved/.cttrend_owned_temp"
  if [[ -e "$target_resolved" && ! -f "$marker" ]]; then
    echo "refusing an unmarked pre-existing temporary directory: $target_resolved" >&2
    return 2
  fi
  mkdir -p -- "$target_resolved"
  {
    printf 'format=cttrend-owned-temp-v1\n'
    printf 'owner_uid=%s\n' "$(id -u)"
    printf 'allowed_root=%s\n' "$root_resolved"
    printf 'purpose=%s\n' "$purpose"
    printf 'created_at=%s\n' "$(date -Is)"
  } > "$marker"
}

cttrend_safe_remove_temp_dir() {
  local target="$1"
  local allowed_root="$2"
  local target_resolved
  local root_resolved
  local marker
  local marker_uid
  local marker_root

  [[ -n "$target" && -n "$allowed_root" ]] || return 2
  [[ -e "$target" || -L "$target" ]] || return 0
  [[ ! -L "$target" ]] || {
    echo "refusing to remove a temporary-directory symlink: $target" >&2
    return 2
  }
  target_resolved="$(realpath -m -- "$target")"
  root_resolved="$(realpath -m -- "$allowed_root")"
  [[ "$target_resolved" == "$root_resolved/"* &&
     "$target_resolved" != "$root_resolved" ]] || {
    echo "refusing temporary cleanup outside allowed root: $target_resolved" >&2
    return 2
  }
  marker="$target_resolved/.cttrend_owned_temp"
  [[ -f "$marker" && ! -L "$marker" ]] || {
    echo "refusing to remove unmarked temporary directory: $target_resolved" >&2
    return 2
  }
  marker_uid="$(awk -F= '$1 == "owner_uid" { print $2; exit }' "$marker")"
  marker_root="$(awk -F= '$1 == "allowed_root" { print substr($0,index($0,"=")+1); exit }' "$marker")"
  [[ "$marker_uid" == "$(id -u)" && "$marker_root" == "$root_resolved" ]] || {
    echo "temporary-directory marker does not match this run: $target_resolved" >&2
    return 2
  }
  rm -rf -- "$target_resolved"
}

cttrend_atomic_write_pointer() {
  local pointer="$1"
  local value="$2"
  local temporary="${pointer}.tmp.$$"
  mkdir -p -- "$(dirname "$pointer")"
  printf '%s\n' "$value" > "$temporary"
  mv -f -- "$temporary" "$pointer"
}

cttrend_atomic_symlink() {
  local target="$1"
  local link_name="$2"
  local temporary="${link_name}.tmp.$$"
  mkdir -p -- "$(dirname "$link_name")"
  [[ ! -e "$temporary" && ! -L "$temporary" ]] || {
    echo "temporary symlink path already exists: $temporary" >&2
    return 2
  }
  ln -s -- "$target" "$temporary"
  mv -Tf -- "$temporary" "$link_name"
}

cttrend_process_group_exists() {
  local pgid="$1"
  [[ "$pgid" =~ ^[1-9][0-9]*$ ]] || return 1
  ps -eo pgid= | awk -v expected="$pgid" \
    '$1 == expected { found=1; exit } END { exit !found }'
}

cttrend_wait_for_process_group_exit() {
  local pgid="$1"
  local grace_seconds="$2"
  local deadline
  [[ "$pgid" =~ ^[1-9][0-9]*$ &&
     "$grace_seconds" =~ ^[1-9][0-9]*$ ]] || {
    echo "invalid process-group exit wait request" >&2
    return 2
  }
  deadline=$(( $(date +%s) + grace_seconds ))
  while cttrend_process_group_exists "$pgid" &&
      (( $(date +%s) < deadline )); do
    sleep 1
  done
  ! cttrend_process_group_exists "$pgid"
}

cttrend_verify_source_map() {
  local source_map="$1"
  local output_inventory="$2"
  local expected_count="$3"
  local temporary="${output_inventory}.tmp.$$"
  local raw_name
  local expected_sha
  local source_path
  local current_sha
  local count=0

  [[ -f "$source_map" && ! -L "$source_map" &&
     "$expected_count" =~ ^[1-9][0-9]*$ ]] || {
    echo "invalid sealed-source verification request" >&2
    return 2
  }
  : > "$temporary"
  while IFS=$'\t' read -r raw_name expected_sha source_path; do
    [[ -n "$raw_name" && "$expected_sha" =~ ^[0-9a-f]{64}$ &&
       -f "$source_path" && ! -L "$source_path" ]] || {
      echo "sealed source row is invalid at publication: $raw_name" >&2
      rm -f -- "$temporary"
      return 1
    }
    current_sha="$(sha256sum -- "$source_path" | awk '{print $1}')"
    [[ "$current_sha" == "$expected_sha" ]] || {
      echo "sealed source changed during execution: $source_path" >&2
      rm -f -- "$temporary"
      return 1
    }
    printf '%s  %s\n' "$current_sha" "$source_path" >> "$temporary"
    count=$((count + 1))
  done < "$source_map"
  [[ "$count" -eq "$expected_count" ]] || {
    echo "sealed source publication inventory is incomplete" >&2
    rm -f -- "$temporary"
    return 1
  }
  mv -f -- "$temporary" "$output_inventory"
}

cttrend_verify_sha256_inventory() {
  local inventory="$1"
  local root="$2"
  [[ -f "$inventory" && ! -L "$inventory" && -d "$root" ]] || {
    echo "invalid SHA-256 inventory verification request" >&2
    return 2
  }
  (
    cd "$root" || exit 2
    sha256sum --status -c "$inventory"
  )
}
