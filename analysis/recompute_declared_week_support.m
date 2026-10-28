function rAudit = recompute_declared_week_support(rFiles,sOutputDir)
% CTREND_REVISIT_FILE_PURPOSE: Revalue fixed D0 forecasts under the declared availability and same-leg reinvestment rule.
%RECOMPUTE_DECLARED_WEEK_SUPPORT Revalue fixed D0 forecasts under the new rule.
%
% Inputs must identify the M0/M2/M1 D0 weekly data, CTREND result and Utils
% trees. Outputs contain revalued returns and reason-coded week support.
% Forecasts, ranks and selected portfolios remain fixed; only the declared
% endpoint/terminal-settlement accounting is applied to M1/M2.
%
% This is a read-only scientific audit. It never edits an existing run and
% never re-estimates M0/M1/M2 forecasts. M1/M2 fixed forecast matrices are
% paired with the revised endpoint/frozen-exit/same-leg accounting; M0 is loaded
% exactly as saved by the new-v2 run and is not revalued. Required rFiles fields are:
%   m0Weekly, m0CTREND,
%   m2Weekly, m2CTREND,
%   m1Weekly, m1CTREND,
%   m0Utils, m2Utils, m1Utils.

arguments
    rFiles (1,1) struct
    sOutputDir (1,1) string
end
cRequired = {'m0Weekly','m0CTREND','m2Weekly','m2CTREND', ...
    'm1Weekly','m1CTREND','m0Utils','m2Utils','m1Utils'};
% Fail before loading large MAT files if any declared dependency is absent.
for iIdx = 1:numel(cRequired)
    sField = cRequired{iIdx};
    assert(isfield(rFiles,sField), 'Missing rFiles.%s',sField);
    if endsWith(sField,'Utils')
        assert(isfolder(rFiles.(sField)), ...
            'Missing utility directory: %s',rFiles.(sField));
    else
        assert(isfile(rFiles.(sField)), ...
            'Missing audit input: %s',rFiles.(sField));
    end
end
if ~isfolder(sOutputDir)
    mkdir(sOutputDir);
end

% M0 is intentionally not recalculated. Load its exact completed new-v2
% result and reconstruct only a transparent support-reason audit.
[rM0,vDateM0] = iLoadM0(rFiles);
[rM2,vDateM2] = iRevalueM1M2('M2',rFiles.m2Weekly, ...
    rFiles.m2CTREND,rFiles.m2Utils,false);
[rM1,vDateM1] = iRevalueM1M2('M1',rFiles.m1Weekly, ...
    rFiles.m1CTREND,rFiles.m1Utils,true);
assert(isequal(vDateM0,vDateM2) && isequal(vDateM0,vDateM1), ...
    'M0/M2/M1 D0 weekly calendars do not align');
vDates = vDateM0;

cMethod = ["M0";"M2";"M1"];
cObject = {rM0;rM2;rM1};
vPreviousN = NaN(3,1);
vRevisedN = NaN(3,1);
vFiniteToMissing = NaN(3,1);
vMissingToFinite = NaN(3,1);
vForecastWeekN = NaN(3,1);
vProposedWeekN = NaN(3,1);
vTradableCSWeekN = NaN(3,1);
vPortfolioSizeWeekN = NaN(3,1);
% Audit each method independently, then compare their common calendar below.
for iIdx = 1:3
    q = cObject{iIdx};
    vPreviousN(iIdx) = nnz(q.lPreviousFinite);
    vRevisedN(iIdx) = nnz(q.lRevisedFinite);
    vFiniteToMissing(iIdx) = nnz(q.lPreviousFinite & ~q.lRevisedFinite);
    vMissingToFinite(iIdx) = nnz(~q.lPreviousFinite & q.lRevisedFinite);
    vForecastWeekN(iIdx) = nnz(q.vSignalCount>0);
    vProposedWeekN(iIdx) = nnz(q.vProposedCount>=25);
    vTradableCSWeekN(iIdx) = nnz(q.vTradableCount>=25);
    vPortfolioSizeWeekN(iIdx) = nnz(q.lPortfolioSizePass);
