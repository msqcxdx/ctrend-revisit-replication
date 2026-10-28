function rResults = fDepDoubleSort(mSortVarA, mSortVarB, mRet, mIndepVars, mMV, options)
% Function for performing dependent double sorts based on two sort variables
%
% Note that this function requires that the sorting variables are in t 
% (or based on information up to t) and the returns are in t+1. This
% function won't perform any lagging
%
% Input:
%   mSortVarA:          N x T matrix of the first sorting variable
%                       N: number of responses
%                       T: number of time-series observations
%   mSortVarB:          N x T matrix of the second sorting variable
%                       N: number of responses
%                       T: number of time-series observations
%   mRet:               N x T matrix of returns 
%                       N: number of responses
%                       T: number of time-series observations
%   mIndepVars:         K x T matrix of independent variables for regressing
%                       portfolio returns on these variables
%   mMV:                N x T matrix of market capitalization
%                       N: number of responses
%                       T: number of time-series observations
%   options:            Name-Value pair arguments
%       'vPercentileA':     (P + 1) x 1 vector of percentiles for sorts with
%                           respect to first sorting variable
%                           (default = 0:0.5:1)
%       'vPercentileB':     (P* + 1) x 1 vector of percentiles for sorts with
%                           respect to second sorting variable
%                           (default = 0:0.5:1)
%       'iMinNumCS':        Scalar, integer, minimum size of cross-section
%                           (default = 1)
%       'iMinNumAssets':    Scalar, integer, minimum number of assets per
%                           portfolio (default = 1)
%       'lEnsureAllObs':    Logical, specifies whether to require the
%                           formation-time sorting variables (and market
%                           value) prior to percentile calculation. Future
%                           realized-return availability is never a filter
%                           (default = true)
%       'sFreq':            String or char, specifies the data frequency
%                           (default = 'monthly')
% 
% Output:
%   rResults:       Struct, containing the results
%       .EW:            Struct, containing results for equal-weighted
%                       portfolios
%       .VW:            Struct, containing results for value-weighted
%                       portfolios

%% Check inputs
arguments
    mSortVarA (:,:) {mustBeNumeric}
    mSortVarB (:,:) {mustBeNumeric}
    mRet (:,:) {mustBeNumeric}
    mIndepVars (:,:) {mustBeNumeric} = []
    mMV (:,:) {mustBeNumeric} = []
    options.vPercentileA (:,1) {mustBeNumeric, mustBeNonnegative} = (0:0.5:1)'
    options.vPercentileB (:,1) {mustBeNumeric, mustBeNonnegative} = (0:0.5:1)'
    options.iMinNumCS (1,1) {mustBeNumeric, mustBeNonnegative} = 1
    options.iMinNumAssets(1,1) {mustBeNumeric, mustBeNonnegative} = 1
    options.lEnsureAllObs (1,1) {mustBeNumericOrLogical, mustBeNonnegative} = true   
    options.sFreq char = 'monthly'
    options.mUniverse (:,:) {mustBeNumericOrLogical} = []
    options.rReinvestmentLedger (1,1) struct = struct()
    options.vLedgerWeekRow (:,1) {mustBeNumeric} = []
    options.sPayoffTiming char = ''
end

% Get dimensions
[iNumResp, iNumObs]     = size(mSortVarA);
[iNumRespB, iNumObsB]   = size(mSortVarB);
[iNumRespY, iNumObsY]   = size(mRet);

% Check dimensions
assert(iNumResp == iNumRespB, 'Number of response variables must agree (VarA, VarB)');
assert(iNumResp == iNumRespY, 'Number of response variables must agree (VarA, mRet)');
assert(iNumObs == iNumObsB, 'Number of time-series observations must agree (VarA, VarB)');
assert(iNumObs == iNumObsY, 'Number of time-series observations must agree (VarA, mRet)');
if ~isempty(mMV)
    assert(iNumResp == size(mMV,1),'Number of response variables must agree (VarA, mMV)');
    assert(iNumObs == size(mMV,2),'Number of time-series observations must agree (VarA, mMV)');
