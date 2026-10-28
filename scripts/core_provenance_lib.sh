#!/usr/bin/env bash
# CTREND_REVISIT_FILE_PURPOSE: Provide shared fail-closed hashing, path, inventory, and process-ownership functions to package runners.
# Shared fail-closed provenance and process helpers for the isolated core runs.

core_die() {
  echo "$*" >&2
  return 1
}

core_atomic_from_stdin() {
  local target="$1" temporary
  mkdir -p -- "$(dirname -- "$target")"
  temporary="${target}.tmp.$$.$RANDOM"
  [[ ! -e "$temporary" && ! -L "$temporary" ]] || return 2
  cat > "$temporary"
  mv -Tf -- "$temporary" "$target"
}

core_atomic_symlink() {
  local target="$1" link_name="$2" temporary
  mkdir -p -- "$(dirname -- "$link_name")"
  temporary="${link_name}.tmp.$$.$RANDOM"
  [[ ! -e "$temporary" && ! -L "$temporary" ]] || return 2
  ln -s -- "$target" "$temporary"
  mv -Tf -- "$temporary" "$link_name"
}

core_manifest_entry() {
  local root="$1" relative="$2" kind sha bytes target
  case "$relative" in
    *$'\t'*|*$'\n'*) core_die "unsafe tab/newline in manifest path: $relative"; return ;;
  esac
  if [[ -L "$root/$relative" ]]; then
    kind=L
    target="$(readlink -- "$root/$relative")"
    case "$target" in
      *$'\t'*|*$'\n'*) core_die "unsafe tab/newline in symlink target: $relative"; return ;;
    esac
    sha="$(printf '%s' "$target" | sha256sum | awk '{print $1}')"
    bytes="$(printf '%s' "$target" | wc -c)"
    printf '%s\t%s\t%s\t%s\t%s\n' "$kind" "$sha" "$bytes" "$relative" "$target"
  elif [[ -f "$root/$relative" ]]; then
    kind=F
    sha="$(sha256sum -- "$root/$relative" | awk '{print $1}')"
    bytes="$(stat -c %s -- "$root/$relative")"
    printf '%s\t%s\t%s\t%s\t\n' "$kind" "$sha" "$bytes" "$relative"
  else
    core_die "manifest member is not a regular file or symlink: $root/$relative"
  fi
}

core_write_manifest_from_find() {
  local root="$1" output="$2" mode="$3" temporary special
  [[ -d "$root" && ! -L "$root" ]] || core_die "invalid manifest root: $root"
  root="$(readlink -f -- "$root")"
  special="$(find "$root" ! -type d ! -type f ! -type l -print -quit)"
  [[ -z "$special" ]] || {
    core_die "manifest root contains an unsupported filesystem object: $special"
    return
  }
  temporary="${output}.tmp.$$.$RANDOM"
  (
    cd "$root"
    case "$mode" in
      all)
        find . \( -type f -o -type l \) -print0
        ;;
      engine)
        find . -path './.raw_input_seed' -prune -o \
          \( -type f -o -type l \) -print0
        ;;
      runtime_engine)
        find . \
          \( -path './DATA' -o -path './Results' -o -path './logs' -o \
             -path './event_registry' -o -path './DesignChoices.mat' \) -prune -o \
          \( -type f -o -type l \) -print0
        ;;
      *) core_die "unknown manifest mode: $mode" ;;
    esac | sort -z | while IFS= read -r -d '' relative; do
      core_manifest_entry "$root" "$relative"
    done
  ) > "$temporary"
  [[ -s "$temporary" ]] || {
    rm -f -- "$temporary"
    core_die "empty manifest for $root"
    return
  }
  mv -Tf -- "$temporary" "$output"
}

core_write_tree_manifest() {
  core_write_manifest_from_find "$1" "$2" all
}

core_write_engine_manifest() {
  core_write_manifest_from_find "$1" "$2" engine
}

core_write_runtime_engine_manifest() {
  core_write_manifest_from_find "$1" "$2" runtime_engine
}

