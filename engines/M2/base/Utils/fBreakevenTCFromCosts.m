function dBreakeven = fBreakevenTCFromCosts(vPortRet,vCostBase,options)
% First transaction-cost rate at which the mean return is not significant.
% This cost-vector form is used only when the frozen-exit ledger introduces
% observable within-week sell-and-reinvest trades that cannot be reconstructed
% from formation weights alone.

arguments
    vPortRet (:,1) {mustBeNumeric}
    vCostBase (:,1) {mustBeNumeric}
    options.dAlpha (1,1) {mustBeNumeric,mustBeNonnegative} = 0.05
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
dZeroMean = mean(vPortRet)/mean(vCostBase);
if ~isfinite(dZeroMean) || dZeroMean <= 0
    dBreakeven = NaN;
    return
end
dP0 = iTwoSidedPValue(vPortRet);
if ~isfinite(dP0)
    dBreakeven = NaN;
    return
elseif dP0 >= options.dAlpha
    dBreakeven = 0;
    return
end
dLower = 0;
dUpper = dZeroMean;
dPUpper = iTwoSidedPValue(vPortRet-dUpper*vCostBase);
assert(isfinite(dPUpper) && dPUpper >= options.dAlpha, ...
    'Could not bracket the first loss of statistical significance');
for iIdx = 1:200
    dMid = dLower+(dUpper-dLower)/2;
    if dMid == dLower || dMid == dUpper
        break
    end
    dPMid = iTwoSidedPValue(vPortRet-dMid*vCostBase);
    assert(isfinite(dPMid), ...
        'The BETC significance statistic became undefined');
    if dPMid >= options.dAlpha
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
    dPval = 2*tcdf(-abs(dT),numel(vNetReturns)-1);
end
if ~isfinite(dPval)
    dPval = NaN;
end
end
