% Script for measuring the variable importance within the cross-sectional
% combined elastic net
%
% Requires that b05CreateCTREND and b06Table3_UnivariatePortfolioSorts 
% were executed
%
% This script produces:
%   Figure C3:  Average Variable Importance
%   Figure C4:  Indicator Selection Over Time

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
lUseVolume          = true;     % Use volume indicator

% Settings for portfolio sorts
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

% M2 retains M0's joint-predictor Figure-C estimator but removes the
% target-outcome path from its panel support.
assert(isfield(rData,'mReturnsM2Raw') && isfield(rData,'mRetLeadM2Raw'), ...
    'Weekly input predates the M2 causal return layer; rerun b02');
mReturns        = rData.mReturnsM2Raw;
mReturnsLead    = rData.mRetLeadM2Raw;
mME             = rData.mME;
mPrices         = rData.mClose;
mVolume         = rData.mVolume;
vDates          = rData.yrmoda;
vMktRet         = rData.vMktRet;
vAssetID        = rMetaData.vID;

% Define technical indicators
if lUseVolume
    cTechnicalIndicators = [cellfun(@(x)['sma_',x,'d'],sprintfc('%i',[3,5,10,20,50,100,200]),'un',false),...
        {'macd', 'macd_diff_signal'},...
        cellfun(@(x)['volsma_',x,'d'],sprintfc('%i',[3,5,10,20,50,100,200]),'un',false),...
        {'volmacd', 'volmacd_diff_signal'},{'rsi', 'stochRSI', 'stochK', 'stochD'}...
        {'boll_low','boll_mid','boll_high','boll_width', 'cci','chaikin'}]';
else
    cTechnicalIndicators = [cellfun(@(x)['sma_',x,'d'],sprintfc('%i',[3,5,10,20,50,100,200]),'un',false),...
        {'macd', 'macd_diff_signal','rsi', 'stochRSI', 'stochK', 'stochD'}...
        {'boll_low','boll_mid','boll_high','boll_width', 'cci'}]';
end

% Determine dimensions
[iNumObs, iNumAssets]   = size(mReturns);
iNumChars               = length(cTechnicalIndicators);

% Lag characteristics and convert to matrix
mChars_L1 = NaN(iNumAssets, iNumObs, iNumChars);
for iIdxChar = 1:iNumChars
    mChars_L1(:,:,iIdxChar) = [NaN(1, iNumAssets); rChars.(cTechnicalIndicators{iIdxChar})(1:end-1,:)]';
end

% Lag formation variables
mME_L1 = [NaN(1, iNumAssets); mME(1:end-1,:)];
mPrices_L1 = [NaN(1, iNumAssets); mPrices(1:end-1,:)];

% Restrict to sample period
lIsSample                   = vDates >= iStartDate & vDates <= iEndDate;
mReturns(~lIsSample,:)      = [];
mReturnsLead(~lIsSample,:)  = [];
mVolume(~lIsSample,:)       = [];
mME_L1(~lIsSample,:)        = [];
mPrices_L1(~lIsSample,:)    = [];
mME(~lIsSample,:)           = [];
mChars_L1(:,~lIsSample,:)   = [];
vDates(~lIsSample)          = [];
vMktRet(~lIsSample)         = [];
iNumObs                     = length(vDates);

% Retain M0's all-predictor intersection but form it without observing Y.
lRemoveObs = isnan(mME_L1) | isnan(mPrices_L1) | ...
    (mME_L1 == 0) | (mME_L1 < dMinMCAP) | (mPrices_L1 < dMinPrc);
if lExclStable
    lRemoveObs = lRemoveObs | rMetaData.lIsStable;
