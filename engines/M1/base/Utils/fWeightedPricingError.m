function vDelta = fWeightedPricingError(mAlphas, mResid)
% Function for calculating the weighted pricing error
%
% Input:
%   mAlphas:        M x K matrix of alphas
%                   M: number of test assets
%                   K: number of models
%   mResid:         T x M x K matrix of regression residuals
%                   T: number of time-series observations
%                   M: number of test assets
%                   K: number of models
%
% Output:
%   vDelta:         K x 1 vector of weighted pricing errors
%                   K: number of models

% Check inputs
arguments
    mAlphas (:,:) {mustBeNumeric}
    mResid (:,:,:) {mustBeNumeric}
end

% Determine dimensions
[iNumTestAssets, iNumModels] = size(mAlphas);
[iNumObs, iNumTestAssets2, iNumModels2] = size(mResid);

% Check dimensions
assert(iNumModels == iNumModels2, 'Number of models must agree');
assert(iNumTestAssets == iNumTestAssets2, 'Number of test assets must agree');

% Initialize memory
vDelta = NaN(iNumModels,1);

% Loop over models
for iIdxM = 1:iNumModels
    vAlphaTemp = mAlphas(:,iIdxM);
    mResidTemp = mResid(:,:,iIdxM);
    lValidAsset = ~isnan(vAlphaTemp) & ~all(isnan(mResidTemp),1)';
    vAlphaTemp = vAlphaTemp(lValidAsset);
    mResidTemp = mResidTemp(:,lValidAsset);

    lValidTime = ~any(isnan(mResidTemp),2);
    mResidTemp = mResidTemp(lValidTime,:);
    if isempty(vAlphaTemp) || size(mResidTemp,1) <= length(vAlphaTemp)
        continue
    end

    % Calculate variance-covariance matrix of model residuals
    mResidCov = cov(mResidTemp);
    if any(~isfinite(mResidCov),'all') || rcond(mResidCov) < 1e-12
        continue
    end

    % Calculate weighted pricing error
    vDelta(iIdxM) = vAlphaTemp' * (mResidCov \ vAlphaTemp);
end
end
