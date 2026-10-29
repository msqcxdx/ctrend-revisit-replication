function [rLedger,mPnlReturns,mPnlRetLead,rDiagnostics] = ...
    fBuildWeeklyReinvestmentLedger( ...
    mCloseEconomic,mMEEconomic,vDates,vAssetID,tExitCalendar)
% Build the frozen daily-event ledger used for weekly economic accounting.
%
% Entry and scheduled exit dates follow the Liu-et-al. weekly partition.
% An asset whose frozen last-tradable date falls inside a holding interval
% is valued at that last positive close.  Its proceeds are not assigned to
% cash here: portfolio-specific same-leg reinvestment is performed later by
% fApplySameLegReinvestment, after the portfolio membership is known.

arguments
    mCloseEconomic (:,:) {mustBeNumeric}
    mMEEconomic (:,:) {mustBeNumeric}
    vDates (:,1) {mustBeNumericOrDatetime}
    vAssetID (:,1) {mustBeNumeric}
    tExitCalendar table
end

[iNumDates,iNumAssets] = size(mCloseEconomic);
assert(isequal(size(mMEEconomic),[iNumDates,iNumAssets]) && ...
    numel(vDates) == iNumDates && numel(vAssetID) == iNumAssets, ...
    'Economic close, market cap, dates, and asset IDs must share axes');
assert(all(isnan(mCloseEconomic) | ...
    (isfinite(mCloseEconomic) & mCloseEconomic > 0),'all'), ...
    'Economic close must contain positive finite values or NaN');
assert(numel(unique(vAssetID)) == iNumAssets && all(isfinite(vAssetID)), ...
    'Asset IDs must be finite and unique');

dtDates = iValidatedDailyCalendar(vDates);
[vWeekStartIndex,vWeekEndIndex,vWeekDate] = iLiuWeekIndices(dtDates);
iNumWeeks = numel(vWeekDate);

cRequired = {'asset_id','last_tradable_index','last_tradable_price', ...
    'mechanical_exit','right_censored','uses_external_source'};
assert(all(ismember(cRequired,tExitCalendar.Properties.VariableNames)) && ...
    height(tExitCalendar) == iNumAssets && ...
    isequal(double(tExitCalendar.asset_id(:)),double(vAssetID(:))), ...
    'Frozen exit calendar does not match the economic asset axis');
assert(~any(tExitCalendar.uses_external_source), ...
    'The declared mechanical exit ledger may not use an external quote');
vLastIndex = double(tExitCalendar.last_tradable_index(:));
vLastPrice = double(tExitCalendar.last_tradable_price(:));

% The frozen calendar must identify the actual last positive cell in this
% exact panel.  This prevents a stale calendar or an altered input panel
% from silently changing an exit date.
for iIdxA = 1:iNumAssets
    iLast = find(isfinite(mCloseEconomic(:,iIdxA)),1,'last');
    if isempty(iLast)
        assert(~isfinite(vLastIndex(iIdxA)) && ...
            ~isfinite(vLastPrice(iIdxA)), ...
            'No-quote asset has a finite frozen exit');
    else
        assert(vLastIndex(iIdxA) == iLast && ...
            iNearlyEqual(vLastPrice(iIdxA),mCloseEconomic(iLast,iIdxA)), ...
            'Frozen exit does not match the economic close panel');
    end
end

mBoundaryClose = mCloseEconomic(vWeekEndIndex,:);
mFormationClose = mCloseEconomic(vWeekStartIndex,:);
mPnlReturns = NaN(iNumWeeks,iNumAssets);
mPnlRetLead = NaN(iNumWeeks,iNumAssets);
lOrdinaryEarlyExit = false(iNumWeeks,iNumAssets);
lLeadEarlyExit = false(iNumWeeks,iNumAssets);

for iIdxW = 2:iNumWeeks
    iEntry = vWeekEndIndex(iIdxW-1);
    iScheduledExit = vWeekEndIndex(iIdxW);
    [mPnlReturns(iIdxW,:),lOrdinaryEarlyExit(iIdxW,:)] = ...
        iAssetPayoff(mCloseEconomic,iEntry,iScheduledExit,vLastIndex);
end
for iIdxW = 1:iNumWeeks-1
    iEntry = vWeekStartIndex(iIdxW);
    iScheduledExit = vWeekStartIndex(iIdxW+1);
    [mPnlRetLead(iIdxW,:),lLeadEarlyExit(iIdxW,:)] = ...
        iAssetPayoff(mCloseEconomic,iEntry,iScheduledExit,vLastIndex);
end

vEventDailyIndex = unique(vLastIndex( ...
    isfinite(vLastIndex) & vLastIndex < iNumDates));
