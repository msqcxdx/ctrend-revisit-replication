function test_compare_nine_methods_common_weeks()
% CTREND_REVISIT_FILE_PURPOSE: Deterministically test nine-way, by-axis, and pairwise finite-week intersections.
% Synthetic deterministic test of nine-way and pairwise support intersections.
% The fixture gives five methods distinct missing weeks and leaves four fully
% observed. Expected masks are derived from the fixture, so the test detects
% accidental zero filling, positional alignment, or method-specific sampling.
sHere = fileparts(mfilename('fullpath'));
sAnalysis = fileparts(sHere);
sOldPath = path;
addpath(sAnalysis);
rPathCleanup = onCleanup(@() path(sOldPath)); %#ok<NASGU>
sRoot = string(tempname);
mkdir(sRoot);
rCleanup = onCleanup(@() rmdir(sRoot,'s')); %#ok<NASGU>
cFiles = strings(1,9);
vDates = (202001:202006)';
for iIdx = 1:9
    vRet = (1:6)'/100+iIdx/1000;
    if iIdx <= 5
        vRet(iIdx) = NaN;
    end
    cResults = struct();
    cResults.VW.mPortRet = [zeros(1,6);vRet'];
    cFiles(iIdx) = fullfile(sRoot,sprintf('cell_%d.mat',iIdx));
    save(cFiles(iIdx),'vDates','cResults');
end
sOut = fullfile(sRoot,'out');
r = compare_nine_methods_common_weeks(cFiles,sOut);
assert(~isfield(r,'cBaselineFiles') && isequal(r.cInputRoles, ...
       ["M0_D0","M0_D1","M0_D2","M2_D0","M2_D1","M2_D2", ...
        "M1_D0","M1_D1","M1_D2"]), ...
    'Audit must retain input roles without leaking machine-specific paths');
assert(nnz(r.lAllNineCommon)==1 && r.vUnionDates(r.lAllNineCommon)==202006, ...
    'All-nine support must be the one deliberately common fixture week');
assert(all(r.tAllNineCommon.n==1), ...
    'Every all-nine summary row must use exactly the same one-week support');
assert(all(r.tAllNineCommon.start_year_week==202006) && ...
       all(r.tAllNineCommon.end_year_week==202006), ...
    'Common-week summary must report calendar labels, not union-row indices');
tWeekly = readtable(fullfile(sOut,'nine_method_weekly_returns.csv'));
assert(nnz(tWeekly.all_nine_common)==1 && ...
       tWeekly.year_week(tWeekly.all_nine_common==1)==202006, ...
    'Written weekly audit must preserve the exact all-nine support mask');
assert(isfile(fullfile(sOut,'nine_method_pairwise_common_week_summary.csv')) && ...
       isfile(fullfile(sOut,'nine_method_by_data_axis_common_summary.csv')) && ...
       isfile(fullfile(sOut,'nine_method_by_method_common_summary.csv')) && ...
       isfile(fullfile(sOut,'nine_method_common_week_audit.mat')), ...
    'Common-week comparison must write grouped, pairwise, and MAT audit outputs');
tByD = readtable(fullfile(sOut, ...
    'nine_method_by_data_axis_common_summary.csv'));
tByM = readtable(fullfile(sOut, ...
    'nine_method_by_method_common_summary.csv'));
assert(height(tByD)==9 && height(tByM)==9, ...
    'Each grouped comparison must contain all nine method rows');
iAssertEqualSupportInsideGroup(tByD);
iAssertEqualSupportInsideGroup(tByM);

% Exercise the numbered post-b18 MATLAB entry point on the same fixtures.
% This proves b19 delegates to the tested path-free implementation instead of
% introducing a second numerical definition.
cLabels = ["M0_D0","M0_D1","M0_D2", ...
    "M2_D0","M2_D1","M2_D2", ...
    "M1_D0","M1_D1","M1_D2"];
for iIdx = 1:numel(cLabels)
    setenv("CTREND_COMMON_WEEK_"+cLabels(iIdx),cFiles(iIdx));
end
sOutB19 = fullfile(sRoot,'b19');
setenv('CTREND_COMMON_WEEK_OUTPUT_DIR',sOutB19);
addpath(fullfile(fileparts(sAnalysis),'postprocessing'));
b19CommonWeekRobustness;
assert(isfile(fullfile(sOutB19,'nine_method_common_week_audit.mat')) && ...
       isequaln(readtable(fullfile(sOutB19, ...
       'nine_method_all_common_summary.csv')), ...
       readtable(fullfile(sOut,'nine_method_all_common_summary.csv'))), ...
    'Numbered b19 entry point must reproduce the core comparison exactly');
fprintf('TEST_COMPARE_NINE_METHODS_COMMON_WEEKS_OK\n');
end

function iAssertEqualSupportInsideGroup(tSummary)
cSupport = unique(string(tSummary.support));
assert(numel(cSupport)==3, ...
    'Grouped comparison must contain exactly three named intersections');
for iIdx = 1:numel(cSupport)
    lGroup = string(tSummary.support)==cSupport(iIdx);
    assert(nnz(lGroup)==3 && all(tSummary.n(lGroup)>0) && ...
           numel(unique(tSummary.n(lGroup)))==1, ...
        'All three rows in a grouped comparison must use one finite-week intersection');
end
end
