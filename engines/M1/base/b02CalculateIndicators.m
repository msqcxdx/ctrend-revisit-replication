% Script for calculating cryptocurrency characteristics and technical
% indicators and resampling them to the weekly frequency.  Corrected data
% construction keeps strict statistical returns untransformed: outlier
% rules are fitted strictly inside each later walk-forward training window.
% Economically realized portfolio P&L is stored separately and is computed
% from exact unsynchronized raw-positive-close endpoints.

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
    rInputProvenance = struct('lValidated', true, ...
        'sManifestSHA256', 'ARTIFICIAL_DATA', 'lArtificial', true);
    sInputCodeFingerprint = fPipelineCodeFingerprint(pwd);
else
    % Load empirical data
    fprintf(2,'Loading empirical data \n');
    load([sInDataPath,'b0DataOLHC.mat']);
    assert(exist('rInputProvenance', 'var') == 1 && ...
        isstruct(rInputProvenance) && ...
        isfield(rInputProvenance, 'lValidated') && ...
        isequal(rInputProvenance.lValidated, true) && ...
        isfield(rInputProvenance, 'sManifestSHA256'), ...
        ['b0DataOLHC.mat predates the corrected input-provenance gate. ' ...
         'Provide an unscreened input export and rerun b01ReadData.']);
    fAssertRawInputProvenance(sInDataPath,rInputProvenance);
    assert(exist('mClosePnlRaw','var') == 1 && ...
        exist('mMEEconomicRaw','var') == 1 && ...
        exist('tMechanicalExitCalendar','var') == 1 && ...
        exist('rMechanicalExitCalendarAudit','var') == 1 && ...
        exist('mVolumeRaw','var') == 1 && ...
        exist('lUnifiedAuxiliaryFilled','var') == 1, ...
        ['b0DataOLHC.mat predates the separated economic-P&L layer. ' ...
         'Rerun b01ReadData before weekly preprocessing.']);
end

% Artificial-data runs predate the empirical raw-panel contract. Preserve
% their existing behavior while giving them the same explicit field axes.
if ~exist('mClosePnlRaw','var')
    mClosePnlRaw = mClose;
    mClosePnlRaw(~isfinite(mClosePnlRaw) | mClosePnlRaw <= 0) = NaN;
end
if ~exist('mVolumeRaw','var')
    mVolumeRaw = mVolume;
    mVolumeRaw(~isfinite(mVolumeRaw)) = NaN;
end
if ~exist('mMEEconomicRaw','var')
    mMEEconomicRaw = mME;
end
if ~exist('tMechanicalExitCalendar','var')
    tMechanicalExitCalendar = table();
end
if ~exist('lUnifiedAuxiliaryFilled','var')
    lUnifiedAuxiliaryFilled = false(size(mClose));
end
assert(isequal(size(mClosePnlRaw),size(mClose)) && ...
    isequal(size(mMEEconomicRaw),size(mME)) && ...
    isequal(size(mVolumeRaw),size(mVolume)) && ...
    isequal(size(lUnifiedAuxiliaryFilled),size(mClose)), ...
    'Raw P&L panels and core panels must have identical date/asset axes');
assert(all(isnan(mClosePnlRaw) | ...
    (isfinite(mClosePnlRaw) & mClosePnlRaw > 0),'all'), ...
    'The economic-P&L close panel may contain only positive prices or NaN');

% A certified raw MAT file can still be stale relative to b01 cleaning code.
% Bind both raw and weekly intermediates to the exact corrected source tree.
sWeeklyCodeFingerprint = fPipelineCodeFingerprint(pwd);
assert(exist('sInputCodeFingerprint', 'var') == 1 && ...
    strcmp(char(sInputCodeFingerprint), sWeeklyCodeFingerprint), ...
    ['Corrected source changed after b01ReadData. Rerun b01 before weekly ' ...
     'preprocessing; do not re-certify a stale b0DataOLHC.mat.']);

% Determine dimensions
[iNumObs, iNumAssets] = size(mClose);

%% Set design choices
% Here we create datasets for various research design choices that affect
% the dataset construction
load('DesignChoices.mat','tDataCombos');
iNumDataCombos = size(tDataCombos,1);
sDataBuildID = char(java.util.UUID.randomUUID());

