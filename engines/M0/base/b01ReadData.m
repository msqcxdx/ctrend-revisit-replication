% Script for reading the raw data obtained from CoinmarketCap.com
%
% The execution of this script requires the following .csv files
%   close_cmc:          Closing prices
%   low_cmc:            Low prices
%   high_cmc:           High prices
%   open_cmc:           Open prices
%   market_cap_cmc:     Market capitalization
%   volume_cmc:         Volume in $
%
% All files are aranged as follows: The first row contains the asset IDs
% and the first column contains the dates

% Clear console
clear, clc; close all;

% Set paths
sOldPath    = path;
addpath('./Utils');
sInDataPath = './DATA/';

% Read open, low, high, and close prices
mClose                  = readmatrix([sInDataPath,'close_cmc.csv']);
mLow                    = readmatrix([sInDataPath,'low_cmc.csv']);
mHigh                   = readmatrix([sInDataPath,'high_cmc.csv']);
mOpen                   = readmatrix([sInDataPath,'open_cmc.csv']);

% Get asset IDs
vAssetID_Close          = mClose(1,2:end); 
vAssetID_Low            = mLow(1,2:end);
vAssetID_High           = mHigh(1,2:end);
vAssetID_Open           = mOpen(1,2:end);

% Check IDs
assert( all(vAssetID_Close == vAssetID_Low), 'Order incorrect');
assert( all(vAssetID_Close == vAssetID_High), 'Order incorrect');
assert( all(vAssetID_Close == vAssetID_Open), 'Order incorrect');

% Remove irrelevant rows and columns
mClose                  = mClose(2:end,2:end);
mLow                    = mLow(2:end,2:end);
mHigh                   = mHigh(2:end,2:end);
mOpen                   = mOpen(2:end,2:end);

% Invalid prices to NaN
mClose(mClose <= 0)     = NaN;
mLow(mLow <= 0)         = NaN;
mHigh(mHigh <= 0)       = NaN;
mOpen(mOpen <= 0)       = NaN;

% Calculate percentage returns from closing prices (non-lagged)
mReturns = [NaN(1, size(mClose,2)); (mClose(2:end,:)./mClose(1:end-1,:)) - 1];

% Read market capitalization
mME             = readmatrix([sInDataPath,'market_cap_cmc.csv']);
vAssetID_ME     = mME(1,2:end);
mME             = mME(2:end,2:end);

% Remove MCAP larger than Bitcoin (must be wrong)
vME_Bitcoin     = mME(:,vAssetID_ME==1);
lRemoveObs      = mME <= 0 | mME > vME_Bitcoin;
mME(lRemoveObs) = NaN;

% Read volume
mVolume         = readmatrix([sInDataPath,'volume_cmc.csv']);
vAssetID_Vol    = mVolume(1,2:end);
mVolume         = mVolume(2:end,2:end);

% Load meta data (this is a struct with fields)
%   .vID:           Asset ID
%   .cCoinType:     'coin' or 'token'
%   .vStableCoin:   Logical that indicates whether asset is a stable coin
%   .cName:         Name
%   .cSymbol:       Symbol
load([sInDataPath, 'MetaData.mat']);

% Remove assets that are not included in all matrices (i.e., prices, market cap,
% volume, or meta data)
lKeepAssetP = ismember(vAssetID_Close, vAssetID_ME) & ismember(vAssetID_Close, vAssetID_Vol) & ...
    ismember(vAssetID_Close, rMetaData.vID);
lKeepAssetME = ismember(vAssetID_ME, vAssetID_Close) & ismember(vAssetID_ME, vAssetID_Vol) & ...
    ismember(vAssetID_ME, rMetaData.vID);
lKeepAssetVol = ismember(vAssetID_Vol, vAssetID_ME) & ismember(vAssetID_Vol, vAssetID_Close) & ...
    ismember(vAssetID_Vol, rMetaData.vID);
lKeepAssetMeta = ismember(rMetaData.vID, vAssetID_Vol) & ismember(rMetaData.vID, vAssetID_ME) & ...
    ismember(rMetaData.vID, vAssetID_Close);

% Remove these assets
mReturns(:,~lKeepAssetP)    = [];
mClose(:,~lKeepAssetP)      = [];
mLow(:,~lKeepAssetP)        = [];
mHigh(:,~lKeepAssetP)       = [];
mOpen(:,~lKeepAssetP)       = [];
mME(:,~lKeepAssetME)        = [];
mVolume(:,~lKeepAssetVol)   = [];
vAssetID_Close(~lKeepAssetP)= [];
vAssetID_ME(~lKeepAssetME)  = [];
vAssetID_Vol(~lKeepAssetVol)= [];
rMetaData = structfun(@(x)x(lKeepAssetMeta),rMetaData,'UniformOutput',false);

% Ensure that all asset IDs agree
assert(all(vAssetID_Close(:) == rMetaData.vID), 'Asset IDs in prices and returns do not agree');
assert(all(vAssetID_ME(:) == rMetaData.vID), 'Asset IDs in market capitalization do not agree');
assert(all(vAssetID_Vol(:) == rMetaData.vID), 'Asset IDs in volume do not agree');

