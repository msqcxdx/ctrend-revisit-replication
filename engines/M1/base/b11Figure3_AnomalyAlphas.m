% Script for calculating the pricing errors of models for anomaly
% portfolios
%
% Requires that b05CreateCTREND was executed
%
% This script produces:
%  Figure 3:    Anomaly Alphas

% Clear console
clear; clc; close all;

% Set paths
sOldPath    = path;
sDataPath   = './DATA/';
addpath('./Utils/');
addpath('./LatexTables/');

% Define samples. We analyze the pricing errors for a) all anomalies in
% LTW, b) all technical indicators, and c) all anomalies and technical
% indicators
cSamples    = {'LTW','TI','All'};
iNumSamples = length(cSamples);

% Define the respective anomaly names
cLTW_Anomalies = {'mcap','prc','maxdprc',...
        'ret_1_0','ret_2_0','ret_3_0','ret_4_0','ret_4_1',...
        'prcvol','volscaled','stdprcvol'};
cTI_Anomalies  = [{'rsi', 'stochRSI', 'stochK', 'stochD', 'cci'},...
        cellfun(@(x)['sma_',x,'d'],sprintfc('%i',[3,5,10,20,50,100,200]),'un',false),...
        {'macd', 'macd_diff_signal'},...
        cellfun(@(x)['volsma_',x,'d'],sprintfc('%i',[3,5,10,20,50,100,200]),'un',false),...
        {'volmacd', 'volmacd_diff_signal','chaikin'},...
        {'boll_low','boll_mid','boll_high','boll_width'}];
cAll_Anomalies  = [cLTW_Anomalies, cTI_Anomalies];
iNumAllAnomalies= length(cAll_Anomalies);

% Create filenames
sFilenameTestAssets = sprintf('./Results/HedgePorts.mat');
sFilenameCTREND     = sprintf('./Results/CTREND/CTREND_Base.mat');

% Load test assets
rTestAssets = load(sFilenameTestAssets);

% Load trend factor
rCTREND   = load(sFilenameCTREND,'cResults','vDates','vAssetID', ...
    'sCodeFingerprint','sDataBuildID');
sCurrentDataBuildID = fGetCurrentWeeklyDataBuildID('./DATA/');
fAssertSavedResultProvenance(rCTREND, sCurrentDataBuildID);
fAssertSavedResultProvenance(rTestAssets, sCurrentDataBuildID);
vCTREND   = rCTREND.cResults.VW.mPortRet(end,:)';
vDates    = rCTREND.vDates;
assert(isfield(rTestAssets, 'vDates') && ...
    isequal(rTestAssets.vDates(:), vDates(:)), ...
    'Hedge-port and CTREND dates are not identical');
assert(size(rTestAssets.mHedgePort,1) == numel(vDates), ...
    'Hedge-port rows do not match CTREND dates');

% Load LTW factors
load('./DATA/LTW_3factor.mat');
mLTW        = fAlignByDate(vDatesLiu, mLTW, vDates, 'LTW', 0.95);

% Make factors to table. Each model uses its own factor support; CCAPM and
% LTW must not lose dates merely because CTREND is unavailable.
mFactors = [mLTW, vCTREND];
tFactors = array2table(mFactors,...
    'VariableNames',{'CMKT', 'CSMB', 'CMOM', 'CTREND'});

% Get test assets
tTestAssets = array2table(rTestAssets.mHedgePort,...
    'VariableNames',rTestAssets.cCharNames);
tTestAssets = tTestAssets(:,cAll_Anomalies);
mTestAssets = table2array(tTestAssets);

% Define models
cFactMdls(1,1)  = {'CCAPM'};                 cFactMdls{1,2} = {'CMKT'};
cFactMdls(2,1)  = {'LTW'};                   cFactMdls{2,2} = {'CMKT', 'CSMB', 'CMOM'};
cFactMdls(3,1)  = {'TREND'};                 cFactMdls{3,2} = {'CMKT', 'CSMB', 'CTREND'};
iNumModels      = size(cFactMdls,1);
cFactorMatrices = cell(iNumModels, 1);
for iIdxM = 1:iNumModels
    cFactorMatrices{iIdxM} = table2array(tFactors(:,cFactMdls{iIdxM,2}));
end

