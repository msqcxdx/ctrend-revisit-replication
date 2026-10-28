function fAssertRawInputProvenance(sDataPath,rInputProvenance)
% Re-hash the current raw inputs before consuming a saved b01 build.

arguments
    sDataPath {mustBeTextScalar}
    rInputProvenance struct
end
cRequired = {'cRawInputName','cRawInputSHA256','vRawInputBytes', ...
    'sRawInputsSHA256'};
assert(all(isfield(rInputProvenance,cRequired)), ...
    ['Input certificate predates raw content hashes. Rerun b01ReadData ' ...
     'from the current raw files.']);
cNames = rInputProvenance.cRawInputName(:);
cHashes = rInputProvenance.cRawInputSHA256(:);
vBytes = rInputProvenance.vRawInputBytes(:);
assert(numel(cNames) == numel(cHashes) && numel(cNames) == numel(vBytes), ...
    'Raw-input provenance arrays have inconsistent lengths');

cCurrentHashes = cell(size(cNames));
for iIdxF = 1:numel(cNames)
    sFilename = fullfile(char(sDataPath),char(cNames{iIdxF}));
    rInfo = dir(sFilename);
    assert(numel(rInfo) == 1 && ~rInfo.isdir && ...
        rInfo.bytes == vBytes(iIdxF), ...
        'Raw input size changed after b01: %s',sFilename);
    cCurrentHashes{iIdxF} = fFileSHA256(sFilename);
    assert(strcmp(cCurrentHashes{iIdxF},char(cHashes{iIdxF})), ...
        'Raw input content changed after b01: %s',sFilename);
end
sAggregate = iAggregate(cNames,cCurrentHashes,vBytes);
assert(strcmp(sAggregate,rInputProvenance.sRawInputsSHA256), ...
    'Aggregate raw-input fingerprint changed after b01');
end

function sHash = iAggregate(cNames,cHashes,vBytes)
rDigest = java.security.MessageDigest.getInstance('SHA-256');
for iIdxF = 1:numel(cNames)
    iUpdate(rDigest,unicode2native(char(cNames{iIdxF}),'UTF-8'));
    iUpdate(rDigest,uint8(0));
    iUpdate(rDigest,unicode2native(char(cHashes{iIdxF}),'UTF-8'));
    iUpdate(rDigest,uint8(0));
    iUpdate(rDigest,unicode2native(sprintf('%.0f',vBytes(iIdxF)),'UTF-8'));
    iUpdate(rDigest,uint8(0));
end
vDigest = typecast(int8(rDigest.digest()),'uint8');
sHash = lower(reshape(dec2hex(vDigest,2).',1,[]));
end

function iUpdate(rDigest,vBytes)
rDigest.update(typecast(uint8(vBytes(:)),'int8'));
end
