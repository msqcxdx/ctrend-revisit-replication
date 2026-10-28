function mMEClean = fCleanMarketCapAgainstBitcoin(mME, vAssetID, cSymbol)
% Remove invalid market caps without broadcasting a missing BTC quote.

assert(isnumeric(mME) && ismatrix(mME), ...
    'Market capitalization must be a numeric matrix');
assert(isnumeric(vAssetID) && isvector(vAssetID) && ...
    numel(vAssetID) == size(mME,2), ...
    'Asset IDs must provide one key per market-cap column');
vAssetID = vAssetID(:)';
assert(sum(vAssetID == 1) == 1, ...
    'Exactly one Bitcoin (CMC ID 1) column is required');
iBitcoin = find(vAssetID == 1);
assert((iscell(cSymbol) || isstring(cSymbol) || ischar(cSymbol)) && ...
    numel(cSymbol) == size(mME,2), ...
    'Metadata symbols must provide one label per market-cap column');
assert(strcmpi(strtrim(string(cSymbol(iBitcoin))),"BTC"), ...
    'CMC ID 1 must be identified as BTC in metadata');

vMEBtc = mME(:,iBitcoin);
lInvalidOwnValue = ~isfinite(mME) | mME <= 0;
% The cross-asset upper-bound check is defined only when BTC itself is
% observed. A missing BTC quote contains no information about another
% asset's market capitalization and must not erase the entire market row.
lValidBitcoinReference = isfinite(vMEBtc) & vMEBtc > 0;
lAboveObservedBitcoin = lValidBitcoinReference & isfinite(mME) & ...
    mME > vMEBtc;
mMEClean = mME;
mMEClean(lInvalidOwnValue | lAboveObservedBitcoin) = NaN;
end
