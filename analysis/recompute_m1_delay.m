function recompute_m1_delay(sRunRoot, sOutputDir)
% CTREND_REVISIT_FILE_PURPOSE: Rebuild only the M1 delay characteristic and its appendix sort from an accepted b01 parent.
% No parent DATA, results, or model forecast is edited. The old delay and
% b04 appendix hedge row must be reproduced before the correction is accepted.

arguments
    sRunRoot (1,:) char
    sOutputDir (1,:) char
end
sRepo = fileparts(fileparts(mfilename('fullpath')));
addpath(fullfile(sRepo,'engines','M1','base','Utils'));
sData = fullfile(sRunRoot,'data');
sResult = fullfile(sRunRoot,'results');
if ~isfolder(sResult)
    sResult = fullfile(sRunRoot,'results.staging');
end
assert(isfile(fullfile(sRunRoot,'RUN_COMPLETE')) && ...
    isfile(fullfile(sData,'b0DataOLHC.mat')) && ...
    isfile(fullfile(sData,'bCharacteristicsOLHC_Combo1.mat')) && ...
    isfile(fullfile(sResult,'HedgePorts.mat')), ...
    'A complete accepted M1 run is required');
if ~isfolder(sOutputDir), mkdir(sOutputDir); end

b0 = load(fullfile(sData,'b0DataOLHC.mat'), ...
    'mClose','mME','mVolume','rMetaData','yrmoda');
b0.mVolume(b0.mVolume > 0 & b0.mVolume <= 1e-6) = NaN;
[~,b0.mME,b0.mVolume,b0.mClose] = fEnsureAllObs( ...
    b0.mME,b0.mVolume,b0.mClose);
mReturns = [NaN(1,size(b0.mClose,2)); ...
    b0.mClose(2:end,:)./b0.mClose(1:end-1,:)-1];
