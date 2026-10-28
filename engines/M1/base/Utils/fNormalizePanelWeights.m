function vW = fNormalizePanelWeights(vW, mID)
% Normalize available panel weights to one separately within each date.
%
% Call this only after applying the current window's Y/X availability
% mask. This prevents a date with missing or truncated labels from having
% less total influence merely because its surviving weights sum to less
% than one.

if isempty(vW)
    return
end
assert(isvector(vW) && size(vW,1) == size(mID,1), ...
    'Weights and panel IDs must have equal length');
assert(all(isfinite(vW) & vW >= 0), ...
    'Weights must be finite and nonnegative after the availability filter');

vTime = unique(mID(:,1));
for iIdxT = 1:numel(vTime)
    lThisTime = mID(:,1) == vTime(iIdxT);
    dSum = sum(vW(lThisTime));
    assert(dSum > 0, 'Available weights must have positive mass per time ID');
    vW(lThisTime) = vW(lThisTime) ./ dSum;
end
end
