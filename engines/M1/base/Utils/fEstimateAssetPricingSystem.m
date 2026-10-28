function rSystem = fEstimateAssetPricingSystem(mTestReturns, mFactors)
% Estimate one asset-pricing system on one common date sample.

arguments
    mTestReturns (:,:) {mustBeNumeric}
    mFactors (:,:) {mustBeNumeric}
end

assert(size(mTestReturns,1) == size(mFactors,1), ...
    'Test returns and factors must have the same number of dates.');
iNumInputAssets = size(mTestReturns,2);
iNumFactors = size(mFactors,2);
rSystem = struct('vAlpha',NaN(iNumInputAssets,1), ...
    'vAlphaT',NaN(iNumInputAssets,1),'mResid',NaN(size(mTestReturns)), ...
    'dDelta',NaN,'dGRSp',NaN,'lCommon',false(size(mTestReturns,1),1), ...
    'vUniqueAssetIndex',NaN(1,0),'vAssetToUnique',NaN(1,iNumInputAssets), ...
    'iNumUniqueAssets',0);
if iNumInputAssets == 0
    return
end

lCommon = all(isfinite(mTestReturns),2) & all(isfinite(mFactors),2);
mYInput = mTestReturns(lCommon,:);
mF = mFactors(lCommon,:);
iNumObs = size(mYInput,1);
if iNumObs == 0
    return
end

% Some anomaly definitions generate exactly identical long-short return
% series. Keeping duplicate test assets makes the residual covariance
% mechanically singular and leaves Delta/GRS undefined. Deduplicate only
% exact system aliases on the already fixed common sample; do not remove
% merely correlated assets or use a pseudoinverse.
[vUniqueAssetIndex,vAssetToUnique] = iExactUniqueColumns(mYInput);
mY = mYInput(:,vUniqueAssetIndex);
iNumAssets = size(mY,2);
rSystem.vUniqueAssetIndex = vUniqueAssetIndex;
rSystem.vAssetToUnique = vAssetToUnique;
rSystem.iNumUniqueAssets = iNumAssets;

mX = [ones(iNumObs,1),mF];
iNumCoeff = size(mX,2);
if iNumObs <= iNumAssets+iNumFactors || iNumObs <= iNumCoeff || ...
        rank(mX) < iNumCoeff
    return
end

mBeta = mX\mY;
mResidCommon = mY-mX*mBeta;
iDFE = iNumObs-iNumCoeff;
vSigma2 = sum(mResidCommon.^2,1)'/iDFE;
[~,mR] = qr(mX,0);
mRinv = mR\eye(iNumCoeff);
mXXinv = mRinv*mRinv';
vSEAlpha = sqrt(vSigma2*mXXinv(1,1));
vAlphaUnique = mBeta(1,:)';
vAlphaTUnique = vAlphaUnique./vSEAlpha;
vAlphaTUnique(~isfinite(vAlphaTUnique)) = NaN;

mResidCov = cov(mResidCommon);
dDelta = NaN;
if all(isfinite(mResidCov),'all') && rcond(mResidCov) >= 1e-12
    dDelta = vAlphaUnique'*(mResidCov\vAlphaUnique);
end
[~,dGRSp] = fGRS(vAlphaUnique,mResidCommon,mF);

rSystem.vAlpha = vAlphaUnique(vAssetToUnique);
rSystem.vAlphaT = vAlphaTUnique(vAssetToUnique);
rSystem.mResid(lCommon,:) = mResidCommon(:,vAssetToUnique);
rSystem.dDelta = dDelta;
rSystem.dGRSp = dGRSp;
rSystem.lCommon = lCommon;
end

function [vUniqueIndex,vMap] = iExactUniqueColumns(mY)
iNumAssets = size(mY,2);
vUniqueIndex = zeros(1,iNumAssets);
vMap = zeros(1,iNumAssets);
iNumUnique = 0;
for iIdxAsset = 1:iNumAssets
    iMatch = 0;
    for iIdxUnique = 1:iNumUnique
        if isequaln(mY(:,iIdxAsset),mY(:,vUniqueIndex(iIdxUnique)))
            iMatch = iIdxUnique;
            break
        end
    end
    if iMatch == 0
        iNumUnique = iNumUnique + 1;
        vUniqueIndex(iNumUnique) = iIdxAsset;
        iMatch = iNumUnique;
    end
    vMap(iIdxAsset) = iMatch;
end
vUniqueIndex = vUniqueIndex(1:iNumUnique);
end
