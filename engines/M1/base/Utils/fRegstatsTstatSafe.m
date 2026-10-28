function [vBeta, vTstat, vResid] = fRegstatsTstatSafe(vY, mX)
% Run regstats after explicit missing-value and degrees-of-freedom checks.

arguments
    vY (:,1) {mustBeNumeric}
    mX (:,:) {mustBeNumeric}
end

iNumCoeff = size(mX, 2) + 1;
vBeta = NaN(iNumCoeff, 1);
vTstat = NaN(iNumCoeff, 1);
vResid = NaN(size(vY));

lValid = isfinite(vY) & all(isfinite(mX), 2);
if sum(lValid) <= iNumCoeff
    return
end

mDesign = [ones(sum(lValid),1), mX(lValid,:)];
if rank(mDesign) < iNumCoeff
    return
end

% The expected non-identification cases have already been handled above.
% Any remaining regstats exception is a software, toolbox/license, or input
% contract failure and must remain visible rather than masquerading as an
% undefined statistic.
rRegResults = regstats(vY(lValid), mX(lValid,:), 'linear', {'tstat','r'});
vBeta = rRegResults.tstat.beta;
vTstat = rRegResults.tstat.t;
vResid(lValid) = rRegResults.r;
end
