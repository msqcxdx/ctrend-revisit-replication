function rModel = fEstFamaMacBethPanel(vY, mX, mID, vW, rModel)
% Function for performing multivariate Fama-MacBeth regressions where data
% is stored in panel format.
%
% Note that it is assumed that independent variables are already lagged!
%
% Input:
%   vY:         (T * N) x 1 vector of the dependent variable
%               T: number of time-series observations
%               N: number of objects
%   mX:         (T * N) x K matrix of the independent variables
%               T: number of time-series observations
%               N: number of objects
%               K: number of independent variables
%   mID:        (T * N) x 2 matrix. First column indicates the time ID and
%               second column refers to the object ID
%               T: number of time-series observations
%               N: number of objects
%   vW:         (T * N) x 1 vector of observation weights
%               T: number of time-series observations
%               N: number of objects
%   rModel:     Name-Value pair arguments
%       'lEstAlpha':        Logical, specifies whether to estimate an
%                           intercept (default = true)
%       'iMinNumObsReg':    Scalar, integer, minimum number of observations
%                           for Fama-MacBeth regression (default = 10)
%       'lGammaOnly':       Logical, specifies whether to return only the gamma
%                           estimates (true) or gamma estimates and additional
%                           statistics (false, default)
%       'iNumLagsNW':       Scalar, integer, number of lags for Newey-West standard
%                           error correction (default = 12)
%       'vAllTimeID':       Complete ordered time axis. Empty cross-sections
%                           remain explicit NaN rows rather than compressing
%                           the Newey-West lag distance.
%
% Output:
%   rModel:                 Struct, containing the Name-Value pair
%                           arguments and the following fields
%       .vGamma:                1 x (lEstAlpha + K) vector of average gamma
%                               coefficients
%       .mGamma:                T x (lEstAlpha + K) matrix of estimated gamma
%                               coefficients
%       .vGammaSE:              1 x (lEstAlpha + K) vector of standard
%                               errors
%       .vGammaT:               1 x (lEstAlpha + K) vector of t-statistics
%       .vGammaP:               1 x (lEstAlpha + K) vector of p-values
%       .vR2:                   T x 1 vector of R2s

% Check input arguments
arguments
    vY (:,1) {mustBeNumeric}
    mX (:,:) {mustBeNumeric}
    mID (:,2) {mustBeNumeric, mustBeNonnegative}
    vW (:,1) {mustBeNumeric} = []
    rModel.lEstAlpha (1,1) {mustBeNumericOrLogical} = true
    rModel.iMinNumObsReg (1,1) {mustBeNumeric, mustBeNonnegative} = 10
    rModel.lGammaOnly (1,1) {mustBeNumericOrLogical, mustBeNonnegative} = false
    rModel.iNumLagsNW (1,1) {mustBeNumeric, mustBeNonnegative} = 12
    rModel.vAllTimeID (:,1) {mustBeNumeric, mustBeNonnegative} = []
end

% Determine dimensions
iNumPanelObs                    = length(vY);
[iNumPanelObsX, iNumIndepVars]  = size(mX);
iNumPanelObsID                  = size(mID,1);
iNumPanelObsW                   = length(vW);
if isempty(rModel.vAllTimeID)
    assert(logical(rModel.lGammaOnly) || rModel.iNumLagsNW == 0, ...
        ['Newey-West inference requires the complete calendar in ' ...
         'vAllTimeID; observed panel rows cannot identify empty weeks']);
    vUniqueTimeID = unique(mID(:,1));
else
    vUniqueTimeID = rModel.vAllTimeID(:);
    assert(numel(unique(vUniqueTimeID)) == numel(vUniqueTimeID) && ...
        all(diff(vUniqueTimeID) > 0), ...
        'vAllTimeID must contain unique, strictly increasing time IDs');
    assert(all(ismember(mID(:,1), vUniqueTimeID)), ...
        'Every observed panel time ID must occur in vAllTimeID');
end
iNumObs                         = length(vUniqueTimeID);

% Check dimensions
assert(iNumPanelObs == iNumPanelObsX, 'Number of panel observations must agree (vY, mX)');
assert(iNumPanelObs == iNumPanelObsID, 'Number of panel observations must agree (vY, mID)');
if ~isempty(vW)
    assert(iNumPanelObs == iNumPanelObsW, 'Number of panel observations must agree (vY, vW)');
    lValueWeightedLS = true;
else
    lValueWeightedLS = false;
end

% Add constant to the independent variables if requested
mX = [ones(iNumPanelObs, rModel.lEstAlpha), mX];

% Initialize memory
iNumIndepVars   = iNumIndepVars + rModel.lEstAlpha;
mGamma          = NaN(iNumObs, iNumIndepVars);
vR2             = NaN(iNumObs, 1);
vNumObsByTime   = NaN(iNumObs, 1);

