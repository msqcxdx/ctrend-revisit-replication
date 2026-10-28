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
end

% Determine dimensions
iNumPanelObs                    = length(vY);
[iNumPanelObsX, iNumIndepVars]  = size(mX);
iNumPanelObsID                  = length(mID);
iNumPanelObsW                   = length(vW);
vUniqueTimeID                   = unique(mID(:,1));
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

% Loop over time
for iIdxT = 1:iNumObs
    % Get current time step
    iIdxTime        = vUniqueTimeID(iIdxT);

    % Get data index
    lIsSampleData   = mID(:,1) == iIdxTime;

    % Skip if too few observations
    if sum(lIsSampleData) < rModel.iMinNumObsReg
        continue
    end

    % Get data
    vYtemp          = vY(lIsSampleData);
    mXtemp          = mX(lIsSampleData,:);
    if lValueWeightedLS
        vWtemp      = vW(lIsSampleData);
    end

    % Remove missing
    lIsNaN = isnan(vYtemp) | any(isnan(mXtemp),2);
    vYtemp(lIsNaN) = [];
    mXtemp(lIsNaN,:) = [];
    if lValueWeightedLS
        vWtemp(lIsNaN) = [];
    end

    % Regression 
    if lValueWeightedLS
        % Value-weighted least squares regression
        mXtW = (mXtemp .* vWtemp)';
        if rcond((mXtW * mXtemp)) < 1e-15
            mGamma(iIdxT,:) = pinv(mXtW * mXtemp) * (mXtW * vYtemp);
        else
            mGamma(iIdxT,:) = (mXtW * mXtemp)\(mXtW * vYtemp);
        end
    else
        % Ordinary least squares regression
        if rcond((mXtemp' * mXtemp)) < 1e-15
            mGamma(iIdxT,:) = pinv(mXtemp' * mXtemp) * (mXtemp' * vYtemp);  
        else
            mGamma(iIdxT,:) = mXtemp\vYtemp;  
        end
    end

    % Calculate the R2
    if ~rModel.lGammaOnly
        % Calculate fitted values
        vYfit       = mXtemp * mGamma(iIdxT,:)';

        % Calculate sum of squared residuals
        if lValueWeightedLS
            % Calculate sum of squared residuals
            dSSR        = sum( vWtemp .* (vYtemp - vYfit).^2 );

            % Calculate sum of squares
            dSSRmean    = sum( vWtemp .* (vYtemp - mean(vYtemp)).^2 );
        else
            % Calculate sum of squared residuals
            dSSR        = sum( (vYtemp - vYfit).^2 );

            % Calculate sum of squares
            dSSRmean    = sum( (vYtemp - mean(vYtemp)).^2 );
        end

        % Calculate R2
        vR2(iIdxT)  = 1 - (dSSR/dSSRmean);
    end
end

% Calculate average of gammas
vGamma          = mean(mGamma, 1, 'omitnan');
rModel.vGamma   = vGamma;
rModel.mGamma   = mGamma;

% Calculate standard deviation, t-statistics, and p-values
if ~rModel.lGammaOnly
    if rModel.iNumLagsNW == 0
        % Uncorrected standard errors
        vGammaSE = std(mBeta,[],1,'omitnan') ./ sqrt(sum(~isnan(mGamma),1));
        vGammaT = vGamma./vGammaSE;

    else
        % Corrected standard errors
        vGammaSE = NaN(1, iNumIndepVars);
        for iIdxV = 1:iNumIndepVars
            [~,vGammaSE(iIdxV)] = hac(ones(iNumObs,1),mGamma(:,iIdxV),'intercept',false,...
                'bandwidth',rModel.iNumLagsNW, 'display', 'off');
        end

        % t-Statistic
        vGammaT = vGamma./(vGammaSE); 
    end

    % Save results
    rModel.vGammaSE     = vGammaSE;
    rModel.vGammaT      = vGammaT;
    rModel.vGammaP      = 2 * (tcdf(-abs(vGammaT),sum(~isnan(mGamma),1)));
    rModel.vR2          = vR2;
end
end