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
%       .lEnsureAllObs:     Logical, specifies whether to control for
%                           nonmissing returns (and market capitalization) 
%                           before calculating percentiles (default =
%                           true)
%       .sFreq:             Data Frequency (default = 'monthly');


%       .vTC:               2 x 1 vector of transaction costs.
%                           First element refers to short-selling costs and
%                           second element is the cost rate for long
%                           positions
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
lLedgerFields = [isfield(rOptions,'rReinvestmentLedger'), ...
    isfield(rOptions,'vLedgerWeekRow'),isfield(rOptions,'sPayoffTiming')];
assert(all(lLedgerFields) || ~any(lLedgerFields), ...
    'Economic ledger, week rows, and payoff timing must be supplied together');
lUseSameLegReinvestment = all(lLedgerFields);
if lUseSameLegReinvestment
    assert(ismember(rOptions.sPayoffTiming,{'ordinary','lead1'}) && ...
        numel(rOptions.vLedgerWeekRow) == iNumObs, ...
        'Invalid economic-ledger timing or week-row axis');
end
% A missing economic payoff means the asset is known to be unavailable for
% this target week under the announcement-equivalence convention. Remove it
% before breakpoints and reallocate over tradable assets, as M0 does; return
% magnitude never enters this availability screen.
if rOptions.lEnsureAllObs
    lAvail = ~isnan(mSortVar) & ~isnan(mRet);

    if ~isempty(mME)
        % Check for nonmissing market value if passed to function
        lAvail = lAvail & ~isnan(mME);

        % Set to missing
        mME(~lAvail) = NaN;
    end    
    % Set to missing
    mSortVar(~lAvail)   = NaN;
end

% Require minimum cross-section. Otherwise the portfolio return will be
% missing
lNonAvailObs                = sum(~isnan(mSortVar),1) < rOptions.iMinNumCS;
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
mWts_ew         = NaN(iNumAssets, iNumObs, iNumPorts);  % Weights for equal-weighted portfolio
mWts_vw         = NaN(iNumAssets, iNumObs,iNumPorts);   % Weights for value-weighted portfolio
mEndWts_ew      = NaN(iNumAssets,iNumObs,iNumPorts);
mEndWts_vw      = NaN(iNumAssets,iNumObs,iNumPorts);
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
    mVarPort = mSortVar .* mIndx;

    % M2 retains M0's target-availability convention: when
    % lEnsureAllObs=true, unavailable target assets were removed before the
    % breakpoints and the remaining assets are reweighted.
    mWts_ew(:,:,iIdxP)      = ~isnan(mRetPort)./sum(~isnan(mRetPort),1);
    mPortRet_ew(iIdxP,:)    = mean(mRetPort,1,'omitmissing');
    mValSortVar_ew(iIdxP,:) = mean(mVarPort,1,'omitmissing');
    if lUseSameLegReinvestment
        [mPortRet_ew(iIdxP,:),mEndWts_ew(:,:,iIdxP), ...
            mWithinWeekFullL1_ew(iIdxP,:),cReinvestmentAuditEW{iIdxP}] = ...
            fApplySameLegReinvestment(mWts_ew(:,:,iIdxP), ...
            rOptions.rReinvestmentLedger,rOptions.vLedgerWeekRow, ...
            rOptions.sPayoffTiming,'EW');
    end

    % Expected number of assets in portfolio
    mExpNum(iIdxP,:)    = sum(mIndx,1,'omitmissing');
    
    % Actual number of assets in portfolio
    mActNum(iIdxP,:)    = sum(~isnan(mRetPort),1);

    % Get value weighted portfolio returns
    if ~isempty(mME)
        % Get market capitalization of all assets within portfolio
        mMktValPort = mME .* mIndx;

        % Calculate weights
        mWts = mMktValPort ./ sum(mMktValPort,1,'omitmissing');

        % Save weights
        mWts_vw(:,:,iIdxP) = mWts;

        % Find all time steps with only missing returns. We need this
        % logical because we will calculate the portfolio return using sum
        % along with the option 'omitmissing', which produces zeros if no
        % data is available. Thus, we use the following logical array to
        % set these returns to missing
        lNonAvailObs = all(isnan(mRetPort),1);

        % Calculate weighted portfolio return
        vPortRetTemp                = sum(mWts .* mRetPort,1,'omitmissing');
        vPortRetTemp(lNonAvailObs)  = NaN;
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
        vSortVarTemp(lNonAvailObs)  = NaN;
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

