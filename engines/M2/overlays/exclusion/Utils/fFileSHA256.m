function sHash = fFileSHA256(sFilename)
% Streaming SHA-256 content digest for a file.

arguments
    sFilename {mustBeTextScalar}
end
sFilename = char(sFilename);
assert(isfile(sFilename),'Cannot hash missing file: %s',sFilename);

rDigest = java.security.MessageDigest.getInstance('SHA-256');
iFile = fopen(sFilename,'rb');
assert(iFile > 0,'Could not open file for hashing: %s',sFilename);
rCleanup = onCleanup(@() fclose(iFile));
while true
    vBytes = fread(iFile,1024*1024,'*uint8');
    if isempty(vBytes)
        break
    end
    rDigest.update(typecast(vBytes(:),'int8'));
end
clear rCleanup
vDigest = typecast(int8(rDigest.digest()),'uint8');
sHash = lower(reshape(dec2hex(vDigest,2).',1,[]));
end
