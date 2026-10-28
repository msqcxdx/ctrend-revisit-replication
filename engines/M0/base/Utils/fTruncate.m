function mData = fTruncate(mData,dPercentile,iMethod,iDim)
% Function for implementing truncation
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

    % Lower truncation
    mData(mData < vQuanL) = NaN;
    
    % Upper truncation
    mData(mData > vQuanH) = NaN;
elseif iMethod == 2
    % Upper winsorization
    vQuanH = quantile(mData, 1 - dPercentile, iDim);
    
    % Upper winsorization
    mData(mData > vQuanH) = NaN;
    
elseif iMethod == 4
    % Lower winsorization
    vQuanL = quantile(mData, dPercentile, iDim);
    
    % Lower winsorization
    mData(mData < vQuanL) = NaN;
end
end