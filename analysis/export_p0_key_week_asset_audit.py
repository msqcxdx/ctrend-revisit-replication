#!/usr/bin/env python3
# CTREND_REVISIT_FILE_PURPOSE: export a narrow, read-only asset/week audit from
# nine accepted P0 baselines and their certified intermediate weekly panels.
# It never refits models, changes a run, or edits existing result inventories.
"""Export the five requested weeks for P0 x M0/M2/M1 x D0/D1/D2.

For each D/week, retain the union of low/high-leg holdings across all three
methods, then emit one row per method and CMCID, including unheld counterparts.
The output directory must not already exist. The exporter reads accepted run
registries, intermediate panels and immutable baseline results; it does not
infer a missing-reason code that the production model did not save.
"""

from __future__ import annotations

import argparse
import csv
import gzip
import hashlib
import io
import math
import os
import tarfile
import tempfile
from collections import defaultdict
from pathlib import Path

import h5py
import numpy as np
from scipy.io import loadmat


REPO = Path(__file__).resolve().parents[1]
WEEKS = (201628, 201750, 202013, 202016, 202103)
METHODS = (0, 2, 1)
INDICATORS = (
    "sma_3d", "sma_5d", "sma_10d", "sma_20d", "sma_50d",
    "sma_100d", "sma_200d", "macd", "macd_diff_signal",
    "volsma_3d", "volsma_5d", "volsma_10d", "volsma_20d",
    "volsma_50d", "volsma_100d", "volsma_200d", "volmacd",
    "volmacd_diff_signal", "rsi", "stochRSI", "stochK", "stochD",
    "boll_low", "boll_mid", "boll_high", "boll_width", "cci", "chaikin",
)


