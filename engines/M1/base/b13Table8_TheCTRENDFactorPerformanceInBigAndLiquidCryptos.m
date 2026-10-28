% Script for analyzing the performance of the CTREND factor depending on
% small and illiquid coins
%
% Requires that b05CreateCTREND and b06Table3_UnivariatePortfolioSorts 
% were executed
%
% This script produces:
%   Table 8: The CTREND Factor Performance in Big and Liquid Cryptocurrencies

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

% Create grid of variables and thresholds. The thresholds indicate the
% fraction of crytocurrencies to keep. An integer means that only this
% exact number is included, e.g., the largest 100
cExclVar        = {'mcap', 'illiq'};
dExclThreshold  = [0.5, 0.3, 0.2, 0.1, 100];
tExclCombos     = combinations(cExclVar, dExclThreshold);
iNumExclCombos  = size(tExclCombos,1);

%% Analysis
% Find number of data setting
iIdxDataComb = tCombos.data_setting( find(strcmpi(tCombos.cOutlierTreatment, sOutlierTreatment) & ...
    tCombos.vThreshold == dThreshold,1,'first') );

% Load data
load([sDataPath,sprintf('bCharacteristicsOLHC_Combo%i.mat', iIdxDataComb)]);
fAssertWeeklyDataProvenance(sDataBuildID, rInputProvenance, ...
    sWeeklyCodeFingerprint);

% Extract data from struct
mReturns        = rData.mReturns;
mReturnsLead    = rData.mRetLead;
mME             = rData.mME;
mPrices         = rData.mClose;
mVolume         = rData.mVolume;
vDates          = rData.yrmoda;
vMktRet         = rData.vMktRet;
vRiskFree       = rData.vRiskFree;
lIsCoin         = rMetaData.lIsCoin;

% Determine dimensions
[iNumObs, iNumAssets]   = size(mReturns);
iNumChars               = length(cExclVar);

% Lag characteristics and convert to matrix
mChars_L1   = NaN(iNumAssets, iNumObs, iNumChars);
parfor iIdxChar = 1:iNumChars
    % Lag characteristic
    mCtemp = [NaN(1, iNumAssets); rChars.(cExclVar{iIdxChar})(1:end-1,:)]';
    mChars_L1(:,:,iIdxChar) = mCtemp;
end 

% Lag market equity
mME_L1 = [NaN(1, iNumAssets); mME(1:end-1,:)];   
mPrices_L1 = [NaN(1, iNumAssets); mPrices(1:end-1,:)];

% Load aggregate trend characteristic
sFilename = sprintf('./Results/CTREND/CTREND_Base.mat');
rCTREND   = load(sFilename, 'mYhat','mRetPnlOOS','cResults','vDates','vAssetID', ...
    'sCodeFingerprint','sDataBuildID');

% Restrict to sample period
lIsSample                   = vDates >= iStartDate & vDates <= iEndDate;
mReturns(~lIsSample,:)      = [];
mReturnsLead(~lIsSample,:)  = [];
mVolume(~lIsSample,:)       = [];
mME_L1(~lIsSample,:)        = [];
mPrices_L1(~lIsSample,:)    = [];
mChars_L1(:,~lIsSample,:)   = [];
mME(~lIsSample,:)           = [];
vDates(~lIsSample)          = [];
vMktRet(~lIsSample)         = [];
vRiskFree(~lIsSample)       = [];
iNumObs                     = length(vDates);
fAssertCTRENDAlignment(rCTREND, vDates, rMetaData.vID(:), iNumAssets, ...
    sDataBuildID);
[rOptions,~,~] = fAttachEconomicLedgerOptions( ...
    rOptions,sDataPath,rData,rMetaData.vID(:),vDates,'ordinary');

mReturnsRaw                 = mReturns;
mReturnsLeadRaw             = mReturnsLead;

% Apply ex-ante market capitalization, price, and stablecoin filters
lRemoveObs                  = ~isfinite(mME_L1) | ~isfinite(mPrices_L1) | ...
                              (mME_L1 == 0) | (mME_L1 < dMinMCAP) | (mPrices_L1 < dMinPrc);
if lExclStable
    lRemoveObs              = lRemoveObs | rMetaData.lIsStable;
end
% Preserve the formation-time eligibility mask before applying it to
% realized-return/accounting arrays.  Table 8's top-size/top-liquidity
% universe must be built from eligible assets only; otherwise an ineligible
% high-score asset can displace an eligible asset at the cutoff.  Future
% payoff availability is deliberately absent from this mask.
lFormationEligible          = ~lRemoveObs;
mReturns(lRemoveObs)        = NaN;
mReturnsLead(lRemoveObs)    = NaN;
mReturnsRaw(lRemoveObs)     = NaN;
mReturnsLeadRaw(lRemoveObs) = NaN;
mME_L1(lRemoveObs)          = NaN;

