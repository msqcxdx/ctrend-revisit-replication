% Script for analyzing the performance of the CTREND factor using single
% sorts
%
% Requires that b05CreateCTREND was executed
%
% This script produces:
%   Figure 1:   Comparison of Cryptocurrency Factors
%   Table 3:    Univariate Portfolio Sorts
%   Figure B.2: Comparison of Cumulative Factor Returns
%   Table B.2:  Descriptive Statistics of Asset Pricing Factor Returns
%
%   and when setting lUseLTW below to false:
%   Table B.7:  Univariate Portfolio Sorts - Alternative Factor Data
%   

% Clear console
clear; clc; close all;

% Set paths
sOldPath    = path;
sDataPath   = './DATA/';
addpath('./Utils/');
addpath('./LatexTables/');

% Use original LTW factors as benchmark. If false, this script creates them
lUseLTW = true;

% Load design choices
load('DesignChoices.mat','tCombos');

% Define baseline setting
sOutlierTreatment   = 'trunc';  % Truncation
dThreshold          = 0.005;    % 0.5% and 99.5% levels
dMinMCAP            = 1e6;      % Minimum market capitalization
dMinPrc             = 0;        % Minimum price
lExclStable         = true;     % Exclude stable coins
iRetLead            = 0;        % Implementation lag
lRoll               = true;     % Fixed-length estimation window?
iNumIn              = 52;       % Number of in-sample periods
lUseValueWts        = true;     % Use value-weighted objective function

% Settings for portfolio sorts
rOptions = struct();
rOptions.sFreq = 'weekly';                  % Data frequency
rOptions.lHedgeOnly = false;                % Get only hedge portfolio
rOptions.iMinNumCS = 25;                    % Minimum cross section
rOptions.iMinNumAssets = 5;                 % Minimum number of assets in portfolio
rOptions.lEnsureAllObs = true;              % Ensure valid observation for market equity, returns, and sort variable
vQuantiles      = 0:0.2:1;                  % Percentiles for sorts
iNumPorts       = length(vQuantiles);

% Other settings that are no design choices
iStartDate      = 201416;       
iEndDate        = 202222; 

%% Analysis
% Find number of data setting
iIdxDataComb = tCombos.data_setting( find(strcmpi(tCombos.cOutlierTreatment, sOutlierTreatment) & ...
    tCombos.vThreshold == dThreshold,1,'first') );

% Load data
load([sDataPath,sprintf('bCharacteristicsOLHC_Combo%i.mat', iIdxDataComb)]);

% M2 keeps every M0 table definition except future-outcome conditioning.
assert(isfield(rData,'mReturnsM2Raw') && isfield(rData,'mRetLeadM2Raw') && ...
    isfield(rData,'mPnlReturnsM2') && isfield(rData,'mPnlRetLeadM2') && ...
    isfield(rData,'rEconomicReinvestmentLedgerReference'), ...
    'Weekly input predates the M2 causal return layer; rerun b02');
mReturns        = rData.mReturnsM2Raw;
mReturnsLead    = rData.mRetLeadM2Raw;
mPnlReturns     = rData.mPnlReturnsM2;
mPnlReturnsLead = rData.mPnlRetLeadM2;
mME             = rData.mME;
mPrices         = rData.mClose;
mVolume         = rData.mVolume;
vDates          = rData.yrmoda;
vMktRet         = rData.vMktRet;

% Get characteristic names for which we want to calculate portfolio
% characteristics
cCharNames = {'mcap','volume','ivol','ret_3_0'};

% Determine dimensions
[iNumObs, iNumAssets]   = size(mReturns);
iNumChars               = length(cCharNames);

% Lag characteristics and convert to matrix
mChars_L1   = NaN(iNumAssets, iNumObs, iNumChars);
for iIdxChar = 1:iNumChars
    % Lag characteristic
    mCtemp = [NaN(1, iNumAssets); rChars.(cCharNames{iIdxChar})(1:end-1,:)]';
    mChars_L1(:,:,iIdxChar) = mCtemp;
end 

% Lag formation variables
mME_L1 = [NaN(1, iNumAssets); mME(1:end-1,:)];
mPrices_L1 = [NaN(1, iNumAssets); mPrices(1:end-1,:)];

