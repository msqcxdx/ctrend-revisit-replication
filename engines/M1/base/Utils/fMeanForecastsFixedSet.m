function vCombined = fMeanForecastsFixedSet(mForecasts)
% Equal-weight a prespecified set of component forecasts using fixed 1/J.
%
% The set is represented by the columns supplied by the caller.  If any
% required component is unavailable for an observation, the combined
% forecast is undefined for that observation.  Missing components are not
% silently dropped because doing so would replace the stated 1/J estimator
% with a time/asset-varying 1/J_t estimator.

arguments
    mForecasts (:,:) {mustBeNumeric}
end

iNumObs = size(mForecasts,1);
iNumForecasts = size(mForecasts,2);
vCombined = NaN(iNumObs,1);
if iNumForecasts == 0
    return
end

lComplete = all(isfinite(mForecasts),2);
vCombined(lComplete) = ...
    sum(mForecasts(lComplete,:),2) ./ iNumForecasts;
vCombined(~isfinite(vCombined)) = NaN;
end
