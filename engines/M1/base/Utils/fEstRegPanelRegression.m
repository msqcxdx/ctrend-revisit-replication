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
%       .rStatus:       Explicit estimation status. Expected statistical
%                       non-identification is returned with a named code;
%                       toolbox, license, dimension, input, and unknown
%                       numerical exceptions are rethrown.

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
lIsNaN              = ~isfinite(vY) | any(~isfinite(mX),2);
if ~isempty(vW)
    lIsNaN          = lIsNaN | ~isfinite(vW) | vW < 0;
    vW(lIsNaN,:)    = [];
end
vY(lIsNaN)          = [];
mX(lIsNaN,:)        = [];
mID(lIsNaN,:)       = [];

% Determine dimensions
iNumPanelObs                    = length(vY);
[iNumPanelObsX, iNumIndepVars]  = size(mX);
iNumPanelObsID                  = size(mID,1);
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

% Initialize output and stop if the regularized regression cannot be
% estimated or AICc would be undefined.
iNumCoeff = iNumIndepVars + rModel.lEstAlpha;
rModel.dLambda = NaN;
rModel.dAIC = NaN;
rModel.vBeta = NaN(iNumCoeff, 1);
rModel.rStatus = iStatus("not_started", "", "");
if iNumPanelObs < 2
    rModel.rStatus = iStatus("expected_insufficient_observations", "", ...
        "Regularized regression requires at least two usable observations.");
    return
end
if iNumIndepVars == 0
    rModel.rStatus = iStatus("expected_no_predictors", "", ...
        "Regularized regression has no usable predictor columns.");
    return
end
if lValueWeightedLS && sum(vW) <= 0
    rModel.rStatus = iStatus("expected_nonpositive_weight_sum", "", ...
        "Regularized regression weights have no positive total mass.");
    return
end

% Estimate model. Do not catch arbitrary LASSO exceptions: missing
% toolboxes/licenses, illegal dimensions or inputs, and unknown numerical
% failures must fail the method/run rather than silently becoming NaNs.
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

% Find valid lambdas. FitInfo.DF counts nonzero predictor coefficients but
% excludes the separately stored intercept, so AICc must add it explicitly.
% Zero, Inf, and NaN MSE values are not admissible likelihood estimates.
vNumNonZero = sum(mParaEst ~= 0, 1);
[vAICAll, lAICDefined] = fCorrectedAICc(rFitInfo.MSE, ...
    rFitInfo.DF, iNumPanelObs, rModel.lEstAlpha);
lFiniteFit = isfinite(rFitInfo.Lambda) & ...
    isfinite(rFitInfo.Intercept) & all(isfinite(mParaEst),1);
lValid = vNumNonZero >= rModel.iMinNumNonZero & ...
    lAICDefined & lFiniteFit;
if ~any(lValid)
    rModel.rStatus = iStatus("expected_no_admissible_lambda", "", ...
        "No lambda has defined AICc and the required nonzero coefficients.");
    return
end

% Extract results
vLambda      = rFitInfo.Lambda(lValid);
vIntercept   = rFitInfo.Intercept(lValid);
mParaEst     = mParaEst(:,lValid);

% Calculate corrected AIC
vAIC = vAICAll(lValid);
assert(all(isfinite(vAIC)), ...
    'Internal error: an undefined AICc candidate passed the admissibility gate');

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
rModel.rStatus = iStatus("estimated", "", "");
end

function rStatus = iStatus(sCode, sIdentifier, sMessage)
rStatus = struct('sCode',string(sCode), ...
    'sIdentifier',string(sIdentifier), 'sMessage',string(sMessage));
end
