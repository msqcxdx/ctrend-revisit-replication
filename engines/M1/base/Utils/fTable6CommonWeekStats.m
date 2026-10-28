function rStats = fTable6CommonWeekStats(mReturns)
% Exact own-, pairwise-, and all-method common-week Sharpe statistics.
%
% No missing return is imputed.  Pair (j,k) is evaluated only on weeks for
% which both methods are finite.  The all-method comparison uses the strict
% intersection of every method's finite weeks within one design cell.

arguments
    mReturns (:,:) {mustBeNumeric}
end
assert(size(mReturns,2) >= 2, ...
    'Common-week comparison requires at least two methods');

iNumMethods = size(mReturns,2);
lFinite = isfinite(mReturns);
rStats = struct();
[rStats.vOwnSharpe,~] = fSharpeRatio(mReturns,0,1,2);
rStats.vOwnSharpe = reshape(rStats.vOwnSharpe,1,[]);
rStats.vOwnN = sum(lFinite,1);
rStats.vOwnFirstIndex = NaN(1,iNumMethods);
rStats.vOwnLastIndex = NaN(1,iNumMethods);
for iIdxM = 1:iNumMethods
    rStats.vOwnFirstIndex(iIdxM) = ...
        iFirstOrNaN(find(lFinite(:,iIdxM),1,'first'));
    rStats.vOwnLastIndex(iIdxM) = ...
        iFirstOrNaN(find(lFinite(:,iIdxM),1,'last'));
end

lAllCommon = all(lFinite,2);
rStats.iAllCommonN = nnz(lAllCommon);
lAllUnion = any(lFinite,2);
rStats.iAllUnionN = nnz(lAllUnion);
if rStats.iAllUnionN > 0
    rStats.dAllCommonOverlap = ...
        rStats.iAllCommonN/rStats.iAllUnionN;
else
    rStats.dAllCommonOverlap = NaN;
end
rStats.iAllCommonFirstIndex = ...
    iFirstOrNaN(find(lAllCommon,1,'first'));
rStats.iAllCommonLastIndex = ...
    iFirstOrNaN(find(lAllCommon,1,'last'));
rStats.vAllCommonSharpe = NaN(1,iNumMethods);
if any(lAllCommon)
    rStats.vAllCommonSharpe = reshape( ...
        fSharpeRatio(mReturns(lAllCommon,:),0,1,2),1,[]);
end

rStats.mPairCommonN = NaN(iNumMethods,iNumMethods);
rStats.mPairUnionN = NaN(iNumMethods,iNumMethods);
rStats.mPairJaccard = NaN(iNumMethods,iNumMethods);
% Entry (j,k) is method j's Sharpe on pair (j,k)'s common weeks.
rStats.mPairSharpe = NaN(iNumMethods,iNumMethods);
for iIdxJ = 1:iNumMethods
    for iIdxK = 1:iNumMethods
        lPairCommon = lFinite(:,iIdxJ) & lFinite(:,iIdxK);
        lPairUnion = lFinite(:,iIdxJ) | lFinite(:,iIdxK);
        rStats.mPairCommonN(iIdxJ,iIdxK) = nnz(lPairCommon);
        rStats.mPairUnionN(iIdxJ,iIdxK) = nnz(lPairUnion);
        if any(lPairUnion)
            rStats.mPairJaccard(iIdxJ,iIdxK) = ...
                nnz(lPairCommon)/nnz(lPairUnion);
        end
        if any(lPairCommon)
            rStats.mPairSharpe(iIdxJ,iIdxK) = ...
                fSharpeRatio(mReturns(lPairCommon,iIdxJ),0,1,2);
        end
    end
end
end

function dValue = iFirstOrNaN(dValue)
if isempty(dValue)
    dValue = NaN;
end
end
