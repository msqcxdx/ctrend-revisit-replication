function [FGRS, pGRS, vAlpha, mResid] = fGRSFromReturns(mTestReturns, mFactors)
% Estimate all test-asset alphas on one common sample and run the GRS test.
%
% GRS is a system test: alphas, residual covariance, and factor moments must
% refer to the same T dates. Pairwise asset regressions followed by a later
% listwise residual deletion do not define the statistic.

arguments
    mTestReturns (:,:) {mustBeNumeric}
    mFactors (:,:) {mustBeNumeric}
end

assert(size(mTestReturns,1) == size(mFactors,1), ...
    'Test returns and factors must have the same number of dates.');

FGRS = NaN;
pGRS = NaN;
vAlpha = NaN(size(mTestReturns,2),1);
mResid = NaN(size(mTestReturns));

iNumAssets = size(mTestReturns,2);
iNumFactors = size(mFactors,2);
if iNumAssets == 0
    return
end

lCommon = all(isfinite(mTestReturns),2) & all(isfinite(mFactors),2);
mY = mTestReturns(lCommon,:);
mF = mFactors(lCommon,:);
iNumCommon = size(mY,1);
if iNumCommon <= iNumAssets + iNumFactors || ...
        iNumCommon <= iNumFactors + 1
    return
end

mX = [ones(iNumCommon,1), mF];
if rank(mX) < size(mX,2)
    return
end
mBeta = mX \ mY;
vAlpha = mBeta(1,:)';
mResidCommon = mY - mX*mBeta;
mResid(lCommon,:) = mResidCommon;

[FGRS, pGRS] = fGRS(vAlpha, mResidCommon, mF);
end
