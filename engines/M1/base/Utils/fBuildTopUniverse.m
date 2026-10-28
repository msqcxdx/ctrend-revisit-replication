function mUniverse = fBuildTopUniverse(mScore, dKeep, mFormationEligible)
% Build an ex-ante top-score universe for each time period.
%
% mScore is N x T. Missing scores are never included. If dKeep is an
% integer, keep exactly the top K available assets. If dKeep is a fraction
% in (0,1), keep exactly ceil(dKeep*N) assets. Score ties are broken by the
% stable asset row/ID order, so the result is deterministic.

arguments
    mScore (:,:) {mustBeNumeric}
    dKeep (1,1) {mustBeNumeric, mustBePositive}
    mFormationEligible (:,:) {mustBeNumericOrLogical} = ...
        true(size(mScore))
end

[iNumAssets, iNumObs] = size(mScore);
assert(isequal(size(mFormationEligible),size(mScore)) && ...
    all(isfinite(double(mFormationEligible)),'all'), ...
    'Formation eligibility must be a complete score-shaped mask');
mScore(~logical(mFormationEligible)) = NaN;
mUniverse = false(iNumAssets, iNumObs);

lIntegerKeep = dKeep == floor(dKeep);
if lIntegerKeep && dKeep < 2
    error('Top-K dKeep must be an integer >= 2. Use an explicit true universe for 100%%.');
elseif ~lIntegerKeep && dKeep >= 1
    error('Fractional dKeep must be in (0,1).');
end

for iIdxT = 1:iNumObs
    vScore = mScore(:, iIdxT);
    lAvail = isfinite(vScore);
    iNumAvail = sum(lAvail);
    if iNumAvail == 0
        continue
    end

    if lIntegerKeep
        iNumKeep = min(dKeep, iNumAvail);
    else
        iNumKeep = min(iNumAvail, max(1, ceil(dKeep*iNumAvail)));
    end
    vIdxAvail = find(lAvail);
    mOrderKey = [-vScore(vIdxAvail), vIdxAvail];
    [~,vOrder] = sortrows(mOrderKey,[1 2]);
    vKeep = vIdxAvail(vOrder(1:iNumKeep));
    mUniverse(vKeep,iIdxT) = true;
end
end
