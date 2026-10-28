function rChars = fComputeTechnicalIndicatorChunk(mClose, mOpen, mHigh, ...
        mLow, mVolume)
% Compute the unchanged technical-indicator formulas for one asset chunk.

indicators = technical_indicators(mClose, mOpen, mHigh, mLow, mVolume);
rChars = struct();

rChars.rsi = indicators.fRelativeStrengthIndex();
rChars.stochRSI = indicators.fStochasticRSI(14, 14);
[rChars.stochK, rChars.stochD] = ...
    indicators.fStochasticOscillator(14, 3, 14);
rChars.cci = indicators.fCCI('iWindowSize', 20, 'iMinNumObs', 20);

vLagLength = [3, 5, 10, 20, 50, 100, 200];
for iIdxL = 1:numel(vLagLength)
    iWindowSize = vLagLength(iIdxL);
    sWindowSize = num2str(iWindowSize);
    rChars.(['sma_', sWindowSize, 'd']) = ...
        indicators.fSimpleMovingAverage(mClose, iWindowSize) ./ mClose;
end

[rChars.macd, macdSignal] = indicators.fPercentagePriceOscillator();
rChars.macd_diff_signal = rChars.macd - macdSignal;

mVolTemp = mVolume;
mVolTemp(mVolTemp == 0) = NaN;
for iIdxL = 1:numel(vLagLength)
    iWindowSize = vLagLength(iIdxL);
    sWindowSize = num2str(iWindowSize);
    rChars.(['volsma_', sWindowSize, 'd']) = ...
        indicators.fSimpleMovingAverage(mVolume, iWindowSize) ./ mVolTemp;
end

[rChars.volmacd, volmacdSignal] = ...
    indicators.fPercentageVolumeOscillator();
rChars.volmacd_diff_signal = rChars.volmacd - volmacdSignal;
rChars.chaikin = indicators.fChaikinMoneyFlow(21, 21);

[bollLow, bollMid, bollHigh] = indicators.fBollingerBands();
rChars.boll_low = bollLow ./ indicators.mClose;
rChars.boll_mid = bollMid ./ indicators.mClose;
rChars.boll_high = bollHigh ./ indicators.mClose;
rChars.boll_width = (bollHigh - bollLow) ./ bollMid;
end
