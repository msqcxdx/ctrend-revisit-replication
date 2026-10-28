# Test and verification entry points

`tests/result_checks/run_publication_checks.sh` is an independent audit of the
saved compact results, not a condition for code/data preflight or archive creation.
It checks compact membership, run identities, recomputed baseline support,
paper citations, the author factor's nineteen-way/pairwise date intersections,
and Figure 1 numerical companions. The author factor is authenticated from the
original ZIP; OOXML/header/calendar negative fixtures and synthetic
fresh-registration tests cover the reporting paths. Run this command explicitly
when reviewing the saved empirical results.

- `./run_all.sh test`: clean-clone source/configuration tests, eighteen
  materializations, frozen engine and M2 derivation contracts, exact
  annotation opcode/body checks, M2 consumer tracing, runner/provenance tests,
  frozen-input hash verification, P0/P1 runtime-package round trips, and MATLAB
  tests when available.
- `tests/integration/test_publication_readiness.py`: bilingual README, English runbook and
  path gate, required engineering file-purpose headers, formal documentation
  set, local-link integrity, and the README's M0/M2/M1 one-command contract.
- `./run_all.sh preflight`: production gate. It verifies the tracked immutable inputs,
  checks source contracts and inner-engine runtime-package round trips, checks
  MATLAB R2023b/toolboxes, and rejects mixed identities or host-local paths.
- `tests/integration/test_m2_derivation_scope.sh`: frozen-parent inventory,
  declared input-treatment allowlists, exact M0→M2 33-file boundary,
  overlay equality, and required causal/bitwise gates.
- `tests/integration/test_m2_consumer_matrix.py`: every direct return, panel,
  screen, reporting-boundary, walk-forward, and portfolio consumer.
- `tests/integration/test_b09_terminal_publication.sh`: atomic completion
  ordering for M0/M1/M2, M0/M2 identity-bound terminal-state classification,
  bounded missing-marker failure, and MATLAB command-line decoy rejection.
- `tests/integration/test_annotation_opcode_coverage.py`: independently
  recomputed operations, line spans, deletions, and hashes for every annotation.
- `tests/integration/test_annotation_readability.py`: percent-marker hierarchy,
  M0/M1/M2/D/PKG ownership, M0-based lineage, exact old/new maps, and bounded
  line width.
- `tests/integration/test_annotated_source_equivalence.py`: comment stripping
  and byte-exact canonical-body/file-set equality.
- `tests/result_checks/verify_completed_run.sh`: complete Results/DATA,
  3,072-design, engine, input, method, D-axis, and provenance acceptance.
- `./run_all.sh verify-all`: independent verification of all eighteen public registrations.
