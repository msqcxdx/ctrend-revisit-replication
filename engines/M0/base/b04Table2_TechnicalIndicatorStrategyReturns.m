% Script for constructing hedge portfolios from characteristics and
% technical indicators
% 
% Requires that b02CalculateIndicators was executed

% Clear console
clear; clc; close all;

% Set paths
sOldPath            = path;
sDataPath           = './DATA/';
addpath('./Utils/');
addpath('./LatexTables/');

% Load design choices
load('DesignChoices.mat','tCombos');

% Other settings that are no design choices
iMinNumAssets   = 5;  % Minimum assets in portfolios 
iMinNumObsCS    = 25; % Minimum cross-section

% Define sample period
iStartDate = 201416; 
iEndDate   = 202222;
vQuantiles = 0:0.2:1;

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

%% Analysis
% Find number of data setting
iIdxDataComb = tCombos.data_setting( find(strcmpi(tCombos.cOutlierTreatment, sOutlierTreatment) & ...
    tCombos.vThreshold == dThreshold,1,'first') );

% Load data
load([sDataPath,sprintf('bCharacteristicsOLHC_Combo%i.mat', iIdxDataComb)]);

% Extract data from struct
mReturns        = rData.mReturns;
mReturnsLead    = rData.mRetLead;
mME             = rData.mME;
mPrices         = rData.mClose;
mVolume         = rData.mVolume;
vDates          = rData.yrmoda;
vMktRet         = rData.vMktRet;

% Apply market capitalization and price filter
lRemoveObs      = (mME == 0) | (mME < dMinMCAP) | (mPrices < dMinPrc);

% Apply stablecoin filter
if lExclStable
    lRemoveObs  = lRemoveObs | rMetaData.lIsStable;
end

% Apply filters
mReturns(lRemoveObs)        = NaN;
mReturnsLead(lRemoveObs)    = NaN;
mME(lRemoveObs)             = NaN;
mPrices(lRemoveObs)         = NaN;
mVolume(lRemoveObs)         = NaN;

% Get characteristic names
cCharNames = fieldnames(rChars);

% Determine dimensions
[iNumObs, iNumAssets]   = size(mReturns);
iNumChars               = length(cCharNames);
iNumPorts           = length(vQuantiles);

% Lag characteristics and convert to matrix
mChars_L1   = NaN(iNumAssets, iNumObs, iNumChars);
for iIdxChar = 1:iNumChars
    % Lag characteristic
    mCtemp = [NaN(1, iNumAssets); rChars.(cCharNames{iIdxChar})(1:end-1,:)]';
    mChars_L1(:,:,iIdxChar) = mCtemp;
end 

% Lag market equity
mME_L1 = [NaN(1, iNumAssets); mME(1:end-1,:)];

% Settings for portfolio sorts
rOptions = struct();
rOptions.sFreq = 'weekly';                  % Data frequency
rOptions.lHedgeOnly = false;                % Get only hedge portfolio
rOptions.iMinNumCS = iMinNumObsCS;          % Minimum cross section
rOptions.iMinNumAssets = iMinNumAssets;     % Minimum number of assets in portfolio
rOptions.lEnsureAllObs = true;              % Ensure valid observation for market equity, returns, and sort variable

% Restrict to sample period
lIsSample                   = vDates >= iStartDate & vDates <= iEndDate;
mReturns(~lIsSample,:)      = [];
mReturnsLead(~lIsSample,:)  = [];
mVolume(~lIsSample,:)       = [];
mME_L1(~lIsSample,:)        = [];
mME(~lIsSample,:)           = [];
mChars_L1(:,~lIsSample,:)   = [];
vDates(~lIsSample)          = [];
vMktRet(~lIsSample)         = [];
iNumObs                     = length(vDates);

% Load LTW factors
load('./DATA/LTW_3factor.mat','vDatesLiu','mLTW');
lIsSample           = vDatesLiu >= iStartDate & vDatesLiu <= iEndDate;
mLTW                = mLTW(lIsSample,:);

% Define return for sorting. If we allow for an implementation lag of
% one day, we choose the one-day leaded return. Not relevant for the
% baseline setting 
if iRetLead == 0
    mRetSort = mReturns';
else
    mRetSort = mReturnsLead';
end

% Define benchmark models
cBenchmark{1,1} = {'CCAPM'};        cBenchmark{1,2} = vMktRet;
cBenchmark{2,1} = {'LTW'};          cBenchmark{2,2} = mLTW;
iNumBenchmark   = size(cBenchmark,1);

