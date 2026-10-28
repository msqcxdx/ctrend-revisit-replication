function rResults = fSingleSortMulti(mSortVar, mRet, vQuantile, mIndepVars, mME, rOptions)
% Function for performing portfolio sorts. 
% 
% Note that this function requires that the sorting variable is in t 
% (or based on information up to t) and the returns are in t+1. This
% function does not perform any lagging or leading
%
% Input:
%   mSortVar:           N x T matrix of sorting variable (t)
%                       N: number of assets
%                       T: number of time-series observations
%   mRet:               N x T matrix of returns (t+1)
%                       N: number of assets
%                       T: number of time-series variables
%   vQuantile:          P x 1 vector of quantiles (default = 0:0.2:1)
%                       P: number of portfolios (including hedge portfolio)
%   mIndepVars:         K x T matrix of independent variables
%                       K: number of factors
%                       T: number of of time-series observations
%   mME:                N x T matrix of market capitalization (t)
%                       N: number of assets
%                       T: number of time-series observations
%   rOptions:           Struct, containing additional options
%       .lHedgeOnly:        Logical, indicates whether to calculate only
%                           the hedge portfolio (default = false)
%       .iHedgeSign:        Scalar, integer, expected sign of hedge portfolio.
%                           Allows to take a long position in the lowest 
%                           portfolio if set to -1 (default = 1)
%       .lAddTests:         Logical, specifies whether to run additional
%                           tests, including monotonicity, variance, 
%                           Sharpe ratio (default = false)
%       .iMinNumCS:         Scalar, integer, minimum number of assets in 
%                           cross-section per period (default = P)
%       .iMinNumAssets:     Scalar, integer, minimum number of assets per 
%                           portfolio (default = 1)
%       .lEnsureAllObs:     Logical, specifies whether to require the
%                           sorting variable, known target tradability and
%                           market capitalization before calculating
%                           percentiles (default = true)
%       .sFreq:             Data Frequency (default = 'monthly');


%       .vTC:               2 x 1 vector of transaction costs.
%                           First element refers to short-selling costs and
%                           second element is the cost rate for long
%                           positions
%       .rReinvestmentLedger: authenticated daily-event economic ledger.
%       .vLedgerWeekRow:     T x 1 rows mapping this call into the ledger.
%       .sPayoffTiming:      'ordinary' or 'lead1'.  When these three fields
%                            are supplied, every frozen exit is sold and its
%                            proceeds are immediately reinvested within the
%                            same portfolio leg; cash is never retained.
%
% Output:
%   rResults            Struct, containing the results including returns
%                       and portfolio statistics

% Check input arguments
arguments
    mSortVar (:,:) {mustBeNumeric}
    mRet (:,:) {mustBeNumeric}
    vQuantile (:,1) {mustBeNumeric, mustBeNonnegative}
    mIndepVars (:,:) {mustBeNumeric}
    mME (:,:) {mustBeNumeric}
    rOptions struct = struct()
end

% Determine dimensions
[iNumAssets, iNumObs]   = size(mSortVar);
iNumPorts               = length(vQuantile)-1; % Without hedge portfolio

% Control dimensions
assert(iNumAssets == size(mRet,1), 'Number of assets must agree');
assert(iNumObs == size(mRet,2), 'Number of observations must agree');

% Set options
if ~isfield(rOptions, 'lHedgeOnly')
    % Calculate only hedge-portfolio
    rOptions.lHedgeOnly = false;
end
if ~isfield(rOptions, 'iHedgeSign')
    % Expected sign of hedge portfolio (allows to take a long position in
    % the lowest percentile if set to -1)
    rOptions.iHedgeSign = 1;
end
if ~isfield(rOptions, 'lAddTests')
    % Run additional tests
    rOptions.lAddTests = false;
end
if ~isfield(rOptions, 'iMinNumCS')
    % Minimum size of cross-section 
    rOptions.iMinNumCS = iNumPorts;
end
if ~isfield(rOptions, 'iMinNumAssets')
    % Minimum number of assets per portfolio
    rOptions.iMinNumAssets = 1;
end
if ~isfield(rOptions, 'lEnsureAllObs')
    % Control for nonmissing return and sorting variable
    rOptions.lEnsureAllObs = true;
end
if ~isfield(rOptions, 'sFreq')
    % Monthly frequency is default
    rOptions.sFreq = 'monthly';
end
if ~isfield(rOptions, 'vTC')
    % Do not assume trading costs
    rOptions.vTC = [];
else
    % Symmetric transaction costs for long and short positions
    if isscalar(rOptions.vTC)
        rOptions.vTC = repmat(rOptions.vTC, 2, 1);
    end
end
if ~isfield(rOptions,'mUniverse')
    rOptions.mUniverse = [];
end
lUniverse = fValidateUniverseMask(rOptions.mUniverse,iNumAssets,iNumObs);
% The three economic-ledger options are an all-or-none contract.
lLedgerFields = [isfield(rOptions,'rReinvestmentLedger'), ...
    isfield(rOptions,'vLedgerWeekRow'), ...
    isfield(rOptions,'sPayoffTiming')];
assert(all(lLedgerFields) || ~any(lLedgerFields), ...
    'Reinvestment ledger, week rows, and payoff timing must be supplied together');
