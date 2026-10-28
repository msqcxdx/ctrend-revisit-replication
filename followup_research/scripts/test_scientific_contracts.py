#!/usr/bin/env python3
"""Offline economic/statistical regression tests, independent of output hashes.

These deliberately exercise counterexamples: negative tangency budgets,
non-consecutive research weeks, one-asset exact GRS, and payoff-blind formation.
Passing them is necessary, not proof of all assumptions or empirical results.
"""
import unittest
import numpy as np
from scipy.stats import f as f_distribution
from analyze_e02 import original_formula
from analyze_e03_oos import opportunity_weights
from analyze_e05_formation import formation_only_weights, weights
from paired_stats import newey_west, max_squared_sharpe
from extend_e07_controlled_transmission import capped_weights, direct_sort
from analyze_e09_cost_accounting import legacy_cost_base
from analyze_e09_capacity_proxy import proxy_capacity
from extend_e03_e04_inference import risk


class ScientificContracts(unittest.TestCase):
    def test_grs_one_asset_equals_intercept_t_squared(self):
        rng=np.random.default_rng(42)
        f=rng.normal(.2,.8,(113,3))
        y=.3+f@np.array([.1,-.4,.2])+rng.normal(0,1,113)
        x=np.column_stack((np.ones(len(y)),f))
        b=np.linalg.lstsq(x,y,rcond=None)[0]; u=y-x@b
        cov=(u@u)/(len(y)-4)*np.linalg.inv(x.T@x)
        t2=b[0]**2/cov[0,0]
        exact=original_formula(b[:1],u[:,None],f,exact_grs=True)
        self.assertAlmostEqual(exact['grs_f'],t2,places=10)
        self.assertAlmostEqual(exact['grs_p'],f_distribution.sf(t2,1,len(y)-4),places=12)
        legacy=original_formula(b[:1],u[:,None],f)
        self.assertGreater(abs(legacy['grs_f']-t2),1e-6)

    def test_excess_factor_negative_budget_not_reverse_expected_return(self):
        rng=np.random.default_rng(7)
        x=rng.normal(size=(250,3))+np.array([-.8,-.4,.1])
        w,reason=opportunity_weights(x)
        self.assertEqual(reason,'ok')
        self.assertLess(w.sum(),0)
        self.assertGreater(x.mean(0)@w,0)
        self.assertAlmostEqual(w@np.cov(x,rowvar=False)@w,.01,places=12)

    def test_nested_sharpe_identity_exact_sample_divisors(self):
        rng=np.random.default_rng(18)
        x=rng.normal(size=(200,4))+.2
        reg=newey_west(x[:,3],x[:,:3])
        delta=max_squared_sharpe(x)-max_squared_sharpe(x[:,:3])
        expected=reg['alpha']**2/reg['residual_sd']**2*199/196
        self.assertAlmostEqual(delta,expected,places=12)

    def test_hac_preserves_calendar_gaps(self):
        y=np.array([1.,2.,np.nan,np.nan,-1.,3.,2.,1.,np.nan,2.,-1.,4.])
        result=newey_west(y,np.empty((len(y),0)),lag=1)
        u=np.where(np.isfinite(y),y-np.nanmean(y),0)
        n=np.isfinite(y).sum()
        variance=(u@u+u[1:]@u[:-1])/n**2
        self.assertAlmostEqual(result['alpha_se_hac']**2,variance,places=12)

    def test_formation_api_cannot_read_future_payoff(self):
        pred=np.arange(100,dtype=float); cap=np.full(100,2e6)
        entry=np.ones(100); stable=np.zeros(100,bool)
        strict,_=formation_only_weights(pred,cap,entry,stable)
        eligible=np.ones(100,bool); eligible[:20]=False
        hindsight,_=weights(pred,cap,eligible)
        again,_=formation_only_weights(pred.copy(),cap.copy(),entry.copy(),stable.copy())
        np.testing.assert_array_equal(strict,again)
        self.assertGreater(np.abs(strict-hindsight).sum(),0)
        self.assertTrue(np.allclose(strict.sum(0),1))

    def test_capped_value_weights_are_fully_invested_or_infeasible(self):
        self.assertIsNone(capped_weights(np.ones(9)))
        for caps in (np.ones(10),np.r_[1e15,np.ones(19)],np.arange(1,101)):
            w=capped_weights(caps)
            self.assertAlmostEqual(w.sum(),1.,places=12)
            self.assertLessEqual(w.max(),.1+1e-12)

    def test_controlled_sort_does_not_drop_an_unpriced_selected_asset(self):
        x=np.arange(50,dtype=float);cap=np.ones(50);pay=np.full(50,.01)
        pay[0]=np.nan
        r=direct_sort(x,cap,pay,np.ones(50,bool),'VW')
        self.assertEqual(r['status'],'selected_payoff_missing_no_renormalization')
        self.assertTrue(np.isnan(r['direct_hl']))

    def test_original_cost_formula_ignores_drift_by_construction(self):
        w=np.array([[[.5],[.5]],[[.5],[.5]]])
        old=legacy_cost_base(w)
        np.testing.assert_array_equal(old[:,0],[1.,0.])
        actual_second=np.abs(w[:,1,0]-np.array([.8,.2])).sum()
        self.assertAlmostEqual(actual_second,.6)

    def test_hedge_only_sort_does_not_require_nontraded_middle_groups(self):
        x=np.r_[-np.arange(20,0,-1),np.zeros(60),np.arange(1,21)].astype(float)
        w,counts=weights(x,np.ones(100),np.ones(100,bool))
        self.assertEqual(min(counts),0)
        self.assertAlmostEqual(w[:,0].sum(),1.)
        self.assertAlmostEqual(w[:,-1].sum(),1.)

    def test_zero_and_unknown_volume_are_not_interchangeable(self):
        known=proxy_capacity([.5,.5],[100,0])
        unknown=proxy_capacity([.5,.5],[100,np.nan])
        self.assertEqual(known[0],0.)
        self.assertTrue(known[1])
        self.assertTrue(np.isnan(unknown[0]))
        self.assertFalse(unknown[1])
        self.assertEqual(unknown[3].min(),200.)

    def test_drawdown_includes_initial_nav_and_rejects_missing_or_negative_gross(self):
        self.assertAlmostEqual(risk(np.array([-.1,.05]))['drawdown'],.1)
        self.assertTrue(np.isnan(risk(np.array([-.1,np.nan,.05]))['drawdown']))
        self.assertTrue(np.isnan(risk(np.array([-.1,-1.5,.05]))['drawdown']))


if __name__=='__main__':
    unittest.main(verbosity=2)
