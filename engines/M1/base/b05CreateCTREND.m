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
lUseValueWeighted   = true;     % Paper regression is market-cap WLS
lUseVolume          = true;     % Use volume indicators

% Settings for portfolio sorts
rOptions = struct();
rOptions.sFreq = 'weekly';                  % Data frequency
rOptions.lHedgeOnly = true;                 % H-L availability uses only its two legs
rOptions.iMinNumCS = 25;                    % Minimum cross section
rOptions.iMinNumAssets = 5;                 % Minimum number of assets in portfolio
rOptions.lEnsureAllObs = true;              % Ensure valid observation for market equity, returns, and sort variable
vQuantiles      = 0:0.2:1;                  % Percentiles for sorts
iNumPorts       = length(vQuantiles);

% Other settings that are no design choices
iStartDate      = 201416;       
iEndDate        = 202222; 

%% Analysis
% Select the baseline data-preparation design row.
iIdxDataComb = tCombos.data_setting( find(strcmpi(tCombos.cOutlierTreatment, sOutlierTreatment) & ...
    tCombos.vThreshold == dThreshold,1,'first') );

% Load raw data
load([sDataPath,sprintf('bCharacteristicsOLHC_Combo%i.mat', iIdxDataComb)]);
fAssertWeeklyDataProvenance(sDataBuildID, rInputProvenance, ...
    sWeeklyCodeFingerprint);
assert(strcmp(char(sDataBuildID), ...
    fGetCurrentWeeklyDataBuildID(sDataPath)), ...
    'Loaded weekly input is not part of the certified complete bundle');

% Extract data from struct
mReturns        = rData.mReturns;
mReturnsLead    = rData.mRetLead;
    assert(isfield(rData,'mPnlReturns') && ...
       isfield(rData,'mPnlRetLead') && ...
       isfield(rData,'mPnlRequiresReinvestment') && ...
       isfield(rData,'mPnlRetLeadRequiresReinvestment') && ...
       isfield(rData,'rEconomicReinvestmentLedgerReference') && ...
       isfield(rData,'mRawOutcomeObserved') && ...
       isfield(rData,'mRawOutcomeObservedLead'), ...
    ['Weekly input predates the separated statistical-label/economic-P&L ' ...
     'build; rerun b01ReadData and b02CalculateIndicators.']);
mPnlReturns     = rData.mPnlReturns;
mPnlRetLead     = rData.mPnlRetLead;
mRawOutcomeObserved = logical(rData.mRawOutcomeObserved);
mRawOutcomeObservedLead = logical(rData.mRawOutcomeObservedLead);
mME             = rData.mME;
mPrices         = rData.mClose;
mVolume         = rData.mVolume;
vDates          = rData.yrmoda;
vMktRet         = rData.vMktRet;
vRiskFree       = rData.vRiskFree;
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
parfor iIdxChar = 1:iNumChars
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
mPnlRetLead(~lIsSample,:)   = [];
mRawOutcomeObserved(~lIsSample,:) = [];
mRawOutcomeObservedLead(~lIsSample,:) = [];
mVolume(~lIsSample,:)       = [];
mME_L1(~lIsSample,:)        = [];
mPrices_L1(~lIsSample,:)    = [];
mME(~lIsSample,:)           = [];
mChars_L1(:,~lIsSample,:)   = [];
vDates(~lIsSample)          = [];
vMktRet(~lIsSample)         = [];
vRiskFree(~lIsSample)       = [];
iNumObs                     = length(vDates);

% Apply formation-time filters using lagged market cap and price
lRemoveObs                  = ~isfinite(mME_L1) | ~isfinite(mPrices_L1) | ...
                              (mME_L1 == 0) | (mME_L1 < dMinMCAP) | (mPrices_L1 < dMinPrc);
if lExclStable
    lRemoveObs              = lRemoveObs | rMetaData.lIsStable;
