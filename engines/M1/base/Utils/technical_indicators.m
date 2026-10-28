classdef technical_indicators

    properties
        mClose (:,:) {mustBeNumeric}
        mOpen  (:,:) {mustBeNumeric}
        mHigh  (:,:) {mustBeNumeric}
        mLow   (:,:) {mustBeNumeric}
        mVolume (:,:) {mustBeNumeric}
        iNumAssets (1,1) {mustBeNumeric}
        iNumObs (1,1) {mustBeNumeric}
    end

    methods
        function self = technical_indicators(mClose, mOpen, mHigh, mLow, mVolume)
            % Error checking
            assert(size(mClose, 1) == size(mOpen,1),...
                sprintf('Number of rows in mClose and mOpen must agree (%i ~= %i)',...
                size(mClose, 1), size(mOpen,1)));

            assert(size(mClose, 2) == size(mOpen,2),...
                sprintf('Number of columns in mClose and mOpen must agree (%i ~= %i)',...
                size(mClose, 2), size(mOpen,2)));

            assert(size(mClose, 1) == size(mHigh,1),...
                sprintf('Number of rows in mClose and mHigh must agree (%i ~= %i)',...
                size(mClose, 1), size(mHigh,1)));

            assert(size(mClose, 2) == size(mHigh,2),...
                sprintf('Number of columns in mClose and mHigh must agree (%i ~= %i)',...
                size(mClose, 2), size(mHigh,2)));

            assert(size(mClose, 1) == size(mLow,1),...
                sprintf('Number of rows in mClose and mLow must agree (%i ~= %i)',...
                size(mClose, 1), size(mLow,1)));

            assert(size(mClose, 2) == size(mLow,2),...
                sprintf('Number of columns in mClose and mLow must agree (%i ~= %i)',...
                size(mClose, 2), size(mLow,2)));

            assert(size(mClose, 1) == size(mVolume,1),...
                sprintf('Number of rows in mClose and mVolume must agree (%i ~= %i)',...
                size(mClose, 1), size(mVolume,1)));

            assert(size(mClose, 2) == size(mVolume,2),...
                sprintf('Number of columns in mClose and mVolume must agree (%i ~= %i)',...
                size(mClose, 2), size(mVolume,2)));

            % Set properties
            self.mClose     = mClose;
            self.mOpen      = mOpen;
            self.mHigh      = mHigh;
            self.mLow       = mLow;
            self.mVolume    = mVolume;
            self.iNumAssets = size(mClose, 2);
            self.iNumObs    = size(mClose, 1);
        end

        % === HELPER FUNCTIONS
        function mMedPrice = fMedianPrice(self)
            % Function for calculating the median daily price

            % Check inputs
            arguments
                self
            end

            % Get median price
            mMedPrice = (self.mHigh + self.mLow)/2;
            mMedPrice(~isfinite(self.mHigh) | ~isfinite(self.mLow)) = NaN;
        end

        function mSMA = fSimpleMovingAverage(self, mData, iWindowSize)
            % Function for calculating the simple moving average of a
            % series
            %
            % Input:
            %   mData:          T x N data matrix
            %                   T: number of time-series observations
            %                   N: number of assets
            %   iWindowSize:    Scalar, integer, window size
            %                   (default = 14)
            %
            % Output:
            %   mSMA:           T x N matrix of moving averages of data
            %                   matrix
            %                   T: number of time-series observations
            %                   N: number of assets

            % Check input arguments
            arguments
                self
                mData (:,:) {mustBeNumeric}
                iWindowSize (1,1) {mustBeNumeric} = 14
            end

            % Determine dimensions
            [iNumObs, iNumAssets] = size(mData);

            % A k-day moving average is defined only when the complete
            % k-day calendar window is observed.  In particular, do not
            % turn a short history (or observations on either side of an
            % internal data gap) into a nominally long-horizon signal.
            mSMA = NaN(iNumObs, iNumAssets);
            for iIdxT = iWindowSize:iNumObs
                vIdxInSample = (iIdxT-iWindowSize+1):iIdxT;
                mDataTemp    = mData(vIdxInSample, :);
                lComplete    = all(isfinite(mDataTemp), 1);
                mSMA(iIdxT, lComplete) = mean(mDataTemp(:, lComplete), 1);
            end
        end

        function mEMA = fExponentialMovingAverage(self, mData, iWindowSize, dSmoothing)
            % Function for calculating the exponential moving average
            %
            % Input:
            %   mData:          T x N data matrix
            %                   T: number of time-series observations
            %                   N: number of assets
            %   iWindowSize:    Scalar, integer, length of formation period
            %                   (default = 14)
            %   dSmoothing:     Scalar, double, smoothing parameter
            %                   (default = 2)
            %
            % Output:
            %   mEMA:           T x N matrix of exponential moving averages
            %                   of input data matrix
            %                   T: number of time-series observations
            %                   N: number of assets

            % Check input arguments
            arguments
                self
                mData (:,:) {mustBeNumeric}
                iWindowSize (1,1) {mustBeNumeric} = 14
                dSmoothing (1,1) {mustBeNumeric} = 1
            end

            % Determine dimensions
            [iNumObs, iNumAssets] = size(mData);

            % Get smooting factor
            dSmoothing  = dSmoothing./(1 + iWindowSize);

            % Supplementary Appendix A.1 specifies alpha=1/(1+L) and says
            % that, when EMA_{t-1} is unavailable, the recursion is
            % initialized with X_{t-1}. A gap therefore invalidates the EMA
            % at the gap and first resumed observation; two consecutive
            % finite observations restart it without inventing a value.
            mEMA = NaN(iNumObs, iNumAssets);
            for iIdxT = 2:iNumObs
                vCurrent = mData(iIdxT, :);
                vPreviousData = mData(iIdxT-1, :);
                vPreviousEMA = mEMA(iIdxT-1, :);
                lCurrentValid = isfinite(vCurrent);
                lContinue = lCurrentValid & isfinite(vPreviousEMA);
                lInitialize = lCurrentValid & ~lContinue & ...
                    isfinite(vPreviousData);
                vState = vPreviousEMA;
                vState(lInitialize) = vPreviousData(lInitialize);
                lCanCompute = lContinue | lInitialize;
                mEMA(iIdxT, lCanCompute) = ...
                    vCurrent(lCanCompute) * dSmoothing + ...
                    vState(lCanCompute) .* (1 - dSmoothing);
            end
        end

        function mLowestLow = fLowestLow(self, mData, iWindowSize, iMinNumObs)
            % Function for calculating the lowest low in a given window
            %
            % Input:
            %   self:               Object, containing high, open, 
            %                       low, close, and volume
            %   mData:              T x N matrix of data
            %   iWindowSize:        Scalar, integer, window size
            %                       (default = 14)

            % Check input arguments
            arguments
                self
                mData (:,:) {mustBeNumeric}
                iWindowSize (1,1) {mustBeNumeric} = 14
                iMinNumObs (1,1) {mustBeNumeric} = iWindowSize 
            end

            % iMinNumObs deliberately permits a partially observed window
            % for callers that request it.  It never permits filling the
            % current observation itself.
            [iNumObs, iNumAssets] = size(mData);
            mLowestLow = NaN(iNumObs, iNumAssets);
            for iIdxT = iWindowSize:iNumObs
                % Get in-sample data
                vIdxInSample = (iIdxT-iWindowSize+1):iIdxT;
                mDataTemp    = mData(vIdxInSample, :);

                lCanCompute = isfinite(mDataTemp(end,:)) & ...
                    sum(isfinite(mDataTemp), 1) >= iMinNumObs;
                mDataTemp(~isfinite(mDataTemp)) = NaN;
                if any(lCanCompute)
                    mLowestLow(iIdxT, lCanCompute) = ...
                        min(mDataTemp(:,lCanCompute), [], 1, 'omitmissing');
                end
            end
        end

        function mHighestHigh = fHighestHigh(self, mData, iWindowSize, iMinNumObs)
            % Function for calculating the highest high in a given window
            %
            % Input:
            %   self:               Object, containing high, open, 
            %                       low, close, and volume
            %   mData:              T x N matrix of data
            %   iWindowSize:        Scalar, integer, window size
            %                       (default = 14)

            % Check input arguments
            arguments
                self
                mData (:,:) {mustBeNumeric}
                iWindowSize (1,1) {mustBeNumeric} = 14
                iMinNumObs (1,1) {mustBeNumeric} = iWindowSize 
            end

            % iMinNumObs deliberately permits a partially observed window
            % for callers that request it.  It never permits filling the
            % current observation itself.
            [iNumObs, iNumAssets] = size(mData);
            mHighestHigh = NaN(iNumObs, iNumAssets);
            for iIdxT = iWindowSize:iNumObs
                % Get in-sample data
                vIdxInSample = (iIdxT-iWindowSize+1):iIdxT;
                mDataTemp    = mData(vIdxInSample, :);

                lCanCompute = isfinite(mDataTemp(end,:)) & ...
                    sum(isfinite(mDataTemp), 1) >= iMinNumObs;
                mDataTemp(~isfinite(mDataTemp)) = NaN;
                if any(lCanCompute)
                    mHighestHigh(iIdxT, lCanCompute) = ...
                        max(mDataTemp(:,lCanCompute), [], 1, 'omitmissing');
                end
            end
        end

        function mCMF = fChaikinMoneyFlow(self, iWindowSize, iMinNumObs)

            % Check input arguments
            arguments
                self
                iWindowSize (1,1) {mustBeNumeric} = 21
                iMinNumObs (1,1) {mustBeNumeric} = iWindowSize 
            end

            % Initialize memory
            mCMF = NaN(self.iNumObs, self.iNumAssets);

            for iIdxT = iWindowSize:self.iNumObs
                % Get in-sample data
                vIdxInSample    = (iIdxT-iWindowSize+1):iIdxT;
                mCloseTemp      = self.mClose(vIdxInSample, :);
                mLowTemp        = self.mLow(vIdxInSample, :);
                mHighTemp       = self.mHigh(vIdxInSample, :);
                mVolTemp        = self.mVolume(vIdxInSample, :);

                % A row contributes only if every field required by CMF is
                % finite and the high-low range is positive.
                lValid = isfinite(mCloseTemp) & isfinite(mLowTemp) & ...
                    isfinite(mHighTemp) & isfinite(mVolTemp) & ...
                    (mHighTemp > mLowTemp);
                lCanCompute = lValid(end,:) & ...
                    sum(lValid, 1) >= iMinNumObs;
               
                % Match missing data
                mCloseTemp(~lValid) = NaN;
                mLowTemp(~lValid)   = NaN;
                mHighTemp(~lValid)  = NaN;
                mVolTemp(~lValid)   = NaN;

                % Subtract low and high from close
                mCloseMinusLow  = mCloseTemp - mLowTemp;
                mHighMinusClose = mHighTemp - mCloseTemp;

                % Price range
                mPriceRange     = mHighTemp - mLowTemp;
                mPriceRange(mPriceRange <= 0) = NaN;

                % Calculate AD
                mAD = (mCloseMinusLow - mHighMinusClose)./mPriceRange;
                mAD = mAD .* mVolTemp;

                % Sum of AD and volume
                vSumAD  = sum(mAD, 1, 'omitmissing');
                vSumVOL = sum(mVolTemp,1, 'omitmissing');
                lCanCompute = lCanCompute & isfinite(vSumAD) & ...
                    isfinite(vSumVOL) & vSumVOL > 0;
                mCMF(iIdxT,lCanCompute) = ...
                    vSumAD(lCanCompute)./vSumVOL(lCanCompute);
            end
        end

        function mTrueRange = fTrueRange(self)
            % Function for calculating the true range

            % Check input arguments
            arguments
                self