end
if ~isempty(mIndepVars)
    [iNumIndepVars, iNumObsK] = size(mIndepVars);
    assert(iNumObs == iNumObsK,'Number of time-series observations must agree (A, mIndepVars)');
end
lUniverse = fValidateUniverseMask(options.mUniverse,iNumResp,iNumObs);
lLedgerFields = [~isempty(fieldnames(options.rReinvestmentLedger)), ...
    ~isempty(options.vLedgerWeekRow),~isempty(options.sPayoffTiming)];
assert(all(lLedgerFields) || ~any(lLedgerFields), ...
    'Dependent-sort reinvestment options must be supplied together');
lUseSameLegReinvestment = all(lLedgerFields);
if lUseSameLegReinvestment
    assert(ismember(options.sPayoffTiming,{'ordinary','lead1'}), ...
        'Unknown economic payoff timing');
end
mSortVarA(~lUniverse) = NaN;
mSortVarB(~lUniverse) = NaN;
if ~isempty(mMV)
    mMV(~lUniverse) = NaN;
end

% Require sorting variables, known target tradability and market value. A
% missing economic payoff removes the unavailable asset before breakpoints;
% the payoff magnitude is not used.
if options.lEnsureAllObs
    lAvail = isfinite(mSortVarA) & isfinite(mSortVarB) & isfinite(mRet);

    if ~isempty(mMV)
        lAvail = lAvail & isfinite(mMV) & mMV > 0;
    end

    % Set non-available observations to missing
    mSortVarA(~lAvail) = NaN;
    mSortVarB(~lAvail) = NaN;
    if ~isempty(mMV)
        mMV(~lAvail) = NaN;
    end
end

% Require minimum size of cross-section
lAvail                   = isfinite(mSortVarA) & isfinite(mSortVarB) & ...
    isfinite(mRet);
if ~isempty(mMV)
    lAvail = lAvail & isfinite(mMV) & mMV > 0;
end
lRemoveTick              = sum(lAvail, 1) < options.iMinNumCS;
mSortVarA(:,lRemoveTick) = NaN;
mSortVarB(:,lRemoveTick) = NaN;

% Check if first sort variable is binary. Then there will be two portfolios
% based on variable A, e.g., 0 and 1
vUnique = unique(mSortVarA(isfinite(mSortVarA)));
if length(vUnique) == 2
    mPercentileA = ones(3, iNumObs) .* [0; 0.5; 1];
else
    % Otherwise, calculate percentiles
    mPercentileA = quantile(mSortVarA, options.vPercentileA);
end

% Percentiles for B will be defined depending on the portfolio constituents
% in the A portfolios

% Number of portfolios
iNumPortsA = size(mPercentileA,1) - 1;
iNumPortsB = length(options.vPercentileB) - 1;

% Preallocate memory
cPortRetsEW     = cell(iNumPortsA, iNumPortsB);     % Realized return for ew portfolios
cPortRetsVW     = cell(iNumPortsA, iNumPortsB);     % Realized return for vw portfolios
cValSortVarA_ew = cell(iNumPortsA, iNumPortsB);     % First sort variable
cValSortVarA_vw = cell(iNumPortsA, iNumPortsB);     % First sort variable
cValSortVarB_ew = cell(iNumPortsA, iNumPortsB);     % Second sort variable
cValSortVarB_vw = cell(iNumPortsA, iNumPortsB);     % Second sort variable

