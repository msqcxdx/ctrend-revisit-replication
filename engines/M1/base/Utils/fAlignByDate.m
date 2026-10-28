function [mAligned, rCoverage] = fAlignByDate(vSourceDates, mSource, vTargetDates, sName, dMinCoverage)
% Align rows of mSource to vTargetDates using exact date keys.

arguments
    vSourceDates (:,1) {mustBeNumeric}
    mSource (:,:) {mustBeNumeric}
    vTargetDates (:,1) {mustBeNumeric}
    sName char = 'source'
    dMinCoverage (1,1) {mustBeNumeric, mustBeNonnegative} = 0
end

assert(size(mSource,1) == length(vSourceDates), 'Source rows and dates must agree');
assert(dMinCoverage <= 1, 'Minimum coverage must be in [0,1]');
assert(all(isfinite(vSourceDates)) && numel(unique(vSourceDates)) == numel(vSourceDates), ...
    '%s dates must be finite and unique', sName);
assert(all(isfinite(vTargetDates)) && numel(unique(vTargetDates)) == numel(vTargetDates), ...
    'Target dates must be finite and unique');

mAligned = NaN(length(vTargetDates), size(mSource,2));
[lFound, vIdx] = ismember(vTargetDates, vSourceDates);
mAligned(lFound,:) = mSource(vIdx(lFound),:);

rCoverage = struct();
rCoverage.sName = sName;
rCoverage.iTargetDates = length(vTargetDates);
rCoverage.iMatchedDates = sum(lFound);
rCoverage.dDateCoverage = mean(lFound);
rCoverage.dNonmissingRowCoverage = mean(any(isfinite(mAligned), 2));

if rCoverage.dDateCoverage < dMinCoverage
    error('%s date coverage %.2f%% is below required %.2f%% (%i/%i matched dates)', ...
        sName, 100 * rCoverage.dDateCoverage, 100 * dMinCoverage, ...
        rCoverage.iMatchedDates, rCoverage.iTargetDates);
end
end