lUseSameLegReinvestment = all(lLedgerFields);
assert(~isfield(rOptions,'mLiquidatedToCash'), ...
    ['Cash settlement is not a supported accounting mode. Frozen exits ' ...
     'must use the same-leg reinvestment ledger.']);
mSortVar(~lUniverse) = NaN;
if ~isempty(mME)
    mME(~lUniverse) = NaN;
end

% Under the declared announcement-equivalence convention, a missing economic
% payoff identifies a target-week asset that cannot be traded/settled. Remove
% it before breakpoints and normalize weights over the remaining tradable
% assets, matching a feasible order rejected at portfolio construction. This
% mask depends only on availability, never on the payoff magnitude.
if rOptions.lEnsureAllObs
    lAvail = isfinite(mSortVar) & isfinite(mRet);

    if ~isempty(mME)
        % Check for nonmissing market value if passed to function
        lAvail = lAvail & isfinite(mME) & mME > 0;

        % Set to missing
        mME(~lAvail) = NaN;
    end    
    % Set to missing
    mSortVar(~lAvail)   = NaN;
end

% Require minimum cross-section. Otherwise the portfolio return will be
% missing
lNonAvailObs                = sum(isfinite(mSortVar),1) < rOptions.iMinNumCS;
mSortVar(:,lNonAvailObs)    = NaN;

% Calculate percentiles
mQuantiles                  = quantile(mSortVar, vQuantile, 1, 'Method','exact');

% Preallocate memory
mPortRet_ew     = NaN(iNumPorts+1,iNumObs);     % Equal-weighted portfolio returns
mPortRet_vw     = NaN(iNumPorts+1,iNumObs);     % Value-weighted portfolio returns
mValSortVar_ew  = NaN(iNumPorts+1,iNumObs);     % Average values for sort variable
mValSortVar_vw  = NaN(iNumPorts+1,iNumObs);     % Average values for sort variable
mIndex          = NaN(iNumAssets,iNumObs);      % Index of portfolio
mExpNum         = NaN(iNumPorts, iNumObs);      % Expected number of assets in portfolio
mActNum         = NaN(iNumPorts, iNumObs);      % Actual number of assets in portfolio
mMissingHoldingNum = zeros(iNumPorts,iNumObs);
mMissingHoldingWeightEW = zeros(iNumPorts,iNumObs);
mMissingHoldingWeightVW = NaN(iNumPorts,iNumObs);
mWts_ew         = NaN(iNumAssets, iNumObs, iNumPorts);  % Weights for equal-weighted portfolio
mWts_vw         = NaN(iNumAssets, iNumObs,iNumPorts);   % Weights for value-weighted portfolio
mEndWts_ew      = NaN(iNumAssets, iNumObs, iNumPorts);
mEndWts_vw      = NaN(iNumAssets, iNumObs, iNumPorts);
mWithinWeekFullL1_ew = NaN(iNumPorts,iNumObs);
mWithinWeekFullL1_vw = NaN(iNumPorts,iNumObs);
cReinvestmentAuditEW = cell(iNumPorts,1);
cReinvestmentAuditVW = cell(iNumPorts,1);