% Iterate over portfolios for first sorting variable
for iIdxA = 1:iNumPortsA
    % 1. Step: Create 0/1 indicator matrix if an asset is in current
    % portfolio
    if iIdxA == 1
        mIndx = double((mSortVarA <= mPercentileA(iIdxA+1,:))&(mSortVarA >= mPercentileA(iIdxA,:)));
    else
        mIndx = double((mSortVarA <= mPercentileA(iIdxA+1,:))&(mSortVarA > mPercentileA(iIdxA,:)));
    end

    % 0/1- to NaN/1-Matrix
    mIndx(mIndx==0) = NaN; % This will be used to set returns to missing if not in portfolio

    % Get returns and sorting variable of assets in portfolio P. Now we
    % will have variables mRetPortA, mSortVarA_A, mSortVarB_A that have only
    % observations for the returns and sorting variables if the respective
    % asset is in the current portfolio
    mRetPortA   = mRet .* mIndx;
    mSortVarA_A = mSortVarA .* mIndx;  
    mSortVarB_A = mSortVarB .* mIndx;

    % Get market value of these assets in portfolio P
    if ~isempty(mMV)
        mMvPort = mMV .* mIndx;
    end

    % Get percentiles of B within portfolio A
    mPercentileB = quantile(mSortVarB_A, options.vPercentileB);

    % Iterate over portfolios for second sorting variable
    for iIdxB = 1:iNumPortsB
        % 1. Step: Create 0/1 indicator matrix if a response is in current
        % portfolio
        if iIdxB == 1
            mIndxB = double((mSortVarB_A <= mPercentileB(iIdxB+1,:))&(mSortVarB_A >= mPercentileB(iIdxB,:)));
        else
            mIndxB = double((mSortVarB_A <= mPercentileB(iIdxB+1,:))&(mSortVarB_A > mPercentileB(iIdxB,:)));
        end
        % 0/1- to NaN/1-Matrix
        mIndxB(mIndxB==0) = NaN;

        % Get returns and sorting variable of assets in portfolio P. Now we
        % will have variables mRetPortB, mSortVarA_AB, mSortVarB_AB that have only
        % observations for the returns and sorting variables if the respective
        % asset is in the current portfolio 
        mRetPortB    = mRetPortA .* mIndxB;
        lMissingHoldingRet = any(mIndxB == 1 & ~isfinite(mRet), 1);
        mSortVarA_AB = mSortVarA_A .* mIndxB;
        mSortVarB_AB = mSortVarB_A .* mIndxB;

        % Get equal-weighted portfolio returns. Under lEnsureAllObs=true,
        % announcement-equivalent target unavailability was already removed
        % before either breakpoint and the surviving tradable cell is
        % normalized here. The missing branch remains a safety rule only for
        % explicit callers that disable that availability step.
        vNumHoldings = sum(mIndxB, 1, 'omitmissing');
        lTooSmall = vNumHoldings < options.iMinNumAssets;
        mWtsEW = mIndxB ./ vNumHoldings;
        vPortRetEW = sum(mWtsEW .* mRetPortB, 1, 'omitnan');
        vPortRetEW(lTooSmall | lMissingHoldingRet) = NaN;
        vMeanSortA = mean(mSortVarA_AB,1,'omitnan');
        vMeanSortB = mean(mSortVarB_AB,1,'omitnan');
        vMeanSortA(lTooSmall) = NaN;
        vMeanSortB(lTooSmall) = NaN;
        cPortRetsEW{iIdxA, iIdxB}       = vPortRetEW;
        if lUseSameLegReinvestment
            [cPortRetsEW{iIdxA,iIdxB},~,~,~] = ...
                fApplySameLegReinvestment(mWtsEW, ...
                options.rReinvestmentLedger,options.vLedgerWeekRow, ...
                options.sPayoffTiming,'EW');
        end
        cValSortVarA_ew{iIdxA,iIdxB}    = vMeanSortA;
        cValSortVarB_ew{iIdxA,iIdxB}    = vMeanSortB;

        % Get value-weighted portfolio returns
        if ~isempty(mMV)
            % Get market capitalization of portfolio assets
            mMvPortB = mMvPort .* mIndxB;

            % Calculate weights. Missing capitalization of a selected
            % holding, or a non-positive total capitalization, is undefined.
            vMktValTotal = sum(mMvPortB,1,'omitmissing');
            lUndefinedVW = any(mIndxB == 1 & (~isfinite(mMV) | mMV <= 0), 1) | ...
                ~isfinite(vMktValTotal) | vMktValTotal <= 0;
            mWts = mMvPortB ./ vMktValTotal;

            % Find all observations with no formation-time holdings.
            lNoHoldings = all(isnan(mMvPortB), 1);

            % Calculate portfolio returns
            vPortRetTemp = sum(mWts .* mRetPortB, 1,'omitmissing');

            % Calculate average sorting variables
            vAvgSortVarA = sum(mWts .* mSortVarA_AB, 1, 'omitmissing');
            vAvgSortVarB = sum(mWts .* mSortVarB_AB, 1, 'omitmissing');

            % Match missing values (omitmissing in sum may result in zeros)
            vPortRetTemp(lNoHoldings | lTooSmall | lMissingHoldingRet | lUndefinedVW) = NaN;
            vAvgSortVarA(lNoHoldings | lTooSmall | lUndefinedVW) = NaN;
            vAvgSortVarB(lNoHoldings | lTooSmall | lUndefinedVW) = NaN;

            % Save results
            cPortRetsVW{iIdxA, iIdxB} = vPortRetTemp;
            if lUseSameLegReinvestment
                [cPortRetsVW{iIdxA,iIdxB},~,~,~] = ...
                    fApplySameLegReinvestment(mWts, ...
                    options.rReinvestmentLedger,options.vLedgerWeekRow, ...
                    options.sPayoffTiming,'VW');
            end
            cValSortVarA_vw{iIdxA,iIdxB} = vAvgSortVarA;
            cValSortVarB_vw{iIdxA,iIdxB} = vAvgSortVarB;
        end
    end
