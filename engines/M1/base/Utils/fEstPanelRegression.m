function rModel = fEstPanelRegression(vY, mX, mID, vW, rModel)
% Function for estimating a panel regression
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
%       'lEstAlpha':    Logical, specifies whether to estimate an intercept
%                       (true, default) or not (false)
%       'lGetStats':    Logical, specifies whether to calculate additional
%                       statistics such as standard errors and t-statistics
%                       (default = false)
%
% Output:
%   rModel:         Struct, containing model setting and additional fields:
%       .vBeta:         (K + lEstAlpha) x 1 vector of estimated coefficients
%       .vBetaSE:       (K + lEstAlpha) x 1 vector of standard errors
%       .vBetaT:        (K + lEstAlpha) x 1 vector of t-statistics
%       .dResidVar:     Scalar, double, residual variance

% Check input arguments
arguments
    vY (:,1) {mustBeNumeric}
    mX (:,:) {mustBeNumeric}
    mID (:,2) {mustBeNumeric, mustBeNonnegative}
    vW (:,1) {mustBeNumeric} = []
    rModel.lEstAlpha (1,1) {mustBeNumericOrLogical} = true
    rModel.lGetStats (1,1) {mustBeNumericOrLogical} = false
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

% Initialize output and stop if the regression is not identified.
iNumCoeff = iNumIndepVars + rModel.lEstAlpha;
rModel.vBeta = NaN(iNumCoeff, 1);
if rModel.lGetStats
    rModel.dResidVar = NaN;
    rModel.vBetaSE = NaN(iNumCoeff, 1);
    rModel.vBetaT = NaN(iNumCoeff, 1);
end
if iNumPanelObs < iNumCoeff || (lValueWeightedLS && sum(vW) <= 0)
    return
end

% Add constant to the independent variables
mX = [ones(iNumPanelObs, rModel.lEstAlpha), mX];
iNumCoeff = size(mX, 2);

% Regression. Normalize columns before the identification check and solve,
% so coefficients remain invariant to economic units (notably raw market
% capitalization) and one numerical tolerance governs both operations.
if lValueWeightedLS
    mXsolve = mX .* sqrt(vW);
    vYsolve = vY .* sqrt(vW);
else
    mXsolve = mX;
    vYsolve = vY;
end
[vBeta,lIdentified,mInvXX] = ...
    fSolveFullRankLeastSquares(mXsolve,vYsolve);
if ~lIdentified
    return
end

% Save results
rModel.vBeta = vBeta;

if rModel.lGetStats
    % Fitted values
    vYhat = mX * vBeta;
    
    % Residuals
    vResid  = vY - vYhat;
    if lValueWeightedLS
        dSSR    = sum(vW .* (vResid.^2),1,'omitmissing');
    else
        dSSR    = vResid' * vResid;
    end

    % Residual variance
    dDof = iNumPanelObs - iNumCoeff;
    if dDof <= 0
        return
    end
    rModel.dResidVar = dSSR/dDof;
    
    % Standard errors use the inverse cross-product returned by the same
    % scale-invariant solve. For WLS, mXsolve already contains sqrt(weights).
    rModel.vBetaSE = sqrt(diag(rModel.dResidVar * mInvXX));
    
    % t-statistic
    rModel.vBetaT = vBeta./rModel.vBetaSE;
end
end
