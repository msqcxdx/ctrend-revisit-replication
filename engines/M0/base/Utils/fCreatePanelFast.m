function [mX,vY,mIdx,vZ] = fCreatePanelFast(mX,mY,mZ)
% Function for the fast creation of panel matrices
%
% Input:
%   mX:             N x T x M matrix of independent variables
%                   N: number of assets
%                   T: number of time-series observations
%                   M: number of variables
%   mY:             N x T matrix of dependent variables
%                   N: number of assets
%                   T: number of time-series observations
%   mZ:             N x T matrix of additional variables (e.g., weights)
%                   N: number of assets
%                   T: number of time-series observations
%
% Output:
%   mX:         (N * T) x M matrix of stacked independent variables 
%               (without NaN)
%   vY:         (N * T) x 1 vector of stacked dependent variables 
%               (without NaN)
%   mIdx:       (N * T) x 2 matrix. First column indicates the time ID and
%               second column refers to the object ID
%   vZ:         (N * T) x 1 vector of stacked dependent additional variables 
%               (e.g., weights) (without NaN)

% Check inputs
arguments
    mX (:,:,:) {mustBeNumeric}
    mY (:,:) {mustBeNumeric}
    mZ (:,:) {mustBeNumeric} = []
end

% Determine dimension
[iNumAssets, iNumObs, iNumVars] = size(mX);
[iNumAssetsY, iNumObsY] = size(mY);

% Check dimensions
assert(iNumAssets == iNumAssetsY, 'Number of assets must agree');
assert(iNumObs == iNumObsY, 'Number of time-series observations must agree');
if ~isempty(mZ)
    assert(iNumAssets == size(mZ,1),'Number of assets must agree');
    assert(iNumObs == size(mZ,2), 'Number of time-series observations must agree');
end

% Create indices for response variables and time-series observations
mNumAssets  = repmat((1:iNumAssets)', 1, iNumObs);
mNumObs     = repmat((1:iNumObs), iNumAssets, 1);

% Reshape indices
vAssetID    = reshape(mNumAssets,iNumAssets * iNumObs, 1);
vTimeID     = reshape(mNumObs,iNumAssets * iNumObs, 1);
mIdx        = [vTimeID, vAssetID];

% Reshape response variables
vY = reshape(mY,iNumAssets * iNumObs, 1);

% Reshape independent variables
mX = reshape(mX,iNumAssets * iNumObs, iNumVars);

% Reshape additional variables
if ~isempty(mZ)
    vZ = reshape(mZ,iNumAssets * iNumObs, 1);
end

% === Remove missing values
% Find missing values
if ~isempty(mZ)
    lIsNaN = any(isnan(mX),2) | isnan(vY) | isnan(vZ);
else
    lIsNaN = any(isnan(mX),2) | isnan(vY);
end

% Remove all missing values
mX(lIsNaN,:)    = [];
vY(lIsNaN)      = [];
mIdx(lIsNaN,:)  = [];
if ~isempty(mZ)
    vZ(lIsNaN)  = [];
else
    vZ = [];
end
end
