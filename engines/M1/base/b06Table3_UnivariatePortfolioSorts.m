% Script for analyzing the performance of the CTREND factor using single
% sorts
%
% Requires that b05CreateCTREND was executed
%
% This script produces:
%   Figure 1:   Comparison of Cryptocurrency Factors
%   Table 3:    Univariate Portfolio Sorts
%   Figure B.2: Comparison of Cumulative Factor Returns
%   Table B.2:  Descriptive Statistics of Asset Pricing Factor Returns
%
%   and when setting lUseLTW below to false:
%   Table B.7:  Univariate Portfolio Sorts - Alternative Factor Data
%   

% Clear console
clear; clc; close all;

% Set paths
sOldPath    = path;
sDataPath   = './DATA/';
addpath('./Utils/');
addpath('./LatexTables/');

% Select the publication output explicitly.  The appendix variant creates
% its own table file and returns before producing any main-text descriptive
% table or figure, so a supplementary run cannot overwrite main outputs.
sOutputVariant = lower(strtrim(getenv('CTREND_OUTPUT_VARIANT')));
if isempty(sOutputVariant)
    sOutputVariant = 'main';
end
assert(ismember(sOutputVariant,{'main','alternative_factor'}), ...
    ['CTREND_OUTPUT_VARIANT must be main or alternative_factor for ' ...
     'b06Table3_UnivariatePortfolioSorts']);
lUseLTW = strcmp(sOutputVariant,'main');

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
fAssertWeeklyDataProvenance(sDataBuildID, rInputProvenance, ...
    sWeeklyCodeFingerprint);

% Extract data from struct
assert(isfield(rData,'mPnlReturns') && ...
       isfield(rData,'mPnlRetLead') && ...
       isfield(rData,'vMktPnl'), ...
    ['Weekly data lack endpoint P&L fields; rerun ' ...
     'b02CalculateIndicators before b06.']);
mPnlReturns     = rData.mPnlReturns;
mPnlRetLead     = rData.mPnlRetLead;
vMktPnl         = rData.vMktPnl;
mME             = rData.mME;
mPrices         = rData.mClose;
mVolume         = rData.mVolume;
vDates          = rData.yrmoda;
vAssetID        = rMetaData.vID(:);
vRiskFree       = rData.vRiskFree;
assert(isequal(size(mPnlReturns),size(mME)) && ...
       isequal(size(mPnlRetLead),size(mME)) && ...
       numel(vMktPnl) == numel(vDates) && ...
       numel(vRiskFree) == numel(vDates), ...
    'Endpoint P&L, market, risk-free, and weekly axes do not agree');

% Get characteristic names for which we want to calculate portfolio
% characteristics. Table 3 reports the previous week's average US-dollar
% trading volume, which is prcvol in the characteristic data. The separate
% volume field is base-quoted volume and is not in USD millions.
cCharNames = {'mcap','prcvol','ivol','ret_3_0'};
cCharDisplayNames = {'mcap','volume','ivol','ret_3_0'};

% Determine dimensions
[iNumObs, iNumAssets]   = size(mPnlReturns);
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

% Restrict to sample period
lIsSample                   = vDates >= iStartDate & vDates <= iEndDate;
mPnlReturns(~lIsSample,:)   = [];
mPnlRetLead(~lIsSample,:)   = [];
mVolume(~lIsSample,:)       = [];
mME_L1(~lIsSample,:)        = [];
mPrices_L1(~lIsSample,:)    = [];
mME(~lIsSample,:)           = [];
mChars_L1(:,~lIsSample,:)   = [];
vDates(~lIsSample)          = [];
vMktPnl(~lIsSample)         = [];
vRiskFree(~lIsSample)       = [];
iNumObs                     = length(vDates);

% Apply ex-ante market capitalization, price, and stablecoin filters
lRemoveObs                  = ~isfinite(mME_L1) | ~isfinite(mPrices_L1) | ...
                              (mME_L1 == 0) | (mME_L1 < dMinMCAP) | (mPrices_L1 < dMinPrc);
