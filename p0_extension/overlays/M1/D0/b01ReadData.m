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

% Dates are an explicit matrix key, not an assumed row order.  Verify all
% six raw panels before discarding their first columns.
dtDate = fReadDateColumn([sInDataPath,'close_cmc.csv']);
assert(isequal(dtDate, fReadDateColumn([sInDataPath,'low_cmc.csv'])), ...
    'Dates in close and low price files do not agree');
assert(isequal(dtDate, fReadDateColumn([sInDataPath,'high_cmc.csv'])), ...
    'Dates in close and high price files do not agree');
assert(isequal(dtDate, fReadDateColumn([sInDataPath,'open_cmc.csv'])), ...
    'Dates in close and open price files do not agree');

% Get asset IDs
vAssetID_Close          = mClose(1,2:end); 
vAssetID_Low            = mLow(1,2:end);
vAssetID_High           = mHigh(1,2:end);
vAssetID_Open           = mOpen(1,2:end);

assert(all(isfinite(vAssetID_Close)) && ...
    numel(unique(vAssetID_Close)) == numel(vAssetID_Close), ...
    'Price asset IDs must be finite and unique');

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
mClose(~isfinite(mClose) | mClose <= 0) = NaN;
mLow(~isfinite(mLow) | mLow <= 0)       = NaN;
mHigh(~isfinite(mHigh) | mHigh <= 0)    = NaN;
mOpen(~isfinite(mOpen) | mOpen <= 0)    = NaN;

% Read market capitalization
mME             = readmatrix([sInDataPath,'market_cap_cmc.csv']);
assert(isequal(dtDate, fReadDateColumn([sInDataPath,'market_cap_cmc.csv'])), ...
    'Dates in close and market-cap files do not agree');
vAssetID_ME     = mME(1,2:end);
assert(all(isfinite(vAssetID_ME)) && ...
    numel(unique(vAssetID_ME)) == numel(vAssetID_ME), ...
    'Market-cap asset IDs must be finite and unique');
mME             = mME(2:end,2:end);

% Read volume
mVolume         = readmatrix([sInDataPath,'volume_cmc.csv']);
assert(isequal(dtDate, fReadDateColumn([sInDataPath,'volume_cmc.csv'])), ...
    'Dates in close and volume files do not agree');
vAssetID_Vol    = mVolume(1,2:end);
assert(all(isfinite(vAssetID_Vol)) && ...
    numel(unique(vAssetID_Vol)) == numel(vAssetID_Vol), ...
    'Volume asset IDs must be finite and unique');
mVolume         = mVolume(2:end,2:end);
mVolume(~isfinite(mVolume)) = NaN;

% Load meta data (this is a struct with fields)
%   .vID:           Asset ID
%   .cCoinType:     'coin' or 'token'
%   .vStableCoin:   Logical that indicates whether asset is a stable coin
%   .cName:         Name
%   .cSymbol:       Symbol
load([sInDataPath, 'MetaData.mat']);

% Validate the unscreened source universe. b02 constructs market-wide series
% before baseline formation-time filters, so stablecoins and low-cap assets
% must remain; histories with internal gaps also remain in the panels.
rInputProvenance = fValidateInputProvenance(sInDataPath, rMetaData, mME);

% Asset ID is a matrix key, not a best-effort intersection. Silently taking
% the common subset would delete columns whenever one raw export were
% incomplete and would violate the certified unscreened universe.
assert(isfield(rMetaData, 'vID') && all(isfinite(rMetaData.vID(:))) && ...
    numel(unique(rMetaData.vID(:))) == numel(rMetaData.vID), ...
    'Metadata asset IDs must be finite and unique');
assert(isequal(vAssetID_Close(:), vAssetID_ME(:)) && ...
       isequal(vAssetID_Close(:), vAssetID_Vol(:)) && ...
       isequal(vAssetID_Close(:), rMetaData.vID(:)), ...
    ['All raw panels and metadata must contain exactly the same asset IDs ' ...
     'in the same order; do not silently intersect different exports.']);
