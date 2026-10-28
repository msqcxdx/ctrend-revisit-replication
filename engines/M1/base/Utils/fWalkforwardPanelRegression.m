function [vYhat, cModels, vYoutPnl, vYoutLabel] = ...
    fWalkforwardPanelRegression(vY, mX, mID, vW, rModel)
% Function for estimating a pooled regression using a
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
%                           for Fama-MacBeth regression (default = 10)
%       'iNumIn':           Scalar, integer, number of in-sample
%                           observations (default = 1)
%       'iNumOut':          Scalar, integer, number of out-of-sample
%                           observations (default = 1)
%       'lRoll':            Logical, indicates whether to use a 
%                           fixed (true, default) or expanding (false) time 
%                           window
%       'vAllTimeID':       Required complete ordered time axis; preserves
%                           calendar weeks with zero usable panel rows.
%       'lUseParallel':     Logical, use PARFOR (true, default) or a serial
%                           FOR loop (false). Both routes return identical
%                           full-length outputs.
%
% Output:
%   vYhat:      (T * N) x 1 vector of estimates for the dependent variable
%               T: number of time-series observations
%               N: number of objects
%   cModels:    M x 1 cell-array, fitted models for each iteration
%               M: number of iterations
%   vYoutPnl:   Raw realized OOS economic returns.
%   vYoutLabel: Raw strict OOS statistical labels. Only already-realized
%               historical weeks are outlier-cleaned.

% Check input arguments
arguments
    vY (:,1) {mustBeNumeric}
    mX (:,:) {mustBeNumeric}
    mID (:,2) {mustBeNumeric, mustBeNonnegative}
    vW (:,1) {mustBeNumeric} = []

    % Model settings
    rModel.lEstAlpha (1,1) {mustBeNumericOrLogical} = true
    rModel.iMinNumObsReg (1,1) {mustBeNumeric, mustBeNonnegative} = 10

    % Estimation settings
    rModel.iNumIn (1,1) {mustBeNumeric, mustBeNonnegative} = 1
    rModel.iNumOut (1,1) {mustBeNumeric, mustBeNonnegative} = 1
    rModel.lRoll (1,1) {mustBeNumericOrLogical} = true
    rModel.vAllTimeID (:,1) {mustBeNumeric, mustBeNonnegative} = []
    rModel.sOutlierTreatment char = 'none'
    rModel.dOutlierThreshold (1,1) {mustBeNumeric, mustBeNonnegative} = 0
    rModel.lDemeanY (1,1) {mustBeNumericOrLogical} = false
    rModel.vEvaluationY (:,1) {mustBeNumeric} = []
    rModel.vOutlierFitY (:,1) {mustBeNumeric} = []
    rModel.mOutlierFitID (:,2) {mustBeNumeric, mustBeNonnegative} = []
    rModel.lUseParallel (1,1) {mustBeNumericOrLogical} = true
end

% Determine dimensions
iNumPanelObs                    = length(vY);
iNumPanelObsX                   = size(mX,1);
iNumPanelObsID                  = size(mID,1);
iNumPanelObsW                   = length(vW);
assert(~isempty(rModel.vAllTimeID), ...
    ['Corrected walk-forward estimation requires the complete calendar in ' ...
     'vAllTimeID; inferring it from observed panel rows can delete empty weeks']);
vUniqueTimeID = rModel.vAllTimeID(:);
assert(numel(unique(vUniqueTimeID)) == numel(vUniqueTimeID) && ...
    all(diff(vUniqueTimeID) > 0), ...
    'vAllTimeID must contain unique, strictly increasing time IDs');
assert(all(ismember(mID(:,1), vUniqueTimeID)), ...
    'Every panel time ID must occur in vAllTimeID');
iNumObs = length(vUniqueTimeID);

% Check dimensions
assert(iNumPanelObs == iNumPanelObsX, 'Number of panel observations must agree');
assert(iNumPanelObs == iNumPanelObsID, 'Number of panel observations must agree');
if ~isempty(vW)
    assert(iNumPanelObs == iNumPanelObsW, 'Number of panel observations must agree');
end
if isempty(rModel.vEvaluationY)
    vEvaluationY = vY;
else
    assert(numel(rModel.vEvaluationY) == iNumPanelObs, ...
        'Evaluation outcomes must match the panel length');
    vEvaluationY = rModel.vEvaluationY;
end
assert(numel(rModel.vOutlierFitY) == size(rModel.mOutlierFitID,1), ...
    'Outlier-fit outcomes and IDs must have equal length');
assert(isempty(rModel.mOutlierFitID) || ...
    all(ismember(rModel.mOutlierFitID(:,1),vUniqueTimeID)), ...
    'Every outlier-fit time ID must occur in vAllTimeID');

