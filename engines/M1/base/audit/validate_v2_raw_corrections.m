function rAudit = validate_v2_raw_corrections()
% Apply the complete production unit registry to real CMC cells, read only.
%
% Only registry asset columns are retained in memory.  The source CSV files
% are never edited.  Compact before/after evidence is written below
% audit/output for independent inspection.

sRawDir = getenv('CTREND_RAW_DATA_DIR');
if isempty(sRawDir)
    sRawDir = fullfile(fileparts(mfilename('fullpath')),'..','DATA');
end
sOutputDir = getenv('CTREND_EVENT_AUDIT_DIR');
if isempty(sOutputDir)
    sOutputDir = fullfile(fileparts(mfilename('fullpath')),'output');
end
if ~exist(sOutputDir,'dir')
    mkdir(sOutputDir);
end

sManifest = fullfile(fileparts(mfilename('fullpath')),'output', ...
    'causal_point_external_disagreement_candidates.csv');
tExternal = readtable(sManifest,'TextType','string');
assert(height(tExternal) == 2600, ...
    'The rejected external-disagreement audit must contain 2,600 rows');
vManualID = [624;638;895;1902;2603;3468;4069;4275;5834;9040];
vWantedID = unique([vManualID;double(tExternal.AssetID)]);

[mClose,vAssetID,dtDate] = iReadSelectedPanel( ...
    sRawDir,'close_cmc.csv',vWantedID);
[mOpen,vIDOpen,dtOpen] = iReadSelectedPanel( ...
    sRawDir,'open_cmc.csv',vWantedID);
[mHigh,vIDHigh,dtHigh] = iReadSelectedPanel( ...
    sRawDir,'high_cmc.csv',vWantedID);
[mLow,vIDLow,dtLow] = iReadSelectedPanel( ...
    sRawDir,'low_cmc.csv',vWantedID);
[mME,vIDME,dtME] = iReadSelectedPanel( ...
    sRawDir,'market_cap_cmc.csv',vWantedID);
[mVolume,vIDVolume,dtVolume] = iReadSelectedPanel( ...
    sRawDir,'volume_cmc.csv',vWantedID);
assert(isequal(vAssetID,vIDOpen,vIDHigh,vIDLow,vIDME,vIDVolume) && ...
    isequal(dtDate,dtOpen,dtHigh,dtLow,dtME,dtVolume), ...
    'Real-data correction validation panels do not share identical keys');

