function [tWeekly, tDaily] = scan_extreme_raw_returns()
% Deterministic full-universe audit of extreme CMC price discontinuities.
%
% This audit does not edit input data. It inventories every paper-sample
% Tuesday-to-Tuesday endpoint and every adjacent-day discontinuity with a
% gross price ratio >= 5 or <= 0.2. The common threshold is deliberately
% broad enough to inventory 10:1 and similar unit conversions that would be
% missed by a 100:1 daily-only screen. It is fixed before inspecting CTREND
% holdings or factor returns.

sRawDir = getenv('CTREND_RAW_DATA_DIR');
if isempty(sRawDir)
    sRawDir = fullfile(fileparts(mfilename('fullpath')),'..','DATA');
end
sOutputDir = getenv('CTREND_EVENT_AUDIT_DIR');
if isempty(sOutputDir)
    sOutputDir = fullfile(fileparts(mfilename('fullpath')),'output');
end
if ~exist(sOutputDir,'dir')
    mkdir(sOutputDir);
end

[mClose,vID,dtDate] = iReadPanel(sRawDir,'close_cmc.csv');
[mOpen,vIDOpen,dtOpen] = iReadPanel(sRawDir,'open_cmc.csv');
[mHigh,vIDHigh,dtHigh] = iReadPanel(sRawDir,'high_cmc.csv');
[mLow,vIDLow,dtLow] = iReadPanel(sRawDir,'low_cmc.csv');
[mCap,vIDCap,dtCap] = iReadPanel(sRawDir,'market_cap_cmc.csv');
[mVolume,vIDVolume,dtVolume] = iReadPanel(sRawDir,'volume_cmc.csv');
assert(isequal(vID,vIDOpen,vIDHigh,vIDLow,vIDCap,vIDVolume) && ...
       isequal(dtDate,dtOpen,dtHigh,dtLow,dtCap,dtVolume), ...
    'Raw event-audit panels do not have identical date/asset keys');

r = load(fullfile(sRawDir,'MetaData.mat'),'rMetaData');
assert(isequal(vID(:),r.rMetaData.vID(:)), ...
    'Raw event-audit asset IDs do not match metadata');
cName = string(r.rMetaData.cName(:));
cSymbol = string(r.rMetaData.cSymbol(:));

lSample = dtDate >= datetime(2014,1,1) & ...
    dtDate <= datetime(2022,5,31);
dtDate = dtDate(lSample);
mClose = mClose(lSample,:);
mOpen = mOpen(lSample,:);
mHigh = mHigh(lSample,:);
mLow = mLow(lSample,:);
mCap = mCap(lSample,:);
mVolume = mVolume(lSample,:);

% Adjacent-day inventory used to identify unit/supply discontinuities.
mDailyRatio = mClose(2:end,:)./mClose(1:end-1,:);
lDailyCandidate = isfinite(mDailyRatio) & ...
    (mDailyRatio >= 5 | mDailyRatio <= 0.2);
[vDailyTime,vDailyAsset] = find(lDailyCandidate);
iDailyN = numel(vDailyTime);
tDaily = table();
tDaily.AssetID = vID(vDailyAsset)';
tDaily.Name = cName(vDailyAsset);
tDaily.Symbol = cSymbol(vDailyAsset);
tDaily.FormationDate = dtDate(vDailyTime);
tDaily.TargetDate = dtDate(vDailyTime+1);
tDaily.Price0 = iAt(mClose,vDailyTime,vDailyAsset);
tDaily.Price1 = iAt(mClose,vDailyTime+1,vDailyAsset);
tDaily.GrossRatio = tDaily.Price1./tDaily.Price0;
tDaily.ReturnPct = 100*(tDaily.GrossRatio-1);
tDaily.MarketCap0 = iAt(mCap,vDailyTime,vDailyAsset);
tDaily.MarketCap1 = iAt(mCap,vDailyTime+1,vDailyAsset);
tDaily.MarketCapRatio = tDaily.MarketCap1./tDaily.MarketCap0;
tDaily.ImpliedSupply0 = tDaily.MarketCap0./tDaily.Price0;
tDaily.ImpliedSupply1 = tDaily.MarketCap1./tDaily.Price1;
tDaily.ImpliedSupplyRatio = ...
    tDaily.ImpliedSupply1./tDaily.ImpliedSupply0;
tDaily.Volume0 = iAt(mVolume,vDailyTime,vDailyAsset);
tDaily.Volume1 = iAt(mVolume,vDailyTime+1,vDailyAsset);
tDaily.FormationCapAtLeast1m = tDaily.MarketCap0 >= 1e6;
tDaily.InversePriceSupplyBreak = ...
    isfinite(tDaily.ImpliedSupplyRatio) & ...
    ((tDaily.GrossRatio >= 5 & ...
      tDaily.ImpliedSupplyRatio <= 0.2) | ...
     (tDaily.GrossRatio <= 0.2 & ...
      tDaily.ImpliedSupplyRatio >= 5));
