function [vHedgePortEW, vHedgePortVW, rCoverage] = ...
    fSingleSortFast(mSortVar, mRet, mME, options)
% Function for performing fast portfolio sortss. Returns only the hedge
% portfolio. 
%
% Note that this function requires that the sorting variable is in t 
% (or based on information up to t) and the returns are in t+1
%
% Input:
%   mSortVar:           N x T matrix of sorting variable (t)
%                       N: number of assets
%                       T: number of time-series observations
%   mRet:               N x T matrix of returns (t+1)
%                       N: number of assets
%                       T: number of time-series variables
%   mME:                N x T matrix of market capitalization (t)
%                       N: number of assets
%                       T: number of time-series observations
%   options:            Name-Value pair arguments
%       'vPercentile':      P x 1 vector of percentiles (default = 0:0.5:1)
%       .iMinNumCS:         Scalar, integer, minimum number of assets in 
%                           cross-section per period (default = 1)
%       .iMinNumAssets:     Scalar, integer, minimum number of assets per 
%                           portfolio (default = 1)
%       .lEnsureAllObs:     Logical, specifies whether to require the
%                           sorting variable, known target tradability and
%                           market capitalization before calculating
%                           percentiles (default = true)
%
% Output:
%   vHedgePortEW:       1 x T vector of ew hedge portfolio return
%                       T: number of time-series observations
%   vHedgePortVW:       1 x T vector of vw hedge portfolio return
%                       T: number of time-series observations
%   rCoverage:          Formation/accounting eligibility determined from
%                       portfolio prerequisites independently of whether
%                       the final numeric hedge return happens to be finite.

%% Check inputs
arguments
    mSortVar (:,:) {mustBeNumeric}
    mRet (:,:) {mustBeNumeric}
    mME (:,:) {mustBeNumeric} = []
    options.vPercentile (:,1) {mustBeNumeric, mustBeNonnegative}    = (0:0.5:1)'
    options.iMinNumCS (1,1) {mustBeNumeric, mustBeNonnegative}      = 1
    options.iMinNumAssets(1,1) {mustBeNumeric, mustBeNonnegative}   = 1
    options.lEnsureAllObs (1,1) {mustBeNumericOrLogical, mustBeNonnegative} = true    
    options.mUniverse (:,:) {mustBeNumericOrLogical} = []
    options.rReinvestmentLedger (1,1) struct = struct()
    options.vLedgerWeekRow (:,1) {mustBeNumeric} = []
    options.sPayoffTiming char = ''
end

% Determine dimensions
[iNumAssets, iNumObs]   = size(mSortVar);
iNumPorts               = length(options.vPercentile)-1;

% Control dimensions
assert(iNumAssets == size(mRet,1), 'Number of assets must agree');
assert(iNumObs == size(mRet,2), 'Number of observations must agree');
lUniverse = fValidateUniverseMask(options.mUniverse,iNumAssets,iNumObs);
lLedgerFields = [~isempty(fieldnames(options.rReinvestmentLedger)), ...
    ~isempty(options.vLedgerWeekRow),~isempty(options.sPayoffTiming)];
assert(all(lLedgerFields) || ~any(lLedgerFields), ...
    'Fast sort reinvestment options must be supplied together');
lUseSameLegReinvestment = all(lLedgerFields);
if lUseSameLegReinvestment
    assert(ismember(options.sPayoffTiming,{'ordinary','lead1'}), ...
        'Unknown economic payoff timing');
end
mSortVar(~lUniverse) = NaN;
if ~isempty(mME)
    mME(~lUniverse) = NaN;
end

% Remove known-untradable target asset-weeks before breakpoints.  The
% availability test is finite economic P&L, not a return-magnitude screen.
if options.lEnsureAllObs
    lAvail = isfinite(mSortVar) & isfinite(mRet);
    if ~isempty(mME)
        lAvail  = lAvail & isfinite(mME) & mME > 0;

        % Set to missing
        mME(~lAvail) = NaN;
    end    
    mSortVar(~lAvail) = NaN;
end

