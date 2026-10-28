function [mPnlReturns,mPnlRetLead,mClosePnlBoundary, ...
        mClosePnlFormationDay,vDatesWeek,rDiagnostics, ...
        mRequiresReinvestment,mRequiresReinvestmentLead,rLedger] = ...
    fBuildWeeklyEndpointPnl( ...
    mClosePnlRaw,vDates,mMEEconomicRaw,vAssetID,tExitCalendar)
% Build weekly endpoint payoffs and the no-cash reinvestment event ledger.
%
% Intermediate missing closes have already been filled by b01 from the
% strictly previous close.  A frozen terminal date before the scheduled
% holding-period endpoint therefore creates a finite last-trade payoff and
% a reinvestment event.  Portfolio-specific proceeds are assigned later,
% after leg membership is known; this function never leaves them in cash.

arguments
    mClosePnlRaw (:,:) {mustBeNumeric}
    vDates (:,1) {mustBeNumericOrDatetime}
    mMEEconomicRaw (:,:) {mustBeNumeric} = []
    vAssetID (:,1) {mustBeNumeric} = []
    tExitCalendar table = table()
end

[iNumDates,iNumAssets] = size(mClosePnlRaw);
if isempty(mMEEconomicRaw)
    mMEEconomicRaw = NaN(iNumDates,iNumAssets);
end
if isempty(vAssetID)
    vAssetID = (1:iNumAssets)';
end
if isempty(tExitCalendar)
    tExitCalendar = iInMemoryExitCalendar(mClosePnlRaw,vAssetID);
end

[rLedger,mPnlReturns,mPnlRetLead,rDiagnostics] = ...
    fBuildWeeklyReinvestmentLedger( ...
    mClosePnlRaw,mMEEconomicRaw,vDates,vAssetID,tExitCalendar);
mClosePnlBoundary = rLedger.mBoundaryClose;
mClosePnlFormationDay = rLedger.mFormationClose;
vDatesWeek = rLedger.vWeekDate;
mRequiresReinvestment = rLedger.lOrdinaryEarlyExit;
mRequiresReinvestmentLead = rLedger.lLeadEarlyExit;
rDiagnostics.sOrdinaryIdentity = ...
    'frozen_exit_or_scheduled_boundary / scheduled_prior_boundary - 1';
rDiagnostics.sLag1Identity = ...
    'frozen_exit_or_next_formation / scheduled_current_formation - 1';
rDiagnostics.sExitUse = ...
    'immediate same-leg reinvestment; never cash';
rDiagnostics.iNumOrdinaryReinvestmentEvents = ...
    nnz(mRequiresReinvestment);
rDiagnostics.iNumLag1ReinvestmentEvents = ...
    nnz(mRequiresReinvestmentLead);
rDiagnostics.lIntermediateMissingAffectsEndpointPayoff = false;
rDiagnostics.lTrailingMissingSettlesAtFrozenLastTradable = true;
rDiagnostics.lProceedsRemainCash = false;
rDiagnostics.lAppliesOutlierTransform = false;
end

function tExit = iInMemoryExitCalendar(mClose,vAssetID)
iNumDates = size(mClose,1);
iNumAssets = size(mClose,2);
vLast = NaN(iNumAssets,1);
vPrice = NaN(iNumAssets,1);
for iIdxA = 1:iNumAssets
    iLast = find(isfinite(mClose(:,iIdxA)) & mClose(:,iIdxA) > 0,1,'last');
    if ~isempty(iLast)
        vLast(iIdxA) = iLast;
        vPrice(iIdxA) = mClose(iLast,iIdxA);
    end
end
lExit = isfinite(vLast) & vLast < iNumDates;
lRight = isfinite(vLast) & vLast == iNumDates;
lExternal = false(iNumAssets,1);
tExit = table(vAssetID(:),vLast,vPrice,lExit,lRight,lExternal, ...
    'VariableNames',{'asset_id','last_tradable_index', ...
    'last_tradable_price','mechanical_exit','right_censored', ...
    'uses_external_source'});
end
