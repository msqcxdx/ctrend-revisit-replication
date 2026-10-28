function [mX,vY,mIdx,vZ] = fCreatePanelExAnteM2(mX,mY,mZ)
% Stack the published joint-complete predictor panel without conditioning
% its rows on the holding-period outcome.  M2 deliberately retains M0's
% intersection of all predictors; it changes only the future-Y filter.

arguments
    mX (:,:,:) {mustBeNumeric}
    mY (:,:) {mustBeNumeric}
    mZ (:,:) {mustBeNumeric} = []
end

[iNumAssets,iNumObs,iNumVars] = size(mX);
assert(isequal(size(mY),[iNumAssets,iNumObs]), ...
    'Dependent-variable dimensions must agree with predictors');
if ~isempty(mZ)
    assert(isequal(size(mZ),[iNumAssets,iNumObs]), ...
        'Weight dimensions must agree with predictors');
end

mAsset = repmat((1:iNumAssets)',1,iNumObs);
mTime = repmat(1:iNumObs,iNumAssets,1);
mIdx = [reshape(mTime,[],1),reshape(mAsset,[],1)];
vY = reshape(mY,[],1);
mX = reshape(mX,[],iNumVars);

% This is the only support change relative to fCreatePanelFast: Y is not a
% formation-time variable and therefore cannot decide whether a prediction
% row exists.  Every M0 predictor must still be finite.
lRemove = any(isnan(mX),2);
if ~isempty(mZ)
    vZ = reshape(mZ,[],1);
    lRemove = lRemove | isnan(vZ);
else
    vZ = [];
end

mX(lRemove,:) = [];
vY(lRemove) = [];
mIdx(lRemove,:) = [];
if ~isempty(vZ)
    vZ(lRemove) = [];
end
end
