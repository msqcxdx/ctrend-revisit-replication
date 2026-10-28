% CTREND_REVISIT_FILE_PURPOSE: recompute ablation diagnostics; publication orchestration, validation or saved-result analysis, not a model-definition edit.
function recompute_ablation_diagnostics(m0d0Path,m0d1Path,m0d2Path, ...
    m1d0Path,m1d1Path,m1d2Path,m2d0Path,m2d1Path,m2d2Path, ...
    m1d1WeeklyPath,m2d0WeeklyPath,m2d1WeeklyPath,outDir)
%RECOMPUTE_ABLATION_DIAGNOSTICS Rebuild the public M0--M2--M1 diagnostics.
%
% Inputs are the nine frozen baseline files plus the named weekly inputs needed
% for the historical M1/M2 payoff reconstruction. Outputs are CSV diagnostics;
% no accepted result is mutated and no missing return is converted to zero.
%
% HISTORICAL PRE-AMENDMENT AUDIT.  It reproduces the exact nine completed
% frozen-parent runs made before the 24-Aug-2026 common-input and no-cash
% same-leg terminal-settlement amendment.
% Do not use it as acceptance evidence for amended M1/M2 source.
%
% This analysis is read-only with respect to production runs.  It consumes
% the nine completed baseline CTREND_Base.mat files and the two M2 weekly
% inputs needed to reconstruct synchronized M2 payoffs.  It writes only CSV
% files below outDir.  Absolute source paths are intentionally not written to
% the outputs, so the published diagnostics contain no site-specific paths.
%
% The calculations align both dates and CMCIDs before comparing methods.
% Missing selected payoffs fail closed under that historical specification.
% NaN observations are never treated as zero, and method-specific headline
% statistics retain each method's own finite-week support.

arguments
    m0d0Path (1,:) char
    m0d1Path (1,:) char
    m0d2Path (1,:) char
    m1d0Path (1,:) char
    m1d1Path (1,:) char
    m1d2Path (1,:) char
    m2d0Path (1,:) char
    m2d1Path (1,:) char
    m2d2Path (1,:) char
    m1d1WeeklyPath (1,:) char
    m2d0WeeklyPath (1,:) char
    m2d1WeeklyPath (1,:) char
    outDir (1,:) char
end

if ~isfolder(outDir)
    mkdir(outDir);
end

R = struct();
R.M0_D0 = iLoadBase(m0d0Path,false);
R.M0_D1 = iLoadBase(m0d1Path,false);
R.M0_D2 = iLoadBase(m0d2Path,false);
R.M1_D0 = iLoadBase(m1d0Path,true);
R.M1_D1 = iLoadBase(m1d1Path,true);
R.M1_D2 = iLoadBase(m1d2Path,true);
R.M2_D0 = iLoadBase(m2d0Path,false);
R.M2_D1 = iLoadBase(m2d1Path,false);
R.M2_D2 = iLoadBase(m2d2Path,false);
R.M1_D1.mPayoffFull = iLoadM1Payoff(m1d1WeeklyPath,R.M1_D1);
R.M2_D0.mPayoff = iLoadM2Payoff(m2d0WeeklyPath,R.M2_D0);
R.M2_D1.mPayoff = iLoadM2Payoff(m2d1WeeklyPath,R.M2_D1);

%% Method-specific headline support
cCells = {'M0_D0','M2_D0','M1_D0', ...
    'M0_D1','M2_D1','M1_D1','M0_D2','M2_D2','M1_D2'};
cUniverse = {'D0','D0','D0','D1','D1','D1','D2','D2','D2'};
cMethod = {'M0','M2','M1','M0','M2','M1','M0','M2','M1'};
n = numel(cCells);
cellName = strings(n,1);
universe = strings(n,1);
method = strings(n,1);
finiteWeeks = zeros(n,1);
meanPct = NaN(n,1);
stdPct = NaN(n,1);
tStatistic = NaN(n,1);
annualizedSharpe = NaN(n,1);
% First describe each saved baseline on its own finite support.
for i=1:n
    x = R.(cCells{i}).vHedge;
    l = isfinite(x);
    cellName(i) = cCells{i};
    universe(i) = cUniverse{i};
    method(i) = cMethod{i};
    finiteWeeks(i) = sum(l);
    meanPct(i) = 100*mean(x(l));
    stdPct(i) = 100*std(x(l));
    tStatistic(i) = mean(x(l))/(std(x(l))/sqrt(sum(l)));
    annualizedSharpe(i) = sqrt(52)*mean(x(l))/std(x(l));
