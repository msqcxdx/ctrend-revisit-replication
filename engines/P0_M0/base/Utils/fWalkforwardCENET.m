function [vYhat, cModels, vYhatWts] = fWalkforwardCENET(vY, mX, mID, vW, rModel)
% Function for estimate the C-ENet using a rolling estimation window
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
%       'dAlpha':           Scalar, double, controls the trade-off between
%                           L1 and L2 regularization (default = 0.5)
%       'iNumIn':           Scalar, integer, number of in-sample periods
%                           (default = 1)
%       'iNumOut':          Scalar, integer, number of out-of-sample periods
%                           (default = 1)
%       'lRoll':            Logical, specifies whether to use a
%                           fixed-length (true, default) or expanding 
%                           estimation window
%       'lDisplay':         Logical, specifies whether to print progress on
%                           console (default = true)
%       'dFracVal':         Scalar, double, specifies the fraction of the
%                           alidation window (default = 0 = no validation
%                           sample)
%       'lReest':           Logical, specifies whether to re-estimate the
%                           parameters after forecast selection using 
%                           validation sample (default = false)
%
% Output:
%   vYhat:      (T * N) x 1 vector of OOS estimates for the dependent variable
%               T: number of time-series observations
%               N: number of objects
%   cModels:    M x 1 cell-array, fitted models
%               M: number of iterations
%   vYhatWts:   (T * N) x 1 vector of OOS estimates for the dependent
%               variable, where the forecasts are weighted using the
%               estimated theta coefficients, obtained from E-Net
%               T: number of time-series observations
%               N: number of objects

