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
rCTREND   = load(sFilenameCTREND,'cResults','vDates','vAssetID');
vCTREND   = rCTREND.cResults.VW.mPortRet(end,:)';
vDates    = rCTREND.vDates;

% Load LTW factors
load('./DATA/LTW_3factor.mat');
lIsSample   = vDatesLiu >= vDates(1) & vDatesLiu <= vDates(end);
mLTW        = mLTW(lIsSample,:);

% Make factors to table
mFactors = [mLTW, vCTREND]; mFactors(any(isnan(mFactors),2),:) = NaN;
tFactors = array2table(mFactors,...
    'VariableNames',{'CMKT', 'CSMB', 'CMOM', 'CTREND'});

% Get test assets
rTestAssets.mHedgePort(any(isnan(mFactors),2),:) = NaN;
tTestAssets = array2table(rTestAssets.mHedgePort,...
    'VariableNames',rTestAssets.cCharNames);
tTestAssets = tTestAssets(:,cAll_Anomalies);

% Define models
cFactMdls(1,1)  = {'CCAPM'};                 cFactMdls{1,2} = {'CMKT'};
cFactMdls(2,1)  = {'LTW'};                   cFactMdls{2,2} = {'CMKT', 'CSMB', 'CMOM'};
cFactMdls(3,1)  = {'TREND'};                 cFactMdls{3,2} = {'CMKT', 'CSMB', 'CTREND'};
iNumModels      = size(cFactMdls,1);

% Average returns of test assets
vAvgRet     = mean(table2array(tTestAssets),'omitmissing')';

% Initialize memory
iNumObs     = length(vDates);
mAlpha      = NaN(iNumAllAnomalies, iNumModels);
mAlphaT     = NaN(iNumAllAnomalies, iNumModels);
mResid      = NaN(iNumObs, iNumAllAnomalies, iNumModels);

% Loop over test assets
for iIdxI = 1:iNumAllAnomalies
    % Get test asset
    vY = tTestAssets.(cAll_Anomalies{iIdxI});

    % Loop over models
    for iIdxM = 1:iNumModels
        % Get factors
        mX = table2array(tFactors(:,cFactMdls{iIdxM,2}));

        % Regression
        rRegResults = regstats(vY, mX, 'linear', {'tstat','r'});

        % Save alphas, t-statistics, and residuals
        mAlpha(iIdxI, iIdxM)    = rRegResults.tstat.beta(1);
        mAlphaT(iIdxI, iIdxM)   = rRegResults.tstat.t(1);
        mResid(:,iIdxI, iIdxM)  = rRegResults.r;
    end
end

% Calculate average alphas, t-statistics for all significant anomalies
lIsAnomaly = round(abs(mAlphaT(:,strcmpi(cFactMdls(:,1),'CCAPM'))),2) > 1.96;

% Initielize memory
mAvgAbsAlpha    = NaN(iNumModels, iNumSamples);
mAvgAbsAlphaT   = NaN(iNumModels, iNumSamples);
mNumSignificant = NaN(iNumModels, iNumSamples);
mDelta          = NaN(iNumModels, iNumSamples);
mGRSp           = NaN(iNumModels, iNumSamples);

% Loop over samples
for iIdxS = 1:iNumSamples
    % Get sample
    switch upper(cSamples{iIdxS})
        case 'LTW'
            cAnomalyUse = cLTW_Anomalies;
        case 'TI'
            cAnomalyUse = cTI_Anomalies;
        case 'ALL'
            cAnomalyUse = cAll_Anomalies;
        otherwise
            error('Unknown set of anomalies');
    end

    % Select anomalies
    lIsSample       = ismember(cAll_Anomalies(:), cAnomalyUse(:));
    lAnalyzeAnomaly = lIsAnomaly & lIsSample;

    % Average alphas and t-statistics
    mAvgAbsAlpha(:,iIdxS)   = mean(abs(mAlpha(lAnalyzeAnomaly,:)),1,'omitmissing');
    mAvgAbsAlphaT(:,iIdxS)  = mean(abs(mAlphaT(lAnalyzeAnomaly,:)),1,'omitmissing');

    % Number of significant anomalies
    mNumSignificant(:,iIdxS) = sum(round(abs(mAlphaT(lIsSample,:)),2) > 1.96,1);

    % Calculate weighted pricing errors
    mDelta(:, iIdxS) = fWeightedPricingError(mAlpha(lAnalyzeAnomaly,:), mResid(:,lAnalyzeAnomaly,:));

    % GRS test
    for iIdxM = 1:iNumModels
        % https://de.mathworks.com/matlabcentral/fileexchange/45898-grs-test-statistic
        [~,mGRSp(iIdxM, iIdxS)] = fGRS(mAlpha(lAnalyzeAnomaly,iIdxM), ...
            mResid(:,lAnalyzeAnomaly,iIdxM), ...
            table2array(tTestAssets(:,lAnalyzeAnomaly)));
    end
end

% Create tables for each model
cTables = cell(iNumModels,1);
for iIdxM = 1:iNumModels
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

% Create figure 3
vAvgRet = vAvgRet * 100;
mAlpha  = mAlpha  * 100;

% Get X and Y limits
vXlimit = [min(vAvgRet) + 0.1*min(vAvgRet), max(vAvgRet) + 0.1 *max(vAvgRet)];
vYlimit = [min(mAlpha, [], 'all') + 0.1*min(mAlpha, [], 'all'), max(mAlpha, [], 'all') + 0.1 *max(mAlpha, [], 'all')];

for iIdxM = 1:iNumModels
    % Get data
    vAvgRetTemp         = vAvgRet;
    vAlphaTemp          = mAlpha(:,iIdxM);
    lSignificantTemp    = round(abs(mAlphaT(:,iIdxM)),2) > 1.96;

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
    round(abs([mAlphaT(lIsAnomalyLTW, iIdxTrend); mAlphaT(lIsAnomalyTI, iIdxTrend)]),2)>=1.96);
cTableB9 = [[cAll_Anomalies(lIsAnomalyLTW),cAll_Anomalies(lIsAnomalyTI)]',cTableB9];
rInput.table = cTableB9;
rInput.tableCaption = 'TREND Model Alphas';
fCreateLatexTable(rInput);

% Restore path
path(sOldPath);