% Script for analyzing the performance of the CTREND factor using extended
% portfolio holding periods
%
% Requires that b05CreateCTREND and b06Table3_UnivariatePortfolioSorts 
% were executed
%
% This script produces:
%   Table B10:  Extended Portfolio Holding Periods

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
lUseValueWts        = true;     % Use value-weighted factor portfolios

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

% Define number of holding periods
vNumHoldingPeriods = 1:6;
iNumHoldingPeriods = length(vNumHoldingPeriods);

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
assert(isfield(rData,'mPnlReturns') && isfield(rData,'mPnlRetLead') && ...
       isfield(rData,'rEconomicReinvestmentLedgerReference'), ...
    'Weekly input lacks separated economic P&L; rerun b01 and b02');
mPnlReturns     = rData.mPnlReturns;
mPnlRetLead     = rData.mPnlRetLead;
mME             = rData.mME;
mPrices         = rData.mClose;
mVolume         = rData.mVolume;
vDates          = rData.yrmoda;
vMktRet         = rData.vMktRet;

% Get characteristic names for which we want to calculate returns as
% benchmark factors
cCharNames = {'ret_1_0','ret_2_0','ret_3_0','ret_4_0'};

% Determine dimensions
[iNumObs, iNumAssets]   = size(mReturns);
iNumChars               = length(cCharNames);

% Lag characteristics and convert to matrix
mChars_L1   = NaN(iNumAssets, iNumObs, iNumChars);
parfor iIdxChar = 1:iNumChars
    % Lag characteristic
    mCtemp = [NaN(1, iNumAssets); rChars.(cCharNames{iIdxChar})(1:end-1,:)]';
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
mPnlReturns(~lIsSample,:)   = [];
mPnlRetLead(~lIsSample,:)   = [];
mVolume(~lIsSample,:)       = [];
mME_L1(~lIsSample,:)        = [];
mPrices_L1(~lIsSample,:)    = [];
mME(~lIsSample,:)           = [];
mChars_L1(:,~lIsSample,:)   = [];
vDates(~lIsSample)          = [];
vMktRet(~lIsSample)         = [];
iNumObs                     = length(vDates);
fAssertCTRENDAlignment(rCTREND, vDates, rMetaData.vID(:), iNumAssets, ...
    sDataBuildID);

% Apply market-capitalization, price, and stablecoin eligibility only to
% formation information. Once an H-week block is formed, its fixed members
% continue to earn the raw inherent holding returns; later eligibility must
% not truncate the position before the scheduled rebalance.
lRemoveObs                  = ~isfinite(mME_L1) | ~isfinite(mPrices_L1) | ...
                              (mME_L1 == 0) | (mME_L1 < dMinMCAP) | (mPrices_L1 < dMinPrc);
if lExclStable
    lRemoveObs              = lRemoveObs | rMetaData.lIsStable;
end
mME_L1(lRemoveObs)          = NaN;

% Add CTREND to characteristics
mChars_L1 = cat(3, rCTREND.mYhat, mChars_L1);
iNumChars = size(mChars_L1,3);
cCoverageNames = [{'CTREND'},cCharNames];
assert(numel(cCoverageNames) == iNumChars, ...
    'Table B10 coverage labels do not match the sorted characteristics');

% Set characteristic observations to missing if sample has not started
mChars_L1(:,1:iNumIn,:) = NaN;

% Define return for sorting
if iRetLead == 0
    mRetSort = mPnlReturns';
    sPayoffTiming = 'ordinary';
else
    mRetSort = mPnlRetLead';
    sPayoffTiming = 'lead1';
end
assert(strcmp(sPayoffTiming,'ordinary'), ...
    'Table B10 baseline is defined for the ordinary weekly holding interval');
[~,rEconomicReinvestmentLedger,vLedgerWeekRow] = ...
    fAttachEconomicLedgerOptions(struct(),sDataPath,rData, ...
    rMetaData.vID(:),vDates,sPayoffTiming);

% Initialize memory
mAvgRet  = NaN(iNumChars,iNumHoldingPeriods);
mAvgRetT = NaN(iNumChars,iNumHoldingPeriods);
cCoverageByHoldingPeriod = cell(iNumHoldingPeriods,1);
mCTRENDReturnByHoldingPeriod = NaN(iNumObs,iNumHoldingPeriods);

% Record the first available OOS CTREND signal for the coverage audit.  The
% helper deliberately preserves the Dataverse block phase (1, 1+H, ...), so
% this marker does not shift the non-overlapping formation grid.
iIdxFirst = find(any(isfinite(mChars_L1(:,:,1)),1),1,'first');
if isempty(iIdxFirst)
    iIdxFirst = iNumObs + 1;