cRequiredMetadata = {'vID','cCoinType','vStableCoin','cName','cSymbol'};
assert(all(isfield(rMetaData,cRequiredMetadata)), ...
    'Metadata is missing a required asset field');
assert(all(cellfun(@(s)numel(rMetaData.(s)) == numel(rMetaData.vID), ...
    cRequiredMetadata)), ...
    'Every required metadata field must contain one value per asset ID');

% Apply same-CMCID integer unit-continuity cleaning only after the immutable
% vendor bytes have been validated and hashed, but before constructing any
% return, weekly endpoint, characteristic or technical indicator.  Older
% OHLC is expressed in the newer unit.  Different CMCIDs remain different
% assets, and neither return magnitude nor cross-source disagreement creates
% a missing price.  Every applied UCID/date/factor is persisted below.
[mOpen,mHigh,mLow,mClose,mME,mVolume,rV2RawCorrectionAudit] = ...
    fApplyV2RawDataCorrections( ...
    mOpen,mHigh,mLow,mClose,mME,mVolume,dtDate, ...
    vAssetID_Close,rMetaData);

% Bind the experiment treatment and its external registry to every derived
% DATA checkpoint.  fPipelineCodeFingerprint covers executable source but
% deliberately does not hash CSV registries.
rInputProvenance.sCoreExperimentID = ...
    rV2RawCorrectionAudit.sExperimentID;
rInputProvenance.sRawAdjustmentMode = rV2RawCorrectionAudit.sMode;
rInputProvenance.sRawAdjustmentRegistrySHA256 = ...
    rV2RawCorrectionAudit.sRegistrySHA256;
rInputProvenance.iRawAdjustmentRegistryRows = ...
    rV2RawCorrectionAudit.iRegistryRows;
rInputProvenance.sRawAdjustmentTransformerSHA256 = ...
    rV2RawCorrectionAudit.sTransformerSHA256;

% Preserve the unit-consistent, unsynchronized economic close before the
% close/volume/market-cap core mask.  A missing intermediate volume or
% market-cap observation must not erase a payoff whose two endpoint closes
% are observed. Extreme raw endpoints remain economic payoffs; missingness is
% never created merely because another source reports a different value.
mClosePnlRaw = mClose;

% Keep the unsynchronized vendor volume for explicit diagnostics.  The v2
% registry never edits volume, and volume does not alter economic P&L.
mVolumeRaw = mVolume;

% Calculate the initial adjacent-day statistical returns after raw-data
% corrections.  They are recomputed again after the core synchronization.
mReturns = [NaN(1, size(mClose,2)); ...
    (mClose(2:end,:)./mClose(1:end-1,:)) - 1];

% Remove invalid market caps and values above an observed Bitcoin market
% cap. Verify both CMC ID and symbol before using that column as the market
% upper-bound reference. A missing BTC quote does not erase other assets.
mME = fCleanMarketCapAgainstBitcoin(mME, vAssetID_ME, rMetaData.cSymbol);

% Preserve the cleaned but unsynchronized market-cap panel for event-day VW
% reinvestment.  A later missing core volume cell must not erase an observed
% event-day market capitalization.
mMEEconomicRaw = mME;

% Transform date to numeric yyyyMMdd without string/eval conversion.
yrmoda = year(dtDate)*10000 + month(dtDate)*100 + day(dtDate);

% Read the Fama-French risk-free rate without fixed row ranges. Header and
% footer rows become nonnumeric and are removed by the explicit date gate.
sFFFile = [sInDataPath, 'F-F_Research_Data_Factors_daily.CSV'];
mFFRaw = readmatrix(sFFFile, 'OutputType','double');
assert(size(mFFRaw,2) >= 5, ...
    'Fama-French daily file must contain Date and RF in columns 1 and 5');
