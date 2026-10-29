function [vPortReturn,mEndRiskyWeights,vWithinWeekFullL1,rAudit] = ...
    fApplySameLegReinvestment( ...
    mFormationWeights,rLedger,vLedgerWeekRow,sTiming,sAllocation)
% Value a long-only portfolio leg with immediate within-leg reinvestment.
%
% At every frozen terminal event, the exiting position is sold at its last
% positive close.  The proceeds are invested immediately in the surviving
% original members of that same leg.  EW divides only the released proceeds
% equally; VW divides them by event-day current market capitalisation.  The
% rest of the leg is not rebalanced.  Cash and cross-leg transfers are never
% permitted.  When positive proceeds have no eligible same-leg recipient,
% the leg fails closed.

arguments
    mFormationWeights (:,:) {mustBeNumeric}
    rLedger (1,1) struct
    vLedgerWeekRow (:,1) {mustBeNumeric}
    sTiming {mustBeMember(sTiming,{'ordinary','lead1'})}
    sAllocation {mustBeMember(sAllocation,{'EW','VW'})}
end

[iNumAssets,iNumObs] = size(mFormationWeights);
cRequired = {'sFormat','vAssetID','vWeekStartIndex','vWeekEndIndex', ...
    'vLastTradableIndex','vEventRowByDailyIndex','mEventClose', ...
    'mEventME','mBoundaryClose','mFormationClose', ...
    'lUsesExternalSource','lAllowsCashAfterExit'};
assert(all(isfield(rLedger,cRequired)) && ...
    strcmp(rLedger.sFormat,'ctrend-same-leg-reinvestment-ledger-v1'), ...
    'Invalid same-leg reinvestment ledger');
assert(~rLedger.lUsesExternalSource && ~rLedger.lAllowsCashAfterExit, ...
    'Economic ledger violates the declared no-external/no-cash contract');
assert(numel(rLedger.vAssetID) == iNumAssets && ...
    numel(vLedgerWeekRow) == iNumObs && ...
    all(isfinite(vLedgerWeekRow)) && ...
    all(vLedgerWeekRow == fix(vLedgerWeekRow)) && ...
    all(vLedgerWeekRow >= 1) && ...
    all(vLedgerWeekRow <= numel(rLedger.vWeekStartIndex)), ...
    'Portfolio axes do not match the reinvestment ledger');

vPortReturn = NaN(1,iNumObs);
mEndRiskyWeights = NaN(iNumAssets,iNumObs);
vWithinWeekFullL1 = NaN(1,iNumObs);
vEventCount = zeros(1,iNumObs);
vExitHoldingCount = zeros(1,iNumObs);
vReinvestedProceeds = NaN(1,iNumObs);
lNoRecipient = false(1,iNumObs);

