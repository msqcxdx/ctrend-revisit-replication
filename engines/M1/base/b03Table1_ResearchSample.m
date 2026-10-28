% Script for creating Table 1 that shows summary statistics, including the
% number of cryptocurrencies per year and the mean and median market
% capitalization and dollar trading volume. 
%
% 
% Requires that b02CalculateIndicators was executed

% Clear console
clear; clc; close all;

% Set paths
sOldPath    = path;
sDataPath   = './DATA/';
addpath('./LatexTables');

% Load data settings
load('DesignChoices.mat','tDataCombos');

% Select the baseline filename used by the paper's design table.
iIdxBaseCombo = tDataCombos.data_setting(tDataCombos.vThreshold == 0.005 & ...
    strcmpi(tDataCombos.cOutlierTreatment,'trunc'));

% Load data
load(sprintf('%s/bCharacteristicsOLHC_Combo%i.mat', sDataPath, iIdxBaseCombo)); 
fAssertWeeklyDataProvenance(sDataBuildID, rInputProvenance, ...
    sWeeklyCodeFingerprint);

% Extract data
mY      = rData.mReturns;       % Returns
mME     = rData.mME;            % Market capitalization
assert(isfield(rData,'vNumDaysWeek') && ...
    numel(rData.vNumDaysWeek) == size(rData.mVolume,1), ...
    'Weekly block lengths are required for Table 1 daily-average volume.');
mVOL    = rData.mVolume ./ rData.vNumDaysWeek(:);
mPrc    = rData.mClose;         % Close
vDates  = rData.yrmoda;         % Dates 
vYnames = rMetaData.vID;        % IDs 
vMktRet = rData.vMktRet;        % Market return
lStable = rMetaData.lIsStable;  % Indicates whether this is a stable coin

% Table 1 describes the paper's evaluation period, not the preceding
% 52-week model-training history.  The paper explicitly starts the reported
% sample in April 2015 and ends it in May 2022.
iEvaluationStart = 201516;
iEvaluationEnd   = 202222;
lIsSample   = vDates >= iEvaluationStart & vDates <= iEvaluationEnd;
mY          = mY(lIsSample,:);
mME         = mME(lIsSample,:);
mVOL        = mVOL(lIsSample,:);
mPrc        = mPrc(lIsSample,:);
vMktRet     = vMktRet(lIsSample);
vDates      = vDates(lIsSample);

% Keep only the years
vYear = cellstr(num2str(vDates));
vYear = cell2mat(cellfun(@(x)str2num(x(1:4)),vYear,'UniformOutput',false));

% Set market captialization filter (we use it in baseline scenario)
lFilterMCAP       = mME < 1e6;
mY(lFilterMCAP)   = NaN;
mVOL(lFilterMCAP) = NaN;
mPrc(lFilterMCAP) = NaN;
mME(lFilterMCAP)  = NaN;

% Exclude stablecoins (we use this filter in baseline scenario)
mY(:,lStable)   = NaN;
mME(:,lStable)  = NaN;
mVOL(:,lStable) = NaN;
mME(:,lStable)  = NaN;
mPrc(:,lStable) = NaN;
vYnames(lStable)= NaN;

% The paper defines one valid observation by jointly observed close, volume,
% and market capitalization. Apply that definition consistently before both
% annual and full-sample counts/statistics. A finite market-cap boundary by
% itself is not a valid weekly observation for a short-history asset.
lValidWeeklyCore = isfinite(mPrc) & isfinite(mVOL) & isfinite(mME);
mY(~lValidWeeklyCore) = NaN;
mME(~lValidWeeklyCore) = NaN;
mVOL(~lValidWeeklyCore) = NaN;
mPrc(~lValidWeeklyCore) = NaN;

% Exclude all columns without data
lExclude                = all(~(isfinite(mPrc) & isfinite(mVOL) & isfinite(mME)),1);
mY(:,lExclude)          = [];
mME(:,lExclude)         = [];
mVOL(:,lExclude)        = [];
mPrc(:,lExclude)        = [];
vYnames(lExclude)       = [];

% Count number of coins per year
vUniqueYear     = unique(vYear);
iNumYears       = length(vUniqueYear);
vNumYear        = NaN(iNumYears,1);
vMeanME         = NaN(iNumYears,1);
vMedME          = NaN(iNumYears,1);
vMeanVOL        = NaN(iNumYears,1);
vMedVOL         = NaN(iNumYears,1);

parfor iIdxY = 1:iNumYears
    % Get data
    lIsSample = vYear == vUniqueYear(iIdxY);
    mYtemp      = mY(lIsSample,:);
    mMEtemp     = mME(lIsSample,:);
    mVOLtemp    = mVOL(lIsSample,:);
    
    % Get number of unique assets
    vNumYear(iIdxY) = sum(any(isfinite(mMEtemp) & ...
        isfinite(mVOLtemp),1),2);
    
    % Get average and median market capitalization
    vMeanME(iIdxY)  = mean(mMEtemp,'all','omitnan')/1e6;
    vMedME(iIdxY)   = median(mMEtemp,'all','omitnan')/1e6;

    % Get average and median trading volume
    vMeanVOL(iIdxY) = mean(mVOLtemp,'all','omitnan')/1000;
    vMedVOL(iIdxY)  = median(mVOLtemp,'all','omitnan')/1000;
end

% Create table
cTable1 = [sprintfc('%i',[vUniqueYear, vNumYear]), sprintfc('%.2f',round([vMeanME, vMedME],2)),...
    sprintfc('%.2f',round([vMeanVOL, vMedVOL],2))];
cTable1 = [{'Year', ' Number', 'Mean (ME)', 'Median (ME)','Mean (VOL)','Median (VOL)'}; cTable1];

% Add full sample properties
iNumUnique  = sum(any(isfinite(mME) & isfinite(mVOL) & isfinite(mPrc),1));
dMeanME     = mean(mME,'all','omitnan')/1e6;
dMedME      = median(mME,'all','omitnan')/1e6;
dMeanVOL    = mean(mVOL,'all','omitnan')/1e3;
dMedVOL     = median(mVOL,'all','omitnan')/1e3;
cTable1     = [cTable1; [{'Full'},sprintfc('%i',iNumUnique), ...
    sprintfc('%.2f',round([dMeanME,dMedME,dMeanVOL,dMedVOL],2))]];

rInput = struct();
rInput.table = cTable1;
rInput.tableCaption = 'Research Sample';
rInput.tableLabel = 't:summary';
fCreateLatexTable(rInput);

% Restore path
path(sOldPath); 
