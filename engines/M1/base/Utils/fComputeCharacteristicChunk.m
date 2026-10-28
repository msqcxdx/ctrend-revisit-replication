function rChars = fComputeCharacteristicChunk(mReturns, mME, mVolume, ...
        mClose, vMktRet, options)
% Compute the unchanged daily characteristic formulas for one asset chunk.

arguments
    mReturns (:,:) {mustBeNumeric}
    mME (:,:) {mustBeNumeric}
    mVolume (:,:) {mustBeNumeric}
    mClose (:,:) {mustBeNumeric}
    vMktRet (:,:) {mustBeNumeric}
    options.lComputeMarketRegressions (1,1) logical = true
end

chars = characteristics(mReturns, mME, mVolume, mClose, vMktRet);
rChars = struct();

rChars.mcap = iWeeklyMeanMarketCap(mME);
rChars.prc = chars.fPrice();
rChars.maxdprc = chars.fMaxPrc(7);
rChars.age = chars.fAge();

rChars.ret_1_0 = chars.fMomentum(7, 0);
rChars.ret_2_0 = chars.fMomentum(14, 0);
rChars.ret_3_0 = chars.fMomentum(21, 0);
rChars.ret_4_0 = chars.fMomentum(28, 0);
rChars.ret_4_1 = chars.fMomentum(28, 7);
rChars.ret_8_0 = chars.fMomentum(7 * 8, 0);
rChars.ret_16_0 = chars.fMomentum(7 * 16, 0);
rChars.ret_50_0 = chars.fMomentum(7 * 50, 0);
rChars.ret_100_0 = chars.fMomentum(7 * 100, 0);

rChars.prcvol = chars.fPrcVolumeLiu(7, 0, 1, false, true);
rChars.volscaled = chars.fPrcVolumeLiu(7, 0, 1, false, true);
rChars.volscaled = rChars.volscaled ./ chars.mME;
[~, rChars.stdprcvol] = chars.fPrcVolumeLiu(30, 0, 5, false, true);
rChars.volume = chars.fAvgVolume(7, 0, 1, false, false);
rChars.illiq = chars.fAmihud(7, 0, 5);

if options.lComputeMarketRegressions
    rMarket = fComputeMarketRegressionCharacteristics( ...
        mReturns,mME,mVolume,mClose,vMktRet);
    rChars.beta = rMarket.beta;
    rChars.ivol = rMarket.ivol;
    rChars.iskew = rMarket.iskew;
    rChars.beta2 = rMarket.beta2;
else
    % Preserve field order and dimensions. Production overwrites these with
    % one full-matrix calculation after parallel chunk merging. Repeating
    % X\Y separately by chunk changes a few last floating-point bits.
    rChars.beta = NaN(size(mReturns));
    rChars.ivol = NaN(size(mReturns));
    rChars.iskew = NaN(size(mReturns));
    rChars.beta2 = NaN(size(mReturns));
end
[rChars.retvol, rChars.skew1] = chars.fVolatility(7, 0, 5);
[~, rChars.skew2] = chars.fVolatility(365, 0, 250);
rChars.maxret = chars.fMaxRet(7, 0, 1);
if options.lComputeMarketRegressions
    rChars.delay = rMarket.delay;
else
    rChars.delay = NaN(size(mReturns));
end

[rChars.var90d, rChars.es90d] = chars.fVaR(90, 0, 20, 0.05);
rChars.ptv = chars.fProspectTheory(365, 0, 250);
rChars.stv = chars.fSalienceTheory(365, 0, 250);
end

function mMcap = iWeeklyMeanMarketCap(mME)
% Table B.1 defines mcap as mean market capitalization during the previous
% week. Keep the old missing-data convention used for weekly volume
% characteristics: at least one finite daily observation in the seven-day
% window. Keep the characteristic in the paper's raw-dollar unit.

[iNumObs, iNumAssets] = size(mME);
mMcap = NaN(iNumObs, iNumAssets);
for iIdxT = 7:iNumObs
    mTemp = mME(iIdxT-6:iIdxT,:);
    lValid = any(isfinite(mTemp),1);
    if any(lValid)
        vMean = mean(mTemp(:,lValid),1,'omitmissing');
        vMean(~isfinite(vMean) | vMean <= 0) = NaN;
        mMcap(iIdxT,lValid) = vMean;
    end
end
end
