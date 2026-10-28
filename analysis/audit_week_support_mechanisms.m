function audit_week_support_mechanisms(m0BasePath,m2BasePath, ...
    m2WeeklyPath,m2DailyPath,m1BasePath,m1WeeklyPath,m1DailyPath,outDir)
% CTREND_REVISIT_FILE_PURPOSE: Preserve the reproducible pre-amendment D0 support-mechanism audit.
%AUDIT_WEEK_SUPPORT_MECHANISMS Trace every D0 baseline support difference.
%
% Inputs are explicit saved baseline, weekly and daily MAT paths for M0/M2/M1.
% Outputs are audit tables below outDir; no input MAT file is saved or edited.
% Assertions bind date and asset axes before any row-level diagnosis, so an
% alignment error fails instead of being reported as an economic mechanism.
%
% HISTORICAL PRE-AMENDMENT AUDIT.  The saved M1/M2 runs inspected here used
% selected-payoff fail-closed support.  For current support counts use
% recompute_declared_week_support.m.
%
% This is a read-only, post-run diagnostic.  It expands every selected
% holding whose saved payoff is missing and records information observable at
% the portfolio boundary, exact raw entry/exit endpoints, and daily support.
% It also reports counterfactual finite-week counts under several accounting
% conventions.  The function never edits a run root and never treats a CMC
% missing value as proof that an exchange delisting announcement existed.

arguments
    m0BasePath (1,:) char
    m2BasePath (1,:) char
    m2WeeklyPath (1,:) char
    m2DailyPath (1,:) char
    m1BasePath (1,:) char
    m1WeeklyPath (1,:) char
    m1DailyPath (1,:) char
    outDir (1,:) char
end

if ~isfolder(outDir)
    mkdir(outDir);
end

M0 = load(m0BasePath,'cResults','vDates','vAssetID','mYhat','mSelected');
M2 = load(m2BasePath,'cResults','vDates','vAssetID','mYhat','mSelected');
M1 = load(m1BasePath,'cResults','vDates','vAssetID','mYhat', ...
    'mSelected','mRetPnlOOS');
W2 = load(m2WeeklyPath,'rData','rMetaData');
D2 = load(m2DailyPath,'mReturns','mClose','mOpen','mVolume','mME', ...
    'yrmoda','rMetaData');
W1 = load(m1WeeklyPath,'rData','rMetaData');
D1 = load(m1DailyPath,'mClosePnlRaw','mVolumeRaw','mME','yrmoda', ...
    'rMetaData');

iAssertBase(M0,'M0');
iAssertBase(M2,'M2');
iAssertBase(M1,'M1');
assert(isfield(M1,'mRetPnlOOS'),'M1 base lacks endpoint P&L');

P2 = iAlignWeekly(M2,W2.rData.yrmoda,W2.rMetaData.vID, ...
    W2.rData.mReturnsM2Raw);
P1 = double(M1.mRetPnlOOS);
assert(isequal(size(P1),size(M1.mYhat)), ...
    'M1 saved endpoint P&L and forecast matrices disagree');

% The fully audited D0 weekly file is used only as an independent raw
% endpoint/tradability diagnostic for M2.  D0 uses the same immutable vendor
% snapshot and asset/date axes; no M1 forecast or holding enters M2 results.
P1ForM2 = iAlignWeekly(M2,W1.rData.yrmoda,W1.rMetaData.vID, ...
    W1.rData.mPnlReturns);
Strict1ForM2 = logical(iAlignWeekly(M2,W1.rData.yrmoda, ...
    W1.rMetaData.vID,double(W1.rData.mRawOutcomeObserved)));

F2 = iBuildFormationDiagnostics(M2,W2,W1,D1,D2);
F1 = iBuildFormationDiagnostics(M1,W1,W1,D1,D2);

T2 = iMissingHoldingTable("M2",M2,P2,P1ForM2,Strict1ForM2,F2);
T1 = iMissingHoldingTable("M1",M1,P1,P1, ...
    isfinite(P1),F1);
writetable(T2,fullfile(outDir,'selected_missing_holdings_M2_D0.csv'));
writetable(T1,fullfile(outDir,'selected_missing_holdings_M1_D0.csv'));

TF = iForecastSupportTable(M0,M2,M1);
writetable(TF,fullfile(outDir,'forecast_support_by_week_D0.csv'));

