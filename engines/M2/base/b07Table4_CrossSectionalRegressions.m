% Script for performing cross-sectional regressions to test for the
% predictive power of the CTREND characteristic after controlling for
% multiple other characteristics
%
% Requires that b05CreateCTREND and b06Table3_UnivariatePortfolioSorts 
% were executed
%
% This script produces:
%   Table 4:    Cross-Sectional Regressions

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

% Specify models
cModels{1,1}  = {'CTREND'};
cModels{2,1}  = {'CTREND', 'BETA'};
cModels{3,1}  = {'CTREND', 'MCAP'};
cModels{4,1}  = {'CTREND', 'BETA', 'MCAP'};
cModels{5,1}  = {'CTREND', 'BETA', 'MCAP', 'ILLIQ'};
cModels{6,1}  = {'CTREND', 'BETA', 'MCAP', 'IVOL'};
cModels{7,1}  = {'CTREND', 'BETA', 'MCAP', 'ILLIQ', 'IVOL'};
cModels{8,1}  = {'CTREND', 'RET_1_0'};
cModels{9,1}  = {'CTREND', 'RET_2_0'};
cModels{10,1} = {'CTREND', 'RET_3_0'};
cModels{11,1} = {'CTREND', 'RET_4_0'};
cModels{12,1} = {'CTREND', 'BETA', 'MCAP', 'ILLIQ','IVOL','RET_1_0', 'RET_2_0', 'RET_3_0', 'RET_4_0'};
iNumModels    = length(cModels);
cCharNames    = unique(horzcat(cModels{:}),'stable');
iNumVars      = length(cCharNames);

%% Analysis
% Find number of data setting
iIdxDataComb = tCombos.data_setting( find(strcmpi(tCombos.cOutlierTreatment, sOutlierTreatment) & ...
    tCombos.vThreshold == dThreshold,1,'first') );

% Load data
load([sDataPath,sprintf('bCharacteristicsOLHC_Combo%i.mat', iIdxDataComb)]);

% Scale characteristics for better interpretability
rChars.illiq = rChars.illiq * 100;

% Table 4 remains M0's statistical-label regression.  Its realised return is
% an ex-post regression outcome: it does not enter CTREND formation, ranking,
% estimation, validation, prediction, or portfolio weights.  Replacing this
% M0 statistical label with the separate raw portfolio-payoff layer would
% therefore be a non-look-ahead estimand change, which M2 must not import.
mReturns        = rData.mReturns;
mReturnsLead    = rData.mRetLead;
mME             = rData.mME;
mPrices         = rData.mClose;
mVolume         = rData.mVolume;
vDates          = rData.yrmoda;
vMktRet         = rData.vMktRet;

% Determine dimensions
[iNumObs, iNumAssets]   = size(mReturns);
iNumChars               = length(cCharNames);

% Lag characteristics and convert to matrix
mChars_L1   = NaN(iNumAssets, iNumObs, iNumChars);
for iIdxChar = 1:iNumChars
    % Lag characteristic
    if ~strcmpi(cCharNames{iIdxChar},'CTREND') % We insert CTREND later
        mCtemp = [NaN(1, iNumAssets); rChars.(lower(cCharNames{iIdxChar}))(1:end-1,:)]';
        mChars_L1(:,:,iIdxChar) = mCtemp;
    end
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
mME_L1(lRemoveObs) = NaN;

% Create weights
mWts_L1 = mME_L1 ./ sum(mME_L1,2,'omitmissing');

% Add trend to characteristics
mChars_L1(:,:,strcmp(cCharNames,'CTREND')) = rCTREND.mYhat;

% To panel matix
[mC, vY, mID, vW] = fCreatePanelFast(mChars_L1, mReturns', mWts_L1');

% Initialize memory
mGamma      = NaN(iNumVars+1, iNumModels);
mGammaT     = NaN(iNumVars+1, iNumModels);
for iIdxM = 1:iNumModels
    % Find position of variables to consider
    cCharsTemp = cModels{iIdxM};                       % Names of variables to consider
    [~,idx]    = ismember(cCharsTemp,cCharNames);      % Position of variables in mChars_L1

    % Get characteristics
    mCtemp     = mC(:,idx);

    % Run Fama-MacBeth regression
    rResultsFM = fEstFamaMacBethPanel(vY, mCtemp, mID, vW, ...
        "lEstAlpha",true,"iNumLagsNW",12);
    
    % Safe coefficients
    idx = [1, idx+1]; % Including intercept
    mGamma(idx, iIdxM)  = rResultsFM.vGamma;
    mGammaT(idx, iIdxM) = rResultsFM.vGammaT;
end

% Create table
cTable4 = fAddStatistics( fMatrix2Cell(mGamma,2,true),...
    fMatrix2Cell(mGammaT,2,true),...
    abs(round(mGammaT,2)) >= 1.96);
cTable4(isnan(mGamma)) = {''};
cTable4 = [[{''}, sprintfc('%i', 1:iNumModels)]; [[{'Intercept'};lower(cCharNames(:))], cTable4]];
rInput.table = cTable4;
rInput.tableCaption = 'Cross-Sectional Regressions';
fCreateLatexTable(rInput);

% Restore path
path(sOldPath);
