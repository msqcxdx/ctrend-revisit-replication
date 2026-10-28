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

% Find base data setting. In our baseline setting, we truncate extreme
% returns at the 0.5% and 99.5% levels. Therefore, we need to load the
% correct data set
iIdxBaseCombo = tDataCombos.data_setting(tDataCombos.vThreshold == 0.005 & ...
    strcmpi(tDataCombos.cOutlierTreatment,'trunc'));

% Load data
load(sprintf('%s/bCharacteristicsOLHC_Combo%i.mat', sDataPath, iIdxBaseCombo)); 

% Extract data
mY      = rData.mReturns;       % Returns
mME     = rData.mME;            % Market capitalization
mVOL    = rData.mVolume/7;      % Volume (divided by 7 to match Liu et al. results)
mPrc    = rData.mClose;         % Close
vDates  = rData.yrmoda;         % Dates 
vYnames = rMetaData.vID;        % IDs 
vMktRet = rData.vMktRet;        % Market return
lStable = rMetaData.lIsStable;  % Indicates whether this is a stable coin

% Restrict sample period
lIsSample   = vDates >= 201401 & vDates <= 202252;
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

% Remove error in volume (obvious data errors, manually checked)
mVOL(mVOL > 10^14) = NaN;

% Exclude stablecoins (we use this filter in baseline scenario)
mY(:,lStable)   = NaN;
mME(:,lStable)  = NaN;
mVOL(:,lStable) = NaN;
mME(:,lStable)  = NaN;
mPrc(:,lStable) = NaN;
vYnames(lStable)= NaN;

% Exclude all columns without data
lExclude                = all(isnan(mY),1) | all(isnan(mME),1); 
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

for iIdxY = 1:iNumYears
    % Get data
    lIsSample = vYear == vUniqueYear(iIdxY);
    mYtemp      = mY(lIsSample,:);
    mMEtemp     = mME(lIsSample,:);
    mVOLtemp    = mVOL(lIsSample,:);
    
    % Get number of unique assets
    vNumYear(iIdxY) = sum(any(~isnan(mMEtemp),1),2);
    
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
iNumUnique  = sum(any(~isnan(mY),1));
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