vFFDate = mFFRaw(:,1);
vFFRF = mFFRaw(:,5);
lFFDaily = isfinite(vFFDate) & isfinite(vFFRF) & ...
    vFFDate == floor(vFFDate) & vFFDate >= 19000101 & vFFDate <= 21001231;
vFFDate = vFFDate(lFFDaily);
vFFRF = vFFRF(lFFDaily);
assert(~isempty(vFFDate) && all(diff(vFFDate) > 0) && ...
    numel(unique(vFFDate)) == numel(vFFDate), ...
    'Fama-French daily dates must be nonempty, unique, and increasing');
dtFF = datetime(compose('%08.0f',vFFDate), 'InputFormat','yyyyMMdd');
tFFdaily = timetable(dtFF, vFFRF, 'VariableNames',{'RF'});

% Align risk-free returns to the already certified CMC calendar.  The FF
% return is earned once on an equity-market trading day; weekends/holidays
% contribute zero.  Refuse rather than silently truncate the crypto sample
% when the supplied FF file does not span it.
assert(dtDate(1) >= tFFdaily.Properties.RowTimes(1) && ...
       dtDate(end) <= tFFdaily.Properties.RowTimes(end), ...
    'Fama-French risk-free data do not span the full CMC calendar');
tFFdaily = retime(tFFdaily,dtDate,'fillwithmissing');
tFFdaily.RF(~isfinite(tFFdaily.RF)) = 0;
tFFdaily.RF = tFFdaily.RF/100;   % Make to decimal number
vRiskFree   = tFFdaily.RF;

% Keep only relevant meta data
rMetaData2.cName            = rMetaData.cName;
rMetaData2.cSymbol          = rMetaData.cSymbol;
rMetaData2.lIsCoin          = strcmpi(rMetaData.cCoinType,'coin')';
rMetaData2.lIsToken         = strcmpi(rMetaData.cCoinType,'token')';
rMetaData2.lIsStable        = logical(rMetaData.vStableCoin)';
rMetaData2.vID              = vAssetID_Close;
fprintf('metadata_unknown_coin_type_assets=%i\n', ...
    nnz(~rMetaData2.lIsCoin & ~rMetaData2.lIsToken));
rMetaData = rMetaData2;

%% Remove data errors
% P0 retains the pre-unified rule: a zero volume paired with an unavailable
% adjacent-day return is treated as missing.  No OHLC forward fill or common
% volume-zero fill is applied in this preprocessing arm.
lReplaceVol             = mVolume == 0 & isnan(mReturns);
mVolume(lReplaceVol)    = NaN;

% The paper defines a valid observation by close, volume, and market value.
% Do not delete an otherwise valid core observation merely because an OHLC
% field used by a subset of technical indicators is unavailable.
[lIsAvailObs, mME, mVolume, mClose] = ...
    fEnsureAllObs(mME, mVolume, mClose);
% This is a one-way core-to-auxiliary mask: an ME/volume/close gap must also
% break OHLC-based technical windows, but an auxiliary-field gap does not
% remove an otherwise valid core observation.
[mOpen,mHigh,mLow,rOHLCValidationDiagnostics] = ...
    fMaskAuxiliaryOHLC(lIsAvailObs,mClose,mOpen,mHigh,mLow);
fprintf('auxiliary_ohlc_invalid_ranges=%d\n', ...
    rOHLCValidationDiagnostics.iNumInvalidAuxiliaryRanges);

% Recompute returns after all price/core-data checks.  This is essential at
% internal gaps: both the missing day and the first resumed observation
% must have a missing return because a valid adjacent close pair is absent.
mReturns = [NaN(1, size(mClose,2)); (mClose(2:end,:)./mClose(1:end-1,:)) - 1];
mReturns(~lIsAvailObs) = NaN;

% Exclude only assets with no usable core observation at all. An asset with
% sparse valid history but no adjacent close pair still remains in the
% certified universe; its unavailable returns stay NaN.
lExclude                = ~any(lIsAvailObs,1);