% Loop over time
for iIdxT = 1:iNumObs
    % Get current time step
    iIdxTime        = vUniqueTimeID(iIdxT);

    % Get data index
    lIsSampleData   = mID(:,1) == iIdxTime;

    % Get data
    vYtemp          = vY(lIsSampleData);
    mXtemp          = mX(lIsSampleData,:);
    if lValueWeightedLS
        vWtemp      = vW(lIsSampleData);
    end

    % Remove missing
    lIsNaN = ~isfinite(vYtemp) | any(~isfinite(mXtemp),2);
    if lValueWeightedLS
        lIsNaN = lIsNaN | ~isfinite(vWtemp) | vWtemp < 0;
    end
    vYtemp(lIsNaN) = [];
    mXtemp(lIsNaN,:) = [];
    if lValueWeightedLS
        vWtemp(lIsNaN) = [];
    end
    vNumObsByTime(iIdxT) = length(vYtemp);

    % Skip if too few usable observations remain after missing-value filters.
    if length(vYtemp) < max(rModel.iMinNumObsReg, iNumIndepVars)
        continue
    end

    % Require an identified cross-sectional regression.  Solve after column
    % normalization so raw market-cap units cannot make rank() and backslash
    % apply inconsistent numerical tolerances.
    if lValueWeightedLS
        if sum(vWtemp) <= 0
            continue
        end
        mXsolve = mXtemp .* sqrt(vWtemp);
        vYsolve = vYtemp .* sqrt(vWtemp);
    else
        mXsolve = mXtemp;
        vYsolve = vYtemp;
    end
    [vGammaTemp,lIdentified] = ...
        fSolveFullRankLeastSquares(mXsolve,vYsolve);
    if ~lIdentified
        continue
    end
    mGamma(iIdxT,:) = vGammaTemp';

    % Calculate the R2
    if ~rModel.lGammaOnly
        % Calculate fitted values
        vYfit       = mXtemp * mGamma(iIdxT,:)';

        % Calculate sum of squared residuals
        if lValueWeightedLS
            % Calculate sum of squared residuals
            dSSR        = sum( vWtemp .* (vYtemp - vYfit).^2 );

            % Calculate sum of squares
            dWeightedMean = sum(vWtemp .* vYtemp) / sum(vWtemp);
            dSSRmean    = sum( vWtemp .* (vYtemp - dWeightedMean).^2 );
        else
            % Calculate sum of squared residuals
            dSSR        = sum( (vYtemp - vYfit).^2 );

            % Calculate sum of squares
            dSSRmean    = sum( (vYtemp - mean(vYtemp)).^2 );
        end

        % Calculate R2
        if isfinite(dSSRmean) && dSSRmean > 0
            vR2(iIdxT) = 1 - (dSSR/dSSRmean);
        end
    end
end

% Calculate average of gammas
vGamma          = mean(mGamma, 1, 'omitnan');
rModel.vGamma   = vGamma;
rModel.mGamma   = mGamma;
rModel.vNumObsByTime = vNumObsByTime;

% Calculate standard deviation, t-statistics, and p-values
if ~rModel.lGammaOnly
    if rModel.iNumLagsNW == 0
        % Uncorrected standard errors
        vGammaSE = std(mGamma,[],1,'omitnan') ./ sqrt(sum(isfinite(mGamma),1));
        vGammaT = NaN(size(vGamma));
        lDefinedSE = isfinite(vGammaSE) & vGammaSE > 0 & isfinite(vGamma);
        vGammaT(lDefinedSE) = vGamma(lDefinedSE)./vGammaSE(lDefinedSE);

    else
        % Newey-West standard errors for the mean gamma. Keep the original
        % weekly time spacing when an individual cross-section is missing;
        % deleting those rows would compress lags and change the estimator.
        vGammaSE = NaN(1, iNumIndepVars);
        for iIdxV = 1:iNumIndepVars
            vGammaSE(iIdxV) = iNeweyWestMeanSE( ...
                mGamma(:,iIdxV), rModel.iNumLagsNW);
        end

        % t-Statistic
        vGammaT = NaN(size(vGamma));
        lDefinedSE = isfinite(vGammaSE) & vGammaSE > 0 & isfinite(vGamma);
        vGammaT(lDefinedSE) = vGamma(lDefinedSE)./vGammaSE(lDefinedSE);
    end

    % Save results
    rModel.vGammaSE     = vGammaSE;
    rModel.vGammaT      = vGammaT;
    vNumGamma           = sum(isfinite(mGamma),1);
    rModel.vGammaP      = NaN(size(vGammaT));
    lValidP             = vNumGamma > 1;
    rModel.vGammaP(lValidP) = 2 * (tcdf(-abs(vGammaT(lValidP)), vNumGamma(lValidP) - 1));
    rModel.vR2          = vR2;
end
end

function dSE = iNeweyWestMeanSE(vSeries, iNumLags)
lValid = isfinite(vSeries);
iNumValid = sum(lValid);
dSE = NaN;
if iNumValid <= 1
    return
end
dMean = mean(vSeries(lValid));
vU = vSeries - dMean;
vU(~lValid) = 0;
dLongRunSum = sum(vU.^2);
iMaxLag = min(iNumLags, numel(vSeries)-1);
for iLag = 1:iMaxLag
    lPair = lValid(1+iLag:end) & lValid(1:end-iLag);
    dCross = sum(vU(1+iLag:end) .* vU(1:end-iLag) .* lPair);
    dBartlett = 1 - iLag/(iMaxLag+1);
    dLongRunSum = dLongRunSum + 2*dBartlett*dCross;
end
dVariance = dLongRunSum/(iNumValid^2);
if isfinite(dVariance) && dVariance >= 0
    dSE = sqrt(dVariance);
end
end
