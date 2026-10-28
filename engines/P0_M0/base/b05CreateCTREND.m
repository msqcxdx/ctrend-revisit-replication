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

% Extract data from struct
mReturns        = rData.mReturns;
mReturnsLead    = rData.mRetLead;
mME             = rData.mME;
mPrices         = rData.mClose;
mVolume         = rData.mVolume;
vDates          = rData.yrmoda;
vMktRet         = rData.vMktRet;
vAssetID        = rMetaData.vID;

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

% Restrict to sample period
lIsSample                   = vDates >= iStartDate & vDates <= iEndDate;
mReturns(~lIsSample,:)      = [];
mReturnsLead(~lIsSample,:)  = [];
mVolume(~lIsSample,:)       = [];
mME_L1(~lIsSample,:)        = [];
mME(~lIsSample,:)           = [];
mChars_L1(:,~lIsSample,:)   = [];
vDates(~lIsSample)          = [];
vMktRet(~lIsSample)         = [];
iNumObs                     = length(vDates);

% Ensure that all characteristic and return observations are available
lAvail = all(~isnan(mChars_L1),3) & ~isnan(mReturns') & ~isnan(mME_L1');
mReturns(~lAvail') = NaN;
for iIdxChar = 1:iNumChars
    mCtemp = mChars_L1(:,:,iIdxChar);
    mCtemp(~lAvail) = NaN;
    mChars_L1(:,:,iIdxChar) = mCtemp;
end

% Get asset weights
if lUseValueWeighted
    mWts_L1 = (mME_L1 ./ sum(mME_L1,2,'omitmissing'))';
else
    mWts_L1 = [];
end

% Rank transformation of characteristics
mCharsUse = permute(fCrossSectTransChars(permute(mChars_L1, [1,3,2]), 'rank'), [1,3,2]);

% Demean returns in the cross-section (not used in sorts but only for estimation)
mRet = mReturns - mean(mReturns,2,'omitmissing');

% To panel matrix
[mC, vY, mID, vW] = fCreatePanelFast(mCharsUse, mRet', mWts_L1);
iNumPanelObs      = length(vY);
vAssetNum         = 1:iNumAssets;
vTimeID           = 1:iNumObs;

% Estimate aggregate trend characteristic using the CS-E-Net
[vYhatTemp, mBeta, mSelected] = fWalkforwardCSENET(vY, mC, mID, vW,...
    "dAlpha",0.5,...
    "iNumIn",iNumIn,...
    "lRoll",lRoll,...
    "lEstAlpha",true);

% Make panel to matrix
mYhat = fPanel2Matrix(vYhatTemp, mID(:,2), mID(:,1), vAssetNum, vTimeID);    

% Sort
cResults = fSingleSortMulti(mYhat, mReturns', 0:0.2:1,[],mME_L1',rOptions);

% Create filename
sFilename = sprintf('./Results/CTREND/CTREND_Base.mat');
save(sFilename, 'mYhat','cResults','vDates','vAssetID','mBeta','mSelected');

% Restore path
path(sOldPath);