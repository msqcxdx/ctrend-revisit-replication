#!/usr/bin/env python3
"""Hold M1 positions fixed; isolate old versus drift-aware cost arithmetic.

The original formula compares successive target weights, not prior drifted
holdings. This diagnostic applies that formula to EXACTLY the accepted M1
targets, so it is not an M0 model backtest. The corrected cost base is checked
asset by asset against saved prior end weights plus within-week trades. Gaps
with unidentified opening state are retained as missing, never free entry.
"""
import csv
from pathlib import Path
import numpy as np
from scipy.io import loadmat
from analyze_e09 import ROOT, REPO, OUT, FEES, write
from paired_stats import newey_west, annual_sharpe


def legacy_cost_base(weights):
    w=np.nan_to_num(weights,nan=0.)
    prior=np.concatenate((np.zeros_like(w[:,:1]),w[:,:-1]),axis=1)
    cost=np.abs(w-prior).sum(axis=0)
    cost[(w==0).all(axis=0)]=np.nan
    return cost


def main():
    weekly=[];summary=[]
    for p in (0,1):
        for d in (0,1,2):
            eid=f'P{p}_M1_D{d}'
            z=loadmat(REPO/'results/experiments'/eid/'CTREND/CTREND_Base.mat',simplify_cells=True)
            port=z['cResults']['VW'];w=np.asarray(port['mWts'],float)
            old=legacy_cost_base(w)
            cost=np.asarray(port['mCostBaseFull'],float)
            opening=np.asarray(port['mOpeningTradeCostBaseFull'],float)
            within=np.asarray(port['mForcedLiquidationCostBaseFull'],float)
            prior=np.asarray(port['mPriorEndRiskyWeightsAtTransition'],float)
            observed=np.asarray(port['lObservableTransition'],bool).T
            raw=np.abs(np.nan_to_num(w,nan=0.)-prior)
            independently_summed=np.nansum(raw,axis=0)
            independently_summed[~observed[:,:5]]=np.nan
            np.testing.assert_allclose(independently_summed,opening[:,:5],atol=1e-12,rtol=1e-12,equal_nan=True)
            np.testing.assert_allclose(cost,opening+within,atol=1e-12,rtol=1e-12,equal_nan=True)
            np.testing.assert_allclose(cost[:,-1],cost[:,0]+cost[:,4],atol=1e-12,rtol=1e-12,equal_nan=True)
            gross=np.asarray(port['mPortRet'],float)[-1]
            first=np.asarray(port['lFirstEverTarget'],bool)
            restart=np.asarray(port['lRestartAfterGap'],bool)
            for t,week in enumerate(np.asarray(z['vDates'],int).ravel()):
                for leg,j in (('short',0),('long',4)):
                    weekly.append(dict(experiment_id=eid,year_week=int(week),leg=leg,
                        original_target_difference_full_l1=old[t,j],
                        drift_aware_opening_full_l1=opening[t,j],within_week_full_l1=within[t,j],
                        corrected_total_full_l1=cost[t,j],observable_transition=int(observed[t,j]),
                        initial_formation=int(first[j,t]),restart_after_gap=int(restart[j,t])))
            for short_rate,long_rate in FEES:
                pair=np.isfinite(gross)&np.isfinite(cost[:,[0,4]]).all(1)&np.isfinite(old[:,[0,4]]).all(1)
                oldnet=np.where(pair,gross-short_rate*old[:,0]-long_rate*old[:,4],np.nan)
                net=np.where(pair,gross-short_rate*cost[:,0]-long_rate*cost[:,4],np.nan)
                reg=newey_west(net-oldnet,np.empty((len(gross),0)))
                summary.append(dict(experiment_id=eid,short_fee=short_rate,long_fee=long_rate,
                    paired_weeks=int(pair.sum()),same_holdings_original_cost_net_mean_pct=100*np.nanmean(oldnet),
                    corrected_cost_net_mean_pct=100*np.nanmean(net),difference_pct=100*reg['alpha'],
                    difference_hac_ci_low_pct=100*reg['alpha_ci_low'],difference_hac_ci_high_pct=100*reg['alpha_ci_high'],
                    original_cost_net_sharpe=annual_sharpe(oldnet),corrected_cost_net_sharpe=annual_sharpe(net),
                    scope='M1_positions_fixed_cost_arithmetic_only_not_M0_model_or_executable_account'))
            print(f'E09_COST_IDENTITY_OK {eid}',flush=True)
    write(OUT/'fixed_holdings_cost_accounting_weekly.csv',weekly)
    write(OUT/'fixed_holdings_cost_accounting_summary.csv',summary)


if __name__=='__main__':main()
