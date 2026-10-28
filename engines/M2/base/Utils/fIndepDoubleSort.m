function rResults = fIndepDoubleSort(mSortVarA, mSortVarB, mRet, mIndepVars, mMV, options)
% Function for performing independent double sorts based on two sort variables
%
% Note that this function requires that the sorting variables are in t 
% (or based on information up to t) and the returns are in t+1
%
% Input:
%   mSortVarA:      N x T matrix of the first sorting variable
%                   N: number of responses
%                   T: number of time-series observations
%   mSortVarB:      N x T matrix of the second sorting variable
%                   N: number of responses
%                   T: number of time-series observations
%   mRet:           N x T matrix of returns 
%                   N: number of responses
%                   T: number of time-series observations
%   vPercentileA:   (P + 1) x 1 vector of percentiles for sorts with
%                   respect to first sorting variable
%                   (default = 0:0.5:1)
%   vPercentileB:   (P* + 1) x 1 vector of percentiles for sorts with
%                   respect to second sorting variable
%                   (default = 0:0.5:1)
%   mIndepVars:     K x T matrix of independent variables for regressing
%                   portfolio returns on these variables
%   mMV:            N x T matrix of market capitalization
%                   N: number of responses
%                   T: number of time-series observations
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
%       'lEnsureAllObs':    Logical, specifies whether to ensure all
%                           observations for sorting variables and returns
%                           prior to calculation of percentiles
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
%       .RW:            Struct, containing results for rank-weighted 
%                     variables        

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
    options.rReinvestmentLedger struct = struct()
    options.vLedgerWeekRow (:,1) {mustBeNumeric} = zeros(0,1)
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
else
    assert(iNumResp == size(mMV,1),'Number of response variables must agree (VarA, mMV)');
    assert(iNumObs == size(mMV,2),'Number of time-series observations must agree (VarA, mMV)');
end
if ~isempty(mIndepVars)
    [iNumIndepVars, iNumObsK] = size(mIndepVars);
    assert(iNumObs == iNumObsK,'Number of time-series observations must agree (A, mIndepVars)');
end
lUseLedger = ~isempty(fieldnames(options.rReinvestmentLedger));
assert(lUseLedger == ~isempty(options.vLedgerWeekRow) && ...
    lUseLedger == ~isempty(options.sPayoffTiming), ...
    'Economic ledger, week rows, and timing must be supplied together');
if lUseLedger
    assert(ismember(options.sPayoffTiming,{'ordinary','lead1'}) && ...
        numel(options.vLedgerWeekRow) == iNumObs, ...
        'Invalid economic-ledger timing or week-row axis');
end

% Require all observations to be nonmissing
if options.lEnsureAllObs
    lAvail = ~isnan(mSortVarA) & ~isnan(mSortVarB) & ~isnan(mRet);

    if ~isempty(mMV)
        lAvail = lAvail & ~isnan(mMV);
    end

    % Set non-available observations to missing
    mSortVarA(~lAvail) = NaN;
    mSortVarB(~lAvail) = NaN;
end

% Require minimum size of cross-section
lAvail                   = ~isnan(mSortVarA) & ~isnan(mSortVarB) & ~isnan(mRet);
lRemoveTick              = sum(lAvail, 1) < options.iMinNumCS;
mSortVarA(:,lRemoveTick) = NaN;
mSortVarB(:,lRemoveTick) = NaN;

% Check if sorting variables are binary
vUniqueA = unique(mSortVarA(~isnan(mSortVarA)));
vUniqueB = unique(mSortVarB(~isnan(mSortVarB)));
if length(vUniqueA) == 2
    mPercentileA = ones(3, iNumObs) .* [0; 0.5; 1];
else
    mPercentileA = quantile(mSortVarA, options.vPercentileA);
end
if length(vUniqueB) == 2
    mPercentileB = ones(3, iNumObs) .* [0; 0.5; 1];
else
    mPercentileB = quantile(mSortVarB, options.vPercentileB);
end

% Number of portfolios
iNumPortsA = size(mPercentileA,1) - 1;
iNumPortsB = size(mPercentileB,1) - 1;

% Preallocate memory
cPortRetsEW     = cell(iNumPortsA, iNumPortsB);     % Realized return for ew portfolios
cPortRetsVW     = cell(iNumPortsA, iNumPortsB);     % Realized return for vw portfolios
cValSortVarA_ew = cell(iNumPortsA, iNumPortsB);     % First sort variable for ew portfolios
cValSortVarA_vw = cell(iNumPortsA, iNumPortsB);     % First sort variable for vw portfolios
cValSortVarB_ew = cell(iNumPortsA, iNumPortsB);     % Second sort variable for ew portfolios
cValSortVarB_vw = cell(iNumPortsA, iNumPortsB);     % Second sort variable for vw portfolios

