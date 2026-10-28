function [vYhat, cModels, vYhatWts, vYoutPnl, vYoutLabel, ...
        rForecastAudit] = ...
    fWalkforwardCENET(vY, mX, mID, vW, rModel)
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
%       'vAllTimeID':       Required complete ordered time axis; preserves
%                           calendar weeks with zero usable panel rows.
%       'iNumVal':          Nonnegative integer, fixed number of most-recent
%                           in-sample weeks reserved for forecast selection
%                           (default = 0 = no validation sample)
%       'lReest':           Logical, specifies whether to re-estimate the
%                           parameters after forecast selection using 
%                           validation sample (default = false)
%       'iMaxNumWorkers':   Nonnegative maximum number of workers used by
%                           the outer parfor loop. Inf preserves the
%                           production default; 0 executes serially
%                           (default = Inf).
%
% Output:
%   vYhat:      (T * N) x 1 vector of OOS estimates for the dependent variable
%               T: number of time-series observations
%               N: number of objects
%   vYoutPnl:   Raw realized OOS economic returns.
%   vYoutLabel: Raw strict OOS statistical labels.  Only already-realized
%               historical weeks are outlier-cleaned.
%   cModels:    M x 1 cell-array, fitted models
%               M: number of iterations
%   vYhatWts:   (T * N) x 1 vector of OOS estimates for the dependent
%               variable, where the forecasts are weighted using the
%               estimated theta coefficients, obtained from E-Net
%               T: number of time-series observations
%               N: number of objects
%   rForecastAudit:
%               Per-window selection status and ex-ante expected panel
%               support used by b09's completeness audit.

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
    rModel.vAllTimeID (:,1) {mustBeNumeric, mustBeNonnegative} = []
    rModel.iNumVal (1,1) {mustBeNumeric, mustBeNonnegative, mustBeInteger} = 0
    rModel.lReest (1,1) {mustBeNumericOrLogical, mustBeNonnegative} = false
    rModel.sOutlierTreatment char = 'none'
    rModel.dOutlierThreshold (1,1) {mustBeNumeric, mustBeNonnegative} = 0
    rModel.lDemeanY (1,1) {mustBeNumericOrLogical} = false
    rModel.vEvaluationY (:,1) {mustBeNumeric} = []
    rModel.vOutlierFitY (:,1) {mustBeNumeric} = []
    rModel.mOutlierFitID (:,2) {mustBeNumeric, mustBeNonnegative} = []
    rModel.iMaxNumWorkers (1,1) {mustBeNumeric, mustBeNonnegative} = Inf
end

% Determine dimensions
iNumPanelObs                    = length(vY);
[iNumPanelObsX, iNumIndepVars]  = size(mX);
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
cYhat       = cell(iNumIter, 1); % Equally weighted
cYhatWts    = cell(iNumIter, 1); % theta-weighted
cYoutPnl    = cell(iNumIter, 1); % Raw realized OOS economic return
    cYoutLabel  = cell(iNumIter, 1); % Raw strict OOS statistical label