end

% Loop over holding periods
parfor iIdxH = 1:iNumHoldingPeriods
    iH = vNumHoldingPeriods(iIdxH);
    vAvgRetTemp  = NaN(iNumChars, 1);
    vAvgRetTTemp = NaN(iNumChars, 1);
    cCoverageTemp = cell(iNumChars,1);
    vCTRENDTemp = NaN(iNumObs,1);

    % Each H-week block is formed only once.  Constituents are fixed
    % within the block, while their value weights evolve with realized
    % returns (buy-and-hold).  Repeating the formation-date market caps in
    % every week would implicitly rebalance the weights every week and
    % therefore would not be an H-week holding strategy.
    for iIdxChar = 1:iNumChars
        [vHedgeRet,rHoldingCoverage] = fExtendedHoldingPeriodVW( ...
            mChars_L1(:,:,iIdxChar), mRetSort, mME_L1', ...
            vQuantiles, iH, iIdxFirst, rOptions.iMinNumCS, ...
            rOptions.iMinNumAssets,rEconomicReinvestmentLedger, ...
            vLedgerWeekRow);
        cCoverageTemp{iIdxChar} = rHoldingCoverage;
        if iIdxChar == 1
            vCTRENDTemp = vHedgeRet;
        end
        vAvgRetTemp(iIdxChar)  = mean(vHedgeRet, 'omitmissing');
        vAvgRetTTemp(iIdxChar) = fMeanTstat(vHedgeRet);
    end

    mAvgRet(:, iIdxH)  = vAvgRetTemp;
    mAvgRetT(:, iIdxH) = vAvgRetTTemp;
    cCoverageByHoldingPeriod{iIdxH} = cCoverageTemp;
    mCTRENDReturnByHoldingPeriod(:,iIdxH) = vCTRENDTemp;
end

% H=1 is not a separate strategy: it must reproduce the baseline weekly
% CTREND sort exactly on the same formation and payoff support.
vBaselineCTREND = rCTREND.cResults.VW.mPortRet(end,:)';
lBothFinite = isfinite(vBaselineCTREND) & ...
    isfinite(mCTRENDReturnByHoldingPeriod(:,1));
assert(isequal(isfinite(vBaselineCTREND), ...
               isfinite(mCTRENDReturnByHoldingPeriod(:,1))) && ...
       all(abs(vBaselineCTREND(lBothFinite) - ...
           mCTRENDReturnByHoldingPeriod(lBothFinite,1)) <= 1e-12), ...
    'Table B10 H=1 must equal the baseline CTREND factor');

sCoverageFile = './Results/Tables/table_b10_holding_coverage.mat';
sCoverageTemporary = [tempname(fileparts(sCoverageFile)),'.mat'];
rCoverageCleanup = onCleanup(@() iDeleteIfExists(sCoverageTemporary));
save(sCoverageTemporary,'cCoverageByHoldingPeriod', ...
    'mCTRENDReturnByHoldingPeriod','vNumHoldingPeriods', ...
    'cCoverageNames','cCharNames', ...
    'vDates','iIdxFirst','sDataBuildID');
[lMoved,sMoveMessage] = movefile( ...
    sCoverageTemporary,sCoverageFile,'f');
assert(lMoved,'Could not publish Table B10 coverage: %s',sMoveMessage);
clear rCoverageCleanup

% Create latex table
cColHeader = [{''},sprintfc('%i', vNumHoldingPeriods)];
cRowHeader = [{'CTREND'}, cCharNames]';
cTableB10  = fAddStatistics( fMatrix2Cell(mAvgRet * 100,2),...
    fMatrix2Cell(mAvgRetT,2),...
    abs(mAvgRetT)>=1.96);
cTableB10  = [cColHeader; [cRowHeader, cTableB10]];
rInput.table        = cTableB10;
rInput.tableCaption = 'Extended Portfolio Holding Periods';
fCreateLatexTable(rInput);

% Restore path
path(sOldPath);

function dTstat = fMeanTstat(vReturns)
vReturns = vReturns(isfinite(vReturns));
if numel(vReturns) < 2
    dTstat = NaN;
    return
end
dStd = std(vReturns);
if ~isfinite(dStd) || dStd <= 0
    dTstat = NaN;
else
    dTstat = mean(vReturns) ./ (dStd ./ sqrt(numel(vReturns)));
end
end

function iDeleteIfExists(sFilename)
if exist(sFilename,'file') == 2
    delete(sFilename);
end
end