% Iterate over portfolios for first sorting variable
for iIdxA = 1:iNumPortsA
    % Check if in portfolio A
    if iIdxA == 1
        lIsInA = (mSortVarA <= mPercentileA(iIdxA+1,:))&(mSortVarA >= mPercentileA(iIdxA,:));
    else
        lIsInA = (mSortVarA <= mPercentileA(iIdxA+1,:))&(mSortVarA > mPercentileA(iIdxA,:));
    end

    for iIdxB = 1:iNumPortsB
        % Check if in portfolio B
        if iIdxB == 1
            lIsInB = (mSortVarB <= mPercentileB(iIdxB+1,:))&(mSortVarB >= mPercentileB(iIdxB,:));
        else
            lIsInB = (mSortVarB <= mPercentileB(iIdxB+1,:))&(mSortVarB > mPercentileB(iIdxB,:));
        end

        % Check if in portfolio A and B
        mIndx = double(lIsInA & lIsInB); % This will be used to set returns to missing if not in portfolio

        % 0/1- to NaN/1-Matrix
        mIndx(mIndx==0) = NaN;

        % Get returns and sorting variable of assets in portfolio P. Now we
        % will have variables mRetPortA, mSortVarAtemp, mSortVarBtemp that have only
        % observations for the returns and sorting variables if the respective
        % asset is in the current portfolio
        mRetPort        = mRet .* mIndx;
        mSortVarAtemp   = mSortVarA .* mIndx;  
        mSortVarBtemp   = mSortVarB .* mIndx;

        % Get market value of these assets in portfolio P
        if ~isempty(mMV)
            mMvPort = mMV .* mIndx;
        end

        % Get equal weighted portfolio returns
        cPortRetsEW{iIdxA, iIdxB}       = mean(mRetPort,1,'omitnan');
        if lUseLedger
            mEW = double(isfinite(mIndx));
            mEW = mEW./sum(mEW,1);
            cPortRetsEW{iIdxA,iIdxB} = fApplySameLegReinvestment( ...
                mEW,options.rReinvestmentLedger,options.vLedgerWeekRow, ...
                options.sPayoffTiming,'EW');
        end
        cValSortVarA_ew{iIdxA,iIdxB}    = mean(mSortVarAtemp,1,'omitnan');
        cValSortVarB_ew{iIdxA,iIdxB}    = mean(mSortVarBtemp,1,'omitnan');

        % Get value-weighted portfolio returns
        if ~isempty(mMV)
            % Get market capitalization of portfolio assets
            mMvPort = mMvPort .* mIndx;

            % Calculate weights
            mWts = mMvPort ./ sum(mMvPort,1,'omitmissing');
            mWts(:,all(isnan(mMvPort),1)) = NaN;

            % Find all nonmissing observations
            lAllNaN = all(isnan(mRetPort), 1);

            % Calculate portfolio returns
            vPortRetTemp = sum(mWts .* mRetPort, 1,'omitnan');

            % Calculate average sorting variables
            vAvgSortVarA = sum(mWts .* mSortVarAtemp, 1, 'omitnan');
            vAvgSortVarB = sum(mWts .* mSortVarBtemp, 1, 'omitnan');

            % Match missing values (omitmissing in sum may result in zeros)
            vPortRetTemp(lAllNaN) = NaN;
            vAvgSortVarA(lAllNaN) = NaN;
            vAvgSortVarB(lAllNaN) = NaN;

            % Save results
            cPortRetsVW{iIdxA, iIdxB}       = vPortRetTemp;
            if lUseLedger
                cPortRetsVW{iIdxA,iIdxB} = fApplySameLegReinvestment( ...
                    mWts,options.rReinvestmentLedger, ...
                    options.vLedgerWeekRow,options.sPayoffTiming,'VW');
            end
            cValSortVarA_vw{iIdxA,iIdxB}    = vAvgSortVarA;
            cValSortVarB_vw{iIdxA,iIdxB}    = vAvgSortVarB;
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
    mN       = cellfun(@(x)sum(~isnan(x)),cPortRetTemp,'UniformOutput',true);

    % Calculate t-statistics and p-values
    mAvgRetT    = mAvgRet./(mStdRet./sqrt(mN));
    mAvgRetP    = 2 * tcdf(-abs(mAvgRetT), mN);

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
    mShp = (mAvgRet ./ mStdRet) * (iFreq/sqrt(iFreq));

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
            rRegResults     = regstats(vPortRet', mIndepVars, 'linear', 'tstat');
            mAlpha(iIdxP)   = rRegResults.tstat.beta(1);
            mAlphaT(iIdxP)  = rRegResults.tstat.t(1); 
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
