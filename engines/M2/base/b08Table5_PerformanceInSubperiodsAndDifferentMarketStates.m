% Script for analyzing the performance of the CTREND factor in subperiods
% and different market states. Requires that the script b05CreateCTREND and
% b06Table3_UnivariatePortfolioSorts were executed
%
% Requires that b05CreateCTREND and b06Table3_UnivariatePortfolioSorts 
% were executed
%
% This script produces:
%   Table 5:    Performance in Subperiods and Different Market States

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
vQuantiles      = 0:0.2:1;                  % Percentiles for sorts

% Other settings that are no design choices
iStartDate      = 201416;       
iEndDate        = 202222; 

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
vMktVol_L1      = [NaN; rData.vMktVol(1:end-1)];

% Calculate 12-month market return 
iNumObs         = length(vMktRet);
iNumIn          = 52;
vMktRetPrior_L1 = NaN(iNumObs, 1);
for iIdxT = iNumIn:iNumObs-1
    % Get data
    vIdxInSample = (iIdxT-iNumIn+1):iIdxT;
    vMktTemp     = vMktRet(vIdxInSample);

    % Calculate cumulative market return. By saving this at position
    % t+1, the proxy for sentiment is already lagged
    vMktRetPrior_L1(iIdxT+1) = prod(1 + vMktTemp, 'omitnan')-1;
end

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
iNumPorts               = length(vQuantiles);

% Load CTREND factor and quintile portfolios
sFilename = sprintf('./Results/CTREND/CTREND_Base.mat');
rCTREND   = load(sFilename,'cResults','mYhat','vDates','vAssetID');
mPortRet  = rCTREND.cResults.VW.mPortRet';

% Restrict to sample period
lIsSample                   = vDates >= iStartDate & vDates <= iEndDate;
mReturns(~lIsSample,:)      = [];
mReturnsLead(~lIsSample,:)  = [];
mVolume(~lIsSample,:)       = [];
vDates(~lIsSample)          = [];
vMktRet(~lIsSample)         = [];
vMktRetPrior_L1(~lIsSample) = [];
vMktVol_L1(~lIsSample)      = [];
iNumObs                     = length(vDates);

% Load LTW factors
load('./DATA/LTW_3factor.mat');
lIsSample           = vDatesLiu >= iStartDate & vDatesLiu <= iEndDate;
mLTW                = mLTW(lIsSample,:);

%% Create state variables
% === Time split
% Find the first OOS formation date from the ex-ante CTREND signal.  Future
% realized-payoff availability must not determine the state-variable sample
% boundary in the look-ahead-only method.
assert(size(rCTREND.mYhat,2) == size(mPortRet,1), ...
    'CTREND signal and portfolio-return calendars must be aligned.');
iIdxFirst       = find(any(~isnan(rCTREND.mYhat),1),1,'first');
assert(~isempty(iIdxFirst), 'No OOS CTREND formation signal is available.');
iNumNonMissing  = size(mPortRet, 1) - iIdxFirst;

