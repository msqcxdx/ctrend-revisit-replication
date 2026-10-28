% Script for analyzing the net performance of the CTREND factor
%
% Requires that b05CreateCTREND and b06Table3_UnivariatePortfolioSorts 
% were executed
%
% This script produces:
%   Table 9:   CTREND Portfolios and Transaction Costs

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

% Define transaction cost rates
mTC    = [0.004, 0.003;...
    0.005, 0.004;...
    0.006, 0.005];
iNumTC = size(mTC,1);
    
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

% Determine dimensions
iNumAssets                  = size(mReturns,2);

% Lag market equity
mME_L1 = [NaN(1, iNumAssets); mME(1:end-1,:)];
mPrices_L1 = [NaN(1, iNumAssets); mPrices(1:end-1,:)];

% Load aggregate trend characteristic
sFilename = sprintf('./Results/CTREND/CTREND_Base.mat');
rCTREND   = load(sFilename, 'mYhat','mRetPnlOOS', ...
    'cResults','vDates','vAssetID', ...
    'sCodeFingerprint','sDataBuildID');

% Restrict to sample period
lIsSample                   = vDates >= iStartDate & vDates <= iEndDate;
mReturns(~lIsSample,:)      = [];
mReturnsLead(~lIsSample,:)  = [];
mVolume(~lIsSample,:)       = [];
mME_L1(~lIsSample,:)        = [];
mPrices_L1(~lIsSample,:)    = [];
mME(~lIsSample,:)           = [];
vDates(~lIsSample)          = [];
vMktRet(~lIsSample)         = [];
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
mReturns(lRemoveObs)        = NaN;
mReturnsLead(lRemoveObs)    = NaN;
mReturnsRaw(lRemoveObs)     = NaN;
mReturnsLeadRaw(lRemoveObs) = NaN;
mME_L1(lRemoveObs)          = NaN;

% The selected implementation lag is already embedded upstream in the saved
% raw OOS P&L panel.
mRetSort = rCTREND.mRetPnlOOS;

