function rChars = fComputeMarketRegressionCharacteristics(mReturns, mME, ...
        mVolume, mClose, vMktRet)
% Compute market-regression characteristics once on the original full panel.
%
% MATLAB's multi-right-hand-side X\Y can differ at machine precision when Y
% is split into different column blocks. Keeping these fields in one call
% preserves the original serial numeric result while other asset-separable
% characteristics run in parallel.

chars = characteristics(mReturns,mME,mVolume,mClose,vMktRet);
[~, rChars.beta, rChars.ivol, rChars.iskew, mR2] = ...
    chars.fAlphaBetaSigma(vMktRet,365,0,250);
rChars.beta2 = rChars.beta.^2;
vMktRet = vMktRet(:);
mX = NaN(numel(vMktRet),3);
mX(:,1) = vMktRet;
if numel(vMktRet) >= 2
    mX(2:end,2) = vMktRet(1:end-1);
end
if numel(vMktRet) >= 3
    mX(3:end,3) = vMktRet(1:end-2);
end
% fAlphaBetaSigma returns [alpha,beta,sigma,iskew,R2]. The fourth output
% is residual skewness, so delay must use the fifth output from both fits.
[~,~,~,~,mR2lag] = chars.fAlphaBetaSigma(mX,365,0,250);
rChars.delay = NaN(size(mR2));
lDefinedDelay = isfinite(mR2) & isfinite(mR2lag) & mR2lag > 0;
rChars.delay(lDefinedDelay) = 1 - mR2(lDefinedDelay)./mR2lag(lDefinedDelay);
rChars.delay(~isfinite(rChars.delay)) = NaN;
end
