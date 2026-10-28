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

% Add constant to the independent variables
mX = [ones(iNumPanelObs, rModel.lEstAlpha), mX];

% Regression 
if lValueWeightedLS
    % Value-weighted least squares regression
    mXtW  = (mX .* vW)';
    if rcond((mXtW * mX)) < 1e-15
        vBeta = pinv(mXtW * mX) * (mXtW * vY);
    else
        vBeta = (mXtW * mX)\(mXtW * vY);
    end
else
    % Ordinary least squares regression
    if rcond((mX' * mX)) < 1e-15
        vBeta = pinv(mX' * mX) * (mX' * vY);  
    else
        vBeta = mX\vY;  
    end
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
    rModel.dResidVar = dSSR/(iNumPanelObs - iNumIndepVars);
    
    % Standard errors
    if lValueWeightedLS
        rModel.vBetaSE = sqrt(diag(rModel.dResidVar * inv(mXtW * mX)));
    else
        rModel.vBetaSE = sqrt(diag(rModel.dResidVar * inv(mX' * mX)));
    end
    
    % t-statistic
    rModel.vBetaT = vBeta./rModel.vBetaSE;
end
end