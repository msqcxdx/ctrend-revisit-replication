function [vHedgeRet,rCoverage] = fExtendedHoldingPeriodVW( ...
        mSortVar,mRet,mME,vQuantiles,iHoldingPeriod,iIdxFirst, ...
        iMinNumCS,iMinNumAssets,rLedger,vLedgerWeekRow)
% Form fixed, non-overlapping H-week value-weighted long-short cohorts.
%
% Members and initial weights are selected once at each block formation.
% Their weights then drift with realized endpoint returns.  A frozen exit
% inside the block is sold at its last tradable quote and the proceeds are
% immediately allocated, by event-day market capitalization, among the
% surviving members of the same leg.  No new member is admitted, no cash is
% retained, and no value is transferred between the low and high legs.

[iNumAssets,iNumObs] = size(mSortVar);
iNumPorts = length(vQuantiles)-1;
assert(isequal(size(mRet),[iNumAssets,iNumObs]) && ...
    isequal(size(mME),[iNumAssets,iNumObs]), ...
    'Return, market-cap, and sorting-variable dimensions must agree');
assert(isvector(vQuantiles) && numel(vQuantiles) >= 2 && ...
    all(isfinite(vQuantiles)) && all(diff(vQuantiles) > 0) && ...
    vQuantiles(1) == 0 && vQuantiles(end) == 1, ...
    'Quantile endpoints must be strictly increasing from zero to one');
vQuantiles = vQuantiles(:);
assert(isscalar(iHoldingPeriod) && isfinite(iHoldingPeriod) && ...
    iHoldingPeriod >= 1 && iHoldingPeriod == fix(iHoldingPeriod), ...
    'Holding period must be a positive integer');
assert(isscalar(iIdxFirst) && isfinite(iIdxFirst) && iIdxFirst >= 1 && ...
    iIdxFirst == fix(iIdxFirst),'First formation index must be positive');
assert(isscalar(iMinNumCS) && isfinite(iMinNumCS) && iMinNumCS >= 1 && ...
    iMinNumCS == fix(iMinNumCS), ...
    'Minimum cross-section size must be a positive integer');
assert(isscalar(iMinNumAssets) && isfinite(iMinNumAssets) && ...
    iMinNumAssets >= 1 && iMinNumAssets == fix(iMinNumAssets), ...
    'Minimum portfolio size must be a positive integer');
assert(isstruct(rLedger) && numel(vLedgerWeekRow) == iNumObs, ...
    'Extended-holding input must include the authenticated economic ledger');
vLedgerWeekRow = vLedgerWeekRow(:);

vHedgeRet = NaN(iNumObs,1);
rCoverage = struct();
rCoverage.lFormationValid = false(iNumObs,1);
rCoverage.lPayoffComplete = false(iNumObs,1);
rCoverage.vUnavailableAtFormationCount = zeros(iNumObs,1);
rCoverage.vExitHoldingCount = zeros(iNumObs,1);
rCoverage.vReinvestmentEventCount = zeros(iNumObs,1);
rCoverage.vReinvestedProceedsLow = NaN(iNumObs,1);
rCoverage.vReinvestedProceedsHigh = NaN(iNumObs,1);
rCoverage.vWithinWeekFullL1Low = NaN(iNumObs,1);
rCoverage.vWithinWeekFullL1High = NaN(iNumObs,1);
rCoverage.lNoEligibleRecipient = false(iNumObs,1);
rCoverage.lEndCashAlwaysZero = true;
rCoverage.lCrossLegTransfer = false;
rCoverage.lPartialTailBlock = false(iNumObs,1);
if iIdxFirst > iNumObs
    return
end