end

% Append results to struct
rResults.EW.cPortRets = cPortRetsEW;
rResults.EW.cSortVarA = cValSortVarA_ew;
rResults.EW.cSortVarB = cValSortVarB_ew;
if ~isempty(mMV)
    rResults.VW.cPortRets = cPortRetsVW;
    rResults.VW.cSortVarA = cValSortVarA_vw;
    rResults.VW.cSortVarB = cValSortVarB_vw;
end

% Extracts fields of struct
cFields = fieldnames(rResults);
iNumFields = length(cFields);

% Calculate hedge-portfolio returns and descriptive statistics
for iIdxF = 1:iNumFields
    % 0. Step: Extract the portfolios
    cPortRetTemp    = rResults.(cFields{iIdxF}).cPortRets; % Portfolio returns

    % Initialize memory
    cHedgeRetA      = cell(iNumPortsA, 1);      % Hedge portfolio (long in high B, short in low B)
    cHedgeRetB      = cell(1, iNumPortsB);      % Hedge portfolio (long in high A, short in low A)

    % 1. Calculate portfolio returns for all portfolios that take a long
    % position in high-B assets and a short position in low-B assets
    for iIdxA = 1:iNumPortsA
        % Get portfolio returns of entire row (low-B, ..., high-B)
        mPortRets   = vertcat(cPortRetTemp{iIdxA,:});

        % Calculate the hedge portfolio return
        cHedgeRetA{iIdxA} = mPortRets(end,:) - mPortRets(1,:);
    end

    % 2. Calculate portfolio returns for all portfolios that take a long
    % position in high-A assets and a short position in low-A assets
    for iIdxB = 1:iNumPortsB
        % Get portfolio returns and sorting variable of entire column
        % (low-A, ..., high-A)
        mPortRets   = vertcat(cPortRetTemp{:, iIdxB});

        % Calculate the hedge portfolio return
        cHedgeRetB{iIdxB} = mPortRets(end,:) - mPortRets(1,:);
    end

    % So far, we calculated N_A hedge-portfolios that take a long position
    % in assets with a high sorting variable B and a short position in
    % assets with low values for B.
    %
    % Likewise, we also calculated N_B portfolios that take a long position
    % in assets with a high sorting variable A and a short position in
    % assets with low values for A.

    % Now we merge them together. The variable will have the dimension
    % (N_A + 1) x (N_B + 1), where the last row and column contain the
    % hedge portfolios.
    cPortRetTemp = [[cPortRetTemp; cHedgeRetB], [cHedgeRetA; cell(1)]];

    % Calculate average returns
    mAvgRet = cellfun(@(x)mean(x,'omitmissing'),cPortRetTemp,'UniformOutput',true);

    % Calculate standard deviations
    mStdRet = cellfun(@(x)std(x,'omitmissing'), cPortRetTemp,'UniformOutput',true);

    % Calculate number of time-series observations
    mN       = cellfun(@(x)sum(isfinite(x)),cPortRetTemp,'UniformOutput',true);

    % Calculate t-statistics and p-values
    mAvgRetT = NaN(size(mAvgRet));
    mAvgRetP = NaN(size(mAvgRet));
    lValidT = mN > 1 & mStdRet > 0;
    mAvgRetT(lValidT) = mAvgRet(lValidT)./(mStdRet(lValidT)./sqrt(mN(lValidT)));
    mAvgRetP(lValidT) = 2 * tcdf(-abs(mAvgRetT(lValidT)), mN(lValidT) - 1);

    % Calculate annualized Sharpe ratio
    switch upper(options.sFreq)
        case {'MONTH', 'MONTHLY', 'M'}
            iFreq = 12;
        case {'WEEK', 'WEEKLY', 'W'}
            iFreq = 52;
        case {'DAY', 'DAILY', 'D'}
            iFreq = 250;
        otherwise
            error('Unknown frequency');
    end
    mShp = NaN(size(mAvgRet));
    lValidShp = mN > 1 & isfinite(mAvgRet) & ...
        isfinite(mStdRet) & mStdRet > 0;
    mShp(lValidShp) = (mAvgRet(lValidShp) ./ ...
        mStdRet(lValidShp)) * sqrt(iFreq);

    % Calculate alpha w.r.t. risk factors
    mAlpha   = NaN(iNumPortsA + 1, iNumPortsB + 1);
    mAlphaT  = NaN(iNumPortsA + 1, iNumPortsB + 1);
    if ~isempty(mIndepVars)
        % Loop over portfolios
        for iIdxP = 1:numel(cPortRetTemp)
            % Get portfolio return
            if ~isempty(cPortRetTemp{iIdxP})
                vPortRet = cPortRetTemp{iIdxP};
            else
                continue
            end

            % Regression
            vPortRet = vPortRet';
            mXtemp = mIndepVars';
            lValidReg = ~isnan(vPortRet) & ~any(isnan(mXtemp),2);
            if sum(lValidReg) <= size(mXtemp,2) + 1
                continue
            end
            [vBetaTemp, vTstatTemp] = fRegstatsTstatSafe(vPortRet(lValidReg), mXtemp(lValidReg,:));
            mAlpha(iIdxP)   = vBetaTemp(1);
            mAlphaT(iIdxP)  = vTstatTemp(1); 
        end
    end
        
    % Append descriptive statistics
    rResults.(cFields{iIdxF}).cPortRets     = cPortRetTemp;
    rResults.(cFields{iIdxF}).mAvgRet       = mAvgRet;
    rResults.(cFields{iIdxF}).mAvgRetT      = mAvgRetT;
    rResults.(cFields{iIdxF}).mAvgRetP      = mAvgRetP;
    rResults.(cFields{iIdxF}).mStd          = mStdRet;
    rResults.(cFields{iIdxF}).mShp          = mShp;
    rResults.(cFields{iIdxF}).mAlpha        = mAlpha;
    rResults.(cFields{iIdxF}).mAlphaT       = mAlphaT;

    % Make to cell
    rResults.(cFields{iIdxF}).cAvgRet   = sprintfc('%.2f', round(mAvgRet * 100, 2));
    rResults.(cFields{iIdxF}).cAvgRetT  = sprintfc('%.2f', round(mAvgRetT, 2));
    rResults.(cFields{iIdxF}).cAlpha    = sprintfc('%.2f', round(mAlpha * 100, 2));
    rResults.(cFields{iIdxF}).cAlphaT   = sprintfc('%.2f', round(mAlphaT, 2));
end
end
