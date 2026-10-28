% CTREND_REVISIT_FILE_PURPOSE: Unit-test whole-history D-axis exclusion across every synchronized raw field and audit count.
function test_global_exclusion(sPackageRoot)
% Deterministic in-memory and immutable-metadata test of D-axis deletion.
% Every excluded CMCID/symbol must exist in frozen metadata, every synchronized
% field must lose the same columns, retained bytes must remain exact, and the
% emitted audit must report the configured identity/count. No file is modified.

arguments
    sPackageRoot {mustBeTextScalar}
end
sPackageRoot = char(java.io.File(char(sPackageRoot)).getCanonicalPath());
addpath(fullfile(sPackageRoot,'engines','M1','base','Utils'));
addpath(fullfile(sPackageRoot,'engines','M1','overlays','exclusion','Utils'));
rCleanup = onCleanup(@() iRestoreEnvironment());

% Prove every frozen CMCID/symbol pair exists exactly once in the actual raw
% metadata.  The synthetic tests below alone would not detect a mistyped ID.
rRaw = load(fullfile(sPackageRoot,'data','raw','common','MetaData.mat'), ...
    'rMetaData');
assert(isfield(rRaw,'rMetaData'));
rActual = rRaw.rMetaData;
assert(numel(unique(rActual.vID(:))) == numel(rActual.vID));
for sDataID = ["D1","D2"]
    % Validate configuration against actual immutable raw metadata first.
    tActual = readtable(fullfile(sPackageRoot,'config','exclusions', ...
        sDataID+'.csv'),'TextType','string','VariableNamingRule','preserve');
    for iRow = 1:height(tActual)
        iColumn = find(rActual.vID(:) == tActual.asset_id(iRow));
        assert(isscalar(iColumn) && ...
            strcmpi(string(rActual.cSymbol(iColumn)),tActual.symbol(iRow)), ...
            'Immutable metadata mismatch for CMCID %d',tActual.asset_id(iRow));
    end
end

% D1: one named asset disappears; every retained raw value stays bit exact.
sD1 = fullfile(sPackageRoot,'config','exclusions','D1.csv');
setenv('CTTREND_DATA_TREATMENT_ID','D1');
setenv('CTTREND_ASSET_EXCLUSION_FILE',sD1);
setenv('CTTREND_ASSET_EXCLUSION_SHA256',fFileSHA256(sD1));
vID = [1;3787;6539];
rMeta = iMetadata(vID,["BTC";"INNBCL";"YAM"]);
cPanel = iPanels(4,numel(vID));
[mOpen,mHigh,mLow,mClose,mME,mVolume,vP,vM,vV,rOut,rAudit] = ...
    fApplyConfiguredGlobalAssetExclusion(cPanel{:},vID,vID,vID,rMeta);
cObserved = {mOpen,mHigh,mLow,mClose,mME,mVolume};
assert(isequal(vP,[1;6539]) && isequal(vP,vM) && isequal(vP,vV));
assert(isequal(rOut.vID,[1;6539]) && ...
    isequal(string(rOut.cSymbol),["BTC";"YAM"]));
for iPanel = 1:6
    assert(isequal(cObserved{iPanel},cPanel{iPanel}(:,[1,3])));
end
assert(rAudit.iExcludedAssets == 1 && ...
    isequal(rAudit.vExcludedAssetID,3787) && ...
    strcmp(rAudit.sDataTreatmentID,'D1'));

% D2: all 28 frozen rows disappear, while BTC, NPXS, PUNDIX and YAM remain.
sD2 = fullfile(sPackageRoot,'config','exclusions','D2.csv');
tD2 = readtable(sD2,'TextType','string','VariableNamingRule','preserve');
setenv('CTTREND_DATA_TREATMENT_ID','D2');
setenv('CTTREND_ASSET_EXCLUSION_FILE',sD2);
setenv('CTTREND_ASSET_EXCLUSION_SHA256',fFileSHA256(sD2));
vID = [1;tD2.asset_id;2603;6539;9040];
sSymbol = ["BTC";tD2.symbol;"NPXS";"YAM";"PUNDIX"];
rMeta = iMetadata(vID,sSymbol);
cPanel = iPanels(3,numel(vID));
[mOpen,mHigh,mLow,mClose,mME,mVolume,vP,vM,vV,rOut,rAudit] = ...
    fApplyConfiguredGlobalAssetExclusion(cPanel{:},vID,vID,vID,rMeta);
cObserved = {mOpen,mHigh,mLow,mClose,mME,mVolume};
assert(isequal(vP,[1;2603;6539;9040]) && isequal(vP,vM) && isequal(vP,vV));
assert(isequal(rOut.vID,[1;2603;6539;9040]) && ...
    isequal(string(rOut.cSymbol),["BTC";"NPXS";"YAM";"PUNDIX"]));
for iPanel = 1:6
    assert(isequal(cObserved{iPanel},cPanel{iPanel}(:,[1,end-2:end])));
end
assert(rAudit.iExcludedAssets == 28 && ...
    numel(rAudit.vExcludedAssetID) == 28 && ...
    any(rAudit.vExcludedAssetID == 17020) && ...
    any(rAudit.vExcludedAssetID == 18615) && ...
    ~any(rAudit.vExcludedAssetID == 2603) && ...
    ~any(rAudit.vExcludedAssetID == 6539) && ...
    ~any(rAudit.vExcludedAssetID == 9040) && ...
    strcmp(rAudit.sDataTreatmentID,'D2'));

clear rCleanup
iRestoreEnvironment();
fprintf(['GLOBAL_EXCLUSION_TEST_OK d1=1 d2=28 raw_metadata_pairs=28 ' ...
    'separate_cmcids_retained=2 nonfixed_retained=1 retained_values_exact=1\n']);
end

function cPanel = iPanels(iRows,iColumns)
mBase = reshape(1:(iRows*iColumns),iRows,iColumns);
cPanel = arrayfun(@(i)mBase+i*100000,1:6,'UniformOutput',false);
end

function rMeta = iMetadata(vID,sSymbol)
rMeta = struct();
rMeta.vID = vID(:);
rMeta.cSymbol = cellstr(sSymbol(:));
rMeta.cName = cellstr("name_"+sSymbol(:));
rMeta.cCoinType = repmat({'coin'},numel(vID),1);
rMeta.vStableCoin = false(numel(vID),1);
end

function iRestoreEnvironment()
setenv('CTTREND_DATA_TREATMENT_ID','');
setenv('CTTREND_ASSET_EXCLUSION_FILE','');
setenv('CTTREND_ASSET_EXCLUSION_SHA256','');
end