% Initialize memory
iNumObs     = length(vDates);
mAlpha      = NaN(iNumAllAnomalies, iNumModels);
mAlphaT     = NaN(iNumAllAnomalies, iNumModels);
mResid      = NaN(iNumObs, iNumAllAnomalies, iNumModels);
mAvgRet     = NaN(iNumAllAnomalies, iNumModels);

% Loop over test assets
parfor iIdxI = 1:iNumAllAnomalies
    % Get test asset
    vY = mTestAssets(:,iIdxI);
    vAlphaTemp  = NaN(1, iNumModels);
    vAlphaTTemp = NaN(1, iNumModels);
    vAvgRetTemp = NaN(1, iNumModels);
    mResidTemp  = NaN(iNumObs, iNumModels);

    % Loop over models
    for iIdxM = 1:iNumModels
        % Get factors
        mX = cFactorMatrices{iIdxM};

        % Regression
        [vBetaTemp, vTstatTemp, vResidTemp] = fRegstatsTstatSafe(vY, mX);
        lRegSample = isfinite(vY) & all(isfinite(mX),2);
        if any(lRegSample)
            vAvgRetTemp(iIdxM) = mean(vY(lRegSample));
        end

        % Save alphas, t-statistics, and residuals
        vAlphaTemp(iIdxM)     = vBetaTemp(1);
        vAlphaTTemp(iIdxM)    = vTstatTemp(1);
        mResidTemp(:, iIdxM)  = vResidTemp;
    end
    mAlpha(iIdxI, :)   = vAlphaTemp;
    mAlphaT(iIdxI, :)  = vAlphaTTemp;
    mAvgRet(iIdxI, :)  = vAvgRetTemp;
    mResid(:, iIdxI, :) = reshape(mResidTemp, iNumObs, 1, iNumModels);
end

% Calculate average alphas, t-statistics for all significant anomalies
lIsAnomaly = abs(mAlphaT(:,strcmpi(cFactMdls(:,1),'CCAPM'))) > 1.96;

% Initielize memory
mAvgAbsAlpha    = NaN(iNumModels, iNumSamples);
mAvgAbsAlphaT   = NaN(iNumModels, iNumSamples);
mNumSignificant = NaN(iNumModels, iNumSamples);
mDelta          = NaN(iNumModels, iNumSamples);
mGRSp           = NaN(iNumModels, iNumSamples);
cSystemAudit    = cell(iNumSamples,iNumModels);

% Loop over samples
parfor iIdxS = 1:iNumSamples
    % Get sample
    cAnomalyUseTemp = {};
    switch upper(cSamples{iIdxS})
        case 'LTW'
            cAnomalyUseTemp = cLTW_Anomalies;
        case 'TI'
            cAnomalyUseTemp = cTI_Anomalies;
        case 'ALL'
            cAnomalyUseTemp = cAll_Anomalies;
        otherwise
            error('Unknown set of anomalies');
    end

    % Select anomalies
    lIsSample       = ismember(cAll_Anomalies(:), cAnomalyUseTemp(:));
    lAnalyzeAnomaly = lIsAnomaly & lIsSample;

    % The first three summary rows describe the pairwise regressions plotted
    % below. Delta and GRS are system statistics and therefore use a common
    % listwise sample within each anomaly set/model.
    vAvgAbsAlphaTemp = NaN(iNumModels,1);
    vAvgAbsAlphaTTemp = NaN(iNumModels,1);
    vNumSignificantTemp = NaN(iNumModels,1);
    vDeltaTemp = NaN(iNumModels,1);
    vGRSpTemp = NaN(iNumModels,1);
    cSystemAuditTemp = cell(1,iNumModels);
    for iIdxM = 1:iNumModels
        vAlphaPairwise = mAlpha(lAnalyzeAnomaly,iIdxM);
        vAlphaTPairwise = mAlphaT(lAnalyzeAnomaly,iIdxM);
        vAvgAbsAlphaTemp(iIdxM) = ...
            mean(abs(vAlphaPairwise),'omitmissing');
        vAvgAbsAlphaTTemp(iIdxM) = ...
            mean(abs(vAlphaTPairwise),'omitmissing');
        vNumSignificantTemp(iIdxM) = ...
            sum(abs(vAlphaTPairwise) > 1.96);

        rSystem = fEstimateAssetPricingSystem( ...
            mTestAssets(:,lAnalyzeAnomaly),cFactorMatrices{iIdxM});
        vDeltaTemp(iIdxM) = rSystem.dDelta;
        vGRSpTemp(iIdxM) = rSystem.dGRSp;
        rAuditTemp = struct();
        rAuditTemp.cInputAssetNames = cAll_Anomalies(lAnalyzeAnomaly);
        rAuditTemp.iNumInputAssets = nnz(lAnalyzeAnomaly);
        rAuditTemp.iNumUniqueAssets = rSystem.iNumUniqueAssets;
        rAuditTemp.iNumCommonWeeks = nnz(rSystem.lCommon);
        rAuditTemp.vUniqueAssetIndex = rSystem.vUniqueAssetIndex;
        rAuditTemp.vAssetToUnique = rSystem.vAssetToUnique;
        cSystemAuditTemp{iIdxM} = rAuditTemp;
    end
    mAvgAbsAlpha(:,iIdxS)    = vAvgAbsAlphaTemp;
    mAvgAbsAlphaT(:,iIdxS)   = vAvgAbsAlphaTTemp;
    mNumSignificant(:,iIdxS) = vNumSignificantTemp;
    mDelta(:, iIdxS)         = vDeltaTemp;
    mGRSp(:, iIdxS)          = vGRSpTemp;
    cSystemAudit(iIdxS,:)    = cSystemAuditTemp;
