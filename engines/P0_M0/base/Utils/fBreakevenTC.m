function [dBreakeven, rStats] = fBreakevenTC(vPortRet, mWts, options)
% Function for calculating breakeven transaction costs.
%
% Input:
%   vPortRet:       1 x T matrix of portfolio returns
%                   T: number of time-series observations
%   mWts:           N x T matrix of portfolio weights
%                   N: number of assets in portfolio
%                   T: number of time-series observations
%   options:        Name-Value pair arguments
%       'dAlpha':       Scalar, double, significance level 
%                       (default = 0 -> BETC rate that sets the return to
%                       exactly zero)
%                       0.05 would imply that the two-sided p-value is
%                       larger than 5%
%
% Output:
%   dBreakeven:     Scalar, double, breakeven transaction costs
%   rStats:         Struct, containing additional statistics
%       .dMean:         Scalar, double, mean of net return for breakeven
%                       transaction cost rate
%       .dStd:          Scalar, double, std of net return for breakeven
%                       transaction cost rate
%       .dShp:          Scalar, double, net Sharpe ratio
%       .dTstat:        Scalar, double, t-statistic
%       .dShp:          Scalar, double, p-value
%       .fval:          Scalar, double, objective function value

% Check inputs
arguments
    vPortRet (1,:) {mustBeNumeric}
    mWts (:,:) {mustBeNumeric}
    options.dAlpha (1,1) {mustBeNumeric, mustBeNonnegative, mustBeNonempty} = 0
end

% Determine dimensions
[iNumAssets, iNumObs] = size(mWts);

% Check dimensions
assert(iNumObs == length(vPortRet), 'Number of time-series dimension must agree');

% Return a zero if the average return in negative
if sign(mean(vPortRet,'omitnan')) == -1
    dBreakeven = 0;
    rStats     = struct();
    return
end

% Replace missing values with zeros
mWts(isnan(mWts)) = 0;

% Get previous and current weights
mWtsTempL1 = [zeros(iNumAssets, 1), mWts(:,1:end-1)];
mWtsTempL0 = mWts;

% Get absolute weight changes
mChWts      = abs(mWtsTempL1 - mWtsTempL0);

% Calculate the cross-sectional sum of weight changes
vSumChWts   = sum(mChWts, 1, 'omitnan');

% Set nonavailable time ticks to missing
vSumChWts(all(isnan(mChWts),1)) = NaN;
vSumChWts(isnan(vPortRet))      = NaN;

% Calculate BETC rate that set the return to exactly zero
dBreakevenZero = mean(vPortRet, 'omitnan')./mean(vSumChWts, 'omitnan');

% Calculate BETC that allow for significance level
if options.dAlpha == 0
    % Return transaction costs
    dBreakeven  = dBreakevenZero;
    fval        = NaN;
else
    % Optimization options
    optoptions = optimset('Display', 'off', 'MaxIter', 4000, 'MaxFunEvals', 1000*iNumObs, 'TolX', 1e-10);

    % Call optimizer. Must be larger zero but smaller than BETC rate that
    % sets the return to exactly zero
    [dBreakeven,fval,exitflag] = ...
        fminbnd(@(x)fObjVal(x,vSumChWts, vPortRet, options.dAlpha),0,dBreakevenZero,optoptions);
end

% Control: Calculate net return
if nargout == 2
    % Calculate the trading costs
    vTradingCosts   = dBreakeven * vSumChWts;
    
    % Calculate net return
    vNetReturn      = vPortRet - vTradingCosts;
    
    % Calculate descriptive statistics
    rStats.dMean    = mean(vNetReturn, 'omitnan');
    rStats.dStd     = std(vNetReturn, 'omitnan');
    rStats.dShp     = rStats.dMean/rStats.dStd;
    [~,rStats.dPval,~,stats] = ttest(vNetReturn);
    rStats.dTstat   = stats.tstat;
    rStats.fval     = fval;
end
end


function dDiff = fObjVal(x, vSumChWts, vPortRet, dAlpha)
% Function

% Calculate the trading costs
vTradingCosts = x * vSumChWts;

% Calculate net portfolio return
vNetReturn = vPortRet - vTradingCosts;

% t-Test
[~,p] = ttest(vNetReturn, 0, 'Tail', 'right');

% Calculate absolute difference 
dDiff = abs(p - (dAlpha+1e-4)/2);
end