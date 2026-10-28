function mDemeaned = fDemeanWeeklyM2(mReturns)
% Cross-sectional demeaning with explicit all-missing-week behavior.
arguments
    mReturns (:,:) {mustBeNumeric}
end
vMean = mean(mReturns,2,'omitmissing');
vMean(all(isnan(mReturns),2)) = NaN;
mDemeaned = mReturns-vMean;
end
