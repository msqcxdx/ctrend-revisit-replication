% Script for analyzing the performance of the CTREND factor using bivariate
% sorts
%
% Requires that b05CreateCTREND and b06Table3_UnivariatePortfolioSorts 
% were executed
%
% This script produces:
%   Table B.3: Bivariate Portfolio Sorts

% Clear console
clear; clc; close all;

% Set paths
sOldPath    = path;
sDataPath   = './DATA/';
addpath('./Utils/');
addpath('./LatexTables/');

% Use LTW factors
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

% Other settings that are no design choices
iStartDate      = 201416;       
iEndDate        = 202222; 

% Define characteristics for which we perform double-sorts
cCharNames = {'beta', 'mcap', 'illiq','ivol', 'ret_1_0', 'ret_2_0', 'ret_3_0', 'ret_4_0'};

%% Analysis
% Find number of data setting
iIdxDataComb = tCombos.data_setting( find(strcmpi(tCombos.cOutlierTreatment, sOutlierTreatment) & ...
    tCombos.vThreshold == dThreshold,1,'first') );

% Load data
load([sDataPath,sprintf('bCharacteristicsOLHC_Combo%i.mat', iIdxDataComb)]);

% M2 removes realised-payoff conditioning and otherwise preserves M0's
% bivariate-sort design.
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

% Determine dimensions
[iNumObs, iNumAssets]   = size(mReturns);
iNumChars               = length(cCharNames);

% Lag characteristics and convert to matrix
mChars_L1 = NaN(iNumAssets, iNumObs, iNumChars);
for iIdxChar = 1:iNumChars
    mChars_L1(:,:,iIdxChar) = [NaN(1, iNumAssets); rChars.(cCharNames{iIdxChar})(1:end-1,:)]';
end

% Lag formation variables
mME_L1 = [NaN(1, iNumAssets); mME(1:end-1,:)];
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

% Load LTW factors
load('./DATA/LTW_3factor.mat','mLTW','vDatesLiu');
lIsSample           = vDatesLiu >= iStartDate & vDatesLiu <= iEndDate;
mLTW                = mLTW(lIsSample,:);

% Define benchmark models
cBenchmark{1,1} = ('CCAPM');        cBenchmark{1,2} = vMktRet;
cBenchmark{2,1} = ('LTW');          cBenchmark{2,2} = mLTW;
iNumBenchmark   = size(cBenchmark,1);

% Define return for sorting
if iRetLead == 0
    % No implementation lag
    mRetSort = mPnlReturns';
    sPayoffTiming = 'ordinary';
else
    % 1-day implementation lag
    mRetSort = mPnlReturnsLead';
    sPayoffTiming = 'lead1';
end
[rDoubleSortOptions,~,~] = fAttachEconomicLedgerOptions( ...
    struct(),sDataPath,rData,rMetaData.vID(:),vDates,sPayoffTiming);

% Match only formation-time support.  Future payoff availability is not a
% sorting variable and is handled fail-closed by the portfolio helper.
lIsNaN = isnan(rCTREND.mYhat) | isnan(mME_L1');

% Initialize memory
vQuantileB  = [0,0.33,0.66,1];
iNumPortsB  = length(vQuantileB);
mAvgRet     = NaN(iNumChars, iNumPortsB);
mAvgRetT    = NaN(iNumChars, iNumPortsB);
mAlpha      = NaN(iNumChars, iNumBenchmark);
mAlphaT     = NaN(iNumChars, iNumBenchmark);

for iIdxChar = 1:iNumChars
    % Get characteristic
    mCtemp = mChars_L1(:,:,iIdxChar);

    % Match missing values
    mCtemp(lIsNaN) = NaN;

    % Independent double sorts
    rResults = fIndepDoubleSort(mCtemp,rCTREND.mYhat,mRetSort,[],mME_L1',...
        'vPercentileA',0:0.5:1, ...
        'vPercentileB',vQuantileB, ...
        'rReinvestmentLedger',rDoubleSortOptions.rReinvestmentLedger, ...
        'vLedgerWeekRow',rDoubleSortOptions.vLedgerWeekRow, ...
        'sPayoffTiming',rDoubleSortOptions.sPayoffTiming);
    iNumPortsB = size(rResults.VW.cPortRets,2);

    % Get average portfolios
    mAvgPort = NaN(iNumObs, iNumPortsB);
    for iIdxB = 1:iNumPortsB-1
        % Get all portfolios
        mPortRet = vertcat(rResults.VW.cPortRets{1:end-1,iIdxB});

        % The two first-sort component portfolios have fixed equal weight.
        % If either realised component is unavailable, the aggregate is
        % unavailable; do not use future missingness to reweight it.
        mAvgPort(:,iIdxB) = mean(mPortRet,1)';
    end
    mAvgPort(:,end) = mAvgPort(:,end-1) - mAvgPort(:,1);

    % Average returns
    mAvgRet(iIdxChar,:) = mean(mAvgPort,1,'omitmissing');
    [~,~,~,stats] = ttest(mAvgPort);
    mAvgRetT(iIdxChar,:) = stats.tstat;

    % Regression on benchmark models
    for iIdxB = 1:iNumBenchmark
        % Get factors
        mFactTemp = cBenchmark{iIdxB,2};

        % Regression on CAPM
        rRegResults                = regstats(mAvgPort(:,end), mFactTemp, 'linear', 'tstat');
        mAlpha(iIdxChar,iIdxB)     = rRegResults.tstat.beta(1);
        mAlphaT(iIdxChar,iIdxB)    = rRegResults.tstat.t(1);
    end
end

% Create table
cTableB3 = fAddStatistics( fMatrix2Cell( [mAvgRet, mAlpha] * 100,2),...
    fMatrix2Cell( [mAvgRetT, mAlphaT], 2),...
    abs(round([mAvgRetT, mAlphaT],2)) >= 1.96);

% Create column header
cColHeader = [replace(sprintfc('%i', 1:iNumPortsB),{num2str(1),num2str(2),num2str(iNumPortsB-1),num2str(iNumPortsB)},{'L','M','H','H-L'}),...
    cellfun(@(x)['$\alpha^{',x,'}$'],cBenchmark(:,1)','UniformOutput',false)];
cTableB3 = [[{''}, cColHeader]; [cCharNames(:) cTableB3]];
rInput.table = cTableB3;
rInput.tableCaption = 'Bivariate Portfolio Sorts';
fCreateLatexTable(rInput);

% Restore path
path(sOldPath);