cModels = cell(iNumIter, 1);
cExpectedOut = cell(iNumIter,1);
cSelectedOut = cell(iNumIter,1);
parfor (iIdxI = 1:iNumIter, rModel.iMaxNumWorkers)
    % Get in- and out-of-sample indices. The time indices in vUniqueTimeID
    % can take any arbitrary value, for example, dates in the format
    % yyyymmdd. The indices in cTimeIdxIn and cTimeIdxOut refer to the
    % index of these time indices, e.g., 1:T. We now get the indices that
    % match the mID and vUniqueTimeID variable. 
    vIdxInSample    = vUniqueTimeID(cTimeIdxIn{iIdxI});
    vIdxOutOfSample = vUniqueTimeID(cTimeIdxOut{iIdxI});   

    % Reserve exactly the most recent iNumVal weeks for forecast selection.
    [vIdxTrain, vIdxTest] = ...
        fSplitTrainValidation(vIdxInSample(:), rModel.iNumVal);
    assert(isempty(vIdxTrain) || isempty(vIdxOutOfSample) || ...
        max(vIdxTrain) < min(vIdxOutOfSample), ...
        'Outlier training dates must strictly precede OOS dates');
    if rModel.iNumVal > 0
        assert(numel(vIdxTest) == rModel.iNumVal && ...
            max(vIdxTrain) < min(vIdxTest) && ...
            max(vIdxTest) < min(vIdxOutOfSample), ...
            'Validation dates must lie strictly between train and OOS dates');
    end

    % Get panel indices
    lIsDataTrain   = ismember(mID(:,1), vIdxTrain);
    lIsDataTest    = ismember(mID(:,1), vIdxTest);
    lIsDataOut     = ismember(mID(:,1), vIdxOutOfSample);

    % Get data
    vYtrainRaw = vY(lIsDataTrain);
    mXtrain    = mX(lIsDataTrain,:);
    vYtestRaw  = vY(lIsDataTest);
    vYoutRaw   = vY(lIsDataOut);
    vYoutEvaluationRaw = vEvaluationY(lIsDataOut);
    mIDtrain   = mID(lIsDataTrain, :);
    mIDtest    = mID(lIsDataTest, :);
    mIDout     = mID(lIsDataOut, :);
    if isempty(rModel.vOutlierFitY)
        vYfitRaw = [vYtrainRaw;vYtestRaw];
        mIDfitRaw = [mIDtrain;mIDtest];
    else
        lFit = ismember(rModel.mOutlierFitID(:,1), ...
            [vIdxTrain(:);vIdxTest(:)]);
        vYfitRaw = rModel.vOutlierFitY(lFit);
        mIDfitRaw = rModel.mOutlierFitID(lFit,:);
    end
    mXtest     = mX(lIsDataTest,:);
    mXout      = mX(lIsDataOut,:);
    if ~isempty(vW)
        vWtrain    = vW(lIsDataTrain);
        vWtest     = vW(lIsDataTest);
    else
        vWtrain    = [];
        vWtest     = [];
    end

    [vYtrain, vYtest, ~, vYoutPnlTemp, ~, vYoutLabelTemp] = ...
        fPrepareWalkforwardOutcomes(vYtrainRaw, vYtestRaw, vYoutRaw, ...
        mIDtrain, mIDtest, mIDout, rModel.sOutlierTreatment, ...
        rModel.dOutlierThreshold, rModel.lDemeanY, vYoutEvaluationRaw, ...
        vYfitRaw,mIDfitRaw);
    cYoutPnl{iIdxI} = vYoutPnlTemp;
    cYoutLabel{iIdxI} = vYoutLabelTemp;

    % Determine dimension
    [iNumObsTemp, iNumIndepVars]    = size(mXout);
    iNumObsTest                     = size(mXtest,1);
    mYhatTest                       = NaN(iNumObsTest, iNumIndepVars);
    mYhatTemp                       = NaN(iNumObsTemp, iNumIndepVars);

    % Loop over independent variables
    for iIdxV = 1:iNumIndepVars
        % Equation (7) is a separate univariate model for predictor j.
        % Estimate it on predictor j's own finite X/Y/W support.
        lValidTrainJ = isfinite(vYtrain) & ...
            isfinite(mXtrain(:,iIdxV));
        if ~isempty(vWtrain)
            lValidTrainJ = lValidTrainJ & isfinite(vWtrain);
            vWtrainJ = fNormalizePanelWeights( ...
                vWtrain(lValidTrainJ), mIDtrain(lValidTrainJ,:));
        else
            vWtrainJ = [];
        end
        vYtrainJ = vYtrain(lValidTrainJ);
        mXtrainJ = mXtrain(lValidTrainJ,iIdxV);
        mIDtrainJ = mIDtrain(lValidTrainJ,:);
        if isempty(vYtrainJ)
            continue
        end

        % Estimate in-sample.
        rModelPOLS = fEstPanelRegression(vYtrainJ, mXtrainJ, ...
            mIDtrainJ, vWtrainJ, 'lEstAlpha', rModel.lEstAlpha);

        % In-sample estimate
        mYhatTest(:,iIdxV) = fPredictPanelRegression(rModelPOLS, mXtest(:,iIdxV), mIDtest);

        % If there is a validation sample, re-estimate betas based on full sample
        if rModel.iNumVal > 0 && rModel.lReest
            lValidReest = isfinite(vYtest) & isfinite(mXtest(:,iIdxV));
            if ~isempty(vWtest)
                lValidReest = lValidReest & isfinite(vWtest);
                % Start from raw weights and normalize again on predictor
                % j's combined estimation support.
                vWreest = [vWtrain(lValidTrainJ); ...
                    vWtest(lValidReest)];
                vWreest = fNormalizePanelWeights(vWreest, ...
                    [mIDtrainJ; mIDtest(lValidReest,:)]);
            else
                vWreest = [];
            end
            rModelPOLS = fEstPanelRegression( ...
                [vYtrainJ; vYtest(lValidReest)], ...
                [mXtrainJ; mXtest(lValidReest,iIdxV)], ...
                [mIDtrainJ; mIDtest(lValidReest,:)], vWreest, ...
                'lEstAlpha', rModel.lEstAlpha);
        end
  
        % Out-of-sample prediction
        mYhatTemp(:,iIdxV) = fPredictPanelRegression(rModelPOLS, mXout(:,iIdxV), mIDout);
    end

    % Let elastic net select predictions
    lValidTest = isfinite(vYtest) & all(isfinite(mYhatTest),2);
    if ~isempty(vWtest)
        lValidTest = lValidTest & isfinite(vWtest);
    end
    vWtestUse = vWtest;
    if ~isempty(vWtestUse)
        vWtestUse = vWtestUse(lValidTest);
        vWtestUse = fNormalizePanelWeights(vWtestUse, ...
            mIDtest(lValidTest,:));
    end
    lPotentialOut = any(isfinite(mXout),2);
    if any(lValidTest)
        rModelENet = fEstRegPanelRegression(vYtest(lValidTest), mYhatTest(lValidTest,:), mIDtest(lValidTest,:), vWtestUse, 'lEstAlpha',...
            rModel.lEstAlpha, 'dAlpha', rModel.dAlpha,'lStandardize',true);

        if rModelENet.rStatus.sCode == "estimated"
            % Only keep predictions with positive nonzero coefficient.
            vBeta = rModelENet.vBeta(end-iNumIndepVars+1:end);
            lKeepPred = vBeta > 0;
            vYhatTemp = fMeanForecastsFixedSet( ...
                mYhatTemp(:,lKeepPred));
            if any(lKeepPred)
                lExpectedOut = all(isfinite(mXout(:,lKeepPred)),2);
                vBetaKeep = vBeta(lKeepPred);
                if rModel.lEstAlpha
                    dIntercept = rModelENet.vBeta(1);
                else
                    dIntercept = 0;
                end
                vYhatTempWts = dIntercept + ...
                    mYhatTemp(:,lKeepPred) * vBetaKeep;
            else
                lExpectedOut = lPotentialOut;
                vYhatTempWts = NaN(iNumObsTemp,1);
            end
        else
            lKeepPred = false(1,iNumIndepVars);
            lExpectedOut = lPotentialOut;
            vYhatTemp = NaN(iNumObsTemp,1);
            vYhatTempWts = NaN(iNumObsTemp,1);
        end
    else
        lKeepPred = false(1,iNumIndepVars);
        lExpectedOut = lPotentialOut;
        vYhatTemp = NaN(iNumObsTemp,1);
        vYhatTempWts = NaN(iNumObsTemp,1);
        rModelENet = struct('rStatus',iExpectedStatus( ...
            "expected_no_complete_validation_support", ...
            "No validation row has a complete component-forecast vector."));
    end

    % Save prediction
    cYhat{iIdxI}        = vYhatTemp;
    cYhatWts{iIdxI}     = vYhatTempWts;
    cModels{iIdxI}      = rModelENet;
    cExpectedOut{iIdxI} = logical(lExpectedOut);
    cSelectedOut{iIdxI} = logical(lKeepPred);
