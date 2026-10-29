function [mOpen,mHigh,mLow,mClose,mVolume,rAudit,lAuxiliaryFilled] = ...
    fApplyUnifiedMissingDataPreprocessing( ...
    mOpen,mHigh,mLow,mClose,mVolume,vDates,vAssetID)
% Apply the frozen missing-data rule shared by every new 3x3 experiment.
%
% Price rule
% ----------
% For each asset and date, a missing open, high, low, or close is replaced
% by that asset's most recent earlier observed close.  Price filling is
% restricted to the interval from the first through the last ORIGINAL
% positive close.  Leading cells and cells after the last original close
% remain missing.  Consequently this routine repairs internal reporting
% gaps but never manufactures post-exit prices.
%
% Volume/turnover rule
% --------------------
% Every non-finite or negative volume/turnover cell is replaced by zero.
% Existing finite nonnegative values, including existing zeros, are preserved.
%
% The helper does not rescale an extreme price, infer an external-source
% quote, or decide portfolio liquidation.  It records the original close
% endpoints required by the separately frozen mechanical exit calendar.

arguments
    mOpen (:,:) {mustBeNumeric}
    mHigh (:,:) {mustBeNumeric}
    mLow (:,:) {mustBeNumeric}
    mClose (:,:) {mustBeNumeric}
    mVolume (:,:) {mustBeNumeric}
    vDates (:,1) {mustBeNumeric}
    vAssetID (:,1) {mustBeNumeric}
end

assert(isequal(size(mOpen),size(mHigh),size(mLow),size(mClose), ...
    size(mVolume)), ...
    'OHLC and volume panels must have identical dimensions');
[iNumDates,iNumAssets] = size(mClose);
assert(numel(vDates) == iNumDates && numel(vAssetID) == iNumAssets, ...
    'Date and asset keys must agree with the panel axes');
assert(all(isfinite(vDates)) && all(diff(vDates) > 0), ...
    'Dates must be finite, unique, and strictly increasing');
assert(all(isfinite(vAssetID)) && ...
    numel(unique(vAssetID)) == iNumAssets, ...
    'Asset IDs must be finite and unique');

% Invalid/non-positive raw price values enter the declared missing-value
% rule as NaN.  Negative volume is not a valid turnover observation and is
% therefore treated exactly like another missing volume cell.
mOpen(~isfinite(mOpen) | mOpen <= 0) = NaN;
mHigh(~isfinite(mHigh) | mHigh <= 0) = NaN;
mLow(~isfinite(mLow) | mLow <= 0) = NaN;
mClose(~isfinite(mClose) | mClose <= 0) = NaN;
mVolume(~isfinite(mVolume) | mVolume < 0) = NaN;

lOriginalCloseObserved = isfinite(mClose);
lOpenFilled = false(iNumDates,iNumAssets);
lHighFilled = false(iNumDates,iNumAssets);
lLowFilled = false(iNumDates,iNumAssets);
lCloseFilled = false(iNumDates,iNumAssets);
vFirstOriginalCloseIndex = NaN(iNumAssets,1);
vLastOriginalCloseIndex = NaN(iNumAssets,1);

for iIdxAsset = 1:iNumAssets
    iFirst = find(lOriginalCloseObserved(:,iIdxAsset),1,'first');
    iLast = find(lOriginalCloseObserved(:,iIdxAsset),1,'last');
    if isempty(iFirst)
        continue
    end
    vFirstOriginalCloseIndex(iIdxAsset) = iFirst;
    vLastOriginalCloseIndex(iIdxAsset) = iLast;

    dPreviousClose = NaN;
    for iIdxDate = 1:iLast
        % "Previous close" means strictly earlier than the current row.
        % Thus a missing auxiliary field on the first observed close date
        % remains missing because no prior close exists.
        if isfinite(dPreviousClose)
            if ~isfinite(mOpen(iIdxDate,iIdxAsset))
                mOpen(iIdxDate,iIdxAsset) = dPreviousClose;
                lOpenFilled(iIdxDate,iIdxAsset) = true;
            end
            if ~isfinite(mHigh(iIdxDate,iIdxAsset))
                mHigh(iIdxDate,iIdxAsset) = dPreviousClose;
                lHighFilled(iIdxDate,iIdxAsset) = true;
            end
            if ~isfinite(mLow(iIdxDate,iIdxAsset))
                mLow(iIdxDate,iIdxAsset) = dPreviousClose;
                lLowFilled(iIdxDate,iIdxAsset) = true;
            end
            if ~isfinite(mClose(iIdxDate,iIdxAsset))
                mClose(iIdxDate,iIdxAsset) = dPreviousClose;
                lCloseFilled(iIdxDate,iIdxAsset) = true;
            end
        end

        if isfinite(mClose(iIdxDate,iIdxAsset))
            dPreviousClose = mClose(iIdxDate,iIdxAsset);
        end
    end
