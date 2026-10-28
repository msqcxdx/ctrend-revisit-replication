function lUniverse = fValidateUniverseMask(mUniverse,iNumAssets,iNumObs)
% Validate and expand an ex-ante portfolio-universe mask.

arguments
    mUniverse {mustBeNumericOrLogical}
    iNumAssets (1,1) {mustBeInteger,mustBePositive}
    iNumObs (1,1) {mustBeInteger,mustBePositive}
end

if isempty(mUniverse)
    lUniverse = true(iNumAssets,iNumObs);
    return
end
if isnumeric(mUniverse)
    assert(all(isfinite(mUniverse),'all') && ...
        all(mUniverse(:) == 0 | mUniverse(:) == 1), ...
        'Numeric universe masks must contain only finite zero/one values');
end
if isvector(mUniverse) && numel(mUniverse) == iNumAssets
    mUniverse = repmat(mUniverse(:),1,iNumObs);
end
assert(isequal(size(mUniverse),[iNumAssets,iNumObs]), ...
    'Universe mask must be N x T or N x 1');
lUniverse = logical(mUniverse);
end
