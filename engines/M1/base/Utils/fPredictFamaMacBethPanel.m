function vYhat = fPredictFamaMacBethPanel(rModel, mX, mID)
% Function for predicting values using an estimated Fama-MacBeth model
% 
% Input:
%   rModel:                 Struct, containing the settings and the 
%                           following fields:
%       .vGamma:                1 x (lEstAlpha + K) vector of average gamma
%                               coefficients
%       .mGamma:                T x (lEstAlpha + K) matrix of estimated gamma
%                               coefficients
%       .vGammaSE:              1 x (lEstAlpha + K) vector of standard
%                               errors
%       .vGammaT:               1 x (lEstAlpha + K) vector of t-statistics
%       .vGammaP:               1 x (lEstAlpha + K) vector of p-values
%       .vR2:                   T x 1 vector of R2s
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
iNumPanelObsID                  = size(mID,1);
vUniqueTimeID                   = unique(mID(:,1));
iNumObs                         = length(vUniqueTimeID);

% Add constant to the independent variables
mX = [ones(iNumPanelObs, rModel.lEstAlpha), mX];
iNumIndepVars   = iNumIndepVars + rModel.lEstAlpha;

% Check dimensions
assert(iNumPanelObs == iNumPanelObsID, 'Number of panel observations must agree (vY, mID)');
assert(iNumIndepVars == length(rModel.vGamma), 'Number of independent variables must agree (G, mX)');

% Initialize memory
vYhat   = NaN(iNumPanelObs, 1);

% Loop over time
for iIdxT = 1:iNumObs
    % Get current time step
    iIdxTime        = vUniqueTimeID(iIdxT);

    % Get data index
    lIsSampleData   = mID(:,1) == iIdxTime;
   
    % Get data
    mXtemp          = mX(lIsSampleData,:);

    % Prediction
    vYhat(lIsSampleData) = mXtemp * rModel.vGamma(:);
end
end
