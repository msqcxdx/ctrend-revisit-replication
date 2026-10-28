function [mRanks,mObserved] = ...
        fRankPredictorsOwnSupport(mRawPredictors,mFormationEligible)
% Rank each predictor on its own formation-time observable cross-section.
%
% Missingness in predictor k must not alter predictor j's percentile rank.
% The common formation mask contains only information known before the
% payoff period (for example, lagged market value, price, and stablecoin
% eligibility).  Model-specific complete cases are selected after this
% transform, never before it.

arguments
    mRawPredictors (:,:,:) {mustBeNumeric}
    mFormationEligible (:,:) {mustBeNumericOrLogical}
end

[iNumAssets,iNumTimes,iNumPredictors] = size(mRawPredictors);
assert(isequal(size(mFormationEligible),[iNumAssets,iNumTimes]), ...
    'Formation eligibility must be asset by time');
assert(all(isfinite(double(mFormationEligible)),'all') && ...
       all(ismember(double(mFormationEligible(:)),[0,1])), ...
    'Formation eligibility must contain only true/false values');

mFormationEligible = logical(mFormationEligible);
mMasked = mRawPredictors;
for iIdxPredictor = 1:iNumPredictors
    mPredictor = mMasked(:,:,iIdxPredictor);
    mPredictor(~mFormationEligible) = NaN;
    mMasked(:,:,iIdxPredictor) = mPredictor;
end
mObserved = isfinite(mMasked);
mRanks = permute(fCrossSectTransChars( ...
    permute(mMasked,[1,3,2]),'rank'),[1,3,2]);

assert(isequal(isfinite(mRanks),mObserved), ...
    'Rank transformation changed predictor-specific observed support');
vFinite = mRanks(isfinite(mRanks));
assert(isempty(vFinite) || ...
    (min(vFinite) >= -0.5-10*eps && max(vFinite) <= 0.5+10*eps), ...
    'Predictor ranks left the paper scale [-0.5,0.5]');
end