if lExclStable
    lRemoveObs              = lRemoveObs | rMetaData.lIsStable;
end
mME_L1(lRemoveObs)          = NaN;

% Scale characteristics for output.  Table 3 reports previous-week averages:
% use the lagged weekly-average mcap characteristic itself, not the single
% lagged week-boundary market-cap snapshot used for portfolio formation.
% prcvol is the raw previous-week average US-dollar trading volume in the
% corrected characteristic build.  IVOL and ret_3_0 are reported in percent.
mChars_L1(:,:,strcmp(cCharNames,'mcap'))    = ...
    mChars_L1(:,:,strcmp(cCharNames,'mcap')) / 1e6;
mChars_L1(:,:,strcmp(cCharNames,'prcvol'))  = ...
    mChars_L1(:,:,strcmp(cCharNames,'prcvol')) / 1e6;
mChars_L1(:,:,strcmp(cCharNames,'ivol'))     = ...
    mChars_L1(:,:,strcmp(cCharNames,'ivol')) * 100;
mChars_L1(:,:,strcmp(cCharNames,'ret_3_0'))  = mChars_L1(:,:,strcmp(cCharNames,'ret_3_0')) * 100;

% Load aggregate trend characteristic (b05CreateCTREND)
sFilename = sprintf('./Results/CTREND/CTREND_Base.mat');
rCTREND   = load(sFilename, 'mYhat','mRetPnlOOS','cResults','vDates','vAssetID', ...
    'sCodeFingerprint','sDataBuildID');
fAssertCTRENDAlignment(rCTREND, vDates, rMetaData.vID(:), iNumAssets, ...
    sDataBuildID);

% Define the realized return for portfolio accounting.  Endpoint P&L is
% never outlier-censored by the formation mask above.  The portfolio helper
% removes a target-week asset known to be unavailable before breakpoints and
% reallocates over the tradable set; a within-week last trade remains a
% finite payoff followed by immediate same-leg reinvestment. Statistical
% mReturns remains separate.
if iRetLead == 0
    mRetSort = mPnlReturns';
    sPayoffTiming = 'ordinary';
else
    mRetSort = mPnlRetLead';
    sPayoffTiming = 'lead1';
end
[rOptions,~,vLedgerWeekRow] = fAttachEconomicLedgerOptions( ...
    rOptions,sDataPath,rData,vAssetID,vDates,sPayoffTiming);

% Get benchmark factors
if lUseLTW
    % Load LTW factors
    load('./DATA/LTW_3factor.mat');
    mLTW                = fAlignByDate(vDatesLiu, mLTW, vDates, 'LTW', 0.95);