%                 iWindowSize (1,1) {mustBeNumeric} = 14
            end

            % Calculate the true range
%             mTR = self.fTrueRange();

            % Calculate difference between high and low (+DM)
            mPriceRangeHL = self.mHigh - self.mLow;

            % Calculate difference between current high and previous close
            % (-DM)
            mPriceRangeHC = self.mHigh - [NaN(1, self.iNumAssets); self.mClose(1:end-1,:)];

            % Calculate difference between current high and previous close
            mPriceRangeLC = [NaN(1, self.iNumAssets); self.mClose(1:end-1,:)] - self.mLow;

            % Find the highest price range
            mTrueRange = NaN(self.iNumObs, self.iNumAssets);
            lValidFirst = isfinite(self.mHigh(1,:)) & isfinite(self.mLow(1,:));
            mTrueRange(1,lValidFirst) = mPriceRangeHL(1,lValidFirst);
            for iIdxT = 2:self.iNumObs
                % Get in-sample data
                mDataTemp = [mPriceRangeHL(iIdxT,:);...
                    mPriceRangeHC(iIdxT,:);...
                    mPriceRangeLC(iIdxT,:)];

                lValid = all(isfinite(mDataTemp), 1);
                if any(lValid)
                    mTrueRange(iIdxT,lValid) = max(mDataTemp(:,lValid), [], 1);
                end
            end
        end

        % === TECHNICAL INDICATORS
        function mADL = fAccDistOscillator(self)

        % Check input arguments
            arguments
                self
            end

            % Calculate money flow multiplier [ -1, +1]
            mMFM = ((self.mClose - self.mLow) - (self.mHigh - self.mClose))./...
                (self.mHigh - self.mLow);

            % Calculate money flow volume
            mMFV = mMFM .* self.mVolume;
            mMFV(~isfinite(mMFV)) = NaN;

            % A missing money-flow observation makes the cumulative level
            % unobservable from that point onward; do not carry the last
            % value across the gap.
            mADL = cumsum(mMFV, 1, 'includemissing');
        end

        function mADX = fAverageDirectionalMovementIndex(self, iWindowSize)

            % Calculate down move and up move
            mUpMove     = self.mHigh - [NaN(1, self.iNumAssets); self.mHigh(1:end-1,:)];
            mDownMove   = [NaN(1, self.iNumAssets); self.mLow(1:end-1,:)] - self.mLow;

            % Calculate DM+ and DM-
            mDMplus     = max(0, mUpMove,   'includenan');
            mDMminus    = max(0, mDownMove, 'includenan');

            % Set DM+ to zero if down move was larger and set DM- to zero
            % if up move was larger
            mDMplus(mUpMove < mDownMove)    = 0;
            mDMminus(mDownMove < mUpMove)   = 0;

            % Calculate directional movement index DI+ and DI-
            mATR = self.fAverageTrueRange(iWindowSize);
            mDIplus = (self.fExponentialMovingAverage(mDMplus, iWindowSize)./...
                mATR);
            mDIminus = (self.fExponentialMovingAverage(mDMminus, iWindowSize)./...
                mATR);
            
            mADX = [];


        end

        function mATR = fAverageTrueRange(self, iWindowSize)
            % Function for calculating the average true range
            %
            % Input:
            %   self:               Object, containing high, open, 
            %                       low, close, and volume
            %   iWindowSize:        Scalar, integer, window size of
            %                       moving average (default = 14)

            % Check input arguments
            arguments
                self
                iWindowSize (1,1) {mustBeNumeric} = 14
            end

            % Calculate true range
            mTR = self.fTrueRange();

            % Calculate moving average of true range
            mATR = self.fSimpleMovingAverage(mTR, iWindowSize);
        end


        function mAO = fAwesomeOscillatorIndicator(self, iWindowSizeFast, iWindowSizeSlow)
            % Function for calculating the Awesome Oscillator Indicator,
            % i.e., the difference of a fast and slow moving average
            %
            % Input:
            %   self:               Object, containing high, open, 
            %                       low, close, and volume
            %   iWindowSizeFast:    Scalar, integer, window size of fast
            %                       moving average (default = 5)
            %   iWindowSizeSlow:    Scalar, integer, window size of slow
            %                       moving average (default = 34)
            %
            % Output:
            %   mAO:                

            % Check inputs
            arguments
                self 
                iWindowSizeFast (1,1) {mustBeNumeric} = 5
                iWindowSizeSlow (1,1) {mustBeNumeric} = 34
            end

            % Check inputs
            assert(iWindowSizeFast < iWindowSizeSlow, ['Length of fast MA must be lower' ...
                'than length of slow MA']);

            % Calculate median price
            mMedPrice = self.fMedianPrice();

            % Calculate slow and fast moving averages of median price
            mSlowMA = self.fSimpleMovingAverage(mMedPrice, iWindowSizeSlow);
            mFastMA = self.fSimpleMovingAverage(mMedPrice, iWindowSizeFast);

            % Calculate difference
            mAO = mFastMA - mSlowMA;
        end

        function [mPPO, mSignal] = fPercentagePriceOscillator(self, iWindowSizeFast, iWindowSizeSlow, iWindowSizeSignal)
            % Function for calculating the Percentage Price Oscillator,
            % i.e., the difference of a fast and slow moving average to the
            % longer moving average
            %
            % Input:
            %   self:               Object, containing high, open, 
            %                       low, close, and volume
            %   iWindowSizeFast:    Scalar, integer, window size of fast
            %                       moving average (default = 12)
            %   iWindowSizeSlow:    Scalar, integer, window size of slow
            %                       moving average (default = 26)
            %   iWindowSizeSignal:  Scalar, window size of the signal line
            %                       (default = 9)
            %
            % Output:
            %   mPPO:               T x N matrix of values for the
            %                       percentage price oscillator
            %                       T: number of time-series observations
            %                       N: number of assets

            % Check inputs
            arguments
                self 
                iWindowSizeFast (1,1) {mustBeNumeric} = 12
                iWindowSizeSlow (1,1) {mustBeNumeric} = 26
                iWindowSizeSignal (1,1) {mustBeNumeric} = 9
            end

            % Check inputs
            assert(iWindowSizeFast < iWindowSizeSlow, ['Length of fast MA must be lower' ...
                'than length of slow MA']);

            % Calculate slow and fast moving averages of close price
            mSlowMA = self.fExponentialMovingAverage(self.mClose, iWindowSizeSlow);
            mFastMA = self.fExponentialMovingAverage(self.mClose, iWindowSizeFast);

            % Main text and Supplementary Eq. (A.12) both scale by the
            % 12-day (fast) EMA.
            mPPO    = (mFastMA - mSlowMA)./mFastMA;

            % Calculate signal line
            mSignal = self.fExponentialMovingAverage(mPPO, iWindowSizeSignal);
        end

        function [mPVO, mSignal] = fPercentageVolumeOscillator(self, iWindowSizeFast, iWindowSizeSlow, iWindowSizeSignal)
            % Function for calculating the Percentage Volume Oscillator,
            % i.e., the difference of a fast and slow moving average to the
            % longer moving average
            %
            % Input:
            %   self:               Object, containing high, open, 
            %                       low, close, and volume
            %   iWindowSizeFast:    Scalar, integer, window size of fast
            %                       moving average (default = 12)
            %   iWindowSizeSlow:    Scalar, integer, window size of slow
            %                       moving average (default = 26)

            % Check inputs
            arguments
                self 
                iWindowSizeFast (1,1) {mustBeNumeric} = 12
                iWindowSizeSlow (1,1) {mustBeNumeric} = 26
                iWindowSizeSignal (1,1) {mustBeNumeric} = 9
            end

            % Check inputs
            assert(iWindowSizeFast < iWindowSizeSlow, ['Length of fast MA must be lower' ...
                'than length of slow MA']);

            % Calculate slow and fast moving averages of close price
            mSlowMA = self.fExponentialMovingAverage(self.mVolume, iWindowSizeSlow);
            mFastMA = self.fExponentialMovingAverage(self.mVolume, iWindowSizeFast);

            % Supplementary Eq. (A.14) uses the 12-day (fast) EMA.
            mPVO = (mFastMA - mSlowMA)./mFastMA;

            % Calculate signal line
            mSignal = self.fExponentialMovingAverage(mPVO, iWindowSizeSignal);
        end

        function mRSI = fRelativeStrengthIndex(self, iWindowSize)
            % Function for calculating the Relative Strength Index
            %
            % Input:
            %   self:               Object, containing high, open, 
            %                       low, close, and volume
            %   iWindowSize:        Scalar, integer, window size 
            %                       (default = 14)
            %
            % Output:
            %   mRSI:               T x N matrix of relative strength index
            %                       values
            %                       T: number of time-series observations
            %                       N: number of assets

            % Check inputs
            arguments
                self
                iWindowSize (1,1) {mustBeInteger, mustBePositive} = 14
            end

            % Supplementary Eqs. (A.3)--(A.5) use simple averages of the
            % preceding L gains and losses. Implement them directly instead
            % of relying on Financial Toolbox's stateful/Wilder convention.
            mRSI = NaN(self.iNumObs, self.iNumAssets);
            mDelta = diff(self.mClose,1,1);
            mGain = max(mDelta,0);
            mLoss = max(-mDelta,0);
            for iIdxT = iWindowSize+1:self.iNumObs
                vIdxWindow = (iIdxT-iWindowSize):iIdxT;
                lComplete = all(isfinite(self.mClose(vIdxWindow,:)),1);
                vGain = mean(mGain(iIdxT-iWindowSize:iIdxT-1,:),1);
                vLoss = mean(mLoss(iIdxT-iWindowSize:iIdxT-1,:),1);
                lBothPositive = lComplete & vGain > 0 & vLoss > 0;
                mRSI(iIdxT,lBothPositive) = 100 - 100 ./ ...
                    (1 + vGain(lBothPositive)./vLoss(lBothPositive));
                lOnlyGain = lComplete & vGain > 0 & vLoss == 0;
                mRSI(iIdxT,lOnlyGain) = 100;
                lOnlyLoss = lComplete & vGain == 0 & vLoss > 0;
                mRSI(iIdxT,lOnlyLoss) = 0;
                % With no gains and no losses RSI is undefined, not 0 or 100.
            end
        end

        function mStochRSI = fStochasticRSI(self, iWindowSize, iMinNumObs)
            % Function for calculating the Stochastic Relative Strength Index
            %
            % Input:
            %   self:               Object, containing high, open, 
            %                       low, close, and volume
            %   iWindowSize:        Scalar, integer, window size (default = 14)
            %
            % Output:
            %   mStochRSI:          T x N matrix of stochastic RSI values
            %                       T: number of time-series observations
            %                       N: number of assets

            % Check inputs
            arguments
                self
                iWindowSize (1,1) {mustBeNumeric} = 14
                iMinNumObs (1,1) {mustBeNumeric} = iWindowSize 
            end

            % Calculate RSI
            mRSI        = self.fRelativeStrengthIndex(iWindowSize);
            
            % Calculate lowest low and highest high of RSI
            mLL         = self.fLowestLow(mRSI, iWindowSize, iMinNumObs);
            mHH         = self.fHighestHigh(mRSI, iWindowSize, iMinNumObs);

            % Calculate stochastic relative strength index
            mRange = mHH - mLL;
            mRange(~isfinite(mRange) | mRange <= 0) = NaN;
            mStochRSI = (mRSI - mLL)./mRange;
            mStochRSI(~isfinite(mRSI)) = NaN;
        end

        function [mStochOscK, mStochOscD] = fStochasticOscillator(self, iWindowSizeK, iWindowSizeD, iMinNumObs)
            % Function for calculating the Stochastic Oscillator
            %
            % Input:
            %   self:               Object, containing high, open, 
            %                       low, close, and volume
            %   iWindowSizeK:       Scalar, integer, window size for 
            %                       the calculation of stochastik %K 
            %                       (default = 14)
            %   iWindowSizeD:       Scalar, integer, window size for 
            %                       the calculation of stochastik %D 
            %                       (default = 3)
            %   iMinNumObs:         Scalar, integer, minimum number of
            %                       observations (default = iWindowSizeK)
            %
            % Output:
            %   mStochOscK:         T x N matrix of stochastic %K values
            %                       T: number of time-series observations
            %                       N: number of assets
            %   mStochOscD:         T x N matrix of stochastic %D values
            %                       T: number of time-series observations
            %                       N: number of assets

            % Check inputs
            arguments
                self
                iWindowSizeK (1,1) {mustBeNumeric} = 14
                iWindowSizeD (1,1) {mustBeNumeric} = 3
                iMinNumObs (1,1) {mustBeNumeric} = iWindowSizeK 
            end

            % Calculate lowest low and highest high of low/high prices
            mLL         = self.fLowestLow(self.mLow, iWindowSizeK, iMinNumObs);
            mHH         = self.fHighestHigh(self.mHigh, iWindowSizeK, iMinNumObs);

            % Calculate stochastic %K
            mRange = mHH - mLL;
            mRange(~isfinite(mRange) | mRange <= 0) = NaN;
            mStochOscK = (self.mClose - mLL)./mRange;
            lCurrentValid = isfinite(self.mClose) & ...
                isfinite(self.mLow) & isfinite(self.mHigh);
            mStochOscK(~lCurrentValid) = NaN;

            % Calculate stochastic %D as simple moving average of %K
            mStochOscD = self.fSimpleMovingAverage(mStochOscK, iWindowSizeD);
        end

        function [mMACD, mSignalLine] = fMACD(self, mData, iWindowSizeFast, iWindowSizeSlow, iWindowSizeMA)
        
            % Check inputs
            arguments
                self 
                mData (:,:)
                iWindowSizeFast (1,1) {mustBeNumeric} = 12
                iWindowSizeSlow (1,1) {mustBeNumeric} = 26
                iWindowSizeMA (1,1) {mustBeNumeric} = 9
            end

            % Check inputs
            assert(iWindowSizeFast < iWindowSizeSlow, ['Length of fast MA must be lower' ...
                'than length of slow MA']);

            % Calculate slow and fast moving averages of close price
            mSlowMA = self.fExponentialMovingAverage(mData, iWindowSizeSlow);
            mFastMA = self.fExponentialMovingAverage(mData, iWindowSizeFast);

            % Calculate difference (fast line)
            mMACD = mFastMA - mSlowMA;

            % Calculate signal line (slow line)
            mSignalLine = self.fExponentialMovingAverage(mMACD, iWindowSizeMA);

            % Set nonavailable observations to missing
            mSignalLine(1:iWindowSizeSlow+iWindowSizeMA,:) = NaN;
            mMACD(1:iWindowSizeSlow,:) = NaN;
        end

        function [mLower, mMiddle, mUpper] = fBollingerBands(self,iWindowSize)

            % Check inputs
            arguments
                self 
                iWindowSize (1,1) {mustBeNumeric} = 20
            end

            % Initialize memory
            mLower = NaN(self.iNumObs, self.iNumAssets);
            mUpper = NaN(self.iNumObs, self.iNumAssets);
            mMiddle= NaN(self.iNumObs, self.iNumAssets);
            for iIdxT= iWindowSize:self.iNumObs
                % Get in-sample data
                vIdxInSample = (iIdxT-iWindowSize+1):iIdxT;
                mDataTemp    = self.mClose(vIdxInSample, :);

                % A 20-day band is available only for a complete,
                % consecutive 20-day closing-price window.
                lComplete = all(isfinite(mDataTemp), 1);
                if any(lComplete)
                    vStd  = std(mDataTemp(:,lComplete), [], 1);
                    vMean = mean(mDataTemp(:,lComplete), 1);
                    mMiddle(iIdxT,lComplete) = vMean;
                    mUpper(iIdxT,lComplete)  = vMean + 2*vStd;
                    mLower(iIdxT,lComplete)  = vMean - 2*vStd;
                end
            end
        end

        function mOBV = fOnBalanceVolume(self, options)
            % Function for calculating the on-balance volume over a given
            % period
            % 
            % Input:
            %   self:
            %   options:        Name-Value pair arguments
            %       .iWindowSize:       Scalar, integer, window size
            %                           (default = 14)
            %       .iMinNumObs:        Scalar, integer, minimum number of
            %                           nonmissing observations 
            %                           (default = iWindowSize)

            % Check input arguments
            arguments
                self 
                options.iWindowSize (1,1) {mustBeNumeric, mustBeInteger, mustBePositive} = 14
                options.iMinNumObs (1,1) {mustBeNumeric, mustBeInteger, mustBeNonnegative} = 0
            end

            % Signed volume is defined only when current volume, current
            % close, and previous close are finite.  The options describe
            % a rolling OBV window; iMinNumObs may permit internal missing
            % observations, but the current signed-volume cell is always
            % required.
            mPriceChange = [NaN(1,self.iNumAssets); diff(self.mClose,1,1)];
            mSignedVolume = sign(mPriceChange) .* self.mVolume;
            lSignedValid = isfinite(mSignedVolume) & ...
                isfinite(self.mClose) & isfinite(self.mVolume);
            mSignedVolume(~lSignedValid) = NaN;

            if options.iMinNumObs == 0
                options.iMinNumObs = options.iWindowSize;
            else
                options.iMinNumObs = min(options.iMinNumObs, options.iWindowSize);
            end
            mOBV = NaN(self.iNumObs, self.iNumAssets);
            for iIdxT = options.iWindowSize:self.iNumObs
                vIdxWindow = (iIdxT-options.iWindowSize+1):iIdxT;
                mSignedTemp = mSignedVolume(vIdxWindow,:);
                lCanCompute = lSignedValid(iIdxT,:) & ...
                    sum(isfinite(mSignedTemp),1) >= options.iMinNumObs;
                if any(lCanCompute)
                    mOBV(iIdxT,lCanCompute) = ...
                        sum(mSignedTemp(:,lCanCompute),1,'omitmissing');
                end
            end
        end

        function mCCI = fCCI(self, options)
            % Function for calculating the Commodity Channel Index
            % 
            % Input:
            %   options:        Name-Value pair arguments
            %       'iWindowSize':  Scalar, integer, length of formation
            %                       period (default = 20)
            %       'iMinNumObs':   Scalar, integer, minimum number of
            %                       observations (default = 20)
            %
            % Output:
            %   mCCI:           T x N matrix of values for the 
            %                   Commodity Channel Index 
            %                   T: number of time-series observations
            %                   N: number of assets

            % Check inputs
            arguments
                self 
                options.iWindowSize (1,1) {mustBeNumeric} = 20
                options.iMinNumObs (1,1) {mustBeNumeric} = 20
            end

            % Reset minimum number of observations required for
            % calculations if it exceeds window size
            options.iMinNumObs = min(options.iMinNumObs, options.iWindowSize);

            % Set constant
            dConstant           = 0.015; % default

            % Get typical price (average of close, low, and high)
            mTypPrc     = (self.mClose + self.mLow + self.mHigh)/3;

            % Initialize memory
            mCCI        = NaN(self.iNumObs, self.iNumAssets);

            % Loop over time
            for iIdxT = options.iWindowSize:self.iNumObs
                % Get in-sample index
                vIdxInSample    = (iIdxT-options.iWindowSize+1):iIdxT;

                mTypPrcTemp = mTypPrc(vIdxInSample,:);
                lValid = isfinite(mTypPrcTemp);
                lCanCompute = lValid(end,:) & ...
                    sum(lValid,1) >= options.iMinNumObs;
                mTypPrcTemp(~lValid) = NaN;
                if any(lCanCompute)
                    vSMArecent = mean(mTypPrcTemp(:,lCanCompute), ...
                        1, 'omitmissing');
                    mAbsDiff = abs(mTypPrcTemp(:,lCanCompute) - vSMArecent);
                    vMeanDev = mean(mAbsDiff, 1, 'omitmissing');
                    vNumerator = mTypPrcTemp(end,lCanCompute) - vSMArecent;
                    vCCI = vNumerator ./ (dConstant * vMeanDev);
                    vCCI(~isfinite(vCCI) | vMeanDev <= 0) = NaN;
                    mCCI(iIdxT,lCanCompute) = vCCI;
                end
            end
        end
    end
end
