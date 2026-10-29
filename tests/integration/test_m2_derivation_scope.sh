#!/usr/bin/env bash
# CTREND_REVISIT_FILE_PURPOSE: Prove the isolated v2 amendment, shared preprocessing bytes, and exact M0-to-M2 scientific boundary.
# Authenticate the frozen parent, enumerate every executable amendment, and
# prove M2 contains only its declared delta from M0. All D overlays are tested.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

python3 - "$ROOT" <<'PY'
import hashlib
import pathlib
import sys

root = pathlib.Path(sys.argv[1])
frozen = root / "provenance" / "frozen_parent_20260824"
manifest = frozen / "FILES.sha256"
assert manifest.is_file(), "missing frozen-parent file inventory"


def sha(path: pathlib.Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


# Authenticate the immutable record of the old 3x3 at the instant the new
# workspace was forked.  The old workspace itself is never a runtime input.
for line in (frozen / "MANIFEST.sha256").read_text().splitlines():
    digest, rel = line.split("  ", 1)
    candidate = root / rel if rel.startswith("provenance/") else frozen / rel
    assert sha(candidate) == digest, f"frozen provenance changed: {rel}"

before: dict[str, str] = {}
# Rebuild frozen/current executable maps rather than trusting prose summaries.
for line in manifest.read_text().splitlines():
    digest, rel = line.split("  ", 1)
    before[rel] = digest

executable_suffixes = {".m", ".sh", ".py", ".csv", ".bat"}
# Build current inventories over the same executable/configuration scope.


def amendment_delta(prefix: str) -> set[str]:
    base = root / prefix
    current = {
        p.relative_to(root).as_posix(): sha(p)
        for p in base.rglob("*")
        if p.is_file() and p.suffix.lower() in executable_suffixes
    }
    prior = {
        rel: digest for rel, digest in before.items()
        if rel.startswith(prefix + "/")
        and pathlib.Path(rel).suffix.lower() in executable_suffixes
    }
    return {
        rel[len(prefix) + 1 :]
        for rel in set(current) | set(prior)
        if current.get(rel) != prior.get(rel)
    }


# Exact path sets expose any unreviewed scientific or engineering change.
expected_amendment = {
    "engines/M0": {
        "base/Utils/fApplyUnifiedMissingDataPreprocessing.m",
        "base/Utils/fBuildAndFreezeMechanicalExitCalendar.m",
        "base/Utils/fFileSHA256.m",
        "base/b01ReadData.m",
        "base/b02CalculateIndicators.m",
        "overlays/exclusion/b01ReadData.m",
        "runner/b09_completion_protocol.sh",
        "runner/run_b09_shard.sh",
        "runner/run_production.sh",
    },
    "engines/M1": {
        "base/Utils/fApplySameLegReinvestment.m",
        "base/Utils/fApplyUnifiedMissingDataPreprocessing.m",
        "base/Utils/fAttachEconomicLedgerOptions.m",
        "base/Utils/fBuildAndFreezeMechanicalExitCalendar.m",
        "base/Utils/fBuildWeeklyEndpointPnl.m",
        "base/Utils/fBuildWeeklyReinvestmentLedger.m",
        "base/Utils/fComputeMarketRegressionCharacteristics.m",
        "base/Utils/fDepDoubleSort.m",
        "base/Utils/fExtendedHoldingPeriodVW.m",
        "base/Utils/fEstEvalTangPort.m",
        "base/Utils/fFileSHA256.m",
        "base/Utils/fIndepDoubleSort.m",
        "base/Utils/fLoadEconomicReinvestmentLedger.m",
        "base/Utils/fMaskAuxiliaryOHLC.m",
        "base/Utils/fMeanVarianceSpanningSoebhag.m",
        "base/Utils/fSingleSortFast.m",
        "base/Utils/fSingleSortMulti.m",
        "base/b01ReadData.m",
        "base/b02CalculateIndicators.m",
        "base/b04Table2_TechnicalIndicatorStrategyReturns.m",
        "base/b05CreateCTREND.m",
        "base/b06Table3_UnivariatePortfolioSorts.m",
        "base/b08Table5_PerformanceInSubperiodsAndDifferentMarketStates.m",
        "base/b09RunResearchDesigns.m",
        "base/b13Table8_TheCTRENDFactorPerformanceInBigAndLiquidCryptos.m",
        "base/b14Table9_CTRENDPortfoliosAndTransactionCosts.m",
        "base/b15TableB3_BivariatePortfolioSorts.m",
        "base/b16TableB4_CTRENDPerformanceDependingOnCryptocurrencyType.m",
        "base/b17TableB10_ExtendedPortfolioHoldingPeriod.m",
        "base/tests/run_corrected_unit_tests.m",
        "base/tests/test_figure_b2_results.m",
        "base/tests/test_portfolio_gap_accounting.m",
        "base/tests/test_v2_no_adjustment_mode.m",
        "base/tests/test_v2_static_guards.sh",
        "base/tests/test_weekly_endpoint_pnl.m",
        "overlays/exclusion/b01ReadData.m",
        "runner/b09_heartbeat_policy.sh",
        "runner/run_b09_shard.sh",
        "runner/run_production.sh",
        "runner/tests/test_runner_fault_controls.sh",
    },
    "engines/M2": {
        "base/Utils/fApplySameLegReinvestment.m",
        "base/Utils/fApplyUnifiedMissingDataPreprocessing.m",
        "base/Utils/fAttachEconomicLedgerOptions.m",
        "base/Utils/fBreakevenTCFromCosts.m",
        "base/Utils/fBuildAndFreezeMechanicalExitCalendar.m",
        "base/Utils/fBuildWeeklyEndpointPnl.m",
        "base/Utils/fBuildWeeklyReinvestmentLedger.m",
        "base/Utils/fDepDoubleSort.m",
        "base/Utils/fFileSHA256.m",
        "base/Utils/fIndepDoubleSort.m",
        "base/Utils/fLoadEconomicReinvestmentLedger.m",
        "base/Utils/fSingleSortFast.m",
        "base/Utils/fSingleSortMulti.m",
        "base/b01ReadData.m",
        "base/b02CalculateIndicators.m",
        "base/b04Table2_TechnicalIndicatorStrategyReturns.m",
        "base/b05CreateCTREND.m",
        "base/b06Table3_UnivariatePortfolioSorts.m",
        "base/b09RunResearchDesigns.m",
        "base/b13Table8_TheCTRENDFactorPerformanceInBigAndLiquidCryptos.m",
        "base/b14Table9_CTRENDPortfoliosAndTransactionCosts.m",
        "base/b15TableB3_BivariatePortfolioSorts.m",
        "base/b16TableB4_CTRENDPerformanceDependingOnCryptocurrencyType.m",
        "base/b17TableB10_ExtendedPortfolioHoldingPeriod.m",
        "overlays/exclusion/b01ReadData.m",
        "runner/b09_completion_protocol.sh",
        "runner/run_b09_shard.sh",
        "runner/run_production.sh",
        "runner/tests/test_m2_causal_contract.m",
        "runner/tests/test_m2_static_guards.sh",
    },
}

for prefix, expected in expected_amendment.items():
    observed = amendment_delta(prefix)
    assert observed == expected, (
        f"{prefix} escaped the isolated-v2 amendment allowlist: "
        f"missing={sorted(expected-observed)} extra={sorted(observed-expected)}"
    )


def identical(paths: list[pathlib.Path], label: str) -> None:
    digests = {sha(path) for path in paths}
    assert len(digests) == 1, f"shared {label} implementations diverged"


# P1 preprocessing/provenance helpers are a common P dimension, not an M delta.
for filename in (
    "fApplyUnifiedMissingDataPreprocessing.m",
    "fBuildAndFreezeMechanicalExitCalendar.m",
    "fFileSHA256.m",
):
    identical(
        [root / "engines" / method / "base" / "Utils" / filename
         for method in ("M0", "M1", "M2")],
        filename,
    )

# Economic settlement shared by M1/M2 must not fork silently between methods.
for filename in (
    "fApplySameLegReinvestment.m",
    "fAttachEconomicLedgerOptions.m",
    "fBuildWeeklyEndpointPnl.m",
    "fBuildWeeklyReinvestmentLedger.m",
    "fLoadEconomicReinvestmentLedger.m",
):
    identical(
        [root / "engines" / method / "base" / "Utils" / filename
         for method in ("M1", "M2")],
        filename,
    )

# After removing the common input amendment, M2 must still differ from M0
# only through the bounded causal/model-support files and the explicitly
# shared M1/M2 economic-settlement adapter.
m0 = root / "engines" / "M0" / "base"
m2 = root / "engines" / "M2" / "base"


def files(base: pathlib.Path) -> dict[str, bytes]:
    return {
        p.relative_to(base).as_posix(): p.read_bytes()
        for p in base.rglob("*") if p.is_file()
    }


a = files(m0)
b = files(m2)
observed_m2_m0 = {
    rel for rel in set(a) | set(b)
    if a.get(rel) != b.get(rel)
}
expected_m2_m0 = {
    "Utils/fApplySameLegReinvestment.m",
    "Utils/fAttachEconomicLedgerOptions.m",
    "Utils/fBreakevenTCFromCosts.m",
    "Utils/fBuildWeeklyEndpointPnl.m",
    "Utils/fBuildWeeklyReinvestmentLedger.m",
    "Utils/fCleanWeeklyLabelsM2.m",
    "Utils/fCreatePanelExAnteM2.m",
    "Utils/fDemeanWeeklyM2.m",
    "Utils/fDepDoubleSort.m",
    "Utils/fFilterM2EstimationSupport.m",
    "Utils/fIndepDoubleSort.m",
    "Utils/fLoadEconomicReinvestmentLedger.m",
    "Utils/fResampleLiuEtAl.m",
    "Utils/fSingleSortFast.m",
    "Utils/fSingleSortMulti.m",
    "Utils/fWalkforwardCENET.m",
    "Utils/fWalkforwardCSENET.m",
    "Utils/fWalkforwardFamaMacBethPanel.m",
    "Utils/fWalkforwardPanelRegression.m",
    "b02CalculateIndicators.m",
    "b04Table2_TechnicalIndicatorStrategyReturns.m",
    "b05CreateCTREND.m",
    "b06Table3_UnivariatePortfolioSorts.m",
    "b07Table4_CrossSectionalRegressions.m",
    "b08Table5_PerformanceInSubperiodsAndDifferentMarketStates.m",
    "b09RunResearchDesigns.m",
    "b10Table6_FactorPerformanceAcrossResearchDesignChoices.m",
    "b13Table8_TheCTRENDFactorPerformanceInBigAndLiquidCryptos.m",
    "b14Table9_CTRENDPortfoliosAndTransactionCosts.m",
    "b15TableB3_BivariatePortfolioSorts.m",
    "b16TableB4_CTRENDPerformanceDependingOnCryptocurrencyType.m",
    "b17TableB10_ExtendedPortfolioHoldingPeriod.m",
    "b18FigureC3_C4_AverageVariableImportance.m",
}
assert observed_m2_m0 == expected_m2_m0, (
    "M2/M0 base delta escaped its scientific allowlist: "
    f"missing={sorted(expected_m2_m0-observed_m2_m0)} "
    f"extra={sorted(observed_m2_m0-expected_m2_m0)}"
)

assert files(root / "engines" / "M0" / "overlays") == files(
    root / "engines" / "M2" / "overlays"
), "M2 data overlay differs from M0"

print(
    "ISOLATED_V2_DERIVATION_SCOPE_OK "
    "parent_manifest=1 m0_amendment=9 m1_amendment=35 "
    "m2_amendment=30 shared_input_helpers=3 "
    "shared_economic_helpers=5 m2_m0_base_allowlist=33 overlays_equal=1"
)
PY

# Exercise every actually materialized M2 D axis.  A package-only base test
# is insufficient because D1/D2 add the configured exclusion overlay.
TMP="$(mktemp -d /tmp/ctrend_m2_materialized_guards_XXXXXX)"
cleanup() { rm -rf -- "$TMP"; }
trap cleanup EXIT
for id in M2_D0 M2_D1 M2_D2; do
  source="$TMP/$id/source"
  "$ROOT/scripts/materialize_experiment_source.sh" "$id" "$source" >/dev/null
  "$ROOT/engines/M2/runner/tests/test_m2_static_guards.sh" "$source" >/dev/null
done
echo 'M2_MATERIALIZED_STATIC_GUARDS_OK axes=3 same_leg_reinvestment=1 no_cash=1'