S = iBuildSummary(M0,M2,M1,P2,P1,P1ForM2,F2,F1,T2,T1,TF);
writetable(S,fullfile(outDir,'week_support_mechanism_summary_D0.csv'));

% Fixed identities from the accepted D0 artifacts.  They make accidental
% path mix-ups and silent changes to the already-published results fail.
assert(sum(isfinite(M0.cResults.VW.mPortRet(end,:)))==349);
assert(sum(isfinite(M2.cResults.VW.mPortRet(end,:)))==280);
assert(sum(isfinite(M1.cResults.VW.mPortRet(end,:)))==326);
assert(numel(unique(T2.yearWeek))==73, ...
    'M2 must have 73 distinct selected-payoff-missing weeks');
assert(numel(unique(T1.yearWeek))==11, ...
    'M1 must have 11 distinct selected-payoff-missing weeks');

fprintf(['WEEK_SUPPORT_MECHANISM_AUDIT_OK M0=%d M2=%d M1=%d ' ...
    'M2_missing_weeks=%d M1_missing_weeks=%d\n'],349,280,326, ...
    numel(unique(T2.yearWeek)),numel(unique(T1.yearWeek)));
end

function iAssertBase(S,label)
required = {'cResults','vDates','vAssetID','mYhat'};
assert(all(isfield(S,required)),'%s base is incomplete',label);
assert(isfield(S.cResults,'VW') && isfield(S.cResults.VW,'mPortRet') && ...
    isfield(S.cResults.VW,'mWts'),'%s base lacks VW results',label);
assert(isequal(size(S.mYhat),[numel(S.vAssetID),numel(S.vDates)]), ...
    '%s forecast dimensions disagree',label);
end

function X = iAlignWeekly(S,weekDates,assetIDs,X0)
weekDates = double(weekDates(:));
assetIDs = double(assetIDs(:));
[tfT,it] = ismember(double(S.vDates(:)),weekDates);
[tfA,ia] = ismember(double(S.vAssetID(:)),assetIDs);
assert(all(tfT) && all(tfA),'Weekly diagnostic input does not cover base axes');
X = double(X0(it,ia))';
end

function F = iBuildFormationDiagnostics(S,WMethod,W1,D1,D2)
% Align exact raw endpoint and daily panels to one saved base artifact.
weekDates = double(W1.rData.yrmoda(:));
weekIDs = double(W1.rMetaData.vID(:));
[tfT,it] = ismember(double(S.vDates(:)),weekDates);
[tfA,ia] = ismember(double(S.vAssetID(:)),weekIDs);
assert(all(tfT) && all(tfA),'M1 weekly raw endpoint file lacks base axes');
assert(all(it>1),'Every baseline week must have a preceding formation week');

F.entryBoundaryClose = double(W1.rData.mClosePnlBoundary(it-1,ia))';
F.entryBoundaryVolume = double(W1.rData.mVolumeRawBoundary(it-1,ia))';
F.entryBoundaryME = double(W1.rData.mME(it-1,ia))';
F.targetFirstDayClose = double(W1.rData.mClosePnlFormationDay(it,ia))';
F.targetFirstDayVolume = double(W1.rData.mVolumeRawFormationDay(it,ia))';
F.targetFirstDayME = double(W1.rData.mMEFormationDay(it,ia))';
F.exitBoundaryClose = double(W1.rData.mClosePnlBoundary(it,ia))';
F.assetName = string(W1.rMetaData.cName(ia));
F.assetSymbol = string(W1.rMetaData.cSymbol(ia));

methodDates = double(WMethod.rData.yrmoda(:));
methodIDs = double(WMethod.rMetaData.vID(:));
[tfTM,itm] = ismember(double(S.vDates(:)),methodDates);
[tfAM,iam] = ismember(double(S.vAssetID(:)),methodIDs);
assert(all(tfTM) && all(tfAM) && all(itm>1), ...
    'Method-specific weekly file lacks formation axes');
F.methodFormationClose = double(WMethod.rData.mClose(itm-1,iam))';
F.methodFormationVolume = double(WMethod.rData.mVolume(itm-1,iam))';
F.methodFormationME = double(WMethod.rData.mME(itm-1,iam))';

dailyIDs1 = double(D1.rMetaData.vID(:));
dailyIDs2 = double(D2.rMetaData.vID(:));
[tfA1,ia1] = ismember(double(S.vAssetID(:)),dailyIDs1);
[tfA2,ia2] = ismember(double(S.vAssetID(:)),dailyIDs2);
assert(all(tfA1) && all(tfA2),'Daily diagnostic inputs lack base assets');

