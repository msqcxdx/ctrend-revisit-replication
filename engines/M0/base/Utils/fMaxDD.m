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
    dim (1,1) {mustBeNumeric, mustBePositive} = 1
    k (1,1) {mustBeNumeric, mustBePositive} = 1
end

% Calculate cumulative return
mCumRet     = cumsum(mRet, dim, 'omitnan');

% Calculate difference
mDiffCumRet = -diff(mCumRet, 1, dim);

% Calculate maximum drawdown
mMaxDD      = maxk(mDiffCumRet, k, dim);
end