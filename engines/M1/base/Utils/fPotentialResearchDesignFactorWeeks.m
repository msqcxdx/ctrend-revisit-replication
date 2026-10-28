function lPotential = fPotentialResearchDesignFactorWeeks( ...
        mExpectedPrediction,vPercentile,iMinNumCS,iMinNumAssets,lScheduled)
% Output-independent minimum support needed to form both hedge legs.

arguments
    mExpectedPrediction (:,:) {mustBeNumericOrLogical}
    vPercentile (1,:) {mustBeNumeric,mustBeNonnegative}
    iMinNumCS (1,1) {mustBeInteger,mustBeNonnegative}
    iMinNumAssets (1,1) {mustBeInteger,mustBeNonnegative}
    lScheduled (:,1) {mustBeNumericOrLogical}
end

assert(size(mExpectedPrediction,2) == numel(lScheduled), ...
    'Expected prediction support and schedule must share the weekly axis');
assert(numel(vPercentile) >= 3 && vPercentile(1) == 0 && ...
    vPercentile(end) == 1 && all(diff(vPercentile) > 0), ...
    'Percentile breakpoints must increase strictly from zero to one');

vExpectedN = sum(logical(mExpectedPrediction),1)';
dLowShare = vPercentile(2)-vPercentile(1);
dHighShare = vPercentile(end)-vPercentile(end-1);
vMinLowN = floor(dLowShare*vExpectedN + 10*eps);
vMinHighN = floor(dHighShare*vExpectedN + 10*eps);
lPotential = logical(lScheduled(:)) & ...
    vExpectedN >= iMinNumCS & ...
    vMinLowN >= iMinNumAssets & vMinHighN >= iMinNumAssets;
end
