function test_audit_remediation()
% Deterministic regressions for the 2026-07-20 independent audit findings.

iTestTable8FormationMask();
iTestBaselineDesignFieldMatch();
iTestPairedSupportBETC();
iTestHedgeEstimatorEquality();
iTestTable5CompletePortfolioConsumer();
iTestOutputIndependentCoverage();
iTestEstimatorStatusCodebook();
iTestPayloadDigestFailClosed();
iTestScreeningManifestContentBinding();
fprintf('AUDIT_REMEDIATION_TEST_OK\n');
end

function iTestTable5CompletePortfolioConsumer()
% b05 must remain hedge-only, but Table 5 must reconstruct its middle
% quintiles.  Week 1 has 23 observed scores, so the all-portfolio estimator
% fails its global five-assets-per-bin check while the two traded legs
% remain valid.  Week 2 has 25 scores and identifies every middle quintile.
iNumAssets = 25;
mSort = repmat((1:iNumAssets)',1,2);
mSort(24:25,1) = NaN;
mRet = repmat((1:iNumAssets)'/1000,1,2);
mME = ones(iNumAssets,2);
vQuantiles = (0:0.2:1)';
rOptions = struct('sFreq','weekly','iMinNumCS',1, ...
    'iMinNumAssets',5,'lEnsureAllObs',true,'lHedgeOnly',true);
rHedge = fSingleSortMulti(mSort,mRet,vQuantiles,[],mME,rOptions);

[mTable5,rDiag] = fBuildTable5PortfolioReturns( ...
    mSort,mRet,mME,rHedge,vQuantiles,rOptions);
rFullOptions = rOptions;
rFullOptions.lHedgeOnly = false;
rFull = fSingleSortMulti(mSort,mRet,vQuantiles,[],mME,rFullOptions);

vOuter = [1,5,6];
assert(isequaln(mTable5(vOuter,:),rHedge.VW.mPortRet(vOuter,:)) && ...
    isfinite(mTable5(6,1)) && isnan(rFull.VW.mPortRet(6,1)), ...
    'Table 5 weakened or replaced b05 hedge-only H-L accounting');
assert(all(isfinite(mTable5(2:4,2))) && ...
    all(abs(mTable5(2:4,2)-rFull.VW.mPortRet(2:4,2)) <= 1e-15), ...
    'Table-5 middle-quintile reconstruction differs from the full sort');
assert(all(isfinite(mTable5(2:4,2))) && ...
    isequal(rDiag.vMiddleRowsReconstructed,2:4) && ...
    rDiag.lOuterRowsExact, ...
    'Table 5 did not produce all identified middle-quintile returns');
end

function iTestBaselineDesignFieldMatch()
sCodeDir = fileparts(fileparts(mfilename('fullpath')));
rDesign = load(fullfile(sCodeDir,'DesignChoices.mat'),'tCombos');
tCombos = rDesign.tCombos;
lBaseline = tCombos.vThreshold == 0.005 & ...
    strcmpi(tCombos.cOutlierTreatment,'trunc') & ...
    tCombos.vExclStable & tCombos.vMinMCAP == 1e6 & ...
    tCombos.vMinPRC == 0 & tCombos.vRetLead == 0 & ...
    tCombos.vRoll & tCombos.vNumIn == 52 & ...
    tCombos.vUseValueWts & tCombos.vUseVolume;
assert(nnz(lBaseline) == 1, ...
    'The b05 baseline must match exactly one b09 design row by fields');
iSetting = tCombos.setting(lBaseline);
assert(iSetting ~= 1, ...
    ['The fixture must prevent tests and documentation from silently ' ...
     'equating physical combo 1 with the field-matched b05 baseline']);
end

function iTestTable8FormationMask()
mScore = [100;90;80;70;60;50];
lEligible = logical([0;1;1;1;1;1]);
lUniverse = fBuildTopUniverse(mScore,3,lEligible);
assert(isequal(find(lUniverse),[2;3;4]), ...
    ['An ineligible high-score asset displaced an eligible Table-8 ' ...
     'cutoff asset']);

% Future payoff availability is intentionally not an input to the helper.
% Changing it therefore cannot alter formation membership.
lFuturePayoffObservedA = logical([1;1;1;1;1;1]); %#ok<NASGU>
lFuturePayoffObservedB = logical([0;0;1;0;1;0]); %#ok<NASGU>
lUniverseAgain = fBuildTopUniverse(mScore,3,lEligible);
assert(isequal(lUniverse,lUniverseAgain), ...
    'Table-8 membership changed with future payoff availability');
end

function iTestPairedSupportBETC()
mSort = repmat((1:6)',1,4);
mSort(:,2) = NaN; % break the transition chain
mRet = repmat([0.01;0.02;0.03;0.04;0.05;0.06],1,4);
mRet(:,3) = mRet(:,3) + 0.20; % finite gross at an unobservable restart cost
mME = ones(size(mSort));
rOptions = struct('sFreq','weekly','iMinNumCS',6, ...
    'iMinNumAssets',1,'lEnsureAllObs',true,'lHedgeOnly',true);
r = fSingleSortMulti(mSort,mRet,[0;0.5;1],[],mME,rOptions);

lPaired = isfinite(r.VW.mGrossRetPairedForBETC(:,end)) & ...
    isfinite(r.VW.mCostBasePaired(:,end));
assert(~lPaired(3) && isfinite(r.VW.mPortRet(end,3)), ...
    'The deterministic restart date must have gross return but no cost');
dExpectedGross = mean(r.VW.mPortRet(end,lPaired));
iAssertClose(r.VW.vAvgGrossPairedForBETC(end), ...
    dExpectedGross,1e-14,'paired BETC gross mean');
if isfinite(r.VW.vBreakEvenTC(end))
    iAssertClose(r.VW.vNetReturnAtBETC(end),0,1e-12, ...
        'paired BETC zero-net identity');
end
end

function iTestHedgeEstimatorEquality()
iNumAssets = 23;
mSort = (1:iNumAssets)';
mRet = (1:iNumAssets)'/1000;
mME = (1:iNumAssets)';
rOptions = struct('sFreq','weekly','iMinNumCS',1, ...
    'iMinNumAssets',5,'lEnsureAllObs',true,'lHedgeOnly',true);
rHedge = fSingleSortMulti(mSort,mRet,(0:0.2:1)',[],mME,rOptions);
[vFastEW,vFastVW] = fSingleSortFast(mSort,mRet,mME, ...
    'vPercentile',(0:0.2:1)', ...
    'iMinNumCS',1,'iMinNumAssets',5);
iAssertClose(rHedge.EW.mPortRet(end),vFastEW,1e-14, ...
    'b05/b09 equal-weight H-L estimator');
iAssertClose(rHedge.VW.mPortRet(end),vFastVW,1e-14, ...
    'b05/b09 value-weight H-L estimator');

rAllPorts = rOptions;
rAllPorts.lHedgeOnly = false;
rAll = fSingleSortMulti(mSort,mRet,(0:0.2:1)',[],mME,rAllPorts);
assert(isnan(rAll.VW.mPortRet(end)) && isfinite(vFastVW), ...
    ['Test fixture failed to create the sparse-middle-bin case that ' ...
     'distinguishes the old b05 availability rule']);
end

function iTestOutputIndependentCoverage()
mExpected = true(25,1);
mYhat = NaN(25,1);
mYhat(1) = 0.1;
lScheduled = true;
lPotential5 = fPotentialResearchDesignFactorWeeks( ...
    mExpected,0:0.2:1,25,5,lScheduled);
lPotential3 = fPotentialResearchDesignFactorWeeks( ...
    mExpected,[0,0.3,0.7,1],25,5,lScheduled);
rEstimatorSummary = fSummarizeResearchDesignEstimatorAudit(struct());
r = fAuditResearchDesignCoverage(mYhat,mExpected,NaN,NaN, ...
    lScheduled,lPotential5,lPotential3,false,false, ...
    rEstimatorSummary,0.5);
assert(r.iExpectedPredictionAssetWeeks == 25 && ...
       r.iFinitePredictionAssetWeeks == 1 && ...
       r.iFailedPredictionWeeks == 1 && ...
       r.dPredictionAssetCoverageRatio == 1/25 && ...
       r.dPredictionCoverageRatio == 0 && ~r.lAccepted, ...
    'One finite asset incorrectly certified an incomplete prediction week');
end

function iTestEstimatorStatusCodebook()
rEstimated = struct('sCode',"estimated",'sIdentifier',"",'sMessage',"");
rFailed = struct('sCode',"expected_no_admissible_lambda", ...
    'sIdentifier',"",'sMessage',"");
rAudit = struct();
rAudit.cSelectionStatus = {rFailed;rEstimated};
rAudit.cSelected = {false(1,2);false(1,2)};
r = fSummarizeResearchDesignEstimatorAudit(rAudit);
assert(isequal(r.vWindowStatus,uint8([5;1])) && ...
    r.iExpectedFailureWindows == 1 && ...
    r.iUnexpectedFailureWindows == 0 && ...
    isequal(r.lEmptySelection,[false;true]), ...
    ['A named ENet failure was conflated with a successfully estimated ' ...
     'empty selected set']);
end

function iTestPayloadDigestFailClosed()
sTempDir = tempname;
mkdir(sTempDir);
rCleanup = onCleanup(@() rmdir(sTempDir,'s')); %#ok<NASGU>
sFile = fullfile(sTempDir,'CTREND_Combo1.mat');
x = 1; %#ok<NASGU>
save(sFile,'x');
sSHA = fFileSHA256(sFile);
iFile = fopen([sFile,'.sha256'],'w');
assert(iFile >= 0,'Could not create deterministic digest fixture');
fprintf(iFile,'%s  CTREND_Combo1.mat\n',sSHA);
fclose(iFile);
assert(strcmp(fAssertB09PayloadDigest(sFile,1,sSHA),sSHA), ...
    'A valid b09 payload digest was rejected');

% Preserve schema and filename but change the numeric payload. The stale
% sidecar/manifest must fail even though a size/status-only validator would
% have accepted the file.
x = 2; %#ok<NASGU>
save(sFile,'x');
lRejected = false;
try
    fAssertB09PayloadDigest(sFile,1,sSHA);
catch
    lRejected = true;
end
assert(lRejected, ...
    'A same-schema, different-numeric b09 payload was not rejected');
end

function iTestScreeningManifestContentBinding()
sTempDir = tempname;
mkdir(sTempDir);
rCleanup = onCleanup(@() rmdir(sTempDir,'s')); %#ok<NASGU>
cInputNames = { ...
    'close_cmc.csv','low_cmc.csv','high_cmc.csv','open_cmc.csv', ...
    'market_cap_cmc.csv','volume_cmc.csv','MetaData.mat', ...
    'F-F_Research_Data_Factors_daily.CSV','LTW_3factor.xlsx','UCRY.csv'};
for iIdx = 1:numel(cInputNames)
    iWriteText(fullfile(sTempDir,cInputNames{iIdx}), ...
        sprintf('fixture_%02d\n',iIdx));
end
sManifest = fullfile(sTempDir,'screening_summary.json');
iWriteText(sManifest,[ ...
    '{"exclude_stablecoins":false,"min_marketcap":0,' ...
     '"strict_contiguous":false}']);
rMetaData = struct('vStableCoin',logical([0;1]));
rProvenance = fValidateInputProvenance(sTempDir,rMetaData);
assert(any(strcmp(rProvenance.cRawInputName, ...
                  'screening_summary.json')), ...
    'The screening certificate was omitted from raw-input content hashes');
fAssertRawInputProvenance(sTempDir,rProvenance);

% The production scripts pass "./DATA/". MATLAB may change folder after the
% process starts, so relative provenance paths must resolve against MATLAB's
% current pwd rather than Java's stale process working directory.
sOldFolder = pwd;
rFolderCleanup = onCleanup(@() cd(sOldFolder));
cd(sTempDir);
rRelative = fValidateInputProvenance('./',rMetaData);
clear rFolderCleanup
cd(sOldFolder);
assert(strcmp(rRelative.sRawInputsSHA256, ...
              rProvenance.sRawInputsSHA256), ...
    'Relative DATA provenance resolved outside MATLAB''s current folder');

% Keep the exporter settings scientifically valid but change the exact
% certificate bytes. The saved b01 provenance must reject the mutation.
iWriteText(sManifest,[ ...
    '{"exclude_stablecoins":false, "min_marketcap":0,' ...
     '"strict_contiguous":false}']);
lRejected = false;
try
    fAssertRawInputProvenance(sTempDir,rProvenance);
catch
    lRejected = true;
end
assert(lRejected, ...
    'A post-b01 screening-manifest content mutation was not rejected');
end

function iWriteText(sFilename,sText)
iFile = fopen(sFilename,'w');
assert(iFile >= 0,'Could not create raw-provenance fixture');
rCleanup = onCleanup(@() fclose(iFile));
fprintf(iFile,'%s',sText);
clear rCleanup
end

function iAssertClose(dActual,dExpected,dTolerance,sName)
assert(all(isfinite([dActual,dExpected])) && ...
    abs(dActual-dExpected) <= dTolerance, ...
    '%s differs from its deterministic reference',sName);
end