end
tSummary = table(cMethod,vPreviousN,vRevisedN,vFiniteToMissing, ...
    vMissingToFinite,vForecastWeekN,vProposedWeekN,vTradableCSWeekN, ...
    vPortfolioSizeWeekN,'VariableNames', ...
    {'method','previous_finite_n','revised_finite_n', ...
     'previous_finite_now_missing_n','previous_missing_now_finite_n', ...
     'any_forecast_week_n','proposed_cs_ge_25_week_n', ...
     'tradable_cs_ge_25_week_n','portfolio_size_pass_week_n'});
writetable(tSummary,fullfile(sOutputDir, ...
    'revised_M0_M2_M1_week_count_summary_D0.csv'));

tWeekly = table(vDates,rM0.lPreviousFinite,rM0.lRevisedFinite, ...
    rM2.lPreviousFinite,rM2.lRevisedFinite,rM1.lPreviousFinite, ...
    rM1.lRevisedFinite,rM0.vSignalCount,rM2.vSignalCount, ...
    rM1.vSignalCount,rM0.vProposedCount,rM2.vProposedCount, ...
    rM1.vProposedCount,rM0.vUnavailableCount,rM2.vUnavailableCount, ...
    rM1.vUnavailableCount,rM0.vTradableCount,rM2.vTradableCount, ...
    rM1.vTradableCount,rM0.sReason,rM2.sReason,rM1.sReason, ...
    'VariableNames',{'year_week','M0_previous_finite','M0_revised_finite', ...
    'M2_previous_finite','M2_revised_finite','M1_previous_finite', ...
    'M1_revised_finite','M0_signal_n','M2_signal_n','M1_signal_n', ...
    'M0_proposed_n','M2_proposed_n','M1_proposed_n', ...
    'M0_known_unavailable_n','M2_known_unavailable_n', ...
    'M1_known_unavailable_n','M0_tradable_n','M2_tradable_n', ...
    'M1_tradable_n','M0_reason','M2_reason','M1_reason'});
writetable(tWeekly,fullfile(sOutputDir, ...
    'revised_M0_M2_M1_week_support_D0.csv'));

% Pairwise and three-way support are reported explicitly because own-support
% statistics are not directly comparable when method-specific formation
% support differs.
cPairA = ["M0";"M0";"M2"];
cPairB = ["M2";"M1";"M1"];
vCommonN = NaN(3,1);
vOnlyAN = NaN(3,1);
vOnlyBN = NaN(3,1);
vUnionN = NaN(3,1);
vJaccard = NaN(3,1);
for iIdx = 1:3
    iA = find(cMethod==cPairA(iIdx),1);
    iB = find(cMethod==cPairB(iIdx),1);
    lA = cObject{iA}.lRevisedFinite;
    lB = cObject{iB}.lRevisedFinite;
    vCommonN(iIdx) = nnz(lA & lB);
    vOnlyAN(iIdx) = nnz(lA & ~lB);
    vOnlyBN(iIdx) = nnz(~lA & lB);
    vUnionN(iIdx) = nnz(lA | lB);
    vJaccard(iIdx) = vCommonN(iIdx)/vUnionN(iIdx);
end
tPairwise = table(cPairA,cPairB,vCommonN,vOnlyAN,vOnlyBN,vUnionN, ...
    vJaccard,'VariableNames',{'method_a','method_b','common_n', ...
    'only_a_n','only_b_n','union_n','jaccard'});
writetable(tPairwise,fullfile(sOutputDir, ...
    'revised_M0_M2_M1_pairwise_support_D0.csv'));

cReasonMethod = strings(0,1);
cReason = strings(0,1);
vReasonN = zeros(0,1);
for iIdx = 1:3
    cUniqueReason = unique(cObject{iIdx}.sReason);
    for iIdxR = 1:numel(cUniqueReason)
        cReasonMethod(end+1,1) = cMethod(iIdx); %#ok<AGROW>
        cReason(end+1,1) = cUniqueReason(iIdxR); %#ok<AGROW>
        vReasonN(end+1,1) = nnz( ...
            cObject{iIdx}.sReason==cUniqueReason(iIdxR)); %#ok<AGROW>
    end