mReturns(~isfinite(mReturns)) = NaN;
lFormation = isfinite(b0.mME) & b0.mME >= 1e6 & ...
    isfinite(b0.mClose) & isfinite(b0.mVolume) & ...
    ~logical(b0.rMetaData.lIsStable(:)');
mMarketME = b0.mME;
mMarketME(~lFormation) = NaN;
vMarket = fValueWeightedMarketReturnStrict(mReturns,mMarketME);
clear mMarketME lFormation

% The fifth output of both regressions is R-squared. Keeping the fourth
% expanded output solely for the old-result equality check proves that the
% correction changes the intended ordinal, not the daily market input.
c = characteristics(mReturns,b0.mME,b0.mVolume,b0.mClose,vMarket);
[~,~,~,~,mBaseR2] = c.fAlphaBetaSigma(vMarket,365,0,250);
mMarketLag = [vMarket,[NaN;vMarket(1:end-1)], ...
    [NaN(2,1);vMarket(1:end-2)]];
[~,~,~,mExpandedSkew,mExpandedR2] = ...
    c.fAlphaBetaSigma(mMarketLag,365,0,250);
clear c mReturns mMarketLag
mOld = NaN(size(mBaseR2));
lOld = isfinite(mBaseR2) & isfinite(mExpandedSkew) & mExpandedSkew > 0;
mOld(lOld) = 1-mBaseR2(lOld)./mExpandedSkew(lOld);
mCorrected = NaN(size(mBaseR2));
lCorrected = isfinite(mBaseR2) & isfinite(mExpandedR2) & mExpandedR2 > 0;
mCorrected(lCorrected) = 1-mBaseR2(lCorrected)./mExpandedR2(lCorrected);
clear mBaseR2 mExpandedSkew mExpandedR2
[mOldWeek,vDates] = fResampleLiuEtAl(mOld,b0.yrmoda, ...
    'sMethod','last','iMinNumObs',1);
mCorrectedWeek = fResampleLiuEtAl(mCorrected,b0.yrmoda, ...
    'sMethod','last','iMinNumObs',1);
clear b0 mOld mCorrected

weekly = load(fullfile(sData,'bCharacteristicsOLHC_Combo1.mat'), ...
    'rData','rChars','rMetaData');
assert(isequal(vDates(:),weekly.rData.yrmoda(:)) && ...
    isequal(size(mOldWeek),size(weekly.rChars.delay)), ...
    'Delay weekly axes differ from accepted b02');
lSameFinite = isequal(isfinite(mOldWeek),isfinite(weekly.rChars.delay));
dOldError = max(abs(mOldWeek-weekly.rChars.delay),[],'all','omitmissing');
assert(lSameFinite && dOldError < 1e-8, ...
    'The published fourth-output delay could not be reproduced');

% Recreate b04's delay-only baseline sort, first with the old vector to
% verify the saved HedgePorts row and then with fifth-output R-squared.
o = struct('sFreq','weekly','lHedgeOnly',false,'iMinNumCS',25, ...
    'iMinNumAssets',5,'lEnsureAllObs',true,'cVarNames',{{'delay'}});
lSample = vDates >= 201416 & vDates <= 202222;
vSampleDates = vDates(lSample);
vAssetID = weekly.rMetaData.vID(:);
[o,~,~] = fAttachEconomicLedgerOptions(o,sData,weekly.rData, ...
    vAssetID,vSampleDates,'ordinary');
mME = weekly.rData.mME;
mPrice = weekly.rData.mClose;
mMELag = [NaN(1,size(mME,2));mME(1:end-1,:)];
mPriceLag = [NaN(1,size(mPrice,2));mPrice(1:end-1,:)];
lRemove = ~isfinite(mMELag) | ~isfinite(mPriceLag) | ...
    mMELag == 0 | mMELag < 1e6 | mPriceLag < 0 | ...
    logical(weekly.rMetaData.lIsStable(:)');
mMELag(lRemove) = NaN;
mRetSort = weekly.rData.mPnlReturns';
vQuantiles = 0:0.2:1;
mOldLag = [NaN(1,size(mOldWeek,2));mOldWeek(1:end-1,:)]';
mNewLag = [NaN(1,size(mCorrectedWeek,2));mCorrectedWeek(1:end-1,:)]';
rOld = fSingleSortMulti(mOldLag(:,lSample),mRetSort(:,lSample), ...
    vQuantiles,[],mMELag(lSample,:)',o);
rNew = fSingleSortMulti(mNewLag(:,lSample),mRetSort(:,lSample), ...
    vQuantiles,[],mMELag(lSample,:)',o);
vOldHedge = rOld.VW.mPortRet(end,:)';
vNewHedge = rNew.VW.mPortRet(end,:)';
vOldHedge(1:52) = NaN;
vNewHedge(1:52) = NaN;
saved = load(fullfile(sResult,'HedgePorts.mat'),'mHedgePort','cCharNames','vDates');
iDelay = find(strcmp(saved.cCharNames,'delay'));
assert(isscalar(iDelay) && isequal(saved.vDates(:),vSampleDates(:)), ...
    'Saved appendix delay identity or calendar differs');
vSaved = saved.mHedgePort(:,iDelay);
dHedgeError = max(abs(vOldHedge-vSaved),[],'omitmissing');
assert(isequal(isfinite(vOldHedge),isfinite(vSaved)) && ...
    dHedgeError < 1e-10, 'Accepted appendix delay hedge cannot be reproduced');

tWeekly = table(vSampleDates(:),vSaved,vNewHedge, ...
    'VariableNames',{'year_week','legacy_delay_hedge','corrected_delay_hedge'});
writetable(tWeekly,fullfile(sOutputDir,'delay_hedge_weekly.csv'));
save(fullfile(sOutputDir,'delay_characteristic_weekly.mat'), ...
    'mCorrectedWeek','vDates','vAssetID','dOldError','dHedgeError','-v7.3');
fprintf(['M1_DELAY_CORRECTION_OK run=%s old_weekly_max_error=%.3g ' ...
    'old_hedge_max_error=%.3g changed_hedge_weeks=%d\n'], ...
    sRunRoot,dOldError,dHedgeError,nnz(isfinite(vSaved) & ...
    isfinite(vNewHedge) & abs(vSaved-vNewHedge)>1e-10));
end
