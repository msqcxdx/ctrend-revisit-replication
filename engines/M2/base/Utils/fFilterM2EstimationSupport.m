function [vY,mX,mID,vW] = fFilterM2EstimationSupport(vY,mX,mID,vW)
% Restrict an already-historical train/validation slice to observations on
% which the published M0 estimator is defined.  This helper is deliberately
% called only after calendar train/validation dates have been fixed; it is
% never used to construct the OOS prediction or portfolio universe.

arguments
    vY (:,1) {mustBeNumeric}
    mX (:,:) {mustBeNumeric}
    mID (:,2) {mustBeNumeric}
    vW (:,1) {mustBeNumeric} = []
end

assert(size(mX,1) == numel(vY) && size(mID,1) == numel(vY), ...
    'Historical estimation arrays must have the same row count');
if isempty(vW)
    lKeep = ~isnan(vY) & all(~isnan(mX),2) & ...
        all(~isnan(mID),2);
else
    assert(numel(vW) == numel(vY), ...
        'Historical estimation weights must match labels');
    lKeep = ~isnan(vY) & all(~isnan(mX),2) & ...
        all(~isnan(mID),2) & ~isnan(vW);
end

vY = vY(lKeep);
mX = mX(lKeep,:);
mID = mID(lKeep,:);
if ~isempty(vW)
    vW = vW(lKeep);
end
end