% Ensure that sufficient number of assets is in each portfolio
if rOptions.iMinNumAssets > 1
    if rOptions.lHedgeOnly
        lAvailObs = mActNum(1,:) >= rOptions.iMinNumAssets & ...
                mActNum(end-1,:) >= rOptions.iMinNumAssets;
    else
        lAvailObs = all(mActNum(1:end-1,:) >= rOptions.iMinNumAssets,1);
    end
    mPortRet_ew(:,~lAvailObs)       = NaN;
    mPortRet_vw(:,~lAvailObs)       = NaN;
    mValSortVar_ew(:,~lAvailObs)    = NaN;
    mValSortVar_vw(:,~lAvailObs)    = NaN;
    mActNum(:,~lAvailObs)           = NaN;
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
if ~isempty(mME)
    rResults.VW.mPortRet        = mPortRet_vw;
    rResults.VW.mValSortVar     = mValSortVar_vw;
    rResults.VW.mWts            = mWts_vw;
    rResults.VW.mEndRiskyWts    = mEndWts_vw;
    rResults.VW.mWithinWeekTradeCostBaseFull = mWithinWeekFullL1_vw';
    rResults.VW.cSameLegReinvestmentAudit = cReinvestmentAuditVW;
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
    [~,vPval,~,stats] = ttest(rResults.(cFields{iIdxF}).mPortRet');
    rResults.(cFields{iIdxF}).vTstat = stats.tstat';
    rResults.(cFields{iIdxF}).vPval = vPval';
    
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
    % Calculate cumulative return of each portfolio (Gu, Kelly, Xiu (2020))
    mCumRet     = cumsum(rResults.(cFields{iIdxF}).mPortRet, 2, 'omitnan');
    rResults.(cFields{iIdxF}).vMaxDrawdrown = max([NaN(iNumPorts + 1, 1), mCumRet(:,1:end-1) - mCumRet(:, 2:end)],[],2);

    % === Portfolio turnover
    % Get all weights and set missing values to zero
    mWtsTemp                    = rResults.(cFields{iIdxF}).mWts;
    mWtsTemp(isnan(mWtsTemp))   = 0;

    mWtsLegs = mWtsTemp;

    % Calculate long-short portfolio weights and add them
    if rOptions.iHedgeSign == 1
        % Long high, short low
        mWtsTemp = cat(3, mWtsTemp, mWtsTemp(:,:,end) - mWtsTemp(:,:,1));
    else
        % Long low, short high
        mWtsTemp = cat(3, mWtsTemp, mWtsTemp(:,:,1) - mWtsTemp(:,:,end));
    end

    % Weight matrix is now N x T x P, where P is number of portfolios,
    % including hedge portfolio

    % Get previous and current weights. Note that we add zeros to account
    % for initial portfolios that have only zero weights
    mWtsTempL1 = cat(2, zeros(iNumAssets, 1, iNumPorts+1), mWtsTemp(:,1:end-1,:));
    mWtsTempL0 = mWtsTemp;

    if lUseSameLegReinvestment
        mEndLegs = rResults.(cFields{iIdxF}).mEndRiskyWts;
        mEndLegs(~isfinite(mEndLegs)) = 0;
        mPriorEndLegs = cat(2,zeros(iNumAssets,1,iNumPorts), ...
            mEndLegs(:,1:end-1,:));
        mOpeningFullLeg = permute(sum(abs(mWtsLegs-mPriorEndLegs),1), ...
            [2,3,1]);
        mWithinFullLeg = ...
            rResults.(cFields{iIdxF}).mWithinWeekTradeCostBaseFull;
        mCostFullLeg = mOpeningFullLeg+mWithinFullLeg;
        lDefinedLeg = permute(any(mWtsLegs ~= 0,1),[2,3,1]);
        mCostFullLeg(~lDefinedLeg | ~isfinite(mWithinFullLeg)) = NaN;
        mChWts = [mCostFullLeg, ...
            mCostFullLeg(:,1)+mCostFullLeg(:,end)];
    else
        % Calculate the cross-sectional sum of absolute weight changes.
        mChWts = sum(abs(mWtsTempL1-mWtsTempL0),1);
        mChWts(all(mWtsTemp == 0,1)) = NaN;
        mChWts = permute(mChWts,[2,3,1]);
    end

    % Calculate breakeven transaction costs
    rResults.(cFields{iIdxF}).vBreakEvenTC = rResults.(cFields{iIdxF}).vAvgRet./mean(mChWts,1,'omitnan')';
    
    % Control: Calculate net returns after transaction costs (should be zero)
    mTradingCosts  = rResults.(cFields{iIdxF}).vBreakEvenTC' .* mChWts;
    vNetReturnsBTC = rResults.(cFields{iIdxF}).vAvgRet - mean(mTradingCosts, 1, 'omitnan')';
    if any(abs(vNetReturnsBTC)>1e-10)
        warning('Net returns after BETC are not zero');
    end

    % Calculate BETC rates at which the net return is not significant 
    % at the 5% significance level
    vBETC = NaN(iNumPorts+1,1);
    for iIdxP = 1:iNumPorts+1
        if lUseSameLegReinvestment
            vBETC(iIdxP) = fBreakevenTCFromCosts( ...
                rResults.(cFields{iIdxF}).mPortRet(iIdxP,:)', ...
                mChWts(:,iIdxP),'dAlpha',0.05);
        else
            vBETC(iIdxP) = fBreakevenTC( ...
                rResults.(cFields{iIdxF}).mPortRet(iIdxP,:), ...
                mWtsTemp(:,:,iIdxP),"dAlpha",0.05);
        end
    end
    rResults.(cFields{iIdxF}).vBreakEvenTC_5pct = vBETC;
    
    % Calculate actual net returns using assumed transaction cost rate
    if ~isempty(rOptions.vTC)
        % Exlude long-short portfolio for now. We consider long-only portfolios first
        mChWtsTemp = mChWts(:,1:end-1); 

        % Calculate net profits after transaction costs with long-only fees
        tc                  = rOptions.vTC(end); % Second position is long tc rate
        mTradingCostsLong   = (tc * mChWtsTemp)';

        % Calculate net profits after transaction costs with short fees
        % for low portfolio
        if rOptions.iHedgeSign == 1
            % Short the low portfolio
            mChWtsShort = mChWtsTemp(:,1);
            mChWtsLong  = mChWtsTemp(:,end);
        else
            % Short the high portfolio
            mChWtsLong  = mChWtsTemp(:,1);
            mChWtsShort = mChWtsTemp(:,end);
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
        rResults.(cFields{iIdxF}).vTstat = stats.tstat';
        rResults.(cFields{iIdxF}).vPval = vPval';
    end

    % Calculate turnover of portfolios (average of percentage weight change)
    mPctChange                          = mChWts./...
        permute(sum(abs(mWtsTempL0),1,'omitnan'),[2,3,1]);
    rResults.(cFields{iIdxF}).vTurnover = mean(mPctChange, 1, 'omitnan');

    % Calculate turnover as in Gu, Kelly, Xiu (2020).  At the formation of
    % target t, only the payoff earned by the preceding holdings (column
    % t-1) is known.  M0 used column t here, which is the future payoff of
    % the new target portfolio.  M2 changes only that timing index and
    % otherwise retains M0's turnover definition, including its initial
    % no-prior-position behavior.
    if lUseSameLegReinvestment
        mTurnoverGKX = 0.5*mChWts;
    else
        mRetDriftL1 = [zeros(iNumAssets,1), mRet(:,1:end-1)];
        mRetDrift = repmat(mRetDriftL1,1,1,size(mWtsTempL1,3));
        lPriorPayoffMissing = any(mWtsTempL1 ~= 0 & isnan(mRetDrift),1);
        mPriorGross = mWtsTempL1 .* (1 + mRetDrift);
        % A missing return for an asset not previously held contributes zero,
        % not NaN, to the drifted prior portfolio.
        mPriorGross(mWtsTempL1 == 0 & isnan(mRetDrift)) = 0;
        mWtsDrifted = mPriorGross ./ sum(mPriorGross,1,'omitnan');
        mTurnoverGKX = squeeze(0.5*sum(abs(mWtsTempL0-mWtsDrifted), ...
            1,'omitnan'));
        lPriorPayoffMissing = squeeze(lPriorPayoffMissing);
        mTurnoverGKX(lPriorPayoffMissing) = NaN;
    end

    % Turnover for long-short portfolio
    mTurnoverGKX(:,end) = (mTurnoverGKX(:,1) + mTurnoverGKX(:,end-1));
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
                rRegResults = regstats(vYtemp, mXtemp, 'linear', {'tstat'});
                vAlpha(iIdxP) = rRegResults.tstat.beta(1);
                vAlphaT(iIdxP) = rRegResults.tstat.t(1);
                vAlphaP(iIdxP) = rRegResults.tstat.pval(1);

                % Regression of net returns on risk factors
                if ~isempty(rOptions.vTC)
                    rRegResults         = regstats(vYnet, mXtemp, 'linear', {'tstat'});
                    vAlphaNet(iIdxP)    = rRegResults.tstat.beta(1);
                    vAlphaT_Net(iIdxP)  = rRegResults.tstat.t(1);
                    vAlphaP_Net(iIdxP)  = rRegResults.tstat.pval(1);
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
        rResults.(cFields{iIdxF}).vAvgSortVar, ...
        rResults.(cFields{iIdxF}).vAvgRet * 100, ...
        rResults.(cFields{iIdxF}).vTstat,...
        rResults.(cFields{iIdxF}).vStdRet * 100, ...
        rResults.(cFields{iIdxF}).vShp,...
        rResults.(cFields{iIdxF}).vT,...
        [rResults.(cFields{iIdxF}).vN],...
        vAlpha * 100, ...
        vAlphaT];
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