core_write_named_regular_manifest() {
  local root="$1" output="$2"
  shift 2
  local temporary="${output}.tmp.$$.$RANDOM" name
  [[ -d "$root" && ! -L "$root" ]] || core_die "invalid named-file root: $root"
  root="$(readlink -f -- "$root")"
  : > "$temporary"
  for name in "$@"; do
    [[ "$name" != */* && -f "$root/$name" && ! -L "$root/$name" ]] || {
      rm -f -- "$temporary"
      core_die "required source is not a regular local file: $root/$name"
      return
    }
    core_manifest_entry "$root" "./$name" >> "$temporary"
  done
  [[ -s "$temporary" ]] || {
    rm -f -- "$temporary"
    core_die "empty named-file manifest for $root"
    return
  }
  mv -Tf -- "$temporary" "$output"
}

core_compare_manifests() {
  local expected="$1" observed="$2" label="$3"
  if ! cmp -s -- "$expected" "$observed"; then
    echo "$label manifest mismatch" >&2
    diff -u -- "$expected" "$observed" >&2 || true
    return 1
  fi
}

core_verify_manifest_members() {
  local root="$1" manifest="$2" kind expected_sha bytes relative target observed
  [[ -d "$root" && -s "$manifest" ]] || return 2
  while IFS=$'\t' read -r kind expected_sha bytes relative target; do
    [[ "$expected_sha" =~ ^[0-9a-f]{64}$ && -n "$relative" ]] || return 1
    case "$kind" in
      F)
        [[ -f "$root/$relative" && ! -L "$root/$relative" ]] || return 1
        [[ "$(stat -c %s -- "$root/$relative")" == "$bytes" ]] || return 1
        observed="$(sha256sum -- "$root/$relative" | awk '{print $1}')"
        ;;
      L)
        [[ -L "$root/$relative" && "$(readlink -- "$root/$relative")" == "$target" ]] || return 1
        observed="$(printf '%s' "$target" | sha256sum | awk '{print $1}')"
        ;;
      *) return 1 ;;
    esac
    [[ "$observed" == "$expected_sha" ]] || return 1
  done < "$manifest"
}

core_assert_no_symlinks() {
  local root="$1" first
  [[ -d "$root" && ! -L "$root" ]] || core_die "invalid no-symlink root: $root"
  first="$(find "$root" -type l -print -quit)"
  [[ -z "$first" ]] || core_die "runtime symlink is forbidden: $first"
}

core_assert_only_regular_tree() {
  local root="$1" first
  core_assert_no_symlinks "$root"
  first="$(find "$root" ! -type d ! -type f -print -quit)"
  [[ -z "$first" ]] || core_die "runtime contains a non-regular object: $first"
}

core_process_group_exists() {
  local pgid="$1"
  [[ "$pgid" =~ ^[1-9][0-9]*$ ]] || return 1
  ps -eo pgid= | awk -v expected="$pgid" \
    '$1 == expected { found=1; exit } END { exit !found }'
}

core_wait_process_group_exit() {
  local pgid="$1" grace="$2" deadline
  [[ "$pgid" =~ ^[1-9][0-9]*$ && "$grace" =~ ^[1-9][0-9]*$ ]] || return 2
  deadline=$(( $(date +%s) + grace ))
  while core_process_group_exists "$pgid" && (( $(date +%s) < deadline )); do
    sleep 1
  done
  ! core_process_group_exists "$pgid"
}

core_terminate_process_group() {
  local pgid="$1" grace="${2:-30}" own_pgid
  [[ "$pgid" =~ ^[1-9][0-9]*$ ]] || return 0
  own_pgid="$(ps -o pgid= -p $$ | tr -d ' ')"
  [[ "$pgid" != "$own_pgid" ]] || core_die "refusing to terminate own PGID $pgid"
  core_process_group_exists "$pgid" || return 0
  kill -TERM -- "-$pgid" 2>/dev/null || true
  if ! core_wait_process_group_exit "$pgid" "$grace"; then
    kill -KILL -- "-$pgid" 2>/dev/null || true
    core_wait_process_group_exit "$pgid" 30 || \
      core_die "process group did not terminate: $pgid"
  fi
}

core_runtime_processes_referencing_path() {
  local needle="$1" ignore_pid="${2:-0}"
  ps -eo pid=,pgid=,comm=,args= | awk -v needle="$needle" -v ignore="$ignore_pid" '
    {
      pid=$1
      if (pid == ignore) next
      command=$3
      line=$0
      sub(/^[[:space:]]*[0-9]+[[:space:]]+[0-9]+[[:space:]]+[^[:space:]]+[[:space:]]+/,"",line)
      is_runtime=(command ~ /^(MATLAB|MATLABWorker|matlab)$/ ||
        line ~ /run_full_pipeline_corrected\.sh|run_supplementary_outputs\.sh/)
      if (is_runtime && index(line,needle)>0) print $0
    }'
}

core_env_value() {
  local file="$1" key="$2"
  awk -F= -v key="$key" '$1==key {print substr($0,index($0,"=")+1); exit}' "$file"
}

core_require_marker() {
  local file="$1" format="$2"
  [[ -s "$file" && "$(core_env_value "$file" format)" == "$format" ]]
}

core_sha256() {
  sha256sum -- "$1" | awk '{print $1}'
}
