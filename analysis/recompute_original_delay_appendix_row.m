function recompute_original_delay_appendix_row(sRunRoot,sMethod,sCorrectionDir)
% CTREND_REVISIT_FILE_PURPOSE: Compare original-code and corrected-R-squared delay appendix rows for an accepted M0/M2 run.
% All sample filters, statistical returns, economic payoffs, and factor
% benchmarks except delay retain the selected method's published settings.

arguments
    sRunRoot (1,:) char
    sMethod (1,:) char {mustBeMember(sMethod,{'M0','M2'})}
    sCorrectionDir (1,:) char
end
if strcmp(sMethod,'M0')
    sRuntime = fullfile(sRunRoot,'runtime','ctrend_old_pipeline');
else
    sRuntime = fullfile(sRunRoot,'runtime','ctrend_lookahead_only_pipeline');
end
addpath(fullfile(sRuntime,'Utils'));
sData = fullfile(sRunRoot,'data');
if ~isfolder(sData), sData = fullfile(sRunRoot,'data.staging'); end
sResults = fullfile(sRunRoot,'results');
if ~isfolder(sResults), sResults = fullfile(sRunRoot,'results.staging'); end
assert(isfile(fullfile(sRunRoot,'RUN_COMPLETE')) && ...
    isfile(fullfile(sCorrectionDir,'delay_characteristic_weekly.mat')), ...
    'Accepted parent and corrected delay are required');
weekly = load(fullfile(sData,'bCharacteristicsOLHC_Combo1.mat'), ...
    'rData','rChars','rMetaData');
fixed = load(fullfile(sCorrectionDir,'delay_characteristic_weekly.mat'), ...
    'mCorrectedWeek','vDates','vAssetID');
vDates = weekly.rData.yrmoda(:);
assert(isequal(vDates,fixed.vDates(:)) && ...
    isequal(weekly.rMetaData.vID(:),fixed.vAssetID(:)) && ...
    isequal(size(weekly.rChars.delay),size(fixed.mCorrectedWeek)), ...
    'Delay corrections are not aligned to the parent weekly input');
lSample = vDates >= 201416 & vDates <= 202222;
vSampleDates = vDates(lSample);
iAssets = size(weekly.rData.mME,2);
mME = weekly.rData.mME;
mPrice = weekly.rData.mClose;
rOptions = struct('sFreq','weekly','lHedgeOnly',false, ...
    'iMinNumCS',25,'iMinNumAssets',5,'lEnsureAllObs',true, ...
    'cVarNames',{{'delay'}});