% Restrict to sample period
lIsSample                   = vDates >= iStartDate & vDates <= iEndDate;
mReturns(~lIsSample,:)      = [];
mReturnsLead(~lIsSample,:)  = [];
mPnlReturns(~lIsSample,:)   = [];
mPnlReturnsLead(~lIsSample,:) = [];
mVolume(~lIsSample,:)       = [];
mME_L1(~lIsSample,:)        = [];
mPrices_L1(~lIsSample,:)    = [];
mME(~lIsSample,:)           = [];
mChars_L1(:,~lIsSample,:)   = [];
vDates(~lIsSample)          = [];
vMktRet(~lIsSample)         = [];
iNumObs                     = length(vDates);

lRemoveObs = isnan(mME_L1) | isnan(mPrices_L1) | ...
    (mME_L1 == 0) | (mME_L1 < dMinMCAP) | (mPrices_L1 < dMinPrc);
if lExclStable
    lRemoveObs = lRemoveObs | rMetaData.lIsStable;
end
mReturns(lRemoveObs) = NaN;
mReturnsLead(lRemoveObs) = NaN;
mPnlReturns(lRemoveObs) = NaN;
mPnlReturnsLead(lRemoveObs) = NaN;
mME_L1(lRemoveObs) = NaN;

% Scale characteristics for output
mChars_L1(:,:,strcmp(cCharNames,'mcap'))    = (mME_L1'/ 1e6);
mChars_L1(:,:,strcmp(cCharNames,'volume'))  = (mVolume' / 1e6);
mChars_L1(:,:,strcmp(cCharNames,'ret_3_0'))  = mChars_L1(:,:,strcmp(cCharNames,'ret_3_0')) * 100;

% Load aggregate trend characteristic (b05CreateCTREND)
sFilename = sprintf('./Results/CTREND/CTREND_Base.mat');
rCTREND   = load(sFilename, 'mYhat','cResults','vDates','vAssetID');

% Define return for sorting. If we allow for an implementation lag of
% one day, we choose the one-day leaded return. Not relevant for the
% baseline setting 
if iRetLead == 0
    mRetSort = mPnlReturns';
    sPayoffTiming = 'ordinary';
else
    mRetSort = mPnlReturnsLead';
    sPayoffTiming = 'lead1';
end
[rOptions,~,~] = fAttachEconomicLedgerOptions( ...
    rOptions,sDataPath,rData,rMetaData.vID(:),vDates,sPayoffTiming);

% Get benchmark factors
if lUseLTW
    % Load LTW factors
    load('./DATA/LTW_3factor.mat');
    lIsSample           = vDatesLiu >= iStartDate & vDatesLiu <= iEndDate;
    mLTW                = mLTW(lIsSample,:);
else
    % Create LTW factors if not use from their website
    % CSMB uses 30% and 70% breakpoints: univariate sorts
    rResultsSMB = fSingleSortMulti(mME_L1', mRetSort, [0, 0.3, 0.7, 1], ...
        [], mME_L1', rOptions);
    vCSMB       = rResultsSMB.VW.mPortRet(end,:) * -1;

    % CMOM uses dependent sorts: First split into small and big
    % cryptocurrencies and then use 30% and 70% breakpoints
    iIdxMom = find(strcmp(cCharNames,'ret_3_0'));
    rResultsCMOM = fDepDoubleSort(mME_L1', mChars_L1(:,:,iIdxMom), ...
        mRetSort, [], mME_L1', 'vPercentileA',0:0.5:1, ...
        'vPercentileB', [0, 0.3, 0.7, 1], ...
        'rReinvestmentLedger',rOptions.rReinvestmentLedger, ...
        'vLedgerWeekRow',rOptions.vLedgerWeekRow, ...
        'sPayoffTiming',rOptions.sPayoffTiming);
    vCMOM = 0.5 * (rResultsCMOM.VW.cPortRets{1,end-1} + ...   % Small high
        rResultsCMOM.VW.cPortRets{2,end-1}) - ...             % Bigh high
        0.5 * (rResultsCMOM.VW.cPortRets{1,1} + ...           % Small low
        rResultsCMOM.VW.cPortRets{2,1});                      % Big low

    % Merge
    mLTW = [vMktRet, vCSMB', vCMOM'];
end

% Define benchmark models
cBenchmark{1,1} = {'CCAPM'};        cBenchmark{1,2} = vMktRet;
cBenchmark{2,1} = {'LTW'};          cBenchmark{2,2} = mLTW;
iNumBenchmark   = size(cBenchmark,1);

% Initialize memory
mBeta_CAPM      = NaN(iNumPorts, 2);                    % Alphas and betas wrt CAPM
mBetaT_CAPM     = NaN(iNumPorts, 2);                    % t-statistics of alphas and betas wrt CAPM
mBeta_LTW       = NaN(iNumPorts, 4);                    % Alphas and betas wrt LTW
mBetaT_LTW      = NaN(iNumPorts, 4);                    % t-statistics of alphas and betas wrt LTW

% Sort w.r.t. characteristic 
rResults = fSingleSortMulti(rCTREND.mYhat, mRetSort, vQuantiles, [], mME_L1', rOptions); 

% Get time-series of portfolios
if lUseValueWts
    mPortRet = rResults.VW.mPortRet';
    mWts     = rResults.VW.mWts;
else
    mPortRet = rResults.EW.mPortRet';
    mWts     = rResults.EW.mWts;
end

% Average portfolio return
vAvgRet                 = mean(mPortRet,1,'omitmissing')';
[~,~,~,stats]           = ttest(mPortRet);
vAvgRetT                = stats.tstat';

% Volatility
vStd                    = std(mPortRet,[],1,'omitmissing')';

% Sharpe ratio
vShp                    = vAvgRet ./ vStd * sqrt(52);

% Regression on CAPM and LTW
for iIdxP = 1:iNumPorts
    % Regression on CAPM
    rRegResults             = regstats(mPortRet(:,iIdxP), vMktRet, 'linear', {'tstat'});
    mBeta_CAPM(iIdxP,:)     = rRegResults.tstat.beta;
    mBetaT_CAPM(iIdxP,:)    = rRegResults.tstat.t;

    % Regression on LTW
    rRegResults             = regstats(mPortRet(:,iIdxP), mLTW, 'linear', {'tstat'});
    mBeta_LTW(iIdxP,:)     = rRegResults.tstat.beta;
    mBetaT_LTW(iIdxP,:)    = rRegResults.tstat.t;
end

% Calculate additional characteristics
mAddPortChars = NaN(iNumPorts, iNumChars);
for iIdxChar = 1:iNumChars
    % Loop over portfolios
    for iIdxP = 1:iNumPorts-1
        % Get characteristics
        mCtemp = mChars_L1(:,:,iIdxChar);
        lIsIn  = rResults.mIndex == iIdxP;

        % Set to missing if not available
        mCtemp(~lIsIn) = NaN;

        % Calculate average
        mAddPortChars(iIdxP, iIdxChar) = mean(mCtemp,'all','omitmissing');
    end
end

% Create LaTeX table
cRowHeader = replace(sprintfc('%i', 1:iNumPorts)',{num2str(1),num2str(iNumPorts-1),num2str(iNumPorts)},{'L','H','H-L'});
cColHeader = [{'Rank','Avg','Std','Shp','$\alpha^{CCAPM}$','$\beta^{CMKT}$',...
    '$\alpha^{LTW}$','$\beta^{CMKT}$','$\beta^{CSMB}$','$\beta^{CMOM}$'},replace(cCharNames,'_','\_')];

% Average returns
cAvgRet = fAddStatistics( fMatrix2Cell( vAvgRet * 100,2),...
    fMatrix2Cell( vAvgRetT, 2),...
    abs(round(vAvgRetT,2)) >= 1.96);

% Regression coefficients
mBeta_CAPM(:,1) = mBeta_CAPM(:,1) * 100; mBeta_LTW(:,1) = mBeta_LTW(:,1) * 100; 
cBeta = fAddStatistics( fMatrix2Cell( [mBeta_CAPM, mBeta_LTW],2),...
    fMatrix2Cell( [mBetaT_CAPM, mBetaT_LTW], 2),...
    abs(round([mBetaT_CAPM, mBetaT_LTW],2)) >= 1.96);

% Volatility and Sharpe ratio
cStats = fMatrix2Cell( [vStd*100, vShp], 2);

% Characteristics
cChars = fMatrix2Cell( mAddPortChars, 2, true);

% Merge
cTable3 = [cColHeader; [cRowHeader, cAvgRet, cStats, cBeta, cChars]];
rInput.table = cTable3;
rInput.tableCaption = 'Univariate Portfolio Sorts';
fCreateLatexTable(rInput);

% Compare factors
mFact               = [mLTW, mPortRet(:,end)];
vDatesTemp          = vDates;
lIsNaN              = any(isnan(mFact),2);
mFact(lIsNaN,:)     = [];
vDatesTemp(lIsNaN)  = [];

% Calculate Sharpe ratios and average returns
vShp    = fSharpeRatio(mFact,0,1,2);
vAvg    = mean(mFact,1,'omitmissing')';
vSkew   = skewness(mFact,[],1)';
vKurt   = kurtosis(mFact,[],1)';
vStd    = std(mFact,[],1)';
[~,~,~,stats] = ttest(mFact);
vTstat  = stats.tstat';

% Calculate correlations
mCorr   = corr(mFact);
mCorr   = triu(mCorr,1); mCorr(mCorr == 0) = NaN;

% Create table B2
cTableB2 = [fAddStatistics( fMatrix2Cell(vAvg * 100, 2),...
    fMatrix2Cell(vTstat,2), abs(round(vTstat,2))>=1.96),...
    fMatrix2Cell( [vStd * 100, vShp, vSkew, vKurt-3, mCorr], 2, true)];
cTableB2(end,:) = [];

% Create column header
cLTWnames  = {'CMKT','CSMB','CMOM'};
cColHeader = [{'','Avg','Std','Shp','Skew','Kurt'}, cLTWnames, {'CTREND'}];

% Merge
cTableB2        = [cColHeader; [cLTWnames(:), cTableB2]];
rInput.table    = cTableB2;
rInput.tableCaption = 'Descriptive Statistics of Asset Pricing Factor Returns';
fCreateLatexTable(rInput);

% Plot average return
h1 = figure(1);
bar(1,vAvg(end) * 100,'grouped','FaceColor',[0.5,0.5,0.5]);
hold on
bar(2:4,vAvg(1:end-1) * 100,'grouped','FaceColor',[0.75,0.75,0.75]);
hold off
xticks(1:4)
xticklabels({'CTREND','CMKT','CSMB','CMOM'});
ylabel('Average Return (\%)','Interpreter','latex','FontSize',12);
yticklabels(sprintfc('%.1f',[0:0.5:4]));
ax = gca(h1);
ax.YAxis.FontSize = 12;
ax.XAxis.FontSize = 12;
box off

% Plot Sharpe ratios
h2 = figure(2);
bar(1,vShp(end),'grouped','FaceColor',[0.5,0.5,0.5]);
hold on
bar(2:4,vShp(1:end-1),'grouped','FaceColor',[0.75,0.75,0.75]);
hold off
xticks(1:4)
xticklabels({'CTREND','CMKT','CSMB','CMOM'});
ylabel('Sharpe Ratio (Annualized)','Interpreter','latex','FontSize',12);
yticklabels(sprintfc('%.1f',[0:0.2:2]));
ax = gca(h2);
ax.YAxis.FontSize = 12;
ax.XAxis.FontSize = 12;
box off

% Plot cumulative returns
mCumRet             = cumsum(mFact, 1, 'omitmissing');
h3 = figure(3);
set(h3, 'DefaultTextFontSize', 30);
plot(mCumRet(:,1), 'LineWidth',2, 'LineStyle','-', 'Color',[0.6, 0.6, 0.6]);
hold on
plot(mCumRet(:,2), 'LineWidth',2, 'LineStyle','--', 'Color',[0.6, 0.6, 0.6]);
plot(mCumRet(:,3), 'LineWidth',2, 'LineStyle','--', 'Color',[0, 0, 0]);
plot(mCumRet(:,4), 'LineWidth',2, 'LineStyle','-', 'Color',[0, 0, 0]);
hold off
box off 
legend({'CMKT', 'CSMB', 'CMOM', 'CTREND'}, 'Location','northwest');
ylabel('Cumulative Return (\%)', 'Interpreter','latex');
xticks(38:52:350)
xticklabels(sprintfc('%i', 2016:2022));

% Restore path
path(sOldPath);
