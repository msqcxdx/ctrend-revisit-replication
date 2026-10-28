% CTREND_REVISIT_FILE_PURPOSE: Check that a saved b01 checkpoint matches its declared M method and D data treatment.
function verify_experiment_identity()
% Verify the saved b01 checkpoint against the declared M/D cell.

sRoot = getenv('CTTREND_VERIFY_PACKAGE_ROOT');
sID = getenv('CTTREND_VERIFY_EXPERIMENT_ID');
sDataFile = getenv('CTTREND_VERIFY_DATA_FILE');
sDesignFile = getenv('CTTREND_VERIFY_DESIGN_CHOICES_FILE');
sExpectedDesignFile = getenv('CTTREND_VERIFY_EXPECTED_DESIGN_CHOICES_FILE');
assert(isfolder(sRoot) && isfile(sDataFile));
assert(any(strcmp(sID,{'M0_D0','M0_D1','M0_D2', ...
    'M1_D0','M1_D1','M1_D2', ...
    'M2_D0','M2_D1','M2_D2', ...
    'P0_M0_D0','P0_M0_D1','P0_M0_D2', ...
    'P0_M1_D0','P0_M1_D1','P0_M1_D2', ...
    'P0_M2_D0','P0_M2_D1','P0_M2_D2'})));
cParts = split(string(sID),'_');
if numel(cParts) == 2
    sPreprocessing = "P1";
    sMethod = cParts(1);
    sDataID = cParts(2);
else
    sPreprocessing = cParts(1);
    sMethod = cParts(2);
    sDataID = cParts(3);
end

r = load(sDataFile,'rGlobalAssetExclusionAudit', ...
    'rV2RawCorrectionAudit','rInputProvenance', ...
    'rUnifiedMissingPreprocessing','lUnifiedAuxiliaryFilled','mClose');
if sPreprocessing == "P0"
    assert(~isfield(r,'rUnifiedMissingPreprocessing'), ...
        'P0 checkpoint unexpectedly contains unified preprocessing state');
    if sMethod == "M1"
        assert(isfield(r,'lUnifiedAuxiliaryFilled') && ...
            islogical(r.lUnifiedAuxiliaryFilled) && ...
            isequal(size(r.lUnifiedAuxiliaryFilled),size(r.mClose)) && ...
            ~any(r.lUnifiedAuxiliaryFilled,'all'), ...
            ['P0 M1 checkpoint must persist a dimension-matched all-false ' ...
             'audit sentinel without filling any input cell']);
    else
        assert(~isfield(r,'lUnifiedAuxiliaryFilled'), ...
            'P0 M2 unexpectedly contains the M1 auxiliary audit sentinel');
    end
end
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
    assert(isfield(r,'rV2RawCorrectionAudit'));
    assert(strcmp(r.rV2RawCorrectionAudit.sMode,'none'));
    assert(r.rV2RawCorrectionAudit.iRegistryRows == 0);
    if isfield(r,'rInputProvenance')
        assert(strcmp(r.rInputProvenance.sRawAdjustmentMode,'none'));
        if sPreprocessing == "P0"
            assert(~isfield(r.rInputProvenance, ...
                'sUnifiedMissingPreprocessingFormat'));
            assert(strcmp(r.rInputProvenance.sCoreExperimentID,sID), ...
                'P0 checkpoint is not bound to its full P/M/D identity');
        end
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
