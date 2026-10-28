function recompute_m1_delay_appendix_row(sRunRoot,sCorrectionDir)
% CTREND_REVISIT_FILE_PURPOSE: Derive the complete corrected delay appendix row from a frozen M1 weekly checkpoint.
% This performs one weekly characteristic sort, not b02 or b09. The saved
% legacy hedge is reproduced first; all corrected values remain separate
% from the accepted parent result tree.

arguments
    sRunRoot (1,:) char
    sCorrectionDir (1,:) char
end
sRepo = fileparts(fileparts(mfilename('fullpath')));
addpath(fullfile(sRepo,'engines','M1','base','Utils'));
sData = fullfile(sRunRoot,'data');
sResults = fullfile(sRunRoot,'results');
if ~isfolder(sResults)
    sResults = fullfile(sRunRoot,'results.staging');
end
assert(isfile(fullfile(sRunRoot,'RUN_COMPLETE')) && ...
    isfile(fullfile(sCorrectionDir,'delay_characteristic_weekly.mat')), ...
    'Accepted parent and independently corrected delay are required');
weekly = load(fullfile(sData,'bCharacteristicsOLHC_Combo1.mat'), ...
    'rData','rChars','rMetaData');
fixed = load(fullfile(sCorrectionDir,'delay_characteristic_weekly.mat'), ...
    'mCorrectedWeek','vDates','vAssetID');
vDates = weekly.rData.yrmoda(:);
assert(isequal(vDates,fixed.vDates(:)) && ...
    isequal(weekly.rMetaData.vID(:),fixed.vAssetID(:)) && ...
    isequal(size(weekly.rChars.delay),size(fixed.mCorrectedWeek)), ...
    'Corrected delay and accepted weekly input differ in calendar or asset identity');
lSample = vDates >= 201416 & vDates <= 202222;
vSampleDates = vDates(lSample);
mME = weekly.rData.mME;
mPrice = weekly.rData.mClose;
mMELag = [NaN(1,size(mME,2));mME(1:end-1,:)];
mPriceLag = [NaN(1,size(mPrice,2));mPrice(1:end-1,:)];
lRemove = ~isfinite(mMELag) | ~isfinite(mPriceLag) | ...
    mMELag == 0 | mMELag < 1e6 | mPriceLag < 0 | ...
    logical(weekly.rMetaData.lIsStable(:)');
mMELag(lRemove) = NaN;
rOptions = struct('sFreq','weekly','lHedgeOnly',false, ...
    'iMinNumCS',25,'iMinNumAssets',5,'lEnsureAllObs',true, ...
    'cVarNames',{{'delay'}});
[rOptions,~,~] = fAttachEconomicLedgerOptions(rOptions,sData, ...
    weekly.rData,fixed.vAssetID(:),vSampleDates,'ordinary');
mPayoff = weekly.rData.mPnlReturns';
mOldLag = [NaN(1,size(mME,2));weekly.rChars.delay(1:end-1,:)]';
mNewLag = [NaN(1,size(mME,2));fixed.mCorrectedWeek(1:end-1,:)]';
vQuantiles = 0:0.2:1;
rOld = fSingleSortMulti(mOldLag(:,lSample),mPayoff(:,lSample), ...
    vQuantiles,[],mMELag(lSample,:)',rOptions);
rNew = fSingleSortMulti(mNewLag(:,lSample),mPayoff(:,lSample), ...
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
dError = max(abs(mOld(:,end)-vSaved),[],'omitmissing');
assert(isequal(isfinite(mOld(:,end)),isfinite(vSaved)) && ...
    dError < 1e-10,'Legacy delay hedge did not reproduce');

% MATLAB's ttest and regression helper are the same estimators as b04.
[~,~,~,oldStats] = ttest(mOld);
[~,~,~,newStats] = ttest(mNew);
cPorts = {'L','2','3','4','H','H-L'}';
tPorts = table(cPorts,mean(mOld,1,'omitmissing')'*100, ...
    mean(mNew,1,'omitmissing')'*100,oldStats.tstat(:), ...
    newStats.tstat(:),'VariableNames', ...
    {'portfolio','legacy_mean_pct','corrected_mean_pct', ...
    'legacy_t','corrected_t'});
writetable(tPorts,fullfile(sCorrectionDir,'delay_appendix_portfolios.csv'));
factors = load(fullfile(sData,'LTW_3factor.mat'),'vDatesLiu','mLTW');
mLTW = fAlignByDate(factors.vDatesLiu,factors.mLTW, ...
    vSampleDates,'LTW',0.95);
cNames = {'CCAPM';'LTW'};
vOldAlpha = NaN(2,1); vNewAlpha = NaN(2,1);
vOldAlphaT = NaN(2,1); vNewAlphaT = NaN(2,1);
for iModel = 1:2
    if iModel == 1, mX = mLTW(:,1); else, mX = mLTW; end
    [vBeta,vT] = fRegstatsTstatSafe(mOld(:,end),mX);
    vOldAlpha(iModel) = vBeta(1)*100;
    vOldAlphaT(iModel) = vT(1);
    [vBeta,vT] = fRegstatsTstatSafe(mNew(:,end),mX);
    vNewAlpha(iModel) = vBeta(1)*100;
    vNewAlphaT(iModel) = vT(1);
end
tAlpha = table(cNames,vOldAlpha,vNewAlpha,vOldAlphaT,vNewAlphaT, ...
    'VariableNames',{'benchmark','legacy_alpha_pct', ...
    'corrected_alpha_pct','legacy_alpha_t','corrected_alpha_t'});
writetable(tAlpha,fullfile(sCorrectionDir,'delay_appendix_alphas.csv'));
fprintf('M1_DELAY_APPENDIX_ROW_OK run=%s old_hedge_max_error=%.3g\n', ...
    sRunRoot,dError);
end
