#!/usr/bin/env python3
# CTREND_REVISIT_FILE_PURPOSE: Coordinate a fail-closed eighteen-experiment reproduction with explicit fresh/resume semantics and current-run reporting.
"""Do not download data or change a scientific engine. Run from a clean package."""
import argparse
import datetime as dt
import fcntl
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]


def source_identity(root):
    """Bind resume to code, configuration and inputs, excluding generated state."""
    h = hashlib.sha256()
    excluded = {'.git', '.github', 'runtime', 'outputs', '__pycache__', '.pytest_cache'}
    for base, dirs, names in os.walk(root):
        dirs[:] = sorted(d for d in dirs if d not in excluded)
        for name in sorted(names):
            p = Path(base) / name
            rel = p.relative_to(root)
            if name.endswith(('.pyc', '.pyo', '.log', '.pid')) or name.startswith('PACKAGE_MANIFEST.sha256') or str(rel) in {'release/SHA256SUMS', 'release/FILE_MANIFEST.csv'}:
                continue
            h.update(str(rel).encode() + b'\0')
            with p.open('rb') as f:
                for block in iter(lambda: f.read(1024 * 1024), b''):
                    h.update(block)
    return h.hexdigest()


def commands(root, report):
    cli = str(root / 'run_all.sh')
    return [[cli, 'preflight'], [cli, 'test'], [cli, 'plan'],
            [cli, 'all', 'production'], [cli, 'verify-all'],
            [cli, 'b20', '--from-registrations', str(report)]]


def run(root, resume=False):
    matlab = os.environ.get('MATLAB_BIN') or shutil.which('matlab')
    if not matlab or not os.access(matlab, os.X_OK):
        raise RuntimeError('Set MATLAB_BIN to the executable R2023b binary; full reproduction cannot skip MATLAB.')
    os.environ['MATLAB_BIN'] = matlab
    # Inner shell helpers also invoke literal python3. Use the interpreter
    # selected by the root entry consistently, including an activated venv.
    os.environ['PYTHON_BIN'] = sys.executable
    os.environ['PATH'] = str(Path(sys.executable).parent) + os.pathsep + os.environ.get('PATH', os.defpath)
    if os.environ.get('RUN_ROOT') or os.environ.get('JOB_STORAGE_ROOT'):
        raise RuntimeError('Do not supply shared RUN_ROOT/JOB_STORAGE_ROOT; use RUN_BASE and WORK_BASE.')
    # Require generated directories outside the source inventory, or below its
    # ignored runtime/outputs trees; a changing inventory cannot support resume.
    for key in ('RUN_BASE', 'WORK_BASE'):
        value = os.environ.get(key)
        if value:
            p = Path(value)
            if not p.is_absolute():
                raise RuntimeError(f'{key} must be absolute')
            p = p.resolve()
            if p.is_relative_to(root) and not any(p.is_relative_to(root / d) for d in ('runtime', 'outputs')):
                raise RuntimeError(f'{key} inside this package must be below runtime/ or outputs/')
    state = root / 'outputs/reproduction'
    state.mkdir(parents=True, exist_ok=True)
    with (state / 'suite.lock').open('a') as lock:
        fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        binding = state / 'SUITE_STARTED.json'
        existing = list((root / 'outputs/experiments').glob('*/registration.env'))
        existing += list((root / 'outputs/experiments').glob('*/PMD_REGISTRATION.env'))
        if not resume and (binding.exists() or existing):
            raise RuntimeError('Existing execution/registrations found. Use a fresh extraction for a full rerun, or --resume for this suite.')
        if resume and not binding.exists():
            raise RuntimeError('--resume requires this wrapper\'s SUITE_STARTED.json; it cannot adopt unrelated registrations.')
        identity = source_identity(root)
        if resume:
            started = json.loads(binding.read_text())
            if started['source_sha256'] != identity:
                raise RuntimeError('Source/input identity changed; resume refused.')
        else:
            started = {'source_sha256': identity, 'started_utc': dt.datetime.now(dt.timezone.utc).isoformat()}
            binding.write_text(json.dumps(started, indent=2) + '\n')
        attempt = dt.datetime.now(dt.timezone.utc).strftime('%Y%m%dT%H%M%S%fZ')
        logs = state / attempt
        logs.mkdir()
        report = logs / 'reports'
        marker = state / 'REPRODUCTION_COMPLETE.json'
        # A prior successful attestation must not represent an in-progress or
        # failed revalidation. Preserve it within the new attempt, not delete it.
        if marker.exists():
            marker.rename(logs / 'PREVIOUS_REPRODUCTION_COMPLETE.json')
        try:
            for i, cmd in enumerate(commands(root, report), 1):
                print(f'REPRODUCTION_STEP {i}/6 {" ".join(cmd)} log={logs / f"{i:02}.log"}', flush=True)
                with (logs / f'{i:02}.log').open('w') as log:
                    process = subprocess.Popen(cmd, cwd=root, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
                    for line in process.stdout:
                        print(line, end='', flush=True)
                        log.write(line)
                        log.flush()
                    if process.wait():
                        raise RuntimeError(f'Step {i} failed: {cmd}; see {logs}')
            if not (report / 'REPORT_COMPLETE.json').is_file():
                raise RuntimeError('Fresh report completion missing')
            if source_identity(root) != identity:
                raise RuntimeError('Source/input changed during reproduction')
            done = {**started, 'completed_utc': dt.datetime.now(dt.timezone.utc).isoformat(),
                    'reports': str(report.relative_to(root)), 'experiments': 18,
                    'report_complete_sha256': hashlib.sha256((report / 'REPORT_COMPLETE.json').read_bytes()).hexdigest(),
                    'online_acquisition_executed': False}
            temp = logs / 'completion.tmp'
            temp.write_text(json.dumps(done, indent=2) + '\n')
            temp.replace(marker)
            print(f'REPRODUCTION_COMPLETE {marker}', flush=True)
        except BaseException as exc:
            (logs / 'FAILED.json').write_text(json.dumps({'error': str(exc), 'attempt': attempt}, indent=2) + '\n')
            raise


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--resume', action='store_true', help='Revalidate accepted cells and rerun unregistered cells in new roots; never delete failed runs.')
    args = parser.parse_args()
    run(ROOT, args.resume)