% Ensure minimum cross-section
lNonAvailObs                = sum(isfinite(mSortVar),1) < options.iMinNumCS;
mSortVar(:,lNonAvailObs)    = NaN;

% Calculate quantiles
mQuantiles = quantile(mSortVar, options.vPercentile, 1, 'Method','exact');

% Preallocate memory
mPortRet_ew = NaN(iNumPorts,iNumObs);     % Equal-weighted portfolio returns
mPortRet_vw = NaN(iNumPorts,iNumObs);     % Value-weighted portfolio returns
mExpNum     = NaN(iNumPorts,iNumObs);     % Formation-time number of assets
lMissingHoldingRetLeg = false(iNumPorts,iNumObs);
lUndefinedVWLeg = false(iNumPorts,iNumObs);
mMissingHoldingCount = zeros(iNumPorts,iNumObs);
mMissingHoldingWeightEW = zeros(iNumPorts,iNumObs);
mMissingHoldingWeightVW = NaN(iNumPorts,iNumObs);

% Iterate over portfolios
for iIdxP = [1,iNumPorts] % Only low and high
    % 1. Step: Create 0/1 indicator matrix if an asset is in current
    % portfolio
    if iIdxP == 1
        mIndx = double((mSortVar<=mQuantiles(iIdxP+1,:))&(mSortVar>=mQuantiles(iIdxP,:)));
    else
        mIndx = double((mSortVar<=mQuantiles(iIdxP+1,:))&(mSortVar>mQuantiles(iIdxP,:)));
    end

    % 0/1- to NaN/1-Matrix
    mIndx(mIndx==0) = NaN; % This will be used to set returns to missing if not in portfolio
    mExpNum(iIdxP,:) = sum(mIndx, 1, 'omitmissing');
    
    % Get returns and sorting variable of assets in portfolio P. Now we
    % will have a variable mRetPort that has only observations for the 
    % returns if the respective asset is in the current portfolio
    mRetPort = mRet .* mIndx;
    lMissingHoldingRet = any(mIndx == 1 & ~isfinite(mRet), 1);
    lMissingHoldingRetLeg(iIdxP,:) = lMissingHoldingRet;
    mMissingHoldingCount(iIdxP,:) = ...
        sum(mIndx == 1 & ~isfinite(mRet),1);

    % Get equal-weighted portfolio returns.  Under lEnsureAllObs=true every
    % known-untradable target was already removed before breakpoints and the
    % remaining weights are normalized here.  The missing-return check is a
    % safety rule for explicit callers that disable that availability step.
    mWtsEW = mIndx ./ mExpNum(iIdxP,:);
    mMissingHoldingWeightEW(iIdxP,:) = ...
        sum(iZeroOutside(mWtsEW) .* (~isfinite(mRet)),1);
    vPortRetTemp = sum(mWtsEW .* mRetPort, 1, 'omitnan');
    vPortRetTemp(mExpNum(iIdxP,:) == 0 | lMissingHoldingRet) = NaN;
    mPortRet_ew(iIdxP,:) = vPortRetTemp;
    if lUseSameLegReinvestment
        [mPortRet_ew(iIdxP,:),~,~,~] = ...
            fApplySameLegReinvestment(mWtsEW, ...
            options.rReinvestmentLedger,options.vLedgerWeekRow, ...
            options.sPayoffTiming,'EW');
    end

    % Get value weighted portfolio returns
    if ~isempty(mME)
        % Get market capitalization of all assets within portfolio
        mMktValPort     = mME .* mIndx;

        % Calculate weights. Missing capitalization of a selected holding,
        % or a non-positive total capitalization, is undefined rather than
        % a reason to re-normalize the remaining holdings.
        vMktValTotal = sum(mMktValPort,1,'omitmissing');
        lUndefinedVW = any(mIndx == 1 & (~isfinite(mME) | mME <= 0), 1) | ...
            ~isfinite(vMktValTotal) | vMktValTotal <= 0;
        lUndefinedVWLeg(iIdxP,:) = lUndefinedVW;
        mWts = mMktValPort ./ vMktValTotal;
        mMissingHoldingWeightVW(iIdxP,:) = ...
            sum(iZeroOutside(mWts) .* (~isfinite(mRet)),1);

        % Find all time steps with no formation-time holdings.
        lNoHoldings = all(isnan(mMktValPort),1);

        % Calculate weighted portfolio return
        vPortRetTemp                = sum(mWts .* mRetPort,1,'omitnan');

        % omitmissing in sum may cause zeros if no holdings are available.
        vPortRetTemp(lNoHoldings | lMissingHoldingRet | lUndefinedVW) = NaN;

        % Save portfolio return
        mPortRet_vw(iIdxP,:)        = vPortRetTemp;
        if lUseSameLegReinvestment
            [mPortRet_vw(iIdxP,:),~,~,~] = ...
                fApplySameLegReinvestment(mWts, ...
                options.rReinvestmentLedger,options.vLedgerWeekRow, ...
                options.sPayoffTiming,'VW');
        end
    end
