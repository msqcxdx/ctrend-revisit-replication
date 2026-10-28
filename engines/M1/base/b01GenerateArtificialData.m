% Script for generating pseudo data

% Clear console
clear; clc; close all;

% Set paths
sOldPath    = path;
addpath('./Utils');
sInDataPath = './DATA/';

% Settings
iNumAssets = 500;                       % Number of assets
dtStart    = datetime('28-Apr-2013');   % Start date (based on actual data)
dtEnd      = datetime('11-Jun-2022');   % End date
dtDates    = (dtStart:dtEnd)';          % Daily dates
iNumObs    = length(dtDates);           % Number of daily observations

% Transform date to numeric
yrmoda = str2num(datestr(dtDates,'YYYYmmdd'));

% Generate returns all same standard deviation but different sign of mean
mReturns   = randn(iNumObs, iNumAssets) * 0.008 + 0.001 .* sign(randn(1,iNumAssets)); 

% Generate OHLC prices
mClose     = ret2price(mReturns,'StartPrices',100);
mOpen      = mClose(1:end-1,:); mClose(1,:) = [];  % Now open is the previous day's closing
mLow       = mClose .* (1 - max(0.01,abs(randn(1,iNumAssets)*0.05))); % Some difference from closing price
mHigh      = mClose .* (1 + max(0.01,abs(randn(1,iNumAssets)*0.05))); % Some difference from closing price

% Generate market equity
mME        = mClose .* randi(1e6,1, iNumAssets);

% Generate volume
mVolume    = abs(randn(iNumObs, iNumAssets)) * 1000;

% Let some assets start later
lIsAvail = randi(50, iNumObs, iNumAssets) == 50; % Probability is 1/50 that an asset starts
parfor iIdxA = 1:iNumAssets
    lAvailTemp = lIsAvail(:,iIdxA);
    iIdxFirst = find(lAvailTemp,1,'first');
    if ~isempty(iIdxFirst)
        lAvailTemp(iIdxFirst:end) = true;
    end
    lIsAvail(:,iIdxA) = lAvailTemp;
end
mReturns(~lIsAvail) = NaN;
mClose(~lIsAvail)   = NaN;
mLow(~lIsAvail)     = NaN;
mHigh(~lIsAvail)    = NaN;
mME(~lIsAvail)      = NaN;
mVolume(~lIsAvail)  = NaN;

% Simulate risk free rate
vRiskFree  = zeros(iNumObs, 1);

% Simulate meta data
    % Names
rMetaData.cName = cellfun(@(x)['X',x], sprintfc('%i',1:iNumAssets),'un',false);
    % Symbols
rMetaData.cSymbol = cellfun(@(x)['S',x], sprintfc('%i',1:iNumAssets),'un',false);
    % Coin type
cCoinType = {'coin','token'};
iCoinType = randi(2,1,iNumAssets);
rMetaData.lIsCoin = strcmpi(cCoinType(iCoinType),'coin');
rMetaData.lIsToken = strcmpi(cCoinType(iCoinType),'token');
    % Stable coin
rMetaData.lIsStable = false(1,iNumAssets);
    % ID
rMetaData.vID       = 1:iNumAssets;

% Save data
save([sInDataPath, 'b0ArtDataOLHC.mat'], 'mClose', 'mReturns', 'mME', ...
    'mVolume','yrmoda', 'rMetaData', 'vRiskFree', 'mLow', 'mOpen', 'mHigh');

% Restore path
path(sOldPath);
