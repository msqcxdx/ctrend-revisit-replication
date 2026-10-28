function sPayloadSHA256 = fAssertB09PayloadDigest( ...
        sFilename,iSetting,sExpectedSHA256)
% Verify a b09 combo's whole-file SHA-256 sidecar and optional manifest hash.

arguments
    sFilename {mustBeTextScalar}
    iSetting (1,1) {mustBeInteger,mustBePositive}
    sExpectedSHA256 {mustBeTextScalar} = ''
end

sFilename = char(sFilename);
sExpectedSHA256 = char(sExpectedSHA256);
sDigestFilename = [sFilename,'.sha256'];
assert(isfile(sFilename) && isfile(sDigestFilename), ...
    'Combo %d MAT or payload digest is missing',iSetting);
sDigestText = strtrim(fileread(sDigestFilename));
cToken = regexp(sDigestText, ...
    '^([0-9a-f]{64})  CTREND_Combo([1-9][0-9]*)\.mat$', ...
    'tokens','once');
assert(~isempty(cToken) && str2double(cToken{2}) == iSetting, ...
    'Combo %d payload digest sidecar is malformed',iSetting);
sPayloadSHA256 = fFileSHA256(sFilename);
assert(strcmp(sPayloadSHA256,cToken{1}), ...
    'Combo %d MAT payload digest mismatch',iSetting);
if ~isempty(sExpectedSHA256)
    assert(~isempty(regexp(sExpectedSHA256,'^[0-9a-f]{64}$','once')) && ...
        strcmp(sPayloadSHA256,sExpectedSHA256), ...
        'Combo %d payload digest disagrees with its manifest',iSetting);
end
end
