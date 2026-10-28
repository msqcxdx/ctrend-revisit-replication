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
rOptions = struct();
rOptions.sFreq = 'weekly';                  % Data frequency
rOptions.lHedgeOnly = false;                 % Table 5 reports all quintiles
rOptions.iMinNumCS = 25;                    % Minimum cross section
rOptions.iMinNumAssets = 5;                 % Minimum assets per portfolio
rOptions.lEnsureAllObs = true;               % Ex-ante signal and cap support
vQuantiles      = (0:0.2:1)';                % Percentiles for sorts

% Other settings that are no design choices
iStartDate      = 201416;       
iEndDate        = 202222; 

%% Analysis
% Find number of data setting
iIdxDataComb = tCombos.data_setting( find(strcmpi(tCombos.cOutlierTreatment, sOutlierTreatment) & ...
    tCombos.vThreshold == dThreshold,1,'first') );

% Empty in a normal end-to-end run.  A sealed Table-5-only amendment must
% name the exact predecessor that produced both the weekly data and b05
% result; the exception never accepts an arbitrary or merely dimensionally
% compatible artifact.
sAllowedPredecessor = string(getenv( ...
    'CTTREND_TABLE5_PREDECESSOR_FINGERPRINT'));

% Load data
load([sDataPath,sprintf('bCharacteristicsOLHC_Combo%i.mat', iIdxDataComb)]);
if strlength(sAllowedPredecessor) == 0
    fAssertWeeklyDataProvenance(sDataBuildID, rInputProvenance, ...
        sWeeklyCodeFingerprint);
else
    fAssertWeeklyDataProvenance(sDataBuildID, rInputProvenance, ...
        sWeeklyCodeFingerprint,sAllowedPredecessor);
end

% Extract data from struct
mReturns        = rData.mReturns;
mReturnsLead    = rData.mRetLead;
mME             = rData.mME;
mPrices         = rData.mClose;
mVolume         = rData.mVolume;
vDates          = rData.yrmoda;
vMktRet         = rData.vMktRet;
% rData.vMktVol(w) is the value-weighted cross-sectional average of each
% asset's daily-return volatility realized within week w.  Lag it exactly
% once so the state used for return week t is fully known in week t-1.
vMktVol_L1      = [NaN; rData.vMktVol(1:end-1)];

% Portfolio weights are fixed from the preceding weekly boundary, exactly
% as in b05/b06.  These arrays are used only for formation; endpoint P&L is
% loaded separately from the saved strictly OOS CTREND result.
mME_L1          = [NaN(1,size(mME,2)); mME(1:end-1,:)];
mPrices_L1      = [NaN(1,size(mPrices,2)); mPrices(1:end-1,:)];

% Calculate 12-month market return 
iNumObs         = length(vMktRet);
iNumIn          = 52;
vMktRetPrior_L1 = NaN(iNumObs, 1);
parfor iIdxT = iNumIn+1:iNumObs
    % Get data
    vIdxInSample = (iIdxT-iNumIn):(iIdxT-1);
    vMktTemp     = vMktRet(vIdxInSample);

    % A 12-month trailing return requires all 52 weekly market returns;
    % treating a missing week as a zero return would silently shorten the
    % horizon. By saving this at t, the state is already lagged.
    if all(isfinite(vMktTemp))
        vMktRetPrior_L1(iIdxT) = prod(1 + vMktTemp)-1;
    end
end

% Determine dimensions
[iNumObs, iNumAssets]   = size(mReturns);
iNumPorts               = length(vQuantiles);

% Load the saved OOS CTREND signal, raw endpoint P&L, and hedge-only
% baseline portfolios.  b05 intentionally leaves the middle quintiles
% empty; Table 5 reconstructs only those missing consumer outputs.
sFilename = sprintf('./Results/CTREND/CTREND_Base.mat');
rCTREND   = load(sFilename,'mYhat','mRetPnlOOS','cResults','vDates','vAssetID', ...
    'sCodeFingerprint','sDataBuildID');

% Restrict to sample period
lIsSample                   = vDates >= iStartDate & vDates <= iEndDate;
mReturns(~lIsSample,:)      = [];
mReturnsLead(~lIsSample,:)  = [];
mVolume(~lIsSample,:)       = [];
mME_L1(~lIsSample,:)        = [];
mPrices_L1(~lIsSample,:)    = [];
vDates(~lIsSample)          = [];
vMktRet(~lIsSample)         = [];
vMktRetPrior_L1(~lIsSample) = [];
vMktVol_L1(~lIsSample)      = [];
iNumObs                     = length(vDates);
% Normal full runs require an exact whole-tree producer fingerprint.  A
% post-publication Table-5-only amendment may consume the already sealed b05
% result only when the operator supplies its exact predecessor fingerprint.
% This exception is intentionally local to this consumer and still enforces
% data-build, date, asset-order, and matrix alignment.
if strlength(sAllowedPredecessor) == 0
    fAssertCTRENDAlignment(rCTREND, vDates, rMetaData.vID(:), iNumAssets, ...
        sDataBuildID);
