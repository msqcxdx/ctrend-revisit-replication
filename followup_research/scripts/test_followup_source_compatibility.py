#!/usr/bin/env python3
"""Test source-reconciliation boundaries and E11 coverage with synthetic data.

No research inputs, MATLAB runs, Git history or network access are needed.
Fixtures exercise the actual E11 CSV writer, including missing values and
different training lengths; retained statistics are checked against direct
NumPy calculations. Tests also ensure that a numerical edit cannot masquerade
as an input-path-only change.
"""
import csv
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

import numpy as np

import analyze_e11 as e11
from followup_source_compatibility import compare_sources, ADDED_COVERAGE_FIELDS


class SourceCompatibilityTests(unittest.TestCase):
    def adapter_fixture(self):
        old = b'''from pathlib import Path
RUNS = {"P0_M0_D0": "archive/run0", "P0_M0_D1": "archive/run1", "P0_M0_D2": "archive/run2",
        "P1_M0_D0": "archive/run3", "P1_M0_D1": "archive/run4", "P1_M0_D2": "archive/run5"}
def estimate(x):
    return x.mean()
def main():
    for experiment, run_text in RUNS.items():
        rows, source_paths = analyze_one(experiment, Path(run_text))
'''
        current = b'''from pathlib import Path
from accepted_run_roots import accepted_roots
RUNS = tuple(f"P{p}_M0_D{d}" for p in (0, 1) for d in (0, 1, 2))
def estimate(x):
    return x.mean()
def main():
    for experiment, run in accepted_roots(RUNS).items():
        rows, source_paths = analyze_one(experiment, run)
'''
        return old, current

    def test_input_adapter_preserves_numerical_syntax(self):
        old, current = self.adapter_fixture()
        self.assertEqual(compare_sources("analyze_e02.py", old, current)["scope"], "input_location_only")

    def test_numerical_change_is_not_a_path_adapter(self):
        old, current = self.adapter_fixture()
        with self.assertRaisesRegex(ValueError, "Executable source changed"):
            compare_sources("analyze_e02.py", old, current.replace(b"x.mean()", b"x.mean() * 2"))

    def test_unknown_source_change_is_rejected(self):
        old, current = self.adapter_fixture()
        with self.assertRaisesRegex(ValueError, "No source-compatibility proof"):
            compare_sources("unreviewed.py", old, current)

    def test_changed_experiment_selection_is_rejected(self):
        old, current = self.adapter_fixture()
        with self.assertRaisesRegex(ValueError, "Changed experiment selection"):
            compare_sources("analyze_e02.py", old, current.replace(b"(0, 1, 2)", b"(0, 1)"))

    def test_coverage_denominators_and_invalid_training(self):
        mask = np.array([False, False, True, False, True, True])
        got = e11.coverage(mask, 2)
        self.assertEqual(got["pair_oos_n"], 3)
        self.assertEqual(got["scheduled_oos_weeks"], 4)
        self.assertEqual(got["pair_full_calendar_coverage"], .5)
        self.assertEqual(got["pair_scheduled_oos_coverage"], .75)
        for training in (-1, len(mask)):
            with self.assertRaises(ValueError):
                e11.coverage(mask, training)

    def test_writer_preserves_return_statistics(self):
        rng = np.random.default_rng(1102)
        training = [26, 52, 104]
        n = 140
        arrays = {}
        with tempfile.TemporaryDirectory() as tmp:
            parent = Path(tmp)
            paths = {f"P0_M{m}_D0": str(parent/f"M{m}") for m in (0, 2, 1)}
            for combo, length in enumerate(training, start=1):
                for m in (0, 2, 1):
                    x = rng.normal(.02, .1, (n, len(e11.METHODS)))
                    x[:length] = np.nan
                    x[length::7, 0] = np.nan
                    x[:, 1] = np.nan
                    arrays[(m, combo)] = x
                    path = Path(paths[f"P0_M{m}_D0"])/"CTREND"/f"CTREND_Combo{combo}.mat"
                    path.parent.mkdir(parents=True, exist_ok=True)
                    path.touch()

            def load_fixture(path, **kwargs):
                m = int(path.parent.parent.name[1:])
                combo = int(path.stem.removeprefix("CTREND_Combo"))
                return dict(vDates=np.arange(n), cTrendNames=e11.METHODS, mTrend_5=arrays[(m, combo)])

            with patch.object(e11, "OUT", parent/"output"), patch.object(e11, "loadmat", load_fixture):
                file, count = e11.worker(0, 0, len(training), paths, "fixture", training)
            with Path(file).open(newline="") as stream:
                rows = list(csv.DictReader(stream))
            self.assertEqual(count, len(training)*len(e11.METHODS)*len(e11.PAIRS))
            self.assertEqual(set(rows[0]), set(e11.FIELDS))
            self.assertTrue(ADDED_COVERAGE_FIELDS <= set(rows[0]))
            for row in rows:
                combo = int(row["b09_combo_id"])
                j = e11.METHODS.index(row["method"])
                a = arrays[(int(row["from_method"][1:]), combo)][:, j]
                b = arrays[(int(row["to_method"][1:]), combo)][:, j]
                mask = np.isfinite(a) & np.isfinite(b)
                aa, bb = a[mask], b[mask]

                def sr(x):
                    x = x[np.isfinite(x)]
                    return np.sqrt(52)*x.mean()/x.std(ddof=1) if len(x) >= 3 and x.std(ddof=1) > 0 else np.nan

                expected = dict(from_own_n=np.isfinite(a).sum(), to_own_n=np.isfinite(b).sum(),
                    pair_n=mask.sum(), from_own_sharpe=sr(a), to_own_sharpe=sr(b),
                    from_pair_sharpe=sr(aa), to_pair_sharpe=sr(bb), delta_sharpe_paired=sr(bb)-sr(aa),
                    from_pair_mean_week_pct=100*aa.mean() if len(aa) else np.nan,
                    to_pair_mean_week_pct=100*bb.mean() if len(bb) else np.nan,
                    delta_mean_week_pct=100*(bb-aa).mean() if len(aa) else np.nan,
                    pair_common_coverage=mask.mean(), scheduled_weeks=n,
                    training_calendar_weeks=training[combo-1], scheduled_oos_weeks=n-training[combo-1],
                    pair_oos_n=mask.sum(), pair_full_calendar_coverage=mask.mean(),
                    pair_scheduled_oos_coverage=mask.sum()/(n-training[combo-1]))
                for field, value in expected.items():
                    self.assertTrue(np.isclose(float(row[field]), value, equal_nan=True), (field, row))
            # An input violating the new training-calendar assertion must stop;
            # it must not silently change the saved finite-week counts.
            arrays[(0, 1)][0, 0] = .1
            arrays[(2, 1)][0, 0] = .2
            with patch.object(e11, "OUT", parent/"invalid"), patch.object(e11, "loadmat", load_fixture):
                with self.assertRaisesRegex(RuntimeError, "inside its training schedule"):
                    e11.worker(0, 0, len(training), paths, "fixture", training)


if __name__ == "__main__":
    unittest.main(verbosity=2)
