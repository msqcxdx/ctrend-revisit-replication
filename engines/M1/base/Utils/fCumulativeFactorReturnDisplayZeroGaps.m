function mCumRet = fCumulativeFactorReturnDisplayZeroGaps(mRet, dim)
% Create a continuous cumulative-return display with internal gaps set to 0.
%
% This helper is presentation-only.  Before the first observed increment a
% series remains undefined.  From its first observation onward, a missing
% calendar increment is displayed as 0 so that the plotted cumulative line
% stays flat and continuous.  The input return matrix is not modified, and
% this display copy must never be used for tables, estimators, portfolio
% accounting, or economic-return claims.

arguments
    mRet (:,:,:) {mustBeNumeric}
    dim (1,1) {mustBeNumeric, mustBeInteger, mustBePositive} = 1
end
assert(dim == 1 || dim == 2, 'Time dimension must be 1 or 2');

mRet(~isfinite(mRet)) = NaN;
iNumDims = ndims(mRet);
vOrder = [dim, 1:dim-1, dim+1:iNumDims];
mRetTimeFirst = permute(mRet,vOrder);
vSize = size(mRetTimeFirst);
iNumTime = vSize(1);
mRetFlat = reshape(mRetTimeFirst,iNumTime,[]);
mCumFlat = NaN(size(mRetFlat));

for iIdxSeries = 1:size(mRetFlat,2)
    vRet = mRetFlat(:,iIdxSeries);
    iIdxFirstFinite = find(isfinite(vRet),1,'first');
    if isempty(iIdxFirstFinite)
        continue
    end

    vDisplayIncrement = vRet(iIdxFirstFinite:end);
    vDisplayIncrement(~isfinite(vDisplayIncrement)) = 0;
    vCum = cumsum(vDisplayIncrement);
    iFirstOverflow = find(~isfinite(vCum),1,'first');
    if isempty(iFirstOverflow)
        iNumDefined = numel(vCum);
    else
        iNumDefined = iFirstOverflow-1;
    end
    if iNumDefined > 0
        mCumFlat(iIdxFirstFinite:iIdxFirstFinite+iNumDefined-1, ...
            iIdxSeries) = vCum(1:iNumDefined);
    end
end

mCumTimeFirst = reshape(mCumFlat,vSize);
mCumRet = ipermute(mCumTimeFirst,vOrder);
end