end

% Exact aliases are removed only from system-level Delta/GRS covariance
% matrices. Publish the names, mapping, and common-week N so this necessary
% identification step is never silent.
for iIdxS = 1:iNumSamples
    for iIdxM = 1:iNumModels
        rAuditTemp = cSystemAudit{iIdxS,iIdxM};
        fprintf(['figure3_system sample=%s model=%s input_assets=%d ' ...
            'unique_assets=%d common_weeks=%d asset_to_unique=%s\n'], ...
            cSamples{iIdxS},cFactMdls{iIdxM,1}, ...
            rAuditTemp.iNumInputAssets,rAuditTemp.iNumUniqueAssets, ...
            rAuditTemp.iNumCommonWeeks,mat2str(rAuditTemp.vAssetToUnique));
    end
end
sSystemAuditFile = './Results/Figure3_SystemAudit.mat';
sSystemAuditTemporary = [tempname('./Results'),'.mat'];
rSystemAuditCleanup = onCleanup(@() iDeleteIfExists(sSystemAuditTemporary));
sCodeFingerprint = fPipelineCodeFingerprint(pwd);
sDataBuildID = sCurrentDataBuildID;
save(sSystemAuditTemporary,'cSystemAudit','cSamples','cFactMdls', ...
    'sCodeFingerprint','sDataBuildID');
[lMoved,sMoveMessage] = movefile( ...
    sSystemAuditTemporary,sSystemAuditFile,'f');
assert(lMoved,'Could not atomically publish %s: %s', ...
    sSystemAuditFile,sMoveMessage);
clear rSystemAuditCleanup

% Runtime consistency gate: the first three table rows must be reproducible
% from the exact pairwise arrays used for the scatter points.
for iIdxS = 1:iNumSamples
    switch upper(cSamples{iIdxS})
        case 'LTW'
            cAnomalyUse = cLTW_Anomalies;
        case 'TI'
            cAnomalyUse = cTI_Anomalies;
        case 'ALL'
            cAnomalyUse = cAll_Anomalies;
    end
    lAnalyzeAnomaly = lIsAnomaly & ...
        ismember(cAll_Anomalies(:),cAnomalyUse(:));
    for iIdxM = 1:iNumModels
        vAlphaCheck = mAlpha(lAnalyzeAnomaly,iIdxM);
        vAlphaTCheck = mAlphaT(lAnalyzeAnomaly,iIdxM);
        dExpectedAlpha = mean(abs(vAlphaCheck),'omitmissing');
        dExpectedT = mean(abs(vAlphaTCheck),'omitmissing');
        iExpectedSignificant = sum(abs(vAlphaTCheck) > 1.96);
        assert((isnan(dExpectedAlpha) && ...
                isnan(mAvgAbsAlpha(iIdxM,iIdxS))) || ...
               abs(dExpectedAlpha-mAvgAbsAlpha(iIdxM,iIdxS)) < 1e-12);
        assert((isnan(dExpectedT) && ...
                isnan(mAvgAbsAlphaT(iIdxM,iIdxS))) || ...
               abs(dExpectedT-mAvgAbsAlphaT(iIdxM,iIdxS)) < 1e-12);
        assert(mNumSignificant(iIdxM,iIdxS) == iExpectedSignificant, ...
            'Figure 3 Nsig must equal the number of significant plotted points');
    end
