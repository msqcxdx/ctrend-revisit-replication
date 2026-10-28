function vYhat = fPredictPanelRegression(rModel, mX, mID)
% Function for predicting values using an pooled OLS model
% 
% Input:
%   rModel:                 Struct, containing the settings and parameters
%   mX:                     (T * N) x K matrix of the independent variables
%                           T: number of time-series observations
%                           N: number of objects
%                           K: number of independent variables
%   mID:                    (T * N) x 2 matrix. First column indicates the
%                           time ID and second column refers to the object ID
%                           T: number of time-series observations
%                           N: number of objects
%
% Output:
%   vYhat:                  (T * N) x 1 vector of estimates for the target
%                           variable
%                           T: number of time-series observations
%                           N: number of objects

% Check input arguments
arguments
    rModel struct
    mX (:,:) {mustBeNumeric}
    mID (:,2) {mustBeNumeric, mustBeNonnegative}
end

% Determine dimensions
[iNumPanelObs, iNumIndepVars]   = size(mX);
iNumPanelObsID                  = length(mID);

% Add constant to the independent variables
mX              = [ones(iNumPanelObs, rModel.lEstAlpha), mX];
iNumIndepVars   = iNumIndepVars + rModel.lEstAlpha;

% Check dimensions
assert(iNumPanelObs == iNumPanelObsID, 'Number of panel observations must agree (vY, mID)');
assert(iNumIndepVars == length(rModel.vBeta), 'Number of independent variables must agree (B, mX)');

% Prediction
vYhat   = mX * rModel.vBeta(:);
end