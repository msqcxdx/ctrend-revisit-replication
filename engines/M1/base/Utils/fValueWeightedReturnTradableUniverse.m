function [vPortfolioReturn,rDiagnostics] = ...
        fValueWeightedReturnTradableUniverse(mReturns,mFormationME)
% Form a value-weighted return over the known-tradable target universe.
%
% A finite positive formation market cap supplies the proposed weight.  A
% missing economic payoff means the asset is unavailable for this target
% week under the declared announcement-equivalence convention, so it is
% removed before weights are normalized.  This is not a zero payoff and is
% not a post-return magnitude screen.

arguments
    mReturns (:,:) {mustBeNumeric}
    mFormationME (:,:) {mustBeNumeric}
end
assert(isequal(size(mReturns),size(mFormationME)), ...
    'Return and formation-market-cap matrices must agree');

lProposed = isfinite(mFormationME) & mFormationME > 0;
lTradable = lProposed & isfinite(mReturns);
mWeightNumerator = mFormationME;
mWeightNumerator(~lTradable) = 0;
vDenominator = sum(mWeightNumerator,2);
mWeights = mWeightNumerator./vDenominator;
mWeights(~lTradable) = 0;
mReturnsUse = mReturns;
mReturnsUse(~lTradable) = 0;
vPortfolioReturn = sum(mWeights.*mReturnsUse,2);
lDefined = isfinite(vDenominator) & vDenominator > 0;
vPortfolioReturn(~lDefined) = NaN;

rDiagnostics = struct();
rDiagnostics.lFormationValid = any(lProposed,2);
rDiagnostics.lPayoffComplete = lDefined;
rDiagnostics.vFormationHoldings = sum(lProposed,2);
rDiagnostics.vUnavailableAtTargetHoldings = sum(lProposed & ~lTradable,2);
rDiagnostics.vTradableHoldings = sum(lTradable,2);
rDiagnostics.vUnavailableProposedWeight = sum( ...
    iNormalizeProposedME(mFormationME,lProposed).*(lProposed & ~lTradable),2);
rDiagnostics.iNumFormationValid = nnz(rDiagnostics.lFormationValid);
rDiagnostics.iNumPayoffComplete = nnz(lDefined);
rDiagnostics.sRule = ...
    'known target unavailability removed before weight normalization';
end

function mWeights = iNormalizeProposedME(mME,lProposed)
mUse = mME;
mUse(~lProposed) = 0;
vTotal = sum(mUse,2);
mWeights = mUse./vTotal;
mWeights(~lProposed | ~isfinite(mWeights)) = 0;
end
