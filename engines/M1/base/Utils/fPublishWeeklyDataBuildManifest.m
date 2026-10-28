function rManifest = fPublishWeeklyDataBuildManifest(sDataPath, ...
        vDataSettings, sDataBuildID, sWeeklyCodeFingerprint, ...
        rInputProvenance, iNumWeeks, iNumAssets)
% Atomically certify the weekly-data bundle only after every file exists.

arguments
    sDataPath {mustBeTextScalar}
    vDataSettings (:,1) {mustBeNumeric, mustBeInteger, mustBePositive}
    sDataBuildID {mustBeTextScalar}
    sWeeklyCodeFingerprint {mustBeTextScalar}
    rInputProvenance (1,1) struct
    iNumWeeks (1,1) {mustBeInteger, mustBePositive}
    iNumAssets (1,1) {mustBeInteger, mustBePositive}
end

sDataPath = char(sDataPath);
vDataSettings = unique(vDataSettings(:),'stable');
cFiles = arrayfun(@(x)sprintf('bCharacteristicsOLHC_Combo%d.mat',x), ...
    vDataSettings,'UniformOutput',false);
cSHA256 = cell(size(cFiles));
vBytes = NaN(size(cFiles));
for iIdxF = 1:numel(cFiles)
    sFile = fullfile(sDataPath,cFiles{iIdxF});
    rInfo = dir(sFile);
    assert(isscalar(rInfo) && rInfo.bytes > 0, ...
        'Weekly bundle member is missing or empty: %s',sFile);
    vBytes(iIdxF) = rInfo.bytes;
    cSHA256{iIdxF} = fFileSHA256(sFile);
    rLoaded = load(sFile,'sDataBuildID','sWeeklyCodeFingerprint');
    assert(isfield(rLoaded,'sDataBuildID') && ...
           isfield(rLoaded,'sWeeklyCodeFingerprint') && ...
           strcmp(char(rLoaded.sDataBuildID),char(sDataBuildID)) && ...
           strcmp(char(rLoaded.sWeeklyCodeFingerprint), ...
                  char(sWeeklyCodeFingerprint)), ...
        'Weekly bundle member has mixed build provenance: %s',sFile);
end

rManifest = struct();
rManifest.lComplete = true;
rManifest.sDataBuildID = char(sDataBuildID);
rManifest.sWeeklyCodeFingerprint = char(sWeeklyCodeFingerprint);
rManifest.sInputManifestSHA256 = ...
    char(rInputProvenance.sManifestSHA256);
rManifest.vDataSettings = vDataSettings;
rManifest.cFiles = cFiles;
rManifest.cSHA256 = cSHA256;
rManifest.vBytes = vBytes;
rManifest.iNumWeeks = iNumWeeks;
rManifest.iNumAssets = iNumAssets;
rManifest.sCreatedAt = char(datetime('now', ...
    'Format','yyyy-MM-dd''T''HH:mm:ss'));

sManifestFile = fullfile(sDataPath,'WeeklyDataBuildManifest.mat');
sTemporary = [tempname(sDataPath),'.mat'];
rCleanup = onCleanup(@() iDeleteIfExists(sTemporary));
save(sTemporary,'rManifest');
[lMoved,sMessage] = movefile(sTemporary,sManifestFile,'f');
assert(lMoved,'Could not publish weekly-data manifest: %s',sMessage);
clear rCleanup
end

function iDeleteIfExists(sFilename)
if exist(sFilename,'file') == 2
    delete(sFilename);
end
end
