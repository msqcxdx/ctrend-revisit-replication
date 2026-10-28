classdef characteristics

    properties
        mME
        mReturns
        mVol
        mPrice
        vMktRet
        iNumAssets
        iNumObs
    end

    methods 

        function self = characteristics(mReturns, mME, mVol, mPrice, vMktRet)
            % Class for calculating various characteristics
            % 
            % Input:
            %   mReturns:       T x N matrix of returns
            %   mME:            T x N matrix of market capitalization
            %   mVolume:        T x N matrix of dollar trading volume
            %   mClose:         T x N matrix of closing prices
            %   vMktRet:        T x 1 vector of market returns

            % Error checking
            assert(size(mReturns, 1) == size(mME,1),...
                sprintf('Number of rows in mReturns and mME must agree (%i ~= %i)',...
                size(mReturns, 1), size(mME,1)));
            assert(size(mReturns, 2) == size(mME,2),...
                sprintf('Number of columns in mReturns and mME must agree (%i ~= %i)',...
                size(mReturns, 2), size(mME,2)));
            assert(size(mReturns, 1) == size(mVol,1),...
                sprintf('Number of rows in mReturns and mVol must agree (%i ~= %i)',...
                size(mReturns, 1), size(mVol,1)));
            assert(size(mReturns, 2) == size(mVol,2),...
                sprintf('Number of columns in mReturns and mVol must agree (%i ~= %i)',...
                size(mReturns, 2), size(mVol,2)));
            assert(size(mReturns, 1) == size(mPrice,1),...
                sprintf('Number of rows in mReturns and mPrice must agree (%i ~= %i)',...
                size(mReturns, 1), size(mPrice,1)));
            assert(size(mReturns, 2) == size(mPrice,2),...
                sprintf('Number of columns in mReturns and mPrice must agree (%i ~= %i)',...
                size(mReturns, 2), size(mPrice,2)));

            % Set properties
            self.mReturns = mReturns;
            self.mME = mME;
            self.mVol = mVol;
            self.mPrice = mPrice;
            self.vMktRet = vMktRet;
            self.iNumAssets = size(mReturns,2);
            self.iNumObs = size(mReturns,1);
        end

        % OVERVIEW:
        %   === SIZE CHARACTERISTICS:
        %   fAge:       
        %   fMarketCap:         Banz (1981)
        %   fPrc:               
        %   fMaxPrc:
        %
        %   === LIQUIDITY CHARACTERISTICS
        %   fAmihud:            Amihud (2002)
        %   fAvgVolume:
        %   fAvgVolumeStd:
        %   fTurnover:
        %   fTurnoverStd:
        %   fZeroTrade:
        %
        %   === PAST PRICES CHARACTERISTICS
        %   fMomentum:          Jedgadeesh (1990), Jegadeesh/Titman (1993)
        %   fRelToHigh:
        %
        %   === RISK CHARACTERISTICS
        %   fAlphaBetaSigma:
        %   fDownUpVolatility:  Chen/Hong/Stein (2001)
        %   fES:
        %   fNCSkew:            Chen/Hong/Stein (2001)
        %   fVaR
        %   fVolatility


        % === SIZE CHARACTERISTICS

        function mAge = fAge(self)
            % Function for calculating the age as the number of periods
            % with valid price data
            %
            % Input:
            %
            % Output:
            %   mAge:           N x T matrix of asset's age
            %                   N: number of assets
            %                   T: number of time-series observations

            % Number of periods with valid price data
            mAge = cumsum(~isnan(self.mPrice),1);

            % Set observations with zero age to missing
            mAge(mAge == 0) = NaN;
        end

        function mME = fMarketCap(self, lUseLog)
            % Function for calculating the market capitalization
            %
            % Input:
            %   lUseLog:        Logical, specifies whether to calculate the
            %                   logarithm of market value (default = true)
            %
            % Output:
            %   mLogME:         N x T matrix of (log) market capitalization
            %                   N: number of assets
            %                   T: number of time-series observations

            % Check inputs
            arguments
                self
                lUseLog (1,1) logical = true
            end

            % Get market capitalization
            if lUseLog
                mME = log(self.mME);
            else
                mME = self.mME;
            end
        end

        function mPrc = fPrice(self)
            % Returns the most recent price 
            mPrc = self.mPrice;
        end

        function mMaxPrc = fMaxPrc(self, iLength, iOffset, iMinPeriods)
            % Function for computing the maximum price over a given window
            %
            % Input:
            %   iLength:        Scalar, integer, calculation period
            %   iOffset:        Scalar, integer, number of periods to skip
            %
            % Output:
            %   mMaxPrc:        T x N matrix 

            % Set default arguments
            arguments
                self
                iLength (1,1) double = 7
                iOffset (1,1) double = 0
                iMinPeriods (1,1) double = 1
            end
            
            % Reset minimum number of observations
            iMinPeriods = min(iLength, iMinPeriods);

            % Preallocate memory
            mMaxPrc = NaN(self.iNumObs, self.iNumAssets);

            % Find time index of first nonmissing observation. This is
            % where the loop starts
            iIdxFirstNonMissing = find(any(~isnan(self.mPrice),2),1,'first');

            % Increase start time index by the number of periods
            iIdxStart = max(iLength, iIdxFirstNonMissing + iMinPeriods-1);
            for iIdxT = iIdxStart:self.iNumObs
                % Get in-sample data
                vIdxInSample = (iIdxT-iLength+1):(iIdxT-iOffset);

                % Get data
                mPrcTemp    = self.mPrice(vIdxInSample, :);
                lValid      = sum(~isnan(mPrcTemp), 1) >= iMinPeriods;

                % Get maximum price (only for assets with valid price
                % observations)
                mMaxPrc(iIdxT, lValid) = max(mPrcTemp(:,lValid), [], 1);
            end
        end


        % === LIQUIDITY CHARACTERISTICS
        function mAmihud = fAmihud(self, iLength, iOffset, iMinPeriods)
            % Returns the Amihud (2002) liquidity measure
            %
            % Input:
            %   iLength:        Scalar, integer, calculation period
            %                   (default = 7)
            %   iOffset:        Scalar, integer, number of periods to skip
            %                   (default = 0)
            %   iMinPeriods:    Scalar, integer, minimum number of periods
            %                   (default = 5)
            %
            % Output:
            %   mAmihud:        N x T matrix of Amihud (2002) measures
            %                   N: number of assets
            %                   T: number of time-series observations    

            % Check inputs
            arguments
                self
                iLength (1,1) double = 7
                iOffset (1,1) double = 0
                iMinPeriods (1,1) double = 5
            end

            % Reset minimum number of periods
            iMinPeriods = min(iLength, iMinPeriods);

            % Calculate price impact
            mPriceImpact = abs(self.mReturns)./(self.mVol+1e-8);

            % Preallocate memory
            mAmihud = NaN(self.iNumObs, self.iNumAssets);
            for iIdxT = iLength:self.iNumObs
                % Get in-sample data
                vIdxInSample = (iIdxT-iLength+1):(iIdxT-iOffset);

                % Get data
                mPriceImpactTemp = mPriceImpact(vIdxInSample,:);
                lValid = sum(~isnan(mPriceImpactTemp), 1) >= iMinPeriods;

                % Get average
                mAmihud(iIdxT, lValid) = mean(mPriceImpactTemp(:,lValid), 1, 'omitnan');
            end
        end

        function mAvgVolume = fAvgVolume(self, iLength, iOffset, iMinPeriods, lUseLog, lPrcVol)
            % Returns the average trading volume in a given window
            %
            % Input:
            %   iLength:        Scalar, integer, calculation period
            %                   (default = 7)
            %   iOffset:        Scalar, integer, number of periods to skip
            %                   (default = 0)
            %   iMinPeriods:    Scalar, integer, minimum number of periods
            %                   with trading data
            %                   (default = 5)
            %   lUseLog:        Logical, specifies whether to calculate log
            %                   volume (default = false)
            %   lPrcVol:        Logical, specifies whether to calculate
            %                   volume as volumes * price (true, default)    
            %
            % Output:
            %   mAvgVolume:     T x N matrix, average trading volume 
            %                   T: number of time-series observations
            %                   N: number of assets
            
            % Set default arguments
            arguments
                self
                iLength (1,1) double = 7
                iOffset (1,1) double = 0
                iMinPeriods (1,1) double = 5
                lUseLog (1,1) logical = false
                lPrcVol (1,1) logical = true
            end

            % Epsilon for avoiding numerical issues ( log(0) = Inf )
            dEps = 1e-10;
            
            % Reset minimum number of periods
            iMinPeriods = min(iLength, iMinPeriods);

            % Get volume
            if lPrcVol
                mVolume = self.mVol; % Already multiplied by price
            else
                mVolume = self.mVol ./ self.mPrice;
            end
            
            % Preallocate memory
            mAvgVolume = NaN(self.iNumObs, self.iNumAssets);

            % Find start index
            iIdxFirstNonMissing = find(any(~isnan(self.mVol),2),1,'first');
            iIdxStart = max(iLength, iIdxFirstNonMissing + iMinPeriods-1);
            for iIdxT = iIdxStart:self.iNumObs
                % Get in-sample data
                vIdxInSample = (iIdxT-iLength+1):(iIdxT-iOffset);

                % Get data
                mVolTemp = mVolume(vIdxInSample,:);
                lValid = sum(~isnan(mVolTemp),1) >= iMinPeriods;

                % Calculate average trading volume
                mAvgVolume(iIdxT,lValid) = mean(mVolTemp(:,lValid), 1, 'omitnan');
            end
            if lUseLog
                mAvgVolume = log(mAvgVolume + dEps);
            end
        end        

        function mVolumeStd = fAvgVolumeStd(self, iLength, iOffset, iMinPeriods, lUseLog, lPrcVol)

            % Set default arguments
            arguments
                self
                iLength (1,1) double = 30
                iOffset (1,1) double = 0
                iMinPeriods (1,1) double = 20
                lUseLog (1,1) logical = false
                lPrcVol (1,1) logical = true
            end

            % Epsilon for avoiding numerical issues ( log(0) = Inf )
            dEps = 1e-10;
            
            % Reset minimum number of periods
            iMinPeriods = min(iLength, iMinPeriods);

            % Get volume
            if lPrcVol
                mVolume = self.mVol; % Already multiplied by price
            else
                mVolume = self.mVol ./ self.mPrices;
            end

            % Calculate standard deviation of trading volume

            % Preallocate memory
            mVolumeStd = NaN(self.iNumObs, self.iNumAssets);

            % Find start index
            iIdxFirstNonMissing = find(any(~isnan(mVolume),2),1,'first');
            iIdxStart = max(iLength, iIdxFirstNonMissing + iMinPeriods-1);
            for iIdxT = iIdxStart:self.iNumObs
                % Get in-sample data
                vIdxInSample = (iIdxT-iLength+1):(iIdxT-iOffset);

                % Get data
                mVolumeTemp = mVolume(vIdxInSample,:);
                lValid = sum(~isnan(mVolumeTemp),1) >= iMinPeriods;

                % Get logarithm
                if lUseLog
                    mVolumeTemp = log(mVolumeTemp + dEps);
                end

                % Calculate average trading volume
                mVolumeStd(iIdxT,lValid) = std(mVolumeTemp(:,lValid), [], 1, 'omitnan');
            end
        end

        function mTurnover = fTurnover(self, lUseLog)
            % Function for computing the turnover

            arguments
                self
                lUseLog (1,1) logical = false
            end
    
            % Calculate turnover
            mTurnover = self.mVol./self.mME;

            % Logarithm of turnover
            if lUseLog
                % Epsilon for avoiding numerical issues ( log(0) = Inf )
                dEps = 1e-10;

                mTurnover = log(mTurnover + dEps);
            end
        end

        function mAvgTurnover = fAvgTurnover(self, iLength, iOffset, iMinPeriods, lUseLog)
            % Set default arguments
            arguments
                self
                iLength (1,1) double = 30
                iOffset (1,1) double = 0
                iMinPeriods (1,1) double = 20
                lUseLog (1,1) logical = false
            end
            
            % Reset minimum number of periods
            iMinPeriods = min(iLength, iMinPeriods);

            % Calculate turnover
            mTurnover = fTurnover(self, lUseLog);

            % Preallocate memory
            mAvgTurnover = NaN(self.iNumObs, self.iNumAssets);

            % Find start index
            iIdxFirstNonMissing = find(any(~isnan(mTurnover),2),1,'first');
            iIdxStart = max(iLength, iIdxFirstNonMissing + iMinPeriods-1);
            for iIdxT = iIdxStart:self.iNumObs
                % Get in-sample data
                vIdxInSample = (iIdxT-iLength+1):(iIdxT-iOffset);

                % Get data
                mTurnTemp = mTurnover(vIdxInSample, :);
                lValid = sum(~isnan(mTurnTemp), 1) >= iMinPeriods;

                % Calculate volatility of turnover
                mAvgTurnover(iIdxT, lValid) = mean(mTurnTemp(:,lValid), 1, 'omitnan');
            end
        end

        function mTurnoverStd = fTurnoverStd(self, iLength, iOffset, iMinPeriods)
            % Function for computing the volatility of turnover
            %
            % Input:
            %   iLength:        Scalar, integer, calculation period
            %                   (default = 30)
            %   iOffset:        Scalar, integer, number of periods to skip
            %                   (default = 0)
            %   iMinPeriods:    Scalar, integer, minimum number of periods
            %                   (default = 20)
            %
            % Output:
            %   mAmihud:        N x T matrix of Amihud (2002) measures
            %                   N: number of assets
            %                   T: number of time-series observations    

            % Set default arguments
            if nargin < 4 || isempty(iMinPeriods)
                iMinPeriods = 20;
            end
            if nargin < 3 || isempty(iOffset)
                iOffset = 0;
            end
            if nargin < 2 || isempty(iLength)
                iLength = 30;
            end
            
            % Reset minimum number of periods
            iMinPeriods = min(iLength, iMinPeriods);

            % Calculate turnover
            mTurnover = fTurnover(self);

            % Preallocate memory
            mTurnoverStd = NaN(self.iNumObs, self.iNumAssets);

            % Find start index
            iIdxFirstNonMissing = find(any(~isnan(mTurnover),2),1,'first');
            iIdxStart = max(iLength, iIdxFirstNonMissing + iMinPeriods-1);
            for iIdxT = iIdxStart:self.iNumObs
                % Get in-sample data
                vIdxInSample = (iIdxT-iLength+1):(iIdxT-iOffset);

                % Get data
                mTurnTemp = mTurnover(vIdxInSample, :);
                lValid = sum(~isnan(mTurnTemp), 1) >= iMinPeriods;

                % Calculate volatility of turnover
                mTurnoverStd(iIdxT, lValid) = std(mTurnTemp(:,lValid), [], 1, 'omitnan');
            end
        end

        function mDetrendTurnover = fDetrendTurnover(self, iLength, iOffset, iMinPeriods)

            % Set default arguments
            arguments
                self
                iLength (1,1) double = 180
                iOffset (1,1) double = 0
                iMinPeriods (1,1) double = 90
            end

            % Reset minimum number of periods
            iMinPeriods = min(iLength, iMinPeriods);

            % Calculate turnover
            mTurnover = fTurnover(self);

            % Calculate market weights
            mWts = self.mME ./sum(self.mME,2,'omitnan');
            mWts_L1 = [NaN(1, self.iNumAssets); mWts(1:end-1,:)];
            mWts_L1 = mWts;
        
            % Calculate market turnover
            vMktTurnover = sum(mWts_L1 .* mTurnover, 2, 'omitnan');
            vMktTurnover(all(isnan(mWts_L1) | isnan(mTurnover),2)) = NaN;

            % Calculate difference to market turnover
            mTurnoverDiff = mTurnover - vMktTurnover;

            % Preallocate memory
            mTurnoverTrend = NaN(self.iNumObs, self.iNumAssets);

            % Find start index
            iIdxFirstNonMissing = find(any(~isnan(mTurnoverDiff),2),1,'first');
            iIdxStart = max(iLength, iIdxFirstNonMissing + iMinPeriods-1);
            for iIdxT = iIdxStart:self.iNumObs
                % Get in-sample index
                vIdxInSample = (iIdxT-iLength+1):(iIdxT-iOffset);

                % Get data
                mTurnoverDiffTemp = mTurnoverDiff(vIdxInSample,:);
                lValid = sum(~isnan(mTurnoverDiffTemp),1) >= iMinPeriods;

                % Get median
                mTurnoverTrend(iIdxT,lValid) = median(mTurnoverDiffTemp(:,lValid), 1, 'omitnan');
            end
            % Detrend turnover
            mDetrendTurnover = mTurnoverDiff - mTurnoverTrend;
        end

        function mZeroTrade = fZeroTrade(self, iLength, iOffset, iMinPeriods, lScale)
            % Function for calculating the number of zero trading days over
            % a given period
            %
            % Input:
            %   iLength:        Scalar, integer, calculation period
            %                   (default = 7)
            %   iOffset:        Scalar, integer, number of periods to skip
            %                   (default = 0)
            %   iMinPeriods:    Scalar, integer, minimum number of periods
            %                   with trading data
            %                   (default = 5)
            %   lScale:         Logical, specifies whether to scale the
            %                   number of zero trading days with the number
            %                   of days within the period
            %                   (default = false)
            %
            % Output:
            %   mZeroTrade:     N x T matrix of zero trading days
            %                   N: number of assets
            %                   T: number of time-series observations

            % Set default arguments
            arguments
                self 
                iLength (1,1) double = 7
                iOffset (1,1) double = 0
                iMinPeriods (1,1) double = 1
                lScale (1,1) logical = true
            end

            % Reset minimum number of periods
            iMinPeriods = min(iLength, iMinPeriods);

            % Preallocate memory
            mZeroTrade = NaN(self.iNumObs, self.iNumAssets);

            % Find start index
            iIdxFirstNonMissing = find(any(~isnan(self.mVol),2),1,'first');
            iIdxStart = max(iLength, iIdxFirstNonMissing + iMinPeriods-1);
            for iIdxT = iIdxStart:self.iNumObs
                % Get in-sample data
                vIdxInSample = (iIdxT-iLength+1):(iIdxT-iOffset);

                % Get data
                mVolTemp = self.mVol(vIdxInSample,:);
                mRetTemp = self.mReturns(vIdxInSample,:);
                lValid = sum(~isnan(mRetTemp),1) >= iMinPeriods;

                % Calculate number of zero trading days
                vNumZeroTrade = sum( mRetTemp == 0 | isnan(mRetTemp), 1); %  | isnan(mVolTemp)

                % Scale
                if lScale
                    mZeroTrade(iIdxT,lValid) = vNumZeroTrade(lValid) ./ size(mVolTemp,1);
                else
                    mZeroTrade(iIdxT,lValid) = vNumZeroTrade(lValid);
                end
            end
        end

        %% PAST PRICE CHARACTERISTICS
        function mMomentum = fMomentum(self, iLength, iOffset)
            % Function for calculating momentum
            %
            % Input:
            %   iLength:        Scalar, integer, length of formation period
            %   iOffset:        Scalar, integer, number of periods to
            %                   before the current time tick t 
            %                   (default = 0)
            %
            % Output:
            %   mMomentum:      T x N matrix of momentum returns
            %                   T: number of time-series observations
            %                   N: number of assets

            % Set default arguments
            arguments
                self 
                iLength (1,1) double = 1
                iOffset (1,1) double = 0
            end

            % Calculate percentage price change
            mMomentum = self.fPctChange(self.mPrice, iLength, iOffset);
        end

        %% RISK CHARACTERISTICS
        function [mAlpha, mBeta, mSigma, mISkew, mR2] = fAlphaBetaSigma(self, mX, iLength, iOffset, iMinPeriods)
            % Function for estimating the alpha, betas, residual variances,
            % idiosyncratic skewness, and R² of a linear regression with
            % rolling estimation window
            %
            % Input:
            %   mX:         T x K matrix of factors
            %               T: number of time-series observations
            %               K: number of factors
            %   iLength:    Scalar, integer, number of in-sample
            %               observations for estimation (default = 90)
            %   iOffset:    Scalar, integer, number of time ticks to skip
            %               prior to the current time tick t (default = 1)
            %   iMinPeriods:Scalar, integer, minimum number of periods for
            %               regression (default = 30)
            %
            % Output:
            %   mAlpha:     T x N matrix of regression alphas
            %               T: number of time-series observations
            %               N: number of assets
            %   mBeta:      T x N x K matrix of regression betas
            %               T: number of time-series observations
            %               N: number of assets
            %               K: number of factors
            %   mSigna:     T x N matrix of residual standard deviations
            %               T: number of time-series observations
            %               N: number of assets
            %   mISkew:     T x N matrix of idiosyncratic skewness measures
            %               T: number of time-series observations
            %               N: number of assets
            %   mR2         T x N matrix of R2s
            %               T: number of time-series observations
            %               N: number of assets

            % Set default arguments
            arguments
                self 
                mX double
                iLength (1,1) double = 90
                iOffset (1,1) double = 0
                iMinPeriods (1,1) double = 30
            end

            % Calculate market return if empty and use this as the only factor
            if nargin < 2 || isempty(mX)
                mWts    = self.mME./sum(self.mME,2,'omitnan');
                mX      = sum(mWts .* self.mReturns, 2, 'omitnan');
                mX(all(isnan(self.mReturns),2)) = NaN;
            end          

            % Determine dimensions
            [iNumObsX, iNumFactors] = size(mX);

            % Check dimensions
            assert(iNumObsX == self.iNumObs, 'Number of time-series observations must agree');
             
            % Preallocate memory
            mAlpha  = NaN(self.iNumObs, self.iNumAssets);
            mBeta   = NaN(self.iNumObs, self.iNumAssets, iNumFactors);
            mSigma  = NaN(self.iNumObs, self.iNumAssets);
            mISkew  = NaN(self.iNumObs, self.iNumAssets);
            mR2     = NaN(self.iNumObs, self.iNumAssets);
            for iIdxT = iLength:self.iNumObs
                % Get in-sample data
                vIdxInSample = (iIdxT-iLength+1):(iIdxT-iOffset);
                iNumObsIn    = length(vIdxInSample);

                % Get return data
                mRetTemp    = self.mReturns(vIdxInSample,:);

                % Add intercept
                mXtemp      = [ones(iNumObsIn, 1), mX(vIdxInSample,:)];

                % === The regressions are performed in two steps. First,
                % for all assets that have all in-sample observations, we
                % can quickly calculate the betas via X\Y where X is the
                % regressor matrix and Y is the matrix of dependent
                % variables. For all other assets, we have to loop over
                % each asset, which is very slow

                % Find indices of assets that have all in-sample observations
                lAllObsAvail = ~any(isnan(mRetTemp),1) & ~any(isnan(mXtemp),'all');
                if any(lAllObsAvail)
                    % Fast regression. The resulting output is a (K+1) x M
                    % matrix, where K is the number of independent
                    % variables and M is the number of dependent variables
                    mCoef = mXtemp\mRetTemp(:,lAllObsAvail);

                    % Save alpha (first row)
                    mAlpha(iIdxT, lAllObsAvail)     = mCoef(1,:);

                    % Save beta (second to end). We have a K x M matrix,
                    % however, want to store it in a 1 x M x K matrix.
                    % Using permute, we change the order of the dimension
                    % of mCoef such that the matrix is of size 1 x M x K
                    mBeta(iIdxT, lAllObsAvail,:)    = permute(mCoef(2:end,:),[3,2,1]);

                    % Get fitted values
                    mYfit   = mXtemp * mCoef;

                    % Get residuals
                    mResid  = mRetTemp(:,lAllObsAvail) - mYfit;

                    % Get residual standard deviation
                    mSigma(iIdxT,lAllObsAvail)  = std(mResid, [], 1);

                    % Calculate skewness of residuals
                    mISkew(iIdxT, lAllObsAvail) = skewness(mResid, [], 1);

                    % Get R2
                    vSSR = sum(mResid.^2);
                    vTSR = sum( (mRetTemp - mean(mRetTemp,1)).^2,1);
                    mR2(iIdxT, lAllObsAvail) = 1 - (vSSR./vTSR(lAllObsAvail));   
                end

                % Now we run the regressions for assets with missing values
                % asset-by-asset. 

                % Find indices of assets with a sufficient number of
                % observations (but not all observations)
                vIdxAsset = find( (sum(~isnan(mRetTemp),1) >= iMinPeriods) & ~lAllObsAvail);

                % Skip if no asset has sufficient data
                if isempty(vIdxAsset)
                    continue
                end

                % Iterate over assets     
                for iIdxA = 1:length(vIdxAsset)
                    % Get data
                    vYtemp = mRetTemp(:,vIdxAsset(iIdxA));
                    mXcopy = mXtemp;
                    
                    % Remove missing values
                    lIsNaN              = any(isnan(mXtemp),2) | isnan(vYtemp);
                    vYtemp(lIsNaN)      = [];
                    mXcopy(lIsNaN,:)    = [];

                    % Regression
                    mCoef = mXcopy\vYtemp;

                    % Save alpha and beta
                    mAlpha(iIdxT, vIdxAsset(iIdxA))     = mCoef(1);
                    mBeta(iIdxT, vIdxAsset(iIdxA),:)    = mCoef(2:end);

                    % Get fitted values
                    mYfit   = mXcopy * mCoef;

                    % Get residuals
                    mResid  = vYtemp - mYfit;

                    % Get residual standard deviation
                    mSigma(iIdxT,vIdxAsset(iIdxA)) = std(mResid, [], 1);

                    % Calculate skewness of residuals
                    mISkew(iIdxT, vIdxAsset(iIdxA)) = skewness(mResid, [], 1);

                    % Get R2
                    vSSR = sum(mResid.^2);
                    vTSR = sum( (vYtemp - mean(vYtemp,1)).^2,1);
                    mR2(iIdxT, vIdxAsset(iIdxA)) = 1 - (vSSR./vTSR);   
                end
            end
        end

        % function mES = fES(self, iLength, iOffset, iMinPeriods, dAlpha)
        %     % Function for calculating the expected shortfall under the
        %     % assumption of a normal distribution
        %     %
        %     % Input:
        %     %   iLength:        Scalar, integer, calculation period
        %     %                   (default = 90)
        %     %   iOffset:        Scalar, integer, number of periods to skip
        %     %                   (default = 0)
        %     %   iMinPeriods:    Scalar, integer, minimum number of periods
        %     %                   (default = 30)
        %     %   dAlpha:         Scalar, double, significance level
        %     %                   (default = 0.05)
        %     % 
        %     % Output:
        %     %   mES:            T x N matrix of expected shortfall
        %     %                   T: number of time-series observations
        %     %                   N: number of assets
        % 
        %     % Set default arguments
        %     arguments
        %         self 
        %         iLength (1,1) double = 90
        %         iOffset (1,1) double = 0
        %         iMinPeriods (1,1) double = 30
        %         dAlpha (1,1) double = 0.05
        %     end
        % 
        %     % Reset minimum number of observations
        %     iMinPeriods = min(iLength, iMinPeriods);
        % 
        %     % Preallocate memory
        %     mES         = NaN(self.iNumObs, self.iNumAssets);
        %     for iIdxT = iLength:self.iNumObs
        %         % Get in-sample data
        %         vIdxInSample    = (iIdxT-iLength+1):(iIdxT-iOffset);
        % 
        %         % Get data
        %         mRetTemp        = self.mReturns(vIdxInSample,:);
        %         lValid          = sum(~isnan(mRetTemp),1) >= iMinPeriods;
        % 
        %         % Get mean and standard deviation
        %         vMean           = mean(mRetTemp(:,lValid),1, 'omitnan');
        %         vStd            = std(mRetTemp(:,lValid),[],1,'omitnan');
        %         vStdH           = vStd * sqrt(iLength/365);
        % 
        %         % Calculate expected shortfall
        %         mES(iIdxT,lValid)  = dAlpha.^(-1) * normpdf(norminv(dAlpha)) .* vStdH - vMean;
        %     end
        % end

        function mNCSkew = fNCSkew(self, iLength, iOffset, iMinPeriods)
            % Function for calculating the negative coefficient of skewness
            %
            % Input:
            %   iLength:        Scalar, integer, calculation period
            %   iOffset:        Scalar, integer, number of periods to skip
            %   iMinPeriods:    Scalar, integer, minimum number of periods
            %
            % Output:
            %   mNCSkew:        N x T matrix of negative coefficients of
            %                   skewness
            %                   N: number of assets
            %                   T: number of time-series observations
            
            % Set default arguments
            arguments
                self 
                iLength (1,1) double = 30
                iOffset (1,1) double = 0
                iMinPeriods (1,1) double = 20
            end

            % Reset minimum number of observations
            iMinPeriods = min(iLength, iMinPeriods);

            % Preallocate memory
            mNCSkew = NaN(self.iNumObs, self.iNumAssets);
            for iIdxT = iLength:self.iNumObs
                % Get in-sample data
                vIdxInSample = (iIdxT-iLength+1):(iIdxT-iOffset);

                % Get data
                mRetTemp = self.mReturns(vIdxInSample,:);
                lValid = sum(~isnan(mRetTemp), 1) >= iMinPeriods;
                mRetTemp(:,~lValid) = [];

                % Demean returns
                mRetTemp = mRetTemp - mean(mRetTemp, 1, 'omitnan');

                % Number of nonmissing observations
                vNumObs = sum(~isnan(mRetTemp),1);

                % Calculate negative coefficient of skewness
                mNCSkew(iIdxT,lValid) = -(vNumObs.*(vNumObs-1).^(1.5) .* sum(mRetTemp.^3,1,'omitnan')) ./ ...
                      ((vNumObs-1).*(vNumObs-2).*sum(mRetTemp.^2,1,'omitnan').^(1.5)); 
            end
            mNCSkew(isinf(mNCSkew)) = NaN;
        end

        function mDUVOL = fDownUpVolatility(self, iLength, iOffset, iMinPeriods)
            % Function for calculating the down-up volatility as in Chen et
            % al. (2001)
            %
            % Input:
            %   iLength:        Scalar, integer, calculation period
            %   iOffset:        Scalar, integer, number of periods to skip
            %   iMinPeriods:    Scalar, integer, minimum number of periods

            % Set default arguments
            arguments
                self 
                iLength (1,1) double = 30
                iOffset (1,1) double = 0
                iMinPeriods (1,1) double = 20
            end
    
            % Reset minimum number of observations
            iMinPeriods = min(iLength, iMinPeriods);

            % Preallocate memory
            mDUVOL = NaN(self.iNumObs, self.iNumAssets);
            for iIdxT = iLength:self.iNumObs
                % Get in-sample data
                vIdxInSample = (iIdxT-iLength+1):(iIdxT-iOffset);

                % Get data
                mRetTemp = self.mReturns(vIdxInSample,:);

                % Remove assets with insufficient return data
                lNotValid = sum(~isnan(mRetTemp), 1) < iMinPeriods;
                mRetTemp(:,lNotValid) = [];

                % Calculate the period mean
                mAvgRet = repmat(mean(mRetTemp, 1, 'omitnan'), length(vIdxInSample), 1);

                % Calculate the volatility of all days below the mean
                mRetDown = mRetTemp; 
                mRetDown(mRetDown > mAvgRet) = NaN;
                vDownVola = std(mRetDown, [], 1, 'omitnan');

                % Calculate the volatility of all days above the mean
                mRetUp = mRetTemp; 
                mRetUp(mRetUp <= mAvgRet) = NaN;
                vUpVola = std(mRetUp, [], 1, 'omitnan');

                % Calculate log ratio
                mDUVOL(iIdxT, ~lNotValid) = log(vDownVola./vUpVola);
            end
            mDUVOL(isinf(mDUVOL)) = NaN;
        end

        function [mVaR, mES] = fVaR(self, iLength, iOffset, iMinPeriods, dAlpha)
            % Returns the value-at-risk and expected shortfall
            %
            % Input:
            %   iLength:        Scalar, integer, calculation period
            %                   (default = 90)
            %   iOffset:        Scalar, integer, number of periods to skip
            %                   (default = 0)
            %   iMinPeriods:    Scalar, integer, minimum number of periods
            %                   (default = 30)
            %   dAlpha:         Scalar, double, significance level
            %                   (default = 0.05)
            %
            % Output:
            %   mVaR:           T x N matrix of VaR
            %   mES:            T x N matrix of expected shortfall
            
            % Set default arguments
            arguments
                self 
                iLength (1,1) double = 90
                iOffset (1,1) double = 0
                iMinPeriods (1,1) double = 30
                dAlpha (1,1) double = 0.05
            end

            % Reset minimum number of observations
            iMinPeriods = min(iLength, iMinPeriods);

            % Preallocate memory
            mVaR = NaN(self.iNumObs, self.iNumAssets);
            mES  = NaN(self.iNumObs, self.iNumAssets);
            for iIdxT = iLength:self.iNumObs
                % Get in-sample data
                vIdxInSample    = (iIdxT-iLength+1):(iIdxT-iOffset);

                % Get data
                mRetTemp        = self.mReturns(vIdxInSample,:);
                lValid          = sum(~isnan(mRetTemp),1) >= iMinPeriods;

                % Get percentile
                vPercentile     = quantile(mRetTemp(:,lValid), dAlpha, 1);
                
                % Calculate value-at-risk
                mVaR(iIdxT,lValid)  = vPercentile;

                % Calculate expected shortfall, i.e., mean of losses below
                % the percentile

                % Get tail losses
                mTailLosses = mRetTemp(:,lValid);
                lIsBelow    = mTailLosses < vPercentile;
                mTailLosses(~lIsBelow) = NaN; % Now only returns below percentile

                % Calculate mean of tail losses
                mES(iIdxT,lValid)   = mean(mTailLosses,1,'omitmissing');
            end
        end

        function [mVol, mSkew] = fVolatility(self, iLength, iOffset, iMinPeriods)
            % Function for calculating the return volatility over a
            % given period
            %
            % Input:
            %   iLength:        Scalar, integer, calculation period
            %   iOffset:        Scalar, integer, number of periods to skip
            %   iMinPeriods:    Scalar, integer, minimum number of periods
            %                   (default = 5)
            %
            % Output:
            %   mVol:           N x T matrix of asset volatilities
            %                   N: number of assets
            %                   T: number of time-series observations

            % Set default arguments
            arguments
                self 
                iLength (1,1) double = 30
                iOffset (1,1) double = 0
                iMinPeriods (1,1) double = 20
            end
            
            % Reset minimum number of periods
            iMinPeriods = min(iLength, iMinPeriods);

            % Preallocate memory
            mVol        = NaN(self.iNumObs, self.iNumAssets);
            mSkew       = NaN(self.iNumObs, self.iNumAssets);
            for iIdxT = iLength:self.iNumObs
                % Get in-sample data
                vIdxInSample = (iIdxT-iLength+1):(iIdxT-iOffset);

                % Get data
                mRetTemp = self.mReturns(vIdxInSample,:);
                lValid = sum(~isnan(mRetTemp), 1) >= iMinPeriods;

                % Calculate return volatility
                mVol(iIdxT,lValid) = std(mRetTemp(:,lValid), [], 1, 'omitnan');
                mSkew(iIdxT,lValid) = skewness(mRetTemp(:,lValid), [], 1);
            end
        end

        function mPPT = fProspectTheory(self, iLength, iOffset, iMinPeriods)
            % Function for calculating the prospect theory value as in:
            %
            % Barberis, Mukherjee, and Wang (2016): Prospect Theory and 
            %   Stock Returns: An Empirical Test, Review of Financial 
            %   Studies, 29(11), pp. 3068-3107.
            %
            % Chen, Lepori, Tai, Sung (2022): Explaining cryptocurrency 
            %   returns: A prospect theory perspective, Journal of 
            %   International Financial Markets, Institutions & Money, 79,
            %   101599
            %
            % Input:
            %   iLength:        Scalar, integer, calculation period
            %                   (default = 365)
            %   iOffset:        Scalar, integer, number of periods to skip
            %                   (default = 0)
            %   iMinPeriods:    Scalar, integer, minimum number of periods
            %                   (default = 250)
            % Output:
            %   mPPT:           N x T matrix of PPT values
            %                   N: number of assets
            %                   T: number of time-series observations

            % Check input arguments
            arguments
                self 
                iLength (1,1) double {mustBeNonempty} = 365
                iOffset (1,1) double {mustBeNonempty} = 0
                iMinPeriods (1,1) double {mustBeNonempty} = 250
            end
            
            % Reset minimum number of periods
            iMinPeriods = min(iLength, iMinPeriods);

            % Settings
            dAlpha  = 0.88;
            dLambda = 2.25;
            dGamma  = 0.61;
            dDelta  = 0.69;

            % Preallocate memory
            mPPT    = NaN(self.iNumObs, self.iNumAssets);

            for iIdxT = iLength:self.iNumObs
                % Get in-sample data
                vIdxInSample = (iIdxT-iLength+1):(iIdxT-iOffset);

                % Get data
                mRetTemp    = self.mReturns(vIdxInSample,:);
                vMktRetTemp = self.vMktRet(vIdxInSample);

                % Remove data with insufficient observations
                lValid      = sum(~isnan(mRetTemp), 1) >= iMinPeriods;
                vIdxValid   = find(lValid);
                mRetTemp(:,~lValid) = [];

                % Determine number of observations
                [iNumObsTemp, iNumAssetsTemp] = size(mRetTemp); 

                % Loop over assets
                for iIdxA = 1:iNumAssetsTemp
                    % Get data
                    vY = mRetTemp(:,iIdxA);
                    vX = vMktRetTemp;

                    % Remove missing values
                    lIsNaN = isnan(vY) | isnan(vX);
                    vY(lIsNaN) = [];
                    vX(lIsNaN) = [];

                    % Regress return on market to get the return in excess
                    % of the market
                    vBeta = vX\vY;
                    vYhat = vY - vX * vBeta;

                    % Sort excess returns
                    vYsorted = sort(vYhat,'ascend');        

                    % Calculate V
                    vV = self.fProspectTheoryEq5(vYsorted, dAlpha, dLambda);

                    % Find positive and negative returns
                    lPositive = vYsorted >= 0;
                    lNegative = vYsorted <  0;

                    % Get positive and negative returns
                    vRetPos     = vYsorted(lPositive);
                    vRetNeg     = vYsorted(lNegative);
                    vVpos       = vV(lPositive);
                    vVneg       = vV(lNegative);

                    % Number of observations
                    iNumPos     = length(vRetPos);
                    iNumNeg     = length(vRetNeg);
                    iNumAll     = iNumPos + iNumNeg;

                    % Assign indices
                    vIdxNeg     = (-(iNumNeg:-1:1))';
                    vIdxPos     = (1:iNumPos)';

                    % Evaluate the negative W
                    [~,WnegA]   = self.fProspectTheoryEq6( (vIdxNeg + iNumNeg + 1)/iNumAll, dGamma, dDelta);
                    [~,WnegB]   = self.fProspectTheoryEq6( (vIdxNeg + iNumNeg)/iNumAll, dGamma, dDelta);
                    [WposA]     = self.fProspectTheoryEq6( (iNumPos - vIdxPos + 1)/iNumAll, dGamma, dDelta);
                    [WposB]     = self.fProspectTheoryEq6( (iNumPos - vIdxPos)/iNumAll, dGamma, dDelta);

                    % Calculate PPT
                    mPPT(iIdxT, vIdxValid(iIdxA)) = sum(vVneg .* (WnegA - WnegB)) + sum(vVpos .* (WposA - WposB));
                end
            end
        end

        function V = fProspectTheoryEq5(self, X, dAlpha, dLambda)
            % Implements Eq. 5 in Barberis, Mukherjee, and Wang (2016): 
            %   Prospect Theory and Stock Returns: An Empirical Test, 
            %   Review of Financial Studies, 29(11), pp. 3068-3107.

            % Copy X
            V = X;

            % Determine smaller or greater than 0
            lGreaterZero = X >= 0;
            lSmallerZero = X < 0;
            
            % Insert respective value for X > 0
            V(lGreaterZero) = V(lGreaterZero).^dAlpha;
            V(lSmallerZero) = -dLambda .* ( (-V(lSmallerZero)) .^dAlpha);
        end

        function [Wplus, Wminus] = fProspectTheoryEq6(self, P, dGamma, dDelta)
            % Implements Eq. 6 in Barberis, Mukherjee, and Wang (2016): 
            %   Prospect Theory and Stock Returns: An Empirical Test, 
            %   Review of Financial Studies, 29(11), pp. 3068-3107.

            Wplus   = (P.^dGamma)./(( P.^dGamma + (1-P).^dGamma ).^(1/dGamma));
            Wminus  = (P.^dDelta)./(( P.^dDelta + (1-P).^dDelta ).^(1/dDelta));
        end
        

        % === Helper functions
        function mPctChange = fPctChange(self, mData, iLength, iOffset)
            % Function for calculating the percentage change
            %
            % Input:
            %   mData:      T x N data matrix
            %               T: number of time-series observations
            %               N: number of assets
            %   iLength:    Scalar, integer, number of periods over which
            %               the percentage change should be calculated
            %   iOffset:    Scalar, integer, number of periods to skip
            %               before the current time tick t
            %
            % Output:
            %   mPctChange: T x N matrix of percentage changes
            %               T: number of time-series observations
            %               N: number of assets

            % Check inputs
            arguments
                self
                mData {mustBeNumeric}
                iLength (1,1) {mustBeNumeric, mustBeNonnegative}
                iOffset (1,1) {mustBeNumeric}
            end

            % Determine dimensions
            [iNumRows, iNumCols] = size(mData);

            % Shift matrices
            mDataLag    = [NaN(iLength, iNumCols); mData(1:end-iLength,:)];
            mDataToday  = [NaN(iOffset, iNumCols); mData(1:end-iOffset,:)];

            % Calculate percentage change
            mPctChange = (mDataToday./mDataLag) - 1;
        end

        function [mAvgVolume, mStdVolume] = fPrcVolumeLiu(self, iLength, iOffset, iMinPeriods, lUseLog, lPrcVol)
            % Returns the average trading volume in a given window
            %
            % Input:
            %   iLength:        Scalar, integer, calculation period
            %                   (default = 7)
            %   iOffset:        Scalar, integer, number of periods to skip
            %                   (default = 0)
            %   iMinPeriods:    Scalar, integer, minimum number of periods
            %                   with trading data
            %                   (default = 5)
            %   lUseLog:        Logical, specifies whether to calculate log
            %                   volume (default = false)
            %   lPrcVol:        Logical, specifies whether to calculate
            %                   volume as volumes * price (true, default)    
            %
            % Output:
            %   mAvgVolume:     T x N matrix, average trading volume 
            %                   T: number of time-series observations
            %                   N: number of assets
            
            % Set default arguments
            arguments
                self
                iLength (1,1) double = 7
                iOffset (1,1) double = 0
                iMinPeriods (1,1) double = 5
                lUseLog (1,1) logical = false
                lPrcVol (1,1) logical = true
            end

            % Epsilon for avoiding numerical issues ( log(0) = Inf ).
            % However, we do not want to exclude these observations because
            % a zero trading volume is also an information. For example,
            % an asset with zero volume should be in the lowest decile in
            % portfolio sorts. This is achieved by assigning a very small
            % value to the trading volume
            dEps = 1e-10;
            
            % Reset minimum number of periods
            iMinPeriods = min(iLength, iMinPeriods);

            % Get volume
            if lPrcVol
                % Note that this is an exact replication of Liu et al. to
                % better match their findings
                mVolume = self.mVol .* self.mPrice;
            else
                mVolume = self.mVol ./ self.mPrice;
            end
            
            % Preallocate memory
            mAvgVolume = NaN(self.iNumObs, self.iNumAssets);
            mStdVolume = NaN(self.iNumObs, self.iNumAssets);

            % Find start index
            iIdxFirstNonMissing = find(any(~isnan(self.mVol),2),1,'first');
            iIdxStart = max(iLength, iIdxFirstNonMissing + iMinPeriods-1);
            for iIdxT = iIdxStart:self.iNumObs
                % Get in-sample data
                vIdxInSample    = (iIdxT-iLength+1):(iIdxT-iOffset);

                % Get data
                mVolTemp        = mVolume(vIdxInSample,:);
                lValid          = sum(~isnan(mVolTemp),1) >= iMinPeriods;

                % Calculate average trading volume and standard deviation
                mAvgVolume(iIdxT,lValid) = mean(mVolTemp(:,lValid), 1, 'omitnan');
                mStdVolume(iIdxT,lValid) = std(mVolTemp(:,lValid), [], 1, 'omitnan');
            end   

            % To logarithm
            if lUseLog
                mAvgVolume = log(mAvgVolume + dEps);
                mStdVolume = log(mStdVolume + dEps);
            end
        end

        function mMaxRet = fMaxRet(self, iLength, iOffset, iMinPeriods)
            % Function for computing the maximum return over a given window
            %
            % Input:
            %   iLength:        Scalar, integer, calculation period
            %   iOffset:        Scalar, integer, number of periods to skip
            %
            % Output:
            %   mMaxPrc:        T x N matrix 

            % Set default arguments
            arguments
                self
                iLength (1,1) double = 7
                iOffset (1,1) double = 0
                iMinPeriods (1,1) double = 1
            end
            
            % Reset minimum number of observations
            iMinPeriods = min(iLength, iMinPeriods);

            % Preallocate memory
            mMaxRet = NaN(self.iNumObs, self.iNumAssets);

            % Find start index
            iIdxFirstNonMissing = find(any(~isnan(self.mPrice),2),1,'first');
            iIdxStart = max(iLength, iIdxFirstNonMissing + iMinPeriods-1);
            for iIdxT = iIdxStart:self.iNumObs
                % Get in-sample data
                vIdxInSample = (iIdxT-iLength+1):(iIdxT-iOffset);

                % Get data
                mRetTemp = self.mReturns(vIdxInSample, :);
                lValid = sum(~isnan(mRetTemp), 1) >= iMinPeriods;

                % Get maximum price
                mMaxRet(iIdxT, lValid) = max(mRetTemp(:,lValid), [], 1);
            end
        end

        function mST = fSalienceTheory(self, iLength, iOffset, iMinPeriods, dTheta, dGamma)
            % Function for calculating the salience theory value as in:
            %
            % Cosemans and Frehen (2021): Salience theory and stock prices: 
            %   Empirical evidence, Journal of Financial Economics, 140(2), 
            %   pp. 460-483.
            %
            % Chen, Lepori, Tai, Sung (2022): Can salience theory explain 
            %   investor behaviour? Real-world evidence from the 
            %   cryptocurrency market, International Review of Financial
            %   Analysis, Institutions & Money, 84, 102419
            %
            % Input:
            %   iLength:        Scalar, integer, calculation period
            %                   (default = 28)
            %   iOffset:        Scalar, integer, number of periods to skip
            %                   (default = 0)
            %   iMinPeriods:    Scalar, integer, minimum number of periods
            %                   (default = 250)
            % Output:
            %   mST:            N x T matrix of ST values
            %                   N: number of assets
            %                   T: number of time-series observations

            % Set default arguments
            arguments
                self
                iLength (1,1) double = 21
                iOffset (1,1) double = 0
                iMinPeriods (1,1) double = 14
                dTheta (1,1) double = 0.1
                dGamma (1,1) double = 0.7
            end
            
            % Reset minimum number of observations
            iMinPeriods = min(iLength, iMinPeriods);

            % Preallocate memory
            mST        = NaN(self.iNumObs, self.iNumAssets);

            % Loop over time
            for iIdxT = iLength:self.iNumObs
                % Get in-sample data
                vIdxInSample = (iIdxT-iLength+1):(iIdxT-iOffset);

                % Get data
                vMktIn      = self.vMktRet(vIdxInSample);
                mDataIn     = self.mReturns(vIdxInSample,:);

                % Remove assets with insufficient data
                lValid              = sum(~isnan(mDataIn), 1) >= iMinPeriods;
                % vIdxValid           = find(lValid);
                mDataIn(:,~lValid)  = [];

                % Calculate salience (Eq. 1 in Chen et al.)
                mSalience = abs(mDataIn - vMktIn)./(abs(mDataIn) + abs(vMktIn) + dTheta);

                % Rank 
                mRank       = tiedrank(-mSalience);
                mWtsTemp    = ones(size(mRank)) ./sum(~isnan(mRank),1);

                % Weights (Eq. 3 in Chen et al.)
                mWts = (dGamma.^mRank) ./ sum( (dGamma.^mRank) .* mWtsTemp,1,'omitmissing');

                % % Calculate covariance of weights with daily returns
                % iNumAssetsTemp = length(vIdxValid);
                % for iIdxA = 1:iNumAssetsTemp
                %     mCov = nancov(mWts(:,iIdxA), mDataIn(:,iIdxA));
                %     mST(iIdxT,vIdxValid(iIdxA)) = mCov(2,1);
                % end

                % Match missing values
                lIsNaN              = isnan(mWts)|isnan(mDataIn);
                mWts(lIsNaN)        = NaN;
                mDataIn(lIsNaN)     = NaN;

                % Center both matrices by subtracting the mean of each column
                mWts_C      = mWts - mean(mWts,1,'omitmissing');
                mDataIn_C   = mDataIn - mean(mDataIn,1,'omitmissing');

                % Calculate the covariance between corresponding columns
                vST = sum(mWts_C .* mDataIn_C,'omitmissing') ./ (sum(~lIsNaN,1) - 1);
                vST(all(lIsNaN,1))  = NaN; % Control for zeros inserted by sum('omitmissing')
                mST(iIdxT,lValid)   = vST;
            end
        end
    end
end