end

lVolumeFilled = ~isfinite(mVolume);
mVolume(lVolumeFilled) = 0;

% The exact user-specified fieldwise fill can make an imputed high/low/open
% inconsistent with another observed field on a large jump date.  Do not
% silently rewrite either value.  Record those cells so downstream code can
% preserve the declared fill without mistaking it for an untouched candle.
lAnyAuxiliaryFilled = lOpenFilled | lHighFilled | lLowFilled;
lAuxiliaryFilled = lAnyAuxiliaryFilled;
lRangeConflict = ...
    (isfinite(mHigh) & isfinite(mLow) & mHigh < mLow) | ...
    (isfinite(mHigh) & isfinite(mClose) & mHigh < mClose) | ...
    (isfinite(mHigh) & isfinite(mOpen) & mHigh < mOpen) | ...
    (isfinite(mLow) & isfinite(mClose) & mLow > mClose) | ...
    (isfinite(mLow) & isfinite(mOpen) & mLow > mOpen);

rAudit = struct();
rAudit.sFormat = 'ctrend-unified-missing-preprocessing-v1';
rAudit.sPriceRule = [ ...
    'within original close history, missing OHLC uses the most recent ' ...
    'strictly earlier nonmissing close; no leading or post-terminal fill'];
rAudit.sVolumeRule = 'nonfinite or negative volume/turnover becomes zero';
rAudit.vAssetID = vAssetID(:);
rAudit.vDate = vDates(:);
rAudit.vFirstOriginalCloseIndex = vFirstOriginalCloseIndex;
rAudit.vLastOriginalCloseIndex = vLastOriginalCloseIndex;
rAudit.vFirstOriginalCloseDate = iIndexToDate( ...
    vFirstOriginalCloseIndex,vDates);
rAudit.vLastOriginalCloseDate = iIndexToDate( ...
    vLastOriginalCloseIndex,vDates);
rAudit.iOpenFilled = nnz(lOpenFilled);
rAudit.iHighFilled = nnz(lHighFilled);
rAudit.iLowFilled = nnz(lLowFilled);
rAudit.iCloseFilled = nnz(lCloseFilled);
rAudit.iVolumeFilledWithZero = nnz(lVolumeFilled);
rAudit.iAssetsWithoutOriginalClose = ...
    nnz(~isfinite(vLastOriginalCloseIndex));
rAudit.iPostTerminalPriceCellsFilled = nnz( ...
    iPostTerminalMask(vLastOriginalCloseIndex,iNumDates) & ...
    (lOpenFilled | lHighFilled | lLowFilled | lCloseFilled));
rAudit.iImputedAuxiliaryRangeConflicts = nnz( ...
    lRangeConflict & lAnyAuxiliaryFilled);
rAudit.lUsesExternalSource = false;
rAudit.lFillsAfterLastOriginalClose = false;

assert(rAudit.iPostTerminalPriceCellsFilled == 0, ...
    'Unified preprocessing must never fill a post-terminal price');
assert(all(isfinite(mVolume(:))) && all(mVolume(:) >= 0), ...
    'Unified volume output must be finite and nonnegative');
end

function vDate = iIndexToDate(vIndex,vDates)
vDate = NaN(size(vIndex));
l = isfinite(vIndex);
vDate(l) = vDates(vIndex(l));
end

function lMask = iPostTerminalMask(vLastIndex,iNumDates)
lMask = false(iNumDates,numel(vLastIndex));
for iIdxAsset = 1:numel(vLastIndex)
    if isfinite(vLastIndex(iIdxAsset)) && vLastIndex(iIdxAsset) < iNumDates
        lMask(vLastIndex(iIdxAsset)+1:end,iIdxAsset) = true;
    end
end
end
