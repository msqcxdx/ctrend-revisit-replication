function [mX, vY, mIdx, vZ] = fCreatePanelExAnte(mX, mY, mZ, options)
% Stack a panel for OOS prediction without filtering on future Y.
%
% Rows are kept when ex-ante predictors and optional weights are available.
% The dependent variable is allowed to be NaN so OOS scoring can still be
% produced for assets whose realized return is not yet known at formation.
% By default, every predictor must be finite, preserving the historical
% complete-case behavior used by Table 4.  Set lKeepPredictorUnion=true for
% models that estimate a separate univariate regression for each predictor;
% then a row is retained whenever at least one predictor is finite.

arguments
    mX (:,:,:) {mustBeNumeric}
    mY (:,:) {mustBeNumeric}
    mZ (:,:) {mustBeNumeric} = []
    options.lKeepPredictorUnion (1,1) {mustBeNumericOrLogical} = false
end

[iNumAssets, iNumObs, iNumVars] = size(mX);
assert(iNumAssets == size(mY, 1), 'Number of assets must agree');
assert(iNumObs == size(mY, 2), 'Number of time-series observations must agree');
if ~isempty(mZ)
    assert(iNumAssets == size(mZ, 1), 'Number of assets must agree');
    assert(iNumObs == size(mZ, 2), 'Number of time-series observations must agree');
end

mNumAssets = repmat((1:iNumAssets)', 1, iNumObs);
mNumObs = repmat(1:iNumObs, iNumAssets, 1);
mIdx = [reshape(mNumObs, [], 1), reshape(mNumAssets, [], 1)];
vY = reshape(mY, [], 1);
mX = reshape(mX, [], iNumVars);

if options.lKeepPredictorUnion
    lMissingPredictors = ~any(isfinite(mX), 2);
else
    lMissingPredictors = any(~isfinite(mX), 2);
end
if ~isempty(mZ)
    vZ = reshape(mZ, [], 1);
    lIsNaN = lMissingPredictors | ~isfinite(vZ);
else
    vZ = [];
    lIsNaN = lMissingPredictors;
end

mX(lIsNaN, :) = [];
vY(lIsNaN) = [];
mIdx(lIsNaN, :) = [];
if ~isempty(vZ)
    vZ(lIsNaN) = [];
end
end
