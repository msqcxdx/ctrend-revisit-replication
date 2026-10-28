function [vMktRet, mME_L1, rDiagnostics] = ...
        fValueWeightedMarketReturnStrict(mReturns, mME)
% Market return from a caller-supplied dynamic universe using lagged caps.
%
% The caller represents formation-date ineligibility by a missing market
% cap. The statistic at date t then uses only finite return_t and positive
% market-cap_{t-1}, re-normalizing weights over exactly that observable
% cross-section. A missing return is neither imputed as zero nor allowed to
% erase the entire market date.

arguments
    mReturns (:,:) {mustBeNumeric}
    mME (:,:) {mustBeNumeric}
end
assert(isequal(size(mReturns), size(mME)), ...
    'Returns and market capitalization must have identical dimensions');

mME_L1 = [NaN(1, size(mME,2)); mME(1:end-1,:)];
lPositiveLaggedME = isfinite(mME_L1) & mME_L1 > 0;
lMissingReturnGivenLaggedME = lPositiveLaggedME & ~isfinite(mReturns);
lConstituent = lPositiveLaggedME & isfinite(mReturns);
mWeightsNumerator = mME_L1;
mWeightsNumerator(~lConstituent) = NaN;
vWeightDenominator = sum(mWeightsNumerator, 2, 'omitmissing');
mWeights = mWeightsNumerator ./ vWeightDenominator;
mWeights(~lConstituent) = 0;

mReturnsForIndex = mReturns;
mReturnsForIndex(~lConstituent) = 0;
vMktRet = sum(mReturnsForIndex .* mWeights, 2);
vMktRet(~isfinite(vWeightDenominator) | vWeightDenominator <= 0) = NaN;

rDiagnostics = struct();
rDiagnostics.iNumDays = size(mReturns,1);
rDiagnostics.iNumDefinedDays = nnz(isfinite(vMktRet));
rDiagnostics.iNumDaysWithMissingReturnGivenLaggedME = ...
    nnz(any(lMissingReturnGivenLaggedME,2));
rDiagnostics.iNumMissingReturnAssetDays = ...
    nnz(lMissingReturnGivenLaggedME);
rDiagnostics.dDefinedFraction = ...
    rDiagnostics.iNumDefinedDays / max(rDiagnostics.iNumDays,1);
end
