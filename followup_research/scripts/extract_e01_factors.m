function extract_e01_factors(sRunRoot,sOutputDir)
% Extract the two Table 3 / Table B.7 LTW definitions and the identical
% CTREND long-short payoff from one accepted M1 run. This function reads
% the accepted run and writes exclusively to sOutputDir.

arguments
    sRunRoot (1,:) char
    sOutputDir (1,:) char
end

sEngine = fullfile(sRunRoot,'runtime','ctrend_corrected_pipeline');
sDataPath = fullfile(sRunRoot,'data');
sBase = fullfile(sRunRoot,'results','CTREND','CTREND_Base.mat');
assert(isfile(fullfile(sRunRoot,'RUN_COMPLETE')),'Accepted run is incomplete');
assert(isfile(sBase),'Baseline CTREND result is missing');
assert(isfolder(sEngine),'Run-local M1 source is missing');
if ~isfolder(sOutputDir)
    mkdir(sOutputDir);
end
addpath(fullfile(sEngine,'Utils'));
% The archived provenance helpers fingerprint pwd, as in the original run.
sOriginalDir = pwd;
rRestoreDir = onCleanup(@() cd(sOriginalDir)); %#ok<NASGU>
cd(sEngine);

% These are the exact baseline choices in b06Table3_UnivariatePortfolioSorts.m.
rChoices = load(fullfile(sRunRoot,'DesignChoices.mat'),'tCombos');
tCombos = rChoices.tCombos;
iChoice = find(strcmpi(tCombos.cOutlierTreatment,'trunc') & ...
    tCombos.vThreshold == 0.005,1,'first');
assert(~isempty(iChoice),'Cannot locate the baseline b06 data choice');
iDataComb = tCombos.data_setting(iChoice);
sWeekly = fullfile(sDataPath, ...
    sprintf('bCharacteristicsOLHC_Combo%i.mat',iDataComb));
rWeekly = load(sWeekly);
sRuntimeFingerprint = fPipelineCodeFingerprint(sEngine);
fAssertWeeklyDataProvenance(rWeekly.sDataBuildID, ...
    rWeekly.rInputProvenance,rWeekly.sWeeklyCodeFingerprint, ...
    sRuntimeFingerprint);
rData = rWeekly.rData;
rMetaData = rWeekly.rMetaData;
rChars = rWeekly.rChars;

vDatesAll = rData.yrmoda(:);
mMEAll = rData.mME;
mCloseAll = rData.mClose;
mPnlAll = rData.mPnlReturns;
vMktPnlAll = rData.vMktPnl(:);
vRiskFreeAll = rData.vRiskFree(:);
vAssetID = rMetaData.vID(:);
assert(isequal(size(mMEAll),size(mPnlAll)) && ...
    numel(vDatesAll) == size(mPnlAll,1), ...
    'Baseline weekly input axes disagree');

% b06 lags formation information before restricting the research sample.
mME_L1 = [NaN(1,size(mMEAll,2));mMEAll(1:end-1,:)];
mClose_L1 = [NaN(1,size(mCloseAll,2));mCloseAll(1:end-1,:)];
mMom_L1 = [NaN(1,size(rChars.ret_3_0,2)); ...
    rChars.ret_3_0(1:end-1,:)];
lSample = vDatesAll >= 201416 & vDatesAll <= 202222;
vDates = vDatesAll(lSample);
mME_L1 = mME_L1(lSample,:);
mClose_L1 = mClose_L1(lSample,:);
mMom_L1 = mMom_L1(lSample,:) * 100;
mPnl = mPnlAll(lSample,:);
vMktPnl = vMktPnlAll(lSample);
vRiskFree = vRiskFreeAll(lSample);

lRemove = ~isfinite(mME_L1) | ~isfinite(mClose_L1) | ...
    mME_L1 == 0 | mME_L1 < 1e6 | mClose_L1 < 0;
lRemove = lRemove | rMetaData.lIsStable;
mME_L1(lRemove) = NaN;