end
mReturns(lRemoveObs)        = NaN;
mReturnsLead(lRemoveObs)    = NaN;
mME_L1(lRemoveObs)          = NaN;

% Build the historical-week outlier reference from every formation-eligible
% return, before imposing predictor availability. Otherwise a missing
% technical indicator would change that week's return-cleaning cutoff.
lOutlierFit = isfinite(mReturns);
[vOutlierFitTime,vOutlierFitAsset] = find(lOutlierFit);
vOutlierFitY = mReturns(lOutlierFit);
mOutlierFitID = [vOutlierFitTime,vOutlierFitAsset];

% Equations (7)-(8) are J separate univariate regressions.  Rank predictor j
% on its own formation-eligible cross-section: missingness in any of the
% other 27 predictors must neither change j's percentile nor remove j from
% its univariate estimation sample.  Payoff availability is deliberately
% absent from this ex-ante transform.
lFormationEligible = isfinite(mME_L1');
[mCharsUse,mRawPredictorObserved] = ...
    fRankPredictorsOwnSupport(mChars_L1,lFormationEligible);
rPredictorSupportAudit = struct();
rPredictorSupportAudit.vObservedByPredictor = ...
    reshape(sum(mRawPredictorObserved,[1,2]),1,[]);
rPredictorSupportAudit.iUnionRows = ...
    nnz(any(mRawPredictorObserved,3));
rPredictorSupportAudit.iJointRows = ...
    nnz(all(mRawPredictorObserved,3));
rPredictorSupportAudit.sRankRule = ...
    ['Each predictor is ranked on its own formation-eligible observed ' ...
     'cross-section before any model-specific complete-case restriction'];

% Get asset weights
if lUseValueWeighted
    mWts_L1 = (mME_L1 ./ sum(mME_L1,2,'omitmissing'))';
else
    mWts_L1 = [];
end

% b02 deliberately keeps raw returns. Clean each already-realized historical
% training week on its own formation-eligible return cross-section. Because
% the model then demeans outcomes within each week, using raw returns is
% algebraically identical to first subtracting the common weekly risk-free
% rate and then demeaning.
mRet = mReturns;

% The realized return used for economic evaluation may differ from the model
% label when the one-day implementation-lag design is selected.  It must stay
% raw: historical-label preprocessing cannot rewrite an investor's payoff.
if iRetLead == 1
    mRetPnl = mPnlRetLead;
    sPayoffTiming = 'lead1';
    mRetRawObserved = mRawOutcomeObservedLead';
else
    mRetPnl = mPnlReturns;
    sPayoffTiming = 'ordinary';
    mRetRawObserved = mRawOutcomeObserved';
end

% Preserve the union of predictor-specific rows.  fWalkforwardCSENET fits
% each equation-(7) regression on j's own finite X/Y/W rows; only the
% elastic-net selection regression requires a complete forecast vector.
[mC, vY, mID, vW] = fCreatePanelExAnte( ...
    mCharsUse,mRet',mWts_L1,'lKeepPredictorUnion',true);
iNumPanelObs      = length(vY);
vAssetNum         = 1:iNumAssets;
vTimeID           = 1:iNumObs;
vEvaluationY      = mRetPnl(sub2ind(size(mRetPnl), mID(:,1), mID(:,2)));
rOutlierAudit = fBuildHistoricalWeeklyOutlierAudit(vOutlierFitY, ...
    mOutlierFitID,vTimeID(:),iNumIn,lRoll,0, ...
    sOutlierTreatment,dThreshold);

% Estimate the aggregate trend characteristic using the CS-E-Net. The
% canonical corrected pipeline always estimates predictions from the
% certified weekly inputs; existing result files are never a cache.
sFilename = './Results/CTREND/CTREND_Base.mat';
[vYhatTemp, mBeta, mSelected, ~, vPnlRawOOS, vLabelOOS, ...
    rForecastAudit] = ...
    fWalkforwardCSENET(vY, mC, mID, vW,...
    "dAlpha",0.5,...
    "iNumIn",iNumIn,...
    "lRoll",lRoll,...
    "vAllTimeID",vTimeID(:),...
    "lEstAlpha",true,...
    "sOutlierTreatment",sOutlierTreatment,...
    "dOutlierThreshold",dThreshold,...
    "lDemeanY",true,...
    "vEvaluationY",vEvaluationY,...
    "vOutlierFitY",vOutlierFitY,...
    "mOutlierFitID",mOutlierFitID);
mYhat = fPanel2Matrix(vYhatTemp, mID(:,2), mID(:,1), ...
    vAssetNum, vTimeID);

% Keep statistical evaluation and economic accounting separate. The
% OOS statistical label is the raw strict core return and is not
% cross-sectionally demeaned; P&L remains the genuine raw endpoint return.
% Both live on the same ex-ante OOS calendar and neither is outlier-cleaned.
vPnlRawOOSCheck = fBuildRawOOSPanelOutcome( ...
    vEvaluationY,mID,vTimeID(:),iNumIn);
assert(isequaln(vPnlRawOOS,vPnlRawOOSCheck), ...
    'Walk-forward raw P&L output must match the scheduled OOS accounting identity');
mRetPnlOOS = fPanel2Matrix(vPnlRawOOS, mID(:,2), mID(:,1), ...
    vAssetNum, vTimeID);
mRetLabelOOS = fPanel2Matrix(vLabelOOS, mID(:,2), mID(:,1), ...
    vAssetNum, vTimeID);
vModelDates = vDates(iNumIn+1:end);
assert(numel(vModelDates) == size(mBeta,1) && ...
       size(mSelected,1) == size(mBeta,1) && ...
       numel(rForecastAudit.cSelectionStatus) == size(mBeta,1), ...
    'Saved model-date axis must agree with beta and selection rows');
assert(isequal(size(mRetRawObserved),[iNumAssets,iNumObs]), ...
    'Raw outcome-observation mask must be asset by calendar week');

% Sort
% Portfolio accounting uses the authenticated frozen event calendar.  Any
% terminal proceeds are reinvested immediately within the same selected leg;
% no cash or cross-leg transfer is possible.
[rOptions,rEconomicReinvestmentLedger,vLedgerWeekRow] = ...
    fAttachEconomicLedgerOptions(rOptions,sDataPath,rData, ...
    vAssetID(:),vDates(:),sPayoffTiming);
cResults = fSingleSortMulti(mYhat, mRetPnlOOS, 0:0.2:1,[],mME_L1',rOptions);
rEconomicReinvestmentLedgerReference = ...
    rData.rEconomicReinvestmentLedgerReference;
clear rEconomicReinvestmentLedger

sCodeFingerprint = fPipelineCodeFingerprint(pwd);
sPredictionSourceFingerprint = sCodeFingerprint;
sTemporary = [tempname(fileparts(sFilename)),'.mat'];
rCleanup = onCleanup(@() iDeleteIfExists(sTemporary));
save(sTemporary, 'mYhat','mRetLabelOOS','mRetPnlOOS', ...
    'cResults','sPayoffTiming','vLedgerWeekRow', ...
    'mRetRawObserved','vDates','vModelDates','vAssetID','mBeta','mSelected', ...
    'cTechnicalIndicators','sCodeFingerprint','sDataBuildID', ...
    'sPredictionSourceFingerprint','rOutlierAudit', ...
    'rPredictorSupportAudit','rForecastAudit', ...
    'rEconomicReinvestmentLedgerReference');
[lMoved,sMoveMessage] = movefile(sTemporary,sFilename,'f');
assert(lMoved,'Could not atomically publish %s: %s', ...
    sFilename,sMoveMessage);
clear rCleanup

% Restore path
path(sOldPath);

function iDeleteIfExists(sFilename)
if exist(sFilename,'file') == 2
    delete(sFilename);
end
end
