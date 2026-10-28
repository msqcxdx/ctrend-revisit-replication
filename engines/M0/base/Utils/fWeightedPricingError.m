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

% Remove missing values
lIsNaN = any(any(isnan(mResid), 2),3);
mResid(lIsNaN,:,:) = [];

% Initialize memory
vDelta = NaN(iNumModels,1);

% Loop over models
for iIdxM = 1:iNumModels
    % Calculate variance-covariance matrix of model residuals
    mResidCov = cov(mResid(:,:,iIdxM));

    % Calculate weighted pricing error
    vDelta(iIdxM) = mAlphas(:,iIdxM)' * inv(mResidCov) * mAlphas(:,iIdxM);
end
end