[codes2,start2,end2] = iLiuWeekBlocks(D2.yrmoda);
[tfB2,ib2] = ismember(double(S.vDates(:)),codes2);
assert(all(tfB2),'M2 daily file lacks base weeks');

nA = numel(S.vAssetID);
nT = numel(S.vDates);
F.expectedDailyRows = zeros(nA,nT);
F.m2FiniteDailyReturns = zeros(nA,nT);
F.m2FiniteDailyClose = zeros(nA,nT);
F.m2FirstDailyClose = NaN(nA,nT);
F.m2FirstDailyOpen = NaN(nA,nT);
F.m2FirstDailyVolume = NaN(nA,nT);
F.m2FirstDailyME = NaN(nA,nT);

for t = 1:nT
    rows = start2(ib2(t)):end2(ib2(t));
    F.expectedDailyRows(:,t) = numel(rows);
    F.m2FiniteDailyReturns(:,t) = ...
        sum(isfinite(D2.mReturns(rows,ia2)),1)';
    F.m2FiniteDailyClose(:,t) = ...
        sum(isfinite(D2.mClose(rows,ia2)),1)';
    F.m2FirstDailyClose(:,t) = double(D2.mClose(rows(1),ia2))';
    F.m2FirstDailyOpen(:,t) = double(D2.mOpen(rows(1),ia2))';
    F.m2FirstDailyVolume(:,t) = double(D2.mVolume(rows(1),ia2))';
    F.m2FirstDailyME(:,t) = double(D2.mME(rows(1),ia2))';
end

% Locate whether a missing target endpoint is internal or terminal in the
% unsynchronized positive-close panel.  These are descriptive data states,
% not claims about exchange tradability or public delisting announcements.
dailyDates1 = double(D1.yrmoda(:));
[codes1,start1,end1] = iLiuWeekBlocks(dailyDates1);
[tfB1,ib1] = ismember(double(S.vDates(:)),codes1);
assert(all(tfB1),'M1 raw daily file lacks base weeks');
F.rawTargetStartDate = zeros(nA,nT);
F.rawTargetEndDate = zeros(nA,nT);
F.hasLaterRawCloseAfterTarget = false(nA,nT);
F.hasRawCloseInsideTarget = false(nA,nT);
for t = 1:nT
    rows = start1(ib1(t)):end1(ib1(t));
    F.rawTargetStartDate(:,t) = dailyDates1(rows(1));
    F.rawTargetEndDate(:,t) = dailyDates1(rows(end));
    F.hasRawCloseInsideTarget(:,t) = ...
        any(isfinite(D1.mClosePnlRaw(rows,ia1)),1)';
    if rows(end) < numel(dailyDates1)
        F.hasLaterRawCloseAfterTarget(:,t) = ...
            any(isfinite(D1.mClosePnlRaw(rows(end)+1:end,ia1)),1)';
    end
end
end

function [codes,startIdx,endIdx] = iLiuWeekBlocks(yyyymmdd)
dt = datetime(cellstr(num2str(double(yyyymmdd(:)))), ...
    'InputFormat','yyyyMMdd');