% Report, but never screen on, full-sample history length. These diagnostics
% make short histories and internal gaps visible without turning them into a
% look-ahead asset filter.
vCoreDays = sum(lIsAvailObs,1);
vReturnDays = sum(isfinite(mReturns),1);
lAfterFirst = cumsum(lIsAvailObs,1) > 0;
lBeforeLast = flipud(cumsum(flipud(lIsAvailObs),1) > 0);
lInternalGapAsset = any(lAfterFirst & lBeforeLast & ~lIsAvailObs,1);
rRawUniverseDiagnostics = struct();
rRawUniverseDiagnostics.iNumInputAssets = numel(vCoreDays);
rRawUniverseDiagnostics.iNumNoCoreAssets = nnz(vCoreDays == 0);
rRawUniverseDiagnostics.iNumOneCoreDayAssets = nnz(vCoreDays == 1);
rRawUniverseDiagnostics.iNumTwoToSixCoreDayAssets = ...
    nnz(vCoreDays >= 2 & vCoreDays <= 6);
rRawUniverseDiagnostics.iNumSevenToTwentyNineCoreDayAssets = ...
    nnz(vCoreDays >= 7 & vCoreDays <= 29);
rRawUniverseDiagnostics.iNumThirtyTo199CoreDayAssets = ...
    nnz(vCoreDays >= 30 & vCoreDays <= 199);
rRawUniverseDiagnostics.iNumAtLeast200CoreDayAssets = nnz(vCoreDays >= 200);
rRawUniverseDiagnostics.iNumInternalGapAssets = nnz(lInternalGapAsset);
rRawUniverseDiagnostics.iNumAssetsWithReturn = nnz(vReturnDays > 0);
rRawUniverseDiagnostics.iNumRawPositiveCloseCells = ...
    nnz(isfinite(mClosePnlRaw));
rRawUniverseDiagnostics.iNumRawVolumeCells = nnz(isfinite(mVolumeRaw));
rRawUniverseDiagnostics.iNumExcludedAssetsWithRawPositiveClose = ...
    nnz(lExclude & any(isfinite(mClosePnlRaw),1));
fprintf(['raw_universe assets=%d no_core=%d one_day=%d days_2_6=%d ' ...
    'days_7_29=%d days_30_199=%d days_ge_200=%d internal_gaps=%d ' ...
    'with_return=%d raw_close_cells=%d raw_volume_cells=%d ' ...
    'excluded_with_raw_close=%d\n'], ...
    rRawUniverseDiagnostics.iNumInputAssets, ...
    rRawUniverseDiagnostics.iNumNoCoreAssets, ...
    rRawUniverseDiagnostics.iNumOneCoreDayAssets, ...
    rRawUniverseDiagnostics.iNumTwoToSixCoreDayAssets, ...
    rRawUniverseDiagnostics.iNumSevenToTwentyNineCoreDayAssets, ...
    rRawUniverseDiagnostics.iNumThirtyTo199CoreDayAssets, ...
    rRawUniverseDiagnostics.iNumAtLeast200CoreDayAssets, ...
    rRawUniverseDiagnostics.iNumInternalGapAssets, ...
    rRawUniverseDiagnostics.iNumAssetsWithReturn, ...
    rRawUniverseDiagnostics.iNumRawPositiveCloseCells, ...
    rRawUniverseDiagnostics.iNumRawVolumeCells, ...
    rRawUniverseDiagnostics.iNumExcludedAssetsWithRawPositiveClose);
clear lAfterFirst lBeforeLast
mReturns(:,lExclude)    = [];
mME(:,lExclude)         = [];
mClose(:,lExclude)      = [];
mClosePnlRaw(:,lExclude)= [];
mMEEconomicRaw(:,lExclude)= [];
mLow(:,lExclude)        = [];
mOpen(:,lExclude)       = [];
mHigh(:,lExclude)       = [];
mVolume(:,lExclude)     = [];
mVolumeRaw(:,lExclude)  = [];
rMetaData               = structfun(@(x)x(~lExclude),rMetaData,'UniformOutput',false);