% Preserve the Dataverse non-overlapping block phase (1,1+H,...).  A block
% formed before the first OOS signal simply remains missing.
for iIdxStart = 1:iHoldingPeriod:iNumObs
    iIdxEnd = min(iIdxStart+iHoldingPeriod-1,iNumObs);
    vSortFormation = mSortVar(:,iIdxStart);
    vMEFormation = mME(:,iIdxStart);
    lProposed = isfinite(vSortFormation) & isfinite(vMEFormation) & ...
        vMEFormation > 0;
    % A finite endpoint payoff verifies a positive entry quote.  An asset
    % that exits later in this target week remains finite and is therefore
    % admitted; its frozen exit is handled by the event ledger below.
    lAvailable = lProposed & isfinite(mRet(:,iIdxStart));
    rCoverage.vUnavailableAtFormationCount(iIdxStart:iIdxEnd) = ...
        nnz(lProposed & ~lAvailable);
    if sum(lAvailable) < iMinNumCS
        continue
    end

    vBreaks = quantile(vSortFormation(lAvailable),vQuantiles,1, ...
        'Method','exact');
    cMembers = cell(iNumPorts,1);
    lFormationValid = true;
    for iIdxP = 1:iNumPorts
        if iIdxP == 1
            lMember = lAvailable & vSortFormation >= vBreaks(iIdxP) & ...
                vSortFormation <= vBreaks(iIdxP+1);
        else
            lMember = lAvailable & vSortFormation > vBreaks(iIdxP) & ...
                vSortFormation <= vBreaks(iIdxP+1);
        end
        cMembers{iIdxP} = lMember;
        lFormationValid = lFormationValid && sum(lMember) >= iMinNumAssets;
    end
    if ~lFormationValid
        continue
    end
    rCoverage.lFormationValid(iIdxStart:iIdxEnd) = true;
    if iIdxEnd-iIdxStart+1 < iHoldingPeriod
        rCoverage.lPartialTailBlock(iIdxStart:iIdxEnd) = true;
    end

    vWtsLow = iInitialValueWeights(vMEFormation,cMembers{1});
    vWtsHigh = iInitialValueWeights(vMEFormation,cMembers{end});
    lStateValid = all(isfinite(vWtsLow)) && all(isfinite(vWtsHigh));
    for iIdxT = iIdxStart:iIdxEnd
        if ~lStateValid
            continue
        end
        [dRetLow,vEndLow,dL1Low,rAuditLow] = ...
            fApplySameLegReinvestment(vWtsLow, rLedger, ...
            vLedgerWeekRow(iIdxT),'ordinary','VW');
        [dRetHigh,vEndHigh,dL1High,rAuditHigh] = ...
            fApplySameLegReinvestment(vWtsHigh,rLedger, ...
            vLedgerWeekRow(iIdxT),'ordinary','VW');
        rCoverage.vExitHoldingCount(iIdxT) = ...
            sum([rAuditLow.vExitedHoldingCount, ...
                 rAuditHigh.vExitedHoldingCount]);
        rCoverage.vReinvestmentEventCount(iIdxT) = ...
            sum([rAuditLow.vEventDateCount,rAuditHigh.vEventDateCount]);
        rCoverage.vReinvestedProceedsLow(iIdxT) = ...
            rAuditLow.vReinvestedProceeds;
        rCoverage.vReinvestedProceedsHigh(iIdxT) = ...
            rAuditHigh.vReinvestedProceeds;
        rCoverage.vWithinWeekFullL1Low(iIdxT) = dL1Low;
        rCoverage.vWithinWeekFullL1High(iIdxT) = dL1High;
        rCoverage.lNoEligibleRecipient(iIdxT) = ...
            rAuditLow.lNoEligibleRecipient | ...
            rAuditHigh.lNoEligibleRecipient;
        if ~isfinite(dRetLow) || ~isfinite(dRetHigh) || ...
                any(~isfinite(vEndLow)) || any(~isfinite(vEndHigh))
            lStateValid = false;
            continue
        end
        vHedgeRet(iIdxT) = dRetHigh-dRetLow;
        rCoverage.lPayoffComplete(iIdxT) = true;
        vWtsLow = vEndLow;
        vWtsHigh = vEndHigh;
        assert(abs(sum(vWtsLow)-1) <= 1e-10 && ...
            abs(sum(vWtsHigh)-1) <= 1e-10, ...
            'Extended-holding risky weights must stay fully invested');
    end
end
end

function vWeights = iInitialValueWeights(vMarketCap,lMember)
vWeights = zeros(size(vMarketCap));
dTotalMarketCap = sum(vMarketCap(lMember));
if ~isfinite(dTotalMarketCap) || dTotalMarketCap <= 0
    vWeights(:) = NaN;
    return
end
vWeights(lMember) = vMarketCap(lMember)./dTotalMarketCap;
end
