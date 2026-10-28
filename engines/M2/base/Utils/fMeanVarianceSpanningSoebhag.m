function rResults = fMeanVarianceSpanningSoebhag(mY, mX, options)
% Function for implementing the mean-variance spanning test as proposed in
% Soebhag, van Vliet, and Verwijmeren (2023)
%
% Tests whether the span of the efficient frontier spanned by the factors Y
% can be improved by adding the factors X. The function also performs a
% reversed test, testing whether adding Y to X improves the performance of X
%
% Input:
%   mY:             T x N matrix of test factors
%                   T: number of time-series observations
%                   N: number of test factors
%   mX:             T x K matrix of benchmark factors
%                   T: number of time-series observations
%                   K: number of benchmark factors
%   options:        'Name-Value' pair arguments
%       .iNumIn:            Scalar, integer, number of in-sample periods
%                           (default = 52)
%       .lRoll:             Logical, specifies whether to estimate using a
%                           rolling (true, default) or expanding (false) 
%                           time window
%       .dTargetVol:        Scalar, double, specifies the target volatility
%                           (default = NaN)
%
% Output:
%   rResults:       Struct, containing the results
%       .vBeta:         2 x 1 vector containing the intercept (i.e.,
%                       generalized alpha) and the regression beta
%       .vBetaT:        2 x 1 vector, t-statistics
%       .vBetaT_hac:    2 x 1 vector, Newey-West corrected t-statistics

% Check inputs
arguments
    mY {mustBeNumeric}
    mX {mustBeNumeric}
    options.iNumIn (1,1) {mustBeNumeric} = 52;
    options.lRoll (1,1) {mustBeNumericOrLogical} = true;
    options.dTargetVol (1,1) {mustBeNumeric} = NaN;
end

% Determine dimensions
[iNumObs, iNumFactY]    = size(mY);
[iNumObsX, iNumFactX]   = size(mX);

% Check dimensions
assert(iNumObs == iNumObsX, 'Number of time-series observations must agree');

% Remove missing values
lIsNaN          = any(isnan(mY), 2) | any(isnan(mX), 2);
mY(lIsNaN,:)    = [];
mX(lIsNaN,:)    = [];

% Determine dimensions
iNumObs         = size(mY,1);

% Initialize memory
vTangPortY      = NaN(iNumObs, 1);
vTangPortX      = NaN(iNumObs, 1);
vTangPortXY     = NaN(iNumObs, 1);

% Iterate through time
for iIdxT = options.iNumIn:iNumObs-1
    % Get indices
    if options.lRoll
        vIdxInSample = (iIdxT-options.iNumIn+1):iIdxT;
    else
        vIdxInSample = 1:iIdxT;
    end
    vIdxOutOfSample = (iIdxT+1);

    % Get data
    mYin    = mY(vIdxInSample,:);
    mYout   = mY(vIdxOutOfSample,:);
    mXin    = mX(vIdxInSample,:);
    mXout   = mX(vIdxOutOfSample,:);

    % Remove assets for which the return is always zero
    lIsZero             = all(mYin == 0,1);
    mYin(:,lIsZero)     = [];
    mYout(:,lIsZero)    = [];

    % Estimate tangency portfolio using test factors
    vTangPortY(vIdxOutOfSample) = fEstEvalTangPort(mYin, mYout, options.dTargetVol);

    % Estimate tangency portfolio using benchmark factors
    vTangPortX(vIdxOutOfSample) = fEstEvalTangPort(mXin, mXout, options.dTargetVol);

    % Estimate tangency portfolio using test and benchmark factors
    vTangPortXY(vIdxOutOfSample) = fEstEvalTangPort([mYin, mXin], [mYout, mXout], options.dTargetVol);
end

% Calculate Sharpe ratios
[rResults.dShp_Y, rResults.dShpT_Y]     = fSharpeRatio(vTangPortY, 0, 1, 0);
[rResults.dShp_X, rResults.dShpT_X]     = fSharpeRatio(vTangPortX, 0, 1, 0);
[rResults.dShp_XY, rResults.dShpT_XY]   = fSharpeRatio(vTangPortXY, 0, 1, 0);

% Regression
rRegResults         = regstats2(vTangPortXY, vTangPortY, 'linear', {'tstat', 'hac'});
rRegResultsReverse  = regstats2(vTangPortXY, vTangPortX, 'linear', {'tstat', 'hac'});

% Save statistics
rResults.vBeta      = rRegResults.tstat.beta;
rResults.vBetaT     = rRegResults.tstat.t;
rResults.vBetaT_hac = rRegResults.hac.t;
rResults.vBetaP     = rRegResults.tstat.pval;
rResults.vBetaP_hac = rRegResults.hac.pval;
rResults.vTheta     = rRegResultsReverse.tstat.beta;
rResults.vThetaT    = rRegResultsReverse.tstat.t;
rResults.vThetaT_hac= rRegResultsReverse.hac.t;
rResults.vThetaP_hac= rRegResultsReverse.tstat.pval;
rResults.vThetaP_hac= rRegResultsReverse.hac.pval;
end