tDaily.MarketCapApproximatelyContinuous = ...
    isfinite(tDaily.MarketCapRatio) & ...
    tDaily.MarketCapRatio >= 0.5 & tDaily.MarketCapRatio <= 2;
tDaily.CandidateClass = repmat( ...
    "extreme_price_requires_external_check",iDailyN,1);
tDaily.CandidateClass( ...
    tDaily.InversePriceSupplyBreak & ...
    tDaily.MarketCapApproximatelyContinuous) = ...
    "probable_unit_or_supply_metadata_break";

% Full Tuesday-to-Tuesday economic-endpoint inventory.
vTuesday = find(weekday(dtDate) == 3);
vWeek0 = vTuesday(1:end-1);
vWeek1 = vTuesday(2:end);
mWeeklyRatio = mClose(vWeek1,:)./mClose(vWeek0,:);
lWeeklyCandidate = isfinite(mWeeklyRatio) & ...
    (mWeeklyRatio >= 5 | mWeeklyRatio <= 0.2);
[vWeeklyTime,vWeeklyAsset] = find(lWeeklyCandidate);
iWeeklyN = numel(vWeeklyTime);
vFormationRow = vWeek0(vWeeklyTime);
vTargetRow = vWeek1(vWeeklyTime);
tWeekly = table();
tWeekly.AssetID = vID(vWeeklyAsset)';
tWeekly.Name = cName(vWeeklyAsset);
tWeekly.Symbol = cSymbol(vWeeklyAsset);
tWeekly.FormationDate = dtDate(vFormationRow);
tWeekly.TargetDate = dtDate(vTargetRow);
tWeekly.Price0 = iAt(mClose,vFormationRow,vWeeklyAsset);
tWeekly.Price1 = iAt(mClose,vTargetRow,vWeeklyAsset);
tWeekly.GrossRatio = tWeekly.Price1./tWeekly.Price0;
tWeekly.ReturnPct = 100*(tWeekly.GrossRatio-1);
tWeekly.MarketCap0 = iAt(mCap,vFormationRow,vWeeklyAsset);
tWeekly.MarketCap1 = iAt(mCap,vTargetRow,vWeeklyAsset);
tWeekly.MarketCapRatio = tWeekly.MarketCap1./tWeekly.MarketCap0;
tWeekly.ImpliedSupply0 = tWeekly.MarketCap0./tWeekly.Price0;
tWeekly.ImpliedSupply1 = tWeekly.MarketCap1./tWeekly.Price1;
tWeekly.ImpliedSupplyRatio = ...
    tWeekly.ImpliedSupply1./tWeekly.ImpliedSupply0;
tWeekly.Volume0 = iAt(mVolume,vFormationRow,vWeeklyAsset);
tWeekly.Volume1 = iAt(mVolume,vTargetRow,vWeeklyAsset);
tWeekly.FormationCapAtLeast1m = tWeekly.MarketCap0 >= 1e6;
tWeekly.FormationCapAtLeast2m = tWeekly.MarketCap0 >= 2e6;
tWeekly.InversePriceSupplyBreak = ...
    isfinite(tWeekly.ImpliedSupplyRatio) & ...
    ((tWeekly.GrossRatio >= 5 & ...
      tWeekly.ImpliedSupplyRatio <= 0.2) | ...
     (tWeekly.GrossRatio <= 0.2 & ...
      tWeekly.ImpliedSupplyRatio >= 5));
tWeekly.MarketCapApproximatelyContinuous = ...
    isfinite(tWeekly.MarketCapRatio) & ...
    tWeekly.MarketCapRatio >= 0.5 & ...
    tWeekly.MarketCapRatio <= 2;

vMinDailyRatio = NaN(iWeeklyN,1);
vMaxDailyRatio = NaN(iWeeklyN,1);
vExtremeDailySteps = zeros(iWeeklyN,1);
vDirectionReversals = zeros(iWeeklyN,1);
vOHLCConsistent = false(iWeeklyN,1);
for iIdx = 1:iWeeklyN
    iAsset = vWeeklyAsset(iIdx);
    vRows = vFormationRow(iIdx):vTargetRow(iIdx);
    vDaily = mClose(vRows(2:end),iAsset)./ ...
        mClose(vRows(1:end-1),iAsset);
    vFiniteDaily = vDaily(isfinite(vDaily));
    if ~isempty(vFiniteDaily)
        vMinDailyRatio(iIdx) = min(vFiniteDaily);
        vMaxDailyRatio(iIdx) = max(vFiniteDaily);
        vExtremeDailySteps(iIdx) = ...
            nnz(vFiniteDaily >= 5 | vFiniteDaily <= 0.2);
        vLogDirection = sign(log(vFiniteDaily));
        vDirectionReversals(iIdx) = ...
            nnz(vLogDirection(2:end).*vLogDirection(1:end-1) < 0);
    end
    lFiniteOHLC = isfinite(mOpen(vRows,iAsset)) & ...
        isfinite(mHigh(vRows,iAsset)) & ...
        isfinite(mLow(vRows,iAsset)) & ...
        isfinite(mClose(vRows,iAsset));
    vOHLCConsistent(iIdx) = all( ...
        ~lFiniteOHLC | ...
        (mLow(vRows,iAsset) <= mOpen(vRows,iAsset) & ...
         mOpen(vRows,iAsset) <= mHigh(vRows,iAsset) & ...
         mLow(vRows,iAsset) <= mClose(vRows,iAsset) & ...
         mClose(vRows,iAsset) <= mHigh(vRows,iAsset)));
