#!/usr/bin/env python3
"""Trace INNBCL's 2020W16 forecast-to-weight path across E06 D0 refits.

Only saved baseline outputs are read.  Direct opening-weight contribution is
not a full reinvestment ledger, and this script does not judge CMC price truth.
"""

from __future__ import annotations

import csv
from hashlib import sha256
import json
from pathlib import Path

import numpy as np
from scipy.io import loadmat


ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "outputs/E06"
TARGET_ID = 3787
TARGET_WEEK = 202016
VARIANTS = ("control", "A", "B", "AB", "CD", "ABCD", "accepted_M1")


def digest(path: Path) -> str:
    h = sha256()
    with path.open("rb") as f:
        for block in iter(lambda: f.read(2**20), b""):
            h.update(block)
    return h.hexdigest()


def finite_number(x: float) -> float:
    return float(x) if np.isfinite(x) else float("nan")


def main() -> None:
    records: list[dict] = []
    sources: list[dict] = []
    for p in (0, 1):
        eid = f"P{p}_M2_D0"
        folder = OUT / "sensitivities" / eid
        receipt_path = folder / "HYBRID_RECEIPT.json"
        receipt = json.loads(receipt_path.read_text())
        if receipt["experiment_id"] != eid or set(receipt["results"]) != set(VARIANTS):
            raise ValueError(f"Incomplete D0 receipt: {eid}")
        sources.append({"experiment_id": eid, "receipt_sha256": digest(receipt_path)})
        for variant in VARIANTS:
            item = receipt["results"][variant]
            path = Path(item["path"])
            if digest(path) != item["sha256"]:
                raise ValueError(f"Result hash mismatch: {eid}/{variant}")
            data = loadmat(path, squeeze_me=True, struct_as_record=False,
                           variable_names=("vAssetID", "vDates", "mYhat",
                                           "mRetPnlOOS", "cResults"))
            ids = np.asarray(data["vAssetID"], dtype=int).ravel()
            weeks = np.asarray(data["vDates"], dtype=int).ravel()
            ai = np.flatnonzero(ids == TARGET_ID)
            wi = np.flatnonzero(weeks == TARGET_WEEK)
            if len(ai) != 1 or len(wi) != 1:
                raise ValueError(f"Target ID/week missing: {eid}/{variant}")
            a, t = int(ai[0]), int(wi[0])
            yhat = float(np.asarray(data["mYhat"], dtype=float)[a, t])
            payoff = float(np.asarray(data["mRetPnlOOS"], dtype=float)[a, t])
            weights = np.asarray(data["cResults"].VW.mWts, dtype=float)
            wlow, whigh = float(weights[a, t, 0]), float(weights[a, t, -1])
            hl = float(np.asarray(data["cResults"].VW.mPortRet,
                                  dtype=float)[-1, t])
            direct = ((whigh if np.isfinite(whigh) else 0.0)
                      -(wlow if np.isfinite(wlow) else 0.0))*payoff
            records.append({"experiment_id": eid, "variant": variant,
                            "year_week": TARGET_WEEK, "cmcid": TARGET_ID,
                            "saved_forecast": finite_number(yhat),
                            "forecast_finite": int(np.isfinite(yhat)),
                            "low_opening_weight": finite_number(wlow),
                            "high_opening_weight": finite_number(whigh),
                            "saved_asset_economic_payoff": finite_number(payoff),
                            "direct_opening_weight_contribution": finite_number(direct),
                            "saved_vw_hl_return": finite_number(hl),
                            "scope": "baseline_saved_output_direct_weight_not_full_ledger"})
    if len(records) != 2*len(VARIANTS):
        raise ValueError("D0 key-week trace incomplete")
    output = OUT / "sensitivity_innbcl_2020W16.csv"
    with output.open("w", newline="", encoding="utf-8") as f:
        writer = csv.DictWriter(f, fieldnames=list(records[0]))
        writer.writeheader()
        writer.writerows(records)
    receipt = {"scope": "D0_two_P_cells_seven_E06_paths_one_asset_one_week",
               "sources": sources, "rows": len(records),
               "output_sha256": digest(output)}
    (OUT / "SENSITIVITY_INNBCL_RECEIPT.json").write_text(json.dumps(receipt, indent=2)+"\n")
    print("E06_INNBCL_TRACE_OK cells=2 paths=7")


if __name__ == "__main__":
    main()
