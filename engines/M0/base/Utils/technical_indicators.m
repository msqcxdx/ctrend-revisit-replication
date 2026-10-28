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

            % Initialize memory
            mSMA = NaN(iNumObs, iNumAssets);
            for iIdxT = 1:iNumObs
                % Get in-sample data
                vIdxInSample    = max(1, (iIdxT-iWindowSize+1)):iIdxT;
                mDataTemp       = mData(vIdxInSample, :);

                % Calculate mean
                mSMA(iIdxT, :)  = mean(mDataTemp, 1, 'omitnan');                
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
                dSmoothing (1,1) {mustBeNumeric} = 2
            end

            % Determine dimensions
            [iNumObs, iNumAssets] = size(mData);

            % Get smooting factor
            dSmoothing  = dSmoothing./(1 + iWindowSize);

            % Get simple MA for initialization
            mSMA        = self.fSimpleMovingAverage(mData, iWindowSize);

            % Initialize memory
            mEMA        = NaN(iNumObs, iNumAssets);
            for iIdxT = 2:iNumObs
                % Get in-sample data
                vIdxInSample = max(1, (iIdxT-iWindowSize+1)):iIdxT;
                mDataTemp    = mData(vIdxInSample, :);

                % Get previous EMA
                vPrevEMA    = mEMA(iIdxT-1, :);

                % Replace missing values of previous EMA with simple moving
                % average
                lIsNaN              = isnan(vPrevEMA);
                vPrevEMA(lIsNaN)    = mSMA(iIdxT-1, lIsNaN);

                % Calculate smoothed mean
                mEMA(iIdxT, :) = mData(iIdxT,:) * dSmoothing + ...
                    vPrevEMA .* (1 - dSmoothing);
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

            % Initialize memory
            mLowestLow = NaN(self.iNumObs, self.iNumAssets);
            for iIdxT = iWindowSize:self.iNumObs
                % Get in-sample data
                vIdxInSample = (iIdxT-iWindowSize+1):iIdxT;
                mDataTemp    = mData(vIdxInSample, :);

                % Ensure that all data exist
                lNotAvail = sum(~isnan(mDataTemp), 1) < iMinNumObs;
                mDataTemp(:, lNotAvail) = NaN;

                % Calculate mean
                mLowestLow(iIdxT, :) = min(mDataTemp, [], 1);                
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

            % Initialize memory
            mHighestHigh = NaN(self.iNumObs, self.iNumAssets);
            for iIdxT = iWindowSize:self.iNumObs
                % Get in-sample data
                vIdxInSample = (iIdxT-iWindowSize+1):iIdxT;
                mDataTemp    = mData(vIdxInSample, :);

                % Ensure that all data exist
                lNotAvail = sum(~isnan(mDataTemp), 1) < iMinNumObs;
                mDataTemp(:, lNotAvail) = NaN;

                % Calculate mean
                mHighestHigh(iIdxT, :) = max(mDataTemp, [], 1);                
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

            % Find first nonmissing observation
            iIdxFirst = max(iWindowSize,find(~all(isnan(self.mVolume),2),1,'first') + iMinNumObs - 1);

            for iIdxT = iIdxFirst:self.iNumObs
                % Get in-sample data
                vIdxInSample    = (iIdxT-iWindowSize+1):iIdxT;
                mCloseTemp      = self.mClose(vIdxInSample, :);
                mLowTemp        = self.mLow(vIdxInSample, :);
                mHighTemp       = self.mHigh(vIdxInSample, :);
                mVolTemp        = self.mVolume(vIdxInSample, :);

                % Ensure that all data exist
                lNotAvail = isnan(mCloseTemp) | isnan(mLowTemp) | ...
                    isnan(mHighTemp) | isnan(mVolTemp);
               
                % Match missing data
                mCloseTemp(lNotAvail)   = NaN;
                mLowTemp(lNotAvail)     = NaN;
                mHighTemp(lNotAvail)    = NaN;
                mVolTemp(lNotAvail)     = NaN;

                % Remove assets with too few observations
                lNotAvail = sum(~lNotAvail, 1) < iMinNumObs;
                mCloseTemp(:, lNotAvail) = NaN;
                mLowTemp(:, lNotAvail)   = NaN;
                mHighTemp(:, lNotAvail)  = NaN;
                mVolTemp(:, lNotAvail)   = NaN;

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
                vSumVOL(vSumVOL <= 0) = NaN;
                mCMF(iIdxT,:) = vSumAD./vSumVOL;
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
            mTrueRange(1,:) = mPriceRangeHL(1,:);
            for iIdxT = 2:self.iNumObs
                % Get in-sample data
                mDataTemp = [mPriceRangeHL(iIdxT,:);...
                    mPriceRangeHC(iIdxT,:);...
                    mPriceRangeLC(iIdxT,:)];

                % Get maximum 
                mTrueRange(iIdxT,:) = max(mDataTemp, [], 1);
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

            % Calculate ADL
            mADL = cumsum(mMFV, 1, 'omitnan');         
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

            % Calculate percentage difference
            mPPO    = (mFastMA - mSlowMA)./mSlowMA;

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

            % Calculate percentage difference
            mPVO = (mFastMA - mSlowMA)./mSlowMA;

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
                iWindowSize (1,1) {mustBeNumeric} = 14
            end

            % Preallocate memory
            mRSI = NaN(self.iNumObs, self.iNumAssets);

            % Loop over assets
            for iIdxA = 1:self.iNumAssets
                mRSI(:, iIdxA) = rsindex(self.mClose(:, iIdxA), 'WindowSize', iWindowSize);
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
            mStochRSI   = (mRSI - mLL)./(mHH - mLL);
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
            mStochOscK = (self.mClose - mLL)./(mHH-mLL);

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

                % Calculate mean and standard deviation
                vStd = std(mDataTemp, [], 1);
                vMean = mean(mDataTemp,1);
            
                % Calculate bands
                mMiddle(iIdxT,:) = vMean;
                mUpper(iIdxT,:) = vMean + 2*vStd;
                mLower(iIdxT,:) = vMean - 2*vStd;
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
                options.iWindowSize (1,1) {mustBeNumeric, mustBeNonnegative} = 14
                options.iMinNumObs (1,1) {mustBeNumeric, mustBeNonnegative} = iWindowSize
            end

            % Calculate returns
            mRet    = [NaN(1, self.iNumAssets); ...
                (self.mClose(2:end,:)./self.mClose(1:end-1,:)) - 1];
            mSign   = sign(mRet);

            % Initialize on-balance volume
            mOBV    = NaN(self.iNumObs, self.iNumAssets);

            % Find first nonmissing observation
            iIdxFirst = find(~all(isnan(self.mVolume),2),1,'first');

            % Loop over time
            for iIdxT = iIdxFirst:self.iNumObs
                % Get in-sample data
                vIdxInSample    = iIdxT;
                mVolTemp        = self.mVolume(vIdxInSample,:);
                mSignTemp       = mSign(vIdxInSample,:);

                % Find valid assets
                lNonValid  = sum( ~isnan(mVolTemp) & ~isnan(mSignTemp), 1) < options.iMinNumObs;
                mVolTemp(:,lNonValid)  = 0;
                mSignTemp(:,lNonValid) = 0;

                % Multiplication of OBV with sign of price change
                mVolSign = mVolTemp .* mSignTemp;

                %  First day is always positive: Determine which assets
                %  already had an on-balance volume observation
                mCumSum = cumsum(~isnan(mOBV),1);
                lPositive = mCumSum(iIdxT,:) == 0;
                
                % Transform to positive
                mVolSign(lPositive) = abs(mVolSign(lPositive));

                % Calculate sum of signed trading volume
                mOBV(iIdxT,~lNonValid) = sum([mOBV(iIdxT-1,~lNonValid); mVolSign(:,~lNonValid)], 1, 'omitnan');
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

            % Get moving average from typical price
            mSMA        = self.fSimpleMovingAverage(mTypPrc, options.iWindowSize);

            % Calculate the difference of typical price and SMA
            mDiff       = mTypPrc - mSMA;

            % Initialize memory
            mCCI        = NaN(self.iNumObs, self.iNumAssets);

            % Loop over time
            for iIdxT = options.iWindowSize:self.iNumObs
                % Get in-sample index
                vIdxInSample    = (iIdxT-options.iWindowSize+1):iIdxT;

                % Get in-sample data
                mDiffTemp       = mDiff(vIdxInSample,:);
                vSMArecent      = mSMA(vIdxInSample(end),:);
                mTypPrcTemp     = mTypPrc(vIdxInSample,:);

                % Find valid assets and set observations of non-valid
                % assets to missing
                lNonValid  = sum( ~isnan(mDiffTemp) | isnan(mTypPrcTemp)) < options.iMinNumObs;
                vSMArecent(:,lNonValid)    = NaN;
                mDiffTemp(:,lNonValid)     = NaN;
                mTypPrcTemp(:,lNonValid)   = NaN;

                % Calculate mean deviation:
                % 1.: subtract the most recent 20-period average of the 
                % typical price from each period's typical price. 
                mAbsDiff = abs(mTypPrcTemp - vSMArecent);

                % 2. Mean of the absolute value
                vMeanDev = mean(mAbsDiff, 1, 'omitmissing');

                % Calculate CCI
                mCCI(iIdxT,:) = mDiffTemp(end,:)./(dConstant * vMeanDev);
            end
        end
    end
end