% Create in-sample and out-of-sample indices for each iteration
cTimeIdxIn  = cell(0);           % In-sample indices for each iteration
cTimeIdxOut = cell(0);          % Out-of-sample indices for each iteration
iNumIter = 0;                   % Number of iterations
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
cYhat      = cell(iNumIter, 1);
cModels    = cell(iNumIter, 1);
cYoutPnl   = cell(iNumIter, 1);
cYoutLabel = cell(iNumIter, 1);
if rModel.lUseParallel
    parfor iIdxI = 1:iNumIter
        [cYhat{iIdxI}, cModels{iIdxI}, cYoutPnl{iIdxI}, ...
            cYoutLabel{iIdxI}] = ...
            iEstimateIteration(iIdxI, cTimeIdxIn, cTimeIdxOut, ...
            vUniqueTimeID, vY, mX, mID, vW, vEvaluationY, rModel);
    end
else
    for iIdxI = 1:iNumIter
        [cYhat{iIdxI}, cModels{iIdxI}, cYoutPnl{iIdxI}, ...
            cYoutLabel{iIdxI}] = ...
            iEstimateIteration(iIdxI, cTimeIdxIn, cTimeIdxOut, ...
            vUniqueTimeID, vY, mX, mID, vW, vEvaluationY, rModel);
    end
end

% To panel
vYhat = NaN(iNumPanelObs,1);
vYoutPnl = NaN(iNumPanelObs,1);
vYoutLabel = NaN(iNumPanelObs,1);
for iIdxI = 1:iNumIter
    vIdxOutOfSample = vUniqueTimeID(cTimeIdxOut{iIdxI});   
    lIsDataOut  = ismember(mID(:,1), vIdxOutOfSample);
    vYhat(lIsDataOut) = cYhat{iIdxI};
    vYoutPnl(lIsDataOut) = cYoutPnl{iIdxI};
    vYoutLabel(lIsDataOut) = cYoutLabel{iIdxI};
end
end

function [vYhat, rModelPOLS, vYoutPnl, vYoutLabel] = iEstimateIteration( ...
        iIdxI, cTimeIdxIn, cTimeIdxOut, vUniqueTimeID, ...
        vY, mX, mID, vW, vEvaluationY, rModel)
% Estimate one calendar walk-forward iteration. Keeping this body in one
% function guarantees that the serial and parallel routes are identical.
vIdxInSample    = vUniqueTimeID(cTimeIdxIn{iIdxI});
vIdxOutOfSample = vUniqueTimeID(cTimeIdxOut{iIdxI});
assert(isempty(vIdxInSample) || isempty(vIdxOutOfSample) || ...
    max(vIdxInSample) < min(vIdxOutOfSample), ...
    'Outlier training dates must strictly precede OOS dates');

lIsDataIn  = ismember(mID(:,1), vIdxInSample);
lIsDataOut = ismember(mID(:,1), vIdxOutOfSample);
vYinRaw = vY(lIsDataIn);
vYoutRaw = vY(lIsDataOut);
vYoutEvaluationRaw = vEvaluationY(lIsDataOut);
mIDin = mID(lIsDataIn,:);
mIDout = mID(lIsDataOut,:);
if isempty(rModel.vOutlierFitY)
    vYfitRaw = vYinRaw;
    mIDfitRaw = mIDin;
else
    lFit = ismember(rModel.mOutlierFitID(:,1),vIdxInSample);
    vYfitRaw = rModel.vOutlierFitY(lFit);
    mIDfitRaw = rModel.mOutlierFitID(lFit,:);
end
mXin = mX(lIsDataIn,:);
mXout = mX(lIsDataOut,:);
if isempty(vW)
    vWin = [];
else
    vWin = vW(lIsDataIn);
end

[vYin, ~, ~, vYoutPnl, ~, vYoutLabel] = fPrepareWalkforwardOutcomes( ...
    vYinRaw, zeros(0,1), vYoutRaw, mIDin, zeros(0,2), mIDout, ...
    rModel.sOutlierTreatment, rModel.dOutlierThreshold, ...
    rModel.lDemeanY, vYoutEvaluationRaw, vYfitRaw,mIDfitRaw);
lValidIn = isfinite(vYin) & all(isfinite(mXin),2);
if ~isempty(vWin)
    lValidIn = lValidIn & isfinite(vWin);
end
vYin = vYin(lValidIn);
mXin = mXin(lValidIn,:);
mIDin = mIDin(lValidIn,:);
if ~isempty(vWin)
    vWin = fNormalizePanelWeights(vWin(lValidIn), mIDin);
end
iNumCoeff = size(mXin,2) + logical(rModel.lEstAlpha);
if numel(vYin) < max(rModel.iMinNumObsReg, iNumCoeff)
    vYhat = NaN(sum(lIsDataOut),1);
    rModelPOLS = struct();
    return
end

rWarningState = warning;
warningCleanup = onCleanup(@() warning(rWarningState));
warning('off');
rModelPOLS = fEstPanelRegression(vYin, mXin, mIDin, vWin, ...
    'lEstAlpha', rModel.lEstAlpha);
clear warningCleanup

vYhat = fPredictPanelRegression(rModelPOLS, mXout, mIDout);
end
