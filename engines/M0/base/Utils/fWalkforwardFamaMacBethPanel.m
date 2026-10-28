function [vYhat, cModels] = fWalkforwardFamaMacBethPanel(vY, mX, mID, vW, rModel)
% Function for estimating a Fama-MacBeth regression using a
% rolling/expanding time window
%
% Input:
%   vY:         (T * N) x 1 vector of the dependent variable
%               T: number of time-series observations
%               N: number of objects
%   mX:         (T * N) x K matrix of the independent variables
%               T: number of time-series observations
%               N: number of objects
%               K: number of independent variables
%   mID:        (T * N) x 2 matrix. First column indicates the time ID and
%               second column refers to the object ID
%               T: number of time-series observations
%               N: number of objects
%   vW:         (T * N) x 1 vector of observation weights
%               T: number of time-series observations
%               N: number of objects
%   rModel:     Name-Value pair arguments
%       'lEstAlpha':        Logical, specifies whether to estimate an
%                           intercept (default = true)
%       'iMinNumObsReg':    Scalar, integer, minimum number of observations
%                           for Fama-MacBeth regression (default = 5)
%       'lGammaOnly':       Logical, specifies whether to estimate only the
%                           slopes without and inference statistics
%                           (default = true)
%       'iNumLagsNW':       Scalar, integer, number of lags for Newey-West standard
%                           error correction (default = 12)
%       'iNumIn':           Scalar, integer, number of in-sample
%                           observations (default = 1)
%       'iNumOut':          Scalar, integer, number of out-of-sample
%                           observations (default = 1)
%       'lRoll':            Logical, indicates whether to use a 
%                           fixed (true, default) or expanding (false) time 
%                           window
%       'lDisplay':         Logical, indicates whether to display the
%                           progress on the console (default = true)
%
% Output:
%   vYhat:      (T * N) x 1 vector of estimates for the dependent variable
%               T: number of time-series observations
%               N: number of objects
%   cModels:    M x 1 cell-array, fitted models for each iteration
%               M: number of iterations

% Check input arguments
arguments
    vY (:,1) {mustBeNumeric}
    mX (:,:) {mustBeNumeric}
    mID (:,2) {mustBeNumeric, mustBeNonnegative}
    vW (:,1) {mustBeNumeric} = []

    % Model settings
    rModel.lEstAlpha (1,1) {mustBeNumericOrLogical} = true
    rModel.iMinNumObsReg (1,1) {mustBeNumeric, mustBeNonnegative} = 5
    rModel.lGammaOnly (1,1) {mustBeNumericOrLogical, mustBeNonnegative} = true
    rModel.iNumLagsNW (1,1) {mustBeNumeric, mustBeNonnegative} = 12

    % Estimation settings
    rModel.iNumIn (1,1) {mustBeNumeric, mustBeNonnegative} = 1
    rModel.iNumOut (1,1) {mustBeNumeric, mustBeNonnegative} = 1
    rModel.lRoll (1,1) {mustBeNumericOrLogical} = true
    rModel.lDisplay (1,1) {mustBeNumericOrLogical} = true
end

% Determine dimensions
iNumPanelObs                    = length(vY);
[iNumPanelObsX, iNumIndepVars]  = size(mX);
iNumPanelObsID                  = length(mID);
iNumPanelObsW                   = length(vW);
vUniqueTimeID                   = unique(mID(:,1));
iNumObs                         = length(vUniqueTimeID);

% Check dimensions
assert(iNumPanelObs == iNumPanelObsX, 'Number of panel observations must agree');
assert(iNumPanelObs == iNumPanelObsID, 'Number of panel observations must agree');
if ~isempty(vW)
    assert(iNumPanelObs == iNumPanelObsW, 'Number of panel observations must agree');
end

% Create in-sample and out-of-sample indices for each iteration
cTimeIdxIn  = cell(0);           % In-sample indices for each iteration
cTimeIdxOut = cell(0);           % Out-of-sample indices for each iteration
iNumIter    = 0;                 % Number of iterations
for iIdxT = rModel.iNumIn:rModel.iNumOut:iNumObs-1
    % Increase number of iterations
    iNumIter = iNumIter + 1;

    % Create in-sample and out-of-sample indices
    [cTimeIdxIn{iNumIter,1},cTimeIdxOut{iNumIter,1}] = ...
        fCreateIndices(iNumObs,iIdxT,rModel.iNumIn,rModel.iNumOut,rModel.lRoll,...
        false,false);
end

%% Loop over time
% Initialize memory
cYhat   = cell(iNumIter, 1);
cModels = cell(iNumIter, 1);
parfor iIdxI = 1:iNumIter
    % Get in- and out-of-sample indices. The time indices in vUniqueTimeID
    % can take any arbitrary value, for example, dates in the format
    % yyyymmdd. The indices in cTimeIdxIn and cTimeIdxOut refer to the
    % index of these time indices, e.g., 1:T. We now get the indices that
    % match the mID and vUniqueTimeID variable. 
    vIdxInSample    = vUniqueTimeID(cTimeIdxIn{iIdxI});
    vIdxOutOfSample = vUniqueTimeID(cTimeIdxOut{iIdxI});   

    % Get panel indices
    lIsDataIn   = ismember(mID(:,1), vIdxInSample);
    lIsDataOut  = ismember(mID(:,1), vIdxOutOfSample);

    % Get data
    vYin        = vY(lIsDataIn);
    mXin        = mX(lIsDataIn,:);
    mXout       = mX(lIsDataOut,:);
    mIDin       = mID(lIsDataIn, :);
    mIDout      = mID(lIsDataOut, :);
    if ~isempty(vW)
        vWin    = vW(lIsDataIn);
    else
        vWin    = [];
    end

    % Estimate in-sample
    warning('off');
    rModelEst = fEstFamaMacBethPanel(vYin, mXin, mIDin, vWin, ...
        'lEstAlpha', rModel.lEstAlpha,...
        'iMinNumObsReg', rModel.iMinNumObsReg,...
        'lGammaOnly',rModel.lGammaOnly,...
        'iNumLagsNW',rModel.iNumLagsNW);
    warning('on');

    % Prediction
    vYhat = fPredictFamaMacBethPanel(rModelEst, mXout, mIDout);

    % Save prediction
    cYhat{iIdxI}    = vYhat;
    cModels{iIdxI}  = rModelEst;
end

% To panel
vYhat = NaN(iNumPanelObs,1);
for iIdxI = 1:iNumIter
    vIdxOutOfSample = vUniqueTimeID(cTimeIdxOut{iIdxI});   
    lIsDataOut  = ismember(mID(:,1), vIdxOutOfSample);
    vYhat(lIsDataOut) = cYhat{iIdxI};
end
end