else
    % Create LTW factors if not use from their website
    % CSMB uses 30% and 70% breakpoints: univariate sorts
    rResultsSMB = fSingleSortMulti(mME_L1', mRetSort, [0, 0.3, 0.7, 1], ...
        [], mME_L1', rOptions);
    vCSMB       = rResultsSMB.VW.mPortRet(end,:) * -1;

    % CMOM uses dependent sorts: First split into small and big
    % cryptocurrencies and then use 30% and 70% breakpoints
    iIdxMom = find(strcmp(cCharNames,'ret_3_0'));
    rResultsCMOM = fDepDoubleSort(mME_L1', mChars_L1(:,:,iIdxMom), ...
        mRetSort, [], mME_L1', 'vPercentileA',0:0.5:1, ...
        'vPercentileB', [0, 0.3, 0.7, 1], ...
        'rReinvestmentLedger',rOptions.rReinvestmentLedger, ...
        'vLedgerWeekRow',vLedgerWeekRow, ...
        'sPayoffTiming',sPayoffTiming);
    vCMOM = 0.5 * (rResultsCMOM.VW.cPortRets{1,end-1} + ...   % Small high
        rResultsCMOM.VW.cPortRets{2,end-1}) - ...             % Bigh high
        0.5 * (rResultsCMOM.VW.cPortRets{1,1} + ...           % Small low
        rResultsCMOM.VW.cPortRets{2,1});                      % Big low

    % Merge
    mLTW = [vMktPnl - vRiskFree, vCSMB', vCMOM'];
end

% Define benchmark models
cBenchmark{1,1} = {'CCAPM'};        cBenchmark{1,2} = mLTW(:,1);
cBenchmark{2,1} = {'LTW'};          cBenchmark{2,2} = mLTW;
iNumBenchmark   = size(cBenchmark,1);

% Initialize memory
mBeta_CAPM      = NaN(iNumPorts, 2);                    % Alphas and betas wrt CAPM
mBetaT_CAPM     = NaN(iNumPorts, 2);                    % t-statistics of alphas and betas wrt CAPM
mBeta_LTW       = NaN(iNumPorts, 4);                    % Alphas and betas wrt LTW
mBetaT_LTW      = NaN(iNumPorts, 4);                    % t-statistics of alphas and betas wrt LTW

% Sort w.r.t. characteristic 
rResults = fSingleSortMulti(rCTREND.mYhat, rCTREND.mRetPnlOOS, ...
    vQuantiles, [], mME_L1', rOptions); 

% Get time-series of portfolios
if lUseValueWts
    mPortRet = rResults.VW.mPortRet';
    mWts     = rResults.VW.mWts;
else
    mPortRet = rResults.EW.mPortRet';
    mWts     = rResults.EW.mWts;
end

% Average portfolio return
vAvgRet                 = mean(mPortRet,1,'omitmissing')';
[~,~,~,stats]           = ttest(mPortRet);
vAvgRetT                = stats.tstat';

% Volatility
vStd                    = std(mPortRet,[],1,'omitmissing')';

% Sharpe ratio
vShp                    = fSharpeRatio(mPortRet, 0, 1, 2);

% Regression on CAPM and LTW
parfor iIdxP = 1:iNumPorts
    % The paper's factor regressions use excess portfolio returns.  The
    % final column is a zero-investment H-L return, for which RF cancels.
    vPortRetReg = mPortRet(:,iIdxP);
    if iIdxP < iNumPorts
        vPortRetReg = vPortRetReg - vRiskFree;
    end
    % Regression on CAPM
    [vBetaTemp, vTstatTemp] = fRegstatsTstatSafe(vPortRetReg, mLTW(:,1));
    mBeta_CAPM(iIdxP,:)     = vBetaTemp;
    mBetaT_CAPM(iIdxP,:)    = vTstatTemp;

    % Regression on LTW
    [vBetaTemp, vTstatTemp] = fRegstatsTstatSafe(vPortRetReg, mLTW);
    mBeta_LTW(iIdxP,:)      = vBetaTemp;
    mBetaT_LTW(iIdxP,:)     = vTstatTemp;
end

% Calculate additional characteristics
mAddPortChars = NaN(iNumPorts, iNumChars);
parfor iIdxChar = 1:iNumChars
    vAddPortCharsTemp = NaN(iNumPorts, 1);
    mCbase = mChars_L1(:,:,iIdxChar);
    % Loop over portfolios
    for iIdxP = 1:iNumPorts-1
        % Get characteristics
        mCtemp = mCbase;
        lIsIn  = rResults.mIndex == iIdxP;

        % Set to missing if not available
        mCtemp(~lIsIn) = NaN;

        % Calculate average
        vAddPortCharsTemp(iIdxP) = mean(mCtemp,'all','omitmissing');
    end
    mAddPortChars(:, iIdxChar) = vAddPortCharsTemp;
end

% Create LaTeX table
cRowHeader = replace(sprintfc('%i', 1:iNumPorts)',{num2str(1),num2str(iNumPorts-1),num2str(iNumPorts)},{'L','H','H-L'});
cColHeader = [{'Rank','Avg','Std','Shp','$\alpha^{CCAPM}$','$\beta^{CMKT}$',...
    '$\alpha^{LTW}$','$\beta^{CMKT}$','$\beta^{CSMB}$','$\beta^{CMOM}$'},replace(cCharDisplayNames,'_','\_')];

% Average returns
cAvgRet = fAddStatistics( fMatrix2Cell( vAvgRet * 100,2),...
    fMatrix2Cell( vAvgRetT, 2),...
    abs(vAvgRetT) >= 1.96);

% Regression coefficients
mBeta_CAPM(:,1) = mBeta_CAPM(:,1) * 100; mBeta_LTW(:,1) = mBeta_LTW(:,1) * 100; 
cBeta = fAddStatistics( fMatrix2Cell( [mBeta_CAPM, mBeta_LTW],2),...
    fMatrix2Cell( [mBetaT_CAPM, mBetaT_LTW], 2),...
    abs([mBetaT_CAPM, mBetaT_LTW]) >= 1.96);

% Volatility and Sharpe ratio
cStats = fMatrix2Cell( [vStd*100, vShp], 2);

% Characteristics
cChars = fMatrix2Cell( mAddPortChars, 2, true);

% Merge
cTable3 = [cColHeader; [cRowHeader, cAvgRet, cStats, cBeta, cChars]];
rInput.table = cTable3;
if strcmp(sOutputVariant,'alternative_factor')
    rInput.tableCaption = ...
        'Univariate Portfolio Sorts - Alternative Factor Data';
    sTableDir = fullfile(pwd,'Results','Tables');
    if ~exist(sTableDir,'dir')
        mkdir(sTableDir);
    end
    rInput.outputDir = fullfile(sTableDir, ...
        'univariate_portfolio_sorts_alternative_factor_data.tex');
else
    rInput.tableCaption = 'Univariate Portfolio Sorts';
end
fCreateLatexTable(rInput);

% Table B.7 is the only requested product of the alternative-factor
% specification.  Do not overwrite the main Table B.2 or Figures 1/B.2.
if strcmp(sOutputVariant,'alternative_factor')
    path(sOldPath);
    return
end

% Compare factors on one listwise common sample for the descriptive table.
% Retain the complete calendar separately for the cumulative-return plot;
% deleting missing weeks would compress both accumulation and the x-axis.
mFactAll            = [mLTW, mPortRet(:,end)];
vDatesTemp          = vDates;
lCommonFactor       = all(isfinite(mFactAll),2);
mFact               = mFactAll(lCommonFactor,:);

% Calculate Sharpe ratios and average returns
vShp    = fSharpeRatio(mFact,0,1,2);
vAvg    = mean(mFact,1,'omitmissing')';
vSkew   = skewness(mFact,[],1)';
vKurt   = kurtosis(mFact,[],1)';
vStd    = std(mFact,[],1)';
[~,~,~,stats] = ttest(mFact);
vTstat  = stats.tstat';

% Calculate correlations
mCorr   = corr(mFact);
mCorr   = triu(mCorr,1); mCorr(mCorr == 0) = NaN;

% Create table B2
cTableB2 = [fAddStatistics( fMatrix2Cell(vAvg * 100, 2),...
    fMatrix2Cell(vTstat,2), abs(vTstat)>=1.96),...
    fMatrix2Cell( [vStd * 100, vShp, vSkew, vKurt-3, mCorr], 2, true)];

% Create column header
cLTWnames  = {'CMKT','CSMB','CMOM'};
cFactNames = [cLTWnames, {'CTREND'}];
cColHeader = [{'','Avg','Std','Shp','Skew','Kurt'}, cLTWnames, {'CTREND'}];

% Merge
cTableB2        = [cColHeader; [cFactNames(:), cTableB2]];
rInput.table    = cTableB2;
rInput.tableCaption = 'Descriptive Statistics of Asset Pricing Factor Returns';
fCreateLatexTable(rInput);

% Plot average return
h1 = figure(1);
vFigure1Average = [vAvg(end);vAvg(1:end-1)]*100;
bar(1,vFigure1Average(1),'grouped','FaceColor',[0.5,0.5,0.5]);
hold on
bar(2:4,vFigure1Average(2:4),'grouped','FaceColor',[0.75,0.75,0.75]);
yline(0,'k-','LineWidth',0.75,'HandleVisibility','off');
hold off
xticks(1:4)
xticklabels({'CTREND','CMKT','CSMB','CMOM'});
ylabel('Average Return (\%)','Interpreter','latex','FontSize',12);
[vAverageYLim,vAverageYTicks] = ...
    fSignedAxisLimitsTicks(vFigure1Average,0.5);
ylim(vAverageYLim);
yticks(vAverageYTicks);
yticklabels(sprintfc('%.1f',vAverageYTicks));
ax = gca(h1);
ax.YAxis.FontSize = 12;
ax.XAxis.FontSize = 12;
box off

% Plot Sharpe ratios
h2 = figure(2);
vFigure1Sharpe = [vShp(end);vShp(1:end-1)];
bar(1,vFigure1Sharpe(1),'grouped','FaceColor',[0.5,0.5,0.5]);
hold on
bar(2:4,vFigure1Sharpe(2:4),'grouped','FaceColor',[0.75,0.75,0.75]);
yline(0,'k-','LineWidth',0.75,'HandleVisibility','off');
hold off
xticks(1:4)
xticklabels({'CTREND','CMKT','CSMB','CMOM'});
ylabel('Sharpe Ratio (Annualized)','Interpreter','latex','FontSize',12);
[vSharpeYLim,vSharpeYTicks] = ...
    fSignedAxisLimitsTicks(vFigure1Sharpe,0.2);
ylim(vSharpeYLim);
yticks(vSharpeYTicks);
yticklabels(sprintfc('%.1f',vSharpeYTicks));
ax = gca(h2);
ax.YAxis.FontSize = 12;
ax.XAxis.FontSize = 12;
box off

% Plot the paper/old-pipeline cumulative factor-return increments on the
% original weekly calendar. All four series use common-factor support. This
% figure-only display leaves the pre-sample period undefined, then sets an
% internal missing common-support increment to 0 so the cumulative paths
% remain flat and connected. mFactAll, mFact and every scientific consumer
% retain the original NaNs; this display convention is not portfolio P&L.
mFactPlot = mFactAll;
mFactPlot(~lCommonFactor,:) = NaN;
mCumRet = fCumulativeFactorReturnDisplayZeroGaps(mFactPlot,1);
h3 = figure(3);
set(h3, 'DefaultTextFontSize', 30);
plot(mCumRet(:,1)*100, 'LineWidth',2, 'LineStyle','-', 'Color',[0.6, 0.6, 0.6]);
hold on
plot(mCumRet(:,2)*100, 'LineWidth',2, 'LineStyle','--', 'Color',[0.6, 0.6, 0.6]);
plot(mCumRet(:,3)*100, 'LineWidth',2, 'LineStyle','--', 'Color',[0, 0, 0]);
plot(mCumRet(:,4)*100, 'LineWidth',2, 'LineStyle','-', 'Color',[0, 0, 0]);
hold off
box off 
legend({'CMKT', 'CSMB', 'CMOM', 'CTREND'}, 'Location','northwest');
ylabel('Cumulative Return (\%; gaps = 0\%)', 'Interpreter','latex');
vLabelYears = 2016:2022;
vTick = NaN(size(vLabelYears));
for iIdxYear = 1:numel(vLabelYears)
    iTickTemp = find(floor(vDatesTemp/100) == ...
        vLabelYears(iIdxYear),1,'first');
    if ~isempty(iTickTemp)
        vTick(iIdxYear) = iTickTemp;
    end
end
lTick = isfinite(vTick);
xticks(vTick(lTick));
xticklabels(sprintfc('%i',vLabelYears(lTick)));

% Restore path
path(sOldPath);
