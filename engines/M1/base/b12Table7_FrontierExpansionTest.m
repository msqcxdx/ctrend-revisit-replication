% Script for implementing the mean-variance frontier expansion test
%
% Requires that b05CreateCTREND and b06Table3_UnivariatePortfolioSorts 
% were executed
%
% This script produces:
%   Table 7:    Frontier Expansion Test

% Clear console
clear; clc; close all;

% Set paths
sOldPath    = path;
sDataPath   = './DATA/';
addpath('./Utils/');
addpath('./LatexTables/');

% Define null models
cFactMdls(1,1) = {'CTREND'};                cFactMdls{1,2} = {'CTREND'};
cFactMdls(2,1) = {'CMKT + CTREND'};         cFactMdls{2,2} = {'CMKT', 'CTREND'};
cFactMdls(3,1) = {'CMKT + CSMB + CTREND'};  cFactMdls{3,2} = {'CMKT', 'CSMB', 'CTREND'};
cFactMdls(4,1) = {'LTW'};                   cFactMdls{4,2} = {'CMKT', 'CSMB', 'CMOM'};
iNumNullModels = size(cFactMdls,1);

% Load trend factor
sFilename = sprintf('./Results/CTREND/CTREND_Base.mat');
rCTREND   = load(sFilename,'cResults','vDates','vModelDates','vAssetID', ...
    'sCodeFingerprint','sDataBuildID');
fAssertSavedResultProvenance(rCTREND, ...
    fGetCurrentWeeklyDataBuildID('./DATA/'));
assert(isfield(rCTREND,'vModelDates') && ~isempty(rCTREND.vModelDates), ...
    ['CTREND_Base.mat must contain the explicitly saved model-date axis; ' ...
     'rerun b05CreateCTREND rather than inferring dates by padding.']);
vCTREND   = rCTREND.cResults.VW.mPortRet(end,:)';
vDates    = rCTREND.vDates;

% The paper starts this second-stage OOS exercise only after a complete
% 52-calendar-week history could have elapsed from the first scheduled
% CTREND model week.  This is a schedule rule, not a requirement that all
% 52 factor returns be finite.
[lModelDateFound,vIdxModelDate] = ismember( ...
    rCTREND.vModelDates(:),vDates(:));
assert(all(lModelDateFound) && ...
    all(diff(vIdxModelDate) > 0) && ...
    numel(unique(vIdxModelDate)) == numel(vIdxModelDate), ...
    'Saved CTREND model dates do not map uniquely to the Table-7 calendar');
iNumIn = 52;
iIdxFirstOut = vIdxModelDate(1) + iNumIn;
assert(iIdxFirstOut <= numel(vDates), ...
    'The sample ends before the first scheduled Table-7 OOS week');
fprintf('table7_first_oos index=%d date=%d model_start_date=%d\n', ...
    iIdxFirstOut,vDates(iIdxFirstOut),rCTREND.vModelDates(1));

% Load LTW factors
load('./DATA/LTW_3factor.mat');
mLTW        = fAlignByDate(vDatesLiu, mLTW, vDates, 'LTW', 0.95);

% Keep every factor on the unchanged weekly calendar. Missingness is applied
% only after a null model and its candidate additional factor have been
% selected below. Otherwise an unused factor could invalidate a 52-week
% window for a test in which that factor never appears.
mFactors = [mLTW, vCTREND];
tFactors = array2table(mFactors,...
    'VariableNames',{'CMKT', 'CSMB', 'CMOM', 'CTREND'});
iNumFact = size(tFactors,2);

% Initialize memory
mGenAlphas      = NaN(iNumFact, iNumNullModels);
mGenAlphasT     = NaN(iNumFact, iNumNullModels);
cSpanningDiagnostics = cell(iNumFact,iNumNullModels);
mRegressionN = NaN(iNumFact,iNumNullModels);

