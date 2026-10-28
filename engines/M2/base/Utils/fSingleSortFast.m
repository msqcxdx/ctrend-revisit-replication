function [vHedgePortEW, vHedgePortVW] = fSingleSortFast(mSortVar, mRet, mME, options)
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
%       .lEnsureAllObs:     Logical, specifies whether to control for
%                           nonmissing returns (and market capitalization) 
%                           before calculating percentiles (default =
%                           true)
%
% Output:
%   vHedgePortEW:       1 x T vector of ew hedge portfolio return
%                       T: number of time-series observations
%   vHedgePortVW:       1 x T vector of vw hedge portfolio return
%                       T: number of time-series observations

%% Check inputs
arguments
    mSortVar (:,:) {mustBeNumeric}
    mRet (:,:) {mustBeNumeric}
    mME (:,:) {mustBeNumeric} = []
    options.vPercentile (:,1) {mustBeNumeric, mustBeNonnegative}    = (0:0.5:1)'
    options.iMinNumCS (1,1) {mustBeNumeric, mustBeNonnegative}      = 1
    options.iMinNumAssets(1,1) {mustBeNumeric, mustBeNonnegative}   = 1
    options.lEnsureAllObs (1,1) {mustBeNumericOrLogical, mustBeNonnegative} = true
    options.rReinvestmentLedger struct = struct()
    options.vLedgerWeekRow (:,1) {mustBeNumeric} = zeros(0,1)
    options.sPayoffTiming char = ''
end

% Determine dimensions
[iNumAssets, iNumObs]   = size(mSortVar);
iNumPorts               = length(options.vPercentile)-1;

% Control dimensions
assert(iNumAssets == size(mRet,1), 'Number of assets must agree');
assert(iNumObs == size(mRet,2), 'Number of observations must agree');
lUseLedger = ~isempty(fieldnames(options.rReinvestmentLedger));
assert(lUseLedger == ~isempty(options.vLedgerWeekRow) && ...
    lUseLedger == ~isempty(options.sPayoffTiming), ...
    'Economic ledger, week rows, and timing must be supplied together');
if lUseLedger
    assert(ismember(options.sPayoffTiming,{'ordinary','lead1'}) && ...
        numel(options.vLedgerWeekRow) == iNumObs, ...
        'Invalid economic-ledger timing or week-row axis');
end

% Ensure that return and market capitalization are available
if options.lEnsureAllObs
    lAvail = ~isnan(mRet);
    if ~isempty(mME)
        lAvail  = lAvail & ~isnan(mME);

        % Set to missing
        mME(~lAvail) = NaN;
    end    
    mSortVar(~lAvail) = NaN;
end

% Ensure minimum cross-section
lNonAvailObs                = sum(~isnan(mSortVar),1) < options.iMinNumCS;
mSortVar(:,lNonAvailObs)    = NaN;

% Calculate quantiles
mQuantiles = quantile(mSortVar, options.vPercentile, 1, 'Method','exact');

% Preallocate memory
mPortRet_ew = NaN(iNumPorts,iNumObs);     % Equal-weighted portfolio returns
mPortRet_vw = NaN(iNumPorts,iNumObs);     % Value-weighted portfolio returns

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
    
    % Get returns and sorting variable of assets in portfolio P. Now we
    % will have a variable mRetPort that has only observations for the 
    % returns if the respective asset is in the current portfolio
    mRetPort = mRet .* mIndx;

    % Get equal weighted portfolio returns
    mPortRet_ew(iIdxP,:) = mean(mRetPort,1,'omitnan');
    if lUseLedger
        mEW = double(isfinite(mIndx));
        mEW = mEW./sum(mEW,1);
        mPortRet_ew(iIdxP,:) = fApplySameLegReinvestment( ...
            mEW,options.rReinvestmentLedger,options.vLedgerWeekRow, ...
            options.sPayoffTiming,'EW');
    end

    % Get value weighted portfolio returns
    if ~isempty(mME)
        % Get market capitalization of all assets within portfolio
        mMktValPort     = mME .* mIndx;

        % Calculate weights
        mWts            = mMktValPort ./ sum(mMktValPort,1,'omitmissing');

        % Find all time steps with only missing returns
        lNonAvailObs = all(isnan(mRetPort),1);

        % Calculate weighted portfolio return
        vPortRetTemp                = sum(mWts .* mRetPort,1,'omitnan');

        % omitmissing in sum may cause zeros if all observations are
        % missin. Control for that
        vPortRetTemp(lNonAvailObs)  = NaN;

        % Save portfolio return
        mPortRet_vw(iIdxP,:)        = vPortRetTemp;
        if lUseLedger
            mPortRet_vw(iIdxP,:) = fApplySameLegReinvestment( ...
                mWts,options.rReinvestmentLedger,options.vLedgerWeekRow, ...
                options.sPayoffTiming,'VW');
        end
    end
end

% Calculate hedge portfolio
vHedgePortEW = (mPortRet_ew(end,:) - mPortRet_ew(1,:))';
vHedgePortVW = (mPortRet_vw(end,:) - mPortRet_vw(1,:))';
end
