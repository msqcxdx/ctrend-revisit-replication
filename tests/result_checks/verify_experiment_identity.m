% CTREND_REVISIT_FILE_PURPOSE: Check that a saved b01 checkpoint matches its declared M method and D data treatment.
function verify_experiment_identity()
% Inputs arrive through CTREND_VERIFY_* environment variables so the shell
% acceptance gate can inspect a run without editing it. The function checks
% D-axis exclusion identities, method-specific raw-correction provenance, and
% M1 DesignChoices content. It writes no result and fails on any mismatch.

sRoot = getenv('CTREND_VERIFY_PACKAGE_ROOT');
sID = getenv('CTREND_VERIFY_EXPERIMENT_ID');
sDataFile = getenv('CTREND_VERIFY_DATA_FILE');
sDesignFile = getenv('CTREND_VERIFY_DESIGN_CHOICES_FILE');
sExpectedDesignFile = getenv('CTREND_VERIFY_EXPECTED_DESIGN_CHOICES_FILE');
assert(isfolder(sRoot) && isfile(sDataFile));
assert(any(strcmp(sID,{'M0_D0','M0_D1','M0_D2', ...
    'M1_D0','M1_D1','M1_D2', ...
    'M2_D0','M2_D1','M2_D2'})));
sMethod = extractBefore(string(sID),'_');
sDataID = extractAfter(string(sID),'_');

r = load(sDataFile,'rGlobalAssetExclusionAudit', ...
    'rV2RawCorrectionAudit','rInputProvenance');
% D0 must contain no exclusion audit; D1/D2 must exactly match frozen CSV IDs.
if sDataID == "D0"
    assert(~isfield(r,'rGlobalAssetExclusionAudit'), ...
        'D0 unexpectedly contains a configured global exclusion audit');
else
    assert(isfield(r,'rGlobalAssetExclusionAudit'));
    a = r.rGlobalAssetExclusionAudit;
    assert(strcmp(a.sDataTreatmentID,sDataID));
    t = readtable(fullfile(sRoot,'config','exclusions',sDataID+'.csv'), ...
        'TextType','string','VariableNamingRule','preserve');
    assert(isequal(sort(a.vExcludedAssetID(:)),sort(t.asset_id(:))));
    assert(a.iExcludedAssets == height(t));
    if sDataID == "D2"
        assert(height(t) == 28 && ~any(ismember([2603;6539;9040],t.asset_id)));
    end
end

if sMethod == "M1"
    % M1 additionally binds its no-raw-adjustment mode and full design matrix.
    assert(isfield(r,'rV2RawCorrectionAudit'));
    assert(strcmp(r.rV2RawCorrectionAudit.sMode,'none'));
    assert(r.rV2RawCorrectionAudit.iRegistryRows == 0);
    if isfield(r,'rInputProvenance')
        assert(strcmp(r.rInputProvenance.sRawAdjustmentMode,'none'));
    end
    assert(isfile(sDesignFile) && isfile(sExpectedDesignFile), ...
        'M1 DesignChoices identity files are missing');
    rObservedDesign = load(sDesignFile);
    rExpectedDesign = load(sExpectedDesignFile);
    assert(isequaln(rObservedDesign,rExpectedDesign), ...
        'Saved M1 DesignChoices differ from the frozen package design');
end
if sMethod == "M2"
    assert(~isfield(r,'rV2RawCorrectionAudit'), ...
        'M2 must be derived from M0, not from the M1 raw-data layer');
end
fprintf(['EXPERIMENT_IDENTITY_TEST_OK experiment=%s data=%s ' ...
    'raw_adjustment=none design_choices_bound=%d\n'], ...
    sID,sDataFile,sMethod == "M1");
end