end
T = table(cellName,universe,method,finiteWeeks,meanPct,stdPct, ...
    tStatistic,annualizedSharpe);
writetable(T,fullfile(outDir,'method_specific_headline_support.csv'));

%% Pairwise common-week decompositions
cPairs = {
    'D0','M0_to_M2','M0_D0','M2_D0';
    'D0','M2_to_M1','M2_D0','M1_D0';
    'D0','M0_to_M1','M0_D0','M1_D0';
    'D1','M0_to_M2','M0_D1','M2_D1';
    'D1','M2_to_M1','M2_D1','M1_D1';
    'D1','M0_to_M1','M0_D1','M1_D1';
    'D2','M0_to_M2','M0_D2','M2_D2';
    'D2','M2_to_M1','M2_D2','M1_D2';
    'D2','M0_to_M1','M0_D2','M1_D2'};
universe = strings(size(cPairs,1),1);
comparison = strings(size(cPairs,1),1);
leftCell = strings(size(cPairs,1),1);
rightCell = strings(size(cPairs,1),1);
commonWeeks = zeros(size(cPairs,1),1);
leftMeanPct = NaN(size(cPairs,1),1);
rightMeanPct = NaN(size(cPairs,1),1);
rightMinusLeftPctPoint = NaN(size(cPairs,1),1);
returnCorrelation = NaN(size(cPairs,1),1);
leftOnlyWeeks = zeros(size(cPairs,1),1);
leftOnlyMeanPct = NaN(size(cPairs,1),1);
rightOnlyWeeks = zeros(size(cPairs,1),1);
rightOnlyMeanPct = NaN(size(cPairs,1),1);
% Then compare only aligned pairwise weeks, holdings, and payoff components.
for i=1:size(cPairs,1)
    a = R.(cPairs{i,3}); b = R.(cPairs{i,4});
    [ia,ib] = iAlignDates(a.vDates,b.vDates);
    x = a.vHedge(ia); y = b.vHedge(ib);
    lc = isfinite(x) & isfinite(y);
    ll = isfinite(x) & ~isfinite(y);
    lr = ~isfinite(x) & isfinite(y);
    universe(i) = cPairs{i,1}; comparison(i) = cPairs{i,2};
    leftCell(i) = cPairs{i,3}; rightCell(i) = cPairs{i,4};
    commonWeeks(i) = sum(lc);
    leftMeanPct(i) = 100*mean(x(lc));
    rightMeanPct(i) = 100*mean(y(lc));
    rightMinusLeftPctPoint(i) = rightMeanPct(i)-leftMeanPct(i);
    if sum(lc)>=2
        C = corrcoef(x(lc),y(lc)); returnCorrelation(i)=C(1,2);
    end
    leftOnlyWeeks(i)=sum(ll); rightOnlyWeeks(i)=sum(lr);
    if any(ll), leftOnlyMeanPct(i)=100*mean(x(ll)); end
    if any(lr), rightOnlyMeanPct(i)=100*mean(y(lr)); end
end
T = table(universe,comparison,leftCell,rightCell,commonWeeks, ...
    leftMeanPct,rightMeanPct,rightMinusLeftPctPoint,returnCorrelation, ...
    leftOnlyWeeks,leftOnlyMeanPct,rightOnlyWeeks,rightOnlyMeanPct);
writetable(T,fullfile(outDir,'pairwise_common_week_decomposition.csv'));

%% Three-method common support
universe = ["D0";"D1";"D2"];
nUniverse = numel(universe);
commonWeeks = zeros(nUniverse,1);
m0MeanPct = NaN(nUniverse,1); m2MeanPct = NaN(nUniverse,1);
m1MeanPct = NaN(nUniverse,1);
m2MinusM0PctPoint = NaN(nUniverse,1);
m1MinusM2PctPoint = NaN(nUniverse,1);
for i=1:nUniverse
    d = char(universe(i));
    a=R.(['M0_' d]); b=R.(['M2_' d]); c=R.(['M1_' d]);
    [dates,ia,ib,ic] = intersect3(a.vDates,b.vDates,c.vDates); %#ok<ASGLU>
    x=a.vHedge(ia); y=b.vHedge(ib); z=c.vHedge(ic);
    l=isfinite(x)&isfinite(y)&isfinite(z);
    commonWeeks(i)=sum(l);
    m0MeanPct(i)=100*mean(x(l)); m2MeanPct(i)=100*mean(y(l));
    m1MeanPct(i)=100*mean(z(l));
    m2MinusM0PctPoint(i)=m2MeanPct(i)-m0MeanPct(i);
    m1MinusM2PctPoint(i)=m1MeanPct(i)-m2MeanPct(i);