end
mReturns(lRemoveObs) = NaN;
mReturnsLead(lRemoveObs) = NaN;
mME_L1(lRemoveObs) = NaN;
lAvail = all(~isnan(mChars_L1),3) & ~isnan(mME_L1');
for iIdxChar = 1:iNumChars
    mCtemp = mChars_L1(:,:,iIdxChar);
    mCtemp(~lAvail) = NaN;
    mChars_L1(:,:,iIdxChar) = mCtemp;
end
mME_L1(~lAvail') = NaN;

% Define methods (here, only the base method C_ENET_SCS is implemented)
cTrendNames = {'C_ENET_SCS'};
iNumTrend   = length(cTrendNames);

% Initialize memory
mTrend      = NaN(iNumObs, iNumTrend);
mAvgRet     = NaN(iNumPorts, iNumTrend);

% Get asset weights
if lUseValueWts
    mWts_L1 = (mME_L1 ./ sum(mME_L1,2,'omitmissing'))';
else
    mWts_L1 = [];
end

% Rank transformation of characteristics
mCharsUse = permute(fCrossSectTransChars(permute(mChars_L1, [1,3,2]), 'rank'), [1,3,2]);

% Demean raw labels; the importance implementation does not consume their
% values, but retaining them makes support auditing explicit.
mRet = fDemeanWeeklyM2(mReturns);

% Stack before observing the target.  This is the only Figure-C estimator
% change: M1's predictor-own-support importance is intentionally not used.
[mC, vY, mID, vW] = fCreatePanelExAnteM2(mCharsUse, mRet', mWts_L1);
iNumPanelObs      = length(vY);
vAssetNum         = unique(mID(:,2));
vTimeID           = unique(mID(:,1));

% Load estimation results
sFilename = sprintf('./Results/CTREND/CTREND_Base.mat');
load(sFilename,'mBeta','mSelected');

% Add missing time steps due to out-of-sample estimation
mBeta       = cat(1, NaN(iNumIn, iNumChars, 2), mBeta);
mSelected   = cat(1, false(iNumIn, iNumChars), mSelected);

% Measure avergage variable importance 
[vImportance]  = fImportanceCS_ENet(vY, mC, mID, mBeta, mSelected);
[~,vSortIdx]   = sort(vImportance,'descend');
cImportancePDP = [cTechnicalIndicators(:), sprintfc('%.2f',round(vImportance(:)*100,2))];
cImportancePDP = cImportancePDP(vSortIdx,:);
vBars = vImportance(vSortIdx);
cCharNamesSorted = flipud(cTechnicalIndicators(vSortIdx));
h1 = figure(1);
barh(flipud(vBars'),'grouped','FaceColor',[0.75,0.75,0.75]);
box off
cCharNamesSorted(strcmpi(cCharNamesSorted,'ppo')) = {'macd'};
cCharNamesSorted(strcmpi(cCharNamesSorted,'ppo_diff_signal')) = {'macd_diff_signal'};
cCharNamesSorted(strcmpi(cCharNamesSorted,'pvo')) = {'volmacd'};
cCharNamesSorted(strcmpi(cCharNamesSorted,'pvo_diff_signal')) = {'volmacd_diff_signal'};
cCharNamesSorted(strcmpi(cCharNamesSorted,'cmf')) = {'chaikin'};
yticks(1:length(cCharNamesSorted));
cCharNamesSortedTex = fAddSlash(fAddSlash(cCharNamesSorted, false), true);
yticklabels(cCharNamesSortedTex);

% Plot predictor selection over time
lIsAvail = ~all(isnan(mSelected)|mSelected==false,2);
h2 = figure(2);
mNotselected = 1 - mSelected(lIsAvail,vSortIdx);
vDatesOoS = vDates(lIsAvail);
imagesc(mNotselected');
colormap(gray);
yticks(1:length(cCharNamesSortedTex));
yticklabels(flipud(cCharNamesSortedTex));
xticks([38:52:350]);
xticklabels(2016:2022);
box off
vFracSelected = sum(mSelected(lIsAvail,vSortIdx),1)/sum(lIsAvail);
ax1 = gca; % Get the current axes
ax2 = axes('Position', ax1.Position, 'YAxisLocation', 'right', 'Color', 'none');
ax2.XTick = [];
ax2.YLim = ax1.YLim;
ax2.YTick = 1:length(cCharNamesSortedTex); % Clear y-ticks for the second axis
ax2.YTickLabel = flipud(sprintfc('%.1f', round(vFracSelected * 100,1))');

% Restore path
path(sOldPath);



