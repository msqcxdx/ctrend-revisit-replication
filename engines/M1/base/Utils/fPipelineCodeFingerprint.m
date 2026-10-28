function sFingerprint = fPipelineCodeFingerprint(sCodeDir)
% SHA-256 fingerprint of executable MATLAB source in the corrected package.

arguments
    sCodeDir {mustBeTextScalar}
end

sCodeDir = char(java.io.File(char(sCodeDir)).getCanonicalPath());
% Hash only executable pipeline source locations.  Cross-source extreme
% return manifests are audit/sensitivity artifacts and are not consumed by
% production code. Recursive hashing of
% the whole package would accidentally include MATLAB job-storage or log
% files created during a run and make the fingerprint change between steps.
rFiles = [ ...
    dir(fullfile(sCodeDir, '*.m')); ...
    dir(fullfile(sCodeDir, 'Utils', '**', '*.m')); ...
    dir(fullfile(sCodeDir, 'LatexTables', '**', '*.m'))];
rFiles = rFiles(~[rFiles.isdir]);
rFiles = rFiles(~startsWith({rFiles.name}, 'tmp_'));
assert(~isempty(rFiles), 'No MATLAB source files found below %s', sCodeDir);

cFullName = arrayfun(@(x)fullfile(x.folder, x.name), rFiles, ...
    'UniformOutput', false);
[~, vOrder] = sort(cFullName);
cFullName = cFullName(vOrder);

rDigest = java.security.MessageDigest.getInstance('SHA-256');
iChunkBytes = 1024 * 1024;
for iIdxF = 1:numel(cFullName)
    sFilename = cFullName{iIdxF};
    sRelative = erase(sFilename, [sCodeDir, filesep]);
    iUpdateDigest(rDigest, unicode2native(sRelative, 'UTF-8'));
    iUpdateDigest(rDigest, uint8(0));

    iFile = fopen(sFilename, 'rb');
    assert(iFile > 0, 'Could not open %s for fingerprinting', sFilename);
    rCleanup = onCleanup(@() fclose(iFile));
    while true
        vBytes = fread(iFile, iChunkBytes, '*uint8');
        if isempty(vBytes)
            break
        end
        iUpdateDigest(rDigest, vBytes);
    end
    clear rCleanup
    iUpdateDigest(rDigest, uint8(0));
end

vDigestSigned = int8(rDigest.digest());
vDigest = typecast(vDigestSigned(:), 'uint8');
sFingerprint = lower(reshape(dec2hex(vDigest, 2).', 1, []));
end

function iUpdateDigest(rDigest, vBytes)
vBytes = uint8(vBytes(:));
rDigest.update(typecast(vBytes, 'int8'));
end