%% Get data
% Outlier method/threshold no longer changes upstream data. Build the raw
% weekly panel once, then save the identical provenance-bound input under
% every Table 6 data-setting key expected by downstream code.
for iIdxBuild = 1:1
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
    rData.vRiskFree = vRiskFree;

    % Determine dimensions
    [iNumObs, iNumAssets] = size(rData.mClose);

    % Construct the economic-return layer directly from unsynchronized raw
    % positive closing prices. Entry uses the scheduled formation endpoint.
    % An interior gap does not erase two observable endpoints; when only the
    % end of the holding week is missing, liquidation occurs at the frozen
    % last valid quote and proceeds are immediately reinvested within the
    % same portfolio leg. No quote is carried from a later weekly block.
    if ~lResampleLiuEtAl
        error(['The separated economic-P&L layer requires the Liu et al. ' ...
            'weekly schedule.']);
    end
    [mPnlReturnsWeek,mPnlRetLeadWeek,mClosePnlBoundaryWeek, ...
        mClosePnlFormationDayWeek,vDatesPnl,rEndpointPnlDiagnostics, ...
        mPnlRequiresReinvestmentWeek, ...
        mPnlRetLeadRequiresReinvestmentWeek, ...
        rEconomicReinvestmentLedger] = fBuildWeeklyEndpointPnl( ...
        mClosePnlRaw,yrmoda,mMEEconomicRaw,rMetaData.vID(:), ...
        tMechanicalExitCalendar);
    [mVolumeRawBoundaryWeek,vDatesVolumeRawBoundary] = ...
        fResampleLiuEtAl(mVolumeRaw,yrmoda, ...
        'sMethod','last','iMinNumObs',1);
    [mVolumeRawFormationDayWeek,vDatesVolumeRawFormationDay] = ...
        fResampleLiuEtAl(mVolumeRaw,yrmoda, ...
        'sMethod','first','iMinNumObs',1);
    assert(isequal(vDatesPnl,vDatesVolumeRawBoundary) && ...
        isequal(vDatesPnl,vDatesVolumeRawFormationDay), ...
        'Raw price and raw-volume weekly endpoint dates must agree');
    % The auditable daily raw panels remain in b0DataOLHC.mat. Only their
    % much smaller weekly endpoint snapshots are needed below.
    clear mClosePnlRaw mMEEconomicRaw mVolumeRaw
    
    % Print progress
    fprintf(2, 'Raw weekly data build 1 of 1 (serves %i outlier settings) \n', ...
        iNumDataCombos);

    % Missing vendor volume was already frozen as zero by b01. Retain zero
    % through feature construction; only a positive sub-cent vendor value
    % remains subject to the confirmed small-positive-data screen.
    rData.mVolume(rData.mVolume > 0 & rData.mVolume <= 1e-6) = NaN;

    % The paper defines a valid core observation by market capitalization,
    % volume, and closing price. Synchronize only those three fields after
    % the volume validity checks above. Do not remove an otherwise valid core
    % observation because open/high/low is missing; indicators that require
    % those fields remain missing naturally.
    [lCoreAvailable, rData.mME, rData.mVolume, rData.mClose] = ...
        fEnsureAllObs(rData.mME, rData.mVolume, rData.mClose);
    [rData.mOpen,rData.mHigh,rData.mLow] = fMaskAuxiliaryOHLC( ...
        lCoreAvailable,rData.mClose,rData.mOpen,rData.mHigh,rData.mLow, ...
        lUnifiedAuxiliaryFilled);
    % Recompute returns from the synchronized closing-price panel. Merely
    % blanking return_t would leave the previously calculated return_{t+1}
    % spanning across a newly introduced gap. The adjacent-price definition
    % makes both the gap date and the first resumed date missing.
    rData.mReturns = [NaN(1, iNumAssets); ...
        rData.mClose(2:end,:) ./ rData.mClose(1:end-1,:) - 1];
    rData.mReturns(~isfinite(rData.mReturns)) = NaN;

    % Do not truncate/winsorize here. The paper/old implementation uses the
    % realized date-t return cross-section to clean date-t returns before any
    % sample split, which is the look-ahead bias corrected by this pipeline.

    % Construct the paper's baseline market dynamically, without an
    % ever-eligible/full-sample asset screen. At each formation date an
    % asset needs valid core data, market cap of at least USD 1 million, and
    % non-stablecoin status. The Bitcoin upper bound is already enforced
    % observation by observation in b01. For return_t, the helper shifts
    % this formation mask and its market cap from t-1, so neither membership
    % nor the value weight uses end-of-return-period information.
    dBaselineMinME = 1e6;
    vIsStable = logical(rMetaData.lIsStable(:)');
    assert(numel(vIsStable) == iNumAssets, ...
        'Stablecoin metadata must provide one flag per asset');
    lMarketFormation = isfinite(rData.mME) & ...
        rData.mME >= dBaselineMinME & isfinite(rData.mClose) & ...
        isfinite(rData.mVolume) & ~vIsStable;
    mMEForMarket = rData.mME;
    mMEForMarket(~lMarketFormation) = NaN;
    [rData.vMktRet, mME_L1, rData.rMarketDiagnostics] = ...
        fValueWeightedMarketReturnStrict(rData.mReturns, mMEForMarket);
    lMarketReturnConstituent = isfinite(mME_L1) & mME_L1 > 0 & ...
        isfinite(rData.mReturns);
    mMarketReturns = rData.mReturns;
    mMarketReturns(~lMarketReturnConstituent) = NaN;
    rData.rMarketDiagnostics.dBaselineMinME = dBaselineMinME;
    rData.rMarketDiagnostics.iNumStableAssets = nnz(vIsStable);
    rData.rMarketDiagnostics.iNumFormationEligibleAssetDays = ...
        nnz(lMarketFormation);
    fprintf(['baseline_market defined_days=%d/%d (%.2f%%) ' ...
        'days_with_missing_return_given_lagged_me=%d ' ...
        'missing_return_asset_days=%d\n'], ...
        rData.rMarketDiagnostics.iNumDefinedDays, ...
        rData.rMarketDiagnostics.iNumDays, ...
        100*rData.rMarketDiagnostics.dDefinedFraction, ...
        rData.rMarketDiagnostics.iNumDaysWithMissingReturnGivenLaggedME, ...
        rData.rMarketDiagnostics.iNumMissingReturnAssetDays);

    % Table 5 defines market volatility as the value-weighted average of
    % asset-level standard deviations of daily returns over the week. Save
    % the within-week asset volatilities now, before daily returns are
    % replaced by their weekly compounded values. Each asset-week requires
    % the complete set of daily returns, so an internal gap remains NaN.
    if lResampleLiuEtAl
        [mAssetVolWeek, vDatesVol] = fResampleLiuEtAl(mMarketReturns, yrmoda, ...
            'sMethod','std', 'iMinNumObs','all');
    else
        error('Correct market-volatility construction requires the Liu et al. weekly schedule.');
    end

    % Compute every asset's characteristics before any baseline investable-
    % universe filter. A short history may make a particular characteristic
    % NaN, but never removes the asset from other characteristics or from
    % market-wide inputs for which its observations are defined. Every
    % characteristic is asset-separable conditional on the shared market
    % return, so split columns across workers and restore original order.
    fprintf('Start calculation of characteristics in parallel asset chunks\n');
    pPool = gcp('nocreate');
    if isempty(pPool)
        iNumChunks = min(12, iNumAssets);
    else
        iNumChunks = min(pPool.NumWorkers, iNumAssets);
    end
    vChunk = ceil((1:iNumAssets) * iNumChunks / iNumAssets);
    cAssetIdx = arrayfun(@(i) find(vChunk == i), ...
        (1:iNumChunks)', 'UniformOutput', false);
    % Materialize sliced cells once so parfor transfers only the assigned
    % columns, rather than broadcasting the complete rData struct to every
    % worker. This changes communication only, never numeric operations.
    cReturns = cellfun(@(idx) rData.mReturns(:,idx), cAssetIdx, ...
        'UniformOutput', false);
    cME = cellfun(@(idx) rData.mME(:,idx), cAssetIdx, ...
        'UniformOutput', false);
    cVolume = cellfun(@(idx) rData.mVolume(:,idx), cAssetIdx, ...
        'UniformOutput', false);
    cClose = cellfun(@(idx) rData.mClose(:,idx), cAssetIdx, ...
        'UniformOutput', false);
    cOpen = cellfun(@(idx) rData.mOpen(:,idx), cAssetIdx, ...
        'UniformOutput', false);
    cHigh = cellfun(@(idx) rData.mHigh(:,idx), cAssetIdx, ...
        'UniformOutput', false);
    cLow = cellfun(@(idx) rData.mLow(:,idx), cAssetIdx, ...
        'UniformOutput', false);
    vMktRetDaily = rData.vMktRet;
    cCharacteristicChunks = cell(iNumChunks, 1);
    parfor iIdxChunk = 1:iNumChunks
        cCharacteristicChunks{iIdxChunk} = fComputeCharacteristicChunk( ...
            cReturns{iIdxChunk}, cME{iIdxChunk}, cVolume{iIdxChunk}, ...
            cClose{iIdxChunk}, vMktRetDaily, ...
            'lComputeMarketRegressions',false);
    end
    rChars = fMergeAssetChunkStructs(cCharacteristicChunks);
    % Preserve the original full-panel X\Y floating-point path for the five
    % regression-derived fields. Column-chunked solves differ by up to a few
    % machine eps even though their mathematics is identical.
    rMarketRegressionChars = fComputeMarketRegressionCharacteristics( ...
        rData.mReturns,rData.mME,rData.mVolume,rData.mClose,vMktRetDaily);
    cMarketRegressionFields = fieldnames(rMarketRegressionChars);
    for iIdxF = 1:numel(cMarketRegressionFields)
        sField = cMarketRegressionFields{iIdxF};
        rChars.(sField) = rMarketRegressionChars.(sField);
    end
    
    % Calculate market illiquidity with a denominator matched to the assets
    % for which illiquidity is observed. Missing values are not zero-return
    % or zero-illiquidity contributions.
    mMktIlliqME = mME_L1;
    lMktIlliqConstituent = lMarketReturnConstituent & ...
        isfinite(rChars.illiq);
    mMktIlliqME(~lMktIlliqConstituent) = NaN;
    vMktIlliqME = sum(mMktIlliqME, 2, 'omitmissing');
    mMktIlliqWts = mMktIlliqME ./ vMktIlliqME;
    rData.vMktIlliq = sum(rChars.illiq .* mMktIlliqWts, 2, 'omitmissing');
    rData.vMktIlliq(~isfinite(vMktIlliqME) | vMktIlliqME <= 0) = NaN;

    fprintf('Start calculation of technical indicators in parallel asset chunks\n');
    cIndicatorChunks = cell(iNumChunks, 1);
    parfor iIdxChunk = 1:iNumChunks
        cIndicatorChunks{iIdxChunk} = fComputeTechnicalIndicatorChunk( ...
            cClose{iIdxChunk}, cOpen{iIdxChunk}, cHigh{iIdxChunk}, ...
            cLow{iIdxChunk}, cVolume{iIdxChunk});
    end
    clear cReturns cME cVolume cClose cOpen cHigh cLow
    rIndicatorChars = fMergeAssetChunkStructs(cIndicatorChunks);
    cIndicatorFields = fieldnames(rIndicatorChars);
    for iIdxF = 1:numel(cIndicatorFields)
        sField = cIndicatorFields{iIdxF};
        assert(~isfield(rChars, sField), ...
            'Duplicate characteristic/indicator field: %s', sField);
        rChars.(sField) = rIndicatorChars.(sField);
    end

    % Return with one day lead: This is required for the implementation
    % lag, which we discuss as a research design choice
    rData.mRetLead = [rData.mReturns(2:end,:); ...
        NaN(1,size(rData.mReturns,2))];

    %% Resample data
    fprintf('Start resampling to weekly data \n');
    
    % Resample characteristics at the scheduled weekly boundary
    cFieldnames  = fieldnames(rChars);
    sMethodChars = 'last'; % Preserve NaN when the boundary cell is missing
    cDailyChars = cellfun(@(s) rChars.(s), cFieldnames, ...
        'UniformOutput', false);
    cWeeklyChars = cell(size(cDailyChars));
    cWeeklyDates = cell(size(cDailyChars));
    parfor iIdxF = 1:length(cFieldnames)
        % Get characteristic
        mCharTemp = cDailyChars{iIdxF};
        mCharTemp(~isfinite(mCharTemp)) = NaN;
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
    vDatesWeek = cWeeklyDates{1};
    for iIdxF = 1:length(cFieldnames)
        if lResampleLiuEtAl
            assert(isequal(cWeeklyDates{iIdxF}, vDatesWeek), ...
                'Characteristic weekly partitions must agree');
        end
        rChars.(cFieldnames{iIdxF}) = cWeeklyChars{iIdxF};
    end

    % Resample market return
    if lResampleLiuEtAl
        [rData.vMktRet, vDatesMktRet] = fResampleLiuEtAl( 1 + rData.vMktRet, yrmoda,...
            'sMethod','prod', 'iMinNumObs','all');
    else
        [rData.vMktRet, vDatesMktRet] = fResampleDay2Week( 1 + rData.vMktRet, yrmoda, ...
            'sMethod','prod', 'iMinNumObs',7);
    end
    rData.vMktRet = rData.vMktRet - 1;

    % Resample the daily risk-free rate over the identical weekly partition.
    % This field is used downstream to construct paper-defined excess returns.
    if lResampleLiuEtAl
        [rData.vRiskFree, vDatesRF] = fResampleLiuEtAl(1 + rData.vRiskFree, yrmoda, ...
            'sMethod','prod', 'iMinNumObs','all');
    else
        [rData.vRiskFree, vDatesRF] = fResampleDay2Week(1 + rData.vRiskFree, yrmoda, ...
            'sMethod','prod', 'iMinNumObs',7);
    end
    rData.vRiskFree = rData.vRiskFree - 1;

    % Resample market illiquidity
    if lResampleLiuEtAl
        [rData.vMktIlliq, vDatesIlliq] = fResampleLiuEtAl( rData.vMktIlliq, yrmoda,...
            'sMethod','last', 'iMinNumObs',1);
    else
        [rData.vMktIlliq, vDatesIlliq] = fResampleDay2Week( rData.vMktIlliq, yrmoda, ...
            'sMethod','last','iMinNumObs',1);
    end

    % Resample returns (use product - REQUIRE ALL OBSERVATIONS)
    if lResampleLiuEtAl
        [rData.mReturns,vDates,rData.vNumDaysWeek] = fResampleLiuEtAl( 1 + rData.mReturns, yrmoda,...
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

    % Publish the physically separate economic P&L matrices.  The legacy
    % mReturns/mRetLead fields above remain the strict statistical outcomes
    % (synchronized core data plus complete daily support) used to fit
    % historical-week cross-sectional transforms and prediction models.
    rData.mPnlReturns = mPnlReturnsWeek;
    rData.mPnlRetLead = mPnlRetLeadWeek;
    rData.mPnlRequiresReinvestment = mPnlRequiresReinvestmentWeek;
    rData.mPnlRetLeadRequiresReinvestment = ...
        mPnlRetLeadRequiresReinvestmentWeek;
    rData.mClosePnlBoundary = mClosePnlBoundaryWeek;
    rData.mClosePnlFormationDay = mClosePnlFormationDayWeek;
    rData.mVolumeRawBoundary = mVolumeRawBoundaryWeek;
    rData.mVolumeRawFormationDay = mVolumeRawFormationDayWeek;

    % Figure C needs an ex-post "subsequent outcome is observed" condition,
    % but the historical label transform must not determine that support.
    % Save the untransformed strict statistical-outcome masks explicitly.
    rData.mRawOutcomeObserved = isfinite(rData.mReturns);
    rData.mRawOutcomeObservedLead = isfinite(rData.mRetLead);

    % A strict statistical return must be a subset of the corresponding
    % raw-endpoint payoff, and the two definitions must telescope to the
    % same value whenever strict support is complete.
    iAssertReturnLayerConsistency(rData.mReturns,rData.mPnlReturns, ...
        'ordinary');
    iAssertReturnLayerConsistency(rData.mRetLead,rData.mPnlRetLead, ...
        'one-day implementation-lag');
    % B02_ENDPOINT_PNL_DIAGNOSTIC_CONTRACT_BEGIN
    rEndpointPnlDiagnostics.iNumStrictStatReturnCells = ...
        nnz(rData.mRawOutcomeObserved);
    rEndpointPnlDiagnostics.iNumStrictStatRetLeadCells = ...
        nnz(rData.mRawOutcomeObservedLead);
    rEndpointPnlDiagnostics.iNumPnlReturnCells = ...
        nnz(isfinite(rData.mPnlReturns));
    rEndpointPnlDiagnostics.iNumPnlRetLeadCells = ...
        nnz(isfinite(rData.mPnlRetLead));
    rEndpointPnlDiagnostics.iNumPnlOnlyReturnCells = ...
        nnz(isfinite(rData.mPnlReturns) & ...
        ~rData.mRawOutcomeObserved);
    rEndpointPnlDiagnostics.iNumPnlOnlyRetLeadCells = ...
        nnz(isfinite(rData.mPnlRetLead) & ...
        ~rData.mRawOutcomeObservedLead);
    rEndpointPnlDiagnostics.iNumStrictOnlyReturnCells = ...
        nnz(rData.mRawOutcomeObserved & ...
        ~isfinite(rData.mPnlReturns));
    rEndpointPnlDiagnostics.iNumStrictOnlyRetLeadCells = ...
        nnz(rData.mRawOutcomeObservedLead & ...
        ~isfinite(rData.mPnlRetLead));
    rEndpointPnlDiagnostics.iNumRawVolumeBoundaryCells = ...
        nnz(isfinite(rData.mVolumeRawBoundary));
    rEndpointPnlDiagnostics.iNumPositiveRawVolumeBoundaryCells = ...
        nnz(isfinite(rData.mVolumeRawBoundary) & ...
        rData.mVolumeRawBoundary > 0);
    rEndpointPnlDiagnostics.iNumRawVolumeFormationDayCells = ...
        nnz(isfinite(rData.mVolumeRawFormationDay));
    rEndpointPnlDiagnostics.iNumPositiveRawVolumeFormationDayCells = ...
        nnz(isfinite(rData.mVolumeRawFormationDay) & ...
        rData.mVolumeRawFormationDay > 0);
    rEndpointPnlDiagnostics.sStatisticalLayer = ...
        'core synchronized; complete daily support; untransformed';
    rEndpointPnlDiagnostics.sEconomicLayer = ...
        ['raw positive close; scheduled entry; frozen terminal exit; ' ...
         'immediate same-leg reinvestment; untransformed'];
    rData.rEndpointPnlDiagnostics = rEndpointPnlDiagnostics;
    fprintf(['return_layers stat=%d pnl=%d pnl_only=%d ' ...
        'stat_lead=%d pnl_lead=%d pnl_only_lead=%d\n'], ...
        rData.rEndpointPnlDiagnostics.iNumStrictStatReturnCells, ...
        rData.rEndpointPnlDiagnostics.iNumPnlReturnCells, ...
        rData.rEndpointPnlDiagnostics.iNumPnlOnlyReturnCells, ...
        rData.rEndpointPnlDiagnostics.iNumStrictStatRetLeadCells, ...
        rData.rEndpointPnlDiagnostics.iNumPnlRetLeadCells, ...
        rData.rEndpointPnlDiagnostics.iNumPnlOnlyRetLeadCells);
    % B02_ENDPOINT_PNL_DIAGNOSTIC_CONTRACT_END

    % For the one-day implementation-lag design, signals are observed at the
    % preceding weekly boundary, the portfolio is constructed on the first
    % day of this block, and returns start on the following day. Preserve the
    % construction-day cap and price before overwriting daily fields below.
    if lResampleLiuEtAl
        [rData.mMEFormationDay,vDatesMEFormationDay] = ...
            fResampleLiuEtAl(rData.mME,rData.yrmoda, ...
            'sMethod','first','iMinNumObs',1);
        [rData.mCloseFormationDay,vDatesCloseFormationDay] = ...
            fResampleLiuEtAl(rData.mClose,rData.yrmoda, ...
            'sMethod','first','iMinNumObs',1);
    else
        error(['The corrected implementation-lag snapshots require the ' ...
            'Liu et al. weekly schedule.']);
    end

    % Resample closing prices at the scheduled weekly boundary. The
    % resampler deliberately leaves a missing boundary observation as NaN.
    if lResampleLiuEtAl
        [rData.mClose, vDatesClose] = fResampleLiuEtAl(rData.mClose, rData.yrmoda,...
            'sMethod','last', 'iMinNumObs',1);
    else
        [rData.mClose, vDatesClose] = fResampleDay2Week(rData.mClose, rData.yrmoda, ...
            'sMethod','last','iMinNumObs',1);
    end

    % Resample volume (sum over the past week). A partial-week sum would
    % silently interpret missing volume as zero, so require all daily cells.
    if lResampleLiuEtAl
        [rData.mVolume, vDatesVolume] = fResampleLiuEtAl(rData.mVolume, rData.yrmoda, ...
            'sMethod','sum', 'iMinNumObs','all');
    else
        [rData.mVolume, vDatesVolume] = fResampleDay2Week(rData.mVolume, rData.yrmoda, ...
            'sMethod','sum','iMinNumObs',7);
    end

    % Resample market capitalization at the scheduled weekly boundary
    if lResampleLiuEtAl
        [rData.mME,vDatesME] = fResampleLiuEtAl(rData.mME, rData.yrmoda, ...
            'sMethod','last', 'iMinNumObs',1);
    else
        [rData.mME,vDatesME] = fResampleDay2Week(rData.mME, rData.yrmoda, ...
            'sMethod','last','iMinNumObs',1);
    end

    % A separately named investable market payoff is formed from the same
    % baseline universe but uses the daily-event economic ledger.  Frozen
    % exits are sold at the last tradable quote and their proceeds are
    % immediately redistributed by event-day market cap among the surviving
    % market-leg constituents.  The market portfolio therefore remains fully
    % invested and uses exactly the same accounting rule as factor legs.
    mMarketPnlME = [NaN(1,iNumAssets);rData.mME(1:end-1,:)];
    mMarketPnlClose = [NaN(1,iNumAssets);rData.mClose(1:end-1,:)];
    lMarketPnlFormation = isfinite(mMarketPnlME) & ...
        mMarketPnlME >= dBaselineMinME & ...
        isfinite(mMarketPnlClose) & ~vIsStable;
    mMarketPnlME(~lMarketPnlFormation) = NaN;
    mMarketPnlWeightNumerator = mMarketPnlME;
    mMarketPnlWeightNumerator(~isfinite(mMarketPnlWeightNumerator) | ...
        mMarketPnlWeightNumerator <= 0 | ~isfinite(rData.mPnlReturns)) = 0;
    vMarketPnlWeightTotal = sum(mMarketPnlWeightNumerator,2);
    mMarketPnlWeights = mMarketPnlWeightNumerator ./ ...
        vMarketPnlWeightTotal;
    mMarketPnlWeights(~isfinite(mMarketPnlWeights)) = 0;
    [vMktPnlRow,mMarketPnlEndWeights,vMarketPnlWithinWeekFullL1, ...
        rMarketPnlReinvestmentAudit] = fApplySameLegReinvestment( ...
        mMarketPnlWeights',rEconomicReinvestmentLedger, ...
        (1:size(mMarketPnlWeights,1))','ordinary','VW');
    rData.vMktPnl = vMktPnlRow';
    rData.rMarketPnlDiagnostics = struct( ...
        'sRule',['value-weighted market leg with frozen exits and ' ...
        'immediate same-leg event-day-market-cap reinvestment'], ...
        'lFormationValid',vMarketPnlWeightTotal > 0, ...
        'lPayoffComplete',isfinite(rData.vMktPnl), ...
        'vFormationHoldings',sum(mMarketPnlWeightNumerator > 0,2), ...
        'mEndRiskyWeights',mMarketPnlEndWeights', ...
        'vWithinWeekFullL1',vMarketPnlWithinWeekFullL1', ...
        'rReinvestmentAudit',rMarketPnlReinvestmentAudit, ...
        'lEndCashAlwaysZero',true, ...
        'lCrossLegTransfer',false);

    % Market volatility observed in week w is the value-weighted average
    % of complete asset-level daily-return standard deviations in week w,
    % using market capitalization at the start of week w (the prior weekly
    % boundary). b08 lags this weekly series once when classifying return
    % week w+1, so no current-week return enters its own state assignment.
    assert(isequal(vDatesVol, vDatesME), ...
        'Market-volatility and market-capitalization weeks must align');
    mMEVol_L1 = [NaN(1, iNumAssets); rData.mME(1:end-1,:)];
    mMktVolME = mMEVol_L1;
    lMktVolConstituent = isfinite(mMEVol_L1) & ...
        mMEVol_L1 >= dBaselineMinME & ~vIsStable & ...
        isfinite(mAssetVolWeek);
    mMktVolME(~lMktVolConstituent) = NaN;
    vMktVolME = sum(mMktVolME, 2, 'omitmissing');
    mMktVolWts = mMktVolME ./ vMktVolME;
    rData.vMktVol = sum(mAssetVolWeek .* mMktVolWts, 2, 'omitmissing');
    rData.vMktVol(~isfinite(vMktVolME) | vMktVolME <= 0) = NaN;

    % Every weekly series must refer to the exact same weekly partition.
    assert(isequal(vDates, vDatesME) && isequal(vDates, vDatesRF) && ...
        isequal(vDates, vDatesLead) && isequal(vDates, vDatesClose) && ...
        isequal(vDates, vDatesVolume) && isequal(vDates, vDatesMktRet) && ...
        isequal(vDates, vDatesIlliq) && isequal(vDates, vDatesWeek) && ...
        isequal(vDates,vDatesMEFormationDay) && ...
        isequal(vDates,vDatesCloseFormationDay) && ...
        isequal(vDates,vDatesPnl) && ...
        isequal(vDates,vDatesVolumeRawBoundary) && ...
        isequal(vDates,vDatesVolumeRawFormationDay), ...
        'All weekly data fields must use the identical weekly partition');

    % Change date
    rData.yrmoda = vDates;
        
    % Publish the daily-event ledger once.  Keeping it outside each of the
    % four otherwise-identical weekly characteristic files avoids four
    % large duplicate event-price matrices.  Every consumer verifies the
    % exact ledger hash and data-build ID before portfolio accounting.
    sEconomicLedgerFile = [sOutDataPath,'b2EconomicReinvestmentLedger.mat'];
    sEconomicLedgerTemporary = [tempname(sOutDataPath),'.mat'];
    rEconomicLedgerCleanup = onCleanup( ...
        @() iDeleteIfExists(sEconomicLedgerTemporary));
    save(sEconomicLedgerTemporary,'rEconomicReinvestmentLedger', ...
        'rEndpointPnlDiagnostics','sDataBuildID', ...
        'rInputProvenance','sWeeklyCodeFingerprint','-v7.3');
    [lLedgerMoved,sLedgerMoveMessage] = movefile( ...
        sEconomicLedgerTemporary,sEconomicLedgerFile,'f');
    assert(lLedgerMoved,'Could not atomically publish %s: %s', ...
        sEconomicLedgerFile,sLedgerMoveMessage);
    clear rEconomicLedgerCleanup
    rData.rEconomicReinvestmentLedgerReference = struct( ...
        'sFormat',rEconomicReinvestmentLedger.sFormat, ...
        'sFilename','b2EconomicReinvestmentLedger.mat', ...
        'sSHA256',fFileSHA256(sEconomicLedgerFile), ...
        'sDataBuildID',sDataBuildID, ...
        'lUsesExternalSource',false, ...
        'lAllowsCashAfterExit',false);

    % Save the same raw weekly panel for every outlier-design key. The keys
    % select train-fit transforms in b05/b09; they do not select pre-cleaned
    % input matrices.
    rData = rmfield(rData, {'mLow', 'mOpen', 'mHigh'});
    fprintf('Start saving data \n');
    for iIdxC = 1:iNumDataCombos
        sFilename = sprintf('%sbCharacteristicsOLHC_Combo%i.mat', ...
            sOutDataPath, tDataCombos.data_setting(iIdxC));
        fSaveData(sFilename, rChars, rData, rMetaData, sDataBuildID, ...
            rInputProvenance, sWeeklyCodeFingerprint);
        fprintf(2, 'Raw weekly data saved for setting %i of %i \n', ...
            iIdxC, iNumDataCombos);
    end
    fPublishWeeklyDataBuildManifest(sOutDataPath, ...
        tDataCombos.data_setting, sDataBuildID, ...
        sWeeklyCodeFingerprint, rInputProvenance, ...
        size(rData.mReturns,1), size(rData.mReturns,2));
end

% Restore path
path(sOldPath);
function fSaveData(sFilename, rChars, rData, rMetaData, sDataBuildID, ...
        rInputProvenance, sWeeklyCodeFingerprint)
    sTemporary = [tempname(fileparts(sFilename)),'.mat'];
    rCleanup = onCleanup(@() iDeleteIfExists(sTemporary));
    save(sTemporary, 'rChars', 'rData', 'rMetaData', 'sDataBuildID', ...
        'rInputProvenance', 'sWeeklyCodeFingerprint', '-v7.3');
    [lMoved,sMoveMessage] = movefile(sTemporary,sFilename,'f');
    assert(lMoved,'Could not atomically publish %s: %s', ...
        sFilename,sMoveMessage);
    clear rCleanup
end

function iDeleteIfExists(sFilename)
    if exist(sFilename,'file') == 2
        delete(sFilename);
    end
end

function iAssertReturnLayerConsistency(mStat,mPnl,sLayer)
    assert(isequal(size(mStat),size(mPnl)), ...
        '%s statistical and P&L return matrices must have equal size', ...
        sLayer);
    lStat = isfinite(mStat);
    lPnl = isfinite(mPnl);
    assert(~any(lStat & ~lPnl,'all'), ...
        ['A strict %s statistical return cannot exist without its raw ' ...
         'endpoint payoff'],sLayer);
    lBoth = lStat & lPnl;
    vTolerance = 1e-10 .* max(1,abs(mPnl(lBoth)));
    assert(all(abs(mStat(lBoth)-mPnl(lBoth)) <= vTolerance), ...
        ['Strict %s returns must telescope to the raw-endpoint payoff ' ...
         'on common support'],sLayer);
end

