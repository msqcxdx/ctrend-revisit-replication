function test_unified_missing_and_exit_calendar(sRoot)
% CTREND_REVISIT_FILE_PURPOSE: Verify causal OHLC fill, zero volume fill, and the frozen no-external mechanical exit calendar.
% The fixture distinguishes leading, internal, and post-terminal gaps. OHLC
% may use only an earlier close, invalid volume becomes zero, and no price may
% be manufactured after the final observed close. The derived exit calendar
% is then frozen and re-read to prove deterministic, source-free behavior.

arguments
    sRoot {mustBeTextScalar}
end
sRoot = char(sRoot);
sUtils = fullfile(sRoot,'engines','M0','base','Utils');
addpath(sUtils);
rPathCleanup = onCleanup(@() rmpath(sUtils));

vDates = (20200101:20200106)';
vAssetID = [11;22;33];
mClose = [NaN NaN 20; 10 NaN 21; NaN NaN NaN; 12 NaN 23; NaN NaN 24; NaN NaN 25];
mOpen = NaN(size(mClose));
mHigh = NaN(size(mClose));
mLow = NaN(size(mClose));
mVolume = [NaN 1 2; 5 -1 Inf; NaN NaN 0; 7 8 9; NaN 10 11; NaN 12 13];

% Apply the common P1 preprocessing once to all synchronized daily panels.
[mOpenOut,mHighOut,mLowOut,mCloseOut,mVolumeOut,rFill,lAux] = ...
    fApplyUnifiedMissingDataPreprocessing( ...
    mOpen,mHigh,mLow,mClose,mVolume,vDates,vAssetID);

% Asset 11: leading prices remain missing; the internal date uses the
% strictly earlier close; the post-terminal tail is never manufactured.
assert(isnan(mCloseOut(1,1)) && mCloseOut(3,1) == 10 && ...
    isnan(mCloseOut(5,1)) && isnan(mCloseOut(6,1)));
assert(isnan(mOpenOut(2,1)) && mOpenOut(3,1) == 10 && ...
    mHighOut(4,1) == 10 && mLowOut(4,1) == 10);
assert(lAux(3,1) && lAux(4,1) && ~lAux(5,1));

% An asset without any original close cannot acquire a price.  Missing,
% infinite, and negative volume/turnover become zero everywhere.
assert(all(isnan(mCloseOut(:,2))));
assert(all(isfinite(mVolumeOut),'all') && all(mVolumeOut >= 0,'all'));
assert(mVolumeOut(1,1) == 0 && mVolumeOut(2,2) == 0 && ...
    mVolumeOut(2,3) == 0 && mVolumeOut(5,1) == 0);
assert(rFill.iCloseFilled == 2 && rFill.iPostTerminalPriceCellsFilled == 0 && ...
    ~rFill.lUsesExternalSource && rFill.iImputedAuxiliaryRangeConflicts >= 1);

sTemp = tempname;
mkdir(sTemp);
rTempCleanup = onCleanup(@() rmdir(sTemp,'s'));
sCalendar = fullfile(sTemp,'mechanical_exit_calendar.csv');
[tCalendar,rCalendar] = fBuildAndFreezeMechanicalExitCalendar( ...
    mCloseOut,vDates,vAssetID,["A";"B";"C"],sCalendar);
assert(isfile(sCalendar) && height(tCalendar) == 3);
assert(tCalendar.mechanical_exit(1) && ...
    tCalendar.last_tradable_index(1) == 4 && ...
    tCalendar.last_tradable_price(1) == 12);
assert(~tCalendar.mechanical_exit(2) && ...
    ~tCalendar.right_censored(2) && ...
    tCalendar.schedule_source(2) == "no_positive_close");
assert(tCalendar.right_censored(3) && ...
    tCalendar.last_tradable_index(3) == 6);
assert(rCalendar.iMechanicalExits == 1 && ...
    rCalendar.iRightCensored == 1 && ...
    rCalendar.iNoPositiveClose == 1 && ...
    ~rCalendar.lUsesExternalSource && ...
    strcmp(rCalendar.sSHA256,fFileSHA256(sCalendar)));

clear rTempCleanup rPathCleanup
fprintf('UNIFIED_MISSING_AND_EXIT_CALENDAR_TEST_OK\n');
end
