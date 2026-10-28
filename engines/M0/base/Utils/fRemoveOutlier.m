function mData = fRemoveOutlier(mData, dPercentile, sMethod, sTail, iDim)
% Function for implementing truncation/winsorization
%
% Input:
%   mData:          T x N data matrix
%   dPercentile:    Scalar, double, percentile for outlier treatment
%                   (default = 1%)
%   sMethod:        String, specifies the method 
%                   'winsorize' 
%                   'truncate' (default)
%   sTail:          String, specifies the tail of the distribution
%                   'left', 'right', 'both' (default)
%   iDim:           Scalar, integer, specifies the dimension (default = 2,
%                   i.e., if data is aranged as T x N matrix, data is
%                   cleaned cross-sectionally)
%
% Output:
%   mData:          T x N clean data matrix

% Check input
arguments
    mData {mustBeNumeric}
    dPercentile (1,1) {mustBeNumeric, mustBeNonnegative} = 0.01;
    sMethod char = 'truncate'
    sTail char = 'both'
    iDim (1,1) {mustBeNumeric, mustBeNonnegative} = 2
end

% Determine dimensions
[iNumRows, iNumCols] = size(mData);

% Calculate quantiles
vQuantileLeft   = quantile(mData, dPercentile, iDim);
vQuantileRight  = quantile(mData, 1 - dPercentile, iDim);

% Clean data
if any(strcmpi(sMethod,{'truncate','truncation','trunc'}))
    % Truncation

    % Left truncation
    if any(strcmpi(sTail, {'left', 'both'}))
        mData(mData < vQuantileLeft) = NaN;
    end

    % Right truncation
    if any(strcmpi(sTail, {'right', 'both'}))
        mData(mData > vQuantileRight) = NaN;
    end

elseif any(strcmpi(sMethod,{'winsorize','winsorization','win'}))
    % Winsorization

    % Increase the dimensions of the upper and lower percentiles
    if iDim == 1
        mQuantileLeft   = repmat(vQuantileLeft, iNumRows, 1);
        mQuantileRight  = repmat(vQuantileRight, iNumRows, 1);
    else
        mQuantileLeft   = repmat(vQuantileLeft, 1, iNumCols);
        mQuantileRight  = repmat(vQuantileRight, 1, iNumCols);
    end

    % Left truncation
    if any(strcmpi(sTail, {'left', 'both'}))
        mData(mData < vQuantileLeft) = mQuantileLeft(mData < vQuantileLeft);
    end

    % Right truncation
    if any(strcmpi(sTail, {'right', 'both'}))
        mData(mData > vQuantileRight) = mQuantileRight(mData > vQuantileRight);
    end
else
    error('Unknown method');
end
end