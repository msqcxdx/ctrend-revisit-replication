#!/usr/bin/env python3
# CTREND_REVISIT_FILE_PURPOSE: Discover and require all offline acquisition regression tests without contacting a data provider.
"""A failing import, empty discovery, skipped test or failed test blocks release."""
# Discovery is dynamic so every test_*.py module under cmc_acquisition/tests is
# mandatory.  Skips are failures because a release must not claim acquisition
# coverage that was silently unavailable on the build host.
from pathlib import Path
import sys
import unittest


def main():
    # These fixtures are offline; executing this gate never calls CMC or another provider.
    directory = Path(__file__).resolve().parents[1] / 'cmc_acquisition/tests'
    files = sorted(directory.glob('test_*.py'))
    if not files:
        raise RuntimeError('No acquisition test modules found')
    loader = unittest.TestLoader()
    suite = loader.discover(str(directory), pattern='test_*.py')
    if loader.errors or suite.countTestCases() == 0:
        raise RuntimeError('Acquisition test discovery failed: ' + '\n'.join(loader.errors))
    result = unittest.TextTestRunner(verbosity=2).run(suite)
    if not result.wasSuccessful() or result.skipped:
        return 1
    print(f'ACQUISITION_REGRESSION_TESTS_OK modules={len(files)} tests={result.testsRun} offline=1')
    return 0


if __name__ == '__main__':
    sys.exit(main())