end
T=table(universe,commonWeeks,m0MeanPct,m2MeanPct,m1MeanPct, ...
    m2MinusM0PctPoint,m1MinusM2PctPoint);
writetable(T,fullfile(outDir,'three_method_common_week_decomposition.csv'));

%% Forecast-cell correlation and low/high membership overlap
universe=["D0";"D1";"D2"];
nUniverse=numel(universe);
commonForecastCells=zeros(nUniverse,1);
forecastCorrelation=NaN(nUniverse,1);
commonDates=zeros(nUniverse,1);
lowJaccardMean=NaN(nUniverse,1); lowJaccardMedian=NaN(nUniverse,1);
highJaccardMean=NaN(nUniverse,1); highJaccardMedian=NaN(nUniverse,1);
for i=1:nUniverse
    d=char(universe(i)); a=R.(['M2_' d]); b=R.(['M1_' d]);
    [ia,ib]=iAlignDates(a.vDates,b.vDates);
    [aa,ab]=iAlignAssets(a.vAssetID,b.vAssetID);
    x=a.mYhat(aa,ia); y=b.mYhat(ab,ib); l=isfinite(x)&isfinite(y);
    commonForecastCells(i)=sum(l,'all');
    C=corrcoef(x(l),y(l)); forecastCorrelation(i)=C(1,2);
    low=zeros(numel(ia),1); high=low;
    for t=1:numel(ia)
        low(t)=iJaccard(a.mWts(aa,ia(t),1),b.mWts(ab,ib(t),1));
        high(t)=iJaccard(a.mWts(aa,ia(t),5),b.mWts(ab,ib(t),5));
    end
    commonDates(i)=numel(ia);
    lowJaccardMean(i)=mean(low,'omitnan');
    lowJaccardMedian(i)=median(low,'omitnan');
    highJaccardMean(i)=mean(high,'omitnan');
    highJaccardMedian(i)=median(high,'omitnan');
end
T=table(universe,commonForecastCells,forecastCorrelation,commonDates, ...
    lowJaccardMean,lowJaccardMedian,highJaccardMean,highJaccardMedian);
writetable(T,fullfile(outDir,'forecast_and_holdings_overlap.csv'));

%% D1 fixed-weight / payoff swap
a=R.M1_D1; b=R.M2_D1;
[ia,ib]=iAlignDates(a.vDates,b.vDates);
[aa,ab]=iAlignAssets(a.vAssetID,b.vAssetID);
W1=a.mWts(aa,ia,:); W2=b.mWts(ab,ib,:);
% Use the complete raw endpoint layer from the weekly M1 input for the swap.
% mRetPnlOOS is intentionally sparse outside M1's own model panel and would
% incorrectly classify M2-only holdings as missing merely because M1 did not
% forecast them.
P1=a.mPayoffFull(aa,ia); P2=b.mPayoff(ab,ib);
vW1P1=iHedgeFromWeightsPayoff(W1,P1);
vW1P2=iHedgeFromWeightsPayoff(W1,P2);
vW2P1=iHedgeFromWeightsPayoff(W2,P1);
vW2P2=iHedgeFromWeightsPayoff(W2,P2);
iAssertReturnMatch(vW1P1,a.vHedge(ia),'M1 D1 reconstruction');
iAssertReturnMatch(vW2P2,b.vHedge(ib),'M2 D1 reconstruction');
cNames={'W1P1_M1_weights_M1_payoff','W1P2_M1_weights_M2_payoff', ...
    'W2P1_M2_weights_M1_payoff','W2P2_M2_weights_M2_payoff'};
V=[vW1P1(:),vW1P2(:),vW2P1(:),vW2P2(:)];
specification=strings(8,1); support=strings(8,1);
finiteWeeks=zeros(8,1); meanPct=NaN(8,1); stdPct=NaN(8,1);
allCommon=all(isfinite(V),2);
for j=1:4
    l=isfinite(V(:,j));
    specification(j)=cNames{j}; support(j)="own_finite_support";
    finiteWeeks(j)=sum(l); meanPct(j)=100*mean(V(l,j));
    stdPct(j)=100*std(V(l,j));
    specification(j+4)=cNames{j}; support(j+4)="all_four_common_support";
    finiteWeeks(j+4)=sum(allCommon); meanPct(j+4)=100*mean(V(allCommon,j));
    stdPct(j+4)=100*std(V(allCommon,j));
