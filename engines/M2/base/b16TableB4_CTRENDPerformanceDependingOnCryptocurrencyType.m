% Script for analyzing the performance of the CTREND factor depending on
% cryptocurrency type
%
% Requires that b05CreateCTREND and b06Table3_UnivariatePortfolioSorts 
% were executed
%
% This script produces:
%   Table B4:   CTREND Performance Depending on Cryptocurrency Type

% Clear console
clear; clc; close all;

% Set paths
sOldPath    = path;
sDataPath   = './DATA/';
addpath('./Utils/');
addpath('./LatexTables/');

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

% M2 payoff is not transformed by its own realised cross-section.
assert(isfield(rData,'mReturnsM2Raw') && isfield(rData,'mRetLeadM2Raw') && ...
    isfield(rData,'mPnlReturnsM2') && isfield(rData,'mPnlRetLeadM2'), ...
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
lIsCoin         = rMetaData.lIsCoin;

% Determine dimensions
iNumAssets = size(mReturns,2);

% Lag formation variables
mME_L1     = [NaN(1, iNumAssets); mME(1:end-1,:)];
mPrices_L1 = [NaN(1, iNumAssets); mPrices(1:end-1,:)];

% Load aggregate trend characteristic
sFilename = sprintf('./Results/CTREND/CTREND_Base.mat');
rCTREND   = load(sFilename, 'mYhat','cResults','vDates','vAssetID');

% Restrict to sample period
lIsSample                   = vDates >= iStartDate & vDates <= iEndDate;
mReturns(~lIsSample,:)      = [];
mReturnsLead(~lIsSample,:)  = [];
mPnlReturns(~lIsSample,:) = [];
mPnlReturnsLead(~lIsSample,:) = [];
mVolume(~lIsSample,:)       = [];
mME_L1(~lIsSample,:)        = [];
mPrices_L1(~lIsSample,:)    = [];
mME(~lIsSample,:)           = [];
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

% Load LTW factors
load('./DATA/LTW_3factor.mat','mLTW','vDatesLiu');
lIsSample           = vDatesLiu >= iStartDate & vDatesLiu <= iEndDate;
mLTW                = mLTW(lIsSample,:);

% Define benchmark models
cBenchmark(1,1) = {'CCAPM'};        cBenchmark{1,2} = vMktRet;
cBenchmark(2,1) = {'LTW'};          cBenchmark{2,2} = mLTW;
iNumBenchmark   = size(cBenchmark,1);

% Define samples
cSamples    = {'Full', 'Coins', 'Tokens'};
iNumSamples = length(cSamples);

% Initialize memory
mAvgRet   = NaN(iNumPorts, iNumSamples);
mAvgRetT  = NaN(iNumPorts, iNumSamples);
mAlpha    = NaN(iNumBenchmark, iNumSamples);
mAlphaT   = NaN(iNumBenchmark, iNumSamples);

% Loop over samples
for iIdxS = 1:iNumSamples
    % Define return for sorting (and copy it)
    if iRetLead == 0
        % No implementation lag
        mRetSort = mPnlReturns';
        sPayoffTiming = 'ordinary';
    else
        % 1-day implementation lag
        mRetSort = mPnlReturnsLead';
        sPayoffTiming = 'lead1';
    end
    [rOptionsSort,~,~] = fAttachEconomicLedgerOptions( ...
        rOptions,sDataPath,rData,rMetaData.vID(:),vDates,sPayoffTiming);

    % Get sample
    switch upper(cSamples{iIdxS})
        case 'FULL'
            lInclude = true(1, iNumAssets);
        case 'COINS'
            lInclude = lIsCoin;
        case 'TOKENS'
            lInclude = ~lIsCoin;
        otherwise
            error('Unknown sample')
    end
    % Encode the named type sample at formation.  Do not use a missing
    % payoff cell as the device that determines whether an asset belonged
    % to the portfolio universe.
    mSignalSort = rCTREND.mYhat;
    mMESort = mME_L1';
    mSignalSort(~lInclude,:) = NaN;
    mMESort(~lInclude,:) = NaN;

    % Sort w.r.t. characteristic 
    rResults = fSingleSortMulti(mSignalSort, mRetSort, vQuantiles, [], ...
        mMESort, rOptionsSort);

    % Get time-series of portfolios
    if lUseValueWts
        mPortRet = rResults.VW.mPortRet';
    else
        mPortRet = rResults.EW.mPortRet';
    end

    % Average portfolio return
    mAvgRet(:,iIdxS)        = mean(mPortRet,1,'omitmissing')';
    [~,~,~,stats]           = ttest(mPortRet);
    mAvgRetT(:,iIdxS)       = stats.tstat';

    % Regression on benchmark models
    for iIdxB = 1:iNumBenchmark
        % Get factors
        mFactTemp = cBenchmark{iIdxB,2};

        % Regression on CAPM
        rRegResults             = regstats(mPortRet(:,end), mFactTemp, 'linear', {'tstat'});
        mAlpha(iIdxB,iIdxS)     = rRegResults.tstat.beta(1);
        mAlphaT(iIdxB,iIdxS)    = rRegResults.tstat.t(1);
    end
end
% Create table
cTableB4 = fAddStatistics( fMatrix2Cell( [mAvgRet;mAlpha] * 100,2),...
    fMatrix2Cell( [mAvgRetT;mAlphaT], 2),...
    abs(round([mAvgRetT;mAlphaT],2)) >= 1.96);
cRowHeader = [replace(sprintfc('%i', 1:iNumPorts),{num2str(1),num2str(iNumPorts-1),num2str(iNumPorts)},{'L','H','H-L'}),...
    cellfun(@(x)['$\alpha^{',x,'}$'],cBenchmark(:,1)','UniformOutput',false)];
rInput.table = [[{''}, cSamples]; [cRowHeader(:) cTableB4]];
rInput.tableCaption = 'CTREND Performance Depending on Cryptocurrency Type';
fCreateLatexTable(rInput);

% Restore path
path(sOldPath);