% Read date
dtDate      = readcell([sInDataPath,'close_cmc.csv'],'Range','A:A');
dtDate(1)   = []; % We removed this before
dtDate      = vertcat(dtDate{:});

% Transform date to numeric
yrmoda      = str2num(datestr(dtDate,'YYYYmmdd'));

% Read risk free rate from Fama-French
tFFdaily            = readtable([sInDataPath, 'F-F_Research_Data_Factors_daily.CSV'],...
    'Range','A22000:E44000');
cVarNames           = readcell([sInDataPath, 'F-F_Research_Data_Factors_daily.CSV'],'Range','A5:E5');
cVarNames{1}        = 'Date';
tFFdaily.Properties.VariableNames = cVarNames;
tFFdaily(isnan(tFFdaily.Date),:) = [];
tFFdaily            = table2timetable(tFFdaily(:,'RF'),...
    'RowTimes',datetime(cellstr(num2str(tFFdaily.Date)),'InputFormat','yyyyMMdd'));

% Add non-business days. Note that FF data covers only five days a week,
% while the cryptocurrency data is available seven days a week. We need to
% adjust for this
dtDatesAll = (tFFdaily.Properties.RowTimes(1):tFFdaily.Properties.RowTimes(end))';
tFFdaily            = retime(tFFdaily,dtDatesAll,'previous');

% Keep only common dates
[yrmoda, idxA, idxB] = intersect(str2num(datestr(tFFdaily.Time,'YYYYmmdd')), yrmoda);
tFFdaily    = tFFdaily(idxA,:);
tFFdaily.RF = tFFdaily.RF/100;   % Make to decimal number
vRiskFree   = tFFdaily.RF;

% Keep only relevant meta data
rMetaData2.cName            = rMetaData.cName;
rMetaData2.cSymbol          = rMetaData.cSymbol;
rMetaData2.lIsCoin          = strcmpi(rMetaData.cCoinType,'coin')';
rMetaData2.lIsStable        = logical(rMetaData.vStableCoin)';
rMetaData2.vID              = vAssetID_Close;
rMetaData = rMetaData2;

%% Remove data errors

% Price must not be lower than low price
lTooLow                 = (mClose - mLow) < -1e-10;
mClose(lTooLow)         = NaN;

% Price must not be higher than high price
lTooHigh                = mClose > mHigh;
mClose(lTooHigh)        = NaN;

% Shared new-3x3 preprocessing: fill internal missing OHLC fields from the
% most recent earlier close, never fill after the last original close, and
% represent NaN, Inf, or negative volume/turnover as zero.
[mOpen,mHigh,mLow,mClose,mVolume,rUnifiedMissingPreprocessing] = ...
    fApplyUnifiedMissingDataPreprocessing( ...
    mOpen,mHigh,mLow,mClose,mVolume,yrmoda(:),vAssetID_Close(:));
mReturns = [NaN(1,size(mClose,2)); ...
    mClose(2:end,:)./mClose(1:end-1,:)-1];
mCloseEconomicRaw = mClose;
mMEEconomicRaw = mME;

% Ensure that every observation has price and market value
[lIsAvailObs, mME, mClose, mLow, mHigh, mOpen] = ...
    fEnsureAllObs(mME, mClose, mLow, mHigh, mOpen);
mReturns(~lIsAvailObs) = NaN;

% Exclude all columns without data
lExclude                = all(isnan(mReturns),1) | all(isnan(mME),1); 
mReturns(:,lExclude)    = [];
mME(:,lExclude)         = [];
mClose(:,lExclude)      = [];
mCloseEconomicRaw(:,lExclude) = [];
mMEEconomicRaw(:,lExclude) = [];
mLow(:,lExclude)        = [];
mOpen(:,lExclude)       = [];
mHigh(:,lExclude)       = [];
mVolume(:,lExclude)     = [];
rMetaData               = structfun(@(x)x(~lExclude),rMetaData,'UniformOutput',false);

[tMechanicalExitCalendar,rMechanicalExitCalendarAudit] = ...
    fBuildAndFreezeMechanicalExitCalendar( ...
    mCloseEconomicRaw,yrmoda(:),rMetaData.vID(:), ...
    rMetaData.cSymbol(:), ...
    [sInDataPath,'mechanical_exit_calendar.csv']);

% Save data
save([sInDataPath, 'b0DataOLHC.mat'], 'mClose', 'mCloseEconomicRaw', ...
    'mMEEconomicRaw', 'mReturns', 'mME', 'mVolume','yrmoda', ...
    'rMetaData', 'vRiskFree', 'mLow', 'mOpen', 'mHigh', ...
    'rUnifiedMissingPreprocessing','tMechanicalExitCalendar', ...
    'rMechanicalExitCalendarAudit','-v7.3');

% Restore path
path(sOldPath);
