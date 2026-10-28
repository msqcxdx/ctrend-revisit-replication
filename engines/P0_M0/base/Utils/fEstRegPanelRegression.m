function rModel = fEstRegPanelRegression(vY, mX, mID, vW, rModel)
% Function for estimating a regularized linear regression
%
% Input:
%   vY:             (T*N)x1 vector of dependent variables
%                   T: number of time-series observations
%                   N: number of objects
%   mX:             (T*N)xK vector of independent variables
%                   T: number of time-series observations
%                   N: number of objects
%                   K: number of independent variables
%   mID:            (T*N)x2 matrix of indices
%                   1. column: time-ID
%                   2. column: object-ID
%                   T: number of time-series observations
%                   N: number of objects
%   vW:             (T*N)x1 vector of observation weights
%                   T: number of time-series observations
%                   N: number of objects
%   rModel:         Name-Value arguments:
%       .lEstAlpha:     Logical, specifies whether to estimate an intercept
%                       (true, default) or not (false)
%       .dAlpha:        Scalar, double, controls the tradeoff between lasso and
%                       ridge. dAlpha == 1 equals lasso and dAlpha close to
%                       zero is close to ridge regression
%       .lStandardize:  Logical, specifies whether to standardize data
%                       (default = false). Note that the entire panel is
%                       standardized to have zero mean and unit variance
%       .iNumLambda:    Scalar, integer, number of regularization strengths to
%                       try (default = 200)
%       .iMinNumNonZero:Scalar, integer, minimum number of nonzero coefficients
%                       (default = 0)
%
% Output:
%   rModel:         Struct, containing settings and coefficient estimates
%       .vBeta:         (K + lEstAlpha) x 1 vector of estimated
%                       coefficients
%       .dLambda:       Scalar, double, optimal lambda  
%       .dAIC:          Scalar, double, optimal AIC

% Check input arguments
arguments
    vY (:,1) {mustBeNumeric}
    mX (:,:) {mustBeNumeric}
    mID (:,2) {mustBeNumeric, mustBeNonnegative}
    vW (:,1) {mustBeNumeric} = []
    rModel.lEstAlpha (1,1) {mustBeNumericOrLogical} = true
    rModel.dAlpha (1,1) {mustBeNumeric, mustBeNonnegative} = 0.5
    rModel.lStandardize (1,1) {mustBeNumericOrLogical} = false;
    rModel.iNumLambda (1,1) {mustBeNumeric, mustBeNonnegative} = 200
    rModel.iMinNumNonZero (1,1) {mustBeNumeric, mustBeNonnegative} = 0
end

% Remove missing values
lIsNaN              = isnan(vY) | any(isnan(mX),2);
if ~isempty(vW)
    lIsNaN          = lIsNaN | isnan(vW);
    vW(lIsNaN,:)    = [];
end
vY(lIsNaN)          = [];
mX(lIsNaN,:)        = [];
mID(lIsNaN,:)       = [];

% Determine dimensions
iNumPanelObs                    = length(vY);
[iNumPanelObsX, iNumIndepVars]  = size(mX);
iNumPanelObsID                  = length(mID);
iNumPanelObsW                   = length(vW);

% Check dimensions
assert(iNumPanelObs == iNumPanelObsX, 'Number of panel observations must agree (vY, mX)');
assert(iNumPanelObs == iNumPanelObsID, 'Number of panel observations must agree (vY, mID)');
if ~isempty(vW)
    assert(iNumPanelObs == iNumPanelObsW, 'Number of panel observations must agree (vY, vW)');
    lValueWeightedLS = true;
else
    lValueWeightedLS = false;
end

% Estimate model
if lValueWeightedLS
    [mParaEst, rFitInfo] = lasso(mX, vY, ...
        'Alpha',rModel.dAlpha,...
        'NumLambda',rModel.iNumLambda,...
        'Intercept',rModel.lEstAlpha,...
        'Standardize', rModel.lStandardize,...
        'Weights', vW);
else
    [mParaEst, rFitInfo] = lasso(mX, vY, ...
        'Alpha',rModel.dAlpha,...
        'NumLambda',rModel.iNumLambda,...
        'Intercept',rModel.lEstAlpha,...
        'Standardize', rModel.lStandardize);
end

% Find valid lambdas
vNumNonZero = sum(mParaEst ~= 0, 1);
lValid      = vNumNonZero >= rModel.iMinNumNonZero;

% Extract results
vLambda      = rFitInfo.Lambda(lValid);
vMSE         = rFitInfo.MSE(lValid);
vDF          = rFitInfo.DF(lValid);
vIntercept   = rFitInfo.Intercept(lValid);
mParaEst     = mParaEst(:,lValid);

% Calculate corrected AIC
vAIC = iNumPanelObs * log(vMSE) + 2 * vDF * iNumPanelObs./(iNumPanelObs - vDF - 1);

% Find best lambda
[dAIC, iIdxMin] = min(vAIC);
dLambda         = vLambda(iIdxMin);
dIntercept      = vIntercept(iIdxMin);
vParaEst        = mParaEst(:,iIdxMin);

% Save results
rModel.dLambda  = dLambda;
rModel.dAIC     = dAIC;
if rModel.lEstAlpha
    rModel.vBeta    = [dIntercept; vParaEst];
else
    rModel.vBeta    = vParaEst;
end
end