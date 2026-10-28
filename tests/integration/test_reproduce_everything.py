#!/usr/bin/env python3
# CTREND_REVISIT_FILE_PURPOSE: Test full-suite orchestration, stale-result rejection, actual-date common support, and fresh report export without starting MATLAB.
# Synthetic integration test: temporary registrations and small MAT fixtures
# exercise orchestration, failure recovery, and reporting without invoking a
# real MATLAB pipeline.  It specifically rejects adoption of stale outputs.
import contextlib
import importlib.util
import io
import json
import os
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch
import zipfile

import numpy as np
from scipy.io import savemat

ROOT = Path(__file__).resolve().parents[2]


def load(name, directory='scripts'):
    spec = importlib.util.spec_from_file_location(name, ROOT / directory / f'{name}.py')
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


suite = load('reproduce_everything')
report = load('report_registered_runs')
acquisition = load('run_acquisition_tests', 'tests')


class ReproductionTests(unittest.TestCase):
    # Each case receives an isolated project-like root; no repository result is mutated.
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)

    def test_no_stale_registration_adoption(self):
        # An existing registration cannot be adopted as if this invocation produced it.
        reg = self.root / 'outputs/experiments/P0_M0_D0/registration.env'
        reg.parent.mkdir(parents=True)
        reg.write_text('old=1\n')
        with patch.dict(os.environ, {'MATLAB_BIN': sys.executable}, clear=True):
            with self.assertRaisesRegex(RuntimeError, 'Existing execution'):
                suite.run(self.root)
            with self.assertRaisesRegex(RuntimeError, 'requires'):
                suite.run(self.root, resume=True)

    def test_source_identity_ignores_logs_but_not_inputs(self):
        # Volatile logs are excluded from source identity; frozen inputs are not.
        (self.root / 'input.csv').write_text('1\n')
        initial = suite.source_identity(self.root)
        (self.root / 'reproduction.log').write_text('progress changed\n')
        self.assertEqual(suite.source_identity(self.root), initial)
        (self.root / 'input.csv').write_text('2\n')
        self.assertNotEqual(suite.source_identity(self.root), initial)

    def test_success_failure_resume_and_source_binding(self):
        # Simulate mixed outcomes, resume only incomplete cells, and bind final sources.
        code = self.root / 'run_all.sh'
        code.write_text('# immutable test source\n')
        calls = []

        def process(cmd, **kwargs):
            calls.append(cmd[1])
            if cmd[1] == 'b20':
                output = Path(cmd[3])
                output.mkdir()
                (output / 'REPORT_COMPLETE.json').write_text('{}')
            class Process:
                stdout = io.StringIO('mock phase finished\n')
                def wait(self):
                    return int(cmd[1] == 'plan' and len(calls) == 3)
            return Process()

        with patch.dict(os.environ, {'MATLAB_BIN': sys.executable}, clear=True), patch.object(suite.subprocess, 'Popen', process), contextlib.redirect_stdout(io.StringIO()):
            with self.assertRaisesRegex(RuntimeError, 'Step 3 failed'):
                suite.run(self.root)
            marker = self.root / 'outputs/reproduction/REPRODUCTION_COMPLETE.json'
            self.assertFalse(marker.exists())
            self.assertEqual(calls, ['preflight', 'test', 'plan'])
            suite.run(self.root, resume=True)
            self.assertTrue(marker.exists())
            self.assertEqual(calls[3:], ['preflight', 'test', 'plan', 'all', 'verify-all', 'b20'])
            code.write_text('# changed source\n')
            with self.assertRaisesRegex(RuntimeError, 'identity changed'):
                suite.run(self.root, resume=True)

    def test_common_support_matches_dates_not_array_positions(self):
        # Common weeks are joined by year-week key, never by coincident row position.
        data = {'P0_M0_D0': {202001: np.arange(6.) / 100, 202002: np.arange(6.) / 50, 202003: np.arange(6.) / 40},
                'P0_M2_D0': {202002: np.arange(6.) / 20, 202003: np.arange(6.) / 10, 202004: np.full(6, np.nan)}}
        own, common, pairs, weekly = report.comparisons(data)
        self.assertEqual([x['weeks'] for x in own], [3, 2])
        self.assertEqual({x['weeks'] for x in common}, {2})
        self.assertEqual(pairs[0]['shared_dates'], '202002;202003')
        self.assertAlmostEqual(pairs[0]['delta_mean_pct_second_minus_first'], 26.25)
        self.assertTrue(np.isnan(report.statistics([0, 0])['sharpe_annualized']))

    def test_baseline_rejects_duplicate_dates(self):
        # Duplicate keys make a support intersection ambiguous and must fail closed.
        p = self.root / 'test.mat'
        savemat(p, {'vDates': [202001, 202001], 'cResults': {'VW': {'mPortRet': np.zeros((6, 2))}}})
        with self.assertRaisesRegex(RuntimeError, 'dimensions'):
            report.baseline(p)

    def test_fresh_export_uses_only_registered_runs(self):
        # Report export may consume accepted registrations only, not stale nearby MATs.
        (self.root / 'config').mkdir()
        (self.root / 'config/output_registry.csv').write_text('paper_item,producer_step,required_output_pattern,minimum_matches,experiments,description\nTable 3,b06,Tables/baseline.tex,1,all,Baseline\nFigure 1,b06,Figures/b06Table3_UnivariatePortfolioSorts_figure0[12].png,2,all,Factor plots\n')
        benchmark = self.root / 'results/comparisons/source_tables/CURATED_PAPER_BENCHMARKS.csv'
        benchmark.parent.mkdir(parents=True)
        benchmark.write_text('paper_item,metric,paper_value,experiment_row_label,experiment_row_occurrence,experiment_column_index\nTable 3,Avg (t),3.87 (5.19),H-L,1,1\nTable 3,Std,14.34,H-L,1,2\nTable 3,Annualized Sharpe,1.94,H-L,1,3\n')
        # A tiny genuine OOXML fixture gives the fresh exporter an independent
        # author source. Its dates and returns intentionally differ from MATs.
        # No copied experiment snapshot is available in this isolated root.
        workbook = io.BytesIO()
        with zipfile.ZipFile(workbook, 'w') as book:
            book.writestr('xl/workbook.xml', '<workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"><sheets><sheet name="Data from Study" r:id="rId2"/></sheets></workbook>')
            book.writestr('xl/_rels/workbook.xml.rels', '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId2" Target="worksheets/sheet2.xml"/></Relationships>')
            book.writestr('xl/sharedStrings.xml', '<sst xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"><si><t>YYYYWW</t></si><si><t>CTREND</t></si></sst>')
            book.writestr('xl/worksheets/sheet2.xml', '<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"><sheetData><row r="1"><c r="A1" t="s"><v>0</v></c><c r="B1" t="s"><v>1</v></c></row>' + ''.join(f'<row r="{i}"><c r="A{i}"><v>{t}</v></c><c r="B{i}"><v>{r}</v></c></row>' for i, (t, r) in enumerate([(202001,.9),(202002,.7),(202003,.8),(202004,.6)], 2)) + '</sheetData></worksheet>')
        (self.root / 'reference').mkdir()
        with zipfile.ZipFile(self.root / 'reference/dataverse_files.zip', 'w') as author:
            author.writestr('Results/CTREND/CTREND.xlsx', workbook.getvalue())
        for i, id in enumerate(report.IDS):
            run = self.root / 'runtime' / id
            results = run / 'results'
            (results / 'CTREND').mkdir(parents=True)
            (results / 'Tables').mkdir()
            (results / 'Figures').mkdir()
            for number in (1, 2):
                figure = results / f'Figures/b06Table3_UnivariatePortfolioSorts_figure0{number}'
                figure.with_suffix('.png').write_bytes(b'fixture: only identity is tested')
                savemat(figure.with_suffix('.fig'), {'hgS_070000': {
                    'type': 'specgraph.barseries',
                    'properties': {'XData': [1,2,3,4], 'YData': [9.,2.,3.,4.]}}})
            (run / 'RUN_COMPLETE').write_text(f'research_run_id=run-{i}\n')
            savemat(results / 'CTREND/CTREND_Base.mat', {'vDates': [202001, 202002, 202003], 'cResults': {'VW': {'mPortRet': np.arange(18.).reshape(6, 3) / 100 + i / 1000}}})
            (results / 'Tables/baseline.tex').write_text(' & Avg \\\\\n\\midrule\nH-L & 123.45 \\\\\n\\bottomrule\n')
            dest = self.root / 'outputs/experiments' / id
            dest.mkdir(parents=True)
            inner = dest / 'registration.env'
            inner.write_text(f'run_root={run}\nresults_root={results}\nresearch_run_id=run-{i}\nresults_inventory_sha256=test\nrun_complete_sha256={report.sha(run / "RUN_COMPLETE")}\n')
            (dest / 'PMD_REGISTRATION.env').write_text(f'inner_registration_relative={inner.relative_to(self.root)}\ninner_registration_sha256={report.sha(inner)}\n')
        output = self.root / 'outputs/fresh_report'
        with patch.object(report.subprocess, 'run') as verify, contextlib.redirect_stdout(io.StringIO()):
            report.build(self.root, output)
        self.assertEqual(verify.call_count, 2)
        self.assertEqual(verify.call_args_list[1].args[0][-2:], ['--results-root', str(output)])
        self.assertTrue((output / 'REPORT_COMPLETE.json').exists())
        self.assertEqual(len(report.csv_rows(output / 'RUN_IDENTITIES.csv')), len(report.IDS))
        self.assertIn('123.45', (output / 'CURRENT_RUN_COMPARISON_CN.md').read_text())
        companion = report.csv_rows(output / 'FACTOR_FIGURE_NUMERICAL_COMPANION.csv')
        self.assertEqual(len(companion), 4 * len(report.IDS))
        self.assertEqual(companion[0]['figure_mean_pct'], '9.0')
        self.assertEqual(companion[0]['ctrend_moments_match'], '0')
        self.assertTrue((output / 'experiments' / report.IDS[0] /
                         'Figures/b06Table3_UnivariatePortfolioSorts_figure01.fig').is_file())
        self.assertEqual(len(report.csv_rows(output / 'PAIRED_ABLATIONS.csv')), len(report.IDS) * (len(report.IDS) - 1) // 2)
        author_comparison = output / 'paper_factor'
        joint = report.csv_rows(author_comparison / 'NINETEEN_WAY_ALL_COMMON_SUMMARY.csv')
        self.assertEqual(len(joint), len(report.IDS) + 1)
        self.assertAlmostEqual(float(joint[0]['mean_weekly_pct']), 80.0)
        self.assertEqual(joint[0]['weeks'], '3')
        # The fresh MAT fixture, not an included/rounded snapshot, determines
        # each experiment statistic and every author--experiment difference.
        self.assertAlmostEqual(float(joint[1]['mean_weekly_pct']), 16.0)
        pp = report.csv_rows(author_comparison / 'PAPER_EXPERIMENT_ALL_COMMON_COMPARISONS.csv')
        self.assertAlmostEqual(float(pp[0]['delta_mean_pp_second_minus_first']), -64.0)
        completion = json.loads((output / 'REPORT_COMPLETE.json').read_text())
        self.assertEqual(completion['comparison_series'], len(report.IDS) + 1)
        self.assertEqual(completion['all_nineteen_common_weeks'], 3)
        for line in (output / 'REPORT_FILES.sha256').read_text().splitlines():
            digest, path = line.split('  ', 1)
            self.assertEqual(digest, report.sha(output / path))
        with self.assertRaisesRegex(RuntimeError, 'fresh directory'):
            report.build(self.root, output)

    def test_all_offline_tests_reach_release(self):
        # The one-command workflow must route every offline gate into release approval.
        preflight = (ROOT / 'scripts/preflight.sh').read_text()
        self.assertLess(preflight.index('if [[ "${1:-}" == "--data-only" ]]'), preflight.index('tests/run_acquisition_tests.py'))
        self.assertIn('tests/run_acquisition_tests.py', (ROOT / 'tests/run_tests.sh').read_text())
        release = (ROOT / 'release/make_release.sh').read_text()
        for stage in ('source_preflight', 'staged_preflight', 'fresh_preflight'):
            self.assertIn(stage, release)
        self.assertGreaterEqual(release.count('--no-matlab'), 2)
        self.assertIn('source_matlab_preflight=PASS', release)
        self.assertIn('acquisition_test_log_sha256=', release)

    def test_acquisition_gate_rejects_failure_skip_and_empty_suite(self):
        # Failed, skipped, or undiscovered acquisition tests must all block a PASS.
        class Failure(unittest.TestCase):
            def runTest(self):
                self.fail('injected regression')
        class Skipped(unittest.TestCase):
            def runTest(self):
                self.skipTest('injected missing dependency')
        for case in (Failure(), Skipped()):
            loader = unittest.TestLoader()
            with patch.object(acquisition.unittest, 'TestLoader', return_value=loader), \
                 patch.object(loader, 'discover', return_value=unittest.TestSuite([case])), \
                 contextlib.redirect_stderr(io.StringIO()):
                self.assertEqual(acquisition.main(), 1)
        loader = unittest.TestLoader()
        with patch.object(acquisition.unittest, 'TestLoader', return_value=loader), \
             patch.object(loader, 'discover', return_value=unittest.TestSuite()):
            with self.assertRaisesRegex(RuntimeError, 'discovery failed'):
                acquisition.main()


if __name__ == '__main__':
    unittest.main(verbosity=2)