% Check input arguments
arguments
    vY (:,1) {mustBeNumeric}
    mX (:,:) {mustBeNumeric}
    mID (:,2) {mustBeNumeric, mustBeNonnegative}
    vW (:,1) {mustBeNumeric} = []

    % Model settings
    rModel.lEstAlpha (1,1) {mustBeNumericOrLogical} = true
    rModel.iMinNumObsReg (1,1) {mustBeNumeric, mustBeNonnegative} = 10
    rModel.dAlpha (1,1) {mustBeNumeric, mustBeNonnegative} = 0.5

    % Estimation settings
    rModel.iNumIn (1,1) {mustBeNumeric, mustBeNonnegative} = 1
    rModel.iNumOut (1,1) {mustBeNumeric, mustBeNonnegative} = 1
    rModel.lRoll (1,1) {mustBeNumericOrLogical} = true
    rModel.lDisplay (1,1) {mustBeNumericOrLogical} = true
    rModel.dFracVal (1,1) {mustBeNumeric, mustBeNonnegative} = 0
    rModel.lReest (1,1) {mustBeNumericOrLogical, mustBeNonnegative} = false
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
cYhat       = cell(iNumIter, 1); % Equally weighted
cYhatWts    = cell(iNumIter, 1); % theta-weighted
cModels = cell(iNumIter, 1);
parfor iIdxI = 1:iNumIter
    % Get in- and out-of-sample indices. The time indices in vUniqueTimeID
    % can take any arbitrary value, for example, dates in the format
    % yyyymmdd. The indices in cTimeIdxIn and cTimeIdxOut refer to the
    % index of these time indices, e.g., 1:T. We now get the indices that
    % match the mID and vUniqueTimeID variable. 
    vIdxInSample    = vUniqueTimeID(cTimeIdxIn{iIdxI});
    vIdxOutOfSample = vUniqueTimeID(cTimeIdxOut{iIdxI});   

    % Further split into training and validation set
    if rModel.dFracVal > 0
        % Get number of validation time steps
        if floor(rModel.dFracVal) == rModel.dFracVal
            iNumObsTrain = rModel.dFracVal;
        else
            iNumObsTrain = fix(length(vIdxInSample) * (1 - rModel.dFracVal));
        end

        % Split into training and validation (preserve temporal order)
        vIdxTrain  = vIdxInSample(1:iNumObsTrain);
        vIdxTest   = vIdxInSample(iNumObsTrain+1:end);
    else
        % Training and testing sample are the same
        vIdxTrain = vIdxInSample;
        vIdxTest  = vIdxInSample;
    end

    % Get panel indices
    lIsDataTrain   = ismember(mID(:,1), vIdxTrain);
    lIsDataTest    = ismember(mID(:,1), vIdxTest);
    lIsDataOut     = ismember(mID(:,1), vIdxOutOfSample);

    % Get data
    vYtrain    = vY(lIsDataTrain);
    mXtrain    = mX(lIsDataTrain,:);
    vYtest     = vY(lIsDataTest);
    mXtest     = mX(lIsDataTest,:);
    mXout      = mX(lIsDataOut,:);
    mIDtrain   = mID(lIsDataTrain, :);
    mIDtest    = mID(lIsDataTest, :);
    mIDout     = mID(lIsDataOut, :);
    if ~isempty(vW)
        vWtrain    = vW(lIsDataTrain);
        vWtest     = vW(lIsDataTest);
    else
        vWtrain    = [];
        vWtest     = [];
    end

    % Determine dimension
    [iNumObsTemp, iNumIndepVars]    = size(mXout);
    iNumObsTest                     = size(mXtest,1);
    mYhatTest                       = NaN(iNumObsTest, iNumIndepVars);
    mYhatTemp                       = NaN(iNumObsTemp, iNumIndepVars);

    % Loop over independent variables
    for iIdxV = 1:iNumIndepVars    
        % Estimate in-sample
        rModelPOLS = fEstPanelRegression(vYtrain, mXtrain(:,iIdxV), ...
            mIDtrain, vWtrain, 'lEstAlpha', rModel.lEstAlpha);

        % In-sample estimate
        mYhatTest(:,iIdxV) = fPredictPanelRegression(rModelPOLS, mXtest(:,iIdxV), mIDtest);

        % If there is a validation sample, re-estimate betas based on full sample
        if rModel.dFracVal > 0 && rModel.lReest
            rModelPOLS = fEstPanelRegression([vYtrain; vYtest], [mXtrain(:,iIdxV); mXtest(:,iIdxV)],...
                [mIDtrain; mIDtest], [vWtrain; vWtest], 'lEstAlpha', rModel.lEstAlpha);
        end
  
        % Out-of-sample prediction
        mYhatTemp(:,iIdxV) = fPredictPanelRegression(rModelPOLS, mXout(:,iIdxV), mIDout);
    end

    % Let elastic net select predictions
    rModelENet = fEstRegPanelRegression(vYtest, mYhatTest, mIDtest, vWtest, 'lEstAlpha',...
        rModel.lEstAlpha, 'dAlpha', rModel.dAlpha,'lStandardize',true);

    % Only keep predictions with positive nonzero coefficient
    vBeta      = rModelENet.vBeta(end-iNumIndepVars+1:end);
    lKeepPred  = vBeta > 0;

    % Average
    vYhatTemp  = mean(mYhatTemp(:,lKeepPred), 2, 'omitnan');

    % Get theta-weighted
    vYhatTempWts = mYhatTemp(:,lKeepPred) * vBeta(lKeepPred);

    % Save prediction
    cYhat{iIdxI}        = vYhatTemp;
    cYhatWts{iIdxI}     = vYhatTempWts;
    cModels{iIdxI}      = rModelPOLS;
end

% To panel
vYhat       = NaN(iNumPanelObs,1);
vYhatWts    = NaN(iNumPanelObs,1);
for iIdxI = 1:iNumIter
    vIdxOutOfSample = vUniqueTimeID(cTimeIdxOut{iIdxI});   
    lIsDataOut  = ismember(mID(:,1), vIdxOutOfSample);
    vYhat(lIsDataOut) = cYhat{iIdxI};
    vYhatWts(lIsDataOut) = cYhatWts{iIdxI};
end
end
