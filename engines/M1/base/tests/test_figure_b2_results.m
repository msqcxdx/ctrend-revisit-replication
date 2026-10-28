function test_figure_b2_results()
% Result-level invariant for the disclosed zero-gap cumulative-return figure.

sTestDir = fileparts(mfilename('fullpath'));
sCodeDir = strtrim(getenv('CTREND_RESULT_CODE_DIR'));
if isempty(sCodeDir)
    sCodeDir = fileparts(sTestDir);
end
assert(exist(sCodeDir,'dir') == 7, ...
    'Figure B.2 result-test code directory does not exist');

% Rebuild the four plotted factor paths from this run's own scientific
% inputs.  Counts such as the number of common-support gaps are properties
% of a particular D0/D1/D2 sample and therefore must never be hard-coded
% from an earlier run.
rDesign = load(fullfile(sCodeDir,'DesignChoices.mat'),'tCombos');
tCombos = rDesign.tCombos;
lBaselineData = strcmpi(tCombos.cOutlierTreatment,'trunc') & ...
    tCombos.vThreshold == 0.005;
iDataSetting = unique(tCombos.data_setting(lBaselineData));
assert(isscalar(iDataSetting), ...
    'Figure B.2 baseline must resolve to one weekly-data setting');
rWeekly = load(fullfile(sCodeDir,'DATA',sprintf( ...
    'bCharacteristicsOLHC_Combo%d.mat',iDataSetting)),'rData');
vDates = rWeekly.rData.yrmoda;
lSample = vDates >= 201416 & vDates <= 202222;
vDates = vDates(lSample);

rLTW = load(fullfile(sCodeDir,'DATA','LTW_3factor.mat'), ...
    'vDatesLiu','mLTW');
mLTW = fAlignByDate(rLTW.vDatesLiu,rLTW.mLTW,vDates,'LTW',0.95);
rBase = load(fullfile(sCodeDir,'Results','CTREND','CTREND_Base.mat'), ...
    'cResults','vDates');
assert(isequal(rBase.vDates(:),vDates(:)), ...
    'Figure B.2 baseline CTREND and weekly-date axes differ');
vCTREND = rBase.cResults.VW.mPortRet(end,:)';
mFactorIncrement = [mLTW,vCTREND];
lCommonFactor = all(isfinite(mFactorIncrement),2);
iExpectedFirst = find(lCommonFactor,1,'first');
assert(~isempty(iExpectedFirst), ...
    'Figure B.2 has no finite common-factor observation');

% Independently implement the documented presentation rule here instead
% of calling the plotting helper: pre-sample rows stay NaN; from the first
% common observation onward, a missing common increment is displayed as
% zero and hence leaves every cumulative path flat.
mExpected = NaN(size(mFactorIncrement));
mDisplayIncrement = mFactorIncrement(iExpectedFirst:end,:);
mDisplayIncrement(~all(isfinite(mDisplayIncrement),2),:) = 0;
mExpected(iExpectedFirst:end,:) = cumsum(mDisplayIncrement,1) * 100;
sExpectedYLabelToken = 'gaps = 0';

sFigure = fullfile(sCodeDir,'Results','Figures', ...
    'b06Table3_UnivariatePortfolioSorts_figure03.fig');
assert(exist(sFigure,'file') == 2, ...
    'Figure B.2 result is missing; run b06 before result invariants');

hFigure = openfig(sFigure,'invisible');
rCleanup = onCleanup(@() close(hFigure)); %#ok<NASGU>
hLines = findobj(hFigure,'Type','line');
assert(numel(hLines) == 4, ...
    'Figure B.2 must contain exactly four factor-return paths');

cFiniteMask = cell(numel(hLines),1);
mY = NaN(numel(vDates),numel(hLines));
for iIdxLine = 1:numel(hLines)
    vY = get(hLines(iIdxLine),'YData');
    vY = vY(:);
    assert(numel(vY) == numel(vDates), ...
        'Figure B.2 path must retain the complete weekly calendar');
    mY(:,iIdxLine) = vY;
    lFinite = isfinite(vY);
    cFiniteMask{iIdxLine} = lFinite;
    assert(isequal(lFinite,isfinite(mExpected(:,1))), ...
        ['Figure B.2 finite support differs from the dynamically rebuilt ' ...
         'common-factor display support']);
    assert(all(lFinite(iExpectedFirst:end)), ...
        ['Figure B.2 contains an internal NaN even though the disclosed ' ...
         'presentation convention sets internal missing increments to 0%%']);
end
for iIdxLine = 2:numel(hLines)
    assert(isequal(cFiniteMask{1},cFiniteMask{iIdxLine}), ...
        'Figure B.2 factor paths do not use identical common-week support');
end

% Graphics objects can be returned in reverse creation order.  Require a
% one-to-one permutation under which every finite value and every NaN agrees
% with the independently rebuilt paths; this validates the entire figure,
% not merely a sample-specific count of flat segments.
mPermutations = perms(1:size(mExpected,2));
dScale = max(1,max(abs(mExpected(isfinite(mExpected)))));
dTolerance = 1e-10 * dScale;
dBestError = Inf;
vBestPermutation = [];
for iIdxPermutation = 1:size(mPermutations,1)
    vPermutation = mPermutations(iIdxPermutation,:);
    mCandidate = mExpected(:,vPermutation);
    if ~isequal(isfinite(mY),isfinite(mCandidate))
        continue
    end
    lFinite = isfinite(mCandidate);
    dError = max(abs(mY(lFinite)-mCandidate(lFinite)),[],'all');
    if dError < dBestError
        dBestError = dError;
        vBestPermutation = vPermutation;
    end
end
assert(~isempty(vBestPermutation) && dBestError <= dTolerance, ...
    ['Figure B.2 paths differ from the cumulative paths dynamically ' ...
     'rebuilt from this run''s LTW and CTREND results']);

lObservedAllPathsFlat = all(abs(diff(mY,1,1)) <= 1e-12,2);
lExpectedAllPathsFlat = all(abs(diff( ...
    mExpected(:,vBestPermutation),1,1)) <= 1e-12,2);
assert(isequal(lObservedAllPathsFlat,lExpectedAllPathsFlat), ...
    'Figure B.2 zero-increment locations differ from rebuilt results');
iExpectedGapCount = nnz(~lCommonFactor(iExpectedFirst:end));

hAxes = ancestor(hLines(1),'axes');
sYLabel = get(get(hAxes,'YLabel'),'String');
if iscell(sYLabel)
    sYLabel = strjoin(sYLabel,' ');
end
assert(contains(sYLabel,sExpectedYLabelToken), ...
    'Figure B.2 axis must disclose that displayed gap increments equal 0%%');

fprintf(['FIGURE_B2_RESULT_TEST_OK lines=%d weeks=%d finite=%d ' ...
    'first=%d last=%d expected_gap_increments=%d ' ...
    'common_flat_increments=%d max_path_error=%.3g ' ...
    'dynamic_rebuild=1 zero_gap_disclosed=1\n'], ...
    numel(hLines),numel(cFiniteMask{1}), ...
    nnz(cFiniteMask{1}),find(cFiniteMask{1},1,'first'), ...
    find(cFiniteMask{1},1,'last'),iExpectedGapCount, ...
    nnz(lObservedAllPathsFlat(iExpectedFirst:end)),dBestError);
end
