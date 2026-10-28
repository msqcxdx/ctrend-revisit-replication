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

% Extract data from struct
mReturns        = rData.mReturns;
mReturnsLead    = rData.mRetLead;
mME             = rData.mME;
mPrices         = rData.mClose;
mVolume         = rData.mVolume;
vDates          = rData.yrmoda;
vMktRet         = rData.vMktRet;
lIsCoin         = rMetaData.lIsCoin;

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

% Determine dimensions
[iNumObs, iNumAssets]   = size(mReturns);
iNumChars               = length(cExclVar);

% Lag characteristics and convert to matrix
mChars_L1   = NaN(iNumAssets, iNumObs, iNumChars);
for iIdxChar = 1:iNumChars
    % Lag characteristic
    mCtemp = [NaN(1, iNumAssets); rChars.(cExclVar{iIdxChar})(1:end-1,:)]';
    mChars_L1(:,:,iIdxChar) = mCtemp;
end 

% Lag market equity
mME_L1 = [NaN(1, iNumAssets); mME(1:end-1,:)];   

% Load aggregate trend characteristic
sFilename = sprintf('./Results/CTREND/CTREND_Base.mat');
rCTREND   = load(sFilename, 'mYhat','cResults','vDates','vAssetID');

% Restrict to sample period
lIsSample                   = vDates >= iStartDate & vDates <= iEndDate;
mReturns(~lIsSample,:)      = [];
mReturnsLead(~lIsSample,:)  = [];
mVolume(~lIsSample,:)       = [];
mME_L1(~lIsSample,:)        = [];
mChars_L1(:,~lIsSample,:)   = [];
mME(~lIsSample,:)           = [];
vDates(~lIsSample)          = [];
vMktRet(~lIsSample)         = [];
iNumObs                     = length(vDates);

% Load LTW factors
load('./DATA/LTW_3factor.mat');
lIsSample           = vDatesLiu >= iStartDate & vDatesLiu <= iEndDate;
mLTW                = mLTW(lIsSample,:);

% Define benchmark models
cBenchmark(1,1) = {'CCAPM'};        cBenchmark{1,2} = vMktRet;
cBenchmark(2,1) = {'LTW'};          cBenchmark{2,2} = mLTW;
iNumBenchmark   = size(cBenchmark,1);

% Initialize memory
mAvgRet   = NaN(iNumPorts, iNumExclCombos);
mAvgRetT  = NaN(iNumPorts, iNumExclCombos);
mAlpha    = NaN(iNumBenchmark, iNumExclCombos);
mAlphaT   = NaN(iNumBenchmark, iNumExclCombos);

% Loop over samples
for iIdxS = 1:iNumExclCombos
    % Get setting
    sExclVar        = tExclCombos.cExclVar{iIdxS};
    dExclThreshold  = tExclCombos.dExclThreshold(iIdxS);

    % Define return for sorting (and copy it)
    if iRetLead == 0
        % No implementation lag
        mRetSort = mReturns';
    else
        % 1-day implementation lag
        mRetSort = mReturnsLead';
    end

    % Get exclusion variable
    mExclChar = mChars_L1(:,:,strcmp(cExclVar,sExclVar));
    if strcmp(sExclVar,'illiq')
        mExclChar = -mExclChar;
    end
    mExclChar(isnan(mRetSort)) = NaN;

    % Calculate minimum value to be included in sample
    if dExclThreshold == floor(dExclThreshold)
        % Integer, number of assets
        vMinValue = min(maxk(mExclChar,dExclThreshold,1),[],1);
        lExclude  = mExclChar < vMinValue;
    else
        vMinValue = quantile(mExclChar,1-dExclThreshold,1);
        lExclude  = mExclChar <= vMinValue;
    end

    % Set all returns to missing if below variable
    mRetSort(lExclude) = NaN;

    % Sort w.r.t. characteristic 
    rResults = fSingleSortMulti(rCTREND.mYhat, mRetSort, vQuantiles, [], mME_L1', rOptions); 

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
cTable8 = fAddStatistics( fMatrix2Cell( [mAvgRet;mAlpha] * 100,2),...
    fMatrix2Cell( [mAvgRetT;mAlphaT], 2),...
    abs(round([mAvgRetT;mAlphaT],2)) >= 1.96);

% Create column header
vThresholds             = unique(tExclCombos.dExclThreshold,'stable'); 
vThresholds(1:end-1)    = vThresholds(1:end-1) * 100;
cColHeader = cellfun(@(x)[x,'\%'],sprintfc('%i',vThresholds),'un',false)';
cRowHeader = [replace(sprintfc('%i', 1:iNumPorts),{num2str(1),num2str(iNumPorts-1),num2str(iNumPorts)},{'L','H','H-L'}),...
    {'$\alpha^{CCAPM}$','$\alpha^{LTW}$'}]';

% Merge
cTable8 = [[{''},repmat(cColHeader,1,length(unique(tExclCombos.cExclVar)))]; [cRowHeader, cTable8]];
rInput.table        = cTable8;
rInput.tableCaption = 'The CTREND Factor Performance in Big and Liquid Cryptocurrencies';
fCreateLatexTable(rInput);

% Restore path
path(sOldPath);