% Create index vector
vStateVarTime   = [NaN(iIdxFirst-1,1); (1:iNumNonMissing+1)'];

% === Market volatility
vMktVol_L1(1:iIdxFirst-1) = NaN;

% === Past market performance
vMktRetPrior_L1(1:iIdxFirst-1) = NaN;

% === Cryptocurrency uncertainty index
% https://sites.google.com/view/cryptocurrency-indices/the-indices/crypto-uncertainty
if exist('./DATA/UCRY.csv','file')
    % Read data
    tUCRY = readtimetable('./DATA/UCRY.csv');

    % Insert non-business days by duplicating the previous value.
    % Cryptocurrencies are traded on seven days a week
    tUCRY = retime(tUCRY,'daily','previous');

    % Get pseudo data for 2013, otherwise resampling does not work
    tUCRY = synchronize(tUCRY, datetime('31.12.2013'):tUCRY.Properties.RowTimes(end));

    % Get data
    vUCRY_day       = tUCRY.UCRYPriceIndex;
    vDateUCRY_day   = str2num(datestr(tUCRY.Properties.RowTimes,'YYYYmmdd'));

    % Resample UCRY to LTW data frequency
    [vUCRY, vDateUCRY] = fResampleLiuEtAl(vUCRY_day, vDateUCRY_day, ...
        'sMethod', 'last', 'iMinNumObs',1);

    % Lag index
    vUCRY = [NaN; vUCRY(1:end-1)];

    % Restrict to sample period
    lIsSample   = vDateUCRY >= iStartDate & vDateUCRY <= iEndDate;
    vUCRY       = vUCRY(lIsSample);
    vDateUCRY   = vDateUCRY(lIsSample);
else
    warning('Cryptocurrency uncertainty index does not exist');
    vUCRY = NaN(iNumObs,1);
end

% Merge all state variables
mStateVars      = [vStateVarTime, vMktVol_L1, vUCRY, vMktRetPrior_L1];
iNumStateVars   = size(mStateVars,2);

% Initialize memory
mAvgRet     = NaN(2, iNumStateVars, iNumPorts);
mAvgRetT    = NaN(2, iNumStateVars, iNumPorts);
mAlpha      = NaN(2, iNumStateVars, 2);
mAlphaT     = NaN(2, iNumStateVars, 2);
for iIdxS = 1:iNumStateVars
    % Get state variable
    vStateVar = mStateVars(:,iIdxS);
    dMedian   = median(vStateVar,'omitmissing');

    % Median split
    lIsFirst  = vStateVar <= dMedian;
    lIsSecond = vStateVar > dMedian;

    % Calculate average returns
    mAvgRet(1,iIdxS,:) = mean(mPortRet(lIsFirst,:),1,'omitmissing');
    mAvgRet(2,iIdxS,:) = mean(mPortRet(lIsSecond,:),1,'omitmissing');

    % Calculate t-statistics
    [~,~,~,stats]       = ttest(mPortRet(lIsFirst,:));
    mAvgRetT(1,iIdxS,:) = stats.tstat;
    [~,~,~,stats]       = ttest(mPortRet(lIsSecond,:));
    mAvgRetT(2,iIdxS,:) = stats.tstat;

    % Calculate the CAPM alphas
    rRegResults             = regstats(mPortRet(lIsFirst,end),vMktRet(lIsFirst,:),'linear','tstat');
    mAlpha(1, iIdxS, 1)     = rRegResults.tstat.beta(1);
    mAlphaT(1, iIdxS, 1)    = rRegResults.tstat.t(1);
    rRegResults             = regstats(mPortRet(lIsSecond,end),vMktRet(lIsSecond,:),'linear','tstat');
    mAlpha(2, iIdxS, 1)     = rRegResults.tstat.beta(1);
    mAlphaT(2, iIdxS, 1)    = rRegResults.tstat.t(1);

    % Calculate the LTW alphas
    rRegResults             = regstats(mPortRet(lIsFirst,end),mLTW(lIsFirst,:),'linear','tstat');
    mAlpha(1, iIdxS, 2)     = rRegResults.tstat.beta(1);
    mAlphaT(1, iIdxS, 2)    = rRegResults.tstat.t(1);
    rRegResults             = regstats(mPortRet(lIsSecond,end),mLTW(lIsSecond,:),'linear','tstat');
    mAlpha(2, iIdxS, 2)     = rRegResults.tstat.beta(1);
    mAlphaT(2, iIdxS, 2)    = rRegResults.tstat.t(1);
end

% === Create LaTeX tables

% Reshape
mAvgRet     = reshape(cat(3,mAvgRet, mAlpha),2*iNumStateVars, iNumPorts+2);
mAvgRetT    = reshape(cat(3,mAvgRetT, mAlphaT),2*iNumStateVars, iNumPorts+2);

% Create row headers
cRowHeader = {'First half'; 'Second half';...
    'Low volatility'; 'High volatility';...
    'Low uncertainty'; 'High uncertainty';...
    'Bear market'; 'Bull market'};

% Create column header
cColHeader = [{''}, replace(sprintfc('%i', 1:iNumPorts),{num2str(1),num2str(iNumPorts-1),num2str(iNumPorts)},{'L','H','H-L'}),...
    {'$\alpha^{CCAPM}$','$\alpha^{LTW}$'}];

% Create table
cTable5 = fAddStatistics( fMatrix2Cell(mAvgRet * 100, 2),...
    fMatrix2Cell(mAvgRetT,2),...
    abs(round(mAvgRetT,2))>= 1.96);
cTable5 = [cColHeader; [cRowHeader, cTable5]];
rInput.table = cTable5;
rInput.tableCaption = 'Performance in Subperiods and Different Market States';
fCreateLatexTable(rInput);

% Restore path
path(sOldPath);
