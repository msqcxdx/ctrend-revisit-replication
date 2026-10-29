function [tExitCalendar,rAudit] = fBuildAndFreezeMechanicalExitCalendar( ...
    mCloseEconomicRaw,vDates,vAssetID,cSymbol,sOutputFile)
% Freeze the full-history mechanical exit schedule before model estimation.
%
% For each asset the last positive close in the immutable input panel is its
% mechanical last-tradable quote.  If that quote precedes the final sample
% date, the asset has one scheduled exit at that date.  Assets observed on
% the final sample date are right-censored and are not assigned a fabricated
% liquidation.  The routine uses no external source and never changes a
% price.  It writes the complete asset-level calendar atomically so every
% downstream result can be tied to the exact frozen schedule.

arguments
    mCloseEconomicRaw (:,:) {mustBeNumeric}
    vDates (:,1) {mustBeNumeric}
    vAssetID (:,1) {mustBeNumeric}
    cSymbol (:,1)
    sOutputFile {mustBeTextScalar}
end

[iNumDates,iNumAssets] = size(mCloseEconomicRaw);
assert(numel(vDates) == iNumDates && numel(vAssetID) == iNumAssets && ...
       numel(cSymbol) == iNumAssets, ...
    'Calendar keys must agree with the economic-close panel');
assert(all(isfinite(vDates)) && all(diff(vDates) > 0) && ...
       all(isfinite(vAssetID)) && ...
       numel(unique(vAssetID)) == iNumAssets, ...
    'Mechanical calendar requires unique increasing dates and asset IDs');
assert(all(isnan(mCloseEconomicRaw) | ...
    (isfinite(mCloseEconomicRaw) & mCloseEconomicRaw > 0),'all'), ...
    'Economic close may contain only positive finite values or NaN');

vFirstIndex = NaN(iNumAssets,1);
vLastIndex = NaN(iNumAssets,1);
vFirstDate = NaN(iNumAssets,1);
vLastDate = NaN(iNumAssets,1);
vLastPrice = NaN(iNumAssets,1);
for iIdxAsset = 1:iNumAssets
    iFirst = find(isfinite(mCloseEconomicRaw(:,iIdxAsset)),1,'first');
    iLast = find(isfinite(mCloseEconomicRaw(:,iIdxAsset)),1,'last');
    if isempty(iFirst)
        continue
    end
    vFirstIndex(iIdxAsset) = iFirst;
    vLastIndex(iIdxAsset) = iLast;
    vFirstDate(iIdxAsset) = vDates(iFirst);
    vLastDate(iIdxAsset) = vDates(iLast);
    vLastPrice(iIdxAsset) = mCloseEconomicRaw(iLast,iIdxAsset);
end

lHasQuote = isfinite(vLastIndex);
lMechanicalExit = lHasQuote & vLastIndex < iNumDates;
lRightCensored = lHasQuote & vLastIndex == iNumDates;
cScheduleSource = repmat("no_positive_close",iNumAssets,1);
cScheduleSource(lMechanicalExit) = ...
    "mechanical_full_history_last_positive_close";
cScheduleSource(lRightCensored) = "sample_end_right_censored";
cConfirmedEventID = strings(iNumAssets,1);
lUsesExternalSource = false(iNumAssets,1);

tExitCalendar = table(vAssetID(:),string(cSymbol(:)),vFirstIndex,vFirstDate, ...
    vLastIndex,vLastDate,vLastPrice,lMechanicalExit,lRightCensored, ...
    cScheduleSource,cConfirmedEventID,lUsesExternalSource, ...
    'VariableNames',{'asset_id','symbol','first_tradable_index', ...
    'first_tradable_date','last_tradable_index','last_tradable_date', ...
    'last_tradable_price','mechanical_exit','right_censored', ...
    'schedule_source','confirmed_event_id','uses_external_source'});

sOutputFile = char(sOutputFile);
sOutputDir = fileparts(sOutputFile);
assert(isfolder(sOutputDir), ...
    'Mechanical exit calendar output directory does not exist: %s', ...
    sOutputDir);
sTemporary = [tempname(sOutputDir),'.csv'];
rCleanup = onCleanup(@() iDeleteIfExists(sTemporary));
writetable(tExitCalendar,sTemporary,'QuoteStrings',true);
[lMoved,sMessage] = movefile(sTemporary,sOutputFile,'f');
assert(lMoved,'Could not publish mechanical exit calendar: %s',sMessage);
clear rCleanup

rAudit = struct();
rAudit.sFormat = 'ctrend-mechanical-exit-calendar-v1';
rAudit.sRule = [ ...
    'last original positive close before sample end is the frozen exit; ' ...
    'sample-end observations are right-censored'];
rAudit.sOutputFile = sOutputFile;
rAudit.sSHA256 = fFileSHA256(sOutputFile);
rAudit.iAssets = iNumAssets;
rAudit.iAssetsWithPositiveClose = nnz(lHasQuote);
rAudit.iMechanicalExits = nnz(lMechanicalExit);
rAudit.iRightCensored = nnz(lRightCensored);
rAudit.iNoPositiveClose = nnz(~lHasQuote);
rAudit.iConfirmedEventExits = 0;
rAudit.lUsesExternalSource = false;
rAudit.lGeneratedBeforeReturnsAndModels = true;
assert(rAudit.iAssets == rAudit.iMechanicalExits + ...
    rAudit.iRightCensored + rAudit.iNoPositiveClose, ...
    'Mechanical exit calendar counts do not reconcile');
end

function iDeleteIfExists(sFilename)
if exist(sFilename,'file') == 2
    delete(sFilename);
end
end