end
tReason = table(cReasonMethod,cReason,vReasonN,'VariableNames', ...
    {'method','mutually_exclusive_reason','week_n'});
writetable(tReason,fullfile(sOutputDir, ...
    'revised_M0_M2_M1_support_reasons_D0.csv'));

lAllThree = rM0.lRevisedFinite & rM2.lRevisedFinite & ...
    rM1.lRevisedFinite;
assert(any(lAllThree),'M0/M2/M1 have no common revised D0 week');
tAllThree = table(nnz(lAllThree),vDates(find(lAllThree,1,'first')), ...
    vDates(find(lAllThree,1,'last')),'VariableNames', ...
    {'common_n','start_year_week','end_year_week'});
writetable(tAllThree,fullfile(sOutputDir, ...
    'revised_M0_M2_M1_all_common_support_D0.csv'));

rAudit = struct('tSummary',tSummary,'tWeekly',tWeekly,'M0',rM0, ...
    'M2',rM2,'M1',rM1,'vDates',vDates,'tPairwise',tPairwise, ...
    'tReason',tReason,'tAllThree',tAllThree, ...
    'sRule',['known target unavailability is removed before breakpoints; ' ...
    'interior OHLC gaps use the prior close; frozen terminal exits settle ' ...
    'at the last tradable close and immediately reinvest within the same leg']);
save(fullfile(sOutputDir,'revised_M0_M2_M1_week_support_D0.mat'), ...
    'rAudit');
fprintf('REVISED_WEEK_SUPPORT_OK M0=%d M2=%d M1=%d\n', ...
    vRevisedN(1),vRevisedN(2),vRevisedN(3));
end

