function mMaxDD = fMaxDD(mRet, dim, k)
% Function for calculating the maximum drawdown as in Gu, Kelly, and Xiu
% (2020)
%
% Input:
%   mRet:       T x N or N x T return matrix
%               T: number of time-series observations
%               N: number of asstes
%   dim:        Scalar, integer, specifies the dimension
%               (default = 1 -> mRet must be T x N matrix)
%   k:          Scalar, integer, number of maximum drawdowns
%
% Output:
%   mMaxDD:     k x N or N x k matrix of maximum drawdown

% Check inputs
arguments
    mRet (:,:,:) {mustBeNumeric}
    dim (1,1) {mustBeNumeric, mustBeInteger, mustBePositive} = 1
    k (1,1) {mustBeNumeric, mustBeInteger, mustBePositive} = 1
end

assert(dim == 1 || dim == 2, 'Time dimension must be 1 or 2');

% A full-period drawdown may trim structural leading cells before a return
% series starts. Once it has started, any missing return (including at the
% planned sample end) leaves the wealth path and maximum drawdown undefined.
% Include initial wealth one so a first-period loss uses the correct peak.
mRet(~isfinite(mRet)) = NaN;
iNumDims = ndims(mRet);
vOrder = [dim, 1:dim-1, dim+1:iNumDims];
mRetTimeFirst = permute(mRet,vOrder);
vSize = size(mRetTimeFirst);
iNumTime = vSize(1);
mRetFlat = reshape(mRetTimeFirst,iNumTime,[]);
mMaxFlat = NaN(k,size(mRetFlat,2));

for iIdxSeries = 1:size(mRetFlat,2)
    vRet = mRetFlat(:,iIdxSeries);
    vIdxFinite = find(isfinite(vRet));
    if isempty(vIdxFinite)
        continue
    end
    iIdxFirst = vIdxFinite(1);
    vRetUse = vRet(iIdxFirst:end);
    if any(~isfinite(vRetUse)) || any(1+vRetUse < 0)
        continue
    end
    vWealth = [1;cumprod(1+vRetUse)];
    vPeak = cummax(vWealth);
    vDrawdown = (vPeak-vWealth)./vPeak;
    if any(~isfinite(vDrawdown))
        continue
    end
    iNumOut = min(k,numel(vDrawdown));
    mMaxFlat(1:iNumOut,iIdxSeries) = maxk(vDrawdown,iNumOut);
end

vOutSize = vSize;
vOutSize(1) = k;
mMaxTimeFirst = reshape(mMaxFlat,vOutSize);
mMaxDD = ipermute(mMaxTimeFirst,vOrder);
end
