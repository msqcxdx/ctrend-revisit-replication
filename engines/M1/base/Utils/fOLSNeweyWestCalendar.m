function rStats = fOLSNeweyWestCalendar(vY, mX)
% OLS and Newey-West inference without compressing missing calendar rows.
%
% Coefficients use the common finite observations.  HAC score products at
% lag L, however, are paired by their original row distance.  A missing
% week is therefore not silently turned into adjacency between the weeks on
% either side of the gap.

arguments
    vY (:,1) {mustBeNumeric}
    mX (:,:) {mustBeNumeric}
end

assert(size(mX,1) == numel(vY), ...
    'Dependent variable and regressors must have the same number of rows');

iNumCalendar = numel(vY);
iNumCoef = size(mX,2) + 1;
lValid = isfinite(vY) & all(isfinite(mX),2);
iNumObs = sum(lValid);

rStats.vBeta = NaN(iNumCoef,1);
rStats.vT = NaN(iNumCoef,1);
rStats.vP = NaN(iNumCoef,1);
rStats.vTHAC = NaN(iNumCoef,1);
rStats.vPHAC = NaN(iNumCoef,1);
rStats.mCov = NaN(iNumCoef);
rStats.mCovHAC = NaN(iNumCoef);
rStats.vResidual = NaN(iNumCalendar,1);
rStats.lValid = lValid;
rStats.iNumObs = iNumObs;
rStats.iNumLags = NaN;

% At least one residual degree of freedom and a uniquely identified design
% are required.  Do not use a pseudoinverse to manufacture coefficients.
if iNumObs <= iNumCoef
    return
end
mDesign = [ones(iNumObs,1), mX(lValid,:)];
if rank(mDesign) < iNumCoef
    return
end
mXX = mDesign' * mDesign;
if any(~isfinite(mXX),'all') || rcond(mXX) < 1e-12
    return
end

vYValid = vY(lValid);
vBeta = mDesign \ vYValid;
vResidual = vYValid - mDesign*vBeta;
if any(~isfinite(vBeta)) || any(~isfinite(vResidual))
    return
end
rStats.vBeta = vBeta;
rStats.vResidual(lValid) = vResidual;

iDfe = iNumObs - iNumCoef;
mBread = mXX \ eye(iNumCoef);
mBread = (mBread + mBread')/2;

% Conventional homoskedastic OLS inference.
dMSE = sum(vResidual.^2)/iDfe;
if isfinite(dMSE) && dMSE >= 0
    mCov = dMSE*mBread;
    mCov = (mCov + mCov')/2;
    rStats.mCov = mCov;
    [rStats.vT,rStats.vP] = iInference(vBeta, mCov, iDfe);
end

% Preserve the old pipeline's automatic bandwidth, but interpret every lag
% in rows of the original weekly calendar rather than in the compressed
% finite-observation sequence.
iNumLags = round(4*(iNumObs/100)^(2/9));
rStats.iNumLags = iNumLags;
mScore = zeros(iNumCalendar,iNumCoef);
mScore(lValid,:) = mDesign .* vResidual;
mMeat = mScore' * mScore;
iMaxLag = min(iNumLags, iNumCalendar-1);
for iLag = 1:iMaxLag
    mLagCross = mScore(1+iLag:end,:)' * ...
        mScore(1:end-iLag,:);
    dBartlett = 1 - iLag/(iNumLags+1);
    mMeat = mMeat + dBartlett*(mLagCross + mLagCross');
end
mCovHAC = mBread*mMeat*mBread;
mCovHAC = (mCovHAC + mCovHAC')/2;
if all(isfinite(mCovHAC),'all')
    rStats.mCovHAC = mCovHAC;
    [rStats.vTHAC,rStats.vPHAC] = ...
        iInference(vBeta, mCovHAC, iDfe);
end
end

function [vT,vP] = iInference(vBeta,mCov,iDfe)
vT = NaN(size(vBeta));
vP = NaN(size(vBeta));
vVariance = diag(mCov);
lDefined = isfinite(vBeta) & isfinite(vVariance) & vVariance > 0;
vT(lDefined) = vBeta(lDefined)./sqrt(vVariance(lDefined));
vP(lDefined) = 2*tcdf(-abs(vT(lDefined)),iDfe);
vT(~isfinite(vT)) = NaN;
vP(~isfinite(vP)) = NaN;
end
