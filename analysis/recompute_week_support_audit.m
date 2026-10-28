% CTREND_REVISIT_FILE_PURPOSE: recompute week support audit; publication orchestration, validation or saved-result analysis, not a model-definition edit.
function recompute_week_support_audit(m0BasePath,m2BasePath, ...
    m2WeeklyPath,m1BasePath,outDir)
%RECOMPUTE_WEEK_SUPPORT_AUDIT Explain D0 headline-week support differences.
%
% Explicit MAT arguments are aligned by date before state labels are assigned.
% The output records mutually exclusive support reasons and finite-week counts;
% it is explanatory evidence for frozen historical runs, not a new estimator.
%
% HISTORICAL PRE-AMENDMENT AUDIT.  This function reconstructs the superseded
% selected-payoff fail-closed runs.  For the declared 24-Aug-2026 settlement
% rule use recompute_declared_week_support.m.
%
% This read-only post-run audit reconstructs, week by week, why the M0, M2,
% and M1 baseline H-L series is finite or missing.  It does not alter a run
% root or replace a missing return by zero.  M2 payoffs are reconstructed
% from the frozen synchronized raw-return layer; M1 uses the saved endpoint
% P&L layer.  Site-local source paths are arguments and are never written to
% either public CSV.

arguments
    m0BasePath (1,:) char
    m2BasePath (1,:) char
    m2WeeklyPath (1,:) char
    m1BasePath (1,:) char
    outDir (1,:) char
end

if ~isfolder(outDir)
    mkdir(outDir);
end

M0 = load(m0BasePath,'cResults','vDates','vAssetID');
M2 = load(m2BasePath,'cResults','vDates','vAssetID');
M1 = load(m1BasePath,'cResults','vDates','vAssetID','mRetPnlOOS');
W2 = load(m2WeeklyPath,'rData','rMetaData');

iAssertBase(M0,'M0');
iAssertBase(M2,'M2');
iAssertBase(M1,'M1');
assert(isfield(M1,'mRetPnlOOS'),'M1 base lacks endpoint P&L');

P2 = iAlignM2Payoff(M2,W2);
P1 = double(M1.mRetPnlOOS);
assert(isequal(size(P1),[numel(M1.vAssetID),numel(M1.vDates)]), ...
    'M1 endpoint P&L dimensions disagree');

A0 = iLegacyState(M0);
A2 = iFailClosedState(M2,P2,'M2');
A1 = iFailClosedState(M1,P1,'M1');

[dates,i0,i2,i1] = iIntersect3(double(M0.vDates(:)), ...
    double(M2.vDates(:)),double(M1.vDates(:)));
assert(numel(dates)==423,'Expected all three D0 baselines to contain 423 dates');

A0 = iSubsetState(A0,i0);
A2 = iSubsetState(A2,i2);
A1 = iSubsetState(A1,i1);

yearWeek = dates;
m0State = iStateLabel(A0,false);
m2State = iStateLabel(A2,true);
m1State = iStateLabel(A1,true);
m0Finite = A0.finite;
m2Finite = A2.finite;
m1Finite = A1.finite;
T = table(yearWeek,m0State,m2State,m1State,m0Finite,m2Finite,m1Finite);
writetable(T,fullfile(outDir,'week_support_mask_D0.csv'));

comparison = strings(0,1);
category = strings(0,1);
weeks = zeros(0,1);
    function add(scope,label,count)
        comparison(end+1,1) = scope;
        category(end+1,1) = label;
        weeks(end+1,1) = count;
    end

add("M0_all","total_calendar_positions",numel(dates));
add("M0_all","empty_formation_leg",sum(A0.emptyLeg));
add("M0_all","finite_hl",sum(A0.finite));
add("M2_all","total_calendar_positions",numel(dates));
add("M2_all","empty_formation_leg",sum(A2.emptyLeg));
add("M2_all","selected_payoff_missing_after_formation", ...
    sum(~A2.emptyLeg & A2.missingPayoff));
add("M2_all","finite_hl",sum(A2.finite));
add("M1_all","total_calendar_positions",numel(dates));
add("M1_all","empty_formation_leg",sum(A1.emptyLeg));
add("M1_all","selected_payoff_missing_after_formation", ...
    sum(~A1.emptyLeg & A1.missingPayoff));
add("M1_all","finite_hl",sum(A1.finite));

l = A0.finite & ~A2.finite;
add("M0_to_M2","m0_finite_m2_empty_formation_leg",sum(l & A2.emptyLeg));
add("M0_to_M2","m0_finite_m2_selected_payoff_missing", ...
    sum(l & ~A2.emptyLeg & A2.missingPayoff));
add("M0_to_M2","m0_missing_m2_finite",sum(~A0.finite & A2.finite));

l = A0.finite & ~A1.finite;
add("M0_to_M1","m0_finite_m1_empty_formation_leg",sum(l & A1.emptyLeg));
add("M0_to_M1","m0_finite_m1_selected_payoff_missing", ...
    sum(l & ~A1.emptyLeg & A1.missingPayoff));
add("M0_to_M1","m0_missing_m1_finite",sum(~A0.finite & A1.finite));

