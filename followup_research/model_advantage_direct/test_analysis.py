#!/usr/bin/env python3
"""Synthetic economic/statistical counterexamples, without research inputs."""
import os
for name in ('OPENBLAS_NUM_THREADS','OMP_NUM_THREADS','MKL_NUM_THREADS'): os.environ[name]='1'
import unittest
from pathlib import Path
import tempfile
import numpy as np
from core import (METHODS,MODELS,PAIRS,block_counts,factor_statistics,influence,
                  regression_hac,pricing_statistics,rolling_opportunities,grs,holm,
                  contrast_diagnostic,interval)


class ScientificContracts(unittest.TestCase):
    def setUp(self):
        self.rng=np.random.default_rng(426)
        self.f=self.rng.normal(0,.05,(300,6))+np.array([.005,.004,.003,.02,.015,.01])

    def test_moments_and_decomposition(self):
        f=self.f.copy();f[90]=np.nan
        q=factor_statistics(f,np.ones((1,len(f))))
        for j,m in enumerate(METHODS):
            ids=list(MODELS[m]);z=f[np.isfinite(f).all(1)][:,ids]
            mu=z.mean(0);cov=np.cov(z,rowvar=False,ddof=0)
            self.assertAlmostEqual(q['s2'][m][0],mu@np.linalg.solve(cov,mu),12)
            vct=q['s2'][f'A_{m}'][0]-q['s2']['LTW'][0]
            vm=q['s2'][f'A_{m}'][0]-q['s2'][m][0]
            self.assertAlmostEqual(vct,q['alpha'][0,j]**2/q['risk'][0,j]**2,12)
            self.assertAlmostEqual(vm,q['alpha_mom'][0,j]**2/q['risk_mom'][0,j]**2,12)
        self.assertAlmostEqual(q['delta'][0,2],q['delta'][0,0]+q['delta'][0,1],12)

    def test_weighted_bootstrap_matches_explicit_sample(self):
        f=self.f.copy();f[9:13]=np.nan
        counts=block_counts(len(f),8,5,100)
        self.assertTrue(np.all(counts.sum(1)==len(f)))
        self.assertTrue(np.array_equal(counts,block_counts(len(f),8,5,100)))
        q=factor_statistics(f,counts)
        for b in range(len(counts)):
            sample=np.repeat(f,counts[b].astype(int),axis=0)
            direct=factor_statistics(sample,np.ones((1,len(sample))))
            np.testing.assert_allclose(q['delta'][b],direct['delta'][0],atol=1e-12)

    def test_influence_derivative(self):
        f=self.f.copy();cols=[0,1,3];n=len(f)
        initial=factor_statistics(f,np.ones((1,n)))['s2']['M0'][0]
        w=np.ones((1,n));eps=1e-5;w[0,42]+=eps
        perturbed=factor_statistics(f,w)['s2']['M0'][0]
        self.assertAlmostEqual((perturbed-initial)/eps,influence(f,cols)[42],7)

    def test_singular_is_not_regularized(self):
        f=self.f.copy();f[:,1]=f[:,0]
        q=factor_statistics(f,np.ones((1,len(f))))
        self.assertTrue(np.isnan(q['d']).all())

    def test_fixed_asset_ols_and_grs(self):
        f=self.f; y=.01+f[:,:3]@self.rng.normal(0,.1,(3,5))+self.rng.normal(0,.03,(len(f),5))
        q=pricing_statistics(f,y,np.ones((1,len(f))))
        for j,(name,cols) in enumerate(MODELS.items()):
            x=np.column_stack([np.ones(len(f)),f[:,cols]])
            beta=np.linalg.lstsq(x,y,rcond=None)[0]
            np.testing.assert_allclose(q['alpha'][name][0],beta[0],atol=1e-13)
            self.assertAlmostEqual(q['msa'][0,j],np.mean(beta[0]**2)*1e4,10)
        self.assertTrue(np.isfinite(grs(f[:,:3],y)['grs_f']))
        self.assertTrue(np.isnan(grs(f[:,:3],np.column_stack([y,y[:,0]]))['grs_f']))

    def test_hac_keeps_missing_calendar_slots(self):
        y=self.f[:,3].copy();f=self.f[:,:2].copy();y[100:110]=np.nan
        a,cov,score,_,keep=regression_hac(y,f)
        self.assertTrue(np.all(score[~keep]==0));self.assertTrue(np.isfinite(cov).all())
        compressed=regression_hac(y[keep],f[keep])[1]
        self.assertFalse(np.allclose(cov,compressed,rtol=1e-9,atol=1e-15))

    def test_direction_and_no_future_training(self):
        f=self.f.copy();f[:,:]=-abs(f)-.02
        r,audit=rolling_opportunities(f,104)
        self.assertTrue(np.nanmean(r[:,0])>0)
        self.assertTrue(any(a['old_normalization_flip_count'] for a in audit))
        future=f.copy();future[200:]*=20
        r2,_=rolling_opportunities(future,104)
        np.testing.assert_array_equal(r[:200],r2[:200])
        f[130:140,5]=np.nan
        r,aa=rolling_opportunities(f,104)
        self.assertTrue(np.isnan(r[130:140]).all())
        self.assertTrue(all(a['train_end']<a['index'] and a['train_start']==a['index']-52 for a in aa))

    def test_degenerate_comparison_is_not_significant(self):
        f=self.f.copy();f[:,4]=f[:,3]
        status=contrast_diagnostic(f,3,4)['inference_status']
        self.assertIn('degenerate',status)
        result=interval(0,np.zeros(100),status,scores=np.zeros(len(f)))
        self.assertTrue(np.isnan(result['p_two_sided']))
        np.testing.assert_allclose(holm([.01,.04,.03]),[.03,.06,.06])

    def test_end_to_end_synthetic(self):
        from run_analysis import setting
        f=self.f; y=self.rng.normal(.002,.02,(len(f),4))
        legacy_f=f.copy();legacy_f[:,3:]=f[:,[5]]
        legacy_d=factor_statistics(legacy_f,np.ones((1,len(f))))['d'][0,2]
        old,_=rolling_opportunities(legacy_f,104,5,ddof=1)
        with tempfile.TemporaryDirectory() as tmp:
            p=Path(tmp)/'fixture.npz'
            np.savez(p,weeks=np.arange(len(f))+1,external=f[:,:3],ct_m0=f[:,3],ct_m2=f[:,4],ct_m1=f[:,5],
                     test_m1=y,test_m0=y,first_model_indices=np.array([52,52,52]),
                     asset_names=np.array(['a','b','c','d']),legacy_d_external=np.array([len(f),legacy_d]),
                     legacy_oos_external=old[:,[0,3]])
            output=setting((p,0,0,'external',50,426))
            self.assertEqual(len(output['advantage_changes']),9)
            self.assertEqual(len(output['pricing_changes']),72)
            self.assertEqual(len(output['oos_changes']),72)


if __name__=='__main__': unittest.main(verbosity=2)