function [rOut,vDates] = iLoadM0(rFiles)
W = load(rFiles.m0Weekly,'rData','rMetaData');
C = load(rFiles.m0CTREND,'mYhat','cResults','vDates');
rData = W.rData;
mReturns = rData.mReturns;
mME = rData.mME;
mPrices = rData.mClose;
vDatesAll = rData.yrmoda(:);
lRemove = mME==0 | mME<1e6 | mPrices<0 | W.rMetaData.lIsStable;
mReturns(lRemove) = NaN;
mME(lRemove) = NaN;
mME_L1 = [NaN(1,size(mME,2));mME(1:end-1,:)];
lSample = vDatesAll>=201416 & vDatesAll<=202222;
vDates = vDatesAll(lSample);
assert(isequal(vDates,C.vDates(:)),'M0 CTREND/weekly calendar mismatch');
mReturns = mReturns(lSample,:)';
mME_L1 = mME_L1(lSample,:)';
rOut = iSupportState(C.mYhat,mReturns,mME_L1,false);
rOut.lPreviousFinite = isfinite(C.cResults.VW.mPortRet(end,:)');
rOut.lRevisedFinite = rOut.lPreviousFinite;
assert(isequal(rOut.lRevisedFinite,rOut.lExpectedFinite), ...
    'M0 reconstructed support differs from its frozen result');
end

function [rOut,vDates] = iRevalueM1M2(sMethod,sWeekly,sCTREND, ...
        sUtils,lHedgeOnly)
sOldPath = path;
addpath(sUtils,'-begin');
rPathCleanup = onCleanup(@() path(sOldPath)); %#ok<NASGU>
clear fAttachEconomicLedgerOptions fLoadEconomicReinvestmentLedger ...
    fSingleSortMulti
W = load(sWeekly,'rData','rMetaData');
C = load(sCTREND,'mYhat','cResults','vDates');
rData = W.rData;
vDatesAll = rData.yrmoda(:);
if strcmp(sMethod,'M1')
    assert(isfield(rData,'mPnlReturns'), ...
        'M1 weekly input lacks endpoint P&L');
    mPnl = rData.mPnlReturns;
else
    assert(isfield(rData,'mPnlReturnsM2'), ...
        'M2 weekly input lacks endpoint P&L');
    mPnl = rData.mPnlReturnsM2;
end
mME_L1 = [NaN(1,size(rData.mME,2));rData.mME(1:end-1,:)];
mPrices_L1 = [NaN(1,size(rData.mClose,2));rData.mClose(1:end-1,:)];
lSample = vDatesAll>=201416 & vDatesAll<=202222;
vDates = vDatesAll(lSample);
assert(isequal(vDates,C.vDates(:)), ...
    '%s CTREND/weekly calendar mismatch',sMethod);
mPnl = mPnl(lSample,:);
mME_L1 = mME_L1(lSample,:);
mPrices_L1 = mPrices_L1(lSample,:);
lRemove = isnan(mME_L1) | isnan(mPrices_L1) | mME_L1==0 | ...
    mME_L1<1e6 | mPrices_L1<0 | W.rMetaData.lIsStable;
mPnl(lRemove) = NaN;
mME_L1(lRemove) = NaN;
rOptions = struct('sFreq','weekly','lHedgeOnly',lHedgeOnly, ...
    'iMinNumCS',25,'iMinNumAssets',5,'lEnsureAllObs',true);
[rOptions,~,~] = fAttachEconomicLedgerOptions( ...
    rOptions,fileparts(sWeekly),rData,W.rMetaData.vID(:),vDates,'ordinary');
rSort = fSingleSortMulti(C.mYhat,mPnl',0:0.2:1,[],mME_L1',rOptions);
rOut = iSupportState(C.mYhat,mPnl',mME_L1',lHedgeOnly);
rOut.lPreviousFinite = isfinite(C.cResults.VW.mPortRet(end,:)');
rOut.lRevisedFinite = isfinite(rSort.VW.mPortRet(end,:)');
rOut.vRevisedReturn = rSort.VW.mPortRet(end,:)';
lEconomicFailure = rOut.lExpectedFinite & ~rOut.lRevisedFinite;
rOut.sReason(lEconomicFailure) = ...
    "terminal_event_no_same_leg_recipient_or_undefined_event_price";
rOut.lExpectedFinite = rOut.lRevisedFinite;
end

function r = iSupportState(mSignal,mReturn,mFormationME,lHedgeOnly)
iNumObs = size(mSignal,2);
r = struct();
r.vSignalCount = sum(isfinite(mSignal),1)';
lProposed = isfinite(mSignal) & isfinite(mFormationME) & mFormationME>0;
lTradable = lProposed & isfinite(mReturn);
r.vProposedCount = sum(lProposed,1)';
r.vUnavailableCount = sum(lProposed & ~isfinite(mReturn),1)';
r.vTradableCount = sum(lTradable,1)';
r.mPortfolioCount = zeros(iNumObs,5);
r.lPortfolioSizePass = false(iNumObs,1);
r.lExpectedFinite = false(iNumObs,1);
r.sReason = strings(iNumObs,1);
for iIdxT = 1:iNumObs
    if r.vSignalCount(iIdxT)==0
        r.sReason(iIdxT) = "no_forecast";
        continue
    end
    if r.vProposedCount(iIdxT)<25
        r.sReason(iIdxT) = "formation_cross_section_below_25";
        continue
    end
    if r.vTradableCount(iIdxT)<25
        r.sReason(iIdxT) = "tradable_cross_section_below_25";
        continue
    end
    vSignal = mSignal(lTradable(:,iIdxT),iIdxT);
    vBreak = quantile(vSignal,0:0.2:1,'Method','exact');
    for iIdxP = 1:5
        if iIdxP==1
            lMember = vSignal>=vBreak(iIdxP) & ...
                vSignal<=vBreak(iIdxP+1);
        else
            lMember = vSignal>vBreak(iIdxP) & ...
                vSignal<=vBreak(iIdxP+1);
        end
        r.mPortfolioCount(iIdxT,iIdxP) = nnz(lMember);
    end
    if lHedgeOnly
        r.lPortfolioSizePass(iIdxT) = ...
            r.mPortfolioCount(iIdxT,1)>=5 && ...
            r.mPortfolioCount(iIdxT,5)>=5;
    else
        r.lPortfolioSizePass(iIdxT) = ...
            all(r.mPortfolioCount(iIdxT,:)>=5);
    end
    if ~r.lPortfolioSizePass(iIdxT)
        r.sReason(iIdxT) = "required_portfolio_below_5";
        continue
    end
    r.lExpectedFinite(iIdxT) = true;
    r.sReason(iIdxT) = "finite";
end
end