end
tWeekly.MinDailyGrossRatio = vMinDailyRatio;
tWeekly.MaxDailyGrossRatio = vMaxDailyRatio;
tWeekly.ExtremeDailySteps = vExtremeDailySteps;
tWeekly.DirectionReversals = vDirectionReversals;
tWeekly.OHLCConsistent = vOHLCConsistent;
tWeekly.CandidateClass = repmat( ...
    "extreme_return_requires_external_check",iWeeklyN,1);
tWeekly.CandidateClass( ...
    tWeekly.InversePriceSupplyBreak & ...
    tWeekly.MarketCapApproximatelyContinuous) = ...
    "probable_unit_or_supply_metadata_break";
tWeekly.CandidateClass( ...
    ~tWeekly.InversePriceSupplyBreak & ...
    tWeekly.DirectionReversals >= 2 & ...
    tWeekly.Volume0 < 1e3) = ...
    "probable_thin_market_or_aggregator_spike";

tWeekly = sortrows(tWeekly, ...
    {'FormationCapAtLeast1m','GrossRatio'}, {'descend','descend'});
tDaily = sortrows(tDaily, ...
    {'FormationCapAtLeast1m','GrossRatio'}, {'descend','descend'});

sWeeklyCSV = fullfile(sOutputDir,'weekly_extreme_return_inventory.csv');
sDailyCSV = fullfile(sOutputDir,'daily_extreme_discontinuity_inventory.csv');
sMAT = fullfile(sOutputDir,'extreme_return_inventory.mat');
writetable(tWeekly,sWeeklyCSV);
writetable(tDaily,sDailyCSV);
save(sMAT,'tWeekly','tDaily','sRawDir');

fprintf(['event_audit_weekly_candidates=%d high_cap_candidates=%d ' ...
    'probable_unit_breaks=%d\n'],height(tWeekly), ...
    nnz(tWeekly.FormationCapAtLeast1m), ...
    nnz(tWeekly.CandidateClass == ...
        "probable_unit_or_supply_metadata_break"));
fprintf(['event_audit_daily_candidates=%d high_cap_candidates=%d ' ...
    'probable_unit_breaks=%d\n'],height(tDaily), ...
    nnz(tDaily.FormationCapAtLeast1m), ...
    nnz(tDaily.CandidateClass == ...
        "probable_unit_or_supply_metadata_break"));
fprintf('event_audit_weekly_csv=%s\n',sWeeklyCSV);
fprintf('event_audit_daily_csv=%s\n',sDailyCSV);
end

function [mPanel,vID,dtDate] = iReadPanel(sRawDir,sFile)
sPath = fullfile(sRawDir,sFile);
mRaw = readmatrix(sPath);
vID = mRaw(1,2:end);
mPanel = mRaw(2:end,2:end);
dtDate = iReadDateColumn(sPath,size(mPanel,1));
assert(all(isfinite(vID)) && numel(unique(vID)) == numel(vID), ...
    'Raw event-audit asset IDs must be finite and unique');
end

function dtDate = iReadDateColumn(sPath,iNumRows)
fid = fopen(sPath,'r');
assert(fid >= 0,'Could not open raw event-audit panel: %s',sPath);
rCleanup = onCleanup(@() fclose(fid)); %#ok<NASGU>
fgetl(fid);
cDate = strings(iNumRows,1);
for iIdx = 1:iNumRows
    sLine = fgetl(fid);
    assert(ischar(sLine) && numel(sLine) >= 10, ...
        'Raw event-audit panel has a malformed date row');
    cDate(iIdx) = string(sLine(1:10));
end
dtDate = datetime(cDate,'InputFormat','yyyy-MM-dd');
assert(all(diff(dtDate) > days(0)), ...
    'Raw event-audit dates must be strictly increasing');
end

function v = iAt(m,vRow,vColumn)
v = m(sub2ind(size(m),vRow(:),vColumn(:)));
end