end

% To panel
vYhat       = NaN(iNumPanelObs,1);
vYhatWts    = NaN(iNumPanelObs,1);
vYoutPnl    = NaN(iNumPanelObs,1);
vYoutLabel  = NaN(iNumPanelObs,1);
lExpectedPanel = false(iNumPanelObs,1);
vWindowIndexByPanel = zeros(iNumPanelObs,1,'uint32');
for iIdxI = 1:iNumIter
    vIdxOutOfSample = vUniqueTimeID(cTimeIdxOut{iIdxI});   
    lIsDataOut  = ismember(mID(:,1), vIdxOutOfSample);
    vYhat(lIsDataOut) = cYhat{iIdxI};
    vYhatWts(lIsDataOut) = cYhatWts{iIdxI};
    vYoutPnl(lIsDataOut) = cYoutPnl{iIdxI};
    vYoutLabel(lIsDataOut) = cYoutLabel{iIdxI};
    lExpectedPanel(lIsDataOut) = cExpectedOut{iIdxI};
    vWindowIndexByPanel(lIsDataOut) = uint32(iIdxI);
end
rForecastAudit = struct();
rForecastAudit.cSelectionStatus = cellfun( ...
    @(r) r.rStatus,cModels,'UniformOutput',false);
rForecastAudit.cSelected = cSelectedOut;
rForecastAudit.cOutTimeID = cellfun( ...
    @(v) vUniqueTimeID(v),cTimeIdxOut,'UniformOutput',false);
rForecastAudit.lExpectedPanel = lExpectedPanel;
rForecastAudit.vWindowIndexByPanel = vWindowIndexByPanel;
rForecastAudit.sExpectedSupportRule = [ ...
    'estimated nonempty selection: all fixed selected predictors observed; ' ...
    'empty/failed selection: all potential union-panel formation rows'];
end

function rStatus = iExpectedStatus(sCode,sMessage)
rStatus = struct('sCode',string(sCode), ...
    'sIdentifier',"",'sMessage',string(sMessage));
end
