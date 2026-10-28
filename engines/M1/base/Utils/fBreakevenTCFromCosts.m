function dBreakeven = fBreakevenTCFromCosts(vPortRet, vCostBase, options)
% First transaction-cost rate at which the mean return is not significant.
%
% Significance follows the paper/old convention of a two-sided one-sample
% t-test. Starting from zero cost, return the first rate at which p >= alpha;
% do not minimize |p-alpha| over the full interval because that does not
% encode the first loss of significance.

arguments
    vPortRet (:,1) {mustBeNumeric}
    vCostBase (:,1) {mustBeNumeric}
    options.dAlpha (1,1) {mustBeNumeric, mustBeNonnegative} = 0.05
end

assert(options.dAlpha > 0 && options.dAlpha < 1, ...
    'The significance level must lie strictly between zero and one');

assert(all(vCostBase(isfinite(vCostBase)) >= 0), ...
    'Transaction-cost base must be nonnegative');
lValid = isfinite(vPortRet) & isfinite(vCostBase);
vPortRet = vPortRet(lValid);
vCostBase = vCostBase(lValid);
if numel(vPortRet) < 2 || all(vCostBase == 0)
    dBreakeven = NaN;
    return
end

dBreakevenZero = mean(vPortRet, 'omitnan') ./ mean(vCostBase, 'omitnan');
if ~isfinite(dBreakevenZero) || dBreakevenZero <= 0
    dBreakeven = NaN;
    return
end

% A portfolio that is already insignificant requires no transaction cost to
% lose significance. At dBreakevenZero the sample mean is zero, so that end
% of the interval is necessarily nonsignificant (up to roundoff).
dPZeroCost = iTwoSidedPValue(vPortRet);
if ~isfinite(dPZeroCost)
    dBreakeven = NaN;
    return
elseif dPZeroCost >= options.dAlpha
    dBreakeven = 0;
    return
end

dLower = 0;
dUpper = dBreakevenZero;
dPUpper = iTwoSidedPValue(vPortRet - dUpper*vCostBase);
if ~isfinite(dPUpper) || dPUpper < options.dAlpha
    error('Could not bracket the first loss of statistical significance');
end

% For y(x)=return-x*cost with positive mean on [0,dBreakevenZero), the
% absolute one-sample t-statistic can rise at most once before declining to
% zero. Hence the significant region containing x=0 has one right boundary.
% Maintain the explicit invariant p(lower)<alpha<=p(upper) and converge to
% that first boundary. This also handles a zero-variance discontinuity.
for iIdx = 1:200
    dMid = dLower + (dUpper-dLower)/2;
    if dMid == dLower || dMid == dUpper
        break
    end
    dPMid = iTwoSidedPValue(vPortRet - dMid*vCostBase);
    if ~isfinite(dPMid)
        error('The BETC significance statistic became undefined');
    elseif dPMid >= options.dAlpha
        dUpper = dMid;
    else
        dLower = dMid;
    end
end
dBreakeven = dUpper;
end

function dPval = iTwoSidedPValue(vNetReturns)
dMean = mean(vNetReturns);
dStd = std(vNetReturns);
if dStd == 0
    if dMean == 0
        dPval = 1;
    else
        dPval = 0;
    end
else
    dT = dMean/(dStd/sqrt(numel(vNetReturns)));
    dPval = 2*tcdf(-abs(dT), numel(vNetReturns)-1);
end
if ~isfinite(dPval)
    dPval = NaN;
end
end
