function [vAICc, lDefined, vNumParameters] = ...
        fCorrectedAICc(vMSE, vDF, iNumObs, lEstAlpha)
% Calculate AICc with an explicit, finite parameter-count convention.
%
% MATLAB's lasso FitInfo.DF counts nonzero predictor coefficients but does
% not count the separately stored intercept.  The corrected pipeline uses
% k = DF + 1 when an intercept is fitted and
%
%   AICc = n*log(MSE) + 2*k*n/(n-k-1).
%
% A candidate is defined only for a finite positive MSE, a finite
% nonnegative integer parameter count, and a strictly positive correction
% denominator.  Undefined or nonfinite values remain NaN and therefore
% cannot be selected as an apparent optimum.

arguments
    vMSE {mustBeNumeric}
    vDF {mustBeNumeric}
    iNumObs (1,1) {mustBeNumeric, mustBeInteger, mustBePositive}
    lEstAlpha (1,1) {mustBeNumericOrLogical} = true
end

assert(isequal(size(vMSE),size(vDF)), ...
    'MSE and degrees-of-freedom arrays must have identical dimensions');

vNumParameters = vDF + double(logical(lEstAlpha));
vDenominator = iNumObs - vNumParameters - 1;
lDefined = isfinite(vMSE) & vMSE > 0 & ...
    isfinite(vNumParameters) & vNumParameters >= 0 & ...
    vNumParameters == fix(vNumParameters) & vDenominator > 0;

vAICc = NaN(size(vMSE));
vAICc(lDefined) = iNumObs .* log(vMSE(lDefined)) + ...
    2 .* vNumParameters(lDefined) .* iNumObs ./ vDenominator(lDefined);

% Guard against arithmetic overflow even when all inputs passed the
% element-wise domain checks above.
lDefined = lDefined & isfinite(vAICc);
vAICc(~lDefined) = NaN;
end