else
    iAssertSealedTable5Predecessor(rCTREND,vDates,rMetaData.vID(:), ...
        iNumAssets,sDataBuildID,sAllowedPredecessor);
    fprintf('table5_amendment predecessor_fingerprint=%s\n', ...
        sAllowedPredecessor);
end
assert(isequal(vDates(:), rCTREND.vDates(:)), ...
    'CTREND portfolio returns and state variables must have identical dates.');
assert(size(rCTREND.mYhat,2) == iNumObs, ...
    'CTREND signal columns must match the weekly sample.');

% Reapply the exact b05 formation filters to the lagged market-cap weights.
% Future payoff availability is deliberately absent from this mask.
lRemoveObs = ~isfinite(mME_L1) | ~isfinite(mPrices_L1) | ...
    (mME_L1 == 0) | (mME_L1 < dMinMCAP) | (mPrices_L1 < dMinPrc);
if lExclStable
    lRemoveObs = lRemoveObs | rMetaData.lIsStable;
end
mME_L1(lRemoveObs) = NaN;

if iRetLead == 0
    sPayoffTiming = 'ordinary';
else
    sPayoffTiming = 'lead1';
end
[rOptions,~,~] = fAttachEconomicLedgerOptions( ...
    rOptions,sDataPath,rData,rMetaData.vID(:),vDates,sPayoffTiming);

