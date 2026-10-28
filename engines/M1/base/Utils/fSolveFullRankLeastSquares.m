function [vBeta,lIdentified,mInvXX,rDiagnostics] = ...
    fSolveFullRankLeastSquares(mX,vY)
% Scale-invariant full-rank least-squares solve.
%
% Raw cryptocurrency market capitalizations can be many orders of magnitude
% larger than the intercept and ranked characteristics.  Checking rank on the
% unscaled matrix and then calling backslash lets two different numerical
% tolerances decide identification.  Normalize every column, use one SVD for
% both decisions and the solve, and map coefficients/covariance back to the
% original economic units.

arguments
    mX (:,:) {mustBeNumeric}
    vY (:,1) {mustBeNumeric}
end

[iNumObs,iNumCoeff] = size(mX);
assert(iNumObs == numel(vY), ...
    'Regressor rows and outcome observations must agree');

vBeta = NaN(iNumCoeff,1);
mInvXX = NaN(iNumCoeff);
lIdentified = false;
rDiagnostics = struct('iRank',0,'dTolerance',NaN, ...
    'dConditionNumber',Inf,'vColumnScale',NaN(1,iNumCoeff));

if iNumCoeff == 0
    vBeta = zeros(0,1);
    mInvXX = zeros(0,0);
    lIdentified = true;
    rDiagnostics.iRank = 0;
    rDiagnostics.dConditionNumber = 1;
    rDiagnostics.vColumnScale = zeros(1,0);
    return
end
if iNumObs < iNumCoeff || any(~isfinite(mX),'all') || ...
        any(~isfinite(vY))
    return
end

vScale = vecnorm(mX,2,1);
rDiagnostics.vColumnScale = vScale;
if any(~isfinite(vScale) | vScale <= 0)
    return
end
mXScaled = mX ./ vScale;

[mU,mS,mV] = svd(mXScaled,0);
vSingular = diag(mS);
if numel(vSingular) < iNumCoeff || isempty(vSingular)
    return
end
dLargest = vSingular(1);
dTolerance = max(size(mXScaled)) * eps(dLargest);
iRank = nnz(vSingular > dTolerance);
rDiagnostics.iRank = iRank;
rDiagnostics.dTolerance = dTolerance;
if vSingular(end) > 0
    rDiagnostics.dConditionNumber = dLargest / vSingular(end);
end
if iRank < iNumCoeff
    return
end

vBetaScaled = mV * ((mU' * vY) ./ vSingular);
vBeta = vBetaScaled ./ vScale(:);

% (X'X)^-1 in original units.  This is needed only by callers requesting
% coefficient standard errors, but returning it here guarantees that the
% covariance uses the exact same identification tolerance as the estimate.
mInvScaledXX = (mV ./ (vSingular'.^2)) * mV';
mInvXX = mInvScaledXX ./ vScale(:) ./ vScale(:)';
lIdentified = all(isfinite(vBeta)) && all(isfinite(mInvXX),'all');
if ~lIdentified
    vBeta(:) = NaN;
    mInvXX(:) = NaN;
end
end
