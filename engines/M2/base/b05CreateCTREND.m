% Script for creating the trend characteristic (CTREND) using the
% CS-C-ENet. 
% 
% Requires that b02CalculateIndicators was executed

% Clear console
clear; clc; close all;

% Set paths
sOldPath    = path;
sDataPath   = './DATA/';
addpath('./Utils/');

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
lUseValueWeighted   = true;     % Use value-weighted objective function
lUseVolume          = true;     % Use volume indicators

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

% M2 preserves M0 features and model parameters but uses the return layer
% frozen before realized-return outlier treatment.  The legacy-cleaned M0
% fields remain in the weekly file for statistical consumers outside this
% OOS factor construction.
assert(isfield(rData,'mReturnsM2Raw') && isfield(rData,'mRetLeadM2Raw') && ...
    isfield(rData,'mPnlReturnsM2') && isfield(rData,'mPnlRetLeadM2') && ...
    isfield(rData,'rEconomicReinvestmentLedgerReference'), ...
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

% Lag market equity
mME_L1 = [NaN(1, iNumAssets); mME(1:end-1,:)];
mPrices_L1 = [NaN(1, iNumAssets); mPrices(1:end-1,:)];

% Restrict to sample period
lIsSample                   = vDates >= iStartDate & vDates <= iEndDate;
mReturns(~lIsSample,:)      = [];
mReturnsLead(~lIsSample,:)  = [];
mPnlReturns(~lIsSample,:)   = [];
mPnlReturnsLead(~lIsSample,:) = [];
mVolume(~lIsSample,:)       = [];
mME_L1(~lIsSample,:)        = [];
mPrices_L1(~lIsSample,:)    = [];
mME(~lIsSample,:)           = [];
mChars_L1(:,~lIsSample,:)   = [];
vDates(~lIsSample)          = [];
vMktRet(~lIsSample)         = [];
iNumObs                     = length(vDates);

% Apply every M0 screen at the formation boundary.  The payoff-period
% market cap/price must not decide whether the position existed.
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

% Retain M0's all-predictor intersection, but determine it entirely from
% formation-time X and weights.  Future Y is absent from ranking/support.
lAvail = all(~isnan(mChars_L1),3) & ~isnan(mME_L1');
for iIdxChar = 1:iNumChars
    mCtemp = mChars_L1(:,:,iIdxChar);
    mCtemp(~lAvail) = NaN;
    mChars_L1(:,:,iIdxChar) = mCtemp;
end
mME_L1(~lAvail') = NaN;

% Get asset weights
if lUseValueWeighted
    mWts_L1 = (mME_L1 ./ sum(mME_L1,2,'omitmissing'))';
else
    mWts_L1 = [];
end

% Rank transformation of characteristics
mCharsUse = permute(fCrossSectTransChars(permute(mChars_L1, [1,3,2]), 'rank'), [1,3,2]);

% Clean each weekly label on that already-realized week's formation-screened
% return cross-section, before predictor availability is applied.  This
% preserves M0's separation between the data-setting outlier rule and later
% model support: changing the predictor set (for example, volume on/off) may
% change the joint M0 estimation panel, but cannot change the return cutoff.
% The raw layer below remains the OOS payoff and is never transformed.
[mTrainingClean,rM2OutlierAudit] = fCleanWeeklyLabelsM2( ...
    mReturns,sOutlierTreatment,dThreshold);
mRetRaw = fDemeanWeeklyM2(mReturns);
mRetEstimation = fDemeanWeeklyM2(mTrainingClean);

% Stack M0's joint-complete X/W support independently of future Y.
[mC, vY, mID, vW] = fCreatePanelExAnteM2( ...
    mCharsUse,mRetRaw',mWts_L1);
vYEstimation = mRetEstimation(sub2ind(size(mRetEstimation), ...
    mID(:,1),mID(:,2)));
iNumPanelObs      = length(vY);
vAssetNum         = 1:iNumAssets;
vTimeID           = 1:iNumObs;

% Estimate aggregate trend characteristic using the CS-E-Net
[vYhatTemp, mBeta, mSelected] = fWalkforwardCSENET(vY, mC, mID, vW,...
    "dAlpha",0.5,...
    "iNumIn",iNumIn,...
    "lRoll",lRoll,...
    "lEstAlpha",true,...
    "vYEstimation",vYEstimation);

% Make panel to matrix
mYhat = fPanel2Matrix(vYhatTemp, mID(:,2), mID(:,1), vAssetNum, vTimeID);    

% Training labels above remain M2's M0-style statistical layer.  Portfolio
% realization is a separate endpoint layer with frozen exits and immediate
% same-leg reinvestment.
if iRetLead == 0
    mRetPnlOOS = mPnlReturns';
    sPayoffTiming = 'ordinary';
else
    mRetPnlOOS = mPnlReturnsLead';
    sPayoffTiming = 'lead1';
end
[rOptions,~,~] = fAttachEconomicLedgerOptions( ...
    rOptions,sDataPath,rData,vAssetID(:),vDates,sPayoffTiming);
cResults = fSingleSortMulti(mYhat,mRetPnlOOS,0:0.2:1,[],mME_L1',rOptions);
rEconomicReinvestmentLedgerReference = ...
    rData.rEconomicReinvestmentLedgerReference;

% Create filename
sFilename = sprintf('./Results/CTREND/CTREND_Base.mat');
rM2Scope = struct('sBase','M0','sChange', ...
    'future_data_paths_plus_shared_economic_settlement', ...
    'lPredictorOwnSupport',false, ...
    'lUsesEndpointSameLegReinvestment',true, ...
    'lAllowsCashAfterExit',false);
save(sFilename, 'mYhat','cResults','vDates','vAssetID','mBeta', ...
    'mSelected','mRetPnlOOS','sPayoffTiming', ...
    'rEconomicReinvestmentLedgerReference', ...
    'rM2OutlierAudit','rM2Scope');

% Restore path
path(sOldPath);