% Initialize memory for hedge portfolio returns, average returns and
% t-statistics, and alphas and the respective t-statistics
mHedgePort      = NaN(iNumObs, iNumChars);      % Hedge portfolios
mAvgRet         = NaN(iNumChars, iNumPorts);    % Average returns 
mAvgRetT        = NaN(iNumChars, iNumPorts);    % t-statistics
mAlpha          = NaN(iNumChars, iNumBenchmark);% Alphas
mAlphaT         = NaN(iNumChars, iNumBenchmark);% t-statistics of alphas

% Sorts
for iIdxChar = 1:iNumChars     
    % Save characteristic name
    rOptionsTemp            = rOptions;
    rOptionsTemp.cVarNames  = cCharNames(iIdxChar);

    % Sort w.r.t. characteristic 
    rResults = fSingleSortMulti(mChars_L1(:,:,iIdxChar), mRetSort, vQuantiles, [], mME_L1', rOptionsTemp); 

    % Get time-series of portfolios
    if lUseValueWts
        mPortRet = rResults.VW.mPortRet';
    else
        mPortRet = rResults.EW.mPortRet';
    end

    % To make it comparable to CTREND factor performance, set the first
    % iNumIn observations to missing
    mPortRet(1:iNumIn,:)    = NaN;

    % Save portfolio time series
    mHedgePort(:,iIdxChar)  = mPortRet(:,end);

    % Average portfolio return
    mAvgRet(iIdxChar,:)     = mean(mPortRet,1,'omitmissing');
    [~,~,~,stats]           = ttest(mPortRet);
    mAvgRetT(iIdxChar,:)    = stats.tstat;

    % Loop over benchmark models
    for iIdxB = 1:iNumBenchmark
        % Get factors
        mFactTemp = cBenchmark{iIdxB,2};

        % Regression
        rRegResults                 = regstats(mHedgePort(:,iIdxChar), mFactTemp, 'linear', {'tstat'});
        mAlpha(iIdxChar, iIdxB)     = rRegResults.tstat.beta(1);
        mAlphaT(iIdxChar, iIdxB)    = rRegResults.tstat.t(1);
    end
end

% Save hedge portfolios
save('./Results/HedgePorts.mat','mHedgePort','vDates','cCharNames');

% Merge all results
mTableRets  = [mAvgRet, mAlpha] * 100;
mTableRetsT = round([mAvgRetT, mAlphaT],2);

% Create tables
cTable = [cCharNames(:), fAddStatistics( fMatrix2Cell(mTableRets, 2),...
    fMatrix2Cell(mTableRetsT, 2),...
    abs(mTableRetsT) >= 1.96)];

% Find technical indicators
cTechnicalIndicators = [{'rsi', 'stochRSI', 'stochK', 'stochD', 'cci'},...
    cellfun(@(x)['sma_',x,'d'],sprintfc('%i',[3,5,10,20,50,100,200]),'un',false),...
    {'macd', 'macd_diff_signal'},...
    cellfun(@(x)['volsma_',x,'d'],sprintfc('%i',[3,5,10,20,50,100,200]),'un',false),...
    {'volmacd', 'volmacd_diff_signal','chaikin'},...
    {'boll_low','boll_mid','boll_high','boll_width'}]';
lIsTechnicalIndicator = ismember(cCharNames, cTechnicalIndicators);

% Create column header
cColHeader = [{''}, replace(sprintfc('%i', 1:iNumPorts),{num2str(1),num2str(iNumPorts-1),num2str(iNumPorts)},{'L','H','H-L'}),...
    {'$\alpha^{CCAPM}$','$\alpha^{LTW}$'}];

% Create table 2    
cTable2             = cTable(lIsTechnicalIndicator,:);
rInput.table        = [cColHeader; cTable2];
rInput.tableCaption = 'Technical Indicator Strategy Returns';
fCreateLatexTable(rInput);

% Find anomalies to create B.8
lIsSignificant = abs(round(mAvgRetT(:,end),2)) >= 1.96;
lIsAnomaly     = (lIsSignificant | ismember(cCharNames,{'mcap','prc','maxdprc',...
    'ret_1_0','ret_2_0','ret_3_0','ret_4_0','ret_4_1',...
    'prcvol','volscaled','stdprcvol'})) & ~lIsTechnicalIndicator;
cTableB8 = cTable(lIsAnomaly,:);
rInput.table        = [cColHeader; cTableB8];
rInput.tableCaption = 'Anomaly Strategy Returns';
fCreateLatexTable(rInput);

% Find non-anomalies to create B.5
cTableB5 = cTable(~lIsAnomaly& ~lIsTechnicalIndicator,1:end-iNumBenchmark);
rInput.table        = [cColHeader(1:end-iNumBenchmark); cTableB5];
rInput.tableCaption = 'Insignificant Anomaly Strategy Returns';
fCreateLatexTable(rInput);

% Restore path
path(sOldPath);