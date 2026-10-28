function [vShp,vShpT] = fSharpeRatio(mX,vRf,iDim,iAnnualize)
% Function for calculating the Sharpe ratio of a time series of returns.
% This function also works for multidimensional arrays
%
% Input:
%   mX:         T x N x ... array of returns
%               T: number of time-series observations
%               N: number of assets
%   vRf:        T x 1 vector of risk-free rates
%   iDim:       Scalar, integer, specifies the dimension
%   iAnnualize  Scalar, integer, specifies the data frequency for
%               annualization
%               0: do not annualize Sharpe ratio
%               1: monthly data (default)
%               2: weekly data 
%               3: daily data
%
% Output:
%   vShp:       N x 1 vector of (annualized) Sharpe ratios
%               N: number of assets
%   vShpT:      N x 1 vector of t-statistics of Sharpe ratios
%               N: number of assets

% Check input arguments
arguments
    mX {mustBeNumeric}
    vRf (:,1) {mustBeNumeric}   = 0
    iDim (1,1) {mustBeNumeric}  = 1
    iAnnualize (1,1) {mustBeNumericOrLogical} = 1
end

% Make X to N x T x ... array. 
mX(~isfinite(mX)) = NaN;
vRf(~isfinite(vRf)) = NaN;
assert(ismember(iDim, [1,2]) && iDim == fix(iDim), ...
    'iDim must identify rows (1) or columns (2) as the time dimension');
assert(ismember(iAnnualize, 0:3) && iAnnualize == fix(iAnnualize), ...
    'iAnnualize must be 0 (none), 1 (monthly), 2 (weekly), or 3 (daily)');
if iDim == 1
    mX = permute(mX, [2,1,3,4]);
end

% The time dimension is now dimension 2. The documented T-by-1 risk-free
% input must therefore be reshaped to 1-by-T before implicit expansion.
% Both the mean and volatility of a Sharpe ratio refer to excess returns.
iNumTime = size(mX, 2);
assert(isscalar(vRf) || numel(vRf) == iNumTime, ...
    'Risk-free rate must be scalar or have one observation per time period');
if isscalar(vRf)
    mExcess = mX - vRf;
else
    vRfShape = ones(1, max(ndims(mX), 2));
    vRfShape(2) = iNumTime;
    mExcess = mX - reshape(vRf, vRfShape);
end

% Determine dimensions
vNumObs = sum(isfinite(mExcess), 2);

% Calculate mean and standard deviation
vMean = mean(mExcess, 2, 'omitnan');
vStd = std(mExcess, [], 2, 'omitnan');

% A Sharpe ratio is undefined with fewer than two observations or zero/
% nonfinite volatility. Never turn such a sample into an infinite statistic.
lDefined = vNumObs >= 2 & isfinite(vMean) & isfinite(vStd) & vStd > 0;
vShp = NaN(size(vMean));
vShp(lDefined) = vMean(lDefined)./vStd(lDefined);

% Lo IID/normal approximation for the Sharpe-ratio test statistic.  This is
% the old/paper convention; it is not a HAC serial-correlation adjustment.
if nargout == 2
    vShpT = vShp ./ sqrt((1 + 0.5 * vShp.^2)./vNumObs);
    vShpT(~lDefined | ~isfinite(vShpT)) = NaN;
end

% Annualize Sharpe ratio
if iAnnualize == 1
    % monthly data
    vShp = vShp * sqrt(12);
elseif iAnnualize == 2
    % weekly data
    vShp = vShp * sqrt(52);
elseif iAnnualize == 3
    % Daily data
    vShp = vShp * sqrt(250);
end
end
