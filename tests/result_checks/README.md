Result checks accept only a complete run root. Missing tables/figures,
experiment-identity mismatches, or an incomplete 3,072-design grid/inventory
all fail closed.

`test_curated_result_snapshot.py` deliberately freezes the nine completed
**pre-amendment** result snapshots. It does not certify those M1/M2 numbers as
the final 24-August-2026 specification. The separate
`test_revised_week_support_snapshot.py` certifies the fixed-forecast amended
D0 support counts (M0=349, M2=353, M1=337, all-method common=337). Final
amended returns and common-week statistics require fresh M1/M2 production
runs and the standalone nine-method common-week comparison.
