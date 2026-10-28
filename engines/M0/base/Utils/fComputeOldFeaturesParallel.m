function rChars = fComputeOldFeaturesParallel(mReturns, mME, mVolume, ...
        mClose, vMktRet, mOpen, mHigh, mLow)
% Parallelize the published b02 formulas over independent asset columns.
%
% This is an execution-only adapter. Every formula, lookback, minimum-count
% convention, and output field is identical to the original b02 script.
% The five market-regression fields are deliberately recomputed once on the
% complete matrix so MATLAB follows the original multi-right-hand-side path.

iNumAssets = size(mClose,2);
pPool = gcp('nocreate');
if isempty(pPool)
    iNumChunks = min(12,iNumAssets);
else
    iNumChunks = min(pPool.NumWorkers,iNumAssets);
end
vChunk = ceil((1:iNumAssets) * iNumChunks / iNumAssets);
cAssetIdx = arrayfun(@(i) find(vChunk == i), ...
    (1:iNumChunks)','UniformOutput',false);

cReturns = cellfun(@(idx) mReturns(:,idx),cAssetIdx,'UniformOutput',false);
cME = cellfun(@(idx) mME(:,idx),cAssetIdx,'UniformOutput',false);
cVolume = cellfun(@(idx) mVolume(:,idx),cAssetIdx,'UniformOutput',false);
cClose = cellfun(@(idx) mClose(:,idx),cAssetIdx,'UniformOutput',false);
cOpen = cellfun(@(idx) mOpen(:,idx),cAssetIdx,'UniformOutput',false);
cHigh = cellfun(@(idx) mHigh(:,idx),cAssetIdx,'UniformOutput',false);
cLow = cellfun(@(idx) mLow(:,idx),cAssetIdx,'UniformOutput',false);

cCharacteristicChunks = cell(iNumChunks,1);
parfor iIdxChunk = 1:iNumChunks
    cCharacteristicChunks{iIdxChunk} = iComputeCharacteristicChunk( ...
        cReturns{iIdxChunk},cME{iIdxChunk},cVolume{iIdxChunk}, ...
        cClose{iIdxChunk},vMktRet);
end
rChars = iMergeChunks(cCharacteristicChunks);

% Preserve the original full-panel floating-point path for fields produced
% by fAlphaBetaSigma. Chunking its multiple RHS can alter last bits.
rMarket = iComputeMarketRegressionCharacteristics( ...
    mReturns,mME,mVolume,mClose,vMktRet);
cMarketFields = fieldnames(rMarket);
for iIdxF = 1:numel(cMarketFields)
    sField = cMarketFields{iIdxF};
    rChars.(sField) = rMarket.(sField);
end

cIndicatorChunks = cell(iNumChunks,1);
parfor iIdxChunk = 1:iNumChunks
    cIndicatorChunks{iIdxChunk} = iComputeIndicatorChunk( ...
        cClose{iIdxChunk},cOpen{iIdxChunk},cHigh{iIdxChunk}, ...
        cLow{iIdxChunk},cVolume{iIdxChunk});
end
rIndicators = iMergeChunks(cIndicatorChunks);
cIndicatorFields = fieldnames(rIndicators);
for iIdxF = 1:numel(cIndicatorFields)
    sField = cIndicatorFields{iIdxF};
    assert(~isfield(rChars,sField),'Duplicate old b02 field: %s',sField);
    rChars.(sField) = rIndicators.(sField);
end
end

function rChars = iComputeCharacteristicChunk(mReturns,mME,mVolume, ...
        mClose,vMktRet)
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
rChars.beta = NaN(size(mReturns));
rChars.beta2 = NaN(size(mReturns));
rChars.ivol = NaN(size(mReturns));
rChars.iskew = NaN(size(mReturns));
[rChars.retvol,rChars.skew1] = chars.fVolatility(7,0,5);
[~,rChars.skew2] = chars.fVolatility(365,0,250);
rChars.maxret = chars.fMaxRet(7,0,1);
rChars.delay = NaN(size(mReturns));
[rChars.var90d,rChars.es90d] = chars.fVaR(90,0,20,0.05);
rChars.ppt = chars.fProspectTheory(365,0,250);
rChars.stv = chars.fSalienceTheory(21,0,14);
end

function rChars = iComputeMarketRegressionCharacteristics(mReturns,mME, ...
        mVolume,mClose,vMktRet)
chars = characteristics(mReturns,mME,mVolume,mClose,vMktRet);
[~,rChars.beta,rChars.ivol,rChars.iskew,mR2] = ...
    chars.fAlphaBetaSigma(vMktRet,365,0,250);
rChars.beta2 = rChars.beta.^2;
mX = lagmatrix(vMktRet,[0,1,2]);
[~,~,~,mR2lag] = chars.fAlphaBetaSigma(mX,365,0,250);
rChars.delay = 1 - (mR2./mR2lag);
end

function rChars = iComputeIndicatorChunk(mClose,mOpen,mHigh,mLow,mVolume)
indicators = technical_indicators(mClose,mOpen,mHigh,mLow,mVolume);
rChars = struct();
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
rChars.macd_diff_signal = rChars.macd - macdSignal;
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
rChars.volmacd_diff_signal = rChars.volmacd - volmacdSignal;
rChars.chaikin = indicators.fChaikinMoneyFlow(21,10);
[bollLow,bollMid,bollHigh] = indicators.fBollingerBands();
rChars.boll_low = bollLow./indicators.mClose;
rChars.boll_mid = bollMid./indicators.mClose;
rChars.boll_high = bollHigh./indicators.mClose;
rChars.boll_width = (bollHigh-bollLow)./bollMid;
end

function rMerged = iMergeChunks(cChunks)
cFields = fieldnames(cChunks{1});
rMerged = struct();
for iIdxC = 2:numel(cChunks)
    assert(isequal(fieldnames(cChunks{iIdxC}),cFields), ...
        'Old b02 parallel chunks returned different fields');
end
for iIdxF = 1:numel(cFields)
    sField = cFields{iIdxF};
    cParts = cellfun(@(r) r.(sField),cChunks,'UniformOutput',false);
    rMerged.(sField) = cat(2,cParts{:});
end
end