% Load LTW factors
load('./DATA/LTW_3factor.mat');
mLTW                = fAlignByDate(vDatesLiu, mLTW, vDates, 'LTW', 0.95);

% Define benchmark models
cBenchmark(1,1) = {'CCAPM'};        cBenchmark{1,2} = mLTW(:,1);
cBenchmark(2,1) = {'LTW'};          cBenchmark{2,2} = mLTW;
iNumBenchmark   = size(cBenchmark,1);

% Initialize memory
mAvgRet   = NaN(iNumPorts, iNumExclCombos);
mAvgRetT  = NaN(iNumPorts, iNumExclCombos);
mAlpha    = NaN(iNumBenchmark, iNumExclCombos);
mAlphaT   = NaN(iNumBenchmark, iNumExclCombos);

% Loop over samples
parfor iIdxS = 1:iNumExclCombos
    % Get setting
    sExclVar        = tExclCombos.cExclVar{iIdxS};
    dExclThreshold  = tExclCombos.dExclThreshold(iIdxS);

    % The selected implementation lag is already embedded upstream in the
    % saved raw OOS P&L panel; do not pretend to select it a second time.
    mRetSort = rCTREND.mRetPnlOOS;

    % Get exclusion variable
    mExclChar = mChars_L1(:,:,strcmp(cExclVar,sExclVar));
    if strcmp(sExclVar,'illiq')
        mExclChar = -mExclChar;
    end
    % Build the ex-ante big/liquid universe period-by-period. Missing
    % scores are excluded; if fewer than K assets are available in a Top-K
    % rule, all available assets are retained.
    lUniverse = fBuildTopUniverse( ...
        mExclChar,dExclThreshold,lFormationEligible');

    % Restrict breakpoints, membership, and weights to this subsample.
    rOptionsTemp = rOptions;
    rOptionsTemp.mUniverse = lUniverse;

    % Sort w.r.t. characteristic 
    rResults = fSingleSortMulti(rCTREND.mYhat, mRetSort, vQuantiles, [], mME_L1', rOptionsTemp); 

    % Get time-series of portfolios
    if lUseValueWts
        mPortRet = rResults.VW.mPortRet';
    else
        mPortRet = rResults.EW.mPortRet';
    end

    % Average portfolio return
    vAvgRetTemp             = mean(mPortRet,1,'omitmissing')';
    [~,~,~,stats]           = ttest(mPortRet);
    vAvgRetTTemp            = stats.tstat';
    vAlphaTemp              = NaN(iNumBenchmark, 1);
    vAlphaTTemp             = NaN(iNumBenchmark, 1);

    % Regression on benchmark models
    for iIdxB = 1:iNumBenchmark
        % Get factors
        mFactTemp = cBenchmark{iIdxB,2};

        % Regression on factor model
        [vBetaTemp, vTstatTemp] = fRegstatsTstatSafe(mPortRet(:,end), mFactTemp);
        vAlphaTemp(iIdxB)       = vBetaTemp(1);
        vAlphaTTemp(iIdxB)      = vTstatTemp(1);
    end
    mAvgRet(:,iIdxS)        = vAvgRetTemp;
    mAvgRetT(:,iIdxS)       = vAvgRetTTemp;
    mAlpha(:,iIdxS)         = vAlphaTemp;
    mAlphaT(:,iIdxS)        = vAlphaTTemp;
end

% Create table
cTable8 = fAddStatistics( fMatrix2Cell( [mAvgRet;mAlpha] * 100,2),...
    fMatrix2Cell( [mAvgRetT;mAlphaT], 2),...
    abs([mAvgRetT;mAlphaT]) >= 1.96);

% Create column header
vThresholds             = unique(tExclCombos.dExclThreshold,'stable'); 
cColHeader = cell(numel(vThresholds),1);
for iIdxThreshold = 1:numel(vThresholds)
    if vThresholds(iIdxThreshold) < 1
        cColHeader{iIdxThreshold} = sprintf('%g\\%%',100*vThresholds(iIdxThreshold));
    else
        cColHeader{iIdxThreshold} = sprintf('Top %i',vThresholds(iIdxThreshold));
    end
end
cRowHeader = [replace(sprintfc('%i', 1:iNumPorts),{num2str(1),num2str(iNumPorts-1),num2str(iNumPorts)},{'L','H','H-L'}),...
    {'$\alpha^{CCAPM}$','$\alpha^{LTW}$'}]';

% Merge. cColHeader is built as a column for convenient indexed assignment,
% but the LaTeX table needs one horizontal block per exclusion variable.
cTable8 = [[{''},repmat(cColHeader',1, ...
    length(unique(tExclCombos.cExclVar)))]; [cRowHeader, cTable8]];
rInput.table        = cTable8;
rInput.tableCaption = 'The CTREND Factor Performance in Big and Liquid Cryptocurrencies';
fCreateLatexTable(rInput);

% Restore path
path(sOldPath);