def sha(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as fh:
        for block in iter(lambda: fh.read(8 * 1024 * 1024), b""):
            h.update(block)
    return h.hexdigest()


def scalar(x):
    y = float(x)
    return "" if not math.isfinite(y) else format(y, ".17g")


def flag(x) -> int:
    return int(bool(x))


def write_csv_gz(path: Path, rows: list[dict], columns: list[str]):
    with path.open("wb") as raw, gzip.GzipFile(
        filename="", mode="wb", fileobj=raw, mtime=0, compresslevel=9
    ) as compressed:
        text = io.TextIOWrapper(compressed, encoding="utf-8", newline="")
        writer = csv.DictWriter(text, fieldnames=columns, lineterminator="\n")
        writer.writeheader()
        writer.writerows(rows)
        text.flush()
        text.detach()


def lookup_file(root: Path, name: str) -> Path:
    matches = [p for p in root.rglob(name) if p.is_file()]
    if len(matches) != 1:
        raise RuntimeError(f"Expected one {name} in {root}, found {len(matches)}")
    return matches[0]


def read_registry(root: Path, method: int, design: int) -> dict:
    file = root / "P0" / f"M{method}" / f"D{design}" / "ACCEPTED_RUN_REGISTRY_ROW.csv"
    with file.open(newline="", encoding="utf-8") as fh:
        rows = list(csv.DictReader(fh))
    if len(rows) != 1 or rows[0]["experiment_id"] != f"P0_M{method}_D{design}":
        raise RuntimeError(f"Bad accepted registry: {file}")
    return rows[0]


def read_env(path: Path) -> dict[str, str]:
    return dict(line.split("=", 1) for line in path.read_text(encoding="utf-8").splitlines()
                if "=" in line)


def matlab_string(h5, ref) -> str:
    return "".join(chr(int(c)) for c in np.asarray(h5[ref]).ravel())


def read_calendar(dates: np.ndarray) -> dict[int, tuple[int, int, int, int]]:
    """Return yyyyWW -> (start_idx, end_idx, start_date, end_date).

    The original resampler numbers 7-day blocks within each calendar year,
    with the last block absorbing remaining days; this is not ISO week time.
    """
    out = {}
    for year in np.unique(dates // 10000):
        positions = np.flatnonzero(dates // 10000 == year)
        n = len(positions) // 7
        for week in range(1, n + 1):
            lo = int(positions[(week - 1) * 7])
            hi = int(positions[week * 7 - 1] if week < n else positions[-1])
            out[int(year) * 100 + week] = (lo, hi, int(dates[lo]), int(dates[hi]))
    return out


def raw_cmc_prices(csv_path: Path, dates: set[int], ids: set[int]) -> dict[tuple[int, int], float]:
    out = {}
    with csv_path.open(newline="", encoding="utf-8") as fh:
        reader = csv.reader(fh)
        header = next(reader)
        fields = [(j, int(value)) for j, value in enumerate(header) if value.isdigit() and int(value) in ids]
        for row in reader:
            date = int(row[0].replace("-", ""))
            if date not in dates:
                continue
            for j, asset_id in fields:
                value = row[j] if j < len(row) else ""
                if value:
                    try:
                        price = float(value)
                    except ValueError:
                        continue
                    if math.isfinite(price) and price > 0:
                        out[date, asset_id] = price
    return out


def group_and_weight(portfolio: dict, asset_idx: int | None, week_idx: int, allocation: str) -> tuple[str, np.ndarray]:
    weights = np.zeros(5, dtype=float)
    if asset_idx is not None:
        values = portfolio[allocation]["mWts"][asset_idx, week_idx, :]
        weights = np.nan_to_num(values, nan=0.0)
    present = np.flatnonzero(weights > 0)
    if len(present) > 1:
        raise AssertionError("Asset belongs to multiple quintiles")
    return (f"Q{int(present[0]) + 1}" if len(present) else "NOT_IN_SAVED_LEGS"), weights


def selected_names(base: dict, idx: int) -> list[str]:
    offset = len(base["vDates"]) - len(base["mSelected"])
    row = idx - offset
    if row < 0:
        return []
    if "vModelDates" in base:
        assert int(base["vModelDates"][row]) == int(base["vDates"][idx])
    return [name for name, keep in zip(INDICATORS, base["mSelected"][row]) if keep]


def daily_master(root: Path):
    source = lookup_file(root, "b0DataOLHC.mat")
    data = loadmat(source, simplify_cells=True, variable_names=["yrmoda", "rMetaData", "mClose"])
    dates = np.asarray(data["yrmoda"]).ravel().astype(int)
    close = np.asarray(data["mClose"])
    meta = data["rMetaData"]
    ids = np.asarray(meta["vID"]).ravel().astype(int)
    names = {int(i): (str(n), str(s)) for i, n, s in zip(ids, meta["cName"], meta["cSymbol"])}
    assert close.shape == (len(dates), len(ids))
    return source, dates, close, ids, names


def predictor_flags(method: int, is_stable: bool, predictor_missing: list[str],
                    formation_cap: float, formation_close: float,
                    target_cap: float, target_close: float,
                    target_return: float) -> list[str]:
    flags = []
    if is_stable:
        flags.append("stablecoin_exclusion")
    cap = target_cap if method == 0 else formation_cap
    close = target_close if method == 0 else formation_close
    if not np.isfinite(cap):
        flags.append("screen_market_cap_missing")
    elif cap < 1_000_000:
        flags.append("screen_market_cap_below_1m")
    if not np.isfinite(close):
        flags.append("screen_close_missing")
    elif close < 0:
        flags.append("screen_close_negative")
    if method == 0 and not np.isfinite(target_return):
        flags.append("M0_target_week_return_missing")
    if not np.isfinite(formation_cap):
        flags.append("formation_market_cap_missing")
    if predictor_missing:
        flags.append("formation_indicator_missing")
    return flags


def field_dictionary() -> str:
    return """# P0 selected-week asset audit: field guide

This is a read-only diagnostic extract, **not a rerun or an altered portfolio**.
Scope: P0 × M0/M2/M1 × D0/D1/D2 (nine baselines), for 2016W28,
2017W50, 2020W13, 2020W16 and 2021W03. `yyyyWW` uses the project's
calendar-year seven-day blocks, not ISO week numbers. For each D/week,
the asset universe is the union of either EW or VW low/high holdings across
all three M methods. Every included CMCID has three method rows, even when
one method gave it no forecast or no position. The same underlying CMCID
is never merged with another identifier merely because tickers match.

`P0_KEY_WEEK_ASSET_METHOD_ROWS.csv.gz` contains:

- `formation_date`/`scheduled_settlement_date`: the saved target week's
  preceding/current block end; `indicator_*_value` is the **previous**
  weekly characteristic used at formation, not the target-week value.
  `indicator_*_missing` and `indicator_missing_count` describe those 28
  saved, pre-rank inputs. A finite input does not prove the later ranked,
  model-specific prediction is finite.
- `forecast`, `selected_indicators`, `ew_group`/`vw_group`, and opening
  weights come from the accepted `CTREND_Base.mat`. M0/M2 save all five
  quintiles; M1 intentionally saves the two extreme legs only, so
  `NOT_IN_SAVED_LEGS` for an M1 forecast **does not identify Q2/Q3/Q4**.
  `NO_FORECAST` means the saved forecast is nonfinite.
- `missing_reason_flags` are **diagnostic input flags reconstructed from
  saved inputs**, not a model-emitted or mutually exclusive causal code.
  `model_or_unresolved` means these checks cannot uniquely explain the
  missing forecast. `indicator_missing_names` is a direct input observation.
- `raw_cmc_endpoint_return` is the unadjusted CMC close at scheduled
  settlement divided by unadjusted close at formation, minus one, only
  when both prices exist. It is intentionally not an imputed/terminal
  return. `model_input_weekly_return` is the method's saved weekly input:
  M0's cleaned legacy weekly return, M2's separately saved raw-return
  layer, or M1's statistical-return layer. `economic_payoff_return` is
  the saved OOS payoff for M1/M2, and the verified saved weekly return
  used by M0 for actual holdings. It may be blank for unheld rows.
- `*_direct_opening_contribution` equals signed opening weight times
  economic payoff; positive for high, negative for low. It is not a
  transaction-level attribution when within-week exits occur. The weekly
  file reports any saved-HL minus direct-contribution residual separately.
  In the **five selected weeks** all saved leg totals reconcile without
  within-week reinvestment events.

`P0_KEY_WEEK_PORTFOLIOS.csv.gz` gives EW/VW low, high, H-L saved returns,
holding counts, selected-set size, and direct-attribution residual for each
of the 45 method/week cases. `P0_REINVESTMENT_EVENT_WEEKS.csv.gz` gives
the saved event-week same-leg reinvestment audit (outside the five selected
weeks when necessary); aggregate proceeds are weekly-leg totals, not
per-recipient cashflows. No chosen focal week has a terminal trade.

`P0_SMA_SHORT_HISTORY_EXAMPLES.csv.gz` shows five actual focal-week
holdings with fewer than 200 observed history days for which M0 saved a
finite SMA-200/close predictor while M1's strict predictor is missing.
`P0_FUTURE_BACKFILL_EXAMPLES.csv.gz` shows five close-price examples where
M0's weekly value matches a **later same-calendar-year** daily value while
M1 leaves the boundary missing. The source date is reconstructed from the
saved daily b01 panel and the original calendar-year `last` resampler;
the post-outlier daily temporary panel was not separately saved, so this
is a value-matched source reconstruction, not a row-level execution trace.

`SOURCE_MANIFEST.csv` records accepted research run IDs and SHA256s of
the baseline, intermediate weekly panel, run completion and acceptance
markers; `SHA256SUMS` verifies every delivered file including the bundle.
All return and contribution columns are decimal units (0.01 = 1%).

Regenerate from accepted full run roots, a run registry and raw CMC input:

```bash
python analysis/export_p0_key_week_asset_audit.py \\
  --registry-root /path/to/accepted/registry \\
  --m2-repair-runs-root /path/to/current/P0_M2/runs \\
  --results-root results \\
  --raw-close data/raw/common/close_cmc.csv \\
  --output-root results/diagnostics/p0_selected_week_asset_audit
```

`--m2-repair-runs-root` is required when the accepted registry points to
earlier M2 runs rather than the zero-volume-rule reruns published in this
repository. SHA256 equality with each repository baseline is enforced.
The exporter refuses to overwrite an existing output directory. It does
not write to any accepted run root or to existing result inventories.
"""


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--registry-root", type=Path,
                        default=os.environ.get("CTREND_ACCEPTED_RUN_REGISTRY"))
    parser.add_argument("--results-root", type=Path, default=REPO / "results")
    parser.add_argument("--raw-close", type=Path,
                        default=REPO / "data/raw/common/close_cmc.csv")
    parser.add_argument("--m2-repair-runs-root", type=Path,
                        help="Accepted P0 M2 D0/D1/D2 reruns matching the current published baselines")
    parser.add_argument("--output-root", type=Path,
                        default=REPO / "results/diagnostics/p0_selected_week_asset_audit")
    args = parser.parse_args()
    if args.registry_root is None:
        parser.error("--registry-root (or CTREND_ACCEPTED_RUN_REGISTRY) is required")
    registry_root = args.registry_root.resolve()
    results_root = args.results_root.resolve()
    raw_close = args.raw_close.resolve()
    out = args.output_root.resolve()
    if out.exists():
        raise FileExistsError(f"Refusing to overwrite existing audit: {out}")
    out.parent.mkdir(parents=True, exist_ok=True)

    records = {}
    manifest = []
    for design in range(3):
        for method in METHODS:
            eid = f"P0_M{method}_D{design}"
            reg = read_registry(registry_root, method, design)
            run = Path(reg["run_root"])
            if method == 2 and args.m2_repair_runs_root is not None:
                matches = list(args.m2_repair_runs_root.glob(f"{eid}_production_*"))
                if len(matches) != 1:
                    raise RuntimeError(f"Expected exactly one repaired run for {eid}: {matches}")
                run = matches[0].resolve()
                complete_data = read_env(run / "RUN_COMPLETE")
                accepted_data = read_env(run / "P0_EXPERIMENT_ACCEPTANCE.env")
                if complete_data.get("complete") != "1" or accepted_data.get("experiment_id") != eid:
                    raise RuntimeError(f"Repaired run is not accepted: {eid}")
                if complete_data.get("research_run_id") != accepted_data.get("research_run_id"):
                    raise RuntimeError(f"Repaired run identity mismatch: {eid}")
                reg.update(research_run_id=complete_data["research_run_id"],
                           run_complete_sha256=sha(run / "RUN_COMPLETE"),
                           acceptance_file="P0_EXPERIMENT_ACCEPTANCE.env",
                           acceptance_sha256=sha(run / "P0_EXPERIMENT_ACCEPTANCE.env"))
            base_file = results_root / "experiments" / eid / "CTREND/CTREND_Base.mat"
            run_base = lookup_file(run, "CTREND_Base.mat")
            weekly = lookup_file(run, "bCharacteristicsOLHC_Combo1.mat")
            ledger = lookup_file(run, "b2EconomicReinvestmentLedger.mat") if method else None
            completed = run / "RUN_COMPLETE"
            accepted = run / reg["acceptance_file"]
            if not (completed.is_file() and accepted.is_file()):
                raise RuntimeError(f"Run is not accepted: {eid}")
            if sha(completed) != reg["run_complete_sha256"] or sha(accepted) != reg["acceptance_sha256"]:
                raise RuntimeError(f"Accepted marker SHA mismatch: {eid}")
            base_sha = sha(base_file)
            if sha(run_base) != base_sha:
                raise RuntimeError(f"Saved baseline != accepted run baseline: {eid}")
            base = loadmat(base_file, simplify_cells=True,
                           variable_names=["cResults", "cTechnicalIndicators", "mYhat",
                                           "mRetPnlOOS", "mSelected", "vDates", "vModelDates", "vAssetID"])
            base["vDates"] = np.asarray(base["vDates"]).ravel().astype(int)
            base["vAssetID"] = np.asarray(base["vAssetID"]).ravel().astype(int)
            if "cTechnicalIndicators" in base:
                assert tuple(base["cTechnicalIndicators"]) == INDICATORS, eid
            assert base["mYhat"].shape == (len(base["vAssetID"]), len(base["vDates"]))
            with h5py.File(weekly) as h5:
                ids = np.asarray(h5["rMetaData/vID"]).ravel().astype(int)
                dates = np.asarray(h5["rData/yrmoda"]).ravel().astype(int)
                assert np.array_equal(ids, base["vAssetID"]), eid
                week_idx = {int(d): i for i, d in enumerate(dates)}
                # Only five dates and their formation predecessors are loaded.
                selected = {}
                for code in WEEKS:
                    target = week_idx[code]
                    previous = target - 1
                    fields = {key: np.asarray(h5[f"rData/{key}"][:, [previous, target]])
                              for key in ("mME", "mClose", "mReturns")}
                    if method == 2:
                        fields["mReturnsM2Raw"] = np.asarray(h5["rData/mReturnsM2Raw"][:, target])
                    if method == 1:
                        fields["mPnlReturns"] = np.asarray(h5["rData/mPnlReturns"][:, target])
                    fields["indicators"] = {
                        key: np.asarray(h5[f"rChars/{key}"][:, previous])
                        for key in INDICATORS
                    }
                    selected[code] = fields
                stable = np.asarray(h5["rMetaData/lIsStable"]).ravel().astype(bool)
            records[eid] = dict(base=base, selected=selected, stable=stable,
                                id_index={int(x): i for i, x in enumerate(ids)},
                                run=run, weekly=weekly, ledger=ledger,
                                research_run_id=reg["research_run_id"])
            manifest.append(dict(experiment_id=eid, research_run_id=reg["research_run_id"],
                                 run_root_name=run.name, baseline_sha256=base_sha,
                                 weekly_panel_sha256=sha(weekly),
                                 economic_ledger_sha256=sha(ledger) if ledger else "",
                                 run_complete_sha256=reg["run_complete_sha256"],
                                 acceptance_sha256=reg["acceptance_sha256"]))
            print(f"SOURCE_OK {eid} {reg['research_run_id']}", flush=True)

    master_run = records["P0_M0_D0"]["run"]
    daily_file, daily_dates, daily_close, daily_ids, names = daily_master(master_run)
    calendar = read_calendar(daily_dates)
    for code in WEEKS:
        assert code in calendar
    raw_dates = set()
    union_by_design_week = {}
    all_ids = set()
    for design in range(3):
        for code in WEEKS:
            assets = set()
            for method in METHODS:
                base = records[f"P0_M{method}_D{design}"]["base"]
                t = int(np.flatnonzero(base["vDates"] == code)[0])
                for allocation in ("EW", "VW"):
                    w = base["cResults"][allocation]["mWts"][:, t, :]
                    held = np.nan_to_num(w[:, 0], nan=0) > 0
                    held |= np.nan_to_num(w[:, 4], nan=0) > 0
                    assets.update(int(i) for i in base["vAssetID"][held])
            assert assets, (design, code)
            union_by_design_week[design, code] = sorted(assets)
            all_ids.update(assets)
            _, _, _, settlement = calendar[code]
            previous_week = int(records[f"P0_M0_D{design}"]["base"]["vDates"][
                int(np.flatnonzero(records[f"P0_M0_D{design}"]["base"]["vDates"] == code)[0]) - 1])
            raw_dates.add(calendar[previous_week][3])
            raw_dates.add(settlement)
    raw = raw_cmc_prices(raw_close, raw_dates, all_ids)

    rows = []
    weekly_rows = []
    reinvest_rows = []
    for design in range(3):
        for code in WEEKS:
            union = union_by_design_week[design, code]
            for method in METHODS:
                eid = f"P0_M{method}_D{design}"
                rec = records[eid]
                base = rec["base"]
                t = int(np.flatnonzero(base["vDates"] == code)[0])
                week = rec["selected"][code]
                prior_code = int(base["vDates"][t - 1])
                formation = calendar[prior_code][3]
                settlement = calendar[code][3]
                selected_set = selected_names(base, t)
                for asset_id in union:
                    i = rec["id_index"].get(asset_id)
                    raw_formation = raw.get((formation, asset_id), np.nan)
                    raw_settlement = raw.get((settlement, asset_id), np.nan)
                    raw_return = (raw_settlement / raw_formation - 1
                                  if np.isfinite(raw_formation) and np.isfinite(raw_settlement)
                                  else np.nan)
                    name, symbol = names.get(asset_id, ("", ""))
                    result = dict(experiment_id=eid, research_run_id=rec["research_run_id"],
                                  design=f"D{design}", method=f"M{method}",
                                  year_week=code, cmcid=asset_id, asset_name=name, ticker=symbol,
                                  formation_date=formation, scheduled_settlement_date=settlement,
                                  present_in_method_universe=flag(i is not None),
                                  selected_indicators="|".join(selected_set),
                                  selected_indicator_count=len(selected_set),
                                  raw_cmc_formation_close=scalar(raw_formation),
                                  raw_cmc_settlement_close=scalar(raw_settlement),
                                  raw_cmc_endpoint_return=scalar(raw_return))
                    if i is None:
                        result.update(forecast="", forecast_available=0,
                                      missing_reason_flags="not_in_experiment_universe",
                                      missing_reason_basis="run_universe_membership",
                                      indicator_missing_count=28,
                                      indicator_missing_names="|".join(INDICATORS),
                                      formation_market_cap="", target_market_cap="",
                                      formation_weekly_close="", target_weekly_close="",
                                      model_input_weekly_return="", economic_payoff_return="")
                        for key in INDICATORS:
                            result[f"indicator_{key}_value"] = ""
                            result[f"indicator_{key}_missing"] = 1
                    else:
                        predictor = {key: float(week["indicators"][key][i]) for key in INDICATORS}
                        missing = [key for key, value in predictor.items() if not np.isfinite(value)]
                        cap_prev = float(week["mME"][i, 0])
                        cap_now = float(week["mME"][i, 1])
                        close_prev = float(week["mClose"][i, 0])
                        close_now = float(week["mClose"][i, 1])
                        model_return = float(week["mReturns"][i, 1])
                        if method == 2:
                            model_return = float(week["mReturnsM2Raw"][i])
                        forecast = float(base["mYhat"][i, t])
                        payoff = (float(base["mRetPnlOOS"][i, t]) if method
                                  else float(week["mReturns"][i, 1]))
                        flags = predictor_flags(method, bool(rec["stable"][i]), missing,
                                                cap_prev, close_prev, cap_now, close_now,
                                                model_return)
                        if not np.isfinite(forecast) and not flags:
                            flags.append("model_or_unresolved")
                        result.update(forecast=scalar(forecast),
                                      forecast_available=flag(np.isfinite(forecast)),
                                      missing_reason_flags="|".join(flags) if not np.isfinite(forecast) else "",
                                      missing_reason_basis="derived_input_flags_not_saved_model_code"
                                      if not np.isfinite(forecast) else "not_applicable",
                                      indicator_missing_count=len(missing),
                                      indicator_missing_names="|".join(missing),
                                      formation_market_cap=scalar(cap_prev),
                                      target_market_cap=scalar(cap_now),
                                      formation_weekly_close=scalar(close_prev),
                                      target_weekly_close=scalar(close_now),
                                      model_input_weekly_return=scalar(model_return),
                                      economic_payoff_return=scalar(payoff))
                        for key, value in predictor.items():
                            result[f"indicator_{key}_value"] = scalar(value)
                            result[f"indicator_{key}_missing"] = flag(not np.isfinite(value))
                    for allocation in ("EW", "VW"):
                        group, weights = group_and_weight(base["cResults"], i, t, allocation)
                        if i is not None and not np.isfinite(base["mYhat"][i, t]):
                            assert not np.any(weights > 0), (eid, code, asset_id)
                            group = "NO_FORECAST"
                        elif i is None:
                            group = "NOT_IN_UNIVERSE"
                        low, high = float(weights[0]), float(weights[4])
                        payoff_num = float(result["economic_payoff_return"]) if result["economic_payoff_return"] != "" else np.nan
                        if (low > 0 or high > 0) and not np.isfinite(payoff_num):
                            raise AssertionError(f"Held asset has missing saved payoff: {eid} {code} {asset_id}")
                        result[f"{allocation.lower()}_group"] = group
                        result[f"{allocation.lower()}_low_weight"] = scalar(low)
                        result[f"{allocation.lower()}_high_weight"] = scalar(high)
                        result[f"{allocation.lower()}_signed_hl_weight"] = scalar(high - low)
                        result[f"{allocation.lower()}_direct_opening_contribution"] = (
                            scalar((high - low) * payoff_num) if np.isfinite(payoff_num)
                            else "0" if low == 0 and high == 0 else "")
                    rows.append(result)
                for allocation in ("EW", "VW"):
                    port = base["cResults"][allocation]
                    low_saved, high_saved, hl_saved = (float(port["mPortRet"][j, t]) for j in (0, 4, 5))
                    direct = 0.0
                    for asset_id in union:
                        row = next(x for x in rows[-len(union):] if x["cmcid"] == asset_id)
                        direct += float(row[f"{allocation.lower()}_direct_opening_contribution"])
                    audit = port.get("cSameLegReinvestmentAudit")
                    event_count = 0
                    if isinstance(audit, list):
                        event_count = int(np.asarray(audit[0]["vEventDateCount"])[t]) + \
                                      int(np.asarray(audit[4]["vEventDateCount"])[t])
                    residual = hl_saved - direct
                    if event_count == 0 and np.isfinite(hl_saved):
                        assert abs(residual) < 1e-9, (eid, code, allocation, residual)
                    weekly_rows.append(dict(experiment_id=eid,
                                            research_run_id=rec["research_run_id"],
                                            year_week=code, formation_date=formation,
                                            scheduled_settlement_date=settlement,
                                            allocation=allocation,
                                            union_asset_count=len(union),
                                            forecast_count=int(np.isfinite(base["mYhat"][:, t]).sum()),
                                            selected_indicator_count=len(selected_set),
                                            selected_indicators="|".join(selected_set),
                                            low_holding_count=int(np.sum(np.nan_to_num(port["mWts"][:, t, 0], nan=0) > 0)),
                                            high_holding_count=int(np.sum(np.nan_to_num(port["mWts"][:, t, 4], nan=0) > 0)),
                                            saved_low_return=scalar(low_saved),
                                            saved_high_return=scalar(high_saved),
                                            saved_hl_return=scalar(hl_saved),
                                            sum_direct_opening_hl_contributions=scalar(direct),
                                            saved_minus_direct_residual=scalar(residual),
                                            within_week_exit_event_count=event_count))

    # Event-week audit is exported even if the five focal weeks contain no
    # exits. It is drawn from each accepted baseline and its frozen ledger.
    for design in range(3):
        for method in (1, 2):
            eid = f"P0_M{method}_D{design}"
            rec = records[eid]
            base = rec["base"]
            with h5py.File(rec["ledger"]) as h5:
                ledger = h5["rEconomicReinvestmentLedger"]
                event_dates = np.asarray(ledger["vEventDate"]).ravel().astype(int)
                event_indices = np.asarray(ledger["vEventDailyIndex"]).ravel().astype(int)
                last_idx = np.asarray(ledger["vLastTradableIndex"]).ravel().astype(int)
                ledger_ids = np.asarray(ledger["vAssetID"]).ravel().astype(int)
                week_dates = np.asarray(ledger["vWeekDate"]).ravel().astype(int)
                early = np.asarray(ledger["lOrdinaryEarlyExit"]).astype(bool)
                event_close = np.asarray(ledger["mEventClose"])
                for allocation in ("EW", "VW"):
                    port = base["cResults"][allocation]
                    audits = port["cSameLegReinvestmentAudit"]
                    for leg_idx, leg_name in ((0, "LOW"), (4, "HIGH")):
                        audit = audits[leg_idx]
                        for t in np.flatnonzero(np.asarray(audit["vEventDateCount"]) > 0):
                            code = int(base["vDates"][t])
                            w = int(np.flatnonzero(week_dates == code)[0])
                            exited = np.flatnonzero(early[:, w] &
                                (np.nan_to_num(port["mWts"][:, t, leg_idx], nan=0) > 0))
                            expected = int(np.asarray(audit["vExitedHoldingCount"])[t])
                            assert len(exited) == expected, (eid, code, allocation, leg_name)
                            for i in exited:
                                event_col = int(np.flatnonzero(event_indices == last_idx[i])[0])
                                asset_id = int(ledger_ids[i])
                                assert asset_id == int(base["vAssetID"][i])
                                name, symbol = names[asset_id]
                                reinvest_rows.append(dict(
                                    experiment_id=eid, research_run_id=rec["research_run_id"],
                                    year_week=code, in_five_requested_weeks=flag(code in WEEKS),
                                    allocation=allocation, leg=leg_name, cmcid=asset_id,
                                    asset_name=name, ticker=symbol,
                                    exit_date=int(event_dates[event_col]),
                                    saved_event_close=scalar(event_close[i, event_col]),
                                    opening_leg_weight=scalar(port["mWts"][i, t, leg_idx]),
                                    week_leg_event_date_count=int(np.asarray(audit["vEventDateCount"])[t]),
                                    week_leg_exited_holding_count=expected,
                                    week_leg_total_reinvested_proceeds=scalar(np.asarray(audit["vReinvestedProceeds"])[t]),
                                    no_eligible_recipient=flag(np.asarray(audit["lNoEligibleRecipient"])[t]),
                                    accounting_scope="weekly_leg_total_not_per_asset_or_recipient"))

    # Five focal-union examples of the legacy short-history SMA(200) rule.
    short_examples = []
    for code in WEEKS:
        formation = calendar[int(records["P0_M0_D0"]["base"]["vDates"][
            int(np.flatnonzero(records["P0_M0_D0"]["base"]["vDates"] == code)[0]) - 1])][3]
        day_idx = int(np.flatnonzero(daily_dates == formation)[0])
        candidates = []
        m0 = records["P0_M0_D0"]["selected"][code]["indicators"]["sma_200d"]
        m1 = records["P0_M1_D0"]["selected"][code]["indicators"]["sma_200d"]
        for asset_id in union_by_design_week[0, code]:
            i = records["P0_M0_D0"]["id_index"].get(asset_id)
            j = records["P0_M1_D0"]["id_index"].get(asset_id)
            if i is None or j is None or not np.isfinite(m0[i]) or np.isfinite(m1[j]):
                continue
            valid = np.flatnonzero(np.isfinite(daily_close[:day_idx + 1, i]))
            if not len(valid):
                continue
            age = day_idx - int(valid[0]) + 1
            count = int(np.isfinite(daily_close[max(0, day_idx - 199):day_idx + 1, i]).sum())
            if age >= 200:
                continue
            name, symbol = names[asset_id]
            candidates.append((age, dict(year_week=code, cmcid=asset_id, asset_name=name,
                                         ticker=symbol, formation_date=formation,
                                         first_finite_daily_close_date=int(daily_dates[valid[0]]),
                                         calendar_days_since_first_finite_close=age,
                                         finite_closes_in_200_day_window=count,
                                         M0_saved_sma_200d_predictor=scalar(m0[i]),
                                         M1_saved_sma_200d_predictor=scalar(m1[j]),
                                         source_basis="accepted_P0_D0_daily_b01_and_weekly_combo1")))
        if candidates:
            short_examples.append(sorted(candidates, key=lambda x: x[0])[0][1])
    assert 3 <= len(short_examples) <= 5, len(short_examples)

    # Source-date reconstruction for M0's calendar-year future-backfill bug.
    future_examples = []
    m0_root = records["P0_M0_D0"]["weekly"]
    m1_root = records["P0_M1_D0"]["weekly"]
    with h5py.File(m0_root) as old_h5, h5py.File(m1_root) as new_h5:
        week_dates = np.asarray(old_h5["rData/yrmoda"]).ravel().astype(int)
        old_close = np.asarray(old_h5["rData/mClose"])
        new_close = np.asarray(new_h5["rData/mClose"])
    old_idx = {int(x): i for i, x in enumerate(week_dates)}
    old_ids = records["P0_M0_D0"]["base"]["vAssetID"]
    for code in WEEKS:
        start, end, _, boundary_date = calendar[code]
        year = code // 100
        year_end = int(np.flatnonzero(daily_dates // 10000 == year)[-1])
        if year_end <= end:
            continue
        within = daily_close[start:end + 1, :]
        future = daily_close[end + 1:year_end + 1, :]
        valid_week = np.isfinite(within).any(axis=0)
        boundary_missing = ~np.isfinite(daily_close[end, :])
        latest = np.full(daily_close.shape[1], np.nan)
        latest_date = np.zeros(daily_close.shape[1], dtype=int)
        for k, values in enumerate(future, start=end + 1):
            mask = np.isfinite(values)
            latest[mask] = values[mask]
            latest_date[mask] = daily_dates[k]
        w = old_idx[code]
        matches = np.flatnonzero(valid_week & boundary_missing &
                                 np.isfinite(latest) & np.isfinite(old_close[:, w]) &
                                 np.isclose(old_close[:, w], latest, rtol=1e-12, atol=0) &
                                 ~np.isfinite(new_close[:, w]))
        if not len(matches):
            continue
        for i in matches[:2]:
            asset_id = int(old_ids[i])
            name, symbol = names[asset_id]
            future_examples.append(dict(year_week=code, cmcid=asset_id,
                                        asset_name=name, ticker=symbol,
                                        scheduled_week_end_date=boundary_date,
                                        scheduled_end_daily_close="",
                                        later_same_year_source_date=int(latest_date[i]),
                                        later_same_year_source_value=scalar(latest[i]),
                                        M0_saved_weekly_close=scalar(old_close[i, w]),
                                        M1_saved_weekly_close=scalar(new_close[i, w]),
                                        source_basis="value_matched_daily_b01_plus_legacy_last_rule"))
            if len(future_examples) == 5:
                break
        if len(future_examples) == 5:
            break
    assert 3 <= len(future_examples) <= 5, len(future_examples)

    manifest.append(dict(experiment_id="RAW_CMC_CLOSE",
                         research_run_id="", run_root_name="", baseline_sha256=sha(raw_close),
                         weekly_panel_sha256="", economic_ledger_sha256="",
                         run_complete_sha256="", acceptance_sha256=""))
    manifest.append(dict(experiment_id="P0_M0_D0_DAILY_B01",
                         research_run_id=records["P0_M0_D0"]["research_run_id"],
                         run_root_name=master_run.name, baseline_sha256=sha(daily_file),
                         weekly_panel_sha256="", economic_ledger_sha256="",
                         run_complete_sha256="", acceptance_sha256=""))

    with tempfile.TemporaryDirectory(prefix=".p0_week_audit_", dir=out.parent) as tmp:
        work = Path(tmp)
        columns = list(rows[0])
        for key in INDICATORS:
            columns.extend((f"indicator_{key}_value", f"indicator_{key}_missing"))
        columns += [f"{a}_{k}" for a in ("ew", "vw") for k in
                    ("group", "low_weight", "high_weight", "signed_hl_weight", "direct_opening_contribution")]
        # Dict insertion order varies between present/absent assets; ensure
        # every declared field is explicitly included exactly once.
        columns = list(dict.fromkeys(columns))
        for row in rows:
            extra = set(row) - set(columns)
            if extra:
                columns.extend(sorted(extra))
        write_csv_gz(work / "P0_KEY_WEEK_ASSET_METHOD_ROWS.csv.gz", rows, columns)
        write_csv_gz(work / "P0_KEY_WEEK_PORTFOLIOS.csv.gz", weekly_rows, list(weekly_rows[0]))
        write_csv_gz(work / "P0_REINVESTMENT_EVENT_WEEKS.csv.gz", reinvest_rows, list(reinvest_rows[0]))
        write_csv_gz(work / "P0_SMA_SHORT_HISTORY_EXAMPLES.csv.gz", short_examples, list(short_examples[0]))
        write_csv_gz(work / "P0_FUTURE_BACKFILL_EXAMPLES.csv.gz", future_examples, list(future_examples[0]))
        with (work / "SOURCE_MANIFEST.csv").open("w", newline="", encoding="utf-8") as fh:
            writer = csv.DictWriter(fh, fieldnames=list(manifest[0]), lineterminator="\n")
            writer.writeheader()
            writer.writerows(manifest)
        (work / "FIELD_DICTIONARY.md").write_text(field_dictionary(), encoding="utf-8")
        bundle = work / "AUDIT_BUNDLE.tar.gz"
        with bundle.open("wb") as raw, gzip.GzipFile(
            filename="", mode="wb", fileobj=raw, mtime=0, compresslevel=9
        ) as compressed, tarfile.open(fileobj=compressed, mode="w") as tar:
            for item in sorted(work.iterdir()):
                if item.name == bundle.name:
                    continue
                info = tar.gettarinfo(str(item), arcname=item.name)
                info.mtime = 0
                info.uid = info.gid = 0
                info.uname = info.gname = ""
                with item.open("rb") as fh:
                    tar.addfile(info, fh)
        checks = "".join(f"{sha(item)}  {item.name}\n" for item in sorted(work.iterdir())
                         if item.name != "SHA256SUMS")
        (work / "SHA256SUMS").write_text(checks, encoding="ascii")
        assert len(rows) == 3 * sum(len(v) for v in union_by_design_week.values())
        assert len(weekly_rows) == 3 * 3 * len(WEEKS) * 2
        out.mkdir()
        for item in work.iterdir():
            item.replace(out / item.name)
    print("P0_KEY_WEEK_AUDIT_OK", len(rows), len(weekly_rows), len(reinvest_rows),
          len(short_examples), len(future_examples), out, flush=True)


if __name__ == "__main__":
    main()