assert(isequal(size(mClosePnlRaw),size(mClose)) && ...
    isequal(size(mMEEconomicRaw),size(mME)) && ...
    isequal(size(mVolumeRaw),size(mVolume)), ...
    'Raw P&L panels must retain the certified core asset and date axes');
assert(all(isnan(mClosePnlRaw) | ...
    (isfinite(mClosePnlRaw) & mClosePnlRaw > 0),'all'), ...
    'The raw P&L close layer may contain only finite positive prices or NaN');

mCloseEconomicRaw = mClosePnlRaw;
[tMechanicalExitCalendar,rMechanicalExitCalendarAudit] = ...
    fBuildAndFreezeMechanicalExitCalendar( ...
    mCloseEconomicRaw,yrmoda(:),rMetaData.vID(:), ...
    rMetaData.cSymbol(:), ...
    [sInDataPath,'mechanical_exit_calendar.csv']);
rInputProvenance.sMechanicalExitCalendarFormat = ...
    rMechanicalExitCalendarAudit.sFormat;
rInputProvenance.sMechanicalExitCalendarSHA256 = ...
    rMechanicalExitCalendarAudit.sSHA256;
rInputProvenance.iMechanicalExits = ...
    rMechanicalExitCalendarAudit.iMechanicalExits;

% P0 deliberately performs no unified auxiliary-field fill. Persist an
% explicit all-false audit mask so the unchanged M1 b01->b02 checkpoint
% contract can distinguish "no cells were filled" from a stale checkpoint.
% This sentinel does not alter any price, volume, return, or sample value.
lUnifiedAuxiliaryFilled = false(size(mClose));

% Save data
sInputCodeFingerprint = fPipelineCodeFingerprint(pwd);
sOutputFile = [sInDataPath, 'b0DataOLHC.mat'];
sTemporary = [tempname(sInDataPath),'.mat'];
rTemporaryCleanup = onCleanup(@() iDeleteIfExists(sTemporary));
save(sTemporary, 'mClose', 'mClosePnlRaw', 'mCloseEconomicRaw', ...
    'mMEEconomicRaw', ...
    'mReturns', 'mME', ...
    'mVolume','mVolumeRaw','yrmoda', 'rMetaData', 'vRiskFree', ...
    'mLow', 'mOpen', 'mHigh', ...
    'rInputProvenance','sInputCodeFingerprint','rRawUniverseDiagnostics', ...
    'rOHLCValidationDiagnostics','rV2RawCorrectionAudit', ...
    'lUnifiedAuxiliaryFilled', ...
    'tMechanicalExitCalendar', ...
    'rMechanicalExitCalendarAudit','-v7.3');
[lMoved,sMoveMessage] = movefile(sTemporary,sOutputFile,'f');
assert(lMoved,'Could not atomically publish %s: %s',sOutputFile,sMoveMessage);
clear rTemporaryCleanup

% Restore path
path(sOldPath);

function dtDate = fReadDateColumn(sFilename)
cDate = readcell(sFilename, 'Range', 'A:A');
assert(numel(cDate) >= 2, 'No date observations in %s', sFilename);
cDate(1) = [];
if all(cellfun(@isdatetime, cDate))
    dtDate = vertcat(cDate{:});
else
    dtDate = datetime(string(cDate), 'InputFormat', 'yyyy-MM-dd');
end
dtDate = dtDate(:);
assert(all(~isnat(dtDate)), 'Invalid date in %s', sFilename);
assert(all(diff(dtDate) > days(0)), ...
    'Dates must be unique and strictly increasing in %s', sFilename);
end

function iDeleteIfExists(sFilename)
if exist(sFilename,'file') == 2
    delete(sFilename);
end
end
