function [vPortfolioReturn,rDiagnostics] = ...
        fValueWeightedReturnFailClosed(mReturns,mFormationME)
% Value-weighted payoff without ex-post survivor reweighting.
%
% A positive finite formation market cap defines a holding before its
% realized payoff is known. If any selected payoff is unavailable, the
% portfolio return is unknown for that date.

arguments
    mReturns (:,:) {mustBeNumeric}
    mFormationME (:,:) {mustBeNumeric}
end
assert(isequal(size(mReturns),size(mFormationME)), ...
    'Return and formation-market-cap matrices must agree');

lHolding = isfinite(mFormationME) & mFormationME > 0;
mNumerator = mFormationME;
mNumerator(~lHolding) = 0;
vDenominator = sum(mNumerator,2);
mWeights = mNumerator ./ vDenominator;
mWeights(~lHolding) = 0;
lMissingPayoff = lHolding & ~isfinite(mReturns);
mReturnsUse = mReturns;
mReturnsUse(~lHolding) = 0;
mReturnsUse(~isfinite(mReturnsUse)) = 0;
vPortfolioReturn = sum(mWeights .* mReturnsUse,2);
lFormationValid = isfinite(vDenominator) & vDenominator > 0;
lPayoffComplete = ~any(lMissingPayoff,2);
vPortfolioReturn(~lFormationValid | ~lPayoffComplete) = NaN;

rDiagnostics = struct();
rDiagnostics.lFormationValid = lFormationValid;
rDiagnostics.lPayoffComplete = lPayoffComplete;
rDiagnostics.vFormationHoldings = sum(lHolding,2);
rDiagnostics.vMissingPayoffHoldings = sum(lMissingPayoff,2);
rDiagnostics.vMissingPayoffWeight = ...
    sum(mWeights .* lMissingPayoff,2);
rDiagnostics.iNumFormationValid = nnz(lFormationValid);
rDiagnostics.iNumPayoffComplete = ...
    nnz(lFormationValid & lPayoffComplete);
end