vEventDailyIndex = sort(vEventDailyIndex(:));
vEventRowByDailyIndex = zeros(iNumDates,1,'uint32');
vEventRowByDailyIndex(vEventDailyIndex) = ...
    uint32((1:numel(vEventDailyIndex))');

rLedger = struct();
rLedger.sFormat = 'ctrend-same-leg-reinvestment-ledger-v1';
rLedger.sRule = [ ...
    'frozen last positive close; immediate same-leg reinvestment; ' ...
    'EW equal recipient dollars; VW event-day market-cap recipient dollars'];
rLedger.vAssetID = vAssetID(:);
rLedger.vWeekDate = vWeekDate(:);
rLedger.vWeekStartIndex = vWeekStartIndex(:);
rLedger.vWeekEndIndex = vWeekEndIndex(:);
rLedger.vLastTradableIndex = vLastIndex;
rLedger.vEventDailyIndex = vEventDailyIndex;
rLedger.vEventDate = iDateKey(dtDates(vEventDailyIndex));
rLedger.vEventRowByDailyIndex = vEventRowByDailyIndex;
rLedger.mEventClose = mCloseEconomic(vEventDailyIndex,:);
rLedger.mEventME = mMEEconomic(vEventDailyIndex,:);
rLedger.mBoundaryClose = mBoundaryClose;
rLedger.mFormationClose = mFormationClose;
rLedger.lOrdinaryEarlyExit = lOrdinaryEarlyExit;
rLedger.lLeadEarlyExit = lLeadEarlyExit;
rLedger.lUsesExternalSource = false;
rLedger.lAllowsCashAfterExit = false;

rDiagnostics = struct();
rDiagnostics.sFormat = rLedger.sFormat;
rDiagnostics.iNumDailyDates = iNumDates;
rDiagnostics.iNumWeeks = iNumWeeks;
rDiagnostics.iNumAssets = iNumAssets;
rDiagnostics.iNumUniqueMechanicalExitDates = numel(vEventDailyIndex);
rDiagnostics.iNumMechanicalExitAssets = ...
    nnz(tExitCalendar.mechanical_exit);
rDiagnostics.iNumOrdinaryEarlyExitAssetWeeks = ...
    nnz(lOrdinaryEarlyExit);
rDiagnostics.iNumLeadEarlyExitAssetWeeks = nnz(lLeadEarlyExit);
rDiagnostics.iNumOrdinaryFinitePayoffs = nnz(isfinite(mPnlReturns));
rDiagnostics.iNumLeadFinitePayoffs = nnz(isfinite(mPnlRetLead));
rDiagnostics.lUsesExternalSource = false;
rDiagnostics.lCashIsPermittedAfterExit = false;
rDiagnostics.sNoRecipientRule = ...
    'portfolio leg is undefined when positive exit proceeds have no survivor';
end

function [vReturn,lEarlyExit] = ...
        iAssetPayoff(mClose,iEntry,iScheduledExit,vLastIndex)
iNumAssets = size(mClose,2);
vReturn = NaN(1,iNumAssets);
lEarlyExit = false(1,iNumAssets);
vEntry = mClose(iEntry,:);
for iIdxA = 1:iNumAssets
    iLast = vLastIndex(iIdxA);
    if ~isfinite(vEntry(iIdxA)) || ~isfinite(iLast) || iLast < iEntry
        continue
    end
    iExit = min(iScheduledExit,iLast);
    dExit = mClose(iExit,iIdxA);
    if ~isfinite(dExit) || dExit <= 0
        continue
    end
    vReturn(iIdxA) = dExit/vEntry(iIdxA)-1;
    lEarlyExit(iIdxA) = iLast < iScheduledExit;
end
end

function [vStart,vEnd,vWeekDate] = iLiuWeekIndices(dtDates)
vYears = year(dtDates);
[vNumDays,vUniqueYears] = groupcounts(vYears);
vNumWeeks = fix(vNumDays/7);
iNumWeeks = sum(vNumWeeks);
vStart = NaN(iNumWeeks,1);
vEnd = NaN(iNumWeeks,1);
vWeekDate = NaN(iNumWeeks,1);
iCounter = 1;
iYearOffset = 0;
for iIdxY = 1:numel(vUniqueYears)
    vStartYear = 1:7:(vNumWeeks(iIdxY)*7);
    vEndYear = [vStartYear(2:end)-1,vNumDays(iIdxY)];
    iRows = iCounter:(iCounter+vNumWeeks(iIdxY)-1);
    vStart(iRows) = iYearOffset+vStartYear;
    vEnd(iRows) = iYearOffset+vEndYear;
    vWeekDate(iRows) = vUniqueYears(iIdxY)*100+(1:vNumWeeks(iIdxY));
    iCounter = iCounter+vNumWeeks(iIdxY);
    iYearOffset = iYearOffset+vNumDays(iIdxY);
end
end

function dtDates = iValidatedDailyCalendar(vDates)
if isnumeric(vDates)
    assert(all(isfinite(vDates)), 'Numeric dates must be finite');
    dtDates = datetime(compose('%08.0f',vDates), ...
        'InputFormat','yyyyMMdd');
else
    dtDates = vDates;
end
dtDates = dtDates(:);
assert(all(~isnat(dtDates)) && ...
    all(dtDates(2:end) == dtDates(1:end-1)+caldays(1)), ...
    'Dates must be valid, unique, increasing, and daily-contiguous');
end

function vKey = iDateKey(dtDates)
vKey = year(dtDates)*10000+month(dtDates)*100+day(dtDates);
end

function lEqual = iNearlyEqual(a,b)
lEqual = isfinite(a) && isfinite(b) && ...
    abs(a-b) <= 16*eps(max([1,abs(a),abs(b)]));
end