for iIdxT = 1:iNumObs
    iWeek = vLedgerWeekRow(iIdxT);
    [iEntry,iScheduledExit,vEntryPrice,vScheduledExitPrice,lTimingDefined] = ...
        iTimingEndpoints(rLedger,iWeek,char(sTiming));
    if ~lTimingDefined
        continue
    end

    vWeight = mFormationWeights(:,iIdxT);
    vWeight(~isfinite(vWeight)) = 0;
    dWeight = sum(vWeight);
    if ~isfinite(dWeight) || dWeight <= 0 || any(vWeight < 0)
        continue
    end
    % Sort helpers construct weights that sum to one.  Normalize only within
    % floating-point tolerance; reject a materially inconsistent caller.
    assert(abs(dWeight-1) <= 1e-10, ...
        'Formation leg weights must sum to one');
    vDollar = vWeight/dWeight;
    vPrice = vEntryPrice(:);
    lHeld = vDollar > 0;
    if any(~isfinite(vPrice(lHeld)) | vPrice(lHeld) <= 0)
        continue
    end

    vLast = rLedger.vLastTradableIndex(:);
    vEvent = unique(vLast(lHeld & isfinite(vLast) & ...
        vLast >= iEntry & vLast < iScheduledExit));
    vEvent = sort(vEvent(:));
    dWithinL1 = 0;
    dReinvested = 0;
    iExitCount = 0;
    lValid = true;

    for iIdxE = 1:numel(vEvent)
        iEvent = vEvent(iIdxE);
        iEventRow = double(rLedger.vEventRowByDailyIndex(iEvent));
        if iEventRow < 1
            lValid = false;
            break
        end
        vEventPrice = rLedger.mEventClose(iEventRow,:)';
        lActive = vDollar > 0;
        if any(~isfinite(vEventPrice(lActive)) | ...
                vEventPrice(lActive) <= 0)
            lValid = false;
            break
        end
        vDollar(lActive) = vDollar(lActive) .* ...
            (vEventPrice(lActive)./vPrice(lActive));
        vPrice(lActive) = vEventPrice(lActive);

        lExit = lActive & vLast == iEvent;
        dProceeds = sum(vDollar(lExit));
        iExitCount = iExitCount+nnz(lExit);
        vDollar(lExit) = 0;
        lSurvivor = vDollar > 0 & vLast > iEvent;
        if dProceeds > 0
            if strcmp(sAllocation,'EW')
                vRecipientWeight = double(lSurvivor);
            else
                vEventME = rLedger.mEventME(iEventRow,:)';
                vRecipientWeight = zeros(iNumAssets,1);
                lRecipient = lSurvivor & isfinite(vEventME) & vEventME > 0;
                vRecipientWeight(lRecipient) = vEventME(lRecipient);
            end
            dRecipientTotal = sum(vRecipientWeight);
            if ~isfinite(dRecipientTotal) || dRecipientTotal <= 0
                lValid = false;
                lNoRecipient(iIdxT) = true;
                break
            end
            vDollar = vDollar + ...
                dProceeds*(vRecipientWeight/dRecipientTotal);
            dWithinL1 = dWithinL1+2*dProceeds;
            dReinvested = dReinvested+dProceeds;
        end
    end

    if ~lValid
        continue
    end
    lActive = vDollar > 0;
    vFinalPrice = vScheduledExitPrice(:);
    if ~any(lActive) || any(~isfinite(vFinalPrice(lActive)) | ...
            vFinalPrice(lActive) <= 0)
        continue
    end
    vDollar(lActive) = vDollar(lActive) .* ...
        (vFinalPrice(lActive)./vPrice(lActive));
    dFinalWealth = sum(vDollar);
    if ~isfinite(dFinalWealth) || dFinalWealth <= 0
        continue
    end
    vPortReturn(iIdxT) = dFinalWealth-1;
    mEndRiskyWeights(:,iIdxT) = vDollar/dFinalWealth;
    vWithinWeekFullL1(iIdxT) = dWithinL1;
    vEventCount(iIdxT) = numel(vEvent);
    vExitHoldingCount(iIdxT) = iExitCount;
    vReinvestedProceeds(iIdxT) = dReinvested;
    assert(abs(sum(mEndRiskyWeights(:,iIdxT))-1) <= 1e-10, ...
        'No-cash end weights must sum to one');
end

rAudit = struct();
rAudit.sFormat = 'ctrend-same-leg-reinvestment-result-v1';
rAudit.sTiming = char(sTiming);
rAudit.sAllocation = char(sAllocation);
rAudit.vEventDateCount = vEventCount;
rAudit.vExitedHoldingCount = vExitHoldingCount;
rAudit.vReinvestedProceeds = vReinvestedProceeds;
rAudit.lNoEligibleRecipient = lNoRecipient;
rAudit.iDefinedPortfolioWeeks = nnz(isfinite(vPortReturn));
rAudit.iWeeksWithExit = nnz(vExitHoldingCount > 0);
rAudit.iNoRecipientFailures = nnz(lNoRecipient);
rAudit.lEndCashAlwaysZero = true;
rAudit.lCrossLegTransfer = false;
end

function [iEntry,iExit,vEntry,vExit,lDefined] = ...
        iTimingEndpoints(rLedger,iWeek,sTiming)
iNumWeeks = numel(rLedger.vWeekStartIndex);
iEntry = NaN;
iExit = NaN;
vEntry = NaN(numel(rLedger.vAssetID),1);
vExit = vEntry;
lDefined = false;
switch sTiming
    case 'ordinary'
        if iWeek < 2, return, end
        iEntry = rLedger.vWeekEndIndex(iWeek-1);
        iExit = rLedger.vWeekEndIndex(iWeek);
        vEntry = rLedger.mBoundaryClose(iWeek-1,:)';
        vExit = rLedger.mBoundaryClose(iWeek,:)';
    case 'lead1'
        if iWeek >= iNumWeeks, return, end
        iEntry = rLedger.vWeekStartIndex(iWeek);
        iExit = rLedger.vWeekStartIndex(iWeek+1);
        vEntry = rLedger.mFormationClose(iWeek,:)';
        vExit = rLedger.mFormationClose(iWeek+1,:)';
end
lDefined = true;
end
