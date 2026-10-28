function fAssertCTRENDAlignment(rCTREND, vDates, vAssetID, iNumAssets, ...
        sExpectedDataBuildID)
% Assert exact date, asset-order, and signal-dimension alignment.

arguments
    rCTREND struct
    vDates (:,1) {mustBeNumeric}
    vAssetID (:,1) {mustBeNumeric}
    iNumAssets (1,1) {mustBeInteger, mustBePositive}
    sExpectedDataBuildID {mustBeTextScalar}
end

fAssertSavedResultProvenance(rCTREND, sExpectedDataBuildID);
cRequired = {'vDates','vAssetID','mYhat','mRetPnlOOS'};
assert(all(isfield(rCTREND, cRequired)), ...
    'Saved CTREND file lacks required alignment fields');
assert(isequal(vDates(:), rCTREND.vDates(:)), ...
    'CTREND and weekly data dates are not identical');
assert(isequal(vAssetID(:), rCTREND.vAssetID(:)), ...
    'CTREND and weekly data asset IDs/order are not identical');
assert(size(rCTREND.mYhat,1) == iNumAssets && ...
       size(rCTREND.mYhat,2) == numel(vDates), ...
    'CTREND signal dimensions do not match assets by weekly dates');
assert(isequal(size(rCTREND.mRetPnlOOS), size(rCTREND.mYhat)), ...
    'Strict-OOS evaluation returns do not align with CTREND signals');
end
