function mData = fWinsorize(mData,dPercentile,iMethod,iDim)
% Function for implementing winsorizing
% Input:
%   mData

% Determine dimensions
[iNumRows, iNumCols] = size(mData);

% Set optional arguments
if nargin < 4 || isempty(iDim)
    iDim = 1;
end
if nargin < 3 || isempty(iMethod)
    iMethod = 1;
end
if nargin < 2 || isempty(dPercentile)
    dPercentile = 0.01;
end

% Calculate quantiles
if iMethod == 1
    % Upper and lower quantile winsorization
    vQuanL = quantile(mData, dPercentile, iDim);
    vQuanH = quantile(mData, 1 - dPercentile, iDim);
    if iDim == 1
        mQuanL = repmat(vQuanL, iNumRows, 1);
        mQuanH = repmat(vQuanH, iNumRows, 1);
    else
        mQuanL = repmat(vQuanL, 1, iNumCols);
        mQuanH = repmat(vQuanH, 1, iNumCols);
    end
    
    % Lower winsorization
    mData(mData < vQuanL) = mQuanL(mData < vQuanL);
    
    % Upper winsorization
    mData(mData > vQuanH) = mQuanH(mData > vQuanH);
elseif iMethod == 2
    % Upper winsorization
    vQuanH = quantile(mData, 1 - dPercentile, iDim);
    
    % Make to matrix
    if iDim == 1
        mQuanH = repmat(vQuanH, iNumRows, 1);
    else
        mQuanH = repmat(vQuanH, 1, iNumCols);
    end
    
    % Upper winsorization
    mData(mData > vQuanH) = mQuanH(mData > vQuanH);
    
elseif iMethod == 4
    % Lower winsorization
    vQuanL = quantile(mData, dPercentile, iDim);
    
    % Make to matrix
    if iDim == 1
        mQuanL = repmat(vQuanL, iNumRows, 1);
    else
        mQuanL = repmat(vQuanL, 1, iNumCols);
    end
    
    % Lower winsorization
    mData(mData < vQuanL) = mQuanL(mData < vQuanL);
end
end