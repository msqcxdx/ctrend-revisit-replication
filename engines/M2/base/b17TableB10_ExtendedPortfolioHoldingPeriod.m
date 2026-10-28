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

% Define number of holding periods
vNumHoldingPeriods = 1:6;
iNumHoldingPeriods = length(vNumHoldingPeriods);

%% Analysis
% Find number of data setting
iIdxDataComb = tCombos.data_setting( find(strcmpi(tCombos.cOutlierTreatment, sOutlierTreatment) & ...
    tCombos.vThreshold == dThreshold,1,'first') );

% Load data
load([sDataPath,sprintf('bCharacteristicsOLHC_Combo%i.mat', iIdxDataComb)]);

% M2 removes target-outcome preprocessing but otherwise keeps M0's
% extended-holding design (it does not import M1's cohort accounting).
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

% Get characteristic names for which we want to calculate returns as
% benchmark factors
cCharNames = {'ret_1_0','ret_2_0','ret_3_0','ret_4_0'};

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

% Add CTREND to characteristics
mChars_L1 = cat(3, rCTREND.mYhat, mChars_L1);
iNumChars = size(mChars_L1,3);

% Set characteristic observations to missing if sample has not started
mChars_L1(:,1:iNumIn,:) = NaN;

% Define return for sorting
if iRetLead == 0
    mRetSort = mPnlReturns';
    sPayoffTiming = 'ordinary';
else
    mRetSort = mPnlReturnsLead';
    sPayoffTiming = 'lead1';
end
[rOptions,~,~] = fAttachEconomicLedgerOptions( ...
    rOptions,sDataPath,rData,rMetaData.vID(:),vDates,sPayoffTiming);

% Initialize memory
mAvgRet  = NaN(iNumChars,iNumHoldingPeriods);
mAvgRetT = NaN(iNumChars,iNumHoldingPeriods);

% Loop over holding periods
for iIdxH = 1:iNumHoldingPeriods
    % Get number of holding periods
    iH = vNumHoldingPeriods(iIdxH);

    % Get first nonmissing observation
    iIdxFirst               = find(any(~isnan(mChars_L1(:,:,1)),1),1,'first');
    
    % Now define a start index of each holding period. The step size
    % depends on the number of weeks
    vIdxStartHP             = 1:iH:iNumObs;

    % Get number of weeks in each holding period
    vNumObsHP               = diff([vIdxStartHP,iNumObs]);

    % Adjustment for the last week. By calculating the number of weeks
    % in the last holding period using diff as above, the number of weeks
    % is underestimated by one, so we need to increase it by 1. E.g.,
    % for one week holding period, we hold the portfolio for one week,
    % not zero weeks
    vNumObsHP(end) = vNumObsHP(end) + 1;

    % Loop over characteristics
    for iIdxChar = 1:iNumChars     
        % Get characteristic at beginning of holding period
        mCtemp = mChars_L1(:,:,iIdxChar);
    
        % To use the function fSingleSortMulti for longer holding
        % periods, we can simply repeat the characteristics and market
        % capitalitaion so that the portfolio composition does not
        % change
        mCrep   = repelem(mCtemp(:,vIdxStartHP)',vNumObsHP,1)';
        mMErep  = repelem(mME_L1(vIdxStartHP,:),vNumObsHP,1)';

        % Sorts
        rResults = fSingleSortMulti(mCrep, mRetSort, vQuantiles, [], mMErep, rOptions);
        mAvgRet(iIdxChar, iIdxH)    = rResults.VW.vAvgRet(end);
        mAvgRetT(iIdxChar, iIdxH)   = rResults.VW.vTstat(end);
    end
end

% Create latex table
cColHeader = [{''},sprintfc('%i', vNumHoldingPeriods)];
cRowHeader = [{'CTREND'}, cCharNames]';
cTableB10  = fAddStatistics( fMatrix2Cell(mAvgRet * 100,2),...
    fMatrix2Cell(mAvgRetT,2),...
    abs(round(mAvgRetT,2))>=1.96);
cTableB10  = [cColHeader; [cRowHeader, cTableB10]];
rInput.table        = cTableB10;
rInput.tableCaption = 'Extended Portfolio Holding Periods';
fCreateLatexTable(rInput);

% Restore path
path(sOldPath);
