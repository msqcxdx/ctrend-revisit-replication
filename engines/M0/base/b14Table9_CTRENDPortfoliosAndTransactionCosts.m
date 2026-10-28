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

% Determine dimensions
iNumAssets                  = size(mReturns,2);

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
mME(~lIsSample,:)           = [];
vDates(~lIsSample)          = [];
vMktRet(~lIsSample)         = [];
iNumObs                     = length(vDates);

% Define return for sorting
if iRetLead == 0
    mRetSort = mReturns';
else
    mRetSort = mReturnsLead';
end

% Loop over samples
for iIdxS = 1:2
    if iIdxS == 1
        % Consider all assets
        vMinMCAP_Top100 = 0;
    elseif iIdxS == 2
        % Consider only largest

        % Find the threshold so that we can consider only the largest 100
        % crpytos
        vMinMCAP_Top100 = min(maxk(mME_L1,100,2),[],2);
    end

    % Set returns to missing if minimum MCAP is not reached
    lSetMissing = mME_L1 < vMinMCAP_Top100;
    mRetSort(lSetMissing') = NaN;

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

        % Sort w.r.t. characteristic 
        rResults = fSingleSortMulti(rCTREND.mYhat, mRetSort, vQuantiles, [], mME_L1', rOptionsTemp); 
    
        % Get time-series of portfolios
        if lUseValueWts
            mPortRet    = rResults.VW.mPortRet';
            mPortRetNet = rResults.VW.mPortRetNet';
        else
            mPortRet    = rResults.EW.mPortRet';
            mPortRetNet = rResults.EW.mPortRetNet';
        end

        % Calculate gross returns
        vAvgGross           = mean(mPortRet,1,'omitmissing')';
        [~,~,~,stats]       = ttest(mPortRet);
        vAvgGrossT          = stats.tstat';

        % Calculate net returns
        mAvgNet(:,iIdxK)    = mean(mPortRetNet,1,'omitmissing')';
        [~,~,~,stats]       = ttest(mPortRetNet);
        mAvgNetT(:,iIdxK)   = stats.tstat;

        % Get turnover
        vTurnover = rResults.VW.vTurnoverGKX*100;
        vTurnover(end) = vTurnover(end)/2; % Report avgerage

        % Get BETC
        vBETC   = rResults.VW.vBreakEvenTC * 100;
        vBETC5  = rResults.VW.vBreakEvenTC_5pct * 100;
    end

    % Create LaTeX table
    cTableTemp = [fAddStatistics( fMatrix2Cell( [vAvgGross, mAvgNet]*100, 2),...
        fMatrix2Cell([vAvgGrossT, mAvgNetT], 2),...
        abs(round([vAvgGrossT, mAvgNetT],2))>= 1.96),...
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
        cTable9A = cTableTemp;
    elseif iIdxS == 2
        % Merge
        cTableTemp = [cell(1, size(cTableTemp,2)+1); [cRowHeader, cTableTemp]];

        % First panel using all cryptos
        cTable9B = cTableTemp;
    end
end

% Merge Panel A and B
cTable9 = [cTable9A; cTable9B];

% Latex code
rInput.table = cTable9;
rInput.tableCaption = 'CTREND Portfolios and Transaction Costs';
fCreateLatexTable(rInput);

% Restore path
path(sOldPath);