% Loop over null models
for iIdxN = 1:iNumNullModels
    % Get factors
    cNullFact = cFactMdls{iIdxN,2};
    mFactNull = table2array(tFactors(:,cNullFact));
    vGenAlphasTemp  = NaN(iNumFact, 1);
    vGenAlphasTTemp = NaN(iNumFact, 1);

    % Loop over factors
    for iIdxA = 1:iNumFact
        % Get factor
        sAltFact = tFactors.Properties.VariableNames{iIdxA};

        % Skip if factor already included in null factor set
        if ismember(sAltFact, cNullFact)
            continue
        end
        vFactAlt = tFactors.(sAltFact);

        % Perform mean-variance frontier expansion test
        rStats = fMeanVarianceSpanningSoebhag(mFactNull, vFactAlt,...
            "iNumIn",iNumIn,'lRoll',true,'dTargetVol',0.1, ...
            'iIdxFirstOut',iIdxFirstOut);

        % Save generalized alphas
        vGenAlphasTemp(iIdxA)  = rStats.vBeta(1);
        vGenAlphasTTemp(iIdxA) = rStats.vBetaT_hac(1);
        cSpanningDiagnostics{iIdxA,iIdxN} = rStats;
        mRegressionN(iIdxA,iIdxN) = rStats.rRegressionY.iNumObs;
        fprintf(['table7_test null="%s" alternative=%s regression_N=%d ' ...
            'identified_oos=%d\n'],cFactMdls{iIdxN,1},sAltFact, ...
            rStats.rRegressionY.iNumObs,nnz(isfinite(rStats.vTangPortXY) & ...
            isfinite(rStats.vTangPortY)));
    end
    mGenAlphas(:, iIdxN)  = vGenAlphasTemp;
    mGenAlphasT(:, iIdxN) = vGenAlphasTTemp;
end

% Create table
cTable7 = fAddStatistics( fMatrix2Cell(mGenAlphas*100,2),...
    fMatrix2Cell(mGenAlphasT,2),...
    abs(mGenAlphasT)>=1.96);
cTable7(isnan(mGenAlphas)) = {''};
cTable7 = [[{''}, cFactMdls(:,1)']; [tFactors.Properties.VariableNames(:), cTable7]];
rInput.table = cTable7;
rInput.tableCaption = 'Frontier Expansion Test';
fCreateLatexTable(rInput);

% Persist the exact calendar-window N, covariance rank/rcond, failure
% reason, and final regression N for every table cell.  This audit file is
% published atomically and is part of the scientific output, not a cache.
rTable7Diagnostics = struct();
rTable7Diagnostics.vDates = vDates;
rTable7Diagnostics.vModelDates = rCTREND.vModelDates;
rTable7Diagnostics.iNumIn = iNumIn;
rTable7Diagnostics.iIdxFirstOut = iIdxFirstOut;
rTable7Diagnostics.iFirstOutDate = vDates(iIdxFirstOut);
rTable7Diagnostics.cFactorNames = ...
    tFactors.Properties.VariableNames;
rTable7Diagnostics.cNullModels = cFactMdls;
rTable7Diagnostics.cSpanningDiagnostics = cSpanningDiagnostics;
rTable7Diagnostics.mRegressionN = mRegressionN;
rTable7Diagnostics.mGenAlphas = mGenAlphas;
rTable7Diagnostics.mGenAlphasT = mGenAlphasT;
rTable7Diagnostics.dTargetVol = 0.1;
rTable7Diagnostics.sWindowMissingRule = ...
    ['Select prior 52 calendar positions, then listwise null+alternative ' ...
     'inside that fixed window; never backfill from older weeks'];
rTable7Diagnostics.sIdentificationRule = ...
    ['All named factors remain required (including an identically-zero ' ...
     'factor); N>K, full covariance rank, rcond>=1e-12, else fail closed'];
sCodeFingerprint = fPipelineCodeFingerprint(pwd);
sDataBuildID = rCTREND.sDataBuildID;
sDiagnosticsFile = './Results/Table7_FrontierExpansionDiagnostics.mat';
sDiagnosticsTemporary = [tempname('./Results'),'.mat'];
rDiagnosticsCleanup = onCleanup(@() iDeleteIfExists(sDiagnosticsTemporary));
save(sDiagnosticsTemporary,'rTable7Diagnostics', ...
    'sCodeFingerprint','sDataBuildID');
[lMoved,sMoveMessage] = movefile( ...
    sDiagnosticsTemporary,sDiagnosticsFile,'f');
assert(lMoved,'Could not atomically publish %s: %s', ...
    sDiagnosticsFile,sMoveMessage);
clear rDiagnosticsCleanup

% Restore path
path(sOldPath);

function iDeleteIfExists(sFilename)
if exist(sFilename,'file') == 2
    delete(sFilename);
end
end


