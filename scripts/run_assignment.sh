#!/usr/bin/env bash
# CTREND_REVISIT_FILE_PURPOSE: Run a registry-defined sequence of experiments assigned to one host, one experiment at a time.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HOST_LABEL="${1:-}"
ASSIGNMENT="${2:-}"
[[ "$HOST_LABEL" =~ ^[A-Za-z0-9_.-]+$ && -f "$ASSIGNMENT" ]] || {
  echo "usage: $0 HOST_LABEL /absolute/or/relative/assignment.csv" >&2; exit 2;
}
ASSIGNMENT="$(readlink -f -- "$ASSIGNMENT")"
[[ -z "${RUN_ROOT:-}" && -z "${JOB_STORAGE_ROOT:-}" ]] || {
  echo 'assignment does not accept a shared RUN_ROOT or JOB_STORAGE_ROOT.' >&2
  echo 'Set only RUN_BASE and WORK_BASE; each experiment creates isolated paths.' >&2
  exit 2
}

ASSIGNED="$(python3 - "$ASSIGNMENT" "$HOST_LABEL" <<'PY'
import csv, sys
path, host = sys.argv[1:]
valid = {
    "M0_D0", "M0_D1", "M0_D2", "M1_D0", "M1_D1", "M1_D2",
    "M2_D0", "M2_D1", "M2_D2",
}
rows = list(csv.DictReader(open(path, newline="", encoding="utf-8")))
assert rows and set(rows[0]) >= {"host", "sequence", "experiment_id"}
all_ids = [r["experiment_id"] for r in rows]
if all(x.startswith('P') for x in all_ids):
    valid={f'P{p}_M{m}_D{d}' for p in range(2) for m in range(3) for d in range(3)}
assert len(rows) == len(valid) and set(all_ids) == valid and len(all_ids) == len(set(all_ids)), \
    "assignment must contain every experiment exactly once"
assert all(r["host"] and r["sequence"].isdigit() and int(r["sequence"]) > 0 \
           for r in rows), "host labels and positive integer sequences are required"
for assigned_host in {r["host"] for r in rows}:
    sequences = [int(r["sequence"]) for r in rows if r["host"] == assigned_host]
    assert len(sequences) == len(set(sequences)), \
        f"duplicate sequence within host {assigned_host}"
chosen = [r for r in rows if r["host"] == host]
assert chosen, f"no assignments for host {host}"
chosen.sort(key=lambda r: int(r["sequence"]))
ids = [r["experiment_id"] for r in chosen]
print("\n".join(ids))
PY
)"
mapfile -t IDS <<< "$ASSIGNED"

echo "ASSIGNMENT_START host=$HOST_LABEL experiments=${IDS[*]}"
for id in "${IDS[@]}"; do
  if [[ "$id" == P* ]]; then
    if [[ -s "$ROOT/outputs/experiments/$id/PMD_REGISTRATION.env" ]]; then
      python3 "$ROOT/scripts/verify_pmd_registrations.py" "$id"
    else
      "$ROOT/scripts/run_pmd_experiment.sh" "$id" production
    fi
    continue
  fi
  if [[ -s "$ROOT/outputs/experiments/$id/registration.env" ]]; then
    echo "SKIP_REGISTERED experiment=$id"
  else
    "$ROOT/scripts/run_experiment.sh" "$id" production
  fi
done
echo "ASSIGNMENT_COMPLETE host=$HOST_LABEL"