rBase = load(sBase,'mYhat','mRetPnlOOS','cResults','vDates', ...
    'vAssetID','sCodeFingerprint','sDataBuildID');
fAssertCTRENDAlignment(rBase,vDates,vAssetID,numel(vAssetID), ...
    rWeekly.sDataBuildID);

rOptions = struct('sFreq','weekly','lHedgeOnly',false, ...
    'iMinNumCS',25,'iMinNumAssets',5,'lEnsureAllObs',true);
[rOptions,~,vLedgerWeekRow] = fAttachEconomicLedgerOptions( ...
    rOptions,[sDataPath filesep],rData,vAssetID,vDates,'ordinary');
mRetSort = mPnl';

% The alternative-factor branch of b06: project-universe CMKT, CSMB, CMOM.
rSize = fSingleSortMulti(mME_L1',mRetSort,[0 0.3 0.7 1], ...
    [],mME_L1',rOptions);
vCSMB = -rSize.VW.mPortRet(end,:)';
rMom = fDepDoubleSort(mME_L1',mMom_L1',mRetSort,[],mME_L1', ...
    'vPercentileA',0:0.5:1,'vPercentileB',[0 0.3 0.7 1], ...
    'rReinvestmentLedger',rOptions.rReinvestmentLedger, ...
    'vLedgerWeekRow',vLedgerWeekRow,'sPayoffTiming','ordinary');
vCMOM = 0.5 * (rMom.VW.cPortRets{1,end-1} + ...
    rMom.VW.cPortRets{2,end-1}) - ...
    0.5 * (rMom.VW.cPortRets{1,1} + rMom.VW.cPortRets{2,1});
mOwn = [vMktPnl-vRiskFree,vCSMB,vCMOM(:)];

% The main-text branch uses the unchanged Liu-Tsyvinski-Wu workbook.
rExternal = load(fullfile(sDataPath,'LTW_3factor.mat'), ...
    'mLTW','vDatesLiu');
mExternal = fAlignByDate(rExternal.vDatesLiu,rExternal.mLTW, ...
    vDates,'LTW',0.95);

% b06 uses the same CTREND sort before either benchmark regression.
rPort = fSingleSortMulti(rBase.mYhat,rBase.mRetPnlOOS, ...
    0:0.2:1,[],mME_L1',rOptions);
vCTREND = rPort.VW.mPortRet(end,:)';
assert(numel(vCTREND) == numel(vDates) && ...
    isequal(size(mOwn),size(mExternal)), ...
    'Benchmark and CTREND weekly axes disagree');

% A direct check against the two previously published b06 alpha rows.
[vBetaExternal,vTExternal] = fRegstatsTstatSafe(vCTREND,mExternal);
[vBetaOwn,vTOwn] = fRegstatsTstatSafe(vCTREND,mOwn);

sMat = fullfile(sOutputDir,'e01_weekly_factors.mat');
save(sMat,'vDates','vCTREND','mExternal','mOwn','vRiskFree', ...
    'vBetaExternal','vTExternal','vBetaOwn','vTOwn', ...
    'sRunRoot','iDataComb','-v7');
tOut = table(vDates,vCTREND,mExternal(:,1),mExternal(:,2), ...
    mExternal(:,3),mOwn(:,1),mOwn(:,2),mOwn(:,3), ...
    'VariableNames',{'week_key','ctrend','external_cmkt', ...
    'external_csize','external_cmom','own_cmkt','own_csize', ...
    'own_cmom'});
writetable(tOut,fullfile(sOutputDir,'e01_weekly_factors.csv'));
fprintf(['E01_EXTRACT_OK run=%s weeks=%i external_alpha_pct=%.8f ' ...
    'external_t=%.8f own_alpha_pct=%.8f own_t=%.8f\n'], ...
    sRunRoot,numel(vDates),100*vBetaExternal(1),vTExternal(1), ...
    100*vBetaOwn(1),vTOwn(1));
end
