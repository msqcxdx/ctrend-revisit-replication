# Audited P0 derivation record

This derivation concerns M1/M2. The eighteen-cell package
also routes P0 M0 to the separately preserved unfilled M0 source; it is not a
b01-only inverse of P1 M0, whose b02 also preserves explicit zero volume.
Runtime archive tests cover all nine P0 cells. Scientific base files
remain untouched; public routing and the P-aware M2 startup guard are release
engineering adapters.

P0 is implemented as a source overlay. A same-M/D inventory comparison requires
`b01ReadData.m` to be the only changed executable file for M1. For M2,
`b02CalculateIndicators.m` also changes, exclusively within the volume-cleaning
block. Its executable statements match both Dataverse and P0/M0: all-zero/missing
rows and volume <= 1e-6, including zero, become NaN; the later original
zero/nonzero-return condition is retained. P1/M0 and P1/M2 preserve explicit
zero. Treating unfilled zero as missing is not an M2 look-ahead correction;
holding the same-P M0/M2 convention fixed prevents confounding the method contrast.

The four source pairs are:

| Method/axis | Frozen P1 b01 SHA-256 | P0 b01 SHA-256 |
|---|---|---|
| M1 D0 | `8605b9bf0dbe4028dc211bbdbf96e9bc12e91128ba00eb5a3b1f4fe5ba679293` | `79323b2aed294fe89b3f7dab7055dbdc908b81be07c0b009f0b2f96dcebf71f8` |
| M1 D1/D2 exclusion source | `afcb2507e34d4db9b9c6a9c106d96153d65ea32ae0abf63b317cbff5c84b3aad` | `fcab8bea4b90d56f3d2cb42e15cfba3627ea6f83286c356618499add32ff7a67` |
| M2 D0 | `d783ef35947adda1bfa0c533cea245b8a5186cbb5174f39561ec8afd0b6f6efd` | `304c4304bb1d9bbb64044bab2a36867266e30b434adef16f226deb322c054956` |
| M2 D1/D2 exclusion source | `a61a2051eec0709a428649381416ca80ee18683d14ffe73d9c5bc9c228b500d0` | `205118fb87f96af85a93c0cf4615bf57e7e6e61d7fc2df08622ad727035c77d2` |

For M1, the P0 overlay removes the unified preprocessing call and its saved
diagnostic structure, uses the direct date-key expression and the
zero-volume-with-missing-return rule, and calls
`fMaskAuxiliaryOHLC` without masking any cell as a unified fill. It persists
`lUnifiedAuxiliaryFilled=false(size(mClose))` solely as an explicit checkpoint
contract sentinel required by the unchanged M1 b02 consumer. The sentinel is
logical, dimension matched, and all false; it does not alter any panel.

For M2, the P0 overlay uses the same zero-volume rule and
removes the unified preprocessing call, the return recomputation caused by
that fill, and its saved diagnostic structure.

All other M1/M2 definitions are held fixed. The economic raw close and market
cap layers, frozen mechanical exit calendar, same-leg reinvestment, M1
statistical/economic separation, M2 causal/model-support changes, all D-axis
exclusions, runners, tests, and publication gates are shared with P1.

`tests/test_preprocessing_derivation.sh` enforces this scope for all six cells.
`tests/test_runtime_packages.sh` initializes and archives all nine P0 sources and
proves that each runtime contains the audited P0 b01 and no mutable DATA or
Results directory. `tests/test_m1_b01_b02_checkpoint_contract.sh` additionally
executes the real P0-M1 b01 against the certified raw inputs and then evaluates
the unchanged production b02 prologue through its checkpoint and source-hash
gates. This detects cross-stage field-contract errors before production.