end

% Ensure minimum formation-time assets in both hedge legs
if options.iMinNumAssets > 1
    lAvailObs = mExpNum(1,:) >= options.iMinNumAssets & ...
        mExpNum(end,:) >= options.iMinNumAssets;
    mPortRet_ew(:,~lAvailObs) = NaN;
    mPortRet_vw(:,~lAvailObs) = NaN;
end

% Calculate hedge portfolio
vHedgePortEW = (mPortRet_ew(end,:) - mPortRet_ew(1,:))';
vHedgePortVW = (mPortRet_vw(end,:) - mPortRet_vw(1,:))';

% Coverage prerequisites are constructed without inspecting return
% magnitude.  The declared information set includes target tradability
% (treated as announcement-equivalent) as well as the signal and formation
% value; accounting eligibility then checks the selected holdings and VW
% weights produced on that investable universe.
lFormationEligible = ~lNonAvailObs & ...
    mExpNum(1,:) >= options.iMinNumAssets & ...
    mExpNum(end,:) >= options.iMinNumAssets;
if lUseSameLegReinvestment
    lHoldingReturnComplete = isfinite(mPortRet_ew(1,:)) & ...
        isfinite(mPortRet_ew(end,:));
else
    lHoldingReturnComplete = ~lMissingHoldingRetLeg(1,:) & ...
        ~lMissingHoldingRetLeg(end,:);
end
rCoverage = struct();
rCoverage.lFormationEligible = lFormationEligible(:);
rCoverage.vFormationHoldingsLow = mExpNum(1,:)';
rCoverage.vFormationHoldingsHigh = mExpNum(end,:)';
rCoverage.vMissingHoldingCount = ...
    (mMissingHoldingCount(1,:) + mMissingHoldingCount(end,:))';
rCoverage.vMissingHoldingWeightEW = ...
    (mMissingHoldingWeightEW(1,:) + ...
     mMissingHoldingWeightEW(end,:))';
rCoverage.vMissingHoldingWeightVW = ...
    (mMissingHoldingWeightVW(1,:) + ...
     mMissingHoldingWeightVW(end,:))';
lEWAccountingEligible = lFormationEligible & lHoldingReturnComplete;
rCoverage.lEWAccountingEligible = lEWAccountingEligible(:);
if isempty(mME)
    rCoverage.lVWAccountingEligible = false(iNumObs,1);
else
    lVWWeightsDefined = ~lUndefinedVWLeg(1,:) & ...
        ~lUndefinedVWLeg(end,:);
    if lUseSameLegReinvestment
        lVWPayoffComplete = isfinite(mPortRet_vw(1,:)) & ...
            isfinite(mPortRet_vw(end,:));
    else
        lVWPayoffComplete = lHoldingReturnComplete;
    end
    lVWAccountingEligible = lFormationEligible & ...
        lVWPayoffComplete & lVWWeightsDefined;
    rCoverage.lVWAccountingEligible = lVWAccountingEligible(:);
end
end

function mOut = iZeroOutside(mIn)
mOut = mIn;
mOut(~isfinite(mOut)) = 0;
end
