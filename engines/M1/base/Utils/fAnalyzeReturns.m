function rStats     = fAnalyzeReturns(mRet, dim, nanflag, mIndepVars, lRobustSE)
% Function for analyzing risk and return of return series
%
% Input:
%   mRet:           T x N or N x T matrix of returns
%                   T: number of time-series observations
%                   N: number of assets
%   dim:            Scalar, integer, specifies the dimension along to
%                   operate
%
% Output:
%   rStats:         Struct, containing N x 1 vectors of statistics
%       .vAvgRet:       average return
%       .vAvgRetT:      t-statistic of return series

% Check inputs
arguments
    mRet (:,:,:) {mustBeNumeric} 
    dim (1,1) {mustBeNumeric, mustBePositive} = 1
    nanflag string = 'omitnan'
    mIndepVars (:,:) {mustBeNumeric} = []
    lRobustSE (1,1) {mustBeNumericOrLogical} = false;
end

% The old optional bootstrap path calls a function that is not included in
% the published package and does not define a reproducible paper estimator.
% Corrected reports one supported convention and fails explicitly rather
% than reaching an undefined function.
assert(~logical(lRobustSE), ...
    ['lRobustSE is unsupported: the old bootstrap implementation is absent ' ...
     'and robustness variants are not part of the corrected main result']);
assert(dim == 1 || dim == 2, 'Analysis dimension must be 1 or 2');

% Determine dimension
if dim == 1
    [iNumObs, iNumAssets, iNumThird] = size(mRet);
elseif dim == 2
    [iNumAssets, iNumObs, iNumThird] = size(mRet);
end

if ~isempty(mIndepVars)
    if dim == 1
        [iNumObsI, iNumIndepVars, iNumMdls] = size(mIndepVars);
    elseif dim == 2
        [iNumIndepVars, iNumObsI, iNumMdls] = size(mIndepVars);
    end
    assert(iNumObs == iNumObsI, 'Number of time-series observations must agree');
end


% Calculate mean and standard deviation
rStats.vAvgRet              = mean(mRet, dim, nanflag);
rStats.vStdRet              = std(mRet, [], dim, nanflag);

% t-Test
[~,~,~,stats]        = ttest(mRet, [], "Dim",dim);
rStats.vAvgRetT       = stats.tstat;

% Calculate Sharpe ratio 
rStats.vShp     = rStats.vAvgRet ./ rStats.vStdRet;

% Test statistic of Sharpe ratio
vNumObs         = sum(~isnan(mRet),dim);
rStats.vShpT    = rStats.vShp ./ sqrt((1 + 0.5 * rStats.vShp.^2)./vNumObs);

% Calculate skewness and kurtosis
if strcmpi(nanflag, 'omitnan') && any(isnan(mRet),'all') 
    % Initialize memory
    if dim ==1
        rStats.vSkewness = NaN(1, iNumAssets, iNumThird);
        rStats.vKurtosis = NaN(1, iNumAssets, iNumThird);
    else
        rStats.vSkewness = NaN(iNumAssets, 1, iNumThird);
        rStats.vKurtosis = NaN(iNumAssets, 1, iNumThird);
    end

    % Loop over assets
    for iIdxT = 1:iNumThird
    for iIdxA = 1:iNumAssets
        % Get return series
        if dim == 1
            vYtemp = mRet(:,iIdxA,iIdxT);
        elseif dim == 2
            vYtemp = permute(mRet(iIdxA,:,iIdxT),[2,3,1]);
        end

        % Remove nan
        vYtemp(isnan(vYtemp)) = [];

        % Calculate skewness and kurtosis
        if dim == 1
            rStats.vSkewness(:,iIdxA,iIdxT) = skewness(vYtemp, [], 1);
            rStats.vKurtosis(:,iIdxA,iIdxT) = kurtosis(vYtemp, [], 1);
        else
            rStats.vSkewness(iIdxA,:,iIdxT) = skewness(vYtemp, [], 1);
            rStats.vKurtosis(iIdxA,:,iIdxT) = kurtosis(vYtemp, [], 1);
        end
    end   
    end
else
    rStats.vSkewness = skewness(mRet, [], dim);
    rStats.vKurtosis = kurtosis(mRet, [], dim);
end

% Calculate maximum drawdown
rStats.vMaxDD = fMaxDD(mRet, dim);

% Calculate alphas
if ~isempty(mIndepVars)
    % Initialize memory
    vAlpha      = NaN(iNumMdls, iNumAssets, iNumThird);
    vAlphaT     = NaN(iNumMdls, iNumAssets, iNumThird);
    vAlphaT_hac = NaN(iNumMdls, iNumAssets, iNumThird);
    mBeta       = NaN(iNumMdls, iNumAssets, iNumIndepVars, iNumThird);
    mBetaT      = NaN(iNumMdls, iNumAssets, iNumIndepVars, iNumThird);
    mBetaT_hac  = NaN(iNumMdls, iNumAssets, iNumIndepVars, iNumThird);

    % Loop over models
    for iIdxM = 1:iNumMdls
        % Loop over return series
        for iIdxT = 1:iNumThird
        for iIdxA = 1:iNumAssets
            % Get return series
            if dim == 1
                vPortRet = mRet(:,iIdxA,iIdxT);
                mXtemp   = mIndepVars(:,:,iIdxM);
            elseif dim == 2
                vPortRet = mRet(iIdxA,:,iIdxT)';
                mXtemp   = mIndepVars(:,:,iIdxM)';
            end

            % Estimate coefficients on the common finite observations while
            % retaining original calendar positions for HAC lag products.
            lValidReg = isfinite(vPortRet) & all(isfinite(mXtemp),2);
            if sum(lValidReg) <= size(mXtemp,2) + 1
                continue
            end
            rRegResults = fOLSNeweyWestCalendar(vPortRet,mXtemp);
            if any(~isfinite(rRegResults.vBeta))
                continue
            end
            % Save coefficients
            vAlpha(iIdxM,iIdxA,iIdxT)       = rRegResults.vBeta(1);
            mBeta(iIdxM,iIdxA,:,iIdxT)      = rRegResults.vBeta(2:end);
            
            % Save hac t-Statistics
            vAlphaT_hac(iIdxM,iIdxA,iIdxT)  = rRegResults.vTHAC(1);
            mBetaT_hac(iIdxM,iIdxA,:,iIdxT) = rRegResults.vTHAC(2:end);

            % Save conventional t-statistics. Calendar-aware HAC statistics
            % are stored separately above.
            vAlphaT(iIdxM,iIdxA,iIdxT)      = rRegResults.vT(1);
            mBetaT(iIdxM,iIdxA,:,iIdxT)     = rRegResults.vT(2:end);
        end
        end
    end

    % Save results
    rStats.vAlpha       = vAlpha;
    rStats.vAlphaT      = vAlphaT;
    rStats.vAlphaT_hac  = vAlphaT_hac;
    rStats.mBeta        = mBeta;
    rStats.mBetaT       = mBetaT;
    rStats.mBetaT_hac   = mBetaT_hac;
end
end
