% Script for creating the trend characteristic (CTREND) and benchmark
% factors for various combinations of reseach designs
%
% Requires that b02CalculateIndicators.m was executed

% Clear console
clear; clc; close all;

% Set paths
sOldPath    = path;
sDataPath   = './DATA/';
addpath('./Utils/');

% Load design choices
load('DesignChoices.mat','tCombos');

% Execution-only range adapter for deterministic single-host sharding.  The
% complete published design table and its global setting numbers are retained;
% this only selects which rows this MATLAB client evaluates.  With both
% variables unset, the published behavior (all 3,072 rows) is unchanged.
sFirstCombo = getenv('OLD_V1_B09_FIRST_COMBO');
sLastCombo = getenv('OLD_V1_B09_LAST_COMBO');
if ~isempty(sFirstCombo) || ~isempty(sLastCombo)
    assert(~isempty(sFirstCombo) && ~isempty(sLastCombo), ...
        'Both OLD_V1_B09_FIRST_COMBO and OLD_V1_B09_LAST_COMBO are required');
    iFirstCombo = str2double(sFirstCombo);
    iLastCombo = str2double(sLastCombo);
    assert(isfinite(iFirstCombo) && isfinite(iLastCombo) && ...
        iFirstCombo == floor(iFirstCombo) && ...
        iLastCombo == floor(iLastCombo) && ...
        1 <= iFirstCombo && iFirstCombo <= iLastCombo && ...
        iLastCombo <= height(tCombos), ...
        'Invalid old v1 b09 combo range');
    lShardRows = tCombos.setting >= iFirstCombo & ...
        tCombos.setting <= iLastCombo;
    assert(nnz(lShardRows) == iLastCombo-iFirstCombo+1 && ...
        isequal(tCombos.setting(lShardRows), (iFirstCombo:iLastCombo)'), ...
        'Published design settings are not a complete ordered shard range');
    tCombos = tCombos(lShardRows,:);
    fprintf(['old_v1_b09_execution_range first_combo=%d ' ...
        'last_combo=%d count=%d\n'], ...
        iFirstCombo, iLastCombo, height(tCombos));
end
iNumCombos      = size(tCombos,1);

% Other settings that are no design choices
iMinNumAssets   = 5;  % Minimum assets in portfolios 
iMinNumObsCS    = 25; % Minimum cross-section
iStartDate      = 201416;       
iEndDate        = 202222; 
vQuantiles      = 0:0.2:1;

% Loop over data combinations
WaitBar = parfor_wait(iNumCombos,'WaitBar',false); % https://de.mathworks.com/matlabcentral/fileexchange/71083-waitbar-for-parfor
for iIdxC = 1:iNumCombos
    % Print progress
    fprintf(2, 'Estimate combo %i of %i\n', iIdxC, iNumCombos);

    % Extract setting
    sOutlierTreatment   = tCombos.cOutlierTreatment{iIdxC};
    dWinThreshold       = tCombos.vThreshold(iIdxC);
    lRoll               = tCombos.vRoll(iIdxC);
    lUseValueWeighted   = tCombos.vUseValueWts(iIdxC);
    iNumIn              = tCombos.vNumIn(iIdxC);
    dMinMCAP            = tCombos.vMinMCAP(iIdxC);
    dMinPrc             = tCombos.vMinPRC(iIdxC);
    lExclStable         = tCombos.vExclStable(iIdxC);
    iRetLead            = tCombos.vRetLead(iIdxC);
    lUseVolume          = tCombos.vUseVolume(iIdxC);
    iNumPorts           = length(vQuantiles);

    % Load data: Varying thresholds for trunction/winsorization
    iIdxDataComb = tCombos.data_setting(iIdxC);
    [rData, rMetaData, rChars] = fLoadData([sDataPath,sprintf('bCharacteristicsOLHC_Combo%i.mat', iIdxDataComb)]);

    % Extract data from struct
    mReturns        = rData.mReturns;
    mReturnsLead    = rData.mRetLead;
    mME             = rData.mME;
    mPrices         = rData.mClose;
    mVolume         = rData.mVolume;
    vDates          = rData.yrmoda;
    vMktRet         = rData.vMktRet;
    vAssetID        = rMetaData.vID;
    mMOM3           = [NaN(1, size(rChars.ret_3_0,2)); rChars.ret_3_0(1:end-1,:)]; % Used for CMOM

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
    mMOM3(~lIsSample,:)         = [];
    iNumObs                     = length(vDates);

    % Get returns for sorting
    if iRetLead == 1
        % 1-day implementation lag
        mRetSort = mReturnsLead;
    else
        % No implementation lag
        mRetSort = mReturns;
    end

    % Create LTW factors
    % CSMB uses 30% and 70% breakpoints: univariate sorts. L-H portfolios
    [vCSMB_EW, vCSMB] = fSingleSortFast(-mME_L1', mRetSort', mME_L1',...
            'vPercentile',[0, 0.3, 0.7, 1],...
            'iMinNumCS', iMinNumObsCS,...
            'iMinNumAssets',iMinNumAssets);

    % CMOM uses dependent sorts: First split into small and big
    % cryptocurrencies and then use 30% and 70% breakpoints
    rResultsCMOM = fDepDoubleSort(mME_L1', mMOM3', ...
        mRetSort', [], mME_L1', 'vPercentileA',0:0.5:1, ...
        'vPercentileB', [0, 0.3, 0.7, 1]);
    vCMOM = 0.5 * (rResultsCMOM.VW.cPortRets{1,end-1} + ...  % Small high
        rResultsCMOM.VW.cPortRets{2,end-1}) - ...             % Bigh high
        0.5 * (rResultsCMOM.VW.cPortRets{1,1} + ...           % Small low
        rResultsCMOM.VW.cPortRets{2,1});                      % Big low
    vCMOM_EW = 0.5 * (rResultsCMOM.EW.cPortRets{1,end-1} + ...  % Small high
        rResultsCMOM.EW.cPortRets{2,end-1}) - ...             % Bigh high
        0.5 * (rResultsCMOM.EW.cPortRets{1,1} + ...           % Small low
        rResultsCMOM.EW.cPortRets{2,1});                      % Big low

    % Merge
    mLTW    = [vCSMB, vCMOM'];
    mLTW_EW = [vCSMB_EW, vCMOM_EW'];

    % Ensure that all characteristic and return observations are available
    lAvail = all(~isnan(mChars_L1),3) & ~isnan(mReturns') & ~isnan(mME_L1');
    mReturns(~lAvail') = NaN;
    for iIdxChar = 1:iNumChars
        mCtemp = mChars_L1(:,:,iIdxChar);
        mCtemp(~lAvail) = NaN;
        mChars_L1(:,:,iIdxChar) = mCtemp;
    end

    % Define methods
    cTrendNames = {'FM','CFM',... % Fama-MacBeth, Combined Fama-MacBeth
        'C_ENET_SCS','C_ENET_SCS_T',... % CS-C-ENet (equal, and theta weighted)
        'POLS','CPOLS',... % Pooled OLS, combined POLS
        'C_ENET',...
        'C_ENET_SCS_VAL','C_ENET_SCS_VAL_T'};% CS-ENet with validation sample and theta weighted
    iNumTrend   = length(cTrendNames);

    % Initialize memory
    mTrend      = NaN(iNumObs, iNumTrend);
    mAvgRet     = NaN(iNumPorts, iNumTrend);

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
    iNumPanelObs    = length(vY);
    vAssetNum       = 1:iNumAssets;
    vTimeID         = 1:iNumObs;

    % Initialize memory
    mYhat       = NaN(iNumAssets, iNumObs, iNumTrend);
    mTrendEW_5  = NaN(iNumObs, iNumTrend); % Quintile, equal-weighted
    mTrendVW_5  = NaN(iNumObs, iNumTrend); % Quintile, value-weighted
    mTrendEW_3  = NaN(iNumObs, iNumTrend); % Tertile, equal-weighted
    mTrendVW_3  = NaN(iNumObs, iNumTrend); % Tertile, value-weighted

    % Loop over methods
    for iIdxM = 1:iNumTrend
        % Copy characteristics
        mCtemp = mC;

        switch upper(cTrendNames{iIdxM})
            case 'FM'
                % Replace missing values in characteristics with zeros
                mCtemp(isnan(mCtemp)) = 0;

                % Estimate Fama-MacBeth
                vYhatTemp = fWalkforwardFamaMacBethPanel(vY, mCtemp, mID, vW,...
                    'lEstAlpha',true,...
                    'iNumIn',iNumIn,...
                    'lRoll',lRoll);

            case 'CFM'
                % Estimate Combined Fama-MacBeth

                % Initialize memory
                mYhatTemp = NaN(length(vY), iNumChars);
                for iIdxV = 1:iNumChars
                    mYhatTemp(:,iIdxV) = fWalkforwardFamaMacBethPanel(vY, mCtemp(:,iIdxV), mID, vW,...
                    'lEstAlpha',true,...
                    'iNumIn',iNumIn,...
                    'lRoll',lRoll);
                end
                % Equally weighted average is the forecast
                vYhatTemp = mean(mYhatTemp,2,'omitmissing');

            case 'C_ENET_SCS'
                % Estimate CS-E-Net (4th output is theta-weighted forecast
                [vYhatTemp, mBeta, mSelected,vYhatTempTheta] = ...
                    fWalkforwardCSENET(vY, mCtemp, mID, vW,...
                    "dAlpha",0.5,...
                    "iNumIn",iNumIn,...
                    "lRoll",lRoll,...
                    "lEstAlpha",true);
            case 'C_ENET_SCS_T'
                % This is already estimated. Please do not change order of
                % methods
                vYhatTemp = vYhatTempTheta;

            case 'POLS' 
                % Pooled OLS

                % Replace missing values in characteristics with zeros
                mCtemp(isnan(mCtemp)) = 0;

                % Estimation
                vYhatTemp = fWalkforwardPanelRegression(vY, mCtemp, mID, vW,...
                    'lEstAlpha',true,...
                    'iNumIn',iNumIn,...
                    'lRoll',lRoll);

            case 'CPOLS' 
                % Combined Pooled OLS

                % Initialize memory
                mYhatTemp = NaN(length(vY), iNumChars);
                for iIdxV = 1:iNumChars
                    mYhatTemp(:,iIdxV) = fWalkforwardPanelRegression(vY, mCtemp(:,iIdxV), mID, vW,...
                    'lEstAlpha',true,...
                    'iNumIn',iNumIn,...
                    'lRoll',lRoll);
                end

                % Equally weighted average is the forecast
                vYhatTemp = mean(mYhatTemp,2,'omitmissing');

            case 'C_ENET'
                % Estimate C-E-Net (3rd output is theta-weighted forecast
                vYhatTemp = ...
                    fWalkforwardCENET(vY, mCtemp, mID, vW,...
                    "dAlpha",0.5,...
                    "iNumIn",iNumIn,...
                    "lRoll",lRoll,...
                    "lEstAlpha",true);

            case 'C_ENET_SCS_VAL'
                % Estimate CS-E-Net with validation sample (4th output is theta-weighted forecast
                [vYhatTemp, mBeta, mSelected,vYhatTempTheta] = ...
                    fWalkforwardCSENET(vY, mCtemp, mID, vW,...
                    "dAlpha",0.5,...
                    "iNumIn",iNumIn,...
                    "lRoll",lRoll,...
                    "lEstAlpha",true,...
                    "dFracVal",0.3);
                
            case 'C_ENET_SCS_VAL_T'
                % This is already estimated. Please do not change order of
                % methods
                vYhatTemp = vYhatTempTheta;

            otherwise
                error('Unknown method');
        end

        % Make panel to matrix
        mYhat(:,:,iIdxM) = fPanel2Matrix(vYhatTemp, mID(:,2), mID(:,1), vAssetNum, vTimeID);    

        % Sorts
        [mTrendEW_5(:,iIdxM), mTrendVW_5(:,iIdxM)] = ...
            fSingleSortFast(mYhat(:,:,iIdxM), mRetSort', mME_L1',...
            'vPercentile',0:0.2:1,...
            'iMinNumCS', iMinNumObsCS,...
            'iMinNumAssets',iMinNumAssets);
        [mTrendEW_3(:,iIdxM), mTrendVW_3(:,iIdxM)] = ...
            fSingleSortFast(mYhat(:,:,iIdxM), mRetSort', mME_L1',...
            'vPercentile',[0,0.3,0.7,1],...
            'iMinNumCS', iMinNumObsCS,...
            'iMinNumAssets',iMinNumAssets);
    end

    % Create filename
    sFilename = sprintf('./Results/CTREND/CTREND_Combo%i.mat', tCombos.setting(iIdxC));
    if lUseValueWeighted
        fSaveTREND(sFilename, mYhat, vDates, vAssetID, cTrendNames, mTrendVW_5, mTrendVW_3, mLTW)
    else
        fSaveTREND(sFilename,mYhat, vDates, vAssetID, cTrendNames, mTrendEW_5, mTrendEW_3, mLTW_EW)
    end
    WaitBar.Send()
end
WaitBar.Destroy()

% Restore path
path(sOldPath);

function [rData, rMetaData, rChars] = fLoadData(sFilename)
load(sFilename)
end
function fSaveTREND(sFilename,mYhat, vDates, vAssetID, cTrendNames, mTrend_5, mTrend_3, mLTW)
save(sFilename, 'mYhat','vDates','vAssetID','cTrendNames','mTrend_5','mTrend_3', 'mLTW');
end