if strcmp(sMethod,'M0')
    % The original b04 screens the current week's return and cap before
    % lagging cap; this is preserved only for the M0 comparison.
    mPayoff = weekly.rData.mReturns;
    lRemove = mME == 0 | mME < 1e6 | mPrice < 0 | ...
        logical(weekly.rMetaData.lIsStable(:)');
    mPayoff(lRemove) = NaN;
    mME(lRemove) = NaN;
    mMELag = [NaN(1,iAssets);mME(1:end-1,:)];
else
    % M2 screens formation-date cap/price and retains its separate
    % endpoint/reinvestment economic payoff accounting.
    mPayoff = weekly.rData.mPnlReturnsM2;
    mMELag = [NaN(1,iAssets);mME(1:end-1,:)];
    mPriceLag = [NaN(1,iAssets);mPrice(1:end-1,:)];
    lRemove = isnan(mMELag) | isnan(mPriceLag) | ...
        mMELag == 0 | mMELag < 1e6 | mPriceLag < 0 | ...
        logical(weekly.rMetaData.lIsStable(:)');
    mPayoff(lRemove) = NaN;
    mMELag(lRemove) = NaN;
    [rOptions,~,~] = fAttachEconomicLedgerOptions(rOptions,sData, ...
        weekly.rData,fixed.vAssetID(:),vSampleDates,'ordinary');
end
mOldLag = [NaN(1,iAssets);weekly.rChars.delay(1:end-1,:)]';
mNewLag = [NaN(1,iAssets);fixed.mCorrectedWeek(1:end-1,:)]';
vQuantiles = 0:0.2:1;
rOld = fSingleSortMulti(mOldLag(:,lSample),mPayoff(lSample,:)', ...
    vQuantiles,[],mMELag(lSample,:)',rOptions);
rNew = fSingleSortMulti(mNewLag(:,lSample),mPayoff(lSample,:)', ...
    vQuantiles,[],mMELag(lSample,:)',rOptions);
mOld = rOld.VW.mPortRet';
mNew = rNew.VW.mPortRet';
mOld(1:52,:) = NaN;
mNew(1:52,:) = NaN;
saved = load(fullfile(sResults,'HedgePorts.mat'), ...
    'mHedgePort','cCharNames','vDates');
iDelay = find(strcmp(saved.cCharNames,'delay'));
assert(isscalar(iDelay) && isequal(saved.vDates(:),vSampleDates(:)), ...
    'Saved delay hedge identity differs');
vSaved = saved.mHedgePort(:,iDelay);
dOldError = max(abs(mOld(:,end)-vSaved),[],'omitmissing');
assert(isequal(isfinite(mOld(:,end)),isfinite(vSaved)) && ...
    dOldError < 1e-10,'Original delay hedge did not reproduce');

[~,~,~,oldStats] = ttest(mOld);
[~,~,~,newStats] = ttest(mNew);
cPorts = {'L','2','3','4','H','H-L'}';
tPorts = table(cPorts,mean(mOld,1,'omitmissing')'*100, ...
    mean(mNew,1,'omitmissing')'*100,oldStats.tstat(:), ...
    newStats.tstat(:),'VariableNames', ...
    {'portfolio','legacy_mean_pct','corrected_mean_pct', ...
    'legacy_t','corrected_t'});
writetable(tPorts,fullfile(sCorrectionDir,'delay_appendix_portfolios.csv'));
tHedge = table(vSampleDates,vSaved,mNew(:,end), ...
    'VariableNames',{'year_week','legacy_delay_hedge', ...
    'corrected_delay_hedge'});
writetable(tHedge,fullfile(sCorrectionDir,'delay_hedge_weekly.csv'));

factors = load(fullfile(sData,'LTW_3factor.mat'),'vDatesLiu','mLTW');
lFactorSample = factors.vDatesLiu >= 201416 & factors.vDatesLiu <= 202222;
mLTW = factors.mLTW(lFactorSample,:);
assert(size(mLTW,1) == length(vSampleDates), ...
    'Original b04 LTW factor calendar length differs');
vMktRet = weekly.rData.vMktRet(lSample);
cNames = {'CCAPM';'LTW'};
vOldAlpha = NaN(2,1); vNewAlpha = NaN(2,1);
vOldAlphaT = NaN(2,1); vNewAlphaT = NaN(2,1);
for iModel = 1:2
    if iModel == 1, mX = vMktRet; else, mX = mLTW; end
    rReg = regstats(mOld(:,end),mX,'linear',{'tstat'});
    vOldAlpha(iModel) = rReg.tstat.beta(1)*100;
    vOldAlphaT(iModel) = rReg.tstat.t(1);
    rReg = regstats(mNew(:,end),mX,'linear',{'tstat'});
    vNewAlpha(iModel) = rReg.tstat.beta(1)*100;
    vNewAlphaT(iModel) = rReg.tstat.t(1);
end
tAlpha = table(cNames,vOldAlpha,vNewAlpha,vOldAlphaT,vNewAlphaT, ...
    'VariableNames',{'benchmark','legacy_alpha_pct', ...
    'corrected_alpha_pct','legacy_alpha_t','corrected_alpha_t'});
writetable(tAlpha,fullfile(sCorrectionDir,'delay_appendix_alphas.csv'));
fprintf('ORIGINAL_DELAY_APPENDIX_ROW_OK method=%s run=%s old_max_error=%.3g\n', ...
    sMethod,sRunRoot,dOldError);
end