% Iterate over portfolios
for iIdxP = 1:iNumPorts
    % Skip if only the calculation of hedge portfolio is requested and
    % current portfolio is neither the low or high portfolio
    if rOptions.lHedgeOnly && (iIdxP > 1 && iIdxP < iNumPorts)
        continue
    end

    % 1. Step: Create 0/1 matrix that indicates if an asset is in current
    % portfolio
    if iIdxP == 1
        mIndx = double((mSortVar<=mQuantiles(iIdxP+1,:))&(mSortVar>=mQuantiles(iIdxP,:)));
    else
        mIndx = double((mSortVar<=mQuantiles(iIdxP+1,:))&(mSortVar>mQuantiles(iIdxP,:)));
    end

    % 0/1- to NaN/1-Matrix
    mIndx(mIndx==0)  = NaN;    % This will be used to set returns to missing if not in portfolio
    mIndex(mIndx==1) = iIdxP;  % This is for the output
    
    % Get returns and sorting variable of assets in portfolio P. Now we
    % will have a variable mRetPort and mVarPort that have only
    % observations for the returns and sorting variable if the respective
    % asset is in the current portfolio
    mRetPort = mRet .* mIndx;
    lMissingHoldingRet = any(mIndx == 1 & ~isfinite(mRet), 1);
    mMissingHoldingNum(iIdxP,:) = ...
        sum(mIndx == 1 & ~isfinite(mRet),1);
    mVarPort = mSortVar .* mIndx;

    % Expected number of assets in portfolio
    mExpNum(iIdxP,:)    = sum(mIndx,1,'omitmissing');
    lNoHoldings         = mExpNum(iIdxP,:) == 0;
    
    % Get equal-weighted portfolio returns and the average sorting variable.
    % With lEnsureAllObs=true, known target unavailability has already been
    % applied before breakpoints and the tradable holdings are normalized
    % here.  The missing-return branch remains a safety rule for explicit
    % callers that disable the availability step.
    mWts_ew(:,:,iIdxP)      = mIndx./mExpNum(iIdxP,:);
    mMissingHoldingWeightEW(iIdxP,:) = sum( ...
        iZeroOutside(mWts_ew(:,:,iIdxP)) .* (~isfinite(mRet)),1);
    vPortRetEW              = sum(mWts_ew(:,:,iIdxP) .* mRetPort, 1, 'omitmissing');
    vPortRetEW(lNoHoldings | lMissingHoldingRet) = NaN;
    mPortRet_ew(iIdxP,:)    = vPortRetEW;
    mValSortVar_ew(iIdxP,:) = mean(mVarPort,1,'omitmissing');
    if lUseSameLegReinvestment
        [mPortRet_ew(iIdxP,:),mEndWts_ew(:,:,iIdxP), ...
            mWithinWeekFullL1_ew(iIdxP,:), ...
            cReinvestmentAuditEW{iIdxP}] = ...
            fApplySameLegReinvestment(mWts_ew(:,:,iIdxP), ...
            rOptions.rReinvestmentLedger,rOptions.vLedgerWeekRow, ...
            rOptions.sPayoffTiming,'EW');
    end
    
    % Actual holdings are the investable holdings after the declared
    % announcement-equivalent availability check.
    mActNum(iIdxP,:)    = mExpNum(iIdxP,:);

    % Get value weighted portfolio returns
    if ~isempty(mME)
        % Get market capitalization of all assets within portfolio
        mMktValPort = mME .* mIndx;

        % Calculate formation-time weights for holdings and turnover. A
        % missing capitalization of a selected holding, or a non-positive
        % total capitalization, leaves value weights undefined.
        vMktValTotal = sum(mMktValPort,1,'omitmissing');
        lUndefinedVW = any(mIndx == 1 & (~isfinite(mME) | mME <= 0), 1) | ...
            ~isfinite(vMktValTotal) | vMktValTotal <= 0;
        mWts = mMktValPort ./ vMktValTotal;
        mWts(:,lUndefinedVW) = NaN;
        mMissingHoldingWeightVW(iIdxP,:) = sum( ...
            iZeroOutside(mWts) .* (~isfinite(mRet)),1);

        % Save weights
        mWts_vw(:,:,iIdxP) = mWts;

        % Find all time steps with no formation-time holdings.
        lNoHoldingsVW = all(isnan(mMktValPort),1);

        % Calculate weighted portfolio return
        vPortRetTemp                = sum(mWts .* mRetPort,1,'omitmissing');
        vPortRetTemp(lNoHoldingsVW | lMissingHoldingRet | lUndefinedVW) = NaN;
        mPortRet_vw(iIdxP,:)        = vPortRetTemp;
        if lUseSameLegReinvestment
            [mPortRet_vw(iIdxP,:),mEndWts_vw(:,:,iIdxP), ...
                mWithinWeekFullL1_vw(iIdxP,:), ...
                cReinvestmentAuditVW{iIdxP}] = ...
                fApplySameLegReinvestment(mWts_vw(:,:,iIdxP), ...
                rOptions.rReinvestmentLedger,rOptions.vLedgerWeekRow, ...
                rOptions.sPayoffTiming,'VW');
        end

        % Calculate weighted average of sorting variable
        vSortVarTemp                = sum(mWts .* mVarPort,1,'omitmissing');
        vSortVarTemp(lNoHoldingsVW | lUndefinedVW) = NaN;
        mValSortVar_vw(iIdxP,:)     = vSortVarTemp;
    end
end

% Get returns of hedge portfolio
if rOptions.iHedgeSign == 1
    % Long high - short low
    mPortRet_ew(end,:)    = mPortRet_ew(iNumPorts,:) - mPortRet_ew(1,:);
    mPortRet_vw(end,:)    = mPortRet_vw(iNumPorts,:) - mPortRet_vw(1,:);
    mValSortVar_ew(end,:) = mValSortVar_ew(iNumPorts,:) - mValSortVar_ew(1,:);
    mValSortVar_vw(end,:) = mValSortVar_vw(iNumPorts,:) - mValSortVar_vw(1,:);
else
    % Long low - short high
    mPortRet_ew(end,:)    = mPortRet_ew(1,:)  - mPortRet_ew(iNumPorts,:);
    mPortRet_vw(end,:)    = mPortRet_vw(1,:)  - mPortRet_vw(iNumPorts,:);
    mValSortVar_ew(end,:) = mValSortVar_ew(1,:) - mValSortVar_ew(iNumPorts,:);
    mValSortVar_vw(end,:) = mValSortVar_vw(1,:) - mValSortVar_vw(iNumPorts,:);
end

% Number of assets in hedge portfolio
mActNum = [mActNum; sum(mActNum([1,iNumPorts],:),1,'omitmissing')];
mExpNumHedge = [mExpNum; sum(mExpNum([1,iNumPorts],:),1,'omitmissing')];
mMissingHoldingNumHedge = [mMissingHoldingNum; ...
    sum(mMissingHoldingNum([1,iNumPorts],:),1)];
mMissingHoldingWeightEWHedge = [mMissingHoldingWeightEW; ...
    sum(mMissingHoldingWeightEW([1,iNumPorts],:),1)];
mMissingHoldingWeightVWHedge = [mMissingHoldingWeightVW; ...
    sum(mMissingHoldingWeightVW([1,iNumPorts],:),1)];