end
T=table(specification,support,finiteWeeks,meanPct,stdPct);
writetable(T,fullfile(outDir,'fixed_weight_payoff_swap_D1.csv'));

%% Extreme-week attribution and M2 trimming sensitivity
rowLabel=strings(3,1); cellName=strings(3,1); yearWeek=NaN(3,1);
hedgeReturnPct=NaN(3,1); assetID=NaN(3,1); assetPayoffPct=NaN(3,1);
lowWeightPct=NaN(3,1); highWeightPct=NaN(3,1);
assetHedgeContributionPctPoint=NaN(3,1);
[~,iMax]=max(R.M2_D0.vHedge,[],'omitnan');
[~,iMin]=min(R.M2_D0.vHedge,[],'omitnan');
[rowLabel(1),cellName(1),yearWeek(1),hedgeReturnPct(1),assetID(1), ...
    assetPayoffPct(1),lowWeightPct(1),highWeightPct(1), ...
    assetHedgeContributionPctPoint(1)] = ...
    iExtremeRow("maximum","M2_D0",R.M2_D0,iMax);
[rowLabel(2),cellName(2),yearWeek(2),hedgeReturnPct(2),assetID(2), ...
    assetPayoffPct(2),lowWeightPct(2),highWeightPct(2), ...
    assetHedgeContributionPctPoint(2)] = ...
    iExtremeRow("minimum","M2_D0",R.M2_D0,iMin);
iInnbcl=find(R.M1_D0.vAssetID==3787,1);
iWeek=find(R.M1_D0.vDates==202016,1);
assert(~isempty(iInnbcl)&&~isempty(iWeek),'INNBCL 2020W16 not found');
rowLabel(3)="INNBCL_2020W16"; cellName(3)="M1_D0";
yearWeek(3)=R.M1_D0.vDates(iWeek);
hedgeReturnPct(3)=100*R.M1_D0.vHedge(iWeek);
assetID(3)=3787; assetPayoffPct(3)=100*R.M1_D0.mPayoff(iInnbcl,iWeek);
lowWeightPct(3)=100*iFiniteWeight(R.M1_D0.mWts(iInnbcl,iWeek,1));
highWeightPct(3)=100*iFiniteWeight(R.M1_D0.mWts(iInnbcl,iWeek,5));
assetHedgeContributionPctPoint(3)=assetPayoffPct(3)* ...
    (highWeightPct(3)-lowWeightPct(3))/100;
T=table(rowLabel,cellName,yearWeek,hedgeReturnPct,assetID,assetPayoffPct, ...
    lowWeightPct,highWeightPct,assetHedgeContributionPctPoint);
writetable(T,fullfile(outDir,'extreme_week_attribution.csv'));

trimCount=[0;1;3;5]; finiteWeeks=repmat(sum(isfinite(R.M2_D0.vHedge)),4,1);
trimmedMeanPct=NaN(4,1); x=sort(R.M2_D0.vHedge(isfinite(R.M2_D0.vHedge)));
for i=1:4
    k=trimCount(i); trimmedMeanPct(i)=100*mean(x(1+k:end-k));
end
T=table(trimCount,finiteWeeks,trimmedMeanPct);
writetable(T,fullfile(outDir,'M2_D0_symmetric_tail_trim_sensitivity.csv'));

fprintf('ABLATION_DIAGNOSTICS_OK out=%s\n',outDir);
end

function r=iLoadBase(path,needsPayoff)
assert(isfile(path),'Missing CTREND base: %s',path);
s=load(path);
required={'cResults','mYhat','vDates','vAssetID'};
assert(all(isfield(s,required)),'Incomplete CTREND base: %s',path);
r=struct(); r.vDates=double(s.vDates(:)); r.vAssetID=double(s.vAssetID(:));
r.vHedge=double(s.cResults.VW.mPortRet(end,:))';
r.mWts=double(s.cResults.VW.mWts); r.mYhat=double(s.mYhat);
assert(size(r.mYhat,1)==numel(r.vAssetID) && ...
    size(r.mYhat,2)==numel(r.vDates),'Base dimensions disagree');
