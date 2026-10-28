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
if iDim == 1
    mX = permute(mX, [2,1,3,4]);
end

% Determine dimensions
vNumObs = sum(~isnan(mX), 2);

% Calculate mean and standard deviation
vMean = mean(mX - vRf, 2, 'omitnan');
vStd = std(mX, [], 2, 'omitnan');

% Calculate Sharpe ratio
vShp = vMean./vStd;

% Calculate test statistic of Sharpe ratio (Lo: The Statistics of Sharpe Ratios)
if nargout == 2
    vShpT = vShp ./ sqrt((1 + 0.5 * vShp.^2)./vNumObs);
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
elseif iAnnualize > 3
    error('Unknown data frequency');
end
end