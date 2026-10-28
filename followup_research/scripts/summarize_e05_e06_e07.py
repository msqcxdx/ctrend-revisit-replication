#!/usr/bin/env python3
"""Summarize isolated formation and weight/payoff mechanism diagnostics."""

from __future__ import annotations

import csv
from pathlib import Path

import numpy as np


ROOT = Path(__file__).resolve().parents[1]


def write(path: Path, rows: list[dict]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w",newline="",encoding="utf-8") as f:
        writer=csv.DictWriter(f,fieldnames=list(rows[0]))
        writer.writeheader();writer.writerows(rows)


def mean_valid(x: np.ndarray) -> float:
    x=x[np.isfinite(x)]
    return float(x.mean()) if len(x) else np.nan


def summarize_e05() -> None:
    rows=list(csv.DictReader((ROOT/"outputs/E05/formation_snapshot_and_future_availability_perturbation.csv").open()))
    out=[]
    for eid in sorted(set(r["experiment_id"] for r in rows)):
        a=[r for r in rows if r["experiment_id"]==eid]
        val=lambda field:np.array([float(r[field]) for r in a])
        changed=val("saved_vs_formation_only_l1")
        missing=val("strict_low_missing_payoff_weight")+val("strict_high_missing_payoff_weight")
        x=val("strict_direct_hl_if_all_selected_payoffs_observed")
        saved=val("saved_hl")
        pair=np.isfinite(x)&np.isfinite(saved)
        out.append(dict(experiment_id=eid,calendar_weeks=len(a),
                        formation_only_vs_accepted_weight_different_weeks=int((changed>1e-10).sum()),
                        strict_selected_payoff_missing_weeks=int((missing>0).sum()),
                        strict_selected_payoff_missing_max_leg_weight=float(missing.max()),
                        accepted_weights_change_under_target_availability_perturbation_weeks=int((val("accepted_replay_after_target_availability_toggle_l1")>1e-10).sum()),
                        strict_weights_change_under_same_perturbation_weeks=int((val("strict_formation_after_target_toggle_l1")>1e-10).sum()),
                        paired_direct_return_weeks=int(pair.sum()),
                        strict_direct_mean_pct=100*mean_valid(x[pair]),
                        accepted_hl_same_week_mean_pct=100*mean_valid(saved[pair]),
                        scope="saved_forecasts_and_formation_sort_only_not_full_model_replay"))
    write(ROOT/"outputs/E05/formation_channel_summary.csv",out)
    print(f"E05_CHANNEL_SUMMARY_OK experiments={len(out)}")


def summarize_e06_e07() -> None:
    rows=list(csv.DictReader((ROOT/"outputs/E07/paired_m2_m1_forecast_weights_payoff.csv").open()))
    ledger={(r['experiment_id'],int(r['week_key'])):r for r in csv.DictReader(
        (ROOT/'outputs/E08/weekly_concentration_and_reconciliation.csv').open())}
    out=[]
    for p in (0,1):
        for d in (0,1,2):
            a=[r for r in rows if r["p"]==str(p) and r["d"]==str(d)]
            val=lambda field:np.array([float(r[field]) for r in a])
            r22=val("m2_weights_m2_payoff_direct")
            r21=val("m2_weights_m1_payoff_direct")
            r11=val("m1_weights_m1_payoff_direct")
            r12=val("m1_weights_m2_payoff_direct")
            four=np.isfinite(r22)&np.isfinite(r21)&np.isfinite(r11)&np.isfinite(r12)
            noexit=np.array([all(int(ledger[(f'P{p}_M{m}_D{d}',int(r['year_week']))][
                'has_same_leg_exit_event'])==0 for m in (2,1)) for r in a])
            actual=np.isfinite(val('saved_m2_hl'))&np.isfinite(val('saved_m1_hl'))
            eligible=four&noexit&actual
            # In an interaction-rich setting this is an ordered path,
            # not an independent causal attribution to a code module.
            payoff=r21-r22
            weights=r11-r21
            total=r11-r22
            if not np.allclose((payoff+weights)[eligible],total[eligible],atol=1e-10):
                raise RuntimeError("E06 ordered swap identity failed")
            out.append(dict(
                p=p,d=d,calendar_weeks=len(a),four_corner_direct_identified_weeks=int(four.sum()),
                paired_direct_without_exit_weeks=int(eligible.sum()),
                m2_to_m1_direct_difference_mean_pct=100*mean_valid(total[eligible]),
                m2_weights_payoff_array_switch_mean_pct=100*mean_valid(payoff[eligible]),
                m1_payoff_weight_switch_mean_pct=100*mean_valid(weights[eligible]),
                reverse_order_weight_switch_mean_pct=100*mean_valid((r12-r22)[eligible]),
                reverse_order_payoff_switch_mean_pct=100*mean_valid((r11-r12)[eligible]),
                weight_payoff_interaction_mean_pct=100*mean_valid((r11-r12-r21+r22)[eligible]),
                arithmetic_shapley_weight_mean_pct=50*mean_valid((r11-r21+r12-r22)[eligible]),
                arithmetic_shapley_payoff_mean_pct=50*mean_valid((r21-r22+r11-r12)[eligible]),
                both_forecast_median=float(np.median(val("both_forecast_count"))),
                only_m2_forecast_median=float(np.median(val("only_m2_forecast_count"))),
                only_m1_forecast_median=float(np.median(val("only_m1_forecast_count"))),
                high_holding_jaccard_median=float(np.nanmedian(
                    val("high_holding_intersection")/np.where(
                        val("high_holding_union")>0,val("high_holding_union"),np.nan))),
                low_holding_jaccard_median=float(np.nanmedian(
                    val("low_holding_intersection")/np.where(
                        val("low_holding_union")>0,val("low_holding_union"),np.nan))),
                scope="ordered_weight_payoff_swap_not_A_to_E_module_ablation",
            ))
    write(ROOT/"outputs/E06/ordered_weight_payoff_mechanism.csv",out)
    write(ROOT/"outputs/E07/coverage_holdings_summary.csv",out)
    print(f"E06_E07_MECHANISM_SUMMARY_OK outer_pairs={len(out)}")


if __name__=="__main__":
    summarize_e05();summarize_e06_e07()