% Ensure sufficient formation-time assets in each portfolio. Realized return
% availability is deliberately not used for this ex-ante filter.
if rOptions.iMinNumAssets > 1
    if rOptions.lHedgeOnly
        lAvailObs = mExpNumHedge(1,:) >= rOptions.iMinNumAssets & ...
                mExpNumHedge(iNumPorts,:) >= rOptions.iMinNumAssets;
    else
        lAvailObs = all(mExpNumHedge(1:end-1,:) >= rOptions.iMinNumAssets,1);
    end
    mPortRet_ew(:,~lAvailObs)       = NaN;
    mPortRet_vw(:,~lAvailObs)       = NaN;
    mValSortVar_ew(:,~lAvailObs)    = NaN;
    mValSortVar_vw(:,~lAvailObs)    = NaN;
    mActNum(:,~lAvailObs)           = NaN;
    mWts_ew(:,~lAvailObs,:)         = NaN;
    mWts_vw(:,~lAvailObs,:)         = NaN;
    mEndWts_ew(:,~lAvailObs,:)      = NaN;
    mEndWts_vw(:,~lAvailObs,:)      = NaN;
    mWithinWeekFullL1_ew(:,~lAvailObs) = NaN;
    mWithinWeekFullL1_vw(:,~lAvailObs) = NaN;
end

% Get time series of returns, sorting variable, and weights
rResults.EW.mPortRet            = mPortRet_ew;
rResults.EW.mValSortVar         = mValSortVar_ew;
rResults.EW.mWts                = mWts_ew;
rResults.EW.mEndRiskyWts        = mEndWts_ew;
rResults.EW.mWithinWeekTradeCostBaseFull = mWithinWeekFullL1_ew';
rResults.EW.cSameLegReinvestmentAudit = cReinvestmentAuditEW;
    rResults.EW.mFormationHoldings  = mExpNumHedge;
    rResults.EW.mMissingPayoffHoldings = mMissingHoldingNumHedge;
    rResults.EW.mMissingPayoffWeight = mMissingHoldingWeightEWHedge;
    rResults.EW.lPayoffComplete = false(size(mMissingHoldingNumHedge));
if ~isempty(mME)
    rResults.VW.mPortRet        = mPortRet_vw;
    rResults.VW.mValSortVar     = mValSortVar_vw;
    rResults.VW.mWts            = mWts_vw;
    rResults.VW.mEndRiskyWts    = mEndWts_vw;
    rResults.VW.mWithinWeekTradeCostBaseFull = mWithinWeekFullL1_vw';
    rResults.VW.cSameLegReinvestmentAudit = cReinvestmentAuditVW;
    rResults.VW.mFormationHoldings = mExpNumHedge;
    rResults.VW.mMissingPayoffHoldings = mMissingHoldingNumHedge;
    rResults.VW.mMissingPayoffWeight = mMissingHoldingWeightVWHedge;
    rResults.VW.lPayoffComplete = false(size(mMissingHoldingNumHedge));
end