l = A1.finite & ~A2.finite;
add("M2_to_M1","m1_finite_m2_empty_formation_leg",sum(l & A2.emptyLeg));
add("M2_to_M1","m1_finite_m2_selected_payoff_missing", ...
    sum(l & ~A2.emptyLeg & A2.missingPayoff));
l = A2.finite & ~A1.finite;
add("M2_to_M1","m2_finite_m1_empty_formation_leg",sum(l & A1.emptyLeg));
add("M2_to_M1","m2_finite_m1_selected_payoff_missing", ...
    sum(l & ~A1.emptyLeg & A1.missingPayoff));

S = table(comparison,category,weeks);
writetable(S,fullfile(outDir,'week_support_reason_summary_D0.csv'));

% Fixed regression identities for the accepted D0 artifacts.  These make a
% future change to any mask or accounting convention fail loudly.
assert(sum(A0.finite)==349 && sum(A0.emptyLeg)==74);
assert(sum(A2.finite)==280 && sum(A2.emptyLeg)==70 && ...
    sum(~A2.emptyLeg & A2.missingPayoff)==73);
assert(sum(A1.finite)==326 && sum(A1.emptyLeg)==86 && ...
    sum(~A1.emptyLeg & A1.missingPayoff)==11);
assert(sum(A0.finite & ~A2.finite & ~A2.emptyLeg & A2.missingPayoff)==73);
assert(sum(~A0.finite & A2.finite)==4);
assert(349-73+4==280);

fprintf('WEEK_SUPPORT_AUDIT_OK dates=%d M0=%d M2=%d M1=%d\n', ...
    numel(dates),sum(A0.finite),sum(A2.finite),sum(A1.finite));
end

function iAssertBase(S,label)
required = {'cResults','vDates','vAssetID'};
assert(all(isfield(S,required)),'%s base is incomplete',label);
assert(isfield(S.cResults,'VW') && isfield(S.cResults.VW,'mPortRet') && ...
    isfield(S.cResults.VW,'mWts'),'%s base lacks VW results',label);
end

function A = iLegacyState(S)
W = double(S.cResults.VW.mWts);
low = isfinite(W(:,:,1)) & W(:,:,1)~=0;
high = isfinite(W(:,:,5)) & W(:,:,5)~=0;
A.emptyLeg = sum(low,1)'==0 | sum(high,1)'==0;
A.missingPayoff = false(size(A.emptyLeg));
A.finite = isfinite(double(S.cResults.VW.mPortRet(end,:))');
assert(isequal(~A.emptyLeg,A.finite), ...
    'M0 finite support is not explained by its saved portfolio weights');
end

function A = iFailClosedState(S,P,label)
W = double(S.cResults.VW.mWts);
low = isfinite(W(:,:,1)) & W(:,:,1)~=0;
high = isfinite(W(:,:,5)) & W(:,:,5)~=0;
A.emptyLeg = sum(low,1)'==0 | sum(high,1)'==0;
A.missingPayoff = any(low & ~isfinite(P),1)' | ...
    any(high & ~isfinite(P),1)';
A.finite = isfinite(double(S.cResults.VW.mPortRet(end,:))');
expected = ~A.emptyLeg & ~A.missingPayoff;
assert(isequal(expected,A.finite), ...
    '%s finite support is not explained by formation and payoff masks',label);
end

function A = iSubsetState(A,idx)
A.emptyLeg = A.emptyLeg(idx);
A.missingPayoff = A.missingPayoff(idx);
A.finite = A.finite(idx);
end

function label = iStateLabel(A,hasPayoffState)
label = strings(numel(A.finite),1);
label(A.emptyLeg) = "empty_formation_leg";
if hasPayoffState
    label(~A.emptyLeg & A.missingPayoff) = ...
        "selected_payoff_missing_after_formation";
end
label(A.finite) = "finite_hl";
assert(all(strlength(label)>0),'Unclassified week-support state');
end

function P = iAlignM2Payoff(S,W)
assert(isfield(W,'rData') && isfield(W,'rMetaData') && ...
    isfield(W.rData,'yrmoda') && isfield(W.rData,'mReturnsM2Raw') && ...
    isfield(W.rMetaData,'vID'),'M2 weekly input is incomplete');
l = W.rData.yrmoda>=201416 & W.rData.yrmoda<=202222;
dates = double(W.rData.yrmoda(l));
ids = double(W.rMetaData.vID(:));
p0 = double(W.rData.mReturnsM2Raw(l,:))';
[~,ir,id] = intersect(double(S.vDates(:)),dates,'stable');
[~,ar,ad] = intersect(double(S.vAssetID(:)),ids,'stable');
assert(numel(ir)==numel(S.vDates) && numel(ar)==numel(S.vAssetID), ...
    'M2 payoff layer does not cover the saved baseline panel');
P = NaN(numel(S.vAssetID),numel(S.vDates));
P(ar,ir) = p0(ad,id);
end

function [dates,ia,ib,ic] = iIntersect3(a,b,c)
[ab,ia0,ib0] = intersect(a,b,'stable');
[dates,iab,ic] = intersect(ab,c,'stable');
ia = ia0(iab);
ib = ib0(iab);
end