[mPortRet,rTable5PortfolioDiagnostics] = ...
    fBuildTable5PortfolioReturns(rCTREND.mYhat,rCTREND.mRetPnlOOS, ...
    mME_L1',rCTREND.cResults,vQuantiles,rOptions);
mPortRet = mPortRet';
assert(size(mPortRet,1) == iNumObs, ...
    'CTREND portfolio-return rows must match the weekly sample.');
assert(all(any(isfinite(mPortRet(:,2:4)),1)), ...
    'Table 5 middle quintiles were not reconstructed');
fprintf(['table5_portfolios finite_weeks=%s outer_exact=%d ' ...
    'source=OOS_signal_raw_endpoint_pnl\n'], ...
    mat2str(rTable5PortfolioDiagnostics.vFiniteWeeksByPortfolio'), ...
    rTable5PortfolioDiagnostics.lOuterRowsExact);

% Load LTW factors
load('./DATA/LTW_3factor.mat');
mLTW                = fAlignByDate(vDatesLiu, mLTW, vDates, 'LTW', 0.95);
vMktExcess          = mLTW(:,1);

%% Create state variables
% === Time split
% Find the first OOS formation date from ex-ante signals, not from future
% realized-return availability.
iIdxFirst       = find(any(isfinite(rCTREND.mYhat),1),1,'first');
assert(~isempty(iIdxFirst), 'No OOS CTREND signal is available.');
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

    % Get pseudo dates for 2013, otherwise resampling does not work. Use an
    % explicit locale-independent calendar construction.
    dtUCRYCalendar = (datetime(2013,12,31):caldays(1): ...
        tUCRY.Properties.RowTimes(end))';
    tUCRY = synchronize(tUCRY, dtUCRYCalendar);

    % Get data
    vUCRY_day       = tUCRY.UCRYPriceIndex;
    dtUCRYDay       = tUCRY.Properties.RowTimes;
    vDateUCRY_day   = year(dtUCRYDay)*10000 + month(dtUCRYDay)*100 + ...
        day(dtUCRYDay);

    % Resample UCRY to LTW data frequency
    [vUCRY, vDateUCRY] = fResampleLiuEtAl(vUCRY_day, vDateUCRY_day, ...
        'sMethod', 'last', 'iMinNumObs',1);

    % Lag index
    vUCRY = [NaN; vUCRY(1:end-1)];

    % Align to the main weekly sample
    vUCRY       = fAlignByDate(vDateUCRY, vUCRY, vDates, 'UCRY', 0.95);
    % Match the other state variables' scheduled OOS support. Otherwise the
    % full-sample UCRY median would also use warm-up weeks in which no CTREND
    % portfolio could have been formed.
    vUCRY(1:iIdxFirst-1) = NaN;
else
    error('Cryptocurrency uncertainty index does not exist. Download UCRY.csv before running this script.');
end

% Merge all state variables
mStateVars      = [vStateVarTime, vMktVol_L1, vUCRY, vMktRetPrior_L1];
iNumStateVars   = size(mStateVars,2);

% Initialize memory
mAvgRet     = NaN(2, iNumStateVars, iNumPorts);
mAvgRetT    = NaN(2, iNumStateVars, iNumPorts);
mAlpha      = NaN(2, iNumStateVars, 2);
mAlphaT     = NaN(2, iNumStateVars, 2);
parfor iIdxS = 1:iNumStateVars
    mAvgRetTemp  = NaN(2, iNumPorts);
    mAvgRetTTemp = NaN(2, iNumPorts);
    mAlphaTemp   = NaN(2, 2);
    mAlphaTTemp  = NaN(2, 2);

    % Get state variable
    vStateVar = mStateVars(:,iIdxS);
    dMedian   = median(vStateVar,'omitmissing');

    % Median split
    lIsFirst  = vStateVar <= dMedian;
    lIsSecond = vStateVar > dMedian;

    % Calculate average returns
    mAvgRetTemp(1,:) = mean(mPortRet(lIsFirst,:),1,'omitmissing');
    mAvgRetTemp(2,:) = mean(mPortRet(lIsSecond,:),1,'omitmissing');

    % Calculate t-statistics
    [~,~,~,stats]       = ttest(mPortRet(lIsFirst,:));
    mAvgRetTTemp(1,:)  = stats.tstat;
    [~,~,~,stats]       = ttest(mPortRet(lIsSecond,:));
    mAvgRetTTemp(2,:)  = stats.tstat;

    % Calculate the CAPM alphas
    [vBetaTemp, vTstatTemp] = fRegstatsTstatSafe(mPortRet(lIsFirst,end),vMktExcess(lIsFirst,:));
    mAlphaTemp(1, 1)        = vBetaTemp(1);
    mAlphaTTemp(1, 1)       = vTstatTemp(1);
    [vBetaTemp, vTstatTemp] = fRegstatsTstatSafe(mPortRet(lIsSecond,end),vMktExcess(lIsSecond,:));
    mAlphaTemp(2, 1)        = vBetaTemp(1);
    mAlphaTTemp(2, 1)       = vTstatTemp(1);

    % Calculate the LTW alphas
    [vBetaTemp, vTstatTemp] = fRegstatsTstatSafe(mPortRet(lIsFirst,end),mLTW(lIsFirst,:));
    mAlphaTemp(1, 2)        = vBetaTemp(1);
    mAlphaTTemp(1, 2)       = vTstatTemp(1);
    [vBetaTemp, vTstatTemp] = fRegstatsTstatSafe(mPortRet(lIsSecond,end),mLTW(lIsSecond,:));
    mAlphaTemp(2, 2)        = vBetaTemp(1);
    mAlphaTTemp(2, 2)       = vTstatTemp(1);

    mAvgRet(:,iIdxS,:)      = reshape(mAvgRetTemp, 2, 1, iNumPorts);
    mAvgRetT(:,iIdxS,:)     = reshape(mAvgRetTTemp, 2, 1, iNumPorts);
    mAlpha(:,iIdxS,:)       = reshape(mAlphaTemp, 2, 1, 2);
    mAlphaT(:,iIdxS,:)      = reshape(mAlphaTTemp, 2, 1, 2);
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
    abs(mAvgRetT)>= 1.96);
cTable5 = [cColHeader; [cRowHeader, cTable5]];
rInput.table = cTable5;
rInput.tableCaption = 'Performance in Subperiods and Different Market States';
fCreateLatexTable(rInput);

% Restore path
path(sOldPath);

function iAssertSealedTable5Predecessor(rCTREND,vDates,vAssetID, ...
        iNumAssets,sExpectedDataBuildID,sAllowedPredecessor)
cRequired = {'sCodeFingerprint','sDataBuildID','vDates','vAssetID', ...
    'mYhat','mRetPnlOOS','cResults'};
assert(all(isfield(rCTREND,cRequired)), ...
    'The sealed Table-5 predecessor lacks required fields');
assert(strcmp(char(rCTREND.sCodeFingerprint), ...
              char(sAllowedPredecessor)), ...
    'The b05 dependency does not match the authorized predecessor fingerprint');
assert(strcmp(char(rCTREND.sDataBuildID), ...
              char(sExpectedDataBuildID)), ...
    'The b05 dependency and weekly input use different data builds');
assert(isequal(vDates(:),rCTREND.vDates(:)) && ...
       isequal(vAssetID(:),rCTREND.vAssetID(:)), ...
    'The b05 dependency does not match the Table-5 date/asset axes');
assert(size(rCTREND.mYhat,1) == iNumAssets && ...
       size(rCTREND.mYhat,2) == numel(vDates) && ...
       isequal(size(rCTREND.mRetPnlOOS),size(rCTREND.mYhat)), ...
    'The b05 dependency does not match the Table-5 matrix dimensions');
end