% Get descriptive statistics of portfolios
cFields = fieldnames(rResults);
for iIdxF = 1:length(cFields)
    % Mean of sorting variable
    rResults.(cFields{iIdxF}).vAvgSortVar = ...
        mean(rResults.(cFields{iIdxF}).mValSortVar,2,'omitnan');
        
    % Mean of return
    rResults.(cFields{iIdxF}).vAvgRet = ...
        mean(rResults.(cFields{iIdxF}).mPortRet,2,'omitnan');
    
    % Standard deviation of return
    rResults.(cFields{iIdxF}).vStdRet = ...
        std(rResults.(cFields{iIdxF}).mPortRet,[],2,'omitnan');

    % t-Test
    if size(rResults.(cFields{iIdxF}).mPortRet, 2) <= 1
        rResults.(cFields{iIdxF}).vTstat = NaN(iNumPorts+1, 1);
        rResults.(cFields{iIdxF}).vPval = NaN(iNumPorts+1, 1);
    else
        [~,vPval,~,stats] = ttest(rResults.(cFields{iIdxF}).mPortRet');
        rResults.(cFields{iIdxF}).vTstat = stats.tstat';
        rResults.(cFields{iIdxF}).vPval = vPval';
    end
    
    % Sharpe Ratio and t-statistic of Sharpe ratio (Lo (2002))
    iAnnualize = find(strcmpi({'monthly','weekly','daily'},rOptions.sFreq));
    [rResults.(cFields{iIdxF}).vShp, rResults.(cFields{iIdxF}).vShpT] = ...
        fSharpeRatio(rResults.(cFields{iIdxF}).mPortRet,0,2,iAnnualize);

    % Calculate skewness and excess kurtosis (i.e., therefore -3)
    rResults.(cFields{iIdxF}).vSkewness = skewness(rResults.(cFields{iIdxF}).mPortRet,[],2);
    rResults.(cFields{iIdxF}).vKurtosis = kurtosis(rResults.(cFields{iIdxF}).mPortRet,[],2)-3;

    % Number of time-series observations
    rResults.(cFields{iIdxF}).vT = sum(~isnan(rResults.(cFields{iIdxF}).mPortRet),2);
    
    % Average number of assets
    rResults.(cFields{iIdxF}).vN = mean(mActNum,2,'omitnan');
    
    % === Maximum drawdown
    rResults.(cFields{iIdxF}).vMaxDrawdrown = fMaxDD(rResults.(cFields{iIdxF}).mPortRet, 2, 1);

    % === Portfolio turnover
    % Preserve the separately financed long-only legs.  Production calls use
    % the frozen-event ledger, so every exit is sold and reinvested within the
    % same leg before the next scheduled rebalance; cash never enters state.
    mWtsLegs = rResults.(cFields{iIdxF}).mWts;
    lTargetDefinedLegs = any(isfinite(mWtsLegs) & mWtsLegs ~= 0,1);
    mWtsLegs(~isfinite(mWtsLegs)) = 0;
    lTargetDefinedHedge = ...
        lTargetDefinedLegs(:,:,1) & lTargetDefinedLegs(:,:,end);
    lTargetDefined = cat(3,lTargetDefinedLegs,lTargetDefinedHedge);

    mCurrentRet = repmat(mRet,1,1,iNumPorts);
    lCurrentHolding = mWtsLegs ~= 0;
    lMissingCurrentHoldingRet = lCurrentHolding & ~isfinite(mCurrentRet);
    mCurrentRet(~lCurrentHolding & ~isfinite(mCurrentRet)) = 0;
    mForcedSaleFullLeg = zeros(iNumObs,iNumPorts);

    % Add the zero-investment hedge target only for reporting.  Its trading
    % cost and turnover are built from its two independently financed legs,
    % never from a netted hedge wealth denominator.
    if rOptions.iHedgeSign == 1
        mWtsTemp = cat(3,mWtsLegs,mWtsLegs(:,:,end)-mWtsLegs(:,:,1));
    else
        mWtsTemp = cat(3,mWtsLegs,mWtsLegs(:,:,1)-mWtsLegs(:,:,end));
    end

    % A payoff can be complete only for an actually formed target.  Without
    % this conjunction, a formation gap with zero selected holdings would be
    % incorrectly labelled as a complete payoff.
    mTargetDefined = permute(lTargetDefined,[3,2,1]);
    if lUseSameLegReinvestment
        mPayoffComplete = mTargetDefined & ...
            isfinite(rResults.(cFields{iIdxF}).mPortRet);
    else
        mPayoffComplete = mTargetDefined & ...
            rResults.(cFields{iIdxF}).mMissingPayoffHoldings == 0;
    end
    rResults.(cFields{iIdxF}).lTargetDefined = mTargetDefined;
    rResults.(cFields{iIdxF}).lPayoffComplete = mPayoffComplete;

    % Observable-transition episode accounting.  The first-ever target is a
    % genuine initial formation from cash.  Thereafter a transition is
    % identified only across adjacent defined targets when every prior
    % holding payoff and the drifted prior wealth are observable.  A middle
    % formation gap breaks the chain: the first target after the gap seeds a
    % new episode but is not treated as a fictitious cash entry.
    lFalseTarget = false(1,1,iNumPorts+1);
    lPreviousTarget = cat(2,lFalseTarget, ...
        lTargetDefined(:,1:end-1,:));
    lEverDefinedBefore = cat(2,lFalseTarget, ...
        cummax(lTargetDefined(:,1:end-1,:),2));
    lFirstEverTarget = lTargetDefined & ~lEverDefinedBefore;
    lRestartAfterGap = lTargetDefined & ...
        ~lPreviousTarget & lEverDefinedBefore;
    lPayoffComplete3 = permute(mPayoffComplete,[3,2,1]);
    lPriorPayoffComplete = cat(2,lFalseTarget, ...
        lPayoffComplete3(:,1:end-1,:));

    % Column t's target legs are compared with the end-of-week t-1 risky
    % legs.  Under the event-ledger path those prior end weights already
    % include every within-week sale and same-leg reinvestment.  Using r_t
    % here would look one period ahead.
    mWtsLegsL1 = cat(2,zeros(iNumAssets,1,iNumPorts), ...
        mWtsLegs(:,1:end-1,:));
    if lUseSameLegReinvestment
        mEndRiskyLegs = rResults.(cFields{iIdxF}).mEndRiskyWts;
        mWtsDriftedLegs = cat(2,zeros(iNumAssets,1,iNumPorts), ...
            mEndRiskyLegs(:,1:end-1,:));
        lInvalidEndState = any(~isfinite(mEndRiskyLegs),1);
        lInvalidPrevWealth = cat(2,false(1,1,iNumPorts), ...
            lInvalidEndState(:,1:end-1,:));
        lMissingPrevHoldingRet = repmat( ...
            cat(2,false(1,1,iNumPorts), ...
            ~lPayoffComplete3(:,1:end-1,1:iNumPorts)), ...
            [iNumAssets,1,1]);
    else
    mRetDriftL1 = [zeros(iNumAssets,1), mRet(:,1:end-1)];
    mRetDrift = repmat(mRetDriftL1,1,1,iNumPorts);
    lMissingPrevHoldingRet = (mWtsLegsL1 ~= 0) & ~isfinite(mRetDrift);
    mRetDrift(mWtsLegsL1 == 0 & ~isfinite(mRetDrift)) = 0;
    mPrevGrowth = mWtsLegsL1 .* (1+mRetDrift);
    mPrevWealth = sum(mPrevGrowth,1,'omitnan');
    mWtsDriftedLegs = mPrevGrowth ./ mPrevWealth;

    lHasPrevPosition = any(mWtsLegsL1 ~= 0,1);
    lInvalidPrevWealth = lHasPrevPosition & ...
        (~isfinite(mPrevWealth) | mPrevWealth <= 0);
    lUndefinedDrift = repmat(any(lMissingPrevHoldingRet, 1) | ...
        lInvalidPrevWealth, [iNumAssets, 1, 1]);
    mWtsDriftedLegs(lUndefinedDrift) = NaN;
    end

    % Only the first-ever formation is known to start from cash.  A target
    % after a middle gap has an unobserved entry state and must remain NaN.
    lInitialPositionLegs = repmat(lFirstEverTarget(:,:,1:iNumPorts), ...
        [iNumAssets,1,1]);
    mWtsDriftedLegs(lInitialPositionLegs) = 0;

    lObservableTransition = lFirstEverTarget | ...
        (lTargetDefined & lPreviousTarget & lPriorPayoffComplete & ...
         ~cat(3,any(lMissingPrevHoldingRet,1),false(1,iNumObs,1)) & ...
         ~cat(3,lInvalidPrevWealth,false(1,iNumObs,1)));
    % Hedge observability is exactly the intersection of its two legs.
    lObservableTransition(:,:,end) = ...
        lObservableTransition(:,:,1) & ...
        lObservableTransition(:,:,end-1);

    mOpeningTradeFullLeg = permute(sum(abs(mWtsLegs-mWtsDriftedLegs), ...
        1,'omitnan'),[2,3,1]);
    lObservableLeg = permute(lObservableTransition(:,:,1:iNumPorts), ...
        [2,3,1]);
    mOpeningTradeFullLeg(~lObservableLeg) = NaN;
    if lUseSameLegReinvestment
        mForcedSaleFullLeg = ...
            rResults.(cFields{iIdxF}).mWithinWeekTradeCostBaseFull;
        lCurrentCompleteLeg = isfinite(mForcedSaleFullLeg);
    else
        lCurrentCompleteLeg = permute(~any(lMissingCurrentHoldingRet,1), ...
            [2,3,1]);
        mForcedSaleFullLeg(~lCurrentCompleteLeg) = NaN;
    end
    mCostBaseFullLeg = mOpeningTradeFullLeg+mForcedSaleFullLeg;

    % Full cost base includes both the opening/rebalance trade and any
    % within-week sale-and-reinvestment trades. H-L costs are the sum of the two
    % independently financed legs.
    mCostBaseFull = [mCostBaseFullLeg, ...
        mCostBaseFullLeg(:,1)+mCostBaseFullLeg(:,end)];
    mOpeningTradeFull = [mOpeningTradeFullLeg, ...
        mOpeningTradeFullLeg(:,1)+mOpeningTradeFullLeg(:,end)];
    mForcedSaleFull = [mForcedSaleFullLeg, ...
        mForcedSaleFullLeg(:,1)+mForcedSaleFullLeg(:,end)];

    % GKX reports one half of full L1 for each leg.  The displayed H-L
    % turnover is the average of the two leg turnover measures.
    mTurnoverGKXLeg = 0.5*mCostBaseFullLeg;
    mTurnoverGKX = [mTurnoverGKXLeg, ...
        0.5*(mTurnoverGKXLeg(:,1)+mTurnoverGKXLeg(:,end))];

    mTurnoverGKX(~permute(lObservableTransition,[2,3,1])) = NaN;
    mCostBaseFull(~permute(lObservableTransition,[2,3,1])) = NaN;
    mOpeningTradeFull(~permute(lObservableTransition,[2,3,1])) = NaN;
    mForcedSaleFull(~permute(lObservableTransition,[2,3,1])) = NaN;
    mChWtsSimple = mCostBaseFull;
    mWtsTempL0 = mWtsTemp;
    rResults.(cFields{iIdxF}).mCostBaseFull = mCostBaseFull;
    rResults.(cFields{iIdxF}).mOpeningTradeCostBaseFull = ...
        mOpeningTradeFull;
    rResults.(cFields{iIdxF}).mForcedLiquidationCostBaseFull = ...
        mForcedSaleFull;
    rResults.(cFields{iIdxF}).mPriorEndRiskyWeightsAtTransition = ...
        mWtsDriftedLegs;
    rResults.(cFields{iIdxF}).lObservableTransition = ...
        permute(lObservableTransition,[3,2,1]);
    rResults.(cFields{iIdxF}).lFirstEverTarget = ...
        permute(lFirstEverTarget,[3,2,1]);
    rResults.(cFields{iIdxF}).lRestartAfterGap = ...
        permute(lRestartAfterGap,[3,2,1]);
    rResults.(cFields{iIdxF}).lPriorPayoffMissingTransition = ...
        permute(lTargetDefined & lPreviousTarget & ...
        ~lPriorPayoffComplete,[3,2,1]);

    % Calculate breakeven transaction costs
    % Costs remain observable from target weights when a realized return is
    % missing, but breakeven calculations must compare returns and costs on
    % the same dates.
    mCostBasePaired = mCostBaseFull;
    mCostBasePaired(~isfinite(rResults.(cFields{iIdxF}).mPortRet')) = NaN;
    mGrossRetPaired = rResults.(cFields{iIdxF}).mPortRet';
    mGrossRetPaired(~isfinite(mCostBasePaired)) = NaN;
    rResults.(cFields{iIdxF}).mCostBasePaired = mCostBasePaired;
    rResults.(cFields{iIdxF}).mGrossRetPairedForBETC = ...
        mGrossRetPaired;
    lEverDefinedBeforePT = ...
        permute(lEverDefinedBefore,[3,2,1]);
    lEverDefinedAfterPT = ...
        fliplr(cummax(fliplr(mTargetDefined),2));
    lInternalFormationGap = ~mTargetDefined & ...
        lEverDefinedBeforePT & lEverDefinedAfterPT;
    rResults.(cFields{iIdxF}).lInternalFormationGap = ...
        lInternalFormationGap;
    rAccountingCounts = struct();
    rAccountingCounts.vTargetN = sum(mTargetDefined,2);
    rAccountingCounts.vGrossN = sum(isfinite( ...
        rResults.(cFields{iIdxF}).mPortRet),2);
    rAccountingCounts.vRawCostN = sum(isfinite(mCostBaseFull),1)';
    rAccountingCounts.vPairedN = sum(isfinite(mCostBasePaired),1)';
    rAccountingCounts.vForcedLiquidationWeekN = ...
        sum(isfinite(mForcedSaleFull) & mForcedSaleFull > 0,1)';
    rAccountingCounts.vForcedLiquidationCostBase = ...
        sum(mForcedSaleFull,1,'omitnan')';
    rAccountingCounts.vInternalFormationGapN = ...
        sum(lInternalFormationGap,2);
    rAccountingCounts.vRestartAfterGapN = sum( ...
        rResults.(cFields{iIdxF}).lRestartAfterGap,2);
    rAccountingCounts.vPriorPayoffMissingTransitionN = sum( ...
        rResults.(cFields{iIdxF}).lPriorPayoffMissingTransition,2);
    rResults.(cFields{iIdxF}).rAccountingCounts = rAccountingCounts;
    vAvgCostBase = mean(mCostBasePaired,1,'omitnan')';
    % Both sides of the breakeven identity must use exactly the same
    % asset-week support.  The descriptive gross mean above intentionally
    % remains an all-observed-return statistic, but it is not a valid BETC
    % numerator when transition costs are missing on a subset of those
    % dates.
    vAvgGrossPaired = mean(mGrossRetPaired,1,'omitnan')';
    vBreakEvenTC = vAvgGrossPaired ./ vAvgCostBase;
    vBreakEvenTC(~isfinite(vAvgCostBase) | vAvgCostBase <= 0) = NaN;
    rResults.(cFields{iIdxF}).vBreakEvenTC = vBreakEvenTC;
    rResults.(cFields{iIdxF}).vAvgGrossPairedForBETC = ...
        vAvgGrossPaired;
    
    % Control: Calculate net returns after transaction costs (should be zero)
    mTradingCosts  = rResults.(cFields{iIdxF}).vBreakEvenTC' .* mCostBasePaired;
    vNetReturnsBTC = mean(mGrossRetPaired - mTradingCosts,1,'omitnan')';
    lCheckBETC = isfinite(vBreakEvenTC);
    assert(all(abs(vNetReturnsBTC(lCheckBETC)) <= 1e-10), ...
        'Paired-support net returns after BETC must be zero');
    rResults.(cFields{iIdxF}).vNetReturnAtBETC = vNetReturnsBTC;

    % Calculate BETC rates at which the net return is not significant 
    % at the 5% significance level
    vBETC = NaN(iNumPorts+1,1);
    for iIdxP = 1:iNumPorts+1
        vBETC(iIdxP) = fBreakevenTCFromCosts(rResults.(cFields{iIdxF}).mPortRet(iIdxP,:)',mCostBasePaired(:,iIdxP),  "dAlpha",0.05);
    end
    rResults.(cFields{iIdxF}).vBreakEvenTC_5pct = vBETC;
    
    % Calculate actual net returns using assumed transaction cost rate
    if ~isempty(rOptions.vTC)
        % Exlude long-short portfolio for now. We consider long-only portfolios first
        mCostBaseTemp = mCostBasePaired(:,1:end-1); 

        % Calculate net profits after transaction costs with long-only fees
        tc                  = rOptions.vTC(end); % Second position is long tc rate
        mTradingCostsLong   = (tc * mCostBaseTemp)';

        % Calculate net profits after transaction costs with short fees
        % for low portfolio
        if rOptions.iHedgeSign == 1
            % Short the low portfolio
            mChWtsShort = mCostBaseTemp(:,1);
            mChWtsLong  = mCostBaseTemp(:,end);
        else
            % Short the high portfolio
            mChWtsLong  = mCostBaseTemp(:,1);
            mChWtsShort = mCostBaseTemp(:,end);
        end

        % Calculate long-short trading costs
        vTradingCostsLongShort = (rOptions.vTC(1) * mChWtsShort + ...
            rOptions.vTC(2) * mChWtsLong)';
           
        % Get overall trading costs
        mTradingCosts = [mTradingCostsLong; vTradingCostsLongShort];

        % Calculate net return
        rResults.(cFields{iIdxF}).mPortRetNet = rResults.(cFields{iIdxF}).mPortRet - mTradingCosts;

        % Mean of return
        rResults.(cFields{iIdxF}).vAvgRetNet = ...
            mean(rResults.(cFields{iIdxF}).mPortRetNet,2,'omitnan');
        
        % Std of return
        rResults.(cFields{iIdxF}).vStdRetNet = ...
            std(rResults.(cFields{iIdxF}).mPortRetNet,[],2,'omitnan');
        
        % Sharpe Ratio and t-statistic of Sharpe ratio
        iAnnualize = find(strcmpi({'monthly','weekly','daily'},rOptions.sFreq));
        [rResults.(cFields{iIdxF}).vShpNet, rResults.(cFields{iIdxF}).vShpNetT] = ...
            fSharpeRatio(rResults.(cFields{iIdxF}).mPortRetNet,0,2,iAnnualize);

        % t-Test 
        [~,vPval,~,stats] = ttest(rResults.(cFields{iIdxF}).mPortRetNet');
        rResults.(cFields{iIdxF}).vTstatNet = stats.tstat';
        rResults.(cFields{iIdxF}).vPvalNet = vPval';
    end

    % Calculate turnover of portfolios (average of percentage weight change)
    mPctChange                          = mChWtsSimple./...
        permute(sum(abs(mWtsTempL0),1,'omitnan'),[2,3,1]);
    rResults.(cFields{iIdxF}).vTurnover = mean(mPctChange, 1, 'omitnan');

    rResults.(cFields{iIdxF}).vTurnoverGKX = mean(mTurnoverGKX, 1, 'omitnan')';

    % === Regression of portfolio returns on risk factors
    % Initialize memory (gross alphas)
    vAlpha      = NaN(iNumPorts+1,1);
    vAlphaT     = NaN(iNumPorts+1,1);
    vAlphaP     = NaN(iNumPorts+1,1);

    % Initialize memory (net alphas)
    vAlphaNet   = NaN(iNumPorts+1,1);
    vAlphaT_Net = NaN(iNumPorts+1,1);
    vAlphaP_Net = NaN(iNumPorts+1,1);

    if ~isempty(mIndepVars)
        for iIdxP = 1:iNumPorts+1
            % Get portfolio returns
            vYtemp = rResults.(cFields{iIdxF}).mPortRet(iIdxP,:)'; % T x 1
            if ~isempty(rOptions.vTC)
                vYnet   = rResults.(cFields{iIdxF}).mPortRetNet(iIdxP,:)'; % T x 1
            end

            % Copy factors
            mXtemp = mIndepVars'; % T x K
            
            % Remove missing values
            lIsNaN              = any(isnan(mXtemp),2) | isnan(vYtemp);
            vYtemp(lIsNaN)      = [];
            mXtemp(lIsNaN,:)    = [];
            if ~isempty(rOptions.vTC)
                vYnet(lIsNaN)   = [];
            end

            % Regression if sufficient number of observations
            if length(vYtemp) >= 30
                % Regression of gross returns on risk factors
                [vBetaTemp, vTstatTemp] = fRegstatsTstatSafe(vYtemp, mXtemp);
                vAlpha(iIdxP) = vBetaTemp(1);
                vAlphaT(iIdxP) = vTstatTemp(1);

                % Regression of net returns on risk factors
                if ~isempty(rOptions.vTC)
                    [vBetaTemp, vTstatTemp] = fRegstatsTstatSafe(vYnet, mXtemp);
                    vAlphaNet(iIdxP)    = vBetaTemp(1);
                    vAlphaT_Net(iIdxP)  = vTstatTemp(1);
                end
            end
        end
    end
    rResults.(cFields{iIdxF}).vAlpha        = vAlpha;
    rResults.(cFields{iIdxF}).vAlphaT       = vAlphaT;
    rResults.(cFields{iIdxF}).vAlphaNet     = vAlphaNet;
    rResults.(cFields{iIdxF}).vAlphaNetT    = vAlphaT_Net;

    % Create table which stores the average sorting variable (AvgSV),
    % average portfolio return (Avg), t-statistic (tStat), standard
    % deviation (Std), annualized Sharpe ratio (Shp), number of
    % time-series observations (T), average number of assets (N), and
    % regression alphas (Alpha) and t-statistics (Alpha tStat)
    cColHeader = {'Port', 'AvgSV' 'Avg','tStat','Std','Shp','T','N','Alpha','Alpha tStat'};
    mSummary = [[(1:iNumPorts)'; NaN], ...
        rResults.(cFields{iIdxF}).vAvgSortVar(:), ...
        rResults.(cFields{iIdxF}).vAvgRet(:) * 100, ...
        rResults.(cFields{iIdxF}).vTstat(:),...
        rResults.(cFields{iIdxF}).vStdRet(:) * 100, ...
        rResults.(cFields{iIdxF}).vShp(:),...
        rResults.(cFields{iIdxF}).vT(:),...
        rResults.(cFields{iIdxF}).vN(:),...
        vAlpha(:) * 100, ...
        vAlphaT(:)];
    cTable = [cColHeader;sprintfc('%.2f',mSummary)]; % To cell-array
    
    % First column constains the portfolio numbers. Make to integer not
    % floating point number with two digits
    cTable(2:end-1,1) = cellfun(@(x)x(1),cTable(2:end-1,1),'UniformOutput',false);

    % Save table to struct
    rResults.(cFields{iIdxF}).cTable = cTable;
end

% Save portfolio composition
rResults.mActNum   = mActNum;
rResults.mIndex    = mIndex;
rResults.mExpNum   = mExpNum;
end

function mOut = iZeroOutside(mIn)
mOut = mIn;
mOut(~isfinite(mOut)) = 0;
end
