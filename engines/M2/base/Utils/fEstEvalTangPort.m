function [dReturn,vWts] = fEstEvalTangPort(mY,vYout,dScale)
% Function for estimating the weights of an unrestricted 
% maximum sharpe ratio portfolio and applying the weights to next period's
% returns
%
% Function is adapted from Kelly et al. 2019
%
% Input:
%   mY:         T x N matrix of historical returns
%               T: number of time-series observations
%               N: number of assets
%   vYout:      1 x N vector of next period's returns
%               N: number of assets
%   dScale:     Scalar, double, target volatility (default = NaN -> no
%               rescaling)
%
% Output:
%   dReturn:    Scalar, double, next period's portfolio return
%   vWts:       N x 1 vector of portfolio weights
%               N: number of assets

% Optional arguments
if nargin < 3 || isempty(dScale)
    dScale = NaN;
end

% Settings
rf      = 0;                            % Risk free rate
iota    = ones(size(mY,2),1);           % Vector of ones

% Calculate mean and variance
S       = cov(mY);                      % Historical covariance matrix
mu      = mean(mY)';                    % Historical mean

% Calculate weights
vWts      = S\(mu-rf*iota)/((iota'/S)*(mu-rf*iota));
if vWts'*(mu-rf)<0, vWts = -vWts; end        

% Find scaling factor of portfolio
if ~isnan(dScale)
    dScale = dScale/sqrt(vWts'*S*vWts);
else
    dScale = 1;
end

% Scale weights with expected volatility
vWts = vWts * dScale;

% Calculate out-of-sample portfolio return
dReturn  = vYout*vWts;
end