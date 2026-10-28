function rAudit = compare_nine_methods_common_weeks(cBaselineFiles,sOutputDir)
% CTREND_REVISIT_FILE_PURPOSE: Compare all nine amended methods on identical finite return weeks without imputation.
%COMPARE_NINE_METHODS_COMMON_WEEKS Compare all 3x3 methods on identical weeks.
%
% Outputs include own-support, all-nine, by-M, by-D, by-P and pairwise tables.
% Each statistic is recomputed from the corresponding finite-date intersection;
% the routine never compares array positions before confirming date equality.
%
% cBaselineFiles must contain the nine CTREND_Base.mat paths in this order:
% M0_D0, M0_D1, M0_D2, M2_D0, M2_D1, M2_D2, M1_D0, M1_D1, M1_D2.
% The function never fills a missing return with zero. It reports each
% method's own support, the strict all-nine intersection, every pairwise
% intersection, and an auditable union-calendar return panel.

arguments
    cBaselineFiles (1,9)
    sOutputDir (1,1) string
end
cBaselineFiles = string(cBaselineFiles);
cLabels = ["M0_D0","M0_D1","M0_D2", ...
    "M2_D0","M2_D1","M2_D2", ...
    "M1_D0","M1_D1","M1_D2"];
if ~isfolder(sOutputDir)
    mkdir(sOutputDir);
end

cDates = cell(1,9);
cReturns = cell(1,9);
% Load and authenticate the common return/date schema for all nine inputs.
for iIdx = 1:9
    assert(isfile(cBaselineFiles(iIdx)), ...
        'Missing baseline file for %s: %s',cLabels(iIdx),cBaselineFiles(iIdx));
    r = load(cBaselineFiles(iIdx),'vDates','cResults');
    assert(isfield(r,'vDates') && isfield(r,'cResults') && ...
           isfield(r.cResults,'VW') && ...
           isfield(r.cResults.VW,'mPortRet'), ...
        '%s lacks vDates or cResults.VW.mPortRet',cLabels(iIdx));
    vDate = double(r.vDates(:));
    vRet = double(r.cResults.VW.mPortRet(end,:)');
    assert(numel(vDate)==numel(vRet) && all(isfinite(vDate)) && ...
           numel(unique(vDate))==numel(vDate) && all(diff(vDate)>0), ...
        '%s has an invalid or duplicate weekly calendar',cLabels(iIdx));
    cDates{iIdx} = vDate;
    cReturns{iIdx} = vRet;
end

vUnionDates = unique(vertcat(cDates{:}));
mReturn = NaN(numel(vUnionDates),9);
for iIdx = 1:9
    [lFound,vLoc] = ismember(cDates{iIdx},vUnionDates);
    assert(all(lFound),'Internal calendar alignment failure for %s',cLabels(iIdx));
    mReturn(vLoc,iIdx) = cReturns{iIdx};
end
lAllNineCommon = all(isfinite(mReturn),2);
assert(any(lAllNineCommon),'The nine methods have no common finite week');

tWeekly = array2table([vUnionDates,mReturn,double(lAllNineCommon)], ...
    'VariableNames',["year_week",cLabels,"all_nine_common"]);
writetable(tWeekly,fullfile(sOutputDir,'nine_method_weekly_returns.csv'));

tOwn = iSummaryTable(cLabels,vUnionDates,mReturn,isfinite(mReturn), ...
    "own_support");
tAll = iSummaryTable(cLabels,vUnionDates,mReturn, ...
    repmat(lAllNineCommon,1,9),"all_nine_common");
writetable(tOwn,fullfile(sOutputDir,'nine_method_own_support_summary.csv'));
writetable(tAll,fullfile(sOutputDir,'nine_method_all_common_summary.csv'));

% Within each data universe, compare M0/M2/M1 on one identical three-method
% support. Within each method, compare D0/D1/D2 on one identical three-universe
% support. These are often more informative than the strict all-nine
% intersection while remaining fully paired.
cByDataAxis = cell(3,1);
% Axis summaries hold D fixed while comparing methods, then hold M fixed while
% comparing data treatments. The same helper enforces equal support per group.
for iIdxD = 1:3
    vIdx = [iIdxD,3+iIdxD,6+iIdxD];
    lCommon = all(isfinite(mReturn(:,vIdx)),2);
    assert(any(lCommon),'No three-method common week for D%d',iIdxD-1);
    sSupport = sprintf('D%d_M0_M2_M1_common',iIdxD-1);
    cByDataAxis{iIdxD} = iSummaryTable( ...
        cLabels(vIdx),vUnionDates,mReturn(:,vIdx), ...
        repmat(lCommon,1,3),sSupport);
end
tByDataAxis = vertcat(cByDataAxis{:});
writetable(tByDataAxis,fullfile(sOutputDir, ...
    'nine_method_by_data_axis_common_summary.csv'));

cByMethod = cell(3,1);
vMethodCode = [0,2,1];
for iIdxM = 1:3
    vIdx = (iIdxM-1)*3+(1:3);
    lCommon = all(isfinite(mReturn(:,vIdx)),2);
    assert(any(lCommon),'No three-universe common week for M%d', ...
        vMethodCode(iIdxM));
    sSupport = sprintf('M%d_D0_D1_D2_common',vMethodCode(iIdxM));
    cByMethod{iIdxM} = iSummaryTable( ...
        cLabels(vIdx),vUnionDates,mReturn(:,vIdx), ...
        repmat(lCommon,1,3),sSupport);
end
tByMethod = vertcat(cByMethod{:});
writetable(tByMethod,fullfile(sOutputDir, ...
    'nine_method_by_method_common_summary.csv'));

iNumPairs = nchoosek(9,2);
cMethodA = strings(iNumPairs,1);
cMethodB = strings(iNumPairs,1);
vN = NaN(iNumPairs,1);
vStart = NaN(iNumPairs,1);
vEnd = NaN(iNumPairs,1);
vJaccard = NaN(iNumPairs,1);
vMeanA = NaN(iNumPairs,1);
vMeanB = NaN(iNumPairs,1);
vMeanDifference = NaN(iNumPairs,1);
vDifferenceT = NaN(iNumPairs,1);
vCorrelation = NaN(iNumPairs,1);
iPair = 0;
for iIdxA = 1:8
    for iIdxB = iIdxA+1:9
        iPair = iPair+1;
        lA = isfinite(mReturn(:,iIdxA));
        lB = isfinite(mReturn(:,iIdxB));
        lCommon = lA & lB;
        vA = mReturn(lCommon,iIdxA);
        vB = mReturn(lCommon,iIdxB);
        cMethodA(iPair) = cLabels(iIdxA);
        cMethodB(iPair) = cLabels(iIdxB);
        vN(iPair) = nnz(lCommon);
        if any(lCommon)
            vStart(iPair) = vUnionDates(find(lCommon,1,'first'));
            vEnd(iPair) = vUnionDates(find(lCommon,1,'last'));
            vMeanA(iPair) = mean(vA)*100;
            vMeanB(iPair) = mean(vB)*100;
            vMeanDifference(iPair) = mean(vA-vB)*100;
            vDifferenceT(iPair) = iTstat(vA-vB);
            if numel(vA) >= 2 && std(vA)>0 && std(vB)>0
                mCorr = corrcoef(vA,vB);
                vCorrelation(iPair) = mCorr(1,2);
            end
        end
        vJaccard(iPair) = nnz(lCommon)/nnz(lA | lB);
    end
end
tPairwise = table(cMethodA,cMethodB,vN,vStart,vEnd,vJaccard, ...
    vMeanA,vMeanB,vMeanDifference,vDifferenceT,vCorrelation, ...
    'VariableNames',{'method_a','method_b','common_n','start_year_week', ...
    'end_year_week','finite_week_jaccard','mean_a_pct','mean_b_pct', ...
    'mean_a_minus_b_pct','paired_difference_t','return_correlation'});
writetable(tPairwise,fullfile(sOutputDir, ...
    'nine_method_pairwise_common_week_summary.csv'));

rAudit = struct();
rAudit.cLabels = cLabels;
% Do not persist machine-specific input paths. The method labels and every
% aligned numeric value needed to rebuild the CSVs are stored below; external
% run inventories bind each input file to its accepted production run.
rAudit.cInputRoles = cLabels;
rAudit.vUnionDates = vUnionDates;
rAudit.mReturn = mReturn;
rAudit.lAllNineCommon = lAllNineCommon;
rAudit.tOwnSupport = tOwn;
rAudit.tAllNineCommon = tAll;
rAudit.tByDataAxisCommon = tByDataAxis;
rAudit.tByMethodCommon = tByMethod;
rAudit.tPairwise = tPairwise;
rAudit.sMissingWeekRule = 'never fill; compare only explicitly intersected finite weeks';
save(fullfile(sOutputDir,'nine_method_common_week_audit.mat'),'rAudit');
fprintf('NINE_METHOD_COMMON_WEEK_COMPARISON_OK union=%d common=%d\n', ...
    numel(vUnionDates),nnz(lAllNineCommon));
end

function t = iSummaryTable(cLabels,vUnionDates,mReturn,mMask,sSupport)
iNumMethods = numel(cLabels);
vN = NaN(iNumMethods,1);
vStart = NaN(iNumMethods,1);
vEnd = NaN(iNumMethods,1);
vMean = NaN(iNumMethods,1);
vStd = NaN(iNumMethods,1);
vT = NaN(iNumMethods,1);
vSharpe = NaN(iNumMethods,1);
for iIdx = 1:iNumMethods
    lUse = mMask(:,iIdx) & isfinite(mReturn(:,iIdx));
    vUse = mReturn(lUse,iIdx);
    vN(iIdx) = numel(vUse);
    if ~isempty(vUse)
        vStart(iIdx) = vUnionDates(find(lUse,1,'first'));
        vEnd(iIdx) = vUnionDates(find(lUse,1,'last'));
        vMean(iIdx) = mean(vUse)*100;
        vStd(iIdx) = std(vUse)*100;
        vT(iIdx) = iTstat(vUse);
        if numel(vUse)>=2 && std(vUse)>0
            vSharpe(iIdx) = sqrt(52)*mean(vUse)/std(vUse);
        end
    end
end
t = table(cLabels(:),repmat(sSupport,iNumMethods,1),vN,vStart,vEnd, ...
    vMean,vStd,vT,vSharpe,'VariableNames', ...
    {'method','support','n','start_year_week','end_year_week', ...
     'mean_pct','std_pct','t_stat','annualized_sharpe'});
end

function dT = iTstat(vData)
vData = vData(isfinite(vData));
if numel(vData)<2 || ~isfinite(std(vData)) || std(vData)<=0
    dT = NaN;
else
    dT = mean(vData)/(std(vData)/sqrt(numel(vData)));
end
end
