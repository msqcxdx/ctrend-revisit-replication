function vPnlRawOOS = fBuildRawOOSPanelOutcome(vEvaluationY, mID, ...
        vAllTimeID, iNumIn)
% Put raw realized panel outcomes on the scheduled OOS calendar only.
%
% Predictions formed after an iNumIn-week training window start in calendar
% week iNumIn+1.  This helper deliberately has no outlier arguments: label
% preprocessing must not alter economic P&L.

arguments
    vEvaluationY (:,1) {mustBeNumeric}
    mID (:,2) {mustBeNumeric, mustBeNonnegative}
    vAllTimeID (:,1) {mustBeNumeric, mustBeNonnegative}
    iNumIn (1,1) {mustBeNumeric, mustBeNonnegative, mustBeInteger}
end

assert(numel(vEvaluationY) == size(mID,1), ...
    'Evaluation outcomes and panel IDs must have equal length');
assert(numel(unique(vAllTimeID)) == numel(vAllTimeID) && ...
    all(diff(vAllTimeID) > 0), ...
    'The complete time axis must be unique and strictly increasing');
assert(all(ismember(mID(:,1), vAllTimeID)), ...
    'Every panel time ID must occur on the complete time axis');

vPnlRawOOS = NaN(size(vEvaluationY));
if iNumIn >= numel(vAllTimeID)
    return
end
vOOSTimeID = vAllTimeID(iNumIn+1:end);
lOOS = ismember(mID(:,1), vOOSTimeID);
vPnlRawOOS(lOOS) = vEvaluationY(lOOS);
end
