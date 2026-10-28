function recompute_original_delay_weekly(sRunRoot,sMethod,sPreprocess,sOutputDir)
% CTREND_REVISIT_FILE_PURPOSE: Compare the published fourth-output delay with its R-squared correction on an accepted M0/M2 parent.
% This deliberately keeps each parent's other data and market-return rules.
% It reads frozen b01/b02 inputs, verifies the original weekly delay, and
% writes only a separate corrected characteristic, never parent results.

arguments
    sRunRoot (1,:) char
    sMethod (1,:) char {mustBeMember(sMethod,{'M0','M2'})}
    sPreprocess (1,:) char {mustBeMember(sPreprocess,{'P0','P1'})}
    sOutputDir (1,:) char
end
if strcmp(sMethod,'M0')
    sRuntime = fullfile(sRunRoot,'runtime','cttrend_old_pipeline');
else
    sRuntime = fullfile(sRunRoot,'runtime','cttrend_lookahead_only_pipeline');
end
addpath(fullfile(sRuntime,'Utils'));
sData = fullfile(sRunRoot,'data');
if ~isfolder(sData), sData = fullfile(sRunRoot,'data.staging'); end
assert(isfile(fullfile(sRunRoot,'RUN_COMPLETE')) && ...
    isfile(fullfile(sData,'b0DataOLHC.mat')) && ...
    isfile(fullfile(sData,'bCharacteristicsOLHC_Combo1.mat')), ...
    'A complete, accepted M0/M2 parent is required');
if ~isfolder(sOutputDir), mkdir(sOutputDir); end
b0 = load(fullfile(sData,'b0DataOLHC.mat'), ...
    'mReturns','mClose','mME','mVolume','mLow','mHigh','mOpen','yrmoda');
weekly = load(fullfile(sData,'bCharacteristicsOLHC_Combo1.mat'), ...
    'rData','rChars','rMetaData');

% Reproduce the original baseline data setting: TRUNC at the 0.5% tails,
% then remove the changed candle before the original market regression.
mReturns = fTruncate(b0.mReturns,0.005,1,2);
mClose = b0.mClose;
mClose(mReturns ~= b0.mReturns) = NaN;
[~,mME,mVolume,mClose] = fEnsureAllObs( ...
    b0.mME,b0.mVolume,mClose,b0.mLow,b0.mHigh,b0.mOpen);
% P0 retains the original zero-to-missing rule. P1 preserves an explicit
% zero introduced by unified preprocessing and only screens tiny positives.
if strcmp(sPreprocess,'P0')
    mVolume(mVolume <= 1e-6) = NaN;
else
    mVolume(mVolume > 0 & mVolume <= 1e-6) = NaN;
end
iAssets = size(mReturns,2);
mMELag = [NaN(1,iAssets);mME(1:end-1,:)];
mWts = mMELag ./ sum(mMELag,2,'omitmissing');
vMarket = sum(mReturns.*mWts,2,'omitnan');
vMarket(all(isnan(mWts),2)) = NaN;
clear mMELag mWts

c = characteristics(mReturns,mME,mVolume,mClose,vMarket);
[~,~,~,~,mBaseR2] = c.fAlphaBetaSigma(vMarket,365,0,250);
mMarketLag = lagmatrix(vMarket,[0,1,2]);
[~,~,~,mExpandedSkew,mExpandedR2] = ...
    c.fAlphaBetaSigma(mMarketLag,365,0,250);
clear c mReturns mME mVolume mClose vMarket mMarketLag
mOldDaily = 1 - mBaseR2./mExpandedSkew;
mNewDaily = NaN(size(mBaseR2));
lValid = isfinite(mBaseR2) & isfinite(mExpandedR2) & mExpandedR2 > 0;
mNewDaily(lValid) = 1 - mBaseR2(lValid)./mExpandedR2(lValid);
clear mBaseR2 mExpandedSkew mExpandedR2
[mOldWeek,vDates] = fResampleLiuEtAl(mOldDaily,b0.yrmoda, ...
    'sMethod','last','iMinNumObs',1);
mCorrectedWeek = fResampleLiuEtAl(mNewDaily,b0.yrmoda, ...
    'sMethod','last','iMinNumObs',1);
assert(isequal(vDates(:),weekly.rData.yrmoda(:)) && ...
    isequal(size(mOldWeek),size(weekly.rChars.delay)), ...
    'Old-delay calendar differs from the accepted weekly input');
lOldFinite = isfinite(mOldWeek);
lSavedFinite = isfinite(weekly.rChars.delay);
dOldError = max(abs(mOldWeek(lOldFinite)- ...
    weekly.rChars.delay(lSavedFinite)),[],'omitmissing');
assert(isequal(lOldFinite,lSavedFinite) && dOldError < 1e-8, ...
    'The accepted original delay could not be reproduced');
vAssetID = weekly.rMetaData.vID(:);
save(fullfile(sOutputDir,'delay_characteristic_weekly.mat'), ...
    'mCorrectedWeek','vDates','vAssetID','dOldError','-v7.3');
fprintf('ORIGINAL_DELAY_WEEKLY_CORRECTION_OK method=%s run=%s old_max_error=%.3g\n', ...
    sMethod,sRunRoot,dOldError);
end
