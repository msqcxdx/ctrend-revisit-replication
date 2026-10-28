% CTREND_REVISIT_FILE_PURPOSE: Prove the parallel b02 feature computation is bitwise equal to the serial implementation.
function test_b02_parallel_equivalence(codeDir)
% Deterministically prove that the old b02 parallel adapter changes no value.

arguments
    codeDir (1,:) char
end
addpath(fullfile(codeDir,'Utils'));
rng(20260807,'twister');
iNumObs = 730;
iNumAssets = 7;
mReturns = 0.02 .* randn(iNumObs,iNumAssets);
mME = 1e6 + 1e8 .* rand(iNumObs,iNumAssets);
mVolume = 1e3 + 1e6 .* rand(iNumObs,iNumAssets);
mClose = exp(2 + 0.01 .* cumsum(randn(iNumObs,iNumAssets),1));
mOpen = mClose .* (1 + 0.002 .* randn(iNumObs,iNumAssets));
mHigh = max(mOpen,mClose) .* (1 + 0.003 .* rand(iNumObs,iNumAssets));
mLow = min(mOpen,mClose) .* (1 - 0.003 .* rand(iNumObs,iNumAssets));
lMissing = rand(iNumObs,iNumAssets) < 0.002;
mReturns(lMissing) = NaN;
mME(lMissing) = NaN;
mVolume(lMissing) = NaN;
mClose(lMissing) = NaN;
mOpen(lMissing) = NaN;
mHigh(lMissing) = NaN;
mLow(lMissing) = NaN;
mME_L1 = [NaN(1,iNumAssets);mME(1:end-1,:)];
mWts = mME_L1 ./ sum(mME_L1,2,'omitmissing');
vMktRet = sum(mReturns .* mWts,2,'omitnan');
vMktRet(all(isnan(mWts),2)) = NaN;

rExpected = iComputePublishedSerial(mReturns,mME,mVolume,mClose, ...
    vMktRet,mOpen,mHigh,mLow);
rActual = fComputeOldFeaturesParallel(mReturns,mME,mVolume,mClose, ...
    vMktRet,mOpen,mHigh,mLow);
assert(isequal(fieldnames(rExpected),fieldnames(rActual)), ...
    'Old b02 parallel adapter changed the output field order');
cFields = fieldnames(rExpected);
for iIdxF = 1:numel(cFields)
    sField = cFields{iIdxF};
    assert(isequaln(rExpected.(sField),rActual.(sField)), ...
        'Old b02 parallel adapter changed field %s',sField);
end
fprintf('OLD_B02_PARALLEL_EQUIVALENCE_OK fields=%d assets=%d observations=%d\n', ...
    numel(cFields),iNumAssets,iNumObs);
end

function rChars = iComputePublishedSerial(mReturns,mME,mVolume,mClose, ...
        vMktRet,mOpen,mHigh,mLow)
chars = characteristics(mReturns,mME,mVolume,mClose,vMktRet);
rChars = struct();
rChars.mcap = chars.fMarketCap(true);
rChars.prc = chars.fPrice();
rChars.maxdprc = chars.fMaxPrc(7);
rChars.ret_1_0 = chars.fMomentum(7,0);
rChars.ret_2_0 = chars.fMomentum(14,0);
rChars.ret_3_0 = chars.fMomentum(21,0);
rChars.ret_4_0 = chars.fMomentum(28,0);
rChars.ret_4_1 = chars.fMomentum(28,7);
rChars.prcvol = chars.fPrcVolumeLiu(7,0,1,true,true);
rChars.volscaled = chars.fPrcVolumeLiu(7,0,1,false,true);
rChars.volscaled = rChars.volscaled ./ chars.mME;
[~,rChars.stdprcvol] = chars.fPrcVolumeLiu(7,0,5,true,true);
rChars.age = chars.fAge();
rChars.ret_8_0 = chars.fMomentum(7*8,0);
rChars.ret_16_0 = chars.fMomentum(7*16,0);
rChars.ret_50_0 = chars.fMomentum(7*50,0);
rChars.ret_100_0 = chars.fMomentum(7*100,0);
rChars.volume = chars.fAvgVolume(7,0,1,true);
rChars.illiq = chars.fAmihud(7,0,5);
[~,rChars.beta,ivol,iskew,mR2] = ...
    chars.fAlphaBetaSigma(vMktRet,365,0,250);
rChars.beta2 = rChars.beta.^2;
rChars.ivol = ivol;
rChars.iskew = iskew;
[rChars.retvol,rChars.skew1] = chars.fVolatility(7,0,5);
[~,rChars.skew2] = chars.fVolatility(365,0,250);
rChars.maxret = chars.fMaxRet(7,0,1);
mX = lagmatrix(vMktRet,[0,1,2]);
[~,~,~,mR2lag] = chars.fAlphaBetaSigma(mX,365,0,250);
rChars.delay = 1 - (mR2./mR2lag);
[rChars.var90d,rChars.es90d] = chars.fVaR(90,0,20,0.05);
rChars.ppt = chars.fProspectTheory(365,0,250);
rChars.stv = chars.fSalienceTheory(21,0,14);

indicators = technical_indicators(mClose,mOpen,mHigh,mLow,mVolume);
rChars.rsi = indicators.fRelativeStrengthIndex();
rChars.stochRSI = indicators.fStochasticRSI(14,5);
[rChars.stochK,rChars.stochD] = ...
    indicators.fStochasticOscillator(14,3,14);
rChars.cci = indicators.fCCI('iMinNumObs',10);
vLagLength = [3,5,10,20,50,100,200];
for iIdxL = 1:numel(vLagLength)
    iWindowSize = vLagLength(iIdxL);
    sWindowSize = num2str(iWindowSize);
    rChars.(['sma_',sWindowSize,'d']) = ...
        indicators.fSimpleMovingAverage(mClose,iWindowSize)./mClose;
end
[rChars.macd,macdSignal] = indicators.fPercentagePriceOscillator();
rChars.macd_diff_signal = rChars.macd-macdSignal;
mVolTemp = mVolume;
mVolTemp(mVolTemp == 0) = NaN;
for iIdxL = 1:numel(vLagLength)
    iWindowSize = vLagLength(iIdxL);
    sWindowSize = num2str(iWindowSize);
    rChars.(['volsma_',sWindowSize,'d']) = ...
        indicators.fSimpleMovingAverage(mVolume,iWindowSize)./mVolTemp;
end
[rChars.volmacd,volmacdSignal] = ...
    indicators.fPercentageVolumeOscillator();
rChars.volmacd_diff_signal = rChars.volmacd-volmacdSignal;
rChars.chaikin = indicators.fChaikinMoneyFlow(21,10);
[bollLow,bollMid,bollHigh] = indicators.fBollingerBands();
rChars.boll_low = bollLow./indicators.mClose;
rChars.boll_mid = bollMid./indicators.mClose;
rChars.boll_high = bollHigh./indicators.mClose;
rChars.boll_width = (bollHigh-bollLow)./bollMid;
end