rRawMeta = load(fullfile(sRawDir,'MetaData.mat'),'rMetaData');
[lPresent,vMetaLocation] = ismember(vAssetID,rRawMeta.rMetaData.vID(:)');
assert(all(lPresent),'Correction validation metadata is incomplete');
rMetaData = struct();
rMetaData.vID = vAssetID(:);
rMetaData.cSymbol = rRawMeta.rMetaData.cSymbol(vMetaLocation);

mCloseBefore = mClose;
mOpenBefore = mOpen;
mHighBefore = mHigh;
mLowBefore = mLow;
mMEBefore = mME;
mVolumeBefore = mVolume;
[mOpen,mHigh,mLow,mClose,mME,mVolume,rAudit] = ...
    fApplyV2RawDataCorrections( ...
    mOpen,mHigh,mLow,mClose,mME,mVolume,dtDate,vAssetID,rMetaData);

assert(isequaln(mVolume,mVolumeBefore), ...
    'Production v2 registry changed real volume data');
lMEChanged = iChanged(mMEBefore,mME);
assert(nnz(lMEChanged) == rAudit.iNumMarketCapCells, ...
    'Production v2 registry changed an unexpected real market-cap cell');

lExpectedCloseChange = false(size(mClose));
for iRule = 1:height(rAudit.tPriceScaleRules)
    iColumn = find(vAssetID == rAudit.tPriceScaleRules.AssetID(iRule));
    lRows = dtDate < rAudit.tPriceScaleRules.TransitionDate(iRule) & ...
        isfinite(mCloseBefore(:,iColumn));
    lExpectedCloseChange(lRows,iColumn) = ...
        rAudit.tPriceScaleRules.PriorPriceFactor(iRule) ~= 1;
end
assert(isequal(iChanged(mCloseBefore,mClose),lExpectedCloseChange), ...
    'Production v2 registry changed an unregistered real close cell');

% Every formerly proposed cross-source/extreme target must remain an
% observed CMC price.  The comparison manifest is audit evidence only.
tExternal.RawClose = NaN(height(tExternal),1);
tExternal.CleanedClose = NaN(height(tExternal),1);
for iRule = 1:height(tExternal)
    iColumn = find(vAssetID == double(tExternal.AssetID(iRule)));
    iRow = find(dtDate == datetime(string(tExternal.Date(iRule)), ...
        'InputFormat','yyyy-MM-dd'));
    assert(isscalar(iColumn) && isscalar(iRow), ...
        'Rejected external-disagreement key is not unique');
    tExternal.RawClose(iRule) = mCloseBefore(iRow,iColumn);
    tExternal.CleanedClose(iRule) = mClose(iRow,iColumn);
end
assert(all(isfinite(tExternal.RawClose)) && ...
    isequaln(tExternal.RawClose,tExternal.CleanedClose), ...
    'An extreme/cross-source-disputed CMC close was changed or made missing');

% NPXS and PUNDIX are different CMCIDs and must remain byte-for-byte
% independent raw columns through the unit-continuity layer.
for iAssetID = [2603,9040]
    iColumn = find(vAssetID == iAssetID);
    assert(isequaln(mOpenBefore(:,iColumn),mOpen(:,iColumn)) && ...
        isequaln(mHighBefore(:,iColumn),mHigh(:,iColumn)) && ...
        isequaln(mLowBefore(:,iColumn),mLow(:,iColumn)) && ...
        isequaln(mCloseBefore(:,iColumn),mClose(:,iColumn)) && ...
        isequaln(mMEBefore(:,iColumn),mME(:,iColumn)), ...
        'Different CMCID %d was altered by a cross-series adjustment',iAssetID);
end

tTransition = table();
tTransition.AssetID = rAudit.tPriceScaleRules.AssetID;
tTransition.RuleID = rAudit.tPriceScaleRules.RuleID;
tTransition.TransitionDate = ...
    rAudit.tPriceScaleRules.TransitionDate;
tTransition.RawPriorClose = NaN(height(tTransition),1);
tTransition.CorrectedPriorClose = NaN(height(tTransition),1);
tTransition.RawTransitionClose = NaN(height(tTransition),1);
tTransition.CorrectedTransitionClose = NaN(height(tTransition),1);
tTransition.RawGrossRatio = NaN(height(tTransition),1);
tTransition.CorrectedHolderGrossRatio = NaN(height(tTransition),1);
for iRule = 1:height(tTransition)
    iColumn = find(vAssetID == tTransition.AssetID(iRule));
    iRow = find(dtDate == tTransition.TransitionDate(iRule));
    iPrior = find(isfinite(mCloseBefore(1:iRow-1,iColumn)),1,'last');
    assert(isscalar(iColumn) && isscalar(iRow) && isscalar(iPrior), ...
        'Production transition evidence is incomplete');
    tTransition.RawPriorClose(iRule) = mCloseBefore(iPrior,iColumn);
    tTransition.CorrectedPriorClose(iRule) = mClose(iPrior,iColumn);
    tTransition.RawTransitionClose(iRule) = mCloseBefore(iRow,iColumn);
    tTransition.CorrectedTransitionClose(iRule) = mClose(iRow,iColumn);
    tTransition.RawGrossRatio(iRule) = ...
        mCloseBefore(iRow,iColumn)/mCloseBefore(iPrior,iColumn);
    tTransition.CorrectedHolderGrossRatio(iRule) = ...
        mClose(iRow,iColumn)/mClose(iPrior,iColumn);
end

writetable(tTransition,fullfile(sOutputDir, ...
    'v2_verified_unit_transition_returns.csv'));
writetable(rAudit.tMarketCapRules,fullfile(sOutputDir, ...
    'v2_verified_market_cap_corrections.csv'));
writetable(tExternal,fullfile(sOutputDir, ...
    'v2_verified_extreme_prices_preserved.csv'));
writetable(rAudit.tApplication,fullfile(sOutputDir, ...
    'v2_raw_correction_application_summary.csv'));
save(fullfile(sOutputDir,'v2_real_raw_correction_validation.mat'), ...
    'rAudit','tTransition','tExternal','vAssetID','dtDate','-v7.3');

fprintf(['v2_real_raw_correction_validation assets=%d price_rules=%d ' ...
    'cap_cells=%d missing_price_dates=%d external_dates=%d ' ...
    'external_extreme_prices_preserved=%d ' ...
    'assets_removed=%d\n'],numel(vAssetID), ...
    rAudit.iNumPriceScaleRules,rAudit.iNumMarketCapCells, ...
    rAudit.iNumMissingPriceDates, ...
    rAudit.iNumExternalCorruptPriceDates,height(tExternal), ...
    rAudit.iNumAssetsRemoved);
end

function [mPanel,vSelectedID,dtDate] = ...
    iReadSelectedPanel(sRawDir,sFilename,vWantedID)
sPath = fullfile(sRawDir,sFilename);
mRaw = readmatrix(sPath);
vAllID = mRaw(1,2:end);
[lPresent,vLocation] = ismember(vWantedID(:)',vAllID);
assert(all(lPresent),'Raw panel %s lacks a correction-registry asset',sFilename);
[vLocation,vOrder] = sort(vLocation);
vSelectedID = vWantedID(vOrder)';
mPanel = mRaw(2:end,vLocation+1);
dtDate = iReadDateColumn(sPath,size(mPanel,1));
end

function dtDate = iReadDateColumn(sPath,iNumRows)
iFile = fopen(sPath,'r');
assert(iFile >= 0,'Could not read date key from %s',sPath);
rCleanup = onCleanup(@() fclose(iFile)); %#ok<NASGU>
fgetl(iFile);
cDate = strings(iNumRows,1);
for iRow = 1:iNumRows
    sLine = fgetl(iFile);
    assert(ischar(sLine) && numel(sLine) >= 10, ...
        'Malformed raw date row in %s',sPath);
    cDate(iRow) = string(sLine(1:10));
end
dtDate = datetime(cDate,'InputFormat','yyyy-MM-dd');
end

function lChanged = iChanged(mBefore,mAfter)
lChanged = xor(isnan(mBefore),isnan(mAfter)) | ...
    (isfinite(mBefore) & isfinite(mAfter) & mBefore ~= mAfter);
end