if needsPayoff
    assert(isfield(s,'mRetPnlOOS'),'M1 base lacks endpoint payoff');
    r.mPayoff=double(s.mRetPnlOOS);
end
end

function p=iLoadM2Payoff(path,r)
assert(isfile(path),'Missing M2 weekly input: %s',path);
s=load(path,'rData','rMetaData');
assert(isfield(s.rData,'mReturnsM2Raw'),'Missing M2 raw return layer');
l=s.rData.yrmoda>=201416 & s.rData.yrmoda<=202222;
dates=double(s.rData.yrmoda(l)); ids=double(s.rMetaData.vID(:));
p0=double(s.rData.mReturnsM2Raw(l,:))';
[ir,id]=iAlignDates(r.vDates,dates);
[ar,ad]=iAlignAssets(r.vAssetID,ids);
assert(numel(ir)==numel(r.vDates)&&numel(ar)==numel(r.vAssetID), ...
    'M2 payoff input does not cover the CTREND base');
p=NaN(numel(r.vAssetID),numel(r.vDates)); p(ar,ir)=p0(ad,id);
end

function p=iLoadM1Payoff(path,r)
assert(isfile(path),'Missing M1 weekly input: %s',path);
s=load(path,'rData','rMetaData');
assert(isfield(s.rData,'mPnlReturns'),'Missing M1 endpoint P&L layer');
l=s.rData.yrmoda>=201416 & s.rData.yrmoda<=202222;
dates=double(s.rData.yrmoda(l)); ids=double(s.rMetaData.vID(:));
p0=double(s.rData.mPnlReturns(l,:))';
[ir,id]=iAlignDates(r.vDates,dates);
[ar,ad]=iAlignAssets(r.vAssetID,ids);
assert(numel(ir)==numel(r.vDates)&&numel(ar)==numel(r.vAssetID), ...
    'M1 payoff input does not cover the CTREND base');
p=NaN(numel(r.vAssetID),numel(r.vDates)); p(ar,ir)=p0(ad,id);
end

function [ia,ib]=iAlignDates(a,b)
[~,ia,ib]=intersect(double(a(:)),double(b(:)),'stable');
assert(~isempty(ia),'No common dates');
end

function [ia,ib]=iAlignAssets(a,b)
[~,ia,ib]=intersect(double(a(:)),double(b(:)),'stable');
assert(~isempty(ia),'No common assets');
end

function [v,ia,ib,ic]=intersect3(a,b,c)
[ab,ia0,ib0]=intersect(double(a(:)),double(b(:)),'stable');
[v,iab,ic]=intersect(ab,double(c(:)),'stable');
ia=ia0(iab); ib=ib0(iab);
end

function j=iJaccard(a,b)
ha=isfinite(a)&a~=0; hb=isfinite(b)&b~=0; u=ha|hb;
if ~any(u), j=NaN; else, j=sum(ha&hb)/sum(u); end
end

function h=iHedgeFromWeightsPayoff(W,P)
low=iLeg(W(:,:,1),P); high=iLeg(W(:,:,5),P); h=high-low;
end

function v=iLeg(W,P)
h=isfinite(W)&W~=0; n=sum(h,1); missing=any(h&~isfinite(P),1);
X=zeros(size(P)); X(h)=W(h).*P(h);
v=sum(X,1)'; v(n==0|missing)=NaN;
end

function iAssertReturnMatch(a,b,label)
l=isfinite(a)&isfinite(b);
assert(all(isfinite(a)==isfinite(b)), '%s finite support mismatch',label);
assert(max(abs(a(l)-b(l)),[],'omitnan')<1e-10,'%s value mismatch',label);
end

function [row,cellName,date,hedge,id,payoff,wl,wh,contribution]= ...
    iExtremeRow(row,cellName,r,t)
date=r.vDates(t); hedge=100*r.vHedge(t);
wl=iFiniteWeightVector(r.mWts(:,t,1));
wh=iFiniteWeightVector(r.mWts(:,t,5));
c=(wh-wl).*r.mPayoff(:,t);
[~,a]=max(abs(c),[],'omitnan');
id=r.vAssetID(a); payoff=100*r.mPayoff(a,t);
wl=100*wl(a); wh=100*wh(a); contribution=100*c(a);
end

function w=iFiniteWeightVector(w)
w=double(w); w(~isfinite(w))=0;
end

function w=iFiniteWeight(w)
if ~isfinite(w), w=0; end
end