years = year(dt);
uniqueYears = unique(years,'stable');
codes = zeros(0,1);
startIdx = zeros(0,1);
endIdx = zeros(0,1);
for y = uniqueYears(:)'
    rows = find(years==y);
    nWeeks = fix(numel(rows)/7);
    localStart = 1:7:(nWeeks*7);
    localEnd = [localStart(2:end)-1,numel(rows)];
    codes = [codes; y*100+(1:nWeeks)']; %#ok<AGROW>
    startIdx = [startIdx; rows(localStart)]; %#ok<AGROW>
    endIdx = [endIdx; rows(localEnd)]; %#ok<AGROW>
end
end

function T = iMissingHoldingTable(method,S,P,endpointP,strictObserved,F)
weights = double(S.cResults.VW.mWts);
assert(size(weights,3)==5,'Expected five formation portfolios');
low = isfinite(weights(:,:,1)) & weights(:,:,1)~=0;
high = isfinite(weights(:,:,5)) & weights(:,:,5)~=0;
missing = (low | high) & ~isfinite(P);
[asset,time] = find(missing);
n = numel(asset);

methodName = repmat(string(method),n,1);
yearWeek = double(S.vDates(time));
assetID = double(S.vAssetID(asset))';
assetName = F.assetName(asset);
assetSymbol = F.assetSymbol(asset);
leg = strings(n,1);
leg(low(sub2ind(size(low),asset,time))) = "low";
leg(high(sub2ind(size(high),asset,time))) = "high";
weight = NaN(n,1);
for i=1:n
    if leg(i)=="low"
        weight(i) = weights(asset(i),time(i),1);
    else
        weight(i) = weights(asset(i),time(i),5);
    end
end
forecast = S.mYhat(sub2ind(size(S.mYhat),asset,time));
endpointPayoffObserved = isfinite(endpointP(sub2ind(size(endpointP),asset,time)));
strictStatReturnObserved = logical(strictObserved( ...
    sub2ind(size(strictObserved),asset,time)));

entryBoundaryClose = iTake(F.entryBoundaryClose,asset,time);
entryBoundaryVolume = iTake(F.entryBoundaryVolume,asset,time);
entryBoundaryME = iTake(F.entryBoundaryME,asset,time);
targetFirstDayClose = iTake(F.targetFirstDayClose,asset,time);
targetFirstDayVolume = iTake(F.targetFirstDayVolume,asset,time);
targetFirstDayME = iTake(F.targetFirstDayME,asset,time);
exitBoundaryClose = iTake(F.exitBoundaryClose,asset,time);
m2FirstDailyClose = iTake(F.m2FirstDailyClose,asset,time);
m2FirstDailyOpen = iTake(F.m2FirstDailyOpen,asset,time);
m2FirstDailyVolume = iTake(F.m2FirstDailyVolume,asset,time);
m2FirstDailyME = iTake(F.m2FirstDailyME,asset,time);
expectedDailyRows = iTake(F.expectedDailyRows,asset,time);
m2FiniteDailyReturns = iTake(F.m2FiniteDailyReturns,asset,time);
m2FiniteDailyClose = iTake(F.m2FiniteDailyClose,asset,time);
rawTargetStartDate = iTake(F.rawTargetStartDate,asset,time);
rawTargetEndDate = iTake(F.rawTargetEndDate,asset,time);
hasRawCloseInsideTarget = logical(iTake(F.hasRawCloseInsideTarget,asset,time));
hasLaterRawCloseAfterTarget = logical(iTake( ...
    F.hasLaterRawCloseAfterTarget,asset,time));

formationBoundaryCoreObserved = iPositive(entryBoundaryClose) & ...
    iPositive(entryBoundaryVolume) & iPositive(entryBoundaryME);
methodFormationCoreObserved = iPositive(iTake( ...
    F.methodFormationClose,asset,time)) & iPositive(iTake( ...
    F.methodFormationVolume,asset,time)) & iPositive(iTake( ...
    F.methodFormationME,asset,time));
targetFirstDayRawTradeProxy = iPositive(targetFirstDayClose) & ...
    iPositive(targetFirstDayVolume) & iPositive(targetFirstDayME);
targetFirstDayM0CoreProxy = iPositive(m2FirstDailyClose) & ...
    iPositive(m2FirstDailyOpen) & iPositive(m2FirstDailyVolume) & ...
    iPositive(m2FirstDailyME);

missingClass = repmat("unclassified",n,1);
l = endpointPayoffObserved;
missingClass(l) = "strict_daily_gap_but_raw_endpoints_observed";
l = ~endpointPayoffObserved & isfinite(entryBoundaryClose) & ...
    ~isfinite(exitBoundaryClose) & hasLaterRawCloseAfterTarget;
missingClass(l) = "missing_exit_endpoint_internal_gap";
l = ~endpointPayoffObserved & isfinite(entryBoundaryClose) & ...
    ~isfinite(exitBoundaryClose) & ~hasLaterRawCloseAfterTarget;
missingClass(l) = "missing_exit_endpoint_terminal_history";
l = ~endpointPayoffObserved & ~isfinite(entryBoundaryClose) & ...
    isfinite(exitBoundaryClose);
missingClass(l) = "missing_entry_endpoint";
l = ~endpointPayoffObserved & ~isfinite(entryBoundaryClose) & ...
    ~isfinite(exitBoundaryClose);
missingClass(l) = "both_endpoints_missing";

% The CMC panels contain no time-stamped exchange announcement field.  Keep
% this explicit so a data gap cannot silently become "known at formation."
announcementEvidenceInInput = false(n,1);

T = table(methodName,yearWeek,assetID,assetName,assetSymbol, ...
    leg,weight,forecast, ...
    methodFormationCoreObserved,formationBoundaryCoreObserved, ...
    targetFirstDayRawTradeProxy, ...
    targetFirstDayM0CoreProxy,endpointPayoffObserved, ...
    strictStatReturnObserved,entryBoundaryClose,entryBoundaryVolume, ...
    entryBoundaryME,targetFirstDayClose,targetFirstDayVolume, ...
    targetFirstDayME,exitBoundaryClose,expectedDailyRows, ...
    m2FiniteDailyReturns,m2FiniteDailyClose,rawTargetStartDate, ...
    rawTargetEndDate,hasRawCloseInsideTarget, ...
    hasLaterRawCloseAfterTarget,announcementEvidenceInInput,missingClass);
end

function x = iTake(M,a,t)
x = M(sub2ind(size(M),a,t));
x = x(:);
end

function l = iPositive(x)
l = isfinite(x) & x>0;
end

function S = iBuildSummary(M0,M2,M1,P2,P1,P1ForM2,F2,F1,T2,T1,TF)
method = strings(0,1);
mechanism = strings(0,1);
weeks = zeros(0,1);
holdings = zeros(0,1);
    function add(m,label,w,h)
        method(end+1,1) = m;
        mechanism(end+1,1) = label;
        weeks(end+1,1) = w;
        holdings(end+1,1) = h;
    end

add("M0","saved_finite_hl", ...
    sum(isfinite(M0.cResults.VW.mPortRet(end,:))),NaN);
add("M2","saved_finite_hl", ...
    sum(isfinite(M2.cResults.VW.mPortRet(end,:))),NaN);
add("M1","saved_finite_hl", ...
    sum(isfinite(M1.cResults.VW.mPortRet(end,:))),NaN);

add("M2","selected_payoff_missing",numel(unique(T2.yearWeek)),height(T2));
add("M2","missing_with_method_formation_core_observed", ...
    numel(unique(T2.yearWeek(T2.methodFormationCoreObserved))), ...
    sum(T2.methodFormationCoreObserved));
add("M2","missing_with_formation_boundary_core_observed", ...
    numel(unique(T2.yearWeek(T2.formationBoundaryCoreObserved))), ...
    sum(T2.formationBoundaryCoreObserved));
add("M2","missing_but_raw_endpoint_payoff_observed", ...
    numel(unique(T2.yearWeek(T2.endpointPayoffObserved))), ...
    sum(T2.endpointPayoffObserved));
add("M2","missing_and_raw_endpoint_payoff_missing", ...
    numel(unique(T2.yearWeek(~T2.endpointPayoffObserved))), ...
    sum(~T2.endpointPayoffObserved));
add("M2","missing_with_target_first_day_raw_trade_proxy", ...
    numel(unique(T2.yearWeek(T2.targetFirstDayRawTradeProxy))), ...
    sum(T2.targetFirstDayRawTradeProxy));

add("M1","selected_payoff_missing",numel(unique(T1.yearWeek)),height(T1));
add("M1","missing_with_method_formation_core_observed", ...
    numel(unique(T1.yearWeek(T1.methodFormationCoreObserved))), ...
    sum(T1.methodFormationCoreObserved));
add("M1","missing_with_formation_boundary_core_observed", ...
    numel(unique(T1.yearWeek(T1.formationBoundaryCoreObserved))), ...
    sum(T1.formationBoundaryCoreObserved));
add("M1","missing_with_target_first_day_raw_trade_proxy", ...
    numel(unique(T1.yearWeek(T1.targetFirstDayRawTradeProxy))), ...
    sum(T1.targetFirstDayRawTradeProxy));

[wAny2,wMin2] = iSurvivorReweightSupport(M2,P2);
[wAny1,wMin1] = iSurvivorReweightSupport(M1,P1);
add("M2","counterfactual_post_sort_survivor_reweight_any",wAny2,NaN);
add("M2","counterfactual_post_sort_survivor_reweight_min5",wMin2,NaN);
add("M1","counterfactual_post_sort_survivor_reweight_any",wAny1,NaN);
add("M1","counterfactual_post_sort_survivor_reweight_min5",wMin1,NaN);

add("M2","counterfactual_same_weights_raw_endpoint_fail_closed", ...
    iSameWeightStrictSupport(M2,P1ForM2),NaN);
add("M2","counterfactual_m0_style_target_mask_and_resort", ...
    iTargetMaskResortSupport(M2,P2,F2.entryBoundaryME,false),NaN);
add("M1","counterfactual_m0_style_target_mask_and_resort", ...
    iTargetMaskResortSupport(M1,P1,F1.entryBoundaryME,true),NaN);

for m = ["M0","M2","M1"]
    state = TF.(m+"ForecastState");
    add(m,"initial_52_week_estimation_window", ...
        sum(state=="initial_estimation_window"),NaN);
    add(m,"post_training_forecasts_1_to_24", ...
        sum(state=="post_training_forecasts_1_to_24"),NaN);
    add(m,"forecast_cross_section_at_least_25", ...
        sum(state=="forecast_cross_section_at_least_25"),NaN);
end
add("M0_to_M2","M0_below25_M2_at_least25", ...
    sum(TF.M0ForecastCount<25 & TF.M2ForecastCount>=25),NaN);
add("M2_to_M1","M2_at_least25_M1_below25", ...
    sum(TF.M2ForecastCount>=25 & TF.M1ForecastCount<25),NaN);
add("M2_to_M1","M2_below25_M1_at_least25", ...
    sum(TF.M2ForecastCount<25 & TF.M1ForecastCount>=25),NaN);

S = table(method,mechanism,weeks,holdings);
end

function T = iForecastSupportTable(M0,M2,M1)
[dates,i0,i2] = intersect(double(M0.vDates(:)),double(M2.vDates(:)),'stable');
[dates,i02,i1] = intersect(dates,double(M1.vDates(:)),'stable');
i0 = i0(i02);
i2 = i2(i02);
assert(numel(dates)==423,'Expected a common 423-week D0 calendar');
M0ForecastCount = sum(isfinite(M0.mYhat(:,i0)),1)';
M2ForecastCount = sum(isfinite(M2.mYhat(:,i2)),1)';
M1ForecastCount = sum(isfinite(M1.mYhat(:,i1)),1)';
M0ForecastState = iForecastState(M0ForecastCount);
M2ForecastState = iForecastState(M2ForecastCount);
M1ForecastState = iForecastState(M1ForecastCount);
T = table(dates,M0ForecastCount,M2ForecastCount,M1ForecastCount, ...
    M0ForecastState,M2ForecastState,M1ForecastState, ...
    'VariableNames',{'yearWeek','M0ForecastCount','M2ForecastCount', ...
    'M1ForecastCount','M0ForecastState','M2ForecastState','M1ForecastState'});
end

function state = iForecastState(n)
state = repmat("forecast_cross_section_at_least_25",numel(n),1);
state(n==0) = "initial_estimation_window";
state(n>0 & n<25) = "post_training_forecasts_1_to_24";
assert(sum(n==0)==52,'Exactly 52 initial estimation weeks are expected');
end

function [anyCount,min5Count] = iSurvivorReweightSupport(S,P)
W = double(S.cResults.VW.mWts);
low = isfinite(W(:,:,1)) & W(:,:,1)~=0 & isfinite(P);
high = isfinite(W(:,:,5)) & W(:,:,5)~=0 & isfinite(P);
anyCount = sum(sum(low,1)>0 & sum(high,1)>0);
min5Count = sum(sum(low,1)>=5 & sum(high,1)>=5);
end

function count = iSameWeightStrictSupport(S,P)
W = double(S.cResults.VW.mWts);
low = isfinite(W(:,:,1)) & W(:,:,1)~=0;
high = isfinite(W(:,:,5)) & W(:,:,5)~=0;
count = sum(sum(low,1)>=5 & sum(high,1)>=5 & ...
    ~any(low & ~isfinite(P),1) & ~any(high & ~isfinite(P),1));
end

function count = iTargetMaskResortSupport(S,P,formationME,hedgeOnly)
count = 0;
for t=1:numel(S.vDates)
    signal = double(S.mYhat(:,t));
    payoff = double(P(:,t));
    me = double(formationME(:,t));
    avail = isfinite(signal) & isfinite(payoff) & isfinite(me) & me>0;
    if sum(avail)<25
        continue
    end
    x = signal(avail);
    q = quantile(x,0:0.2:1,'Method','exact');
    n = zeros(1,5);
    n(1) = sum(x>=q(1) & x<=q(2));
    for p=2:5
        n(p) = sum(x>q(p) & x<=q(p+1));
    end
    if hedgeOnly
        ok = n(1)>=5 && n(5)>=5;
    else
        ok = all(n>=5);
    end
    count = count+ok;
end
end
