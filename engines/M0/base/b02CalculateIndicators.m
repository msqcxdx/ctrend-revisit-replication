% Script for doing the data preprocessing. We control for outliers here,
% calculate cryptocurrency characteristics and technical indicators. The
% data is resampled to the weekly frequency

% Clear console
clear; clc; close all;

% Set paths
sOldPath        = path;
sInDataPath     = './DATA/';
sOutDataPath    = './DATA/';
addpath('./Utils/');

% Resampling to weekly data as in Liu et al. If set to false, data is
% resampled from sunday to sunday
lResampleLiuEtAl    = true;

% Use artificial data
lUseArtData         = false;

% Load data
if lUseArtData
    % Load artificial data
    fprintf(2,'Loading artificial data \n');
    load([sInDataPath,'b0ArtDataOLHC.mat'])
else
    % Load empirical data
    fprintf(2,'Loading empirical data \n');
    load([sInDataPath,'b0DataOLHC.mat']);
end

% Determine dimensions
[iNumObs, iNumAssets] = size(mClose);

%% Set design choices
% Here we create datasets for various research design choices that affect
% the dataset construction
load('DesignChoices.mat','tDataCombos');
iNumDataCombos = size(tDataCombos,1);

%% Get data
% Loop over combinations
for iIdxC = 1:iNumDataCombos
    % Copy data (allows running the loop in parallel)
    rData           = struct();
    rChars          = struct();
    rData.mReturns  = mReturns;
    rData.mClose    = mClose;
    rData.mVolume   = mVolume;
    rData.mME       = mME;
    rData.yrmoda    = yrmoda;
    rData.mLow      = mLow;
    rData.mHigh     = mHigh;
    rData.mOpen     = mOpen;

    % Determine dimensions
    [iNumObs, iNumAssets] = size(rData.mClose);
    
    % Print progress
    fprintf(2, 'Combo %i of %i \n', iIdxC, iNumDataCombos);

    % Extract setting
    sOutlierTreatment   = tDataCombos.cOutlierTreatment{iIdxC};
    dThreshold          = tDataCombos.vThreshold(iIdxC);

    % Winsorize/truncate returns
    switch upper(sOutlierTreatment)
        case 'WIN'
            % Winsorize returns
            rData.mReturns = fWinsorize(rData.mReturns, dThreshold, 1, 2);
        case 'TRUNC'
            % Trunctate returns
            rData.mReturns = fTruncate(rData.mReturns, dThreshold, 1, 2);
    end
    % Find changed data
    lChanged                = rData.mReturns ~= mReturns;
    rData.mClose(lChanged)  = NaN;

    % Ensure that every observation has price, volume, and market value
    [lIsAvailObs, rData.mME, rData.mVolume, rData.mClose, rData.mLow, rData.mHigh, rData.mOpen] = ...
        fEnsureAllObs(rData.mME, rData.mVolume, rData.mClose, rData.mLow, rData.mHigh, rData.mOpen);

    % A raw missing volume is explicitly zero under the shared preprocessing
    % contract. Preserve that zero; only a positive but sub-cent vendor
    % value retains the published small-positive-data screen.
    rData.mVolume(rData.mVolume > 0 & rData.mVolume <= 1e-6) = NaN;

    % Calculate value-weighted market return
    mME_L1          = [NaN(1, iNumAssets); rData.mME(1:end-1,:)];
    mWts            = mME_L1 ./ sum(mME_L1,2,'omitmissing');
    rData.vMktRet   = sum(rData.mReturns .* mWts, 2, 'omitnan');
    rData.vMktRet(all(isnan(mWts), 2)) = NaN;

    % Calculate the rolling market volatility
    vMktVol         = NaN(iNumObs, 1);
    iNumInMktVol    = 28;
    for iIdxT = iNumInMktVol:iNumObs
        % Get data
        vIdxInSample    = (iIdxT-iNumInMktVol+1):iIdxT;
        vMktRetTemp     = rData.vMktRet(vIdxInSample);

        % Calculate volatility
        vMktVol(iIdxT)  = std(vMktRetTemp);
    end
    rData.vMktVol       = vMktVol;

    % Compute asset-separable characteristics and technical indicators in
    % column chunks, following the corrected pipeline's execution topology.
    % The helper deliberately preserves every published old formula and
    % parameter; only independent asset columns are scheduled in parallel.
    fprintf('Start calculation of characteristics and technical indicators in parallel asset chunks \n');
    rChars = fComputeOldFeaturesParallel(rData.mReturns, rData.mME, ...
        rData.mVolume, rData.mClose, rData.vMktRet, rData.mOpen, ...
        rData.mHigh, rData.mLow);
    
    % Calculate the market illiquidity
    rData.vMktIlliq     = sum(rChars.illiq .* mWts, 2, 'omitnan');
    rData.vMktIlliq(all(isnan(mWts), 2)) = 0;
    rData.vMktIlliq(all(isnan(rChars.illiq) | rChars.illiq == 0,2)) = NaN;

    % Return with one day lead: This is required for the implementation
    % lag, which we discuss as a research design choice
    rData.mRetLead = lagmatrix(rData.mReturns, -1);

    %% Resample data
    fprintf('Start resampling to weekly data \n');
    
    % Resample characteristics (use last valid observation)
    cFieldnames  = fieldnames(rChars);
    sMethodChars = 'last'; % Use last nonmissing observation
    cDailyChars = cellfun(@(s) rChars.(s), cFieldnames, ...
        'UniformOutput', false);
    cWeeklyChars = cell(size(cDailyChars));
    cWeeklyDates = cell(size(cDailyChars));
    parfor iIdxF = 1:length(cFieldnames)
        % Get characteristic
        mCharTemp = cDailyChars{iIdxF};
        if lResampleLiuEtAl
            % This resamples the data as in Liu et al.
            [cWeeklyChars{iIdxF}, cWeeklyDates{iIdxF}] = ...
                fResampleLiuEtAl(mCharTemp, yrmoda, ...
                'sMethod', sMethodChars, 'iMinNumObs', 1);
        else
            % This resamples the data from sunday to sunday
            cWeeklyChars{iIdxF} = fResampleDay2Week(mCharTemp, yrmoda, ...
                'sMethod', sMethodChars, 'iMinNumObs',1);
        end
    end
    for iIdxF = 1:length(cFieldnames)
        rChars.(cFieldnames{iIdxF}) = cWeeklyChars{iIdxF};
    end

    % Resample market return
    if lResampleLiuEtAl
        rData.vMktRet = fResampleLiuEtAl( 1 + rData.vMktRet, yrmoda,...
            'sMethod','prod', 'iMinNumObs','all');
    else
        rData.vMktRet = fResampleDay2Week( 1 + rData.vMktRet, yrmoda, ...
            'sMethod','prod', 'iMinNumObs',7);
    end
    rData.vMktRet = rData.vMktRet - 1;

    % Resample market illiquidity
    if lResampleLiuEtAl
        rData.vMktIlliq = fResampleLiuEtAl( rData.vMktIlliq, yrmoda,...
            'sMethod','last', 'iMinNumObs',1);
    else
        rData.vMktIlliq = fResampleDay2Week( rData.vMktIlliq, yrmoda, ...
            'sMethod','last','iMinNumObs',1);
    end

    % Resample market volatiliy
    if lResampleLiuEtAl
        rData.vMktVol = fResampleLiuEtAl( rData.vMktVol, yrmoda, ...
            'sMethod', 'last', 'iMinNumObs',1);
    else
        rData.vMktVol = fResampleDay2Week( rData.vMktVol, yrmoda, ...
            'sMethod','last','iMinNumObs',1);
    end

    % Resample returns (use product - REQUIRE ALL OBSERVATIONS)
    if lResampleLiuEtAl
        [rData.mReturns,vDates] = fResampleLiuEtAl( 1 + rData.mReturns, yrmoda,...
            'sMethod','prod', 'iMinNumObs','all');
    else
        [rData.mReturns,vDates] = fResampleDay2Week( 1 + rData.mReturns, yrmoda, ...
            'sMethod','prod', 'iMinNumObs',7);
    end
    rData.mReturns = rData.mReturns-1;

    % Resample leaded return
    if lResampleLiuEtAl
        [rData.mRetLead,vDatesLead] = fResampleLiuEtAl( 1 + rData.mRetLead, yrmoda, ...
            'sMethod','prod', 'iMinNumObs','all');
    else
        [rData.mRetLead,vDatesLead] = fResampleDay2Week( 1 + rData.mRetLead, yrmoda, ...
            'sMethod','prod', 'iMinNumObs',7);
    end
    rData.mRetLead = rData.mRetLead - 1;

    % Resample closing prices (last valid observation)
    if lResampleLiuEtAl
        [rData.mClose, dates] = fResampleLiuEtAl(rData.mClose, rData.yrmoda,...
            'sMethod','last', 'iMinNumObs',1);
    else
        [rData.mClose, dates] = fResampleDay2Week(rData.mClose, rData.yrmoda, ...
            'sMethod','last','iMinNumObs',1);
    end

    % Resample volume (sum over the past week)
    if lResampleLiuEtAl
        rData.mVolume = fResampleLiuEtAl(rData.mVolume, rData.yrmoda, ...
            'sMethod','sum', 'iMinNumObs',1);
    else
        rData.mVolume = fResampleDay2Week(rData.mVolume, rData.yrmoda, ...
            'sMethod','sum','iMinNumObs',1);
    end

    % Resample market capitalization (last valid observation)
    if lResampleLiuEtAl
        [rData.mME,vDatesME] = fResampleLiuEtAl(rData.mME, rData.yrmoda, ...
            'sMethod','last', 'iMinNumObs',1);
    else
        [rData.mME,vDatesME] = fResampleDay2Week(rData.mME, rData.yrmoda, ...
            'sMethod','last','iMinNumObs',1);
    end

    % Change date
    rData.yrmoda = vDates;
        
    % Create filename
    sFilename = sprintf('%sbCharacteristicsOLHC_Combo%i.mat', sOutDataPath, tDataCombos.data_setting(iIdxC));

    % Save 
    rData = rmfield(rData, {'mLow', 'mOpen', 'mHigh'});
    fprintf('Start saving data \n');
    fSaveData(sFilename, rChars, rData, rMetaData);
    fprintf(2, 'Combo %i of %i saved \n', iIdxC, iNumDataCombos);
end

% Restore path
path(sOldPath);
function fSaveData(sFilename, rChars, rData, rMetaData)
    save(sFilename, 'rChars', 'rData', 'rMetaData', '-v7.3');
end