% Loop over samples
cTablePanels = cell(2,1);
cAccountingAudit = cell(2,1);
parfor iIdxS = 1:2
    % Consider all assets by default.
    lUniverse = true(iNumAssets, iNumObs);
    if iIdxS == 2
        % Consider only the largest 100 cryptos by lagged market equity,
        % omitting missing market-equity observations.
        lUniverse = fBuildTopUniverse(mME_L1', 100);
    end

    % Initialize memory
    vAvgGross  = NaN(iNumPorts,1);              % Average gross returns
    vAvgGrossT = NaN(iNumPorts,1);              % t-statistics
    vTurnover  = NaN(iNumPorts,1);              % Turnover
    vBETC      = NaN(iNumPorts,1);              % Breakeven transaction costs
    vBETC5     = NaN(iNumPorts,1);              % Breakeven transaction costs (5% significance)
    mAvgNet    = NaN(iNumPorts, iNumTC);        % Average net return
    mAvgNetT   = NaN(iNumPorts, iNumTC);        % t-statistics

    % Loop over transaction cost rates
    for iIdxK = 1:iNumTC
        % Copy options and set transaction costs
        rOptionsTemp        = rOptions;
        rOptionsTemp.vTC    = mTC(iIdxK,:);
        rOptionsTemp.mUniverse = lUniverse;
        % Sort w.r.t. characteristic 
        rResults = fSingleSortMulti(rCTREND.mYhat, mRetSort, vQuantiles, [], mME_L1', rOptionsTemp); 
    
        % Get time-series of portfolios
        if lUseValueWts
            mPortRet    = rResults.VW.mPortRet';
            mPortRetNet = rResults.VW.mPortRetNet';
            rSelectedResults = rResults.VW;
        else
            mPortRet    = rResults.EW.mPortRet';
            mPortRetNet = rResults.EW.mPortRetNet';
            rSelectedResults = rResults.EW;
        end

        % Calculate gross returns
        vAvgGross           = mean(mPortRet,1,'omitmissing')';
        [~,~,~,stats]       = ttest(mPortRet);
        vAvgGrossT          = stats.tstat';

        % Calculate net returns
        mAvgNet(:,iIdxK)    = mean(mPortRetNet,1,'omitmissing')';
        [~,~,~,stats]       = ttest(mPortRetNet);
        mAvgNetT(:,iIdxK)   = stats.tstat';

        % Get turnover
        vTurnover = rSelectedResults.vTurnoverGKX*100;

        % Get BETC
        vBETC   = rSelectedResults.vBreakEvenTC * 100;
        vBETC5  = rSelectedResults.vBreakEvenTC_5pct * 100;
    end

    % Persist the exact gross-return/cost support after the sort has been
    % calculated.  Gross returns and the full drift-adjusted L1 cost base do
    % not depend on the fee-rate row, so the final loop result is the common
    % accounting object for all three net-return columns.
    rAccountingAudit = struct();
    rAccountingAudit.vDates = vDates;
    rAccountingAudit.mGrossReturn = mPortRet;
    rAccountingAudit.mCostBaseFull = ...
        rSelectedResults.mCostBaseFull;
    rAccountingAudit.mCostBasePaired = ...
        rSelectedResults.mCostBasePaired;
    rAccountingAudit.mOpeningTradeCostBaseFull = ...
        rSelectedResults.mOpeningTradeCostBaseFull;
    rAccountingAudit.mForcedLiquidationCostBaseFull = ...
        rSelectedResults.mForcedLiquidationCostBaseFull;
    rAccountingAudit.mFormationHoldings = ...
        rSelectedResults.mFormationHoldings';
    rAccountingAudit.mMissingPayoffHoldings = ...
        rSelectedResults.mMissingPayoffHoldings';
    rAccountingAudit.mMissingPayoffWeight = ...
        rSelectedResults.mMissingPayoffWeight';
    rAccountingAudit.mTargetDefined = ...
        rSelectedResults.lTargetDefined';
    rAccountingAudit.mPayoffComplete = ...
        rSelectedResults.lPayoffComplete';
    rAccountingAudit.mObservableTransition = ...
        rSelectedResults.lObservableTransition';
    rAccountingAudit.mRestartAfterGap = ...
        rSelectedResults.lRestartAfterGap';
    rAccountingAudit.mInternalFormationGap = ...
        rSelectedResults.lInternalFormationGap';
    rAccountingAudit.rCounts = ...
        rSelectedResults.rAccountingCounts;
    rAccountingAudit.vGrossN = ...
        rSelectedResults.rAccountingCounts.vGrossN;
    rAccountingAudit.vRawCostN = ...
        rSelectedResults.rAccountingCounts.vRawCostN;
    rAccountingAudit.vPairedN = ...
        rSelectedResults.rAccountingCounts.vPairedN;
    rAccountingAudit.mNetN = repmat( ...
        rSelectedResults.rAccountingCounts.vPairedN,1,iNumTC);
    rAccountingAudit.lIncludesInitialFormation = true;
    rAccountingAudit.lIncludesTerminalLiquidation = false;
    rAccountingAudit.lIncludesWithinWeekLastTradeLiquidation = true;
    rAccountingAudit.sGapPolicy = ...
        ['Only first-ever formation or an adjacent defined target with a ' ...
         'complete prior payoff and positive prior wealth has an observable ' ...
         'transition; a post-gap target seeds a new episode without a ' ...
         'fabricated cash-entry cost'];
    cAccountingAudit{iIdxS} = rAccountingAudit;

    % Create LaTeX table
    cTableTemp = [fAddStatistics( fMatrix2Cell( [vAvgGross, mAvgNet]*100, 2),...
        fMatrix2Cell([vAvgGrossT, mAvgNetT], 2),...
        abs([vAvgGrossT, mAvgNetT])>= 1.96),...
        fMatrix2Cell([vTurnover, vBETC, vBETC5],2)];

    % Create column header
    cColHeader = [{'','Avg$^{gross}$'},cellfun(@(x)['Avg$^{net}$ (',x,')'],...
        sprintfc('%i',1:iNumTC),'UniformOutput',false),{'TO', 'BETC','BETC 5\%'}];

    % Create row header
    cRowHeader = replace(sprintfc('%i', 1:iNumPorts)',{num2str(1),num2str(iNumPorts-1),num2str(iNumPorts)},{'L','H','H-L'});

    % Rename table
    if iIdxS == 1
        % Merge
        cTableTemp = [cColHeader; [cRowHeader, cTableTemp]];

        % First panel using all cryptos
        cTablePanels{iIdxS} = cTableTemp;
    elseif iIdxS == 2
        % Merge
        cTableTemp = [cell(1, size(cTableTemp,2)+1); [cRowHeader, cTableTemp]];

        % First panel using all cryptos
        cTablePanels{iIdxS} = cTableTemp;
    end
end

% Merge Panel A and B
cTable9 = [cTablePanels{1}; cTablePanels{2}];

sAuditFile = './Results/Tables/table9_transaction_cost_accounting.mat';
sAuditTemporary = [tempname(fileparts(sAuditFile)),'.mat'];
rAuditCleanup = onCleanup(@() iDeleteIfExists(sAuditTemporary));
save(sAuditTemporary,'cAccountingAudit','mTC','vDates','sDataBuildID');
[lMoved,sMoveMessage] = movefile(sAuditTemporary,sAuditFile,'f');
assert(lMoved,'Could not publish Table 9 accounting audit: %s', ...
    sMoveMessage);
clear rAuditCleanup

% Latex code
rInput.table = cTable9;
rInput.tableCaption = 'CTREND Portfolios and Transaction Costs';
fCreateLatexTable(rInput);

% Restore path
path(sOldPath);

function iDeleteIfExists(sFilename)
if exist(sFilename,'file') == 2
    delete(sFilename);
end
end
