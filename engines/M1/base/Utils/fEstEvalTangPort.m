function [dReturn,vWts] = fEstEvalTangPort(mY,vYout,dScale)
% Estimate a tangency portfolio on one fixed calendar window and apply it.

arguments
    mY (:,:) {mustBeNumeric}
    vYout (1,:) {mustBeNumeric}
    dScale (1,1) {mustBeNumeric} = NaN
end

iNumAssets = size(mY,2);
dReturn = NaN;
vWts = NaN(iNumAssets,1);
if iNumAssets == 0 || size(mY,1) < 2 || ...
        numel(vYout) ~= iNumAssets || ...
        any(~isfinite(mY),'all') || any(~isfinite(vYout),'all')
    return
end

% The unrestricted tangency weights require an identified, positive-definite
% covariance system. A pseudoinverse would silently select an arbitrary
% portfolio when the frontier is not identified.
S = cov(mY);
mu = mean(mY,1)';
if any(~isfinite(S),'all') || any(~isfinite(mu)) || ...
        rank(S) < iNumAssets || rcond(S) < 1e-12
    return
end
vDirection = S \ mu;
% Factor returns are zero-cost spreads: a sum-to-one budget is not an
% economic constraint. Dividing by a negative exposure sum reverses the
% maximum-Sharpe direction before the volatility normalization below.
vWts = vDirection;

dVariance = vWts' * S * vWts;
if ~isfinite(dVariance) || dVariance <= 0
    vWts(:) = NaN;
    return
end
if isfinite(dScale)
    if dScale <= 0
        vWts(:) = NaN;
        return
    end
    vWts = vWts * (dScale/sqrt(dVariance));
elseif ~isnan(dScale)
    vWts(:) = NaN;
    return
end

dReturn = vYout * vWts;
if ~isfinite(dReturn)
    dReturn = NaN;
end
end