end

% Create tables for each model
cTables = cell(iNumModels,1);
parfor iIdxM = 1:iNumModels
    cTableTemp = [fMatrix2Cell( [mAvgAbsAlpha(iIdxM,:) * 100;...
        mAvgAbsAlphaT(iIdxM,:)],2);...
        sprintfc('%i',mNumSignificant(iIdxM,:));...
        fMatrix2Cell(mDelta(iIdxM,:),3);...
        fMatrix2Cell(mGRSp(iIdxM,:)*100,2)];

    % Add column and row header
    cTables{iIdxM} = [[{''},cSamples]; ...
        [{'Avg $|\alpha|$'; 'Avg $|t|$';'$N_{sig}$';'$\Delta$';'GRS ($p$)'}, cTableTemp]];
end

% Merge tables
cTableFigure3 = horzcat(cTables{:});
rInput.table  = cTableFigure3;
rInput.tableCaption = 'Anomaly Alphas';
fCreateLatexTable(rInput);

% Create figure 3.  Each x coordinate uses the same finite observations as
% that anomaly/model alpha regression.
mAvgRet = mAvgRet * 100;
mAlpha  = mAlpha  * 100;

% Get X and Y limits
dXmin = min(mAvgRet,[],'all','omitmissing');
dXmax = max(mAvgRet,[],'all','omitmissing');
dYmin = min(mAlpha,[],'all','omitmissing');
dYmax = max(mAlpha,[],'all','omitmissing');
vXlimit = [dXmin-0.1*max(eps,dXmax-dXmin),dXmax+0.1*max(eps,dXmax-dXmin)];
vYlimit = [dYmin-0.1*max(eps,dYmax-dYmin),dYmax+0.1*max(eps,dYmax-dYmin)];

for iIdxM = 1:iNumModels
    % Get data
    vAvgRetTemp         = mAvgRet(:,iIdxM);
    vAlphaTemp          = mAlpha(:,iIdxM);
    lSignificantTemp    = abs(mAlphaT(:,iIdxM)) > 1.96;

    % Create figure
    h = figure(iIdxM);
    scatter(vAvgRetTemp(lSignificantTemp), vAlphaTemp(lSignificantTemp), 'black','filled');
    hold on
    scatter(vAvgRetTemp(~lSignificantTemp), vAlphaTemp(~lSignificantTemp), 'black');
    xlim(vXlimit)
    ylim(vYlimit)
    ylabel('$\alpha$ (\%)','Interpreter','latex');
    xlabel('Avg (\%)','Interpreter','latex');

    % Add 45° line
    hLine = refline(1);
    hLine.Color = [0,0,0];
    hLine2 = refline(0);
    hLine2.Color = [0,0,0];
end

% === Create Table B9: Trend Model Alphas
% Find anomalies
lIsAnomalyLTW = ismember(cAll_Anomalies,cLTW_Anomalies); % Panel A
lIsAnomalyTI  = ismember(cAll_Anomalies,cTI_Anomalies); % Panel B

% Find trend model
iIdxTrend     = find(strcmp(cFactMdls(:,1),'TREND'));

% Get their alphas
cTableB9 = fAddStatistics(...
    fMatrix2Cell( [mAlpha(lIsAnomalyLTW, iIdxTrend); mAlpha(lIsAnomalyTI, iIdxTrend)], 2),...
    fMatrix2Cell( [mAlphaT(lIsAnomalyLTW, iIdxTrend); mAlphaT(lIsAnomalyTI, iIdxTrend)],2),...
    abs([mAlphaT(lIsAnomalyLTW, iIdxTrend); mAlphaT(lIsAnomalyTI, iIdxTrend)])>=1.96);
cTableB9 = [[cAll_Anomalies(lIsAnomalyLTW),cAll_Anomalies(lIsAnomalyTI)]',cTableB9];
rInput.table = cTableB9;
rInput.tableCaption = 'TREND Model Alphas';
fCreateLatexTable(rInput);

% Restore path
path(sOldPath);

function iDeleteIfExists(sFilename)
if exist(sFilename,'file') == 2
    delete(sFilename